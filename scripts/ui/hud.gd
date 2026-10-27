class_name OfficeHud
extends CanvasLayer
## The office's screen-space furniture: the top bar (its machine chips and
## portrait strip are how the mouse moves between machines and zones), the
## arrows on the world's edges toward blocked desks off screen, the agent list
## in a drawer on the right (opened by `A`), and the bottom panel
## (OfficeBottomPanel, `staff`: the AGENT page is the agent card, `inspector`,
## with NEXT at its right end; then HISTORY and EVENTS, with NEWS in its top
## row), the strategic view over the world rect and the OVERVIEW over the
## world when they are open; laid out by the scene and styled by one Theme.
## In answer mode the bottom panel stands in the middle of the screen over a
## dimmed office, as a modal (_fit_staff()).
##
## The office hands it models and asks it back for the room it left over; it
## never tells a panel where to stand. Moving a panel in `hud.tscn` moves the
## world with it.

## A portrait card's place (its zone tag and space) was pressed; `key` is that
## zone's key. The office pans to that zone at once: there is no transition.
signal zone_picked(key: String)
## A machine chip of the top bar was pressed; `key` is that machine's key. The
## office shows that machine's map.
signal machine_picked(key: String)
## An edge arrow was pressed: the office pans to the desk of pane `pane_key`,
## and selects nothing.
signal arrow_picked(pane_key: String)
## A pane was chosen in the agent list: pick it, as a click on its desk does.
signal agent_picked(key: String)
## The viewer asked for the terminal monitor on pane `pane_key`: a pane opened
## in the agent list (double-click, Enter, Open) or the card's "Monitor".
## The office decides and opens it.
signal monitor_requested(pane_key: String)
## A History line of the agent list asked to be located (its menu's View).
signal history_locate_requested(key: String)
## A line of the bottom panel's HISTORY page was clicked: pick pane `key`, if
## it is still the terminal the log saw (the office checks again).
signal history_picked(key: String)
signal attention_snooze_requested(id: String, seconds: int)
signal attention_hidden_changed(id: String, hidden: bool)
## The list's view or a fold changed; the office may remember it.
signal agent_list_changed
## The terminal monitor closed.
signal monitor_closed
## NEXT on the bottom panel was pressed: the office does what `N` does.
signal next_requested
## `‹` (-1) or `›` (+1) under NEXT on the bottom panel was pressed: the office picks
## the one before or after the pick in NEXT's queue, and only picks.
signal step_requested(direction: int)
## A split from the bottom panel of pane `target_key` made pane `pane_id` (see
## OfficePaneInspector.pane_split): the office picks it once it shows.
signal pane_split(target_key: String, pane_id: String, terminal_id: String, generation: int)
## The card made a new space or worktree from pane `from_key` (OfficePaneInspector.space_created):
## the office picks its root pane, in its new zone, once it shows.
signal space_created(from_key: String, workspace_id: String, pane_id: String, terminal_id: String, generation: int)
## A panel's placement changed without the window changing: the office lays the
## world out again (see _fit_room()).
signal room_changed
## A card of the top bar's portrait strip was clicked: pick pane `key`, as the list does.
signal portrait_picked(key: String)
## A fold or a tally of the portrait strip was clicked: the office opens the
## OVERVIEW on its group's state, or toggles that chip while it is open.
signal fold_pressed(group: PortraitBarModel.Group)
## The top bar's `13 panes` was clicked: the office opens the OVERVIEW, or closes it.
signal panes_pressed
## The top bar's chime switch was clicked: `on` is what it asks for (OfficeBar.chime_toggled).
signal chime_toggled(on: bool)
## An entry of the NEWS row was clicked: pick pane `key`, as the list does.
signal news_picked(key: String)
## A row of the EVENTS page was clicked: pick pane `key`, keeping that page.
signal event_picked(key: String)
## The mouse came onto a NEWS item, a row of the agent list, of HISTORY or of
## EVENTS, or a portrait card, about pane `key`, or left it (`""`): the office
## points at that desk, and only points.
signal pane_pointed(key: String)
## The same for an edge arrow and its zone `key`: the office outlines that
## zone's blocked cards in the top bar.
signal zone_pointed(key: String)
## The bottom panel's HISTORY or EVENTS page has just come into sight: the
## office lays it out now rather than on its next refresh.
signal page_shown(page: OfficeBottomPanel.Page)

## The overview closed (its `X  Esc`, Esc or `O`): the office shows the world again.
signal overview_closed
## A row of the overview was pressed: pick pane `key`, as a click on its desk does.
signal overview_picked(key: String)
## The overview's sort or filter changed: the office draws it again at once.
signal overview_changed
## The strategic view closed (`S`, Escape, or a square clicked): the office
## shows the world again, unless the overview covers it.
signal strategic_closed
## A square of the strategic view was clicked: pick pane `key` (the view has
## closed first).
signal strategic_picked(key: String)

