class_name PortraitFold
extends Button
## The agents of one group the portrait strip has no room to show as cards or
## faces (scenes/ui/portrait_fold.tscn): `+12` over herdr's word for the group
## (`working`), or, tallied on a crowded bar, `+12` alone. Hovering it names
## who is in it; a press is the bar's to say (OfficeBar.fold_pressed). Its
## frame wears the group's colour, and it reads pressed while the OVERVIEW
## shows that state alone.
##
## There is one per group, permanent, in the scene; data only changes its text,
## width, look and visibility.

## A fold's tooltip names at most this many agents, then `+N more`.
const TIP_LINES := 12
## The frame each group wears, and pressed.
const LOOKS: Dictionary[PortraitBarModel.Group, StringName] = {
	PortraitBarModel.Group.BLOCKED: &"PortraitFoldBlocked",
	PortraitBarModel.Group.DONE: &"PortraitFoldDone",
	PortraitBarModel.Group.WORKING: &"PortraitFoldWorking",
	PortraitBarModel.Group.IDLE: &"PortraitFoldIdle",
}

## Which group this fold stands for. Set in the scene.
@export var group := PortraitBarModel.Group.BLOCKED
## The width of the tally form. Set in the scene.
@export var tally_width := 0.0

var _folded: Array[PortraitBarModel.Card] = []
var _tally := false
var _on := false
## The fold form's width, as the scene sets it (custom_minimum_size), kept
## from before the tally form first changes it; −1 until asked.
var _fold_width := -1.0


func _ready() -> void:
	var word: Label = %Word
	word.text = PortraitBarModel.WORDS[group]
	_restyle()


## `folded` are the group's agents with no card or face; `tally` is the
## number alone.
func show_fold(folded: Array[PortraitBarModel.Card], tally: bool) -> void:
	_folded = folded
	_tally = tally
	var count: Label = %Count
	var word: Label = %Word
	count.text = "+%d" % folded.size()
	word.visible = not tally
	var full := _full_width()
	custom_minimum_size.x = tally_width if tally else full
	visible = not folded.is_empty()


## The OVERVIEW shows this group's state alone: the fold reads pressed.
func set_on(on: bool) -> void:
	_on = on
	_restyle()


func is_on() -> bool:
	return _on


func tallied() -> bool:
	return _tally


func count_text() -> String:
	var count: Label = %Count
	return count.text


func folded_cards() -> Array[PortraitBarModel.Card]:
	return _folded


## The width this fold needs as a fold or as a tally, from the scene's sizes.
func needed_width(tally: bool) -> float:
	return tally_width if tally else _full_width()


func _full_width() -> float:
	if _fold_width < 0.0:
		_fold_width = custom_minimum_size.x
	return _fold_width


func _restyle() -> void:
	theme_type_variation = StringName(str(LOOKS[group]) + ("On" if _on else ""))


func _get_tooltip(_at: Vector2) -> String:
	return tooltip_of(_folded)


## Up to TIP_LINES lines `name · space` (`@ machine` among several machines),
## then `+N more`.
static func tooltip_of(folded: Array[PortraitBarModel.Card]) -> String:
	var lines := PackedStringArray()
	for index in mini(folded.size(), TIP_LINES):
		var card := folded[index]
		var line := "%s · %s" % [card.name, card.place]
		if not card.machine_label.is_empty():
			line += " @ " + card.machine_label
		lines.append(line)
	if folded.size() > TIP_LINES:
		lines.append("+%d more" % (folded.size() - TIP_LINES))
	return "\n".join(lines)
