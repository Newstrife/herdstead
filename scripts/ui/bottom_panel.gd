class_name OfficeBottomPanel
extends HdPanel
## The panel along the screen's bottom: the one frame there (the one the skin
## dresses), a top row of page tabs (`AGENT | HISTORY | EVENTS`) with the NEWS
## line to their right, and under it the page shown: the agent card
## (OfficePaneInspector), the HISTORY page (HistoryList) or the EVENTS page
## (EventList).
##
## Every run starts on AGENT, and nothing is remembered. A tab only shows its
## page; where the panel stands and how tall it is are the HUD's
## (OfficeHud._fit_staff()). The card reads only while its page shows (its own
## is_visible_in_tree()); HISTORY and EVENTS are laid out only while theirs
## does: page_shown says when one comes into sight. In answer mode the HUD
## floats the panel as a modal and hides the top row (set_top_row()).

## The page shown changed, by a tab's click or show_page(): the HUD lays the
## panel out again (on a short screen HISTORY and EVENTS open it).
signal page_changed(page: Page)
## The HISTORY or EVENTS page has just come into sight: the office lays it out now.
signal page_shown(page: Page)

## The pages, in the order of their tabs.
enum Page { AGENT, HISTORY, EVENTS }

## The agent card: the AGENT page.
var card: OfficePaneInspector:
	get:
		return %Card

## The NEWS line in the top row.
var news: OfficeNews:
	get:
		return %News

## The HISTORY page.
var history: HistoryList:
	get:
		return %History

## The EVENTS page.
var events: EventList:
	get:
		return %Events

## The page tabs.
var tabs: TabBar:
	get:
		return %PageTabs


func _ready() -> void:
	tabs.tab_changed.connect(func(index: int) -> void: show_page(index as Page))
	# The panel draws the one frame; the pages inside draw none.
	history.set_framed(false)
	events.set_framed(false)


## Take the pack: this panel's frame and every page's art.
func dress(pack: ArtPack) -> void:
	super(pack)
	card.dress(pack)
	news.dress(pack)
	history.dress(pack)
	events.dress(pack)


## Show page `which`; its tab's click comes through here too. A page that
## changes says page_changed, and HISTORY or EVENTS coming into sight then
## says page_shown.
func show_page(which: Page) -> void:
	if tabs.current_tab != which:
		# Says tab_changed, which comes back here with the page already current.
		tabs.current_tab = which
		return
	var page_node := _page_node(which)
	if page_node.visible:
		return
	card.visible = which == Page.AGENT
	history.visible = which == Page.HISTORY
	events.visible = which == Page.EVENTS
	page_changed.emit(which)
	if which != Page.AGENT:
		page_shown.emit(which)


## The page shown.
func page() -> Page:
	return tabs.current_tab as Page


## The top row (tabs and NEWS) shows, except in answer mode.
func set_top_row(on: bool) -> void:
	var row: Control = %TopRow
	if row.visible != on:
		row.visible = on


## Whether the top row shows its NEWS line (the showroom has none).
func set_news_shown(on: bool) -> void:
	if news.visible != on:
		news.visible = on


func _page_node(which: Page) -> Control:
	match which:
		Page.HISTORY:
			return history
		Page.EVENTS:
			return events
	return card