## The overview's chip each portrait fold stands for (filter_of()): the one
## place a group of the top bar and a chip of the overview are matched.
const FOLD_FILTERS: Dictionary[PortraitBarModel.Group, OverviewModel.Filter] = {
	PortraitBarModel.Group.BLOCKED: OverviewModel.Filter.BLOCKED,
	PortraitBarModel.Group.DONE: OverviewModel.Filter.DONE,
	PortraitBarModel.Group.WORKING: OverviewModel.Filter.WORKING,
	PortraitBarModel.Group.IDLE: OverviewModel.Filter.IDLE,
}

## What the world keeps clear of the panels: to the side of the right column,
## and above the bottom panel and below the bar. The rest of the geometry is the
## scene's.
@export var world_gap := Vector2(8, 16)
## The world's left edge from the screen's: the bottom panel's inset, so the
## two line up. Set in the scene.
@export var world_left := 0.0
## Where the world tooltip (over a blocked agent's chip, over a zone's sign) stands from the pointer. Set in the scene.
@export var tip_gap := Vector2.ZERO
## The right-hand drawer's left edge, open, from the screen's right (see
## _fit_drawer()); closed, it takes no room at all. Set in the scene.
@export var drawer_open_left := 0.0
## The bottom panel's bottom edge, and its top edge docked (a screen at least
## `staff_tall_from` high: always open, its preview CardPicture.DOCKED_ROWS
## rows), opened from its line on a shorter screen (the whole preview), and
## folded to its two rows there (the top row over the card's line), from the
## screen's bottom (see _fit_staff()). Set in the scene.
@export var staff_bottom := 0.0
@export var staff_docked_top := 0.0
@export var staff_opened_top := 0.0
@export var staff_compact_top := 0.0
## The bottom panel's inset from the screen's sides along the bottom, and its
## widest and tallest in answer mode, where it stands in the middle under the
## bar, at least `staff_modal_gap` clear of the bar and of the screen's bottom
## (see _fit_staff()). Set in the scene.
@export var staff_inset := 0.0
@export var staff_modal_width := 0.0
@export var staff_modal_height := 0.0
@export var staff_modal_gap := 0.0
## The logical screen height from which the bottom panel is docked, always
## open, and the bar is `bar_tall_height` tall; below it the panel folds to
## its two rows and the bar is `bar_short_height` (see _fit_staff(), fit()).
## Set in the scene.
@export var staff_tall_from := 0.0
## The logical screen width from which NEXT stays beside the panel at full
## height, and the one-line row says its long words (`Monitor`, `Open`,
## NEXT's whole line); below it, the full panel needs NEXT's room for its
## preview and the row says its short ones. Set in the scene.
@export var staff_next_from := 0.0
## The same for the docked panel: below this screen width the card's columns
## (its left column, the preview and the 240-wide launch block) need NEXT's
## room, and the right-hand column keeps only the verbs.
@export var staff_docked_next_from := 0.0
## NEXT's width, and its width from `staff_next_from` where it says `NEXT:`,
## whom and the wait in a row (the docked panel, the one-line row); and its
## height docked, where it is a pill over `‹ ›` (see _fit_staff()). Set in the scene.
@export var next_width := 0.0
@export var next_wide_width := 0.0
@export var next_docked_height := 0.0
## The world width below which the edge arrows leave their zone's number to the
## tooltip (see _fit_edge_arrows()). Set in the scene.
@export var edge_arrows_compact_from := 0.0
## The logical screen width from which the bar shows `13 panes` and the chime switch. Set in the scene.
@export var bar_titles_from := 0.0
## The top bar's height on a screen at least `staff_tall_from` high, and below
## it (see fit()). Set in the scene.
@export var bar_tall_height := 0.0
@export var bar_short_height := 0.0
## What the OVERVIEW and the right column keep clear under the bar. Set in the scene.
@export var panel_top_gap := 0.0
## The logical screen width from which the overview shows every column. Set in the scene.
@export var overview_full_from := 0.0
## Whether this HUD has a NEWS line at all: the showroom has none (preview.gd),
## the office always does. It stands in the bottom panel's top row (_fit_staff()).
var news_wanted := true

## The parts, resolved on first use: the office reaches the HUD before any of
## them is in the tree, so `@onready` would be too late.
var bar: OfficeBar:
	get:
		if _bar == null:
			_bar = $Screen/Bar
		return _bar

## The agent card: the bottom panel's AGENT page.
var inspector: OfficePaneInspector:
	get:
		if _inspector == null:
			_inspector = staff.card
		return _inspector

var agent_list: AgentList:
	get:
		if _agent_list == null:
			_agent_list = $Screen/RightColumn/ListHolder/Pages/AgentList
		return _agent_list

## The right-hand drawer: the agent list while open, nothing while closed;
## where it stands is what the world keeps clear of.
var right_column: Control:
	get:
		return $Screen/RightColumn

