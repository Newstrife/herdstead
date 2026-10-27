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
## Two forms of the same node, by the bar's height (set_tall()). On a tall bar
## it is B2's tile (`tile_size`): the face in a window (`%FaceBox`) that wears
## the frame and the rings, the state's small mark in the window's top-left
## corner (`%Badge`, the pack's `badge_<badge>_small`: a plain Sprite2D, not a
## StatusBadge, so the attention clock never bobs it; and the scene names no
## StatusBadge script, which would load in a cycle under the bar's preload),
## and the name and the place under it on
## the bar's ground. On a short bar it is the horizontal card (`card_size`):
## the face at the left, the words beside it, the frame round the whole card,
## and no mark. The rings (`%Selected`, `%Pointed`) move to whichever node
## wears the frame; every node is kept.
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

## The frameless tile; its window wears the state (FACE_LOOKS).
const TILE_LOOK := &"PortraitTile"
## The face window's frame on a tile, by group; `Lit` added under the pointer.
const FACE_LOOKS: Dictionary[PortraitBarModel.Group, String] = {
	PortraitBarModel.Group.BLOCKED: "PortraitFaceBlocked",
	PortraitBarModel.Group.DONE: "PortraitFaceDone",
	PortraitBarModel.Group.WORKING: "PortraitFaceWorking",
	PortraitBarModel.Group.IDLE: "PortraitFaceIdle",
}
## The face window on a card: the card's own frame shows round it.
const FACE_BARE := &"PortraitFaceBare"
## The face and the words side by side (a card), or one over the other (a tile).
const BODY_LOOKS: Dictionary[bool, StringName] = {false: &"PortraitBody", true: &"PortraitBodyTall"}

## The card and the tile, whole. Set in the scene.
@export var card_size := Vector2.ZERO
@export var tile_size := Vector2.ZERO
## The width of the face-only form, as a card and as a tile. Set in the scene.
@export var face_width := 0.0
@export var tile_face_width := 0.0
## The face window's least size, as a card and as a tile. Set in the scene.
@export var card_face := Vector2.ZERO
@export var tile_face := Vector2.ZERO
## How far in from the card's edges the face and the words stand (left, top,
## right, bottom), as a card and as a tile. Set in the scene.
@export var card_body := Vector4.ZERO
@export var tile_body := Vector4.ZERO

## The pane this card shows (HerdrFleet.pane_key); empty while pooled.
var key := ""

var _card: PortraitBarModel.Card
var _art: ArtPack
var _actor: PixelPerson
## What the person is dressed as now: provider, pack and pane.
var _look := ""
var _face_only := false
## The tile form (set_tall()), or the card.
var _tall := false
## The pointer is on the card: a tile's window frame thickens, as a card's edge does.
var _lit := false
## The small mark the tile wears now; empty for none.
var _dot := &""
## A hovered HUD line names this pane (set_pointed()).
var _pointed := false


func _ready() -> void:
	var button: Button = %PlaceButton
	button.pressed.connect(func() -> void: place_picked.emit(_card.zone_key))
	button.mouse_entered.connect(func() -> void: place_hovered.emit(true))
	button.mouse_exited.connect(func() -> void: place_hovered.emit(false))
	mouse_entered.connect(_light.bind(true))
	mouse_exited.connect(_light.bind(false))


## Show `card` dressed from `art`; `selected` rings it.
func show_card(card: PortraitBarModel.Card, art: ArtPack, selected: bool) -> void:
	if art != _art:
		_dot = &""
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
	ring.visible = selected
	_restyle()
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
	_size()
	_show_wait_label()


func face_only() -> bool:
	return _face_only


## The tile (`on`, a tall bar) or the horizontal card (a short one). Only the
## nodes' properties change: the box turns, the sizes are the scene's, the
## rings move to the node that wears the frame, and the mark shows on a tile
## alone. Nothing is made or freed.
func set_tall(on: bool) -> void:
	if on == _tall:
		return
	_tall = on
	var body: BoxContainer = %Body
	var face_box: Control = %FaceBox
	var name_label: Label = %Name
	var inset := tile_body if on else card_body
	body.vertical = on
	body.theme_type_variation = BODY_LOOKS[on]
	body.offset_left = inset.x
	body.offset_top = inset.y
	body.offset_right = -inset.z
	body.offset_bottom = -inset.w
	face_box.custom_minimum_size = tile_face if on else card_face
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if on else HORIZONTAL_ALIGNMENT_LEFT
	_wear_rings()
	_size()
	_restyle()


func is_tall() -> bool:
	return _tall


## The width this card needs as a face alone or as a whole card, in its form
## now, from the scene's sizes (what OfficeBar fits the strip by).
func needed_width(face_alone: bool) -> float:
	if _tall:
		return tile_face_width if face_alone else tile_size.x
	return face_width if face_alone else card_size.x


func _size() -> void:
	var height := tile_size.y if _tall else card_size.y
	var wanted := Vector2(needed_width(_face_only), height)
	if custom_minimum_size != wanted:
		custom_minimum_size = wanted


## The rings go where the frame is: round the whole card, or inside a tile's
## face window. `%Pointed` stays under the face (the head's top, at its row,
## stays whole) and `%Selected` over it, under the mark.
func _wear_rings() -> void:
	var under: Control = %Pointed
	var over: Control = %Selected
	var face: Control = %Face
	var holder: Control = %FaceBox if _tall else self
	for ring: Control in [under, over]:
		if ring.get_parent() != holder:
			# Moved, never made again: the owner is let go for the move and
			# taken back, so `%Selected` / `%Pointed` still find it.
			ring.owner = null
			ring.get_parent().remove_child(ring)
			holder.add_child(ring)
			ring.owner = self
	holder.move_child(under, 0)
	holder.move_child(over, face.get_index() + 1 if _tall else holder.get_child_count() - 1)


## The looks the form and the group give: a card's frame on the card, or a
## tile's frame on its window (thicker under the pointer), and the tile's mark.
func _restyle() -> void:
	var face_box: Control = %FaceBox
	var mark: Sprite2D = %Badge
	if _card == null:
		return
	var group := _card.group
	theme_type_variation = TILE_LOOK if _tall else LOOKS[group]
	face_box.theme_type_variation = (StringName(FACE_LOOKS[group] + ("Lit" if _lit else "")) if _tall else FACE_BARE)
	var dot := dot_of(_art, group) if _tall else &""
	if dot != _dot:
		_dot = dot
		if dot.is_empty():
			mark.visible = false
		else:
			var image := _art.ui_sprite(dot)
			_art.dress(mark, _art.sprite_texture(image), image.pivot)
			mark.visible = true


func _light(on: bool) -> void:
	_lit = on
	_restyle()


## The small mark a tile of `group` wears: the pack's `badge_<badge>_small`
## for the badge its state wears (ArtContract.tile_dot(); done wears unread's),
## or none when the pack has no such image.
static func dot_of(art: ArtPack, group: PortraitBarModel.Group) -> StringName:
	if art == null:
		return &""
	var dot := ArtContract.tile_dot(CardDetails.badge_of(art, StringName(PortraitBarModel.WORDS[group])))
	return dot if art.ui_sprite(dot) != null else &""


## The tile's mark; hidden on a card.
func badge() -> Sprite2D:
	return %Badge


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
