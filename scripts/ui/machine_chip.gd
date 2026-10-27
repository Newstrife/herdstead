class_name MachineChip
extends Button
## One machine in the top bar, among several (scenes/ui/machine_chip.tscn):
## its label at 8, cut to the chip's width and whole in its tooltip, which is
## that machine's line of the status line's hover (OfficeTotals.machine_line():
## how it answers, when it was last heard from). A click shows that machine's
## map (OfficeBar.machine_picked). Its words say how it answers: paper while
## live, muted while it connects, the blocked colour while it is offline (the
## alarm the MACHINES counter wore); the chip of the machine whose map is drawn
## stands on `slate` (…Current).
##
## The bar keeps one per machine by its key and updates it in place; data only
## changes its text, look and width. It takes no focus, so no key reaches it.

## The look for how the machine answers (HudTheme._machine_chips()); the
## current one adds `Current`.
const LOOKS: Dictionary[MachineLiveness.State, String] = {
	MachineLiveness.State.LIVE: "MachineChip",
	MachineLiveness.State.CONNECTING: "MachineChipConnecting",
	MachineLiveness.State.OFFLINE: "MachineChipOffline",
}

## The chip's width on a bar with titles, and below `OfficeHud.bar_titles_from`. Set in the scene.
@export var wide_width := 0.0
@export var narrow_width := 0.0

## The machine this chip stands for; empty until show_machine().
var key := ""

var _row: OfficeTotals.MachineRow
var _current := false


## Machine `row`; `current` is its map being the one drawn. Only what changed is written.
func show_machine(row: OfficeTotals.MachineRow, current: bool) -> void:
	key = row.key
	_row = row
	_current = current
	if text != row.label:
		text = row.label
	var look := StringName(LOOKS[row.state] + ("Current" if current else ""))
	if theme_type_variation != look:
		theme_type_variation = look


## The narrow chip (`on`) of a bar without titles, or the wide one.
func set_narrow(on: bool) -> void:
	var width := narrow_width if on else wide_width
	if custom_minimum_size.x != width:
		custom_minimum_size.x = width


## Whether this chip's machine has its map drawn.
func is_current() -> bool:
	return _current


## How its machine answers, as last shown.
func machine_state() -> MachineLiveness.State:
	return MachineLiveness.State.OFFLINE if _row == null else _row.state


## Written when the pointer asks: how long ago is the time it rests there.
func _get_tooltip(_at: Vector2) -> String:
	return "" if _row == null else OfficeTotals.machine_line(_row, Time.get_unix_time_from_system())