## The bottom panel (its AGENT page is `inspector`): it takes room from the
## world's bottom while it is visible, and it is the node answer mode floats.
var staff: OfficeBottomPanel:
	get:
		return %Staff

## The arrows on the world's edges; they stand over the world and take no room.
var edge_arrows: OfficeEdgeArrows:
	get:
		return %EdgeArrows

## The NEWS line in the bottom panel's top row (the showroom hides it).
var news: OfficeNews:
	get:
		return staff.news

## The OVERVIEW, over the world and both side columns while it is open. It
## covers them and takes no room: nothing is laid out again for it.
var overview: OfficeOverview:
	get:
		return %Overview

## The strategic view (`S`) over the world rect while it is open; it covers
## the world, as the OVERVIEW does, and takes no room.
var strategic: OfficeStrategic:
	get:
		return %Strategic

## The drawer's tab row (AGENTS only).
var drawer_tabs: TabBar:
	get:
		return %DrawerTabs

## The bottom panel's EVENTS page.
var event_list: EventList:
	get:
		return staff.events

## The bottom panel's HISTORY page.
var history_list: HistoryList:
	get:
		return staff.history

## The terminal monitor, over everything else when it is open.
var monitor: TerminalMonitor:
	get:
		if _monitor == null:
			_monitor = $Screen/Monitor
		return _monitor

## Logical screen the panels are laid out on; the office sets it with fit().
var _screen := Vector2(800, 480)
var _bar: OfficeBar
var _inspector: OfficePaneInspector
var _agent_list: AgentList
## The bottom panel is down to its two rows; see _fit_staff().
var _compact := false
## The drawer shows the agent list (open) or nothing; see _fit_drawer().
## Every run starts with it closed, whatever an earlier run left.
var _drawer_open := false
## The bottom panel was opened up from its line (expand_card(), or answer mode).
var _expanded := false
## Whether the edge arrows were last handed any (show_edge_arrows()): an
## overlay closing shows the same arrows again without a refresh.
var _arrows_shown := false
## What _process() last saw of the card: answering, and the pane it shows
## (the panel was opened for that pane; another one folds it).
var _was_answering := false
var _expanded_pane := ""
## In answer mode the panel floats in the middle of the screen, and its slot
## along the bottom, which the world keeps clear of, is kept here: its top and
## bottom edges from the screen's bottom (see _fit_staff()).
var _floating := false
var _slot_top := 0.0
var _slot_bottom := 0.0
var _monitor: TerminalMonitor
## Agents that need a human now (AttentionStore.current()): only counted since
## the drawer lost its closed tab; its records go with the list.
var _attention_count := 0


func _ready() -> void:
	bar.zone_picked.connect(func(key: String) -> void: zone_picked.emit(key))
	bar.machine_picked.connect(func(key: String) -> void: machine_picked.emit(key))
	edge_arrows.arrow_picked.connect(func(key: String) -> void: arrow_picked.emit(key))
	edge_arrows.zone_pointed.connect(func(key: String) -> void: zone_pointed.emit(key))
	bar.portrait_picked.connect(func(key: String) -> void: portrait_picked.emit(key))
	bar.portrait_pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	bar.fold_pressed.connect(func(group: PortraitBarModel.Group) -> void: fold_pressed.emit(group))
	bar.panes_pressed.connect(func() -> void: panes_pressed.emit())
	bar.chime_toggled.connect(func(on: bool) -> void: chime_toggled.emit(on))
	agent_list.pane_picked.connect(_on_list_pick)
	agent_list.pane_activated.connect(_on_list_open)
	agent_list.history_locate_requested.connect(func(key: String) -> void: history_locate_requested.emit(key))
	agent_list.snooze_requested.connect(
		func(id: String, seconds: int) -> void: attention_snooze_requested.emit(id, seconds)
	)
	agent_list.hidden_changed.connect(
		func(id: String, is_hidden: bool) -> void: attention_hidden_changed.emit(id, is_hidden)
	)
	agent_list.layout_changed.connect(func() -> void: agent_list_changed.emit())
	agent_list.keyboard_changed.connect(_fit_room)
	agent_list.keyboard_changed.connect(_show_keyboard_cue)
	var collapse: Button = %Collapse
	collapse.pressed.connect(close_drawer)
	event_list.picked.connect(func(key: String) -> void: event_picked.emit(key))
	history_list.picked.connect(func(key: String) -> void: history_picked.emit(key))
	history_list.pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	# A page shown is laid out first (on a short screen HISTORY and EVENTS open
	# the panel), then the office hears of a page that came into sight.
	staff.page_changed.connect(func(_which: OfficeBottomPanel.Page) -> void: _fit_room())
	staff.page_shown.connect(func(which: OfficeBottomPanel.Page) -> void: page_shown.emit(which))
	inspector.monitor_requested.connect(func(key: String) -> void: monitor_requested.emit(key))
	inspector.next_requested.connect(func() -> void: next_requested.emit())
	inspector.step_requested.connect(func(direction: int) -> void: step_requested.emit(direction))
	# The line's `Open` and the panel's `▾ Esc` are the HUD's own: they only
	# open the panel or fold it, which is the HUD's layout, not the office's.
	inspector.open_requested.connect(expand_card)
	inspector.fold_requested.connect(compact_card)
	inspector.pane_split.connect(pane_split.emit)
	inspector.space_created.connect(space_created.emit)
	monitor.closed.connect(_on_monitor_closed)
	news.picked.connect(func(key: String) -> void: news_picked.emit(key))
	news.pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	agent_list.pane_pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	event_list.pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	overview.closed.connect(_on_overview_closed)
	overview.picked.connect(func(key: String) -> void: overview_picked.emit(key))
	overview.sort_changed.connect(func(_by: OverviewModel.Sort, _reversed: bool) -> void: overview_changed.emit())
	overview.filter_changed.connect(_on_overview_filter)
	strategic.closed.connect(_on_strategic_closed)
	strategic.picked.connect(_on_strategic_picked)


