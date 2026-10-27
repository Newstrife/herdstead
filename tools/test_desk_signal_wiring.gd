extends "res://tools/office_test_base.gd"
## The live office brings a desk into view, opens a zone, frames a pointed desk
## and stands its edge arrows exactly where it did before "where is this desk's
## signal" became OfficeFloorView's to answer (lane RECT, off 6413cec): every
## number here was printed by 6413cec on this fixture, and the cases go only
## through what the office offered then (OfficeScene.reveal() and
## reveal_zone(), OfficeFloorView.point() and its pointer, the HUD's arrows), so
## the same file passes on that commit. The answers themselves, on a bare floor
## view, are tools/test_desk_signal.gd's. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_desk_signal_wiring.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## When a desk's rows (OfficeStation), a pod's measure or the map's plan change
## on purpose, these numbers change with them: a failure prints the new one.
## Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new zone takes lanes until it
## stands one row; the map replans. Re-pinned from the office's own answers
## (printed by a throwaway dump case) and checked against the plans: 800x480
## plans 20 cells, three lanes, 18x26 (api, web, infra two lanes each down the
## left, notes and data one lane each beside api and web); 480x320 plans 10
## cells, the narrowest plan's two lanes (FRAME-Q2), 13x33 (api, web, infra
## stacked, notes and data side by side under them); 1280x720 plans 34 cells,
## six lanes, 33x19, as deep as before.

