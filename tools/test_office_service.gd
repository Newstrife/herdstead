extends "res://tools/test_base.gd"
## Pure: the entry band as the plan places it and the validator walks it
## (OfficeFixturePlanner, OfficeFloorValidation, OfficeWalkGraph): two cells
## deep, the walking lane in front of the pantry counter, a corner nook nobody
## walks to or stands at; that every state sits at its seat (OfficeStation on
## a bare table, no office); and the one ranking the `N` key uses. There is no
## reception. No office.
## D2 (2026-10-27): idle sits with a mug; the pantry is a nook nobody walks to;
## the band is two cells (SEATED-Q2). Who rested where (OfficeRests) is retired
## with its spots and the fixture row.

var people: PixelPeople
## Made on first use by _pen().
var pen: OfficeDraw
## A bare world for the cases that furnish a station: freed after each case.
var world: Node2D


func _initialize() -> void:
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	run_cases()


func _marker() -> String:
	return "OFFICE SERVICE TESTS"


func _after_case() -> void:
	super()
	if is_instance_valid(world):
		world.free()


# --- the entry band ---------------------------------------------------------------


## A floor with tables planned with its fixtures, `width` cells wide.
func _serviced(floor_model: ZoneModel, width := 32, previous: FloorPlan = null) -> FloorPlan:
	var rules := _real_rules(width)
	var result := OfficeFloorLayout.plan(
		MapModel.of(floor_model), previous, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "a valid serviced floor: " + "; ".join(result.problems))
	return result.plan


## The entry band is two cells deep: the top wall's drawing clearance and the
## walking lane. A map of one zone of one pod row is 2 + 2 + 1 + the pod row's
## cells deep (the wall, the band, the zone's aisle row, the pod row: 6 cells,
## 11 in all); an empty map is still 11, and so is nothing smaller. The
## threshold is the lane's node under the door, and the first zone starts under
## the band and its aisle row.
func test_the_entry_band_is_two_cells_deep() -> void:
	var rules := _real_rules(20)
	_eq([rules.entry_cells, rules.min_height_cells], [2, 11], "the policy's entry band and smallest floor")
	_eq(OfficeShell.WALKING_LANE, 48.0, "the walking lane is the band's second row's centre")
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	_eq(plan.entry_cells, Rect2i(1, 2, 16, 2), "under the top wall, between the side walls")
	var pod := OfficeZoneLayout.pod_row_cells()
	_eq(plan.floor_cells.size.y, 2 + 2 + 1 + pod, "one pod row: 2 + 2 + 1 + %d cells" % pod)
	_eq(plan.zones[0].cells.position.y, 5, "the first zone starts under the band and its aisle row")
	# An empty workspace is a zone of one empty pod row: as deep as one table.
	_eq(_plan(_floor([])).floor_cells.size.y, 2 + 2 + 1 + pod, "an empty workspace is one pod row deep")
	var empty := OfficeFloorLayout.plan(MapModel.empty("machine"), null, _real_rules()).plan
	_eq(empty.floor_cells.size.y, 11, "an empty map (a machine with no workspace) stays 11 deep")
	var graph := _graph_of(plan, rules)
	_eq(graph.threshold, Vector2(OfficeShell.door(plan).x, 112), "the threshold is the lane's node under the door")
	_eq(graph.threshold_problem(), "", "and the door reaches it")
	for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.end.x):
		_check(graph.walkable(Vector2i(x, 3)), "the walking lane is open at column %d" % x)
		_check(not graph.walkable(Vector2i(x, 2)), "the wall's clearance is not walked at column %d" % x)