## Build the Theme from `art` and hand every part the pack's own textures.
## Called once at startup and again on a theme switch, which rebuilds no node.
func dress(art: ArtPack, font: Font) -> void:
	var screen: Control = $Screen
	screen.theme = HudTheme.build(art, font)
	bar.dress(art)
	edge_arrows.dress(art)
	staff.dress(art)
	agent_list.dress(art)
	monitor.dress(art)
	overview.dress(art)
	strategic.dress(art)
	var tip: HdPanel = %WorldTip
	tip.dress(art)


## The world tooltip, over a blocked agent's chip or a zone's sign: `text` (the question's excerpt
## or why there is none; the sign's repository and checkout), near the pointer at `at` (viewport pixels), kept
## inside world_rect(). The office says what and where; nothing here reads herdr.
func show_world_tip(text: String, at: Vector2) -> void:
	var tip: Control = %WorldTip
	var label: Label = %WorldTipText
	if label.text != text:
		label.text = text
	tip.reset_size()
	var room := world_rect()
	var corner := (room.end - tip.size).max(room.position)
	tip.position = (at + tip_gap).clamp(room.position, corner)
	tip.visible = true


func hide_world_tip() -> void:
	var tip: Control = %WorldTip
	tip.visible = false


## Whether the world tooltip is up, and what it says.
func world_tip_shown() -> bool:
	var tip: Control = %WorldTip
	return tip.visible


func world_tip_text() -> String:
	var label: Label = %WorldTipText
	return label.text


## The Theme dress() built, for furniture in the world that reads like the HUD
## (the machine plate): the same pack, the same variations, built once.
func screen_theme() -> Theme:
	var screen: Control = $Screen
	return screen.theme


## How many agents need a human now: current attention, snoozed and hidden
## records left out (attention_count()).
func show_attention(current_items: Array[AttentionItem]) -> void:
	_attention_count = current_items.size()


func attention_count() -> int:
	return _attention_count


## The NEWS line's entries, newest first (NewsItem, the office's); see OfficeNews.
func show_news(items: Array[NewsItem]) -> void:
	news.show_news(items)


## The EVENTS page's rows: the log's `events`, newest on top; `pickable` says
## whether a pane key is still there to pick. See EventList.
func show_events(
	events: Array[StateLog.Event], pickable: Callable, selected: String, opened_unix: float, several: bool
) -> void:
	event_list.show_events(events, pickable, selected, opened_unix, several)


## The HISTORY page's lines (AgentHistory, newest first), `selected` highlighted,
## the log opened at `opened_unix`. See HistoryList.
func show_history(lines: Array[AgentHistory.Line], selected: String, opened_unix: float) -> void:
	history_list.show_history(lines, selected, opened_unix)


## Show the bottom panel's page `which` (its tab's click comes through the
## panel too). Every run starts on AGENT and nothing is remembered. On a tall
## screen the panel is docked whatever its page, so the world never moves; on
## a short one HISTORY and EVENTS open it and AGENT folds it back to its line,
## as before (_fit_staff() reads the page; the panel's page_changed lays it out).
func show_page(which: OfficeBottomPanel.Page) -> void:
	staff.show_page(which)


## The bottom panel's page shown.
func page() -> OfficeBottomPanel.Page:
	return staff.page()


## The AGENT page: the card. A pick, `N`, a chip click and Enter show it.
func show_card_page() -> void:
	show_page(OfficeBottomPanel.Page.AGENT)


## The AGENTS tab's word in the blocked colour while the list holds the
## keyboard.
func _show_keyboard_cue() -> void:
	var look := &"DrawerTabsHeld" if agent_list.has_keyboard() else &"DrawerTabs"
	if drawer_tabs.theme_type_variation != look:
		drawer_tabs.theme_type_variation = look


