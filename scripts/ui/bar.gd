class_name OfficeBar
extends Control
## The top bar: the wordmark on the left, among several machines a chip per
## machine (a click shows its map), then the portrait strip, who needs you as
## faces (the blocked in the order `N` walks them, each with how long
## it has waited; then the done, oldest first; then the working and the idle,
## in place order), then `1 machine · 13 panes` and the chime switch, and two
## right-aligned lines, the pack's name and how the office is running, as wide
## as the longest status needs at every window size (the scene's offsets).
## Where the agents do not all fit, the strip folds them by a fixed ladder
## (PortraitBarModel.fit(), from the widths the scene's nodes measure), never
## hiding the longest-waiting blocked. `13 panes` and the chime switch show
## where titles are allowed; on a narrower bar they step aside and the strip
## takes their room. Hovering the status line says how each machine answers,
## and a machine chip says it for its machine. On a tall bar (a screen at least
## `OfficeHud.staff_tall_from` high) the cards are B2's tiles, the face over the
## words, and the folds as tall; on a short one, the horizontal cards
## (set_tall()). The wordmark, the strip and the right end stand in the band's
## middle either way (the scene's anchors; on a tall bar the wordmark's caps,
## not its box, are centred: HudTheme's WordmarkMarginTall).
##
## Its nodes are permanent, but for the cards and the chips: a card exists only
## while its pane shows as a card or a face, and a pane that stops showing gives
## its node back to a pool, hidden and not freed, for the next pane to take.
## The pool is bounded by the strip's width, not by the panes. A chip is kept by
## its machine's key for as long as the fleet has that machine. A click on a
## card, a card's place, a chip, a fold or `13 panes` is the office's to act on
## (portrait_picked, zone_picked, machine_picked, fold_pressed, panes_pressed).
## The bar is how the mouse moves between machines (the chips) and zones (a
## card's place); PageUp / PageDown and `S` reach the zones nobody waits in.
##
## In a window that fills the screen the bar is also its title bar: the window's
## own buttons (the macOS traffic lights) stand over its left end, so the
## wordmark and the strip start after them (set_title_gap()), and a press on the
## bar's bare ground drags the window, a double click zooms it (moves_window).

## A card was clicked: pick pane `key`.
signal portrait_picked(key: String)
## The pointer rests on pane `key`'s card (empty: on none any more).
signal portrait_pointed(key: String)
## A card's place was clicked: pan to zone `key`, select nothing.
signal zone_picked(key: String)
## A machine chip was clicked: show machine `key`'s map.
signal machine_picked(key: String)
## A fold or a tally was clicked: its group's state in the OVERVIEW.
signal fold_pressed(group: PortraitBarModel.Group)
## `13 panes` was clicked: the OVERVIEW, opened or closed.
signal panes_pressed
## The chime switch was clicked: `on` is what it asks for. The office decides,
## and says what it decided with show_chime().
signal chime_toggled(on: bool)

const CARD_SCENE := preload("res://scenes/ui/portrait_card.tscn")
const CHIP_SCENE := preload("res://scenes/ui/machine_chip.tscn")
## What the theme line says while the lens is held (show_lens()).
const LENS_LINE := "LENS · hold L"
## What it says while the strategic view is open (show_strategic()).
const STRATEGIC_LINE := "STRATEGIC · S"
## What the chime switch says, on and off (show_chime()).
const CHIME_ON := "CHIME ON"
const CHIME_OFF := "CHIME OFF"

## The bar stands in for the window's title bar: its bare ground drags the
## window and a double click zooms it. The office sets it; off in a plain window.
var moves_window := false

## The pack's name, for the theme line when the lens is let go and the
## strategic view closed.
var _theme_name := ""
var _lensed := false
var _strategic := false
## What the chime switch says (show_chime()).
var _chime_on := false
## A machine is not answering (show_bar()).
var _alarmed := false
## Every machine, for the status line's hover.
var _machines: Array[OfficeTotals.MachineRow] = []
## Machine key -> its chip, while there are several machines.
var _chips: Dictionary[String, MachineChip] = {}
## Whether the bar has its titles (set_titled()): the chips are wide.
var _titled := true
## Whether the cards are tiles (set_tall()).
var _tall := false
## The panes whose cards a hovered HUD line outlines (point()), as a set.
var _pointed: Dictionary[String, bool] = {}
## Who the strip shows, and dressed from what.
var _model := PortraitBarModel.new()
var _art: ArtPack
## The rung the strip fits on now.
var _fit := PortraitBarModel.Fit.new()
## Each blocked card's wait (show_waits()), by pane key.
var _waits: Dictionary[String, String] = {}
## The cards showing a pane now, by its key; the rest of %Cards' cards are pooled.
var _shown: Dictionary[String, PortraitCard] = {}
## A card never added to the strip, only asked for the scene's widths.
var _gauge: PortraitCard
## What the strip last laid out (_signature_of()): a refresh that would lay out
## the same writes nothing. Empty until the first lay-out, and after a pack swap.
var _laid_out := ""
## How many times the strip has been laid out (layouts()).
var _layouts := 0


