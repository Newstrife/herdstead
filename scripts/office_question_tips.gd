class_name OfficeQuestionTips
extends RefCounted
## What the question reader (OfficeQuestionReader) is told about the shown
## map, and the tooltips over the world: over a blocked agent's chip, what the
## reader found; over a seat, the pane's whole name; over a zone's sign, its
## repository. Reads nothing itself and never writes: the reader's own gates
## decide every read (docs/WRITE_BOUNDARY.md, "Reads that are not gestures").

## The office's lens, once it exists: nothing comes up over a chip while it is held.
var lens: OfficeLens
## The office's art pack, for the pack's word for a state in a seat's tooltip.
var art: ArtPack
var _fleet: HerdrFleet
var _hud: OfficeHud
var _camera: OfficeCamera
var _questions: OfficeQuestionReader
## The office's frame now (-> OfficeFrame): a read can come back between refreshes.
var _frame: Callable
## The pointer in viewport pixels now (-> Vector2).
var _mouse: Callable
## The pane whose chip the pointer is over, its tooltip shown; empty for none.
var _tip_key := ""
## Where the pointer came onto it, in viewport pixels.
var _tip_at := Vector2.ZERO
## The zone whose sign the pointer is over, its tooltip shown; empty for none.
var _sign_key := ""
## The pane whose seat the pointer is over, its tooltip shown; empty for none.
var _seat_key := ""


func _init(hud: OfficeHud, camera: OfficeCamera, frame: Callable, mouse: Callable) -> void:
	_hud = hud
	_camera = camera
	_frame = frame
	_mouse = mouse


## The fleet and the question reader, once the office has made them: until
## then nothing is watched and only hide_tip() does anything.
func attach(fleet: HerdrFleet, questions: OfficeQuestionReader) -> void:
	_fleet = fleet
	_questions = questions


## Tell the question reader which blocked agents the shown machine's map
## (`machine`'s, every zone of it, drawn by `floor_view`) has, which of their chips are inside the world on
## screen (`view` -> Rect2, global; in wait order, longest first) and whether their
## machine may be read; nothing is on screen while the terminal monitor, the
## overview or the strategic view covers the world. A refresh and a timer call
## this: a pan moves chips on and off screen without a refresh. The tooltip
## over a chip is written afresh from the reader here, and goes with the chip.
func watch(floor_view: OfficeFloorView, machine: String, view: Callable) -> void:
	_refresh_seat()
	if floor_view == null or _questions == null:
		return
	var frame: OfficeFrame = _frame.call()
	var blocked: Dictionary[String, String] = {}
	var seen: Array[PaneModel] = []
	var found := frame.map_of(machine)
	var live := false
	if found != null:
		live = (
			_fleet.has(machine)
			and _fleet.snapshot_is_current(machine)
			and not _hud.monitor_open()
			and not _hud.overview_open()
			and not _hud.strategic_open()
		)
		var on_screen_rect: Rect2 = view.call()
		for room in found.rooms:
			for pane in room.panes:
				var seat := floor_view.seat(pane.key)
				if seat == null or not _asking(pane):
					continue
				blocked[pane.key] = pane.identity_key()
				var chip := seat.node.chip_rect()
				if chip.has_area() and chip.intersects(on_screen_rect):
					seen.append(pane)
	var on_screen := PackedStringArray()
	for pane in OfficeProjection.wait_order(seen):
		on_screen.append(pane.key)
	_questions.watch(blocked, on_screen, live)
	# The tooltip says what the reader keeps now, so a terminal it just dropped
	# (another session, still blocked) is never shown; a chip gone takes it.
	if not _tip_key.is_empty():
		if blocked.has(_tip_key):
			_show_tip(_tip_key)
		else:
			hide_tip()


## A read came back for pane `key`: the tooltip over its chip says it now.
func show_question(key: String) -> void:
	if key == _tip_key:
		_show_tip(key)


## The pointer came onto the chip of pane `key` (`inside`), or left it. No
## tooltip while the monitor covers the world or a drag is under way.
func on_chip_hovered(key: String, inside: bool) -> void:
	if not inside:
		if key == _tip_key:
			hide_tip()
		return
	if _hud.monitor_open() or _camera.dragging or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# Under the lens the chip draws nothing, and nothing comes up over it.
	if lens != null and lens.held:
		return
	_sign_key = ""
	_seat_key = ""
	_tip_key = key
	_tip_at = _mouse.call()
	_show_tip(key)


