class_name PortraitCard
extends Button
## One agent in the top bar's portrait strip (scenes/ui/portrait_card.tscn):
## the seat's person, standing still, with the pane's name over its place (a
## tag in its worktree group's carpet family and its space) and, for a blocked
## agent, how long it has waited. Its frame wears the state's colour; the
## selected one a paper ring just inside it, and one a hovered HUD line points
## at a paper ring inside that (set_pointed()): the three nest and all show. Face-only, the words go and the
## card is as wide as the face.
##
## The place is a button of its own (`%PlaceButton`): a click there pans to the
## zone (place_picked) and selects nothing; its
## tooltip is the zone's sign. An unseated pane's place is only words, and a
## click anywhere else on the card picks the pane.
##
## Its nodes are permanent: a card shown for another pane is the same node
## with new text (the bar pools them). A press is the bar's to say
## (OfficeBar.portrait_picked, OfficeBar.zone_picked); the card takes no focus,
## so no key reaches it. The card's tooltip is written only when the pointer
## asks, as a list row's is.

## The place (`%PlaceButton`) was pressed: pan to zone `zone_key`.
signal place_picked(zone_key: String)
## The pointer came onto the place (`on`) or left it. The place takes the
## mouse, so the card itself does not hear the pointer there; the bar points
## at the card's desk all the same.
signal place_hovered(on: bool)

## The frame each group wears (HudTheme._portraits()).
const LOOKS: Dictionary[PortraitBarModel.Group, StringName] = {
	PortraitBarModel.Group.BLOCKED: &"PortraitCardBlocked",
	PortraitBarModel.Group.DONE: &"PortraitCardDone",
	PortraitBarModel.Group.WORKING: &"PortraitCardWorking",
	PortraitBarModel.Group.IDLE: &"PortraitCardIdle",
}

## The width of the face-only form. Set in the scene.
@export var face_width := 0.0

## The pane this card shows (HerdrFleet.pane_key); empty while pooled.
var key := ""

var _card: PortraitBarModel.Card
var _art: ArtPack
var _actor: PixelPerson
## What the person is dressed as now: provider, pack and pane.
var _look := ""
var _face_only := false
## A hovered HUD line names this pane (set_pointed()).
var _pointed := false
## The card form's width, as the scene sets it (custom_minimum_size), kept
## from before the face-only form first changes it; −1 until asked.
var _card_width := -1.0


func _ready() -> void:
	var button: Button = %PlaceButton
	button.pressed.connect(func() -> void: place_picked.emit(_card.zone_key))
	button.mouse_entered.connect(func() -> void: place_hovered.emit(true))
	button.mouse_exited.connect(func() -> void: place_hovered.emit(false))


## Show `card` dressed from `art`; `selected` rings it.
func show_card(card: PortraitBarModel.Card, art: ArtPack, selected: bool) -> void:
	_card = card
	_art = art
	key = card.key
	var name_label: Label = %Name
	var place: Label = %Place
	var tag: Panel = %Tag
	var ring: Panel = %Selected
	var button: Button = %PlaceButton
	name_label.text = card.name
	place.text = card.place
	# A seated pane's place is a button to its zone; an unseated one's is only
	# words, and its click falls through to the card, which picks the pane.
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE if card.zone == null else Control.MOUSE_FILTER_STOP
	button.tooltip_text = place_tip_of(card)
	tag.visible = not card.group_key.is_empty()
	if tag.visible:
		tag.theme_type_variation = StringName("CarpetTag%d" % OfficeZoneSign.accent_of(card.group_key))
	theme_type_variation = LOOKS[card.group]
	ring.visible = selected
	_show_face(card, art)
	_show_wait_label()


## The person at the seat, still: a strip of bobbing heads would compete with
## the seats. Dressed again only when the pane, its provider or the pack changes.
func _show_face(card: PortraitBarModel.Card, art: ArtPack) -> void:
	var holder: Node2D = %FaceHolder
	var look := JSON.stringify([card.provider, art.base_path, card.key])
	if look != _look:
		_look = look
		_actor = OfficeDraw.seat_face(holder, _actor, art, card.provider, card.key)
		_actor.animation = &""
	var animation := art.animation_for_state(StringName(card.state), card.starting)
	if _actor.animation != animation:
		_actor.play_state(animation)
	_actor.pause()


## How long a blocked agent has waited (OfficeAttention.wait_text()); empty
## for none. Only a blocked card says it.
func show_wait(said: String) -> void:
	var wait: Label = %Wait
	wait.text = said
	_show_wait_label()


func _show_wait_label() -> void:
	var wait: Label = %Wait
	var blocked := _card != null and _card.group == PortraitBarModel.Group.BLOCKED
	wait.visible = blocked and not wait.text.is_empty() and not _face_only


## The face alone (`on`), or the whole card.
func set_face_only(on: bool) -> void:
	_face_only = on
	var words: Control = %Text
	words.visible = not on
	var full := _full_width()
	custom_minimum_size.x = face_width if on else full
	_show_wait_label()


func face_only() -> bool:
	return _face_only


## The width this card needs as a face alone or as a whole card, from the
## scene's sizes (what OfficeBar fits the strip by).
func needed_width(face_alone: bool) -> float:
	return face_width if face_alone else _full_width()


func _full_width() -> float:
	if _card_width < 0.0:
		_card_width = custom_minimum_size.x
	return _card_width


## A hovered HUD line names this card's pane (`on`): a 1-unit paper ring 2
## units in, inside the selection's (PortraitPointed), until it does not. It
## lies under the face (first in the scene), so the head's top, at that same
## row, stays whole. Written only when it changes.
func set_pointed(on: bool) -> void:
	if on == _pointed:
		return
	_pointed = on
	var ring: Panel = %Pointed
	ring.visible = on


## Whether the card is outlined as pointed at (set_pointed()).
func pointed() -> bool:
	return _pointed


## The person on the card; null before the first show_card().
func person() -> PixelPerson:
	return _actor


func shown_card() -> PortraitBarModel.Card:
	return _card


func _get_tooltip(_at: Vector2) -> String:
	return tooltip_of(_card, _art, (%Wait as Label).text)


## The place's tooltip: the words on its zone's sign (`3 INFRA`, a
## mezzanine's `3A CHECKOUT`) over what the sign's own tooltip says
## (ZoneRef.sign_text(): repository, checkout, whose worktree); empty for an
## unseated pane, whose place is not a button. (Not through
## OfficeQuestionTips: the bar preloads this card, and that reader's
## dependencies loading under it left the zone sign's scene empty.)
static func place_tip_of(card: PortraitBarModel.Card) -> String:
	if card == null or card.zone == null:
		return ""
	return OfficeZoneSign.words(card.zone.zone_model) + "\n" + card.zone.sign_text()


## The card's tooltip: the whole name; `PROVIDER · <the pack's word for the
## state> · <wait>` (a blocked card's wait only); `space / tab`; and
## `@ machine` among several machines.
static func tooltip_of(card: PortraitBarModel.Card, art: ArtPack, wait: String) -> String:
	if card == null:
		return ""
	var lines := PackedStringArray([card.name])
	var about := PackedStringArray([card.provider.to_upper(), CardDetails.caption_of(art, StringName(card.state))])
	if card.group == PortraitBarModel.Group.BLOCKED and not wait.is_empty():
		about.append(wait)
	lines.append(" · ".join(about))
	lines.append(card.place if card.tab.is_empty() else "%s / %s" % [card.place, card.tab])
	if not card.machine_label.is_empty():
		lines.append("@ " + card.machine_label)
	return "\n".join(lines)