## Every pane in the agent list, `selected` highlighted; see AgentList.
func show_agents(
	frame: OfficeFrame, active: Array[AttentionItem], history: Array[AgentHistory.Line], selected: String, now_msec: int
) -> void:
	agent_list.show_agents(frame, active, history, selected, now_msec)


## `A` (and nothing else: the drawer has no closed tab): the drawer opens and
## the list takes the keyboard in its flat view, or lets it go when it has it.
## Taking it ends the card's answer mode, so no key the list lets through can
## answer an agent behind the viewer's back. The bottom panel's page stays.
func toggle_agent_list() -> void:
	open_drawer()
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
		return
	inspector.leave_answer()
	_fit_room()
	agent_list.take_keyboard()


## The agent list shows only the panes in `presences`; the same again shows
## every pane. Applying a filter opens the drawer, or the filtered list is out
## of sight; clearing one leaves the drawer as it is.
## Nothing is picked and the keyboard stays where it is. The top bar no longer
## asks for it (a fold opens the OVERVIEW instead); the list keeps it until
## the drawer retires.
func toggle_list_filter(presences: Array[AgentListModel.Presence]) -> void:
	if agent_list.presence_filter() == presences:
		agent_list.set_presence_filter([])
		return
	open_drawer()
	agent_list.set_presence_filter(presences)


## Whether the list, the overview or the strategic view holds the keyboard:
## the arrows are theirs (or nobody's), not the camera's.
func holds_keyboard() -> bool:
	return agent_list.has_keyboard() or overview_open() or strategic_open()


## Whether the overview is open over the world.
func overview_open() -> bool:
	return overview.visible


## Open the overview over the world and both side columns (they stay where
## they are: nothing is laid out again). The list lets the keyboard go; the
## bottom panel below stays as it is, answer mode included. `13 panes` reads
## pressed, and so does the fold of the state the overview's chip keeps.
func open_overview() -> void:
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
	hide_world_tip()
	overview.open()
	_fit_edge_arrows()
	bar.set_overview(true)
	bar.set_fold_on(_fold_of(overview.filter()))


func close_overview() -> void:
	overview.close()


## The overview's rows, from the office's model.
func show_overview(model: OverviewModel, art: ArtPack) -> void:
	overview.show_overview(model, art)


## However it closed: `13 panes` and every fold are released.
func _on_overview_closed() -> void:
	_fit_edge_arrows()
	bar.set_overview(false)
	bar.set_fold_on(-1)
	overview_closed.emit()


func _on_overview_filter(keep: OverviewModel.Filter) -> void:
	if overview_open():
		bar.set_fold_on(_fold_of(keep))
	overview_changed.emit()


## The overview's chip a portrait fold stands for: its group's state.
static func filter_of(group: PortraitBarModel.Group) -> OverviewModel.Filter:
	return FOLD_FILTERS[group]


## The fold a chip stands for in the bar; −1 for ALL.
static func _fold_of(keep: OverviewModel.Filter) -> int:
	for group in FOLD_FILTERS:
		if FOLD_FILTERS[group] == keep:
			return group
	return -1


## Whether the strategic view is open over the world rect.
func strategic_open() -> bool:
	return strategic.visible


## Open the strategic view over the world rect (the office shows it a model
## right after). The world tooltip and the edge arrows go; the list keeps the
## keyboard it has, and the bottom panel stays as it is. The top bar's theme
## line says `STRATEGIC · S`.
func open_strategic() -> void:
	hide_world_tip()
	strategic.open()
	_fit_edge_arrows()
	bar.show_strategic(true)


func close_strategic() -> void:
	strategic.close()


## The strategic view's schematic, from the office's model, over the world
## rect as it is now (world_rect(), as the edge arrows stand in it).
func show_strategic(model: StrategicModel) -> void:
	var room := world_rect()
	if strategic.position != room.position:
		strategic.position = room.position
	if strategic.size != room.size:
		strategic.size = room.size
	strategic.show_model(model)


## A HUD line under the mouse names pane `key`: the strategic view dashes its
## square (empty, or a pane it has no square for: none).
func point_strategic(key: String) -> void:
	strategic.point(key)


## Scroll the open strategic view to the section of zone `key`: a card's place
## or a page key picked it under the view.
func reveal_strategic_section(key: String) -> void:
	strategic.reveal_section(key)


## However it closed: the theme line says the pack again.
func _on_strategic_closed() -> void:
	_fit_edge_arrows()
	bar.show_strategic(false)
	strategic_closed.emit()


## A square was clicked: close the view first, then say which pane.
func _on_strategic_picked(key: String) -> void:
	close_strategic()
	strategic_picked.emit(key)


## Open the drawer: the agent list stands in the right column again. Only the
## drawer opens; the list takes no keyboard (that is `A`).
func open_drawer() -> void:
	if _drawer_open:
		return
	_drawer_open = true
	_fit_room()
	agent_list_changed.emit()


