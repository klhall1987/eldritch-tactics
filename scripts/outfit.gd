extends Node
## What the player character wears, by slot (`top`, `bottom`, `feet`). Each piece is a clothing glb
## (assets/models/clothes, #67) naming its slot in `slot` metadata. Putting one on moves its meshes
## onto the character's own skeleton, so they play every animation with him; it replaces whatever was
## in its slot. Taking one off leaves his base layer showing there. He starts in `default_pieces`.

## Emitted when a slot's piece changes (put on, replaced or taken off).
signal outfit_changed(slot: String)

const SLOTS: Array[String] = ["top", "bottom", "feet"]

## The character model to dress (its Skeleton3D carries the worn pieces).
@export var character_path: NodePath
## The pieces he wears when the game starts.
@export var default_pieces: Array[String] = [
	"res://assets/models/clothes/tee_purple.glb",
	"res://assets/models/clothes/jeans_blue.glb",
	"res://assets/models/clothes/sneakers_dark.glb",
]

var _worn := {}  # slot -> piece path
var _meshes := {}  # slot -> [MeshInstance3D, ...] drawn on him

@onready var _skeleton := _find_skeleton()


func _ready() -> void:
	for path in default_pieces:
		wear(slot_of(path), path)


## Puts the piece at `piece_path` on in `slot`, replacing what's there. Returns false, changing
## nothing, if the piece doesn't fill that slot (or can't be loaded).
func wear(slot: String, piece_path: String) -> bool:
	if not slot in SLOTS or slot_of(piece_path) != slot or _skeleton == null:
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
	piece.free()
	_worn[slot] = piece_path
	_meshes[slot] = meshes
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
	outfit_changed.emit(slot)


## The glb path of the piece worn in `slot`, or "" if it's empty.
func worn(slot: String) -> String:
	return _worn.get(slot, "")


## The meshes drawn on him for `slot` (none when it's empty).
func worn_meshes(slot: String) -> Array:
	return _meshes.get(slot, []).duplicate()


## The slot a clothing piece fills (its `slot` metadata), or "" if it isn't one.
static func slot_of(piece_path: String) -> String:
	var packed := load(piece_path) as PackedScene
	if packed == null:
		return ""
	var piece := packed.instantiate()
	var slot := str(piece.get_meta("slot", ""))
	piece.free()
	return slot


func _find_skeleton() -> Skeleton3D:
	var character := get_node_or_null(character_path)
	if character == null:
		return null
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	return skeletons[0] if not skeletons.is_empty() else null
