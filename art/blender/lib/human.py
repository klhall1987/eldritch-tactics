"""The player character's body, built with MPFB (the MakeHuman plugin for Blender): shared by the
character script and the clothes script, so every clothing piece is fitted to exactly the same body,
skeleton and rest pose as the character.

MPFB must be installed in Blender (the extension `bl_ext.user_default.mpfb`); it brings the
MakeHuman base mesh, shape targets and skeletons. The MakeHuman assets fitted to the body are
committed under art/base/makehuman (see art/base/README.md).
"""

import pathlib

import addon_utils
import bpy
import numpy as np
from mathutils import Matrix, Vector

MPFB = "bl_ext.user_default.mpfb"
MAKEHUMAN = pathlib.Path(__file__).resolve().parents[2] / "base" / "makehuman"


def start():
    """Enables MPFB and empties the scene. tools/blender.sh starts Blender with --factory-startup,
    which leaves user add-ons off; MPFB reads its own preferences while registering, so it has to be
    enabled as a (session-only) preference."""
    addon_utils.enable(MPFB, default_set=True)
    if not addon_utils.check(MPFB)[1]:
        raise SystemExit("MPFB isn't installed in this Blender: install the MPFB extension "
                         "(https://extensions.blender.org/add-ons/mpfb/) and try again.")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)


def create():
    """The body from MPFB's sliders (a slim man of about 32, about 1.86 m to the top of his hair) on
    MPFB's game-engine skeleton. Returns (basemesh, rig)."""
    from bl_ext.user_default.mpfb.services import HumanService, TargetService
    macro = TargetService.get_default_macro_info_dict()
    macro.update({"gender": 1.0, "age": 0.55, "muscle": 0.5, "weight": 0.38, "height": 0.6, "proportions": 0.5})
    macro["race"] = {"caucasian": 1.0, "asian": 0.0, "african": 0.0}
    basemesh = HumanService.create_human(macro_detail_dict=macro)
    rig = HumanService.add_builtin_rig(basemesh, "game_engine")
    rig.name = rig.data.name = "character"
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return basemesh, rig


def asset(basemesh, path, kind):
    """Fits a MakeHuman asset (a path under art/base/makehuman) to the body, skinned to the rig."""
    from bl_ext.user_default.mpfb.services import HumanService
    return HumanService.add_mhclo_asset(str(MAKEHUMAN / path), basemesh, asset_type=kind, subdiv_levels=0)


def body(basemesh):
    """His low-poly body (the male1591 proxy), named `body`."""
    obj = asset(basemesh, "proxymeshes/male1591/male1591.proxy", "Proxymeshes")
    obj.name = obj.data.name = "body"
    return obj


def aim(rig, bone, direction):
    """Turns `bone` about its head so it points along `direction` (world: +X his left, -Y ahead, +Z up)."""
    bpy.context.view_layer.update()
    pb = rig.pose.bones[bone]
    head = pb.matrix.translation.copy()
    turn = (pb.tail - pb.head).normalized().rotation_difference(Vector(direction).normalized())
    pb.matrix = Matrix.Translation(head) @ turn.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()


def arms_down(rig, meshes):
    """MPFB's rest pose holds the arms out and forward. This re-poses him standing with his arms
    hanging just clear of his sides and makes that the rest pose: the pose is baked into `meshes`,
    the skeleton's rest is set to it, and the meshes are skinned to it again with the same weights."""
    for side in (1, -1):
        s = "l" if side > 0 else "r"
        aim(rig, f"upperarm_{s}", (0.13 * side, 0.02, -1.0))  # hanging, a hand's width out from his side
        aim(rig, f"lowerarm_{s}", (0.06 * side, -0.14, -1.0))  # elbow a little bent, forearm slightly forward
    for obj in meshes:
        with bpy.context.temp_override(object=obj, active_object=obj):
            for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
                bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in meshes:
        obj.modifiers.new("Armature", "ARMATURE").object = rig


# --- Materials -----------------------------------------------------------------------------------------

def load(path):
    """An image from art/base/makehuman."""
    return bpy.data.images.load(str(MAKEHUMAN / path), check_existing=True)


def _pixels(image):
    w, h = image.size
    return np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)


def _packed(name, pixels):
    h, w = pixels.shape[:2]
    copy = bpy.data.images.new(name, w, h, alpha=True)
    copy.pixels.foreach_set(pixels.ravel())
    copy.pack()
    return copy


def darkened(image, brightness):
    """A copy of `image` scaled so its opaque pixels average `brightness` (their brightest channel)."""
    pixels = _pixels(image)
    opaque = pixels[..., 3] > 0.5
    pixels[..., :3] *= brightness / pixels[..., :3][opaque].max(axis=-1).mean()
    return _packed(image.name.rsplit(".", 1)[0] + "_dark", pixels)


def recoloured(image, colour, name):
    """A copy of `image` dyed `colour` (sRGB 0..1): its shading kept as light and dark, its hue
    replaced, scaled so its opaque pixels average `colour`."""
    pixels = _pixels(image)
    opaque = pixels[..., 3] > 0.5
    shade = pixels[..., :3].mean(axis=-1)
    shade = shade / max(shade[opaque].mean(), 1e-6)
    pixels[..., :3] = np.clip(shade[..., None] * np.array(colour)[None, None, :], 0.0, 1.0)
    return _packed(name, pixels)


def textured(name, image, roughness=0.6, cutout=False):
    """A Principled material showing `image`. With `cutout`, the image's alpha cuts holes (alpha clip:
    glTF's MASK mode, which a Round node on the alpha tells the exporter)."""
    mat = bpy.data.materials.new(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if cutout:
        clip = nodes.new("ShaderNodeMath")
        clip.operation = "ROUND"
        links.new(tex.outputs["Alpha"], clip.inputs[0])
        links.new(clip.outputs[0], bsdf.inputs["Alpha"])
    return mat


def use(obj, *materials):
    obj.data.materials.clear()
    for mat in materials:
        obj.data.materials.append(mat)


def height(objects):
    return max((obj.matrix_world @ v.co).z for obj in objects for v in obj.data.vertices)
