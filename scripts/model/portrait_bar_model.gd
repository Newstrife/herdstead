class_name PortraitBarModel
extends RefCounted
## Who the top bar's portrait strip shows, and in what order, made once per
## refresh from the frame (PortraitBarModel.of()): every agent of a live
## machine, the blocked first in the order `N` walks them, then the done
## (unread) oldest first, then the working and the idle in place order. How
## many of them fit as cards, as faces, or only as a fold's or a tally's
## number is fit()'s, from the widths the scene measures.
##
## A card is for an agent: a shell has none, nor has an agent herdr is still
## launching that does not ask (the old counters' rule, PaneModel.launching()),
## nor any pane of a machine that is not answering (AGENTS.md invariant 4: a
## dropped machine's agents never show as activity). It reads no Time, no
## fleet and no node: a wait is written by OfficeAttention, from the state log.

## The bar's four groups, left to right.
enum Group { BLOCKED, DONE, WORKING, IDLE }
## How a group shows: each agent a card (face and words) or a face alone; or
## the whole group as one fold (`+12` over `working`) or one tally (`+12`).
enum Form { CARD, FACE, FOLD, TALLY }

## The groups in the bar's order.
const GROUPS: Array[Group] = [Group.BLOCKED, Group.DONE, Group.WORKING, Group.IDLE]
## herdr's word for each group, in lower case, as a fold says it.
const WORDS: Dictionary[Group, String] = {
	Group.BLOCKED: "blocked",
	Group.DONE: "done",
	Group.WORKING: "working",
	Group.IDLE: "idle",
}
## The ladder's last rung: the blocked keep as many faces as fit before a tally.
const LAST_RUNG := 7
## Written for a space whose label is empty (NextModel.of()'s rule).
const UNNAMED_SPACE := "?"


## One agent the bar can show.
class Card:
	extends RefCounted
	## HerdrFleet.pane_key: machine and pane id.
	var key := ""
	var machine := ""
	## The machine's label, only among several machines; empty otherwise.
	var machine_label := ""
	var pane_id := ""
	var provider := ""
	## What every surface calls the pane (PaneModel.name).
	var name := ""
	## Its workspace's label, or UNNAMED_SPACE.
	var place := ""
	## Its tab as a place says it (PaneModel.tab_shown): empty for a lone tab.
	var tab := ""
	var group := Group.IDLE
	## herdr's word for its state.
	var state := ""
	## The zone that seats it; empty when no zone does.
	var zone_key := ""
	## Its worktree group: the mezzanine's source zone, else its own zone;
	## empty when unseated. The tag's colour comes from it, never the state.
	var group_key := ""
	## Drawn as still starting (PaneModel.launching(), the seat's rule): never
	## for a card, which a launching agent does not get, unless it asks.
	var starting := false


## What fit() needs from the scene, in units: a card, a face-only card, a
## fold, a tally, and the gap between two items.
class Metrics:
	extends RefCounted
	var card := 0.0
	var face := 0.0
	var fold := 0.0
	var tally := 0.0
	var gap := 0.0


## The rung of the ladder that fits: each group's form, how many blocked are
## shown (as cards or faces) before the blocked tally (all of them below the
## last rung), and the width all that needs.
class Fit:
	extends RefCounted
	var rung := 1
	var forms: Dictionary[Group, Form] = {}
	var faces_shown := 0
	var needed := 0.0

	## How many of `many` agents in `group` show as a card or a face; the rest
	## are in the group's fold or tally.
	func shown_of(group: Group, many: int) -> int:
		if forms[group] != Form.CARD and forms[group] != Form.FACE:
			return 0
		return mini(faces_shown, many) if group == Group.BLOCKED else many


## Every card, in drawing order.
var cards: Array[Card] = []
## How many agents each group holds.
var counts: Dictionary[Group, int] = {}
## The key the office has selected (OfficeNavigator.active_key); empty for none.
var selected := ""


## The bar for `frame`, with `picked` the office's selection.
static func of(frame: OfficeFrame, picked: String) -> PortraitBarModel:
	var model := PortraitBarModel.new()
	model.selected = picked
	for group in GROUPS:
		model.counts[group] = 0
	for pane in OfficeNavigator.waiting(frame, str(ArtContract.STATE_BLOCKED)):
		model._add(frame, pane, Group.BLOCKED)
	for pane in OfficeNavigator.waiting(frame, str(ArtContract.STATE_DONE)):
		model._add(frame, pane, Group.DONE)
	var idle: Array[PaneModel] = []
	for pane in _in_place_order(frame):
		if pane.provider.is_empty() or pane.launching():
			continue
		if pane.state == str(ArtContract.STATE_WORKING):
			model._add(frame, pane, Group.WORKING)
		elif pane.state != str(ArtContract.STATE_BLOCKED) and pane.state != str(ArtContract.STATE_DONE):
			idle.append(pane)
	for pane in idle:
		model._add(frame, pane, Group.IDLE)
	return model