## The pan after reveal(key) and reveal(key, true) from no pan, then the same
## two from the far corner of the map, before the camera's next frame clamps
## it: an 800x480 window (the world at (96, 48), 660x308 of it in view, a
## three-lane map 576 wide, 832 deep).
const REVEAL_800: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 12), Vector2(0, 76), Vector2(0, 230), Vector2(0, 230)],
	"api:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 58), Vector2(0, 58)],
	"api:p3": [Vector2(0, 76), Vector2(0, 76), Vector2(0, 296), Vector2(0, 230)],
	"api:p4": [Vector2(0, 12), Vector2(0, 76), Vector2(0, 230), Vector2(0, 230)],
	"data:p1": [Vector2(0, 236), Vector2(0, 300), Vector2(0, 454), Vector2(0, 454)],
	"data:p2": [Vector2(0, 300), Vector2(0, 300), Vector2(0, 520), Vector2(0, 454)],
	"infra:p1": [Vector2(0, 460), Vector2(0, 524), Vector2(0, 556), Vector2(0, 556)],
	"infra:p2": [Vector2(0, 460), Vector2(0, 524), Vector2(0, 556), Vector2(0, 556)],
	"infra:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 58), Vector2(0, 58)],
	"notes:p1": [Vector2(0, 12), Vector2(0, 76), Vector2(0, 230), Vector2(0, 230)],
	"web:p1": [Vector2(0, 236), Vector2(0, 300), Vector2(0, 456), Vector2(0, 454)],
	"web:p2": [Vector2(0, 300), Vector2(0, 300), Vector2(0, 520), Vector2(0, 454)],
	"web:p3": [Vector2(0, 236), Vector2(0, 300), Vector2(0, 454), Vector2(0, 454)],
}
## The same in the smallest window, 480x320: 340x200 of a 416-wide map in
## view, so a reveal pans sideways too. Z1 (2026-10-27): the narrowest plan
## stays two lanes (13 cells, FRAME-Q2); its 33 rows (40 with one 9-cell lane)
## move every zone under api and web up.
const REVEAL_480: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 120), Vector2(0, 184), Vector2(65, 230), Vector2(64, 230)],
	"api:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(76, 58), Vector2(76, 58)],
	"api:p3": [Vector2(0, 184), Vector2(0, 184), Vector2(76, 296), Vector2(64, 230)],
	"api:p4": [Vector2(0, 120), Vector2(0, 184), Vector2(76, 230), Vector2(76, 230)],
	"data:p1": [Vector2(0, 792), Vector2(0, 856), Vector2(76, 888), Vector2(76, 888)],
	"data:p2": [Vector2(0, 856), Vector2(0, 856), Vector2(76, 888), Vector2(76, 888)],
	"infra:p1": [Vector2(0, 568), Vector2(0, 632), Vector2(65, 680), Vector2(64, 678)],
	"infra:p2": [Vector2(0, 568), Vector2(0, 632), Vector2(76, 678), Vector2(76, 678)],
	"infra:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(76, 58), Vector2(76, 58)],
	"notes:p1": [Vector2(0, 792), Vector2(0, 856), Vector2(65, 888), Vector2(64, 888)],
	"web:p1": [Vector2(0, 344), Vector2(0, 408), Vector2(65, 456), Vector2(64, 454)],
	"web:p2": [Vector2(0, 408), Vector2(0, 408), Vector2(65, 520), Vector2(64, 454)],
	"web:p3": [Vector2(0, 344), Vector2(0, 408), Vector2(76, 454), Vector2(76, 454)],
}
## The same in a 1280x720 window: the world at (144, 48), 1092x548 of a
## six-lane map 640 deep in view, so the pan only ever reaches 92 down.
const REVEAL_1280: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"api:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 58), Vector2(0, 58)],
	"api:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"api:p4": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"data:p1": [Vector2(0, 0), Vector2(0, 60), Vector2(0, 92), Vector2(0, 92)],
	"data:p2": [Vector2(0, 60), Vector2(0, 60), Vector2(0, 92), Vector2(0, 92)],
	"infra:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"infra:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"infra:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 58), Vector2(0, 58)],
	"notes:p1": [Vector2(0, 0), Vector2(0, 60), Vector2(0, 92), Vector2(0, 92)],
	"web:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"web:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
	"web:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 92), Vector2(0, 92)],
}
## The pointer's frame around each desk, in the floor's own coordinates, on the
## 800x480 window's three-lane map (the 480x320 window planned the same one
## before Z1; it plans its own two-lane map now).
const POINTER_800: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 228, 34, 62),
	"api:p2": Rect2(275, 56, 42, 60),
	"api:p3": Rect2(95, 294, 34, 60),
	"api:p4": Rect2(159, 228, 34, 62),
	"data:p1": Rect2(383, 452, 34, 62),
	"data:p2": Rect2(383, 518, 34, 60),
	"infra:p1": Rect2(63, 678, 34, 60),
	"infra:p2": Rect2(159, 676, 34, 62),
	"infra:p3": Rect2(131, 56, 42, 60),
	"notes:p1": Rect2(383, 228, 34, 62),
	"web:p1": Rect2(63, 454, 34, 60),
	"web:p2": Rect2(63, 518, 34, 60),
	"web:p3": Rect2(159, 452, 34, 62),
}
## And on the 480x320 window's two-lane map (13 cells).
const POINTER_480: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 228, 34, 62),
	"api:p2": Rect2(227, 56, 42, 60),
	"api:p3": Rect2(95, 294, 34, 60),
	"api:p4": Rect2(159, 228, 34, 62),
	"data:p1": Rect2(223, 900, 34, 62),
	"data:p2": Rect2(223, 966, 34, 60),
	"infra:p1": Rect2(63, 678, 34, 60),
	"infra:p2": Rect2(159, 676, 34, 62),
	"infra:p3": Rect2(179, 56, 42, 60),
	"notes:p1": Rect2(63, 900, 34, 62),
	"web:p1": Rect2(63, 454, 34, 60),
	"web:p2": Rect2(63, 518, 34, 60),
	"web:p3": Rect2(159, 452, 34, 62),
}
## And on the 1280x720 window's six-lane map.
const POINTER_1280: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 228, 34, 62),
	"api:p2": Rect2(611, 56, 42, 60),
	"api:p3": Rect2(95, 294, 34, 60),
	"api:p4": Rect2(159, 228, 34, 62),
	"data:p1": Rect2(223, 452, 34, 62),
	"data:p2": Rect2(223, 518, 34, 60),
	"infra:p1": Rect2(703, 230, 34, 60),
	"infra:p2": Rect2(799, 228, 34, 62),
	"infra:p3": Rect2(515, 56, 42, 60),
	"notes:p1": Rect2(63, 452, 34, 62),
	"web:p1": Rect2(383, 230, 34, 60),
	"web:p2": Rect2(383, 294, 34, 60),
	"web:p3": Rect2(479, 228, 34, 62),
}
## The pan after reveal_zone(zone) from no pan, and where the camera's next
## frame leaves it; then the same two from the far corner of the map.
const ZONES_800: Dictionary[String, Array] = {
	"api": [Vector2(0, 206), Vector2(0, 206), Vector2(0, 206), Vector2(0, 206)],
	"web": [Vector2(0, 430), Vector2(0, 430), Vector2(0, 430), Vector2(0, 430)],
	"infra": [Vector2(0, 654), Vector2(0, 556), Vector2(0, 654), Vector2(0, 556)],
	"notes": [Vector2(0, 206), Vector2(0, 206), Vector2(0, 206), Vector2(0, 206)],
	"data": [Vector2(0, 430), Vector2(0, 430), Vector2(0, 430), Vector2(0, 430)],
}
const ZONES_480: Dictionary[String, Array] = {
	"api": [Vector2(0, 206), Vector2(0, 206), Vector2(32, 206), Vector2(32, 206)],
	"web": [Vector2(0, 430), Vector2(0, 430), Vector2(32, 430), Vector2(32, 430)],
	"infra": [Vector2(0, 654), Vector2(0, 654), Vector2(32, 654), Vector2(32, 654)],
	"notes": [Vector2(0, 878), Vector2(0, 878), Vector2(32, 878), Vector2(32, 878)],
	"data": [Vector2(0, 878), Vector2(0, 878), Vector2(76, 878), Vector2(76, 878)],
}
const ZONES_1280: Dictionary[String, Array] = {
	"api": [Vector2(0, 206), Vector2(0, 92), Vector2(0, 206), Vector2(0, 92)],
	"web": [Vector2(0, 206), Vector2(0, 92), Vector2(0, 206), Vector2(0, 92)],
	"infra": [Vector2(0, 206), Vector2(0, 92), Vector2(0, 206), Vector2(0, 92)],
	"notes": [Vector2(0, 430), Vector2(0, 92), Vector2(0, 430), Vector2(0, 92)],
	"data": [Vector2(0, 430), Vector2(0, 92), Vector2(0, 430), Vector2(0, 92)],
}
## REVEAL_800 and ZONES_800 with the drawer open (536 of the map in view): see test_a_relayout_moves_no_answer.
const REVEAL_DRAWER: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 12), Vector2(0, 76), Vector2(40, 230), Vector2(40, 230)],
	"api:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(40, 58), Vector2(40, 58)],
	"api:p3": [Vector2(0, 76), Vector2(0, 76), Vector2(40, 296), Vector2(40, 230)],
	"api:p4": [Vector2(0, 12), Vector2(0, 76), Vector2(40, 230), Vector2(40, 230)],
	"data:p1": [Vector2(0, 236), Vector2(0, 300), Vector2(40, 454), Vector2(40, 454)],
	"data:p2": [Vector2(0, 300), Vector2(0, 300), Vector2(40, 520), Vector2(40, 454)],
	"infra:p1": [Vector2(0, 460), Vector2(0, 524), Vector2(40, 556), Vector2(40, 556)],
	"infra:p2": [Vector2(0, 460), Vector2(0, 524), Vector2(40, 556), Vector2(40, 556)],
	"infra:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(40, 58), Vector2(40, 58)],
	"notes:p1": [Vector2(0, 12), Vector2(0, 76), Vector2(40, 230), Vector2(40, 230)],
	"web:p1": [Vector2(0, 236), Vector2(0, 300), Vector2(40, 456), Vector2(40, 454)],
	"web:p2": [Vector2(0, 300), Vector2(0, 300), Vector2(40, 520), Vector2(40, 454)],
	"web:p3": [Vector2(0, 236), Vector2(0, 300), Vector2(40, 454), Vector2(40, 454)],
}
const ZONES_DRAWER: Dictionary[String, Array] = {
	"api": [Vector2(0, 206), Vector2(0, 206), Vector2(32, 206), Vector2(32, 206)],
	"web": [Vector2(0, 430), Vector2(0, 430), Vector2(32, 430), Vector2(32, 430)],
	"infra": [Vector2(0, 654), Vector2(0, 556), Vector2(32, 654), Vector2(32, 556)],
	"notes": [Vector2(0, 206), Vector2(0, 206), Vector2(40, 206), Vector2(40, 206)],
	"data": [Vector2(0, 430), Vector2(0, 430), Vector2(40, 430), Vector2(40, 430)],
}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket", "work"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s= (use tools/run_tests.sh)" % name)
			quit(2)
			return
	# Nothing here may reach the user's herdr, machines or forwards.
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("desk-signal-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	# Both seat sides in every rest: web:p2 (near) asks beside web:p1 (far),
	# data:p2 (near) works, api:p2 (far) and infra:p3 (near) rest in the pantry,
	# api:p3 (near) and web:p3 (far) are shells.
	fixture = _dict(fixture_file, "snapshot")
	fixture = _with(_with(fixture, "web:p2", {"agent_status": "blocked"}), "data:p2", {"agent_status": "working"})
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "DESK SIGNAL WIRING TESTS"


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The fixture drawn and settled in a window of `screen`.
func _office(screen := Vector2(SCREEN)) -> OfficeDouble:
	var office := await _live_office(fixture, screen)
	office.settle()
	await _frames(2)
	return office


## The furthest the pan goes on the shown map.
func _far(office: OfficeDouble) -> Vector2:
	return (office.camera.world_size - office.camera.free_rect().size).max(Vector2.ZERO)


## reveal() for every desk of `wanted`, plainly and with its pod, from no pan
## and from the far corner, against the pans 6413cec left.
func _reveals(office: OfficeDouble, wanted: Dictionary[String, Array], where: String) -> void:
	_eq(office.floor_view.seats.size(), wanted.size(), "%s: every desk of the fixture is seated" % where)
	for pane_id: String in wanted:
		var pans := []
		for from: Vector2 in [Vector2.ZERO, _far(office)]:
			for whole: bool in [false, true]:
				office.camera.pan = from
				office.reveal(_pk(pane_id), whole)
				pans.append(office.camera.pan)
		_eq(
			pans,
			wanted[pane_id],
			"%s: %s revealed alone and with its pod, from the top and from the far corner" % [where, pane_id]
		)


## reveal_zone() for every zone of `wanted`, from no pan and from the far
## corner, each time as the call leaves the pan and as the next frame clamps it.
func _openings(office: OfficeDouble, wanted: Dictionary[String, Array], where: String) -> void:
	_eq(office.floor_view.plan.zones.size(), wanted.size(), "%s: every zone of the fixture is placed" % where)
	for zone_id: String in wanted:
		var pans := []
		for from: Vector2 in [Vector2.ZERO, _far(office)]:
			office.camera.pan = from
			office.reveal_zone(_pk(zone_id))
			pans.append(office.camera.pan)
			await _frames(1)
			pans.append(office.camera.pan)
		_eq(pans, wanted[zone_id], "%s: %s opened from the top and from the far corner" % [where, zone_id])


## point() at every desk of `wanted`, against the frames 6413cec drew.
func _pointed(office: OfficeDouble, wanted: Dictionary[String, Rect2], where: String) -> void:
	var pointer := office.floor_view.pointer
	for pane_id: String in wanted:
		office.floor_view.point(_pk(pane_id))
		_eq([pointer.key, pointer.visible], [_pk(pane_id), true], "%s: the pointer is at %s" % [where, pane_id])
		_eq(pointer.rect, wanted[pane_id], "%s: and frames %s where it did" % [where, pane_id])
	office.floor_view.point("")
	_eq([pointer.key, pointer.visible, pointer.rect], ["", false, Rect2()], "%s: pointing at nothing clears it" % where)
	var first: String = wanted.keys()[0]
	office.floor_view.point(_pk(first))
	office.floor_view.point(_pk("nobody:p9"))
	_eq([pointer.key, pointer.visible], ["", false], "%s: and so does a pane with no seat here" % where)


## The arrows the HUD shows once the view is at `pan`: each one's zone, the
## desk a click pans to, how many are blocked there, its edge, and where along
## the edge to the four decimals the arrows' own signature keeps
## (EdgeArrowModel.signature()).
func _arrows_at(office: OfficeDouble, pan: Vector2) -> Array:
	office.camera.pan = pan
	await _frames(3)
	var said := []
	for arrow in office.hud.edge_arrows.models():
		said.append([arrow.zone_key, arrow.pane_key, arrow.blocked, arrow.edge, "%.4f" % arrow.along])
	return said


## One arrow as _arrows_at() says it.
func _arrow(zone_id: String, pane_id: String, blocked: int, edge: EdgeArrowModel.Edge, along: String) -> Array:
	return [_pk(zone_id), _pk(pane_id), blocked, edge, along]


# --- a desk brought into view -----------------------------------------------------


## reveal(key) and reveal(key, true) leave the pan where 6413cec left it, for
## every desk of the fixture: a seated worker far and near, a blocked one with
## its chip on either side, a pantry worker (whose pod is too far below to join
## the framing), and a shell.
func test_a_desk_is_revealed_where_it_was_at_800x480() -> void:
	var office := await _office()
	_eq(office.world.position, Vector2(96, 48), "the world stands at the HUD's free corner")
	_eq(office.camera.free_rect(), Rect2(96, 48, 660, 308), "with 660x308 of it in view")
	_eq(office.floor_view.root.position, Vector2(0, OfficeScene.PLATE_HEIGHT), "and the floor under the plate")
	_reveals(office, REVEAL_800, "800x480")
	_done(office)


## The smallest window pans sideways too: 340 of the map's 416 units in view.
## Z1 (2026-10-27): two lanes of 4 (the narrowest plan, FRAME-Q2), 416 wide as
## one lane of 9 was, 33 rows deep instead of 40.
func test_a_desk_is_revealed_where_it_was_in_the_smallest_window() -> void:
	var office := await _office(Vector2(480, 320))
	_eq(office.camera.free_rect(), Rect2(96, 48, 340, 200), "340x200 of the world in view")
	_eq(_far(office), Vector2(76, 888), "the pan reaches 76 sideways")
	_reveals(office, REVEAL_480, "480x320")
	# A reveal starts from the pan as it is and leaves it between units when
	# nothing has to move; only the camera's next frame rounds, and only its
	# position.
	office.camera.pan = Vector2(10.5, 130.25)
	office.reveal(_pk("api:p1"))
	_eq(office.camera.pan, Vector2(10.5, 130.25), "api:p1 already in view from a pan between units: no move")
	await _frames(1)
	_eq(office.camera.pan, Vector2(10.5, 130.25), "the next frame keeps the pan")
	_eq(office.camera.position, Vector2(11, 130), "and rounds the camera's position")
	office.camera.pan = Vector2(10.5, 300.75)
	office.reveal(_pk("api:p1"))
	_eq(office.camera.pan, Vector2(10.5, 230), "from below: up to its headroom, sideways untouched")
	_done(office)


## A wide window moves the world's origin (the SPACES rail is wider) and plans
## six lanes (three of 9 before Z1: the same 33x19 map): the pans are still the
## ones 6413cec left.
func test_a_desk_is_revealed_where_it_was_at_another_world_origin() -> void:
	var office := await _office(Vector2(1280, 720))
	_eq(office.world.position, Vector2(144, 48), "the world stands further right")
	_eq(office.camera.free_rect(), Rect2(144, 48, 1092, 548), "with 1092x548 of it in view")
	_reveals(office, REVEAL_1280, "1280x720")
	_done(office)


## A pane with no seat on the shown map and a zone the plan does not place
## move nothing.
func test_no_seat_and_no_zone_pan_nothing() -> void:
	var office := await _office()
	office.camera.pan = Vector2(77, 55)
	office.reveal(_pk("nobody:p9"))
	office.reveal(_pk("nobody:p9"), true)
	office.reveal("")
	office.reveal_zone(_pk("nowhere"))
	office.reveal_zone("")
	_eq(office.camera.pan, Vector2(77, 55), "the pan is where it was")
	_done(office)


## Z1 (2026-10-27): a 1024x960 window leaves the world 836x788 units, planned
## at 26 cells: four lanes of 4 now, so the fixture's map is 23 cells by 19
## (608 units, 640 with its plate; two lanes of 9 made it 26 deep, 864 with the
## plate, taller than the room) and fits the room: the view opens unpanned, and
## a real drag and the arrow keys pan nothing (OfficeCamera clamps the pan to
## the map). Every zone's row on the SPACES rail is marked in view.
func test_a_map_that_fits_the_view_cannot_be_panned() -> void:
	var office := await _office(Vector2(1024, 960))
	var room := office.camera.free_rect()
	var world := office.camera.world_size
	_check(
		world.x <= room.size.x and world.y <= room.size.y,
		"the map and its plate fit the room: %s in %s" % [world, room]
	)
	_eq(office.camera.position, Vector2.ZERO, "the first refresh leaves the view unpanned")
	var seen := Rect2(office.camera.position + room.position, room.size)
	await _drag(Vector2(400, 300), Vector2(320, 220))
	await _frames(2)
	_eq(office.camera.position, Vector2.ZERO, "a real drag 80 units up and left pans nothing")
	_eq(Rect2(office.camera.position + room.position, room.size), seen, "the world on screen is the same")
	for keycode: Key in [KEY_DOWN, KEY_RIGHT]:
		await _parsed(_key(keycode))
		_check(Input.is_action_pressed("ui_down" if keycode == KEY_DOWN else "ui_right"), "the key is held")
		await _frames(2)
		var release := _key(keycode)
		release.pressed = false
		await _parsed(release)
		_eq(office.camera.position, Vector2.ZERO, "%s held for frames pans nothing" % OS.get_keycode_string(keycode))
	_eq(Rect2(office.camera.position + room.position, room.size), seen, "and the world on screen stays")
	var rail := office.hud.spaces
	_eq(Array(rail.in_view()), Array(rail.row_keys()), "every zone's row is marked in view")
	_done(office)


# --- a zone opened ----------------------------------------------------------------


## reveal_zone() puts the top of the zone's sign at the top of the world, with
## no headroom, and pans sideways only as far as the zone's width needs; the
## camera's next frame clamps the pan to the map (infra on the 800x480
## window's map, and every zone of the shallow 1280x720 one, stop at the map's
## end).
func test_a_zone_is_opened_where_it_was() -> void:
	var office := await _office()
	await _openings(office, ZONES_800, "800x480")
	_done(office)
	office = await _office(Vector2(480, 320))
	await _openings(office, ZONES_480, "480x320")
	_done(office)
	office = await _office(Vector2(1280, 720))
	await _openings(office, ZONES_1280, "1280x720")
	_done(office)


# --- the pointer ------------------------------------------------------------------


## point() frames the desk's click area and its chip, grown by
## OfficePointer.GROW and on whole units, in the floor's own coordinates
## whatever the world's origin; nothing and an unseated pane clear it.
func test_the_pointer_frames_what_it_framed() -> void:
	var office := await _office()
	_pointed(office, POINTER_800, "800x480")
	_done(office)
	office = await _office(Vector2(480, 320))
	_pointed(office, POINTER_480, "480x320")
	_done(office)
	office = await _office(Vector2(1280, 720))
	_pointed(office, POINTER_1280, "1280x720")
	_done(office)


# --- the edge arrows --------------------------------------------------------------


## The arrows at the corners and the middle of the map: which zones, the desk
## each leads to, how many blocked desks it counts, its edge and its place
## along it are what 6413cec showed. Z1 (2026-10-27): a lane is 4 cells, pitch
## 5, a new zone takes lanes until it stands one row; the map replans. The
## 800x480 bottom is the far pan's now (its map is 26 rows deep, so the bottom
## shows web's near chip and infra's); 480x320 (two lanes, 13x33, FRAME-Q2)
## keeps its top and middle values and its bottom is 888 down (1112 before).
func test_the_arrows_stand_where_they_stood() -> void:
	var office := await _office()
	var below := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.3294"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.3969")
	]
	var above := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4119"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.3668")
	]
	_eq(await _arrows_at(office, Vector2.ZERO), below, "800x480, at the top: both zones below")
	_eq(
		await _arrows_at(office, _far(office)),
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2274")],
		"800x480, at the bottom: web's far chip above, its near one and infra's in view"
	)
	_eq(await _arrows_at(office, Vector2(0, 502)), [], "800x480, in the middle: every chip in view")
	_done(office)
	office = await _office(Vector2(480, 320))
	below = [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.4332"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4573")
	]
	var below_right := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.3767"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4213")
	]
	above = [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4462"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.4012")
	]
	var above_right := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4008"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.3178")
	]
	_eq(await _arrows_at(office, Vector2.ZERO), below, "480x320, top left")
	_eq(await _arrows_at(office, Vector2(76, 0)), below_right, "480x320, top right")
	_eq(await _arrows_at(office, Vector2(0, 888)), above, "480x320, bottom left")
	_eq(await _arrows_at(office, Vector2(76, 888)), above_right, "480x320, bottom right")
	_eq(
		await _arrows_at(office, Vector2(38, 556)),
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2647")],
		"480x320, in the middle: one of web's two chips is above the view"
	)
	_done(office)