## Where the counter stands is a pure function of the plan: at the band's left
## end, its foot COUNTER_FOOT into the band (map y 106), its footprint 14 deep
## (92..106), its drawing inside the plan's bounds. The same plan twice is the
## same; a zone growing leaves it where it is; widening the map moves the lift
## door with the main corridor and leaves the counter where it was. It is the
## only fixture, and it has no spots: nobody stands at it.
func test_the_counter_stands_where_the_plan_puts_it() -> void:
	var model := _floor([_room("a", 4), _room("b", 2, 1)])
	var plan := _serviced(model, 20)
	var pantry := plan.pantry
	_check(pantry != null, "an 18-cell map has the counter")
	if pantry == null:
		return
	_eq(plan.fixtures().size(), 1, "and no other fixture")
	var width := OfficeDecor.footprint_of(_pen().art, ArtContract.PROP_PANTRY).x
	_eq(pantry.position, Vector2(32.0 + width / 2.0, 106.0), "at the band's left end, its foot at 106")
	_eq(pantry.footprint, Rect2(32, 92, width, 14), "standing on 92..106, the left wall on")
	_check(plan.render_bounds.encloses(pantry.draw_rect), "its drawing is on the map: %s" % pantry.draw_rect)
	_check(not "spots" in pantry and not "approaches" in pantry, "it has no spots: nobody stands at it")
	_eq(_serviced(model, 20).geometry_signature(), plan.geometry_signature(), "the same plan twice")
	# Ten panes: a five-desk pod, 6 cells, more than the pod row has left.
	model.rooms.append(_room("c", 10, 2))
	var grown := _serviced(model, 20, plan)
	_check(grown.zones[0].rows.size() > plan.zones[0].rows.size(), "a new pod row")
	_eq(grown.pantry.geometry_signature(), pantry.geometry_signature(), "the counter stays as it was")
	# Wide enough to widen the map: a table of 30 panes, 16 columns, 35 cells.
	var wide := _floor([_room("a", 4), _room("b", 30, 1)])
	var narrow := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 20)
	var widened := _serviced(wide, 20, narrow)
	_check(widened.lanes > narrow.lanes, "the map widened by lanes: %d -> %d" % [narrow.lanes, widened.lanes])
	var moved := widened.main_corridor_cells.position.x - narrow.main_corridor_cells.position.x
	_eq(moved, 5 * (widened.lanes - narrow.lanes), "the main corridor moves five cells a lane")
	_eq(OfficeShell.door(widened) - OfficeShell.door(narrow), Vector2(moved * 32, 0), "and the lift door with it")
	_eq(widened.pantry.geometry_signature(), narrow.pantry.geometry_signature(), "the counter stays at the left end")


## No counter where there are no desks: an empty map and an empty workspace. No
## plan has a reception.
func test_no_fixtures_without_tables() -> void:
	var cache := FloorPlanCache.new()
	var lobby := cache.prepare(MapModel.empty("machine"), _pen(), 640.0)
	_eq(lobby.fixtures().size(), 0, "an empty map has none")
	var empty := cache.prepare(MapModel.of(_floor([])), _pen(), 640.0)
	_eq(empty.fixtures().size(), 0, "nor has an empty workspace")
	var tables := cache.prepare(MapModel.of(_floor([_room("a", 2)])), _pen(), 640.0)
	_check(tables.pantry != null, "a map with a table has a pantry")
	for plan: FloorPlan in [lobby, empty, tables]:
		_check(not "reception" in plan, "a plan has no reception")
		for fixture in plan.fixtures():
			_eq([fixture.key, fixture.piece], ["pantry", ArtContract.PROP_PANTRY], "its one fixture is the pantry")


## The nook holds nobody: the placement has no spots and no approaches, the
## walk graph no fixture row, and the only FIXTURE obstacle is the counter's
## footprint inflated by the feet, with no entries (nobody walks into it).
func test_the_nook_holds_nobody() -> void:
	var rules := _real_rules(32)
	var plan := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 32)
	_check(plan.pantry != null, "the map has its counter")
	if plan.pantry == null:
		return
	for gone: String in ["spots", "approaches"]:
		_check(not gone in plan.pantry, "a FixturePlacement has no %s" % gone)
	_check(not plan.pantry.has_method("capacity"), "and holds nobody")
	var graph := _graph_of(plan, rules)
	for gone: String in ["fixture_row", "walking_lane"]:
		_check(not gone in graph, "the walk graph has no %s" % gone)
	var fixtures := graph.obstacles.filter(
		func(each: OfficeWalkGraph.Obstacle) -> bool: return each.kind == OfficeWalkGraph.Kind.FIXTURE
	)
	_eq(fixtures.size(), 1, "one FIXTURE obstacle")
	var feet := PixelPerson.footprint()
	var inflated := Rect2(plan.pantry.footprint.position - feet.end, plan.pantry.footprint.size + feet.size)
	_eq(fixtures[0].rect, inflated, "the counter's footprint inflated by the feet")
	_eq(fixtures[0].entries, PackedVector2Array(), "with no entries: nobody walks into it")


