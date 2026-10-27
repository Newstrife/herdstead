extends "res://tools/test_base.gd"
## Seat-level helpers of the office geometry suite (test_office_geometry.gd):
## what a seat draws or answers a click with, in which rows, and its worker's
## pixels. Split off when the suite reached gdlint's file length (S3 SEATTAGS,
## 2026-10-27); moved as they were. No cases here.

## A pane name longer than two slots' plate (S3 SEATTAGS).
const LONG_NAME := "a pane name longer than two rows"


## The four bars of `table`'s selection frame, in global coordinates.
func _frame_bars(table: OfficeTable) -> Array[Rect2]:
	var bars: Array[Rect2] = []
	for bar: Node in table.get_node("Overlay/Frame").get_children():
		var control: Control = bar
		bars.append(control.get_global_transform() * Rect2(Vector2.ZERO, control.size))
	return bars


## Whether these are the seat marks of the two seats facing each other across
## one desk. Those two may meet: the near worker sits over the desk's near
## plane, a raised hand's top (pod -28) above the far mark's foot (-24), so the
## near mark [-32, 16) and the far one [-72, -24) share pod [-32, -24). Only
## one seat is ever selected, so the two are never drawn together; this case
## selects every seat only to measure each mark against everything else.
static func _facing_marks(a: OfficeStation, a_part: String, b: OfficeStation, b_part: String) -> bool:
	return a_part == "mark" and b_part == "mark" and a.table == b.table and a.column == b.column and a.side != b.side


## Whether two parts of the same seat may not meet: the three rows (plate,
## lens, tag) with each other, and the seat's rectangle with the chip's. The
## seat mark, and a click rectangle over the rows it answers for, may.
static func _same_seat_clash(a: String, b: String) -> bool:
	var rows := ["plate", "lens", "badge"]
	if a in rows and b in rows:
		return true
	if a in rows and b == "chip" or b in rows and a == "chip":
		return a != "badge" and b != "badge"
	return (a == "seat" and b == "chip rect") or (a == "chip rect" and b == "seat")


## What a seat draws or answers a click with, by name, in global coordinates:
## only what is shown now.
func _seat_rows(station: OfficeStation) -> Dictionary[String, Rect2]:
	var rows: Dictionary[String, Rect2] = {}
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	if badge.visible:
		rows["badge"] = badge.get_global_transform() * _opaque_local(badge)
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	if frame.is_visible_in_tree():
		rows["chip"] = frame.get_global_transform() * Rect2(Vector2.ZERO, frame.size)
	for label: String in ["Lens", "Plate"]:
		var control: Label = station.get_node("Overlay/" + label)
		if control.is_visible_in_tree():
			rows[label.to_lower()] = control.get_global_transform() * Rect2(Vector2.ZERO, control.size)
	var mark: Sprite2D = station.get_node("Overlay/Selection")
	if mark.is_visible_in_tree():
		rows["mark"] = mark.get_global_transform() * _opaque_local(mark)
	rows["seat"] = station.target_rect()
	var chip: CollisionShape2D = station.get_node(OfficeStation.CHIP_TARGET)
	if not chip.disabled:
		rows["chip rect"] = _shape_rect(chip)
	return rows


func _plate_of(station: OfficeStation) -> Label:
	return station.get_node("Overlay/Plate")


