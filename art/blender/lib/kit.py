"""Shared helpers for building low-poly models in Blender from code.

Run model scripts with tools/blender.sh, never by opening Blender. See art/README.md for the
conventions (units, facing, origin) every model follows.

A model script looks like:

    import sys, pathlib
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "lib"))
    import kit

    kit.reset()
    robe = kit.material("robe", (0.25, 0.05, 0.05))
    body = kit.cone("body", radius=0.35, top_radius=0.2, depth=1.1, location=(0, 0, 0.55), mat=robe, bone="spine")
    ...
    rig = kit.armature("cultist", [("spine", (0, 0, 0.1), (0, 0, 1.2), None), ...])
    model = kit.bind(rig, [body, ...], "cultist")
    kit.animate(rig, "idle", {0: {"spine": (0, 0, 0)}, 30: {"spine": (4, 0, 0)}, 60: {"spine": (0, 0, 0)}})
    kit.export(model_name="cultist", kind="characters")
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

GAME_DIR = Path(__file__).resolve().parents[3]
ASSETS_DIR = GAME_DIR / "assets" / "models"
PREVIEWS_DIR = GAME_DIR / "art" / "previews"

# Preview cameras as (pitch down, yaw) in degrees. "iso" is the isometric game view (30 down, 45 around).
VIEWS = {
    "iso": (30.0, 45.0),
    "front": (10.0, 0.0),
    "side": (10.0, 90.0),
}
FPS = 30


def script_args():
    """Arguments passed after the script name in tools/blender.sh."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def reset():
    """Starts from an empty scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def material(name, color, roughness=0.9, emission=None):
    """A flat Principled material. `color` is (r, g, b) in 0..1. `emission` makes it glow."""
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    mat.diffuse_color = (*color, 1.0)  # what the workbench previews show
    return mat


def _object_from_bmesh(name, bm, location, rotation, mat, bone):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = Euler([math.radians(a) for a in rotation])
    if mat:
        mesh.materials.append(mat)
    if bone:
        obj.vertex_groups.new(name=bone).add(range(len(mesh.vertices)), 1.0, "REPLACE")
    return obj


def box(name, size, location=(0, 0, 0), rotation=(0, 0, 0), mat=None, bone=None):
    """A box of `size` (x, y, z) centred on `location`. `bone` rigidly attaches it for bind()."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return _object_from_bmesh(name, bm, location, rotation, mat, bone)


def cone(name, radius, depth, top_radius=0.0, segments=6, location=(0, 0, 0), rotation=(0, 0, 0), mat=None, bone=None):
    """A low-poly cone or cylinder (top_radius == radius) standing along Z, centred on `location`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=top_radius, depth=depth)
    return _object_from_bmesh(name, bm, location, rotation, mat, bone)


def ball(name, radius, subdivisions=1, location=(0, 0, 0), rotation=(0, 0, 0), scale=(1, 1, 1), mat=None, bone=None):
    """A low-poly icosphere, optionally squashed by `scale`."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    return _object_from_bmesh(name, bm, location, rotation, mat, bone)


def armature(name, bones):
    """An armature from (bone, head, tail, parent) tuples. Parents must come before children."""
    data = bpy.data.armatures.new(name + "_rig")
    rig = bpy.data.objects.new(name + "_rig", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, head, tail, parent in bones:
        eb = data.edit_bones.new(bone)
        eb.head, eb.tail = Vector(head), Vector(tail)
        if parent:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
    return rig


def bind(rig, parts, name):
    """Joins the parts into one mesh named `name`, skinned rigidly to `rig` by each part's bone."""
    for part in parts:  # bake each part's transform so joining keeps it in place
        part.data.transform(part.matrix_world)
        part.matrix_world = Matrix.Identity(4)
    with bpy.context.temp_override(active_object=parts[0], selected_editable_objects=parts):
        bpy.ops.object.join()
    model = parts[0]
    model.name = model.data.name = name
    model.parent = rig
    model.modifiers.new("Armature", "ARMATURE").object = rig
    return model


def animate(rig, name, keys, loop=True):
    """Adds an animation clip. `keys` maps frame -> {bone: (x, y, z) rotation in degrees}.

    Frames are at 30 fps. Bones left out of a key keep their rest pose in that key.
    Looping clips get Godot's "-loop" import suffix, so they arrive in Godot as `name`, looping.
    """
    name = name + "-loop" if loop else name
    rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame, pose in sorted(keys.items()):
        for pb in rig.pose.bones:
            pb.rotation_euler = Euler([math.radians(a) for a in pose.get(pb.name, (0, 0, 0))])
            pb.keyframe_insert("rotation_euler", frame=frame)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(min(keys)), action)
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_euler = Euler((0, 0, 0))
    return action


def _bounds():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector([min(c[i] for c in corners) for i in range(3)])
    hi = Vector([max(c[i] for c in corners) for i in range(3)])
    return lo, hi


def render_previews(model_name, views=VIEWS, size=512):
    """Renders flat-lit PNGs of the scene to art/previews/<model>_<view>.png for review."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"

    lo, hi = _bounds()
    center = (lo + hi) / 2
    extent = max(hi - lo)
    cam = bpy.data.objects.new("preview_cam", bpy.data.cameras.new("preview_cam"))
    scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = extent * 1.4
    scene.camera = cam

    PREVIEWS_DIR.mkdir(parents=True, exist_ok=True)
    paths = []
    for view, (pitch, yaw) in views.items():
        rot = Euler((math.radians(90 - pitch), 0, math.radians(yaw)))
        cam.rotation_euler = rot
        cam.location = center + rot.to_matrix() @ Vector((0, 0, extent * 4))
        path = PREVIEWS_DIR / f"{model_name}_{view}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    bpy.data.objects.remove(cam)
    return paths


def export(model_name, kind, previews=True):
    """Writes assets/models/<kind>/<model>.glb, and preview renders unless `previews` is False."""
    out = ASSETS_DIR / kind / f"{model_name}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
    )
    print(f"KIT: exported {out}")
    if previews:
        for path in render_previews(model_name):
            print(f"KIT: preview {path}")
    return out