## The cards of `group`, in drawing order.
func of_group(group: Group) -> Array[Card]:
	var found: Array[Card] = []
	for card in cards:
		if card.group == group:
			found.append(card)
	return found


func _add(frame: OfficeFrame, pane: PaneModel, group: Group) -> void:
	var card := Card.new()
	card.key = pane.key
	card.machine = pane.machine()
	if frame.several_machines():
		var building := frame.building_of(card.machine)
		card.machine_label = building.label if building != null else card.machine
	card.pane_id = pane.pane_id
	card.provider = pane.provider
	card.name = pane.name
	card.place = pane.workspace_label if not pane.workspace_label.is_empty() else UNNAMED_SPACE
	card.tab = pane.tab_shown
	card.group = group
	card.state = pane.state
	card.starting = pane.launching()
	card.zone_key = frame.zone_of(pane.key)
	var zone := frame.find_zone(card.zone_key) if not card.zone_key.is_empty() else null
	if zone != null:
		var source := zone.zone_model.mezzanine_of
		card.group_key = source if not source.is_empty() else zone.zone_model.key
	cards.append(card)
	counts[group] += 1


## Every pane of a live machine in place order: machine by machine, its zones,
## their rooms and their panes (the walk OfficeNavigator makes for `N`), then
## the panes no zone seats, in the frame's order. A pane is listed once.
static func _in_place_order(frame: OfficeFrame) -> Array[PaneModel]:
	var found: Array[PaneModel] = []
	var seen: Dictionary[String, bool] = {}
	for building in frame.buildings:
		if building.stale:
			continue
		for zone in building.zones:
			for room in zone.rooms:
				for pane in room.panes:
					if not seen.has(pane.key):
						seen[pane.key] = true
						found.append(pane)
	for pane in frame.live_panes:
		if not seen.has(pane.key):
			seen[pane.key] = true
			found.append(pane)
	return found


## The first rung of the ladder whose width fits `room`:
##
## | Rung | Blocked | Done | Working | Idle |
## | 1 | cards | cards | cards | cards |
## | 2 | cards | cards | fold | fold |
## | 3 | cards | faces | fold | fold |
## | 4 | faces | faces | fold | fold |
## | 5 | faces | fold | fold | fold |
## | 6 | faces | tally | tally | tally |
## | 7 | first k faces + tally | tally | tally | tally |
##
## A group with nobody in it shows nothing. On the last rung k is the most
## blocked faces that fit, so the longest-waiting blocked are the last to
## fold; when not even its tallies fit, the last rung with no face.
static func fit(held: Dictionary[Group, int], metrics: Metrics, room: float) -> Fit:
	var blocked: int = held.get(Group.BLOCKED, 0)
	for rung in range(1, LAST_RUNG):
		var made := _rung(rung, held, metrics, blocked)
		if made.needed <= room:
			return made
	for shown in range(blocked - 1, 0, -1):
		var cut := _rung(LAST_RUNG, held, metrics, shown)
		if cut.needed <= room:
			return cut
	return _rung(LAST_RUNG, held, metrics, 0)


## Rung `rung` with `shown` blocked before the blocked tally (all of them below
## the last rung), and the width it needs.
static func _rung(rung: int, held: Dictionary[Group, int], metrics: Metrics, shown: int) -> Fit:
	var made := Fit.new()
	made.rung = rung
	made.faces_shown = shown
	made.forms = _forms(rung)
	var items := 0
	var width := 0.0
	for group in GROUPS:
		var many: int = held.get(group, 0)
		if many == 0:
			continue
		match made.forms[group]:
			Form.CARD:
				items += many
				width += metrics.card * many
			Form.FACE:
				var faces := shown if group == Group.BLOCKED else many
				items += faces
				width += metrics.face * faces
				if faces < many:
					items += 1
					width += metrics.tally
			Form.FOLD:
				items += 1
				width += metrics.fold
			Form.TALLY:
				items += 1
				width += metrics.tally
	made.needed = width + metrics.gap * maxi(items - 1, 0)
	return made


static func _forms(rung: int) -> Dictionary[Group, Form]:
	var blocked := Form.CARD if rung <= 3 else Form.FACE
	var done := Form.CARD
	if rung >= 6:
		done = Form.TALLY
	elif rung == 5:
		done = Form.FOLD
	elif rung >= 3:
		done = Form.FACE
	var rest := Form.CARD if rung == 1 else Form.FOLD if rung <= 5 else Form.TALLY
	var forms: Dictionary[Group, Form] = {
		Group.BLOCKED: blocked,
		Group.DONE: done,
		Group.WORKING: rest,
		Group.IDLE: rest,
	}
	return forms