## A band whose bay left of the main corridor is narrower than the counter has
## none; one as wide has it. On hand-made plans: no real map is so narrow.
func test_a_band_too_narrow_for_the_counter_has_none() -> void:
	var planner := OfficeFixturePlanner.new(_pen())
	var width := OfficeDecor.footprint_of(_pen().art, ArtContract.PROP_PANTRY).x
	_eq(width, 64.0, "the counter stands on 64 units: two cells")
	var cases := {2: false, 3: true, 4: true}
	for corridor: int in cases:
		var plan := FloorPlan.new()
		var desk := DeskPlacement.new()
		desk.tab_key = "a"
		desk.capacity = 2
		desk.measure = OfficeTable.measure(2)
		desk.origin = Vector2(64, 480)
		plan.desks.append(desk)
		plan.floor_cells = Rect2i(0, 0, corridor + 3, 18)
		plan.entry_cells = Rect2i(1, 2, corridor + 1, 2)
		plan.main_corridor_cells = Rect2i(corridor, 2, 2, 16)
		planner.furnish(plan)
		_eq(plan.pantry != null, cases[corridor], "a corridor at column %d: the counter" % corridor)
	# A band of one cell has no walking lane under the wall's clearance.
	var shallow := FloorPlan.new()
	shallow.desks.append(DeskPlacement.new())
	shallow.floor_cells = Rect2i(0, 0, 9, 18)
	shallow.entry_cells = Rect2i(1, 2, 7, 1)
	shallow.main_corridor_cells = Rect2i(6, 2, 2, 16)
	planner.furnish(shallow)
	_eq(shallow.pantry, null, "a one-cell band: none")


## The validator treats the counter as furniture with a place of its own: it
## stands only in the band's bay, so one moved out of its corner over a
## table's approach is refused (as a decoration standing in a walkway is) and
## the plan leaves it out (test_a_fixture_that_fails_is_left_out); nothing is
## ever said about spots or legs, which it has none of; back in its corner all
## is well.
func test_the_validator_treats_the_counter_as_furniture() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	_eq(OfficeFloorLayout.validate(plan, rules), PackedStringArray(), "the serviced floor validates")
	var placed := plan.desks[0]
	var approach := placed.origin + placed.measure.approach_position(0, "far")
	var pantry := plan.pantry
	var stands := pantry.footprint
	pantry.footprint = Rect2(approach - Vector2(20, 8), Vector2(40, 12))
	var problems := OfficeFloorLayout.validate(plan, rules)
	_eq(
		problems,
		PackedStringArray(["fixture: pantry stands outside the entry band's bay"]),
		"a counter over an approach is refused where it stands"
	)
	# Grown down over the lane and past the band's end (BreakingFixtures' shape):
	# refused the same way, and never as a spot's problem.
	pantry.footprint = Rect2(stands.position, Vector2(stands.size.x, 60))
	problems = OfficeFloorLayout.validate(plan, rules)
	_check(
		problems.has("fixture: pantry stands outside the entry band's bay"), "over the lane: refused: %s" % [problems]
	)
	for problem in problems:
		_check(not problem.contains("leg") and not problem.contains("pantry approach"), "no spot problems: " + problem)
	pantry.footprint = stands
	_eq(OfficeFloorLayout.validate(plan, rules), PackedStringArray(), "and all is well again")


## The lane under the counter is walked: every node on it from the left wall to
## the main corridor is walkable and joined to the next, the counter's inflated
## footprint ends short of its centres, and the way in from the door to a table
## in the first lane runs along it.
func test_the_lane_under_the_counter_is_walked() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 2), _room("b", 2, 1)]), 20)
	var graph := _graph_of(plan, rules)
	var corridor := plan.main_corridor_cells.position.x
	for x in range(plan.entry_cells.position.x, corridor):
		_check(graph.walkable(Vector2i(x, 3)), "the lane's node at column %d is walked" % x)
		_check(graph.linked(Vector2i(x, 3), OfficeWalkGraph.RIGHT), "and joined to the next at column %d" % x)
	var feet := PixelPerson.footprint()
	_check(plan.pantry.footprint.end.y + feet.size.y < 112.0, "the counter with the feet ends short of y 112")
	var first := plan.desks[0]
	for desk in plan.desks:
		if desk.origin.x < first.origin.x:
			first = desk
	var approach := first.origin + first.measure.approach_position(0, "far")
	var route := graph.from_door(OfficeWalkGraph.cell_of(approach))
	_check(not route.is_empty(), "the door reaches the first lane's far approach")
	var on_lane := 0
	for point in route:
		on_lane += int(point.y == 112.0)
	_check(on_lane >= 2, "the way in runs along the lane: %s" % route)
	_check(graph.clear_route(route), "and is clear")