func _ready() -> void:
	_gauge = CARD_SCENE.instantiate()
	for fold in folds():
		var group := fold.group
		fold.pressed.connect(func() -> void: fold_pressed.emit(group))
	var panes: Button = %Panes
	panes.pressed.connect(func() -> void: panes_pressed.emit())
	var switch: Button = %Chime
	switch.pressed.connect(func() -> void: chime_toggled.emit(not _chime_on))
	var strip: Control = %Strip
	strip.resized.connect(_fit_chips)
	strip.resized.connect(_lay_out)
	if _tall:
		_take_form()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_lay_out()
	elif what == NOTIFICATION_PREDELETE and is_instance_valid(_gauge):
		_gauge.free()


## The bar takes the mouse like the two panels do; see HdPanel._gui_input.
## Standing in for the title bar, a left press on its bare ground drags the
## window and a double click zooms it, as the system's title bar would; a
## card, a fold, `13 panes` or the chime switch takes its own press first.
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	accept_event()
	var button := event as InputEventMouseButton
	if not moves_window or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var window := get_window()
	if button.double_click:
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_MAXIMIZED else Window.MODE_MAXIMIZED
	else:
		window.start_drag()


## Over the status line, how each machine answers and when it was last heard
## from (OfficeTotals.machines_tip()), at the time the pointer rests there.
## Elsewhere on the bar's bare ground, nothing.
func _get_tooltip(at: Vector2) -> String:
	var status_label: Label = %StatusLine
	if not status_label.get_global_rect().has_point(get_global_transform() * at):
		return ""
	return OfficeTotals.machines_tip(_machines, Time.get_unix_time_from_system())


## `theme_name` is the pack's name (plus `[T]` when there is more than one),
## `status` how the office runs (`LIVE / READ ONLY`, `1 OFFLINE / OPERATOR`,
## `OFFLINE / RECONNECTING`). `is_alarmed` is a machine being down: the line
## turns the blocked colour.
func show_bar(theme_name: String, status: String, is_alarmed: bool) -> void:
	var status_label: Label = %StatusLine
	_theme_name = theme_name
	_alarmed = is_alarmed
	_say_theme()
	status_label.text = status
	status_label.theme_type_variation = &"LabelBlocked" if is_alarmed else &"LabelCream"


## Every machine, for the status line's hover (OfficeTotals.machines_tip()),
## and, when there are `several`, a chip each in the fleet's order, machine
## `shown`'s (its map is the one drawn) the current one. Chips are kept by
## machine key and written in place; a machine gone takes its chip with it.
## The chips take their room from the strip, which fits what is left.
func show_machines(machines: Array[OfficeTotals.MachineRow], shown := "", several := false) -> void:
	_machines = machines
	var row: HBoxContainer = %MachineRow
	var listed: Dictionary[String, bool] = {}
	if several:
		for machine in machines:
			listed[machine.key] = true
	for key: String in _chips.keys():
		if not listed.has(key):
			row.remove_child(_chips[key])
			_chips[key].queue_free()
			_chips.erase(key)
	var at := 0
	for machine in machines:
		if not listed.has(machine.key):
			continue
		var chip: MachineChip = _chips.get(machine.key)
		if chip == null:
			chip = CHIP_SCENE.instantiate()
			row.add_child(chip)
			chip.set_narrow(not _titled)
			chip.pressed.connect(func() -> void: machine_picked.emit(chip.key))
			_chips[machine.key] = chip
		chip.show_machine(machine, machine.key == shown)
		if chip.get_index() != at:
			row.move_child(chip, at)
		at += 1
	var clip: Control = %Machines
	if clip.visible == _chips.is_empty():
		clip.visible = not _chips.is_empty()
	_fit_chips()