## Close the drawer (the ▶ beside the drawer's tab): it takes no room then.
## The list lets the keyboard go first: a list out of sight holds no keys.
func close_drawer() -> void:
	if not _drawer_open:
		return
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
	_drawer_open = false
	_fit_room()
	agent_list_changed.emit()


func toggle_drawer() -> void:
	if _drawer_open:
		close_drawer()
	else:
		open_drawer()


## Whether the drawer shows the agent list; the office remembers it.
func drawer_open() -> bool:
	return _drawer_open


## Whether the bottom panel is down to its two rows (see _fit_staff()). The
## card is told this covers it: its preview is out of sight, so it reads nothing.
func card_compact() -> bool:
	return _compact


## Whether the panel was opened up from its line on a short screen and is not
## answering (Escape folds it then; in answer mode Escape only leaves answer
## mode). On a tall screen there is nothing to fold, and an Escape that folded
## nothing must reach the OVERVIEW and the strategic view.
func card_expanded() -> bool:
	return _expanded and not inspector.answering() and _screen.y < staff_tall_from


## Open the bottom panel up from its line to full height: Enter on a shown pane,
## the line's `Open`, or answer mode. It folds again on Escape out of answer
## mode, the panel's `▾ Esc`, the card aimed at another pane, or compact_card();
## answer mode ending by itself leaves it open, so what a sent key did stays in
## sight, and so does a new terminal, agent or connection in the same pane (a
## start's progress, a reconnect). `for_key` is the pane the office is about to
## aim the card at (a split's new pane), when that is not the one shown yet.
func expand_card(for_key := "") -> void:
	# A closed card (its `×`) opens only on a pick of the viewer's own, which
	# un-closes it in show_pane() before anything opens it.
	if inspector.closed():
		return
	_expanded = true
	_expanded_pane = for_key if not for_key.is_empty() else inspector.shown_pane_key()
	_fit_room()


func compact_card() -> void:
	_expanded = false
	_fit_room()


## Answer mode opening, and the card being aimed at another pane, change what
## the column shows; the card says neither, so the HUD looks each frame. Answer
## mode opening opens the panel for good: its end folds nothing.
func _process(_delta: float) -> void:
	var answering := inspector.answering()
	var pane := inspector.shown_pane_key()
	if answering == _was_answering and pane == _expanded_pane:
		return
	if answering:
		_expanded = true
	elif pane != _expanded_pane:
		_expanded = false
	_was_answering = answering
	_expanded_pane = pane
	_fit_room()


## Every entry that can move a panel (fit(), the card opening or folding, a
## page shown, the list taking the keyboard, answer mode, the drawer) comes
## through here, so the office hears room_changed whenever the world's room
## moved without the window. Each panel's own fit is called from here: the
## drawer first, then the bottom panel, then the right column, which stops
## above the bottom panel while it is shown (at the screen's bottom gap while
## it is not), the overview on that same bottom edge, and the edge arrows last
## (they stand over world_rect(), which reads all of those). Every edge is one of
## the scene's values. The order is final: no panel adds a step of its own.
func _fit_room() -> void:
	var moved := _fit_drawer()
	moved = _fit_staff() or moved
	var bottom := _column_bottom()
	if right_column.offset_bottom != bottom:
		right_column.offset_bottom = bottom
		moved = true
	moved = _fit_overview() or moved
	_fit_edge_arrows()
	if moved:
		room_changed.emit()


## Where the right column (and the overview) stops, from the screen's bottom.
func _column_bottom() -> float:
	if staff.visible:
		return _staff_top() - world_gap.y
	return -world_gap.y


## The drawer open is the agent list, `drawer_open_left` from the screen's
## right; closed, the right column is hidden and takes no room. True when its
## edge moved.
func _fit_drawer() -> bool:
	var holder: Control = %ListHolder
	holder.visible = _drawer_open
	var moved := right_column.visible != _drawer_open
	right_column.visible = _drawer_open
	if right_column.offset_left != drawer_open_left:
		right_column.offset_left = drawer_open_left
		moved = true
	return moved