## An arrow stands by its desk's chip alone, to the unit: with the view's top
## edge one unit into the chip there is none, and with it at the chip's bottom
## edge there is one, although the seat under a far chip is then wholly in
## view (the chip and the seat together are what a reveal frames, not what an
## arrow aims at). A near seat's chip is below its sitter: web:p2's counts
## from the unit the view's top passes it, while its seat left the view above.
## Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new zone takes lanes until it
## stands one row; the map replans. In the 480x320 window: the 800x480 map is
## 26 rows deep now and its pan stops (556) short of web:p2's and infra:p1's
## edges; the 480x320 map (13x33, the narrowest plan's two lanes) pans 888 down,
## past all three. The 200-unit view leaves infra below while web:p1's chip
## passes the top.
func test_an_arrow_follows_its_chip_to_the_unit() -> void:
	var office := await _office(Vector2(480, 320))
	var room := office.camera.free_rect()
	var far_chip := office.floor_view.seat(_pk("web:p1")).node.chip_rect()
	var far_seat := office.floor_view.seat(_pk("web:p1")).node.target_rect()
	_eq([far_chip, far_seat], [Rect2(161, 536, 30, 16), Rect2(161, 552, 30, 40)], "web:p1's chip over its seat")
	var edge := far_chip.end.y - room.position.y
	_eq(edge, 504.0, "the pan that puts the view's top at the chip's bottom")
	var infra_below := _arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2738")
	_eq(await _arrows_at(office, Vector2(0, edge - 1)), [infra_below], "one unit of web:p1's chip in view: no arrow")
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2549"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2718")
		],
		"the chip just out of view, its seat still in: the arrow"
	)
	_check(far_seat.intersects(Rect2(Vector2(0, edge) + room.position, room.size)), "the seat is in view then")
	_eq(
		await _arrows_at(office, Vector2(0, edge + 1)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2572"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2698")
		],
		"a unit further: the arrow, a little along"
	)
	var near_chip := office.floor_view.seat(_pk("web:p2")).node.chip_rect()
	var near_seat := office.floor_view.seat(_pk("web:p2")).node.target_rect()
	_eq([near_chip, near_seat], [Rect2(161, 640, 30, 16), Rect2(161, 600, 30, 38)], "web:p2's chip under its seat")
	edge = near_chip.end.y - room.position.y
	_eq(
		await _arrows_at(office, Vector2(0, edge - 1)),
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.3745")],
		"one unit of web:p2's chip in view: only web:p1 counts"
	)
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.3751")],
		"web:p2's chip just out of view: both count"
	)
	var infra_chip := office.floor_view.seat(_pk("infra:p1")).node.chip_rect()
	edge = infra_chip.end.y - room.position.y
	_eq(
		await _arrows_at(office, Vector2(0, edge - 1)),
		[_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4200")],
		"one unit of infra:p1's chip in view: web's arrow alone"
	)
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4203"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.2549")
		],
		"infra:p1's chip just out of view: its arrow too"
	)
	_done(office)


