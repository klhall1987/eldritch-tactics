extends Node
## What the player character wears, by slot (`top`, `bottom`, `feet`). Each piece is a clothing glb
## (assets/models/clothes, #67) naming its slot in `slot` metadata. Putting one on moves its meshes
## onto the character's own skeleton, so they play every animation with him; it replaces whatever was
## in its slot. Taking one off leaves his base layer showing there. He starts in `default_pieces`.
## A piece only goes on if it was made for his body type (its `body_type` metadata matching his model's,
## #154), and while it's worn, the body regions it `covers` (his `body_<region>` meshes) are hidden so
## his skin can't show through it (#153).

## Emitted when a slot's piece changes (put on, replaced or taken off).
signal outfit_changed(slot: String)

const SLOTS: Array[String] = ["top", "bottom", "feet"]

## The character model to dress (its Skeleton3D carries the worn pieces).
@export var character_path: NodePath
## The pieces he wears when the game starts (none, since the old MakeHuman clothes went, #141).
@export var default_pieces: Array[String] = []

var _worn := {}  # slot -> piece path
var _meshes := {}  # slot -> [MeshInstance3D, ...] drawn on him
var _covers := {}  # slot -> [region, ...] its piece covers

@onready var _skeleton := _find_skeleton()
@onready var _character := get_node_or_null(character_path)


func _ready() -> void:
	for path in default_pieces:
		wear(slot_of(path), path)


## Puts the piece at `piece_path` on in `slot`, replacing what's there. Returns false, changing
## nothing, if the piece doesn't fill that slot, wasn't made for his body type (or names none), or
## can't be loaded.
func wear(slot: String, piece_path: String) -> bool:
	if not slot in SLOTS or slot_of(piece_path) != slot or _skeleton == null or not fits(piece_path):
		return false
	var piece := (load(piece_path) as PackedScene).instantiate()
	take_off(slot)
	var meshes := []
	for mi: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		mi.get_parent().remove_child(mi)
		mi.owner = null
		_skeleton.add_child(mi)
		mi.transform = Transform3D.IDENTITY
		mi.skeleton = mi.get_path_to(_skeleton)
		meshes.append(mi)
	var covers: Array = piece.get_meta("covers", [])
	piece.free()
	_worn[slot] = piece_path
	_meshes[slot] = meshes
	_covers[slot] = covers
	_show_body()
	outfit_changed.emit(slot)
	return true


## Takes off whatever is in `slot`, leaving his base layer showing there.
func take_off(slot: String) -> void:
	if not _worn.has(slot):
		return
	for mi: MeshInstance3D in _meshes[slot]:
		if is_instance_valid(mi):
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	_worn.erase(slot)
	_meshes.erase(slot)
	_covers.erase(slot)
	_show_body()
	outfit_changed.emit(slot)


## The glb path of the piece worn in `slot`, or "" if it's empty.
func worn(slot: String) -> String:
	return _worn.get(slot, "")


## The meshes drawn on him for `slot` (none when it's empty).
func worn_meshes(slot: String) -> Array:
	return _meshes.get(slot, []).duplicate()


## The slot a clothing piece fills (its `slot` metadata), or "" if it isn't one.
static func slot_of(piece_path: String) -> String:
	return str(_meta_of(piece_path, "slot"))


## Whether the piece at `piece_path` was made for his body type (#154): its `body_type` metadata names
## his model's. A piece naming no body type fits nobody.
func fits(piece_path: String) -> bool:
	var his := str(_character.get_meta("body_type", "")) if _character != null else ""
	return his != "" and str(_meta_of(piece_path, "body_type")) == his


## Shows each of his body regions (`body_<region>`) unless a worn piece covers it (#153).
func _show_body() -> void:
	if _character == null:
		return
	var covered := {}
	for regions: Array in _covers.values():
		for region in regions:
			covered[str(region)] = true
	for mi: MeshInstance3D in _character.find_children("body_*", "MeshInstance3D", true, false):
		mi.visible = not covered.has(str(mi.name).trim_prefix("body_"))


## The `key` metadata of the clothing piece at `piece_path`, or "" if it has none (or can't be loaded).
static func _meta_of(piece_path: String, key: String) -> Variant:
	var packed := load(piece_path) as PackedScene if ResourceLoader.exists(piece_path) else null
	if packed == null:
		return ""
	var piece := packed.instantiate()
	var value = piece.get_meta(key, "")
	piece.free()
	return value


func _find_skeleton() -> Skeleton3D:
	var character := get_node_or_null(character_path)
	if character == null:
		return null
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null