## The bottom panel along the bottom (`staff_bottom`), its top edge one of
## three. On a screen at least `staff_tall_from` high it is docked
## (`staff_docked_top`) whatever its page: always open, the card's preview
## CardPicture.DOCKED_ROWS rows, nothing to fold. Below that it is two rows
## (`staff_compact_top`: the top row over the card's line: who, state and
## seat, the wait, Monitor, Open, and NEXT with `‹ ›`) until it is opened:
## Enter on a shown pane, the line's `Open`, answer mode, and the HISTORY or
## EVENTS page open it to `staff_opened_top` (the whole preview); Escape out
## of answer mode, its `▾ Esc` and the AGENT tab fold it (see expand_card()).
## At full height on a screen narrower than `staff_next_from` (docked:
## `staff_docked_next_from`), the preview takes NEXT's room; from that width
## NEXT says its words in a row where it can (docked, or the line) and is
## `next_wide_width` wide. Only which value
## applies, and `visible`, change here. True when an edge of its slot moved.
##
## In answer mode the panel, at most `staff_modal_width` wide and
## `staff_modal_height` tall (less on a screen without the room,
## `staff_modal_gap` clear of the bar and the bottom), stands in the middle under
## the bar, over the dim (`%ModalDim`): a modal, laid out top to bottom by the
## card itself; its slot along the bottom stays where it was and the world keeps
## clear of it, so leaving answer mode drops the panel back into it and lays
## nothing out again. The dim only darkens: a click goes through it, so a click
## on another desk or chip picks that pane, which leaves answer mode as it
## always has (a new binding), and the next agent can be answered from there.
func _fit_staff() -> bool:
	var answering := inspector.answering()
	var docked := _screen.y >= staff_tall_from
	var page_open := staff.page() != OfficeBottomPanel.Page.AGENT
	var full := answering or _expanded or docked or page_open
	var width := _screen.x - 2.0 * staff_inset
	if answering:
		width = minf(width, staff_modal_width)
	var wide := width + 2.0 * staff_inset >= staff_next_from
	_compact = not full
	inspector.set_docked(docked)
	inspector.set_compact(_compact)
	inspector.set_wide(wide)
	var room_for_next := wide and (not docked or answering or _screen.x >= staff_docked_next_from)
	inspector.set_next_shown(not full or room_for_next)
	var in_a_row := _compact or (docked and not answering)
	inspector.set_next_width(next_wide_width if in_a_row and wide else next_width)
	inspector.set_next_height(next_docked_height if docked and not answering else 0.0)
	staff.set_top_row(not answering)
	staff.set_news_shown(news_wanted)
	var floor_y := staff_bottom
	var top := staff_compact_top
	if full:
		top = staff_docked_top if docked else staff_opened_top
	var before := Vector2(_staff_top(), _slot_bottom if _floating else staff.offset_bottom)
	var dim: Control = %ModalDim
	dim.visible = answering
	_floating = answering
	_slot_top = top
	_slot_bottom = floor_y
	var side := (_screen.x - width) / 2.0
	staff.offset_left = side
	staff.offset_right = -side
	if answering:
		var below := placed(bar).end.y + staff_modal_gap
		var room := _screen.y - below - staff_modal_gap
		var height := minf(staff_modal_height, room)
		staff.offset_top = below - _screen.y + roundf((room - height) / 2.0)
		staff.offset_bottom = staff.offset_top + height
	else:
		staff.offset_top = top
		staff.offset_bottom = floor_y
	return before != Vector2(top, floor_y)


## The top of the bottom panel's slot along the bottom, from the screen's
## bottom: where the panel stands, or would stand while it floats.
func _staff_top() -> float:
	return _slot_top if _floating else staff.offset_top


## The overview stops where the right column does, so it covers it and the
## world beside it exactly, and starts `panel_top_gap` under the bar. It is
## not in world_rect(): it covers, it takes no room. True when an edge moved
## (only the window moves it).
func _fit_overview() -> bool:
	overview.set_compact(_screen.x < overview_full_from)
	var bottom := _column_bottom()
	var top := placed(bar).end.y + panel_top_gap
	if overview.offset_bottom == bottom and overview.offset_top == top:
		return false
	overview.offset_bottom = bottom
	overview.offset_top = top
	return true


## The arrows on the world's edges toward the zones of the shown map with
## blocked desks off screen (EdgeArrowModel, the office's); none hides them.
## Kept by the arrows themselves, so an overlay closing or the world's room
## changing shows or places the same arrows without a refresh
## (_fit_edge_arrows()): an edge too short for its arrows folds the last of
## them into a `+N` note, and unfolds them when it has the room again.
func show_edge_arrows(arrows: Array[EdgeArrowModel]) -> void:
	_arrows_shown = not arrows.is_empty()
	edge_arrows.show_arrows(arrows)
	_fit_edge_arrows()


## Whether the arrows leave their zone's number to the tooltip: a world
## narrower than `edge_arrows_compact_from` (the 480x320 minimum, 4x), where a
## full arrow would cover too much of it. The top bar's blocked cards say who
## waits there, and NEXT names who is next.
func edge_arrows_compact() -> bool:
	return world_rect().size.x < edge_arrows_compact_from


## The edge arrows stand over the world rect, inside its edges (OfficeEdgeArrows
## places each on its own edge). Shown while there are any and nothing covers
## the world: not under the OVERVIEW, the strategic view or the terminal
## monitor. They cover the world where they stand: a chip under one cannot be
## clicked or hovered.
func _fit_edge_arrows() -> void:
	edge_arrows.visible = _arrows_shown and not overview_open() and not strategic_open() and not monitor_open()
	edge_arrows.set_compact(edge_arrows_compact())
	var room := world_rect()
	if edge_arrows.position != room.position:
		edge_arrows.position = room.position
	if edge_arrows.size != room.size:
		edge_arrows.size = room.size