## The chips take the width they need from the room they share with the strip,
## but never so much that the strip is left less than the ladder's last rung
## (a tally per group, PortraitBarModel.fit()): the longest-waiting blocked
## stay in sight however many machines there are. Past that the row of chips
## is cut where its room ends; the machines beyond it are reached by their
## cards and PageUp / PageDown. Only the clip's width is written.
func _fit_chips() -> void:
	var clip: Control = %Machines
	if not is_node_ready() or not clip.visible:
		return
	var needed := 0.0
	for chip in chips():
		needed += chip.get_combined_minimum_size().x
	var row: HBoxContainer = %MachineRow
	needed += row.get_theme_constant("separation") * maxi(_chips.size() - 1, 0)
	var made := metrics()
	var groups := PortraitBarModel.GROUPS.size()
	var last_rung := made.tally * groups + made.gap * (groups - 1)
	var strip: Control = %Strip
	var width := clampf(strip.size.x + clip.custom_minimum_size.x - last_rung, 0.0, needed)
	if clip.custom_minimum_size.x != width:
		clip.custom_minimum_size.x = width


## The machine chips, left to right; none for a single machine.
func chips() -> Array[MachineChip]:
	var found: Array[MachineChip] = []
	var row: HBoxContainer = %MachineRow
	for child in row.get_children():
		if child is MachineChip:
			found.append(child)
	return found


## Machine `key`'s chip; null when there is one machine, or no such machine.
func chip_for(key: String) -> MachineChip:
	return _chips.get(key)


## Outline the cards of panes `keys` (a hovered HUD line points at them), and
## no other; a pane folded away has no card to outline. Only the cards whose
## ring changes are written, and nothing is laid out.
func point(keys: PackedStringArray) -> void:
	_pointed.clear()
	for key in keys:
		_pointed[key] = true
	for key: String in _shown:
		_shown[key].set_pointed(_pointed.has(key))


## The lens is held (`held`): the theme line says so, `LENS · hold L`; let go,
## the pack's name again. Only the text changes.
func show_lens(held: bool) -> void:
	var theme_label: Label = %ThemeLine
	if held and not _lensed and not _strategic:
		_theme_name = theme_label.text
	_lensed = held
	_say_theme()


## The strategic view is open (`on`): the theme line says so, `STRATEGIC · S`,
## over the lens's line (the two are never on together, but a lens let go in
## the same frame must not take the line back); closed, the pack's name again.
func show_strategic(on: bool) -> void:
	var theme_label: Label = %ThemeLine
	if on and not _strategic and not _lensed:
		_theme_name = theme_label.text
	_strategic = on
	_say_theme()


## The theme line: the strategic view's, the lens's, or the pack's name.
func _say_theme() -> void:
	var theme_label: Label = %ThemeLine
	theme_label.text = STRATEGIC_LINE if _strategic else LENS_LINE if _lensed else _theme_name


## The pack the faces are dressed from: a switch dresses every shown face
## again on the same nodes.
func dress(art: ArtPack) -> void:
	_art = art
	_laid_out = ""
	_lay_out()


## Who the strip shows (`model`), and from `totals` how many machines there
## are and how many panes the live ones carry, for `1 machine · 13 panes`
## (OfficeTotals.count_words()).
func show_portraits(model: PortraitBarModel, totals: OfficeTotals) -> void:
	_model = model
	var button: Button = %Panes
	var said := OfficeTotals.count_words(totals.machines_total, totals.panes)
	if button.text != said:
		button.text = said
	_lay_out()


## Each blocked card's wait in OfficeAttention.wait_text()'s words, by pane
## key, on attention's beat. Only the words change: a card's width is the
## scene's, so nothing is fitted again.
func show_waits(texts: Dictionary[String, String]) -> void:
	_waits = texts
	for key in _shown:
		var text: String = texts.get(key, "")
		_shown[key].show_wait(text)


## The OVERVIEW is open (`on`): `13 panes` reads pressed.
func set_overview(on: bool) -> void:
	var button: Button = %Panes
	button.theme_type_variation = &"BarLineOn" if on else &"BarLine"


## The fold of the state the OVERVIEW shows alone reads pressed; `group` −1
## for none (the OVERVIEW closed, or on ALL).
func set_fold_on(group: int) -> void:
	for fold in folds():
		fold.set_on(fold.group == group)


## Room, in the bar's own pixels, the window's own buttons take at its left
## end; the wordmark and the strip start after it. 0 in a plain window.
func set_title_gap(width: float) -> void:
	var content: Control = %Content
	if is_equal_approx(content.offset_left, width):
		return
	content.offset_left = width


func title_gap() -> float:
	var content: Control = %Content
	return content.offset_left


## `13 panes` and the chime switch show on a screen wide enough for titles
## (OfficeHud.fit()) only; on a narrower one the strip takes their room, and
## the machine chips go narrow.
func set_titled(on: bool) -> void:
	var panes: Button = %Panes
	var switch: Button = %Chime
	panes.visible = on
	switch.visible = on
	_titled = on
	for key: String in _chips:
		_chips[key].set_narrow(not on)
	_fit_chips()


