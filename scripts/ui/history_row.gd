class_name HistoryRow
extends Button
## One line of the bottom panel's HISTORY page (AgentHistory.Line), on one
## line: the badge of what the pane waited as (blocked, or done's UNREAD mark),
## who, the space, and at the tail OFFLINE or GONE for a pane whose machine is
## away or that closed (an ENDED pane has no tail). A line whose pane is still
## the terminal the log saw (`locatable`) picks it on a click; every other line
## is greyed and cannot be clicked, and its tooltip says why. Kept for as long
## as its line is in the history, updated in place.

## A click on a locatable line: pick pane `pane_key`.
signal picked(pane_key: String)

## What the line waited as (AgentHistory.Line.was) -> the state whose badge it
## wears (the marks the retired agent list's History group wore).
const MARKS: Dictionary[String, StringName] = {
	"blocked": ArtContract.STATE_BLOCKED,
	"done": ArtContract.STATE_DONE,
}
## Palette-driven looks for the selected pane's line, the rest, and a line
## that cannot be clicked.
const LOOKS := {
	true: {"row": &"ListRowCurrent", "name": &"LabelPaper", "note": &"LabelPaper"},
	false: {"row": &"ListRow", "name": &"LabelWoodDark", "note": &"LabelSlate"},
}
## Why a line cannot be clicked, by what became of its pane.
const NOT_HERE := "Not here any more: "
const WHY_OFFLINE := "its machine is offline."
const WHY_GONE := "the pane closed."
const WHY_REPLACED := "another terminal or agent run holds this pane now."


## Everything a line shows, as one value (words_of()).
class Words:
	extends RefCounted
	var title := ""
	var space := ""
	var tail := ""
	var mark := &""
	var enabled := false
	var current := false
	var tip := ""


## HerdrFleet.pane_key of the line shown.
var pane_key := ""

var _art: ArtPack
var _mark := &""


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(pane_key))


## Take the pack's badge art. A theme switch calls this again and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	_draw_badge()


## What a row says for `line`, `current` when it is the selected pane's.
## The title is what the office called the pane, else its agent in
## capitals, else AGENT.
static func words_of(line: AgentHistory.Line, current: bool) -> Words:
	var made := Words.new()
	made.title = line.name
	if made.title.is_empty():
		made.title = line.provider.to_upper() if not line.provider.is_empty() else "AGENT"
	made.space = line.space
	made.tail = "" if line.what == AgentHistory.ENDED else line.what
	made.mark = MARKS.get(line.was, ArtContract.STATE_DONE)
	made.enabled = line.locatable
	made.current = current
	# The tab is what a place says for it: none for a workspace's lone default tab.
	var workspace := line.space if not line.space.is_empty() else "Unknown workspace"
	var lines := PackedStringArray([made.title])
	lines.append("%s / %s" % [line.machine_label, workspace] + ("" if line.tab.is_empty() else " / " + line.tab))
	lines.append(AgentHistory.tooltip_of(line))
	if line.locatable:
		lines.append(NewsItem.TIP_PICK)
	elif line.what == AgentHistory.OFFLINE:
		lines.append(NOT_HERE + WHY_OFFLINE)
	elif line.what == AgentHistory.GONE:
		lines.append(NOT_HERE + WHY_GONE)
	else:
		lines.append(NOT_HERE + WHY_REPLACED)
	made.tip = "\n".join(lines)
	return made


## Show `line`, `current` for the selected pane's.
func show_line(line: AgentHistory.Line, current: bool) -> void:
	pane_key = line.key
	var words := words_of(line, current)
	var tones: Dictionary = LOOKS[current]
	theme_type_variation = tones.row
	var title: Label = %Name
	var space: Label = %Space
	var tail: Label = %Tail
	var tone: StringName = tones.name if words.enabled or current else &"LabelMuted"
	var note_tone: StringName = tones.note if words.enabled or current else &"LabelMuted"
	_write(title, words.title, tone)
	_write(space, words.space, note_tone)
	_write(tail, words.tail, note_tone)
	tail.visible = not words.tail.is_empty()
	disabled = not words.enabled
	tooltip_text = words.tip
	if words.mark != _mark:
		_mark = words.mark
		_draw_badge()


## `words` in `label`, written only when they changed, in `look`.
static func _write(label: Label, words: String, look: StringName) -> void:
	if label.text != words:
		label.text = words
	label.theme_type_variation = look


## What the row says, for the tests: the title, the space and the tail.
func shown_text() -> String:
	var title: Label = %Name
	var space: Label = %Space
	var tail: Label = %Tail
	return " ".join(PackedStringArray([title.text, space.text, tail.text])).strip_edges()


## The UI image the badge shows: the pack's badge for the state the line waited as.
func mark() -> StringName:
	if _art == null or _mark.is_empty():
		return &""
	var drawn := _art.state(_mark)
	var id: StringName = drawn.badge if drawn != null else _mark
	if _art.ui_sprite(id) == null:
		id = _art.state(ArtContract.STATE_UNKNOWN).badge
	return id


func _draw_badge() -> void:
	if _art == null:
		return
	var badge: StatusBadge = %Badge
	var id := mark()
	if id.is_empty():
		badge.clear(_art)
		return
	badge.show_badge(_art, id)
	badge.visible = true
	# Every UI image declares its own pivot; the sprite stands at it inside its
	# square, as in the EVENTS page's rows.
	badge.position = _art.ui_sprite(id).pivot