func _on_list_pick(key: String, _by_keyboard: bool) -> void:
	agent_picked.emit(key)


func _on_list_open(key: String) -> void:
	monitor_requested.emit(key)


## Open the terminal monitor on `context` (HerdrFleet.context_for() of the
## pane). One at a time: while one is open, this does nothing.
func open_monitor(context: CommandContext) -> void:
	# The card's reply box and the list let go first: the monitor takes the keyboard.
	inspector.leave_answer()
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
	monitor.open_monitor(context)
	_fit_edge_arrows()


func close_monitor() -> void:
	monitor.close_monitor()


func monitor_open() -> bool:
	return monitor.is_open()


## The monitor closed, however: the edge arrows it covered are back.
func _on_monitor_closed() -> void:
	_fit_edge_arrows()
	monitor_closed.emit()


## Lay the panels out for a `screen`-sized viewport: the bar's height first
## (`bar_tall_height` on a screen at least `staff_tall_from` high, its cards
## B2's tiles; `bar_short_height` below, the horizontal cards), then every
## panel under it.
func fit(screen: Vector2) -> void:
	_screen = screen
	var control: Control = $Screen
	if control.size != screen:
		control.size = screen
	bar.set_titled(screen.x >= bar_titles_from)
	var band := bar_tall_height if screen.y >= staff_tall_from else bar_short_height
	if bar.offset_bottom != band:
		bar.offset_bottom = band
	bar.set_tall(screen.y >= staff_tall_from)
	var top := band + panel_top_gap
	if right_column.offset_top != top:
		right_column.offset_top = top
	_fit_room()


## The screen area left over for the office, from where the panels stand: from
## `world_left` (the bottom panel's inset) to the right column. Each slot takes
## room only while it is visible: the showroom hides the right column
## (preview.gd), and the drawer closed takes none. The edge arrows never take
## any: they stand over the world.
func world_rect() -> Rect2:
	var right := placed(right_column)
	var origin := Vector2(world_left, placed(bar).end.y + world_gap.y)
	var corner := Vector2(_screen.x - world_gap.x, right.end.y)
	if right_column.visible:
		corner.x = right.position.x - world_gap.x
	if staff.visible:
		corner.y = _screen.y + _staff_top() - world_gap.y
	return Rect2(origin, (corner - origin).maxf(0.0))


## The width a floor is planned for the first time it is shown: the world's
## width with the drawer closed, whatever the viewer has opened, so a floor's
## plan does not depend on the drawer. The drawer open covers the plan's
## right-hand desks; the camera pans to them (world_rect() still stops at the
## open drawer). (The bottom panel's height moves only the world's bottom.)
## Worked out from the scene's values; no node moves.
func plan_width() -> float:
	return maxf(_screen.x - world_gap.x - world_left, 0.0)


## Where a panel lands on the screen fit() was given, from the anchors and
## offsets its scene carries. Godot resolves those at the end of a frame and
## only inside the tree; the world has to know before it lays a floor out.
func placed(control: Control) -> Rect2:
	var left := control.anchor_left * _screen.x + control.offset_left
	var top := control.anchor_top * _screen.y + control.offset_top
	var right := control.anchor_right * _screen.x + control.offset_right
	var bottom := control.anchor_bottom * _screen.y + control.offset_bottom
	return Rect2(left, top, right - left, bottom - top)


## The top bar's right-hand lines. `alarmed` is a machine being offline.
func show_bar(theme_name: String, status: String, alarmed: bool) -> void:
	bar.show_bar(theme_name, status, alarmed)


## The top bar's portrait strip (`model`), and from `totals` its
## `1 machine · 13 panes`,
## the status line's hover and, among several machines, a chip per machine,
## `shown`'s (the machine whose map is drawn) the current one.
func show_portraits(model: PortraitBarModel, totals: OfficeTotals, shown := "") -> void:
	bar.show_machines(totals.machine_rows, shown, totals.machines_total > 1)
	bar.show_portraits(model, totals)


## Outline the portrait cards of panes `keys` as pointed at (a HUD line about a
## pane on another machine, an edge arrow's zone's blocked agents), and no
## other; a pane folded into a fold or a tally has no card to outline.
func point_cards(keys: PackedStringArray) -> void:
	bar.point(keys)


## Each blocked card's wait, by pane key, on attention's beat.
func show_waits(texts: Dictionary[String, String]) -> void:
	bar.show_waits(texts)


## Whether the chime is on, as the top bar's switch shows it (OfficeBar.show_chime()).
func show_chime(on: bool) -> void:
	bar.show_chime(on)