## The furnished map is validated once; what fails is left out, never a desk:
## the furniture first, then the pantry, at most three validations. A broken
## pantry takes all three: with everything, without the furniture (the pantry
## still breaks it), without both.
func test_a_fixture_that_fails_is_left_out() -> void:
	var rules := _real_rules(32)
	var model := _floor([_room("a", 4), _room("b", 2, 1)])
	var before := OfficeFloorValidation.validations
	var fine := OfficeFloorLayout.plan(
		MapModel.of(model), null, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(OfficeFloorValidation.validations - before, 1, "one validation, the pantry and furniture included")
	_check(fine.plan != null and fine.plan.pantry != null and not fine.plan.decorations.is_empty(), "all of them")
	var planner := BreakingFixtures.new(_pen())
	before = OfficeFloorValidation.validations
	var result := OfficeFloorLayout.plan(MapModel.of(model), null, rules, OfficeDecorPlanner.new(_pen()), planner)
	var spent := OfficeFloorValidation.validations - before
	_eq(result.problems, PackedStringArray(), "a broken pantry leaves the floor valid")
	if result.plan == null:
		return
	_eq(result.plan.desks.size(), 2, "with its desks")
	_eq(result.plan.pantry, null, "without the pantry")
	_eq(spent, 3, "in three validations")
	_check(result.plan.decorations.is_empty(), "the furniture went first")


## A pantry whose counter reaches across the walking lane (see
## test_a_fixture_that_fails_is_left_out).
class BreakingFixtures:
	extends OfficeFixturePlanner

	func furnish(next: FloorPlan) -> void:
		super.furnish(next)
		if next.pantry != null:
			var stands := next.pantry.footprint
			next.pantry.footprint = Rect2(stands.position.x, stands.position.y, stands.size.x, 60)


# --- every state sits ----------------------------------------------------------


## A pane with an agent in `state` at `since` (-1: unknown), `key` its pane key.
func _agent(key: String, state: String, since := -1.0, starting := false) -> PaneModel:
	var pane := _pane(key)
	pane.provider = "claude"
	pane.state = state
	pane.state_since = since
	pane.starting = starting
	return pane


## One ranking for `N`: an unknown start first, as
## having waited longest, then the earliest start; ties, and the unknown among
## themselves, in projection order. Forty agents that went idle in the same
## snapshot rank in projection order.
func test_whoever_waited_longest_goes_first() -> void:
	var panes: Array[PaneModel] = [
		_agent("a", "idle", 300.0),
		_agent("b", "idle"),
		_agent("c", "idle", 100.0),
		_agent("d", "idle", 200.0),
		_agent("e", "idle"),
		_agent("f", "idle", 100.0)
	]
	var order := OfficeProjection.wait_order(panes).map(func(pane: PaneModel) -> String: return pane.key)
	_eq(order, ["b", "e", "c", "f", "d", "a"], "unknown first, then the earliest; ties in projection order")
	var tied: Array[PaneModel] = []
	for index in 40:
		tied.append(_agent("t%02d" % (39 - index), "idle", 500.0))
	var same := OfficeProjection.wait_order(tied).map(func(pane: PaneModel) -> String: return pane.key)
	_eq(same, tied.map(func(pane: PaneModel) -> String: return pane.key), "forty at once stand as projected")


## Every state sits at the seat, through OfficeStation.furnish() on a bare
## table: working, starting (whatever its status), unknown, done, blocked and
## idle all sit at the desk (AvatarLook.DESK, at the seat's own point), and
## what the desk shows beside the laptop is the state's: the paper for done,
## the mug for idle, nothing otherwise; a shell has nobody and nothing.
func test_every_state_sits() -> void:
	var table := _bare_table(4)
	var cases := [
		["working", ArtContract.STATE_WORKING, false, &""],
		["starting", ArtContract.STATE_BLOCKED, true, &""],
		["starting idle", ArtContract.STATE_IDLE, true, &""],
		["unknown", &"unknown", false, &""],
		["done", ArtContract.STATE_DONE, false, ArtContract.PROP_DONE_STACK_SMALL],
		["blocked", ArtContract.STATE_BLOCKED, false, &""],
		["idle", ArtContract.STATE_IDLE, false, ArtContract.PROP_IDLE_MUG],
	]
	for side: String in OfficeTable.SIDES:
		var station := _pen().station(world, table, 1, side)
		for each: Array in cases:
			var what: String = "%s %s" % [side, each[0]]
			var state: StringName = each[1]
			var starting: bool = each[2]
			station.furnish("claude", state, false, starting)
			var worker := station.actor()
			_check(worker != null, what + ": somebody is there")
			if worker == null:
				continue
			_eq([worker.look.context, worker.position], [AvatarLook.DESK, Vector2.ZERO], what + ": at the desk")
			_eq(table.item_piece(1, side), each[3], what + ": what the desk shows")
			_eq(table.item(1, side).visible, each[3] != &"", what + ": shown or not")
		station.furnish("", ArtContract.STATE_IDLE)
		_eq(station.actor(), null, side + " shell: nobody in the chair")
		_eq(table.item_piece(1, side), &"", side + " shell: nothing beside the laptop")
		station.vacate()
		_eq([table.item_piece(1, side), table.item(1, side).visible], [&"", false], side + " vacant: nothing")


## The door's field reaches every approach of every table across the band,
## and from_door() reads a route in from the door to each: on a map of
## several zones, partitions and all, 20 and 32 cells asked. What to_lane() /
## from_lane() proved for the pantry's walkers, every walk in from the door
## needs.
func test_the_doors_field_reaches_every_approach_across_the_band() -> void:
	for width: int in [20, 32]:
		var rules := _real_rules(width)
		var zones: Array[ZoneModel] = [
			_zone("machine/1", 1, [_room("a", 4), _room("b", 2, 1), _room("c", 2, 2)]),
			_zone("machine/2", 2, [_room("d", 6)]),
			_zone("machine/3", 3, [_room("e", 2), _room("f", 8, 1)]),
		]
		var result := OfficeFloorLayout.plan(
			MapModel.of_zones("machine", zones),
			null,
			rules,
			OfficeDecorPlanner.new(_pen()),
			OfficeFixturePlanner.new(_pen())
		)
		_eq(result.problems, PackedStringArray(), "%d cells: a valid map of three zones" % width)
		if result.plan == null:
			continue
		var plan := result.plan
		var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
		var count := 0
		for placed in plan.desks:
			for column in placed.capacity:
				for side: String in OfficeTable.SIDES:
					var cell := OfficeWalkGraph.cell_of(placed.origin + placed.measure.approach_position(column, side))
					var named := "%d cells, %s %d %s" % [width, placed.tab_key, column, side]
					var route := graph.from_door(cell)
					_check(route.size() >= 2 and route[0] == graph.door, named + ": in from the door")
					_check(route[1] == graph.threshold, named + ": over the threshold on the lane")
					_check(route[route.size() - 1] == OfficeWalkGraph.centre(cell), named + ": to the approach's node")
					_check(graph.clear_route(route), named + ": clear")
					count += 1
		_check(count >= 30, "%d cells: every approach: %d" % [width, count])


## The `N` key visits a floor's blocked agents longest-waiting first, then its
## UNREAD in the same waiting order. D2 (2026-10-27): idle sits with a mug; the
## pantry is a nook nobody walks to: nothing else shares the ranking, and
## "every one of them at their seat" is every state's now (test_every_state_sits).
func test_n_follows_the_wait_order() -> void:
	var room := _room("a")
	var blocked: Array[PaneModel] = []
	for index in 8:
		var agent := _agent("b%d" % index, "blocked", -1.0 if index % 3 == 0 else 50.0 * (8 - index))
		room.panes.append(agent)
		blocked.append(agent)
	room.panes.append(_agent("d0", "done", 20.0))
	room.panes.append(_agent("d1", "done"))
	var floor_model := _floor([room])
	var building := BuildingModel.new()
	building.zones.append(floor_model)
	var buildings: Array[BuildingModel] = [building]
	var order := OfficeProjection.attention_queue(buildings)
	var waited := OfficeProjection.wait_order(blocked).map(func(pane: PaneModel) -> String: return pane.key)
	_eq(order.slice(0, 8), waited, "N walks the blocked longest-waiting first")
	_eq(waited.slice(0, 3), ["b0", "b3", "b6"], "the unknown starts first")
	_eq(order.slice(8), ["d1", "d0"], "then UNREAD, the unknown start first")


## A map without the counter (a band too narrow for it) seats everyone just
## as one with it: every state sits, the idle too, and the walk graph is the
## same but for the counter's obstacle.
func test_everyone_sits_with_or_without_the_counter() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 4)]), 20)
	var with_counter := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
	var kinds := with_counter.obstacles.map(func(each: OfficeWalkGraph.Obstacle) -> int: return each.kind)
	plan.pantry = null
	var bare := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
	var bare_kinds := bare.obstacles.map(func(each: OfficeWalkGraph.Obstacle) -> int: return each.kind)
	_eq(kinds.count(OfficeWalkGraph.Kind.FIXTURE), 1, "with the counter: one FIXTURE obstacle, the counter")
	_eq(bare_kinds.count(OfficeWalkGraph.Kind.FIXTURE), 0, "without it: none, no row barrier either")
	kinds.erase(OfficeWalkGraph.Kind.FIXTURE)
	_eq(bare_kinds, kinds, "without the counter: the same obstacles less its one")
	var table := _bare_table(4)
	for state: StringName in [
		ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_DONE, ArtContract.STATE_IDLE
	]:
		var station := _pen().station(world, table, 0, "far")
		station.furnish("claude", state)
		_eq(
			[station.actor().look.context, station.actor().position],
			[AvatarLook.DESK, Vector2.ZERO],
			"%s: seated, counter or not (no station asks the plan)" % state
		)
		station.free()


