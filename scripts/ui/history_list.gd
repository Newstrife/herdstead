class_name HistoryList
extends HdPanel
## The bottom panel's HISTORY page: one line per pane whose agent needed a
## human this run and does not now (AgentHistory, from the StateLog), newest
## on top, each a HistoryRow. A click on a line whose pane is still the
## terminal the log saw picks it; the office checks that again before it does.
##
## Plain lines in, pane keys out. Rows are kept by pane key and changed in
## place; a row is made the first time its line is drawn and dropped when the
## line goes. Nothing is laid out while the page is out of sight: the office
## shows it only then.

## A locatable line was clicked: pick pane `pane_key` (OfficeHud.history_picked).
signal picked(pane_key: String)
## The mouse came onto a line about pane `pane_key`, or left it (`""`).
signal pointed(pane_key: String)

@export var row_scene: PackedScene

var _rows: Dictionary[String, HistoryRow] = {}


func _ready() -> void:
	# The panel's thin bar, shown only when rows overflow (the scroll reserves
	# its room either way), never focused.
	var scroll: ScrollContainer = %Scroll
	var bar := scroll.get_v_scroll_bar()
	bar.theme_type_variation = &"PageScroll"
	bar.focus_mode = Control.FOCUS_NONE


## Draw `lines` (AgentHistory, newest first): `selected` is the office's
## selected pane (its line is highlighted), `opened_unix` when the log began.
func show_history(lines: Array[AgentHistory.Line], selected: String, opened_unix: float) -> void:
	var since: Label = %Since
	var said := (
		"since %s · %d line%s"
		% [OfficeAttention.wall_clock(opened_unix), lines.size(), "" if lines.size() == 1 else "s"]
	)
	if opened_unix < 0.0:
		said = ""
	if since.text != said:
		since.text = said
	var wanted: Array[HistoryRow] = []
	for line in lines:
		var row: HistoryRow = _rows.get(line.key)
		if row == null:
			row = _row(line.key)
		row.show_line(line, not selected.is_empty() and line.key == selected)
		wanted.append(row)
	_keep(wanted)
	var empty: Label = %Empty
	empty.visible = wanted.is_empty()


## The row drawn for pane `key`, or null.
func row_for(key: String) -> HistoryRow:
	return _rows.get(key)


## The pane keys of the rows drawn, top to bottom.
func shown_keys() -> PackedStringArray:
	var result := PackedStringArray()
	for node in _rows_box().get_children():
		var row := node as HistoryRow
		if row != null:
			result.append(row.pane_key)
	return result


## Take the pack's art, here and in every row. A theme switch rebuilds nothing.
func dress(pack: ArtPack) -> void:
	super(pack)
	for key: String in _rows:
		_rows[key].dress(pack)


## Drop the rows whose lines are gone and put the rest in `wanted`'s order.
## Nothing already in its place is moved.
func _keep(wanted: Array[HistoryRow]) -> void:
	var keep: Dictionary[String, bool] = {}
	for row in wanted:
		keep[row.pane_key] = true
	for key: String in _rows.keys():
		if not keep.has(key):
			var gone := _rows[key]
			_rows.erase(key)
			_rows_box().remove_child(gone)
			gone.queue_free()
	var box := _rows_box()
	for index in wanted.size():
		if box.get_child(index) != wanted[index]:
			box.move_child(wanted[index], index)


func _row(key: String) -> HistoryRow:
	var row: HistoryRow = row_scene.instantiate()
	row.pane_key = key
	row.picked.connect(func(picked_key: String) -> void: picked.emit(picked_key))
	row.mouse_entered.connect(func() -> void: pointed.emit(row.pane_key))
	row.mouse_exited.connect(func() -> void: pointed.emit(""))
	_rows_box().add_child(row)
	if art != null:
		row.dress(art)
	_rows[key] = row
	return row


func _rows_box() -> VBoxContainer:
	return %Rows