# --- a relayout -------------------------------------------------------------------


## Opening the drawer by a real click takes the world's right edge in (536 of
## it in view where 660 were) and moves nothing on the floor: every reveal and
## every zone from no pan is where it was, every pointed desk too, and the
## arrows stand along the narrower view. Z1 (2026-10-27): the three-lane map is
## 576 wide, wider than 536, so the far corner moves 40 right and a reveal or
## an opening from it keeps or takes that 40 (REVEAL_DRAWER, ZONES_DRAWER).
func test_a_relayout_moves_no_answer() -> void:
	var office := await _office()
	var tab: Control = office.hud.get_node("%DrawerTab")
	await _click(tab.get_global_rect().get_center())
	await _frames(2)
	_check(office.hud.drawer_open(), "a real click on the tab opens the drawer")
	_eq(office.camera.free_rect(), Rect2(96, 48, 536, 308), "the world's room stops at the open drawer")
	_eq(_far(office), Vector2(40, 556), "the far corner is 40 further right")
	for key: String in REVEAL_800:
		_eq(REVEAL_DRAWER[key].slice(0, 2), REVEAL_800[key].slice(0, 2), "%s: from no pan, as with it shut" % key)
	for key: String in ZONES_800:
		_eq(ZONES_DRAWER[key].slice(0, 2), ZONES_800[key].slice(0, 2), "%s: opened from no pan, as with it shut" % key)
	_reveals(office, REVEAL_DRAWER, "drawer open")
	await _openings(office, ZONES_DRAWER, "drawer open")
	_pointed(office, POINTER_800, "drawer open")
	_eq(
		await _arrows_at(office, Vector2.ZERO),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.3421"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4046")
		],
		"drawer open, at the top: both zones below, along the narrower view"
	)
	_eq(
		await _arrows_at(office, Vector2(0, 556)),
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2476")],
		"drawer open, at the bottom: web's far chip above"
	)
	_done(office)