## Every map with desks has the walking lane in front of the counter, and the
## threshold stands on it, whether or not the counter stands there: (the
## door's column, 112), the door's clearance above it never walked. A map
## without desks (an empty workspace, an empty map) has no counter either.
func test_the_threshold_stands_on_the_lane_with_or_without_the_counter() -> void:
	var rules := _real_rules(32)
	var served := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 32)
	var bare := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 32)
	bare.pantry = null
	for plan: FloorPlan in [served, bare]:
		var what := "with the counter" if plan.pantry != null else "without it"
		var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
		_eq(graph.threshold, Vector2(OfficeShell.door(plan).x, 112), what + ": the threshold on the lane")
		_eq(graph.threshold_problem(), "", what + ": the door reaches it")
		for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.position.x):
			_check(graph.walkable(Vector2i(x, 3)), "%s: the walking lane at column %d is open" % [what, x])
		var along := graph.route_between(
			Vector2i(1, 3),
			[Vector2i(plan.main_corridor_cells.position.x - 1, 3)] as Array[Vector2i],
			PackedFloat32Array([0.0]),
			PackedInt32Array([-1]),
			100000,
			1000
		)
		_check(not along.points.is_empty(), what + ": a walk along the band")
		for point in along.points:
			_eq(point.y, 112.0, "%s: runs on the lane: %s" % [what, point])
	var empty := _plan(_floor([]))
	_eq(empty.fixtures().size(), 0, "a map without desks has no counter")