## Move the real pointer to `at` (viewport pixels) and let physics picking see it.
func _point(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


## Every opaque texel `sprite` draws, as texel cells (half a unit each at
## density 2) in global coordinates, or in `into`'s.
func _texels(sprite: Sprite2D, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	var image := sprite.texture.get_image()
	var used := image.get_used_rect()
	var to_world := into * sprite.get_global_transform()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var middle := to_world * (sprite.offset + Vector2(x + 0.5, y + 0.5))
			found[Vector2i(floori(middle.x * 2.0), floori(middle.y * 2.0))] = true
	return found


## Every opaque texel of the station's chair, as texel cells (see _texels()).
func _chair_texels(station: OfficeStation, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var chair: Sprite2D = station.get_node("Chair")
	return _texels(chair, into)


## Every opaque texel the station's worker draws in the track it plays, over
## all of its frames and both layers, as texel cells (see _texels()).
func _figure_texels(station: OfficeStation, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	var person := station.actor()
	var people := person.people
	var track := people.tracks[person.track]
	for layer in PixelPeople.LAYERS:
		var sprite: Sprite2D = person.get_node(PixelPeople.SPRITES[layer])
		if sprite.texture == null:
			continue
		var image := sprite.texture.get_image()
		for index in track.frame_count():
			var frame := people.frame_rect(track.frame(index))
			for y in frame.size.y:
				for x in frame.size.x:
					if image.get_pixel(frame.position.x + x, frame.position.y + y).a <= 0.0:
						continue
					var local := Vector2(x + 0.5, y + 0.5) / people.density - people.pivot
					if sprite.flip_h:
						local.x = -local.x
					var middle := into * person.get_global_transform() * local
					found[Vector2i(floori(middle.x * 2.0), floori(middle.y * 2.0))] = true
	return found


## Every opaque pixel the station's worker draws in the track it plays, over
## all of its frames and both layers (mirrored where a layer is), in the
## station's coordinates.
func _drawn_figure(station: OfficeStation) -> Rect2:
	var person := station.actor()
	var people := person.people
	var track := people.tracks[person.track]
	var drawn := Rect2()
	for layer in PixelPeople.LAYERS:
		var sprite: Sprite2D = person.get_node(PixelPeople.SPRITES[layer])
		# A layer the look leaves empty (no glasses, the hair under a hood) draws nothing.
		if sprite.texture == null:
			continue
		var image := sprite.texture.get_image()
		for index in track.frame_count():
			var used := image.get_region(people.frame_rect(track.frame(index))).get_used_rect()
			if used.size == Vector2i.ZERO:
				continue
			# Texels back to units.
			var local := Rect2(
				Vector2(used.position) / people.density - people.pivot, Vector2(used.size) / people.density
			)
			if sprite.flip_h:
				local = Rect2(Vector2(-local.end.x, local.position.y), local.size)
			var placed := Rect2(person.position + local.position, local.size)
			drawn = placed if drawn.size == Vector2.ZERO else drawn.merge(placed)
	return drawn


## Where the plate's upper-case text is drawn, in the station's coordinates:
## centred in the plate, from its top down to the font's baseline.
func _plate_text(station: OfficeStation) -> Rect2:
	var overlay: Node2D = station.get_node("Overlay")
	var plate: Label = overlay.get_node("Plate")
	var font := plate.get_theme_font("font")
	var pixels := plate.get_theme_font_size("font_size")
	var width := font.get_string_size(plate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var top_left := plate.position + Vector2((plate.size.x - width) / 2.0, 0)
	return _in_station(station, overlay, Rect2(top_left, Vector2(width, font.get_ascent(pixels))))


## The opaque pixels of `sprite` in its own coordinates (before its transform):
## what get_rect() is for the pixels that are drawn.
func _opaque_local(sprite: Sprite2D) -> Rect2:
	var used := Rect2(sprite.texture.get_image().get_used_rect())
	used.position += sprite.offset
	return used


## A collision shape's rectangle, in global coordinates.
func _shape_rect(node: Node) -> Rect2:
	var shape: CollisionShape2D = node
	var box: RectangleShape2D = shape.shape
	return Rect2(shape.global_position - box.size / 2.0, box.size)


## `bounds`, given in `node`'s own coordinates, in the station's.
func _in_station(station: OfficeStation, node: CanvasItem, bounds: Rect2) -> Rect2:
	return station.get_global_transform().affine_inverse() * node.get_global_transform() * bounds


## Seat a pane, named LONG_NAME, at every near seat of `stations` (one pod's,
## column by column, far then near) and at the far ones in `far`; vacate the
## rest; the map has few seats; widen the plates as the floor does.
func _seat_far(stations: Array[OfficeStation], far: Array[int]) -> void:
	for station in stations:
		if station.side == "near" or station.column in far:
			station.furnish("claude", ArtContract.STATE_WORKING)
			station.show_name(LONG_NAME)
		else:
			station.vacate()
		station.show_plates_always(true)
	OfficeFloorView.widen_plates(stations)


## Where `station`'s plate is drawn, in its pod's coordinates.
func _pod_plate(station: OfficeStation) -> Rect2:
	var plate := _plate_of(station)
	var drawn := plate.get_global_transform() * Rect2(Vector2.ZERO, plate.size)
	return station.table.global_transform.affine_inverse() * drawn
