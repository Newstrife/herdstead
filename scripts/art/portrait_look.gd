class_name PortraitLook
extends RefCounted
## One portrait's look: the seat's person (`look`, the very AvatarLook the seat
## and the tile's small person resolve for the pane) and the portrait's own
## extras, which only a portrait draws: the expression, the marks on the skin
## (freckles) and what hangs round the neck (headphones).
##
## The extras are looks, never state (docs/VISUAL_LANGUAGE.md, "Looks"): each is
## picked once per pane by PixelPortraits.look_of() with the people's own hash
## under its own name, and nothing that changes with an agent's state takes part.

const EXPRESSION := &"expression"
const MARKS := &"marks"
const NECKWEAR := &"neckwear"
## Every extra, in the order the portraits' manifest lists them.
const EXTRAS: Array[StringName] = [EXPRESSION, MARKS, NECKWEAR]

## The seat's person: every look slot resolved (PixelPeople.look_for()).
var look: AvatarLook
var expression := &""
var marks := &""
var neckwear := &""


## The option this look names for extra `id`; empty when `id` is not an extra.
func extra(id: StringName) -> StringName:
	if not EXTRAS.has(id):
		return &""
	var value: StringName = get(id)
	return value


## Name `value` for extra `id`; false (and nothing changes) when `id` is not one.
func set_extra(id: StringName, value: StringName) -> bool:
	if not EXTRAS.has(id):
		push_error("PortraitLook: no extra %s" % id)
		return false
	set(id, value)
	return true


## A stable identity for this portrait: the person's slots and the extras, so
## a holder can tell whether it has to be dressed again.
func key() -> String:
	var parts := PackedStringArray()
	for id in AvatarLook.SLOTS:
		parts.append(str(look.slot(id)) if look != null else "")
	for id in EXTRAS:
		parts.append(str(extra(id)))
	return "/".join(parts)