## At the shipped plan width (the default window's 772 units, 24 cells, and
## 25: four lanes, a map 23 cells wide) the counter is the band's one fixture,
## in its corner from the left wall at 32, well short of the main corridor at
## 640, and the band's lane runs from it to the door.
func test_the_counter_is_the_only_fixture_at_twenty_three_cells() -> void:
	var plan := _serviced(_floor([_room("a", 2)]), 25)
	_eq([plan.lanes, plan.floor_cells.size.x, plan.main_corridor_cells.position.x], [4, 23, 20], "four lanes, 23 cells")
	_eq(plan.fixtures().size(), 1, "one fixture")
	_eq([plan.pantry.key, plan.pantry.footprint.position.x], ["pantry", 32.0], "the counter from the left wall")
	_check(plan.pantry.footprint.end.x < 640.0, "short of the main corridor")
	var graph := _graph_of(plan, _real_rules(25))
	var along := graph.from_door(Vector2i(1, 3))
	_check(not along.is_empty() and along[along.size() - 1] == Vector2(48, 112), "the door reaches the lane's end")


## The counter clears the lane at every furnished width (FloorPlanCache's
## FURNISHED_WIDTHS as the layout suite asks them): its footprint grown by the
## feet ends short of the lane's node centres (y 112), the node in front of
## its middle is walked and joined both ways, and the threshold is on the lane.
func test_the_counter_clears_the_lane_at_every_shipped_width() -> void:
	var feet := PixelPerson.footprint()
	for width: int in [11, 20, 24, 32, 60]:
		var rules := _real_rules(width)
		var plan := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), width)
		if plan == null or plan.pantry == null:
			_check(false, "%d cells: a counter" % width)
			continue
		var grown_end := plan.pantry.footprint.end.y + feet.end.y + feet.size.y
		_check(grown_end < 112.0, "%d cells: the counter and the feet end at %s, short of 112" % [width, grown_end])
		var graph := _graph_of(plan, rules)
		var front := OfficeWalkGraph.cell_of(Vector2(plan.pantry.position.x, 112))
		_check(graph.walkable(front), "%d cells: the lane's node in front of it is walked" % width)
		_check(
			graph.linked(front, OfficeWalkGraph.LEFT) and graph.linked(front, OfficeWalkGraph.RIGHT),
			"%d cells: and joined both ways" % width
		)
		_eq(graph.threshold.y, 112.0, "%d cells: the threshold on the lane" % width)