## The cards are tiles (`on`, a tall bar) or horizontal cards. Every card,
## pooled ones and the gauge included, and every fold takes the form; the
## strip is laid out once with the new widths. Nothing when the form is the
## same (OfficeHud.fit() asks on every fit).
func set_tall(on: bool) -> void:
	if on == _tall:
		return
	_tall = on
	if is_node_ready():
		_take_form()


## Every card, the gauge and every fold in the form set_tall() asked for, and
## the strip laid out with their widths.
func _take_form() -> void:
	var margin: Control = %WordmarkMargin
	margin.theme_type_variation = &"WordmarkMarginTall" if _tall else &"WordmarkMargin"
	_gauge.set_tall(_tall)
	var row: HBoxContainer = %Cards
	for child in row.get_children():
		if child is PortraitCard:
			(child as PortraitCard).set_tall(_tall)
	for fold in folds():
		fold.set_tall(_tall)
	_laid_out = ""
	_lay_out()


## Whether the cards are tiles.
func is_tall() -> bool:
	return _tall


## The chime is on (`on`) or off: the switch says so, in the lines' cream
## while it is on (BarSwitchOn) and their muted colour while it is off. This is
## the office telling the switch; a click only asks (chime_toggled), so a
## switch nobody answers, the showroom's, stays as it was.
func show_chime(on: bool) -> void:
	var switch: Button = %Chime
	_chime_on = on
	switch.text = CHIME_ON if on else CHIME_OFF
	switch.theme_type_variation = &"BarSwitchOn" if on else &"BarSwitch"


## Whether the chime switch says the chime is on.
func chime_shown() -> bool:
	return _chime_on


## The widths the ladder is fitted by, from the scene's nodes: a card and a
## face (the gauge card), a fold and a tally, and the strip's gap.
func metrics() -> PortraitBarModel.Metrics:
	var made := PortraitBarModel.Metrics.new()
	var row: HBoxContainer = %Cards
	var fold: PortraitFold = %FoldIdle
	made.card = _gauge.needed_width(false)
	made.face = _gauge.needed_width(true)
	made.fold = fold.needed_width(false)
	made.tally = fold.needed_width(true)
	made.gap = row.get_theme_constant("separation")
	return made


## Fit the strip to its room, and give each shown pane its card: the blocked
## first, each group's fold after its cards, and the pool's hidden cards last.
## A pane that stays shown keeps its node; one that goes gives it back. The
## pool grows to the most cards ever shown at once, bounded by the strip's
## width, and never frees one. A strip that would show what it shows already
## (_signature_of(): the same rung, the same cards, folds and selection, the
## same room and pack) writes nothing and lays nothing out.
func _lay_out() -> void:
	if not is_node_ready() or _art == null:
		return
	var strip: Control = %Strip
	var row: HBoxContainer = %Cards
	var made := PortraitBarModel.fit(_model.counts, metrics(), strip.size.x)
	var signature := _signature_of(made, strip.size.x)
	if signature == _laid_out:
		return
	_laid_out = signature
	_layouts += 1
	_fit = made
	var order: Array[Control] = []
	var wanted: Dictionary[String, bool] = {}
	var placed: Array[PortraitBarModel.Card] = []
	var faces: Dictionary[String, bool] = {}
	for group in PortraitBarModel.GROUPS:
		var members := _model.of_group(group)
		var shown := _fit.shown_of(group, members.size())
		for index in shown:
			wanted[members[index].key] = true
			placed.append(members[index])
			faces[members[index].key] = _fit.forms[group] == PortraitBarModel.Form.FACE
		var folded: Array[PortraitBarModel.Card] = []
		for index in range(shown, members.size()):
			folded.append(members[index])
		# Only the blocked keep faces before a fold: a tally, on the last rung.
		var form := _fit.forms[group]
		fold_of(group).show_fold(folded, form == PortraitBarModel.Form.TALLY or form == PortraitBarModel.Form.FACE)
	for key: String in _shown.keys():
		if not wanted.has(key):
			_pool(_shown[key])
			_shown.erase(key)
	for card in placed:
		var node: PortraitCard = _shown.get(card.key)
		if node == null:
			node = _unpooled()
			_shown[card.key] = node
		node.visible = true
		node.set_face_only(faces[card.key])
		node.show_card(card, _art, card.key == _model.selected)
		node.set_pointed(_pointed.has(card.key))
		var wait: String = _waits.get(card.key, "")
		node.show_wait(wait)
	var at := 0
	for group in PortraitBarModel.GROUPS:
		for card in placed:
			if card.group == group:
				order.append(_shown[card.key])
		order.append(fold_of(group))
	for each in order:
		if each.get_index() != at:
			row.move_child(each, at)
		at += 1


