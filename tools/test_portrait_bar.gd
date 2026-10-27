extends "res://tools/office_test_base.gd"
## The top bar's portrait strip (S3 BAR-a): who gets a card and in what order
## (PortraitBarModel.of(): the blocked in `N`'s order, the done oldest first,
## the working and the idle in place order), the fold ladder
## (PortraitBarModel.fit()), and the cards themselves: words within their
## width, a pool that keeps its nodes, the zone tag in its group's carpet
## family, the seat's person standing still, the state's frame and the
## selection's ring, no key reaching a card, and a hover pointing at the desk.
## Hovers, clicks and keys go through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_portrait_bar.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## The pack's states, as the projection is told them.
const STATES := ["working", "blocked", "done", "idle", "unknown"]
## The widths the ladder's table in the spec is worked out with (A.2): a card,
## a face, a fold, a tally, the gap.
const METRICS := [86.0, 20.0, 40.0, 24.0, 2.0]
## The strip's room at 960, 800, 640 and 480 units, plain window (A.2).
const ROOMS: Array[float] = [573.0, 413.0, 253.0, 208.0]


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("portrait-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	fixture = _snapshot_of("res://tools/fixtures/snapshot_floors.json")
	if fixture.is_empty():
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "PORTRAIT BAR TESTS"


# --- cases --------------------------------------------------------------------


## snapshot_floors on one machine: the blocked stand in exactly the order `N`
## walks them (OfficeNavigator.waiting()), infra:p1 first, blocked longer; the
## done after them, the oldest UNREAD first; then the working and the idle in
## place order (api's zone, web's, infra's, data's: herdr's numbers). On two
## machines the blocked interleave by their waits, and with nobody's start
## known the projection's order (Local's zones, then bee's) breaks the tie.
func test_the_cards_stand_in_n_order_then_done_working_idle() -> void:
	var frame := _frame_of([_view(LOCAL, "Local", fixture, false)])
	_since(frame, LOCAL, "infra:p1", 100.0)
	_since(frame, LOCAL, "web:p1", 200.0)
	_since(frame, LOCAL, "web:p2", 300.0)
	_since(frame, LOCAL, "infra:p2", 50.0)
	var model := PortraitBarModel.of(frame, "")
	_eq(_keys(model, PortraitBarModel.Group.BLOCKED), _waiting(frame, "blocked"), "the blocked in N's order")
	_eq(
		_keys(model, PortraitBarModel.Group.BLOCKED),
		[_pane("infra:p1"), _pane("web:p1")],
		"infra:p1 first: it has waited longer"
	)
	_eq(
		_keys(model, PortraitBarModel.Group.DONE),
		_waiting(frame, "done"),
		"the done in N's order once nobody is blocked"
	)
	_eq(_keys(model, PortraitBarModel.Group.DONE), [_pane("infra:p2"), _pane("web:p2")], "the oldest UNREAD first")
	_eq(
		_keys(model, PortraitBarModel.Group.WORKING),
		[_pane("api:p1"), _pane("api:p4"), _pane("data:p1")],
		"working in place order"
	)
	_eq(_keys(model, PortraitBarModel.Group.IDLE), [_pane("api:p2"), _pane("infra:p3")], "idle in place order")
	var groups: Array[int] = []
	for card in model.cards:
		groups.append(card.group)
	var sorted := groups.duplicate()
	sorted.sort()
	_eq(groups, sorted, "blocked, then done, then working, then idle: %s" % [groups])
	_eq(
		[
			model.counts[PortraitBarModel.Group.BLOCKED],
			model.counts[PortraitBarModel.Group.DONE],
			model.counts[PortraitBarModel.Group.WORKING],
			model.counts[PortraitBarModel.Group.IDLE]
		],
		[2, 2, 3, 2],
		"two, two, three, two"
	)
	_check(
		model.cards.all(func(card: PortraitBarModel.Card) -> bool: return card.machine_label.is_empty()),
		"one machine: none named"
	)
	var two := _frame_of([_view(LOCAL, "Local", fixture, false), _view(BEE, "bee", fixture, false)])
	_since(two, BEE, "infra:p1", 50.0)
	_since(two, LOCAL, "web:p1", 100.0)
	_since(two, BEE, "web:p1", 150.0)
	var both := PortraitBarModel.of(two, "")
	var blocked := [
		_pane("infra:p1"), HerdrFleet.pane_key(BEE, "infra:p1"), _pane("web:p1"), HerdrFleet.pane_key(BEE, "web:p1")
	]
	_eq(_keys(both, PortraitBarModel.Group.BLOCKED), _waiting(two, "blocked"), "two machines: still N's order")
	_eq(
		_keys(both, PortraitBarModel.Group.BLOCKED),
		blocked,
		"Local's unknown start first, then by wait across the machines"
	)
	var done := [
		_pane("web:p2"), _pane("infra:p2"), HerdrFleet.pane_key(BEE, "web:p2"), HerdrFleet.pane_key(BEE, "infra:p2")
	]
	_eq(_keys(both, PortraitBarModel.Group.DONE), done, "no start known: the projection's order breaks the tie")
	var working := [_pane("api:p1"), _pane("api:p4"), _pane("data:p1")]
	for pane_id: String in ["api:p1", "api:p4", "data:p1"]:
		working.append(HerdrFleet.pane_key(BEE, pane_id))
	_eq(_keys(both, PortraitBarModel.Group.WORKING), working, "working: Local's places, then bee's")
	_eq(both.cards[1].machine_label, "bee", "among several machines a card names its machine")


## Who gets no card: a shell, an agent herdr is still launching that does not
## ask (api:p2 idle, data:p2), and every pane of a machine that is not
## answering (bee). A blocked agent still starting is BLOCKED; a state the
## pack does not draw is IDLE; a pane no zone seats has a card with an
## unnamed space and no group.
func test_only_agents_of_live_machines_get_cards() -> void:
	var loose := _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	loose = _with(loose, "api:p1", {"agent_status": "blocked", "launch_pending": true})
	loose = _with(loose, "api:p2", {"launch_pending": true})
	loose = _with(loose, "infra:p3", {"agent_status": "unknown"})
	var frame := _frame_of([_view(LOCAL, "Local", loose, false), _view(BEE, "bee", fixture, true)])
	var model := PortraitBarModel.of(frame, "")
	var keys: Array[String] = []
	for card in model.cards:
		keys.append(card.key)
	_check(keys.all(func(key: String) -> bool: return key.begins_with(LOCAL)), "nothing of bee's: %s" % [keys])
	for shell: String in ["api:p3", "web:p3", "notes:p1"]:
		if shell != "notes:p1":
			_check(not keys.has(_pane(shell)), "%s is a shell: no card" % shell)
	_check(not keys.has(_pane("api:p2")), "an idle agent herdr still launches: no card")
	_check(not keys.has(_pane("data:p2")), "nor data:p2")
	var starting := _card(model, _pane("api:p1"))
	_check(
		starting != null and starting.group == PortraitBarModel.Group.BLOCKED,
		"a blocked agent still starting is blocked"
	)
	if starting != null:
		_check(not starting.starting, "and drawn as it is at its seat: blocked, not starting")
	var unknown := _card(model, _pane("infra:p3"))
	_check(unknown != null and unknown.group == PortraitBarModel.Group.IDLE, "a state the pack does not draw is idle")
	if unknown != null:
		_eq(unknown.state, "unknown", "herdr's word kept")
	var unseated := _card(model, _pane("notes:p1"))
	_check(unseated != null and unseated.group == PortraitBarModel.Group.BLOCKED, "a pane no zone seats has its card")
	if unseated != null:
		_eq([unseated.place, unseated.zone_key, unseated.group_key], ["?", "", ""], "no space, no zone, no group")
	_eq(model.counts[PortraitBarModel.Group.BLOCKED], 4, "web:p1, infra:p1, api:p1 and notes:p1")
	_eq(keys.size(), 4 + 2 + 2 + 1, "four blocked, two done, two working, one idle")


## The spec's table (A.2): four fleets at the strip's room at 960, 800, 640 and
## 480 units take exactly these rungs, forms, blocked shown and widths; and the
## scene measures those rooms and those widths.
func test_the_fold_ladder_takes_the_first_rung_that_fits() -> void:
	var metrics := _metrics()
	# fleet (b/d/w/i) -> per room: [rung, faces_shown, needed]
	var table: Dictionary[String, Array] = {
		"2/2/3/2": [[2, 2, 434.0], [3, 2, 302.0], [4, 2, 170.0], [4, 2, 170.0]],
		"1/1/2/2": [[1, 1, 526.0], [2, 1, 258.0], [3, 1, 192.0], [3, 1, 192.0]],
		"3/6/22/18": [[3, 3, 478.0], [4, 3, 280.0], [5, 3, 190.0], [5, 3, 190.0]],
		"12/10/20/11": [[4, 12, 566.0], [5, 12, 388.0], [7, 6, 234.0], [7, 4, 190.0]],
	}
	var forms: Dictionary[int, Array] = {
		1:
		[
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD
		],
		2:
		[
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		3:
		[
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		4:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		5:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		6:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY
		],
		7:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY
		],
	}
	for fleet: String in table:
		var counts := _counts(fleet)
		for index in ROOMS.size():
			var wanted: Array = table[fleet][index]
			var made := PortraitBarModel.fit(counts, metrics, ROOMS[index])
			var where := "%s at %d" % [fleet, ROOMS[index]]
			_eq([made.rung, made.faces_shown, made.needed], wanted, where)
			var rung: int = wanted[0]
			_eq(_forms(made), forms[rung], "%s: rung %d's forms" % [where, rung])
	# The scene: its widths, and the room it leaves the strip.
	var hud := await _bare_hud(Vector2(960, 480))
	var scene := hud.bar.metrics()
	_eq([scene.card, scene.face, scene.fold, scene.tally, scene.gap], METRICS, "the scene measures the table's widths")
	var strip: Control = hud.bar.get_node("%Strip")
	var widths: Array[float] = [960.0, 800.0, 640.0, 480.0]
	for index in widths.size():
		hud.fit(Vector2(widths[index], 480.0 if widths[index] > 480.0 else 320.0))
		await _frames(2)
		_eq(strip.size.x, ROOMS[index], "the strip's room at %d" % widths[index])
	hud.free()


## For every room from the four tallies' 102 to 1200, on the four fleets and a
## fleet of blocked alone: what the rung needs fits; every agent is shown or
## folded, once; on the last rung the faces are the first k blocked and the
## rest are the blocked tally; and a wider room never shows fewer agents.
func test_the_ladder_never_hides_the_longest_waiting_blocked() -> void:
	var metrics := _metrics()
	for fleet: String in ["2/2/3/2", "1/1/2/2", "3/6/22/18", "12/10/20/11", "40/0/0/0", "0/3/50/50"]:
		var counts := _counts(fleet)
		var agents := 0
		for group: PortraitBarModel.Group in counts:
			agents += counts[group]
		var shown_before := -1
		var broken := 0
		for room in range(102, 1201):
			var made := PortraitBarModel.fit(counts, metrics, float(room))
			var shown := 0
			var folded := 0
			for group in PortraitBarModel.GROUPS:
				var on := made.shown_of(group, counts[group])
				shown += on
				folded += counts[group] - on
			var ok := made.needed <= float(room) and shown + folded == agents and shown >= shown_before
			if made.rung == PortraitBarModel.LAST_RUNG and counts[PortraitBarModel.Group.BLOCKED] > 0:
				ok = ok and made.forms[PortraitBarModel.Group.BLOCKED] == PortraitBarModel.Form.FACE
				ok = (
					ok
					and (
						made.shown_of(PortraitBarModel.Group.BLOCKED, counts[PortraitBarModel.Group.BLOCKED])
						== made.faces_shown
					)
				)
			if not ok and broken < 3:
				broken += 1
				_fail(
					"%s at %d: rung %d needs %s, shows %d of %d" % [fleet, room, made.rung, made.needed, shown, agents]
				)
			shown_before = shown
		_check(broken == 0, "%s holds at every room from 102 to 1200" % fleet)
	# The bar gives the first k blocked the faces, in N's order: the longest waits.
	var office := await _live_office(_many_blocked(12))
	office.test_screen = Vector2(480, 320)
	office.refresh()
	await _frames(2)
	var bar := office.hud.bar
	var order := _waiting(office.frame, "blocked")
	var faces: Array[String] = []
	for card in bar.cards():
		faces.append(card.key)
	_eq(bar.fitted().rung, PortraitBarModel.LAST_RUNG, "fourteen blocked at 480 take the last rung")
	_eq(faces, order.slice(0, faces.size()), "the faces are the first of N's order")
	_check(bar.fold_of(PortraitBarModel.Group.BLOCKED).tallied(), "and the rest a tally")
	_eq(
		bar.fold_of(PortraitBarModel.Group.BLOCKED).count_text(),
		"+%d" % (order.size() - faces.size()),
		"counting the blocked who have no face"
	)
	_done(office)


## A card at 2x in the shipped pack: a seven-glyph CJK name whole, a long
## English task cut with an ellipsis and whole in the tooltip, a blocked
## card's place and its hour-long wait (`api`, `1h 05m+`) both whole, a done
## card with no wait; every label inside its card.
func test_a_card_says_name_place_and_wait_within_its_width() -> void:
	var hud := await _bare_hud(Vector2(960, 480))
	var model := PortraitBarModel.new()
	model.counts = {
		PortraitBarModel.Group.BLOCKED: 2,
		PortraitBarModel.Group.DONE: 1,
		PortraitBarModel.Group.WORKING: 0,
		PortraitBarModel.Group.IDLE: 0
	}
	model.cards = [
		_made("Local:a", PortraitBarModel.Group.BLOCKED, "整理舰队的日志", "api"),
		_made("Local:b", PortraitBarModel.Group.BLOCKED, "refactor the fleet", "api"),
		_made("Local:c", PortraitBarModel.Group.DONE, "tests", "web"),
	]
	hud.bar.show_portraits(model, 3)
	hud.bar.show_waits({"Local:a": "12m", "Local:b": "1h 05m+"})
	await _frames(2)
	_eq(hud.bar.fitted().rung, 1, "three cards fit at 960")
	var cjk := hud.bar.card_for("Local:a")
	var long := hud.bar.card_for("Local:b")
	var done := hud.bar.card_for("Local:c")
	_check(cjk != null and long != null and done != null, "each has its card")
	if cjk == null or long == null or done == null:
		hud.free()
		return
	_check(_fits_label(_label(cjk, "%Name")), "a seven-glyph CJK name is whole")
	var name_label := _label(long, "%Name")
	_check(not _fits_label(name_label), "`refactor the fleet` does not fit its 60 units")
	_eq(name_label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "so it ends in an ellipsis")
	_eq(name_label.text, "refactor the fleet", "the label keeps the whole text")
	_check(long.get_tooltip(Vector2.ZERO).begins_with("refactor the fleet\n"), "and the tooltip says it whole")
	_check(_fits_label(_label(long, "%Place")), "`api` is whole")
	var wait := _label(long, "%Wait")
	_check(wait.visible and wait.text == "1h 05m+", "the hour-long wait shows: `%s`" % wait.text)
	_check(_fits_label(wait), "and whole")
	_check(not _label(done, "%Wait").visible, "a done card says no wait")
	for card: PortraitCard in [cjk, long, done]:
		var rect := card.get_global_rect()
		for path: String in ["%Name", "%Place", "%Wait"]:
			var label := _label(card, path)
			if label.is_visible_in_tree():
				_check(rect.encloses(label.get_global_rect()), "%s %s inside its card" % [card.key, path])
		_check(rect.encloses((card.get_node("%Tag") as Control).get_global_rect()), "%s: its tag too" % card.key)
	hud.free()


## A refresh keeps every card's node; a new order moves them; a pane that
## folds gives its node back to the pool, hidden, never freed, and the next
## pane shown takes it; the pool never holds more cards than were ever shown.
func test_cards_are_pooled_and_a_refresh_keeps_them() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var ids := _card_ids(bar)
	var most := ids.size()
	_check(most >= 4, "the fixture shows cards at 800: %s" % [ids.keys()])
	_feed(office, fixture)
	await _frames(1)
	_eq(_card_ids(bar), ids, "a refresh keeps every node")
	# infra:p1 blocks again from now: web:p1 has waited longer.
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	_feed(office, fixture)
	await _frames(1)
	var keys: Array[String] = []
	for card in bar.cards():
		keys.append(card.key)
	_eq(keys.slice(0, 2), [_pane("web:p1"), _pane("infra:p1")], "web:p1 now first")
	_eq(_card_ids(bar), ids, "the same nodes, moved")
	office.test_screen = Vector2(480, 320)
	office.refresh()
	await _frames(2)
	var kept := _card_ids(bar)
	for key: String in ids:
		if not kept.has(key):
			var node := instance_from_id(ids[key])
			_check(is_instance_valid(node), "%s's node is kept" % key)
			if is_instance_valid(node):
				var card := node as PortraitCard
				_check(not card.visible and card.key.is_empty(), "%s's node is pooled, hidden" % key)
	_eq(bar.cards().size() + bar.cards_pooled().size(), most, "no node made or freed")
	office.test_screen = Vector2(1920, 480)
	office.refresh()
	await _frames(2)
	most = maxi(most, bar.cards().size())
	_eq(bar.cards().size(), 9, "every agent has a card at 1920")
	_check(bar.cards_pooled().is_empty(), "the pool gave its nodes back")
	_check(bar.cards().size() + bar.cards_pooled().size() <= most, "never more nodes than were ever shown")
	_done(office)


## A card's tag wears its worktree group's carpet family (the sign's and the
## carpet's index, OfficeZoneSign.accent_of()): a mezzanine's tag is its
## source zone's; a pane no zone seats shows no tag.
func test_the_zone_tag_wears_its_groups_carpet_family() -> void:
	var worktrees := _snapshot_of("res://tools/fixtures/snapshot_worktrees.json")
	var office := await _live_office(worktrees, Vector2(1920, 480))
	var bar := office.hud.bar
	var source := ""
	var mezzanines := 0
	for card in bar.cards():
		var shown := card.shown_card()
		var tag: Panel = card.get_node("%Tag")
		_check(not shown.group_key.is_empty() and tag.visible, "%s is seated: a tag" % card.key)
		_eq(tag.theme_type_variation, StringName("CarpetTag%d" % OfficeZoneSign.accent_of(shown.group_key)), card.key)
		var zone := office.frame.find_zone(shown.zone_key)
		if zone != null and not zone.zone_model.mezzanine_of.is_empty():
			mezzanines += 1
			_eq(shown.group_key, zone.zone_model.mezzanine_of, "%s: a mezzanine's group is its source" % card.key)
			source = zone.zone_model.mezzanine_of
	_check(mezzanines >= 2, "the fixture's two lanes sit on mezzanines")
	var hs := bar.card_for(HerdrFleet.pane_key(LOCAL, "hs:p1"))
	var lane := bar.card_for(HerdrFleet.pane_key(LOCAL, "hud:p1"))
	_check(hs != null and lane != null, "the repo's own space and its lane both have cards")
	if hs != null and lane != null:
		_eq(source, hs.shown_card().zone_key, "the lanes hang under the repo's own space")
		_eq(
			(lane.get_node("%Tag") as Panel).theme_type_variation,
			(hs.get_node("%Tag") as Panel).theme_type_variation,
			"so a lane's tag is its source's"
		)
	_done(office)
	var loose := _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	var other := await _live_office(loose, Vector2(1920, 480))
	var unseated := other.hud.bar.card_for(_pane("notes:p1"))
	_check(unseated != null, "the unseated pane has a card")
	if unseated != null:
		_check(not (unseated.get_node("%Tag") as Panel).visible, "and no tag")
	_done(other)


## A card's face is the seat's person: the same look (every slot) for the same
## pane and provider, standing and facing front, and it stands still.
func test_the_face_is_the_seats_person_and_stands_still() -> void:
	var office := await _live_office(fixture, Vector2(1920, 480))
	var checked := 0
	for card in office.hud.bar.cards():
		if not office.floor_view.seats.has(card.key):
			continue
		var seated := _worker(office.floor_view.seats[card.key].node)
		var face := card.person()
		_check(face != null and seated != null, "%s: a person on the card and at the seat" % card.key)
		if face == null or seated == null:
			continue
		checked += 1
		for slot in AvatarLook.SLOTS:
			_eq(face.look.slot(slot), seated.look.slot(slot), "%s: the same %s" % [card.key, slot])
		_eq(face.look.context, AvatarLook.STAND, "%s stands" % card.key)
		var player: AnimationPlayer = face.get_node("AnimationPlayer")
		_check(not player.is_playing(), "%s's face stands still" % card.key)
	_eq(checked, 9, "every agent of the fixture")
	await _frames(10)
	var still := office.hud.bar.cards()[0].person().get_node("AnimationPlayer") as AnimationPlayer
	_check(not still.is_playing(), "and stays still")
	_done(office)


## Each group's frame is its own (PortraitCard<State>); only the selected
## pane's card wears the paper ring, and it follows the selection.
func test_a_card_frame_says_the_state_and_the_selected_one_its_ring() -> void:
	var office := await _live_office(fixture, Vector2(1920, 480))
	var bar := office.hud.bar
	var looks: Dictionary[String, StringName] = {
		"web:p1": &"PortraitCardBlocked",
		"web:p2": &"PortraitCardDone",
		"api:p1": &"PortraitCardWorking",
		"api:p2": &"PortraitCardIdle",
	}
	for pane_id: String in looks:
		var card := bar.card_for(_pane(pane_id))
		_check(card != null, "%s has a card" % pane_id)
		if card != null:
			_eq(card.theme_type_variation, looks[pane_id], pane_id)
	# Before any pick the office's selection is herdr's focus (the list's highlight).
	var active := office.navigator.active_key
	var at_first: Array[String] = []
	if bar.card_for(active) != null:
		at_first.append(active)
	_eq(_ringed(bar), at_first, "the ring is on the office's selection alone: %s" % active)
	await _click_desk(office, _pane("api:p1"))
	await _frames(2)
	_eq(office.navigator.active_key, _pane("api:p1"), "a click on the desk selects api:p1")
	_eq(_ringed(bar), [_pane("api:p1")], "its card alone wears the ring")
	var ring := bar.card_for(_pane("api:p1")).get_node("%Selected") as Control
	var frame := bar.card_for(_pane("api:p1")).get_global_rect()
	_eq(ring.get_global_rect(), frame.grow(-1.0), "inside the state's edge, which still shows")
	# S3 BAR-b ruling 1 (2026-10-27): the pointed ring nests inside the selection's, so the state's edge,
	# the selection and the pointing all show at once.
	bar.point(PackedStringArray([_pane("api:p1")]))
	var pointed := bar.card_for(_pane("api:p1")).get_node("%Pointed") as Control
	_check(pointed.visible and ring.visible, "pointed at and selected together")
	_eq(pointed.get_global_rect(), frame.grow(-2.0), "the pointed ring inside the selection's")
	_eq(pointed.theme_type_variation, &"PortraitPointed", "in its own look")
	var face := bar.card_for(_pane("api:p1")).get_node("%Face") as Control
	_check(pointed.get_index() < face.get_index(), "drawn under the face: the head's top, at its row, stays whole")
	bar.point(PackedStringArray())
	await _click_desk(office, _pane("web:p2"))
	await _frames(2)
	_eq(_ringed(bar), [_pane("web:p2")], "and the ring follows")
	_done(office)


## Answer mode owns the number keys: outside it, real presses of 1 to 9 pick
## no card, and no card ever holds the focus.
func test_number_keys_pick_no_card() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_check(not office.hud.inspector.answering(), "not answering")
	for card in bar.cards():
		_eq(card.focus_mode, Control.FOCUS_NONE, "%s takes no focus" % card.key)
	var picked := office.picked_key
	for code: Key in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
		await _office_key(office, code)
	_eq(office.picked_key, picked, "1 to 9 pick nobody")
	await _press(bar.cards()[0])
	await _frames(2)
	_check(not office.picked_key.is_empty(), "a click picks")
	_check(not (root.gui_get_focus_owner() is PortraitCard), "and leaves no card with the focus")
	_done(office)


## A real motion onto a card points at its desk (OfficePointer's frame there,
## as a list row does); moving off clears it. Nothing is picked.
func test_hovering_a_card_points_at_its_desk() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var card := bar.cards()[0]
	var pointer := office.floor_view.pointer
	await _hover(card)
	await _frames(1)
	_eq(root.gui_get_hovered_control(), card, "the pointer is over the card")
	_eq([pointer.key, pointer.visible], [card.key, true], "its desk is framed")
	var extent := office.floor_view.signal_extent(card.key)
	_check(
		pointer.rect.encloses(extent) and pointer.rect.get_center().is_equal_approx(extent.get_center()),
		"round the desk's signal"
	)
	_eq(office.picked_key, "", "and nothing is picked")
	await _pointer_to(office.hud.world_rect().get_center())
	await _frames(1)
	_eq([pointer.key, pointer.visible], ["", false], "off the card: no frame")
	_done(office)


## A refresh that would show the strip it shows already lays nothing out and
## writes nothing (S3 BAR-a ruling 1): the same snapshot again, the same model
## handed to the bar again, and attention's beat (which writes only the waits)
## leave the lay-out count and every card's and fold's words, look, size and
## place as they were. A real change lays it out once. Among several machines
## (S3 BAR-b, 2026-10-27), the chips and a card's pointed ring are written apart,
## each on its own change: the same snapshots leave the chips as they were, and
## pointing at a card writes its ring alone and lays nothing out.
func test_an_unchanged_strip_lays_nothing_out() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	await _text_tick()
	var count := bar.layouts()
	var before := _strip_picture(bar)
	_feed(office, fixture)
	await _frames(2)
	_eq(bar.layouts(), count, "the same snapshot again: no lay-out")
	bar.show_portraits(PortraitBarModel.of(office.frame, office.navigator.active_key), 13)
	await _frames(2)
	_eq(bar.layouts(), count, "the same model handed again: none either")
	_eq(_strip_picture(bar), before, "and nothing on the strip changed")
	await _wait_ticks(2)
	_eq(bar.layouts(), count, "attention's beat writes the waits, and lays nothing out")
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	await _frames(2)
	_eq(bar.layouts(), count + 1, "a real change: laid out once")
	_check(bar.card_for(_pane("infra:p1")) == null, "infra:p1 is no longer a blocked card")
	_done(office)
	var two := await _two_machine_office()
	bar = two.hud.bar
	await _text_tick()
	count = bar.layouts()
	before = _strip_picture(bar)
	var chips := _chip_picture(bar)
	_eq(chips.size(), 2, "two machines: a chip each")
	_feed(two, fixture)
	# bee's client is stopped and online already (_two_machine_office()): the
	# same snapshot applied again, as a reply would be.
	_bee(two)._apply_snapshot(_bee_snapshot("blocked"))
	await _frames(2)
	_eq(bar.layouts(), count, "the same two snapshots again: no lay-out")
	_eq(_chip_picture(bar), chips, "the chips as they were, on the same nodes")
	_eq(_strip_picture(bar), before, "and the strip too")
	var hive := HerdrFleet.pane_key(BEE, "hive:p1")
	bar.point(PackedStringArray([hive]))
	await _frames(2)
	_eq(bar.layouts(), count, "pointing at a card lays nothing out")
	_check(bar.card_for(hive).pointed(), "it writes that card's ring")
	before[before.find(before.filter(func(row: Array) -> bool: return row[0] == hive)[0])][8] = true
	_eq(_strip_picture(bar), before, "and nothing else on the strip")
	bar.point(PackedStringArray())
	await _frames(2)
	_check(not bar.card_for(hive).pointed(), "pointing at nothing takes the ring away")
	_eq(bar.layouts(), count, "and lays nothing out either")
	_eq(_chip_picture(bar), chips, "the chips untouched throughout")
	_done(two)


# --- helpers ------------------------------------------------------------------


## Every shown card's and visible fold's words, look, size and place, its
## place's tooltip and its pointed ring, but the waits, which tick on their own
## beat.
func _strip_picture(bar: OfficeBar) -> Array:
	var picture := []
	for card in bar.cards():
		(
			picture
			. append(
				[
					card.key,
					_label(card, "%Name").text,
					_label(card, "%Place").text,
					card.theme_type_variation,
					(card.get_node("%Tag") as Control).theme_type_variation,
					card.get_global_rect(),
					card.face_only(),
					(card.get_node("%PlaceButton") as Control).tooltip_text,
					card.pointed(),
				]
			)
		)
	for fold in bar.folds():
		if fold.visible:
			picture.append([fold.name, fold.count_text(), fold.theme_type_variation, fold.get_global_rect()])
	return picture


## Every machine chip's key, words, look, rect and node.
func _chip_picture(bar: OfficeBar) -> Array:
	return bar.chips().map(
		func(chip: MachineChip) -> Array:
			return [chip.key, chip.text, chip.theme_type_variation, chip.get_global_rect(), chip.get_instance_id()]
	)


## `count` of attention's text beats.
func _wait_ticks(count: int) -> void:
	for index in count:
		await _text_tick()


func _snapshot_of(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		return {}
	var file: Dictionary = parsed
	return _dict(file, "snapshot") if file.has("snapshot") else file


func _view(key: String, label: String, snapshot: Dictionary, stale: bool) -> MachineView:
	return MachineView.new(key, label, HerdrSnapshot.from_wire(snapshot), stale)


func _frame_of(machines: Array[MachineView]) -> OfficeFrame:
	return OfficeProjection.frame(machines, PackedStringArray(STATES))


## Pane `pane_id` of `machine` began its state at unix `since`, wherever the
## frame holds it.
func _since(frame: OfficeFrame, machine: String, pane_id: String, since: float) -> void:
	var key := HerdrFleet.pane_key(machine, pane_id)
	for building in frame.buildings:
		for zone in building.zones:
			for room in zone.rooms:
				for pane in room.panes:
					if pane.key == key:
						pane.state_since = since
		for pane in building.all_panes:
			if pane.key == key:
				pane.state_since = since
	for pane in frame.live_panes:
		if pane.key == key:
			pane.state_since = since


func _waiting(frame: OfficeFrame, state: String) -> Array[String]:
	var keys: Array[String] = []
	for pane in OfficeNavigator.waiting(frame, state):
		keys.append(pane.key)
	return keys


func _keys(model: PortraitBarModel, group: PortraitBarModel.Group) -> Array[String]:
	var keys: Array[String] = []
	for card in model.of_group(group):
		keys.append(card.key)
	return keys


func _card(model: PortraitBarModel, key: String) -> PortraitBarModel.Card:
	for card in model.cards:
		if card.key == key:
			return card
	return null


func _metrics() -> PortraitBarModel.Metrics:
	var made := PortraitBarModel.Metrics.new()
	made.card = METRICS[0]
	made.face = METRICS[1]
	made.fold = METRICS[2]
	made.tally = METRICS[3]
	made.gap = METRICS[4]
	return made


## `b/d/w/i` as the four groups' counts.
func _counts(fleet: String) -> Dictionary[PortraitBarModel.Group, int]:
	var parts := fleet.split("/")
	var counts: Dictionary[PortraitBarModel.Group, int] = {}
	for index in PortraitBarModel.GROUPS.size():
		counts[PortraitBarModel.GROUPS[index]] = int(parts[index])
	return counts


func _forms(made: PortraitBarModel.Fit) -> Array:
	var forms := []
	for group in PortraitBarModel.GROUPS:
		forms.append(made.forms[group])
	return forms


## The fixture with every agent blocked and `extra` more blocked agents in
## web's ui tab.
func _many_blocked(extra: int) -> Dictionary:
	var snapshot: Dictionary = fixture.duplicate(true)
	var panes: Array = snapshot.panes
	var agents: Array = snapshot.agents
	for index in extra:
		var pane_id := "web:x%d" % index
		var template: Dictionary = panes[4]
		var pane: Dictionary = template.duplicate(true)
		pane.pane_id = pane_id
		pane.terminal_id = "term-x%d" % index
		pane.agent_status = "blocked"
		panes.append(pane)
		var record: Dictionary = agents[3]
		var agent: Dictionary = record.duplicate(true)
		agent.pane_id = pane_id
		agent.terminal_id = pane.terminal_id
		agents.append(agent)
	return snapshot


func _made(key: String, group: PortraitBarModel.Group, name: String, place: String) -> PortraitBarModel.Card:
	var card := PortraitBarModel.Card.new()
	card.key = key
	card.machine = LOCAL
	card.provider = "claude"
	card.name = name
	card.place = place
	card.group = group
	card.state = PortraitBarModel.WORDS[group]
	card.group_key = HerdrFleet.pane_key(LOCAL, place)
	return card


func _card_ids(bar: OfficeBar) -> Dictionary[String, int]:
	var ids: Dictionary[String, int] = {}
	for card in bar.cards():
		ids[card.key] = card.get_instance_id()
	return ids


func _ringed(bar: OfficeBar) -> Array[String]:
	var found: Array[String] = []
	for card in bar.cards():
		if (card.get_node("%Selected") as Control).visible:
			found.append(card.key)
	return found


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## A bare HUD dressed with the shipped pack and laid out for `screen`: no
## office, so nothing writes into the bar behind the case.
func _bare_hud(screen: Vector2) -> OfficeHud:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var hud: OfficeHud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(screen)
	await _frames(2)
	return hud


## Whether `label`'s text fits its width in its own font, with no ellipsis.
func _fits_label(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x


## A real pointer motion onto the middle of `control`.
func _hover(control: Control) -> void:
	await _pointer_to(_aim(control))


## A real left click on `control`, where _aim() points.
func _press(control: Control) -> void:
	var at := _aim(control)
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## Where a real pointer aims at `control`: its middle, but a portrait card's
## face (S3 BAR-b, 2026-10-27: the lower half of a card's words is its place,
## a button of its own that pans to the zone; the face is the card's own).
func _aim(control: Control) -> Vector2:
	if control is PortraitCard:
		var face: Control = control.get_node("%Face")
		return face.get_global_rect().get_center()
	return control.get_global_rect().get_center()