# --- helpers --------------------------------------------------------------------


## A room "a" holding exactly `panes`, as a plan seats them.
func _room_of(panes: Array[PaneModel]) -> RoomModel:
	var room := _room("a")
	room.panes.assign(panes)
	return room


func _pane(key: String, x := -1, side := "far", order := -1) -> PaneModel:
	var pane := PaneModel.new()
	pane.key = key
	pane.pane_id = key
	pane.explicit_layout = x >= 0
	pane.table_x = x
	pane.side = side
	pane.layout_order = order
	return pane


func _room(key: String, count := 0, number := 0) -> RoomModel:
	var room := RoomModel.new()
	room.key = key
	room.tab_id = key
	room.number = number
	for index in count:
		room.panes.append(_pane("%s-%03d" % [key, index]))
	return room


func _floor(rooms: Array[RoomModel]) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = "machine/workspace"
	floor_model.rooms = rooms
	return floor_model


## A workspace `key` numbered `number` with `rooms`: one zone of a map.
func _zone(key: String, number: int, rooms: Array[RoomModel]) -> ZoneModel:
	var zone := _floor(rooms)
	zone.key = key
	zone.number = number
	return zone


func _plan(floor_model: ZoneModel) -> FloorPlan:
	var rules := _real_rules()
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules)
	_eq(result.problems, PackedStringArray(), "valid plan: " + "; ".join(result.problems))
	return result.plan


## The shipped pack's pen, made once: the planners measure its props with it.
func _pen() -> OfficeDraw:
	if pen == null:
		pen = OfficeDraw.new(ArtPack.from_manifest("res://assets/daylight/manifest.json"))
	return pen


func _real_rules(width := 32) -> FloorLayoutPolicy:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = width
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	return rules


func _graph_of(plan: FloorPlan, rules: FloorLayoutPolicy) -> OfficeWalkGraph:
	return OfficeWalkGraph.of(plan, rules.actor_footprint, rules.actor_draw_rect)


## A bare pod of `capacity` columns in a fresh world (freed after the case),
## for the cases that furnish a station without an office.
func _bare_table(capacity: int) -> OfficeTable:
	world = Node2D.new()
	var ground := Node2D.new()
	world.add_child(ground)
	root.add_child(world)
	var measured := OfficeTable.measure(capacity)
	return _pen().table(world, ground, "Bare", Vector2(160, 240), measured.table_width, measured.columns)
