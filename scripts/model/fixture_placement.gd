class_name FixturePlacement
extends RefCounted
## A map's service fixture in its entry band, as the plan placed it: the
## pantry counter in the band's corner. Planned by OfficeFixturePlanner, drawn
## by OfficeFloorView, an obstacle on the walk graph (OfficeWalkGraph). It is
## furniture: nobody walks to it or stands at it (an idle agent sits at their
## seat with a mug, docs/VISUAL_LANGUAGE.md). There is no reception any more.

enum Kind { PANTRY }

var kind := Kind.PANTRY
## Stable within the plan: "pantry".
var key := ""
## The counter's semantic prop.
var piece: StringName = &""
## Where the counter meets the floor, against the top wall.
var position := Vector2.ZERO
## What the counter stands on, and what it draws, in floor units.
var footprint := Rect2()
var draw_rect := Rect2()


func geometry_signature() -> String:
	return JSON.stringify([kind, key, piece, position, footprint, draw_rect])