## The pointer came onto the sign of zone `zone_key` (`inside`), or left it:
## the tooltip names the zone's repository and checkout, and whose worktree a
## mezzanine is (sign_text()). Read from the frame the office holds: nothing is
## read from herdr and nothing written. Not while the monitor covers the world,
## during a drag, or under the lens.
func on_sign_hovered(zone_key: String, inside: bool) -> void:
	if not inside:
		if zone_key == _sign_key:
			hide_tip()
		return
	if _hud.monitor_open() or _camera.dragging or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if lens != null and lens.held:
		return
	var frame: OfficeFrame = _frame.call()
	var found := frame.find_zone(zone_key)
	if found == null:
		return
	_tip_key = ""
	_seat_key = ""
	_sign_key = zone_key
	_tip_at = _mouse.call()
	_hud.show_world_tip(sign_text(found), _tip_at)


## The pointer came onto the seat of pane `key` (`inside`), or left it: the
## tooltip says the pane's whole name, who sits there and in what state, and
## where (seat_text()), the plate having room for only the name's start. From
## the frame the office holds: nothing is read from herdr and nothing written.
## Not while the monitor covers the world, during a drag, or under the lens;
## a chip's tooltip is never replaced by it (the chip's rectangle and the
## seat's never share a point, and the chip's came last).
func on_seat_hovered(key: String, inside: bool) -> void:
	if not inside:
		if key == _seat_key:
			hide_tip()
		return
	if _hud.monitor_open() or _camera.dragging or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if lens != null and lens.held:
		return
	var frame: OfficeFrame = _frame.call()
	var pane := frame.pane(key)
	if pane == null:
		return
	_tip_key = ""
	_sign_key = ""
	_seat_key = key
	_tip_at = _mouse.call()
	_hud.show_world_tip(seat_text(pane, _live(frame, pane), art), _tip_at)


## What a seat's tooltip says: the pane's whole name, then who sits there and
## in what state (`CLAUDE · BLOCKED`, `CLAUDE-2 · STARTING`, `CODEX · OFFLINE`,
## `SHELL`), then where (`api / tests`). The state is the pack's word when
## `art` has one (`UNREAD`).
static func seat_text(pane: PaneModel, live: bool, pack: ArtPack) -> String:
	var who := PackedStringArray([pane.who()])
	if not live:
		who.append("OFFLINE")
	elif pane.launching():
		who.append("STARTING")
	elif not pane.provider.is_empty():
		var drawn: ArtState = null if pack == null else pack.state(StringName(pane.state))
		who.append(pane.state.to_upper() if drawn == null else drawn.label)
	return "%s\n%s\n%s" % [pane.name, " · ".join(who), pane.place()]


## What a zone's sign tooltip says (ZoneRef.sign_text(), the one place it is
## worked out): `repo · checkout · worktree of 3`. A portrait card's place and
## the strategic view's caption say it too.
static func sign_text(found: ZoneRef) -> String:
	return found.sign_text()


## Take the tooltip away (a drag, another map, the overview, the lens, ...).
func hide_tip() -> void:
	_tip_key = ""
	_sign_key = ""
	_seat_key = ""
	_hud.hide_world_tip()


## A refresh: the seat's tooltip says the pane as it is now (a new task, a new
## state), and goes with the pane.
func _refresh_seat() -> void:
	if _seat_key.is_empty():
		return
	var frame: OfficeFrame = _frame.call()
	var pane := frame.pane(_seat_key)
	if pane == null:
		hide_tip()
		return
	_hud.show_world_tip(seat_text(pane, _live(frame, pane), art), _tip_at)


## Whether `pane`'s machine is live in `frame`: a dropped one's seats say OFFLINE.
static func _live(frame: OfficeFrame, pane: PaneModel) -> bool:
	var building: BuildingModel = frame.building_by_key.get(pane.machine())
	return building != null and not building.stale


func _show_tip(key: String) -> void:
	var frame: OfficeFrame = _frame.call()
	var pane := frame.pane(key)
	if pane == null:
		hide_tip()
		return
	_hud.show_world_tip(_question_text(key, pane.identity_key()), _tip_at)


## What the tooltip over the chip of pane `key` (terminal `identity`) says:
## that this office reads nothing, the excerpt read for that terminal (an empty
## one says so), or plainly that there is none: never a placeholder promising a
## read, which a dropped machine would never bring.
func _question_text(key: String, identity: String) -> String:
	if _fleet.read_only():
		return OfficeQuestionReader.READ_ONLY_TEXT
	var asked := _questions.question(key, identity)
	if asked == null:
		return OfficeQuestionReader.NOT_READ_TEXT
	return OfficeQuestionReader.EMPTY_TEXT if asked.text.is_empty() else asked.text


## Whether `pane`'s seat shows a chip: a blocked agent, launching or not
## (PaneModel.asks(): blocked comes first).
static func _asking(pane: PaneModel) -> bool:
	return pane.asks()
