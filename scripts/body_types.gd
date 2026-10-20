extends RefCounted
## The game's body types (#150), as in Baldur's Gate 3: every humanoid character is one of a few body
## types, and every body type's model is built on one shared skeleton (the same bones, parents and rest
## pose), so a clothing piece made for a body type binds to any character of that type by bone name
## (scripts/outfit.gd). Characters of one type share the body and skeleton; they differ in head, hair
## and skin. A model names its type with `body_type` metadata (set by its import script).

## Body type -> its model.
const MODELS := {
	"male_average": "res://assets/models/characters/character.glb",  # the player's Meshy character (#142)
}
## The body type whose model's skeleton is the shared skeleton.
const SHARED := "male_average"


## Every body type's name.
static func names() -> Array:
	return MODELS.keys()


## The model of body type `name`, or "" if there's no such body type.
static func model(name: String) -> String:
	return MODELS.get(name, "")


## The model whose skeleton is the shared skeleton.
static func shared_model() -> String:
	return MODELS[SHARED]