## Everything a lay-out at `rung` in `room` units would write, as one string:
## the rung, the room and the pack, each shown card's words, look, place (its
## zone and the sign's tooltip) and selection, and each fold's count and the
## names its tooltip lists. (A card's pointed ring and the machine chips are
## written apart, each on its own change: point(), show_machines().) Only what
## shows is in it, so a fleet of 400 costs no more than the strip's room.
func _signature_of(rung: PortraitBarModel.Fit, room: float) -> String:
	var parts := PackedStringArray(["%d %d %s %s" % [rung.rung, rung.faces_shown, room, _art.base_path]])
	for group in PortraitBarModel.GROUPS:
		var members := _model.of_group(group)
		var shown := rung.shown_of(group, members.size())
		for index in shown:
			var card := members[index]
			var selected := card.key == _model.selected
			(
				parts
				. append(
					(
						"%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s"
						% [
							card.key,
							card.group,
							card.state,
							card.name,
							card.place,
							card.tab,
							card.group_key,
							card.starting,
							card.provider,
							card.machine_label,
							selected,
							rung.forms[group],
							card.zone_key,
							PortraitCard.place_tip_of(card).c_escape(),
						]
					)
				)
			)
		parts.append("fold %d %d" % [group, members.size() - shown])
		for index in range(shown, mini(members.size(), shown + PortraitFold.TIP_LINES)):
			var card := members[index]
			parts.append("%s\t%s\t%s" % [card.name, card.place, card.machine_label])
	return "\n".join(parts)


## How many times the strip has been laid out since it was made.
func layouts() -> int:
	return _layouts


## A pooled card, or a new one when the pool is empty.
func _unpooled() -> PortraitCard:
	for each in cards_pooled():
		return each
	var made: PortraitCard = CARD_SCENE.instantiate()
	var row: HBoxContainer = %Cards
	row.add_child(made)
	made.set_tall(_tall)
	made.pressed.connect(func() -> void: portrait_picked.emit(made.key))
	made.place_picked.connect(func(zone: String) -> void: zone_picked.emit(zone))
	made.place_hovered.connect(func(on: bool) -> void: portrait_pointed.emit(made.key if on else ""))
	made.mouse_entered.connect(func() -> void: portrait_pointed.emit(made.key))
	made.mouse_exited.connect(func() -> void: portrait_pointed.emit(""))
	return made


func _pool(card: PortraitCard) -> void:
	card.visible = false
	card.key = ""
	card.set_pointed(false)


## The cards showing a pane now, left to right.
func cards() -> Array[PortraitCard]:
	var found: Array[PortraitCard] = []
	var row: HBoxContainer = %Cards
	for child in row.get_children():
		if child is PortraitCard and not (child as PortraitCard).key.is_empty():
			found.append(child)
	return found


## The cards in the pool: hidden, showing nobody.
func cards_pooled() -> Array[PortraitCard]:
	var found: Array[PortraitCard] = []
	var row: HBoxContainer = %Cards
	for child in row.get_children():
		if child is PortraitCard and (child as PortraitCard).key.is_empty():
			found.append(child)
	return found


## Pane `key`'s card while it shows; null when it is folded or has none.
func card_for(key: String) -> PortraitCard:
	return _shown.get(key)


## The four folds, in the bar's order.
func folds() -> Array[PortraitFold]:
	var found: Array[PortraitFold] = []
	var row: HBoxContainer = %Cards
	for child in row.get_children():
		if child is PortraitFold:
			found.append(child)
	return found


func fold_of(group: PortraitBarModel.Group) -> PortraitFold:
	for fold in folds():
		if fold.group == group:
			return fold
	return null


## How many agents `group` holds, shown or folded.
func count(group: PortraitBarModel.Group) -> int:
	var many: int = _model.counts.get(group, 0)
	return many


## Who the strip was last told about.
func portraits() -> PortraitBarModel:
	return _model


## The rung the strip fits on now.
func fitted() -> PortraitBarModel.Fit:
	return _fit


## The pack's name, as the first right-hand line shows it.
func theme_line() -> String:
	var theme_label: Label = %ThemeLine
	return theme_label.text


## How the office runs, as the second right-hand line shows it.
func status_line() -> String:
	var status_label: Label = %StatusLine
	return status_label.text


## Whether a machine is down: the status line says it in the blocked colour.
func alarmed() -> bool:
	return _alarmed
