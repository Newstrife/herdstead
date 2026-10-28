"""Build the portraits: art/portraits/portraits.json -> assets/portraits/.

A portrait is the head and shoulders of the seat's person, a 40x40-unit square
(80x80 texels at density 2, sampled NEAREST, pivot at its bottom centre) that
the HUD shows in the top bar's tiles and on the agent card. It is drawn as nine
layered *parts*, bottom to top ``top``, ``head``, ``face``, ``brows``,
``marks``, ``neckwear``, ``glasses``, ``hair`` and ``headwear``, each one
80x80 picture, stacked by the runtime in that order.

A portrait is the seat's person by construction: the parts are painted in the
pixel people's own key colours and recoloured here with the people's own
swatches (art/pixel_people/people.json ``keys``, ``fixed``, ``slots``, read
through tools/build_pixel_people.py, never copied), and each layer binds to the
people's look slots by name (``head`` is coloured by ``skin``, ``hair`` is
shaped by ``hair_style`` and coloured by ``hair_colour``, ...). Three portrait-
only *extras* (``expression``, ``marks``, ``neckwear``) are shape choices of
their own, picked per pane by the runtime with the people's hash under new
names, so nobody's look moves.

Sources (``art/portraits/parts/``, key colours, one per layer and shape):

* ``top.png``, ``head.png``                 -> ``top_<swatch>``, ``head_<skin>``
* ``face_<expression>.png``                 -> ``face_<expression>_<skin>``
* ``brows_<expression>.png``                -> ``brows_<expression>_<hair colour>``
* ``marks_<mark>.png``                      -> ``marks_<mark>_<skin>``
* ``neckwear_<shape>.png``, ``glasses_<shape>.png`` -> as they are (fixed colours only)
* ``hair_<style>.png``, ``headwear_<shape>.png`` -> ``..._<colour>``

Every product is one 80x80 *cell*; the cells ship packed row-major in one sheet,
``portraits.png`` (no gutter, the manifest's ``cells`` give each one's index), so
a portrait's nine layers draw from one texture in one draw call. Packing is a
build step (invariant 6 forbids repacking at runtime, not here).

When a source exists it is checked and used. When it does not, a placeholder is
drawn from the contract in the key colours and listed in the product manifest's
``mock_files`` (the painter's to-do, as the pixel people's). Either way the
source passes the same checks, the cross-part checks below and the same exact
recolour, so the office can be built on placeholders alone.

The product manifest is ``portraits_manifest.json``, never ``manifest.json``:
every ``assets/*/manifest.json`` is a theme to the Makefile, tools/check_packs.gd
and the office's theme list.

Run from the repository root::

    .venv/bin/python tools/build_portraits.py
    .venv/bin/python tools/build_portraits.py --source DIR --output DIR

A broken contract or source stops the build with ``PORTRAITS_BUILD_FAILED:``
naming the file and the rule, and a nonzero exit.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

import build_pixel_people as people_build
from build_assets import prune_unreferenced, report_pruned, save_if_pixels_moved
from recolour import repaint


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art" / "portraits"
OUTPUT = ROOT / "assets" / "portraits"
SPEC_NAME = "portraits.json"
PARTS_DIR = "parts"
# Not manifest.json: every assets/*/manifest.json is a theme to the Makefile,
# tools/check_packs.gd and the office's theme list.
PRODUCT_NAME = "portraits_manifest.json"
SHEET_NAME = "portraits.png"
SCHEMA_VERSION = 1
DENSITY = 2
FILTER = "nearest"
CANVAS = (40, 40)
# The layers the runtime stacks, bottom to top (PixelPortraits.LAYERS).
LAYERS = ("top", "head", "face", "brows", "marks", "neckwear", "glasses", "hair", "headwear")
NONE = "none"
SPEC_KEYS = {"schema_version", "density", "filter", "canvas", "pivot", "people", "layers", "extras", "fixed",
             "face_box", "head_rows"}
LAYER_KEYS = {"shape", "colour", "fixed"}
EXTRA_KEYS = {"options", "none", "default", "pool"}
# The people's fixed colours only a face may hold: the eyes and their catchlight.
FACE_ONLY = ("eye", "catchlight")
FACE = "face"
# The layers whose every texel must lie inside face_box: the HUD's rings, the
# tile's corner mark and the face-only crop never touch them.
FACE_LAYERS = ("face", "brows")
# Portrait-only fixed colours: at most this many, each at least this far (RGB
# Manhattan) from every key and fixed colour and from each other.
FIXED_MAX = 3
FIXED_DISTANCE = 12
# How far (units) the base's crown may sit from head_rows before the build says so.
HEAD_ROWS_SLACK = 1


class PortraitError(ValueError):
    """The contract or a source picture is broken; the message names the file and the rule."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PortraitError(message)


def known_keys(value, allowed, label: str) -> None:
    require(isinstance(value, dict), f"{label} must be an object")
    unknown = set(value) - set(allowed)
    require(not unknown, f"{label}: unknown field(s) {sorted(unknown)}")


def safe_name(value, label: str) -> None:
    require(isinstance(value, str) and value and value.isascii()
            and all(c.isalnum() or c == "_" for c in value), f"{label}: {value!r} must be a safe name")


def whole_list(value, count: int, label: str) -> list[int]:
    require(isinstance(value, list) and len(value) == count and all(type(v) is int and v >= 0 for v in value),
            f"{label} must be a list of {count} whole, non-negative numbers; found {value!r}")
    return list(value)


# --- the contract -----------------------------------------------------------------


def load_spec(source: Path) -> dict:
    """portraits.json, checked, with the people's contract it names loaded
    beside it as ``spec["_people"]`` (keys, fixed colours, slots, swatches)."""
    path = source / SPEC_NAME
    require(path.is_file(), f"{path}: no portraits contract")
    try:
        spec = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        raise PortraitError(f"{path}: not JSON ({error})") from error
    require(isinstance(spec, dict), f"{path}: not a JSON object")
    known_keys(spec, SPEC_KEYS, str(path))
    people_path = spec.get("people")
    require(isinstance(people_path, str) and Path(people_path).name == people_build.SPEC_NAME,
            f"{path}: people must name the pixel people's {people_build.SPEC_NAME}, relative to {source}")
    try:
        people = people_build.load_spec((source / people_path).parent)
    except people_build.PeopleError as error:
        raise PortraitError(f"{path}: the people it names: {error}") from error
    validate(spec, people, path)
    spec["_people"] = people
    return spec


def validate(spec: dict, people: dict, where: Path) -> None:
    """Everything about portraits.json that can be known without a picture."""
    require(type(spec.get("schema_version")) is int and spec["schema_version"] == SCHEMA_VERSION,
            f"{where}: schema_version must be {SCHEMA_VERSION}")
    require(type(spec.get("density")) is int and spec["density"] == DENSITY,
            f"{where}: density must be {DENSITY}, the pixel people's: texture pixels per unit")
    require(spec.get("filter") == FILTER, f"{where}: filter must be {FILTER}")
    canvas = whole_list(spec.get("canvas"), 2, f"{where}: canvas")
    require(tuple(canvas) == CANVAS, f"{where}: canvas must be {list(CANVAS)} units, the HUD's portrait window")
    pivot = whole_list(spec.get("pivot"), 2, f"{where}: pivot")
    require(pivot[0] * 2 == canvas[0], f"{where}: pivot x must be half the canvas ({canvas[0] / 2:g}), "
            "the people's rule for an origin")
    require(pivot[1] <= canvas[1], f"{where}: pivot must lie on the canvas")
    validate_fixed(spec, people, where)
    validate_extras(spec, people, where)
    validate_layers(spec, people, where)
    box = whole_list(spec.get("face_box"), 4, f"{where}: face_box")
    require(box[0] < box[2] <= canvas[0] and box[1] < box[3] <= canvas[1],
            f"{where}: face_box must be [x0, y0, x1, y1] on the canvas with x0 < x1 and y0 < y1")
    rows = whole_list(spec.get("head_rows"), 2, f"{where}: head_rows")
    require(rows[0] < rows[1] <= canvas[1], f"{where}: head_rows must be [crown, chin] rows on the canvas")


def validate_fixed(spec: dict, people: dict, where: Path) -> None:
    fixed = spec.get("fixed")
    require(isinstance(fixed, dict), f"{where}: fixed must be an object")
    require(len(fixed) <= FIXED_MAX, f"{where}: fixed may add at most {FIXED_MAX} portrait-only colours")
    others = dict(people_build.source_palette(people))
    for name, colour in fixed.items():
        safe_name(name, f"{where}: fixed")
        require(name not in people["fixed"], f"{where}: fixed.{name} is already one of the people's fixed colours")
        people_build.hex_colour(colour, f"{where}: fixed.{name}")
        for other, value in others.items():
            distance = sum(abs(a - b) for a, b in zip(rgb(colour), rgb(value)))
            require(distance >= FIXED_DISTANCE, f"{where}: fixed.{name} #{colour} is {distance} from {other} "
                    f"#{value}; a portrait colour stands at least {FIXED_DISTANCE} apart (RGB Manhattan)")
        others[f"fixed.{name}"] = colour
    # One colour, one meaning: the recolour is a lookup.
    people_table(others, {})


def validate_extras(spec: dict, people: dict, where: Path) -> None:
    extras = spec.get("extras")
    require(isinstance(extras, dict), f"{where}: extras must be an object")
    for extra, info in extras.items():
        label = f"{where}: extras.{extra}"
        safe_name(extra, label)
        require(extra not in people["slots"], f"{label}: {extra} is a people look slot; an extra is a portrait's own")
        known_keys(info, EXTRA_KEYS, label)
        choices = info.get("options")
        require(isinstance(choices, list) and choices, f"{label}.options must be a non-empty list of names")
        for option in choices:
            safe_name(option, f"{label}.options")
            require(option != NONE, f"{label}: {NONE} is not an option; say \"none\": true")
        require(len(choices) == len(set(choices)), f"{label}.options must not repeat a name")
        require(isinstance(info.get("none", False), bool), f"{label}.none must be true or false")
        drawn = extra_options(spec, extra)
        require(info.get("default") in drawn, f"{label}.default must be one of {drawn}; found {info.get('default')!r}")
        pool = info.get("pool")
        # A repeat is a weight, as in people.json's variation.
        require(isinstance(pool, list) and pool, f"{label}.pool must be a non-empty list of options")
        for value in pool:
            require(value in drawn, f"{label}.pool names {value!r}, which the extra does not draw")


def validate_layers(spec: dict, people: dict, where: Path) -> None:
    layers = spec.get("layers")
    require(isinstance(layers, dict) and list(layers) == list(LAYERS),
            f"{where}: layers must be exactly {list(LAYERS)}, in that order (the runtime's sprites, bottom to top)")
    allowed_fixed = set(people["fixed"]) | set(spec["fixed"])
    for layer, info in layers.items():
        label = f"{where}: layers.{layer}"
        known_keys(info, LAYER_KEYS, label)
        require(set(info) == LAYER_KEYS, f"{label} must say shape, colour and fixed (null or [] for none)")
        shape = info["shape"]
        if shape is not None:
            people_shape = shape in people["slots"] and "shapes" in people["slots"][shape]
            require(people_shape or shape in spec["extras"],
                    f"{label}.shape must be a people shape slot or an extra; found {shape!r}")
        colour = info["colour"]
        if colour is not None:
            require(colour in people["slots"] and "role" in people["slots"][colour],
                    f"{label}.colour must be a people colour slot (a role and its swatches); found {colour!r}")
        fixed = info["fixed"]
        require(isinstance(fixed, list), f"{label}.fixed must be a list of fixed colour names")
        for name in fixed:
            require(name in allowed_fixed, f"{label}.fixed names {name!r}, which is no fixed colour")
            require(name not in FACE_ONLY or layer == FACE, f"{label}.fixed: {name} is the face's alone")
        require(colour is not None or fixed, f"{label} may hold no colour at all")


def extra_options(spec: dict, extra: str) -> list[str]:
    """What an extra can be: its options, and none where allowed."""
    info = spec["extras"][extra]
    return list(info["options"]) + ([NONE] if info.get("none", False) else [])


def shapes_of(spec: dict, layer: str) -> list[str | None]:
    """The drawings a layer has: its shape slot's or extra's options (never none),
    or [None] for a layer that is one drawing."""
    shape = spec["layers"][layer]["shape"]
    if shape is None:
        return [None]
    people = spec["_people"]
    if shape in people["slots"]:
        return list(people["slots"][shape]["shapes"])
    return list(spec["extras"][shape]["options"])


def swatches_of(spec: dict, layer: str) -> list[str | None]:
    colour = spec["layers"][layer]["colour"]
    return [None] if colour is None else list(spec["_people"]["slots"][colour]["swatches"])


def role_of(spec: dict, layer: str) -> str | None:
    colour = spec["layers"][layer]["colour"]
    return None if colour is None else spec["_people"]["slots"][colour]["role"]


# --- palette and recolour ---------------------------------------------------------


def rgb(colour: str) -> tuple[int, int, int]:
    return people_build.rgb(colour)


def people_table(palette: dict[str, str], overrides: dict[str, str]) -> dict:
    try:
        return people_build.table(palette, overrides)
    except people_build.PeopleError as error:
        raise PortraitError(str(error)) from error


def fixed_colours(spec: dict) -> dict[str, str]:
    """Every fixed colour a part may name: the people's and the portrait's own."""
    return {**spec["_people"]["fixed"], **spec["fixed"]}


def layer_palette(spec: dict, layer: str) -> dict[str, str]:
    """What a layer's sources may hold, by name: its colour slot's role keys and
    the fixed colours it lists."""
    palette = {}
    role = role_of(spec, layer)
    if role is not None:
        palette.update({people_build.key_name(role, tone): colour
                        for tone, colour in enumerate(spec["_people"]["keys"][role])})
    everything = fixed_colours(spec)
    palette.update({f"fixed.{name}": everything[name] for name in spec["layers"][layer]["fixed"]})
    return palette


def allowed_colours(spec: dict, layer: str) -> set[tuple[int, int, int]]:
    return {rgb(colour) for colour in layer_palette(spec, layer).values()}


@dataclass(frozen=True)
class Cell:
    """One shipped 80x80 picture: its name, its layer, the source it is
    recoloured from, and the swatch its role is mapped to (None: fixed only)."""

    name: str
    layer: str
    source: str
    swatch: str | None


def source_name(layer: str, shape: str | None) -> str:
    return layer if shape is None else f"{layer}_{shape}"


def cells(spec: dict) -> list[Cell]:
    """Every cell, in packing order: layer by layer, shape by shape, swatch by swatch."""
    result = []
    for layer in LAYERS:
        for shape in shapes_of(spec, layer):
            source = source_name(layer, shape)
            for swatch in swatches_of(spec, layer):
                result.append(Cell(source if swatch is None else f"{source}_{swatch}", layer, source, swatch))
    return result


def sources(spec: dict) -> list[tuple[str, str]]:
    """(source name, layer) of every part a complete family has, in layer order."""
    return [(source_name(layer, shape), layer) for layer in LAYERS for shape in shapes_of(spec, layer)]


def recolour(image: Image.Image, spec: dict, cell: Cell, label: str) -> Image.Image:
    """The cell: every key colour of the layer's role substituted by the swatch's tone."""
    palette = layer_palette(spec, cell.layer)
    overrides = {}
    if cell.swatch is not None:
        colour = spec["layers"][cell.layer]["colour"]
        role = role_of(spec, cell.layer)
        target = spec["_people"]["slots"][colour]["swatches"][cell.swatch]
        overrides = {people_build.key_name(role, tone): target[tone] for tone in range(people_build.TONES)}
    painted, foreign = repaint(image, people_table(palette, overrides), label, keep_foreign=True)
    require(not foreign, f"{label}: {cell.name} maps no colour for "
            + ", ".join("#%02x%02x%02x" % colour for colour in sorted(foreign)))
    return painted


# --- one source ---------------------------------------------------------------------


def canvas_texels(spec: dict) -> tuple[int, int]:
    return (spec["canvas"][0] * spec["density"], spec["canvas"][1] * spec["density"])


def check_source(image: Image.Image, spec: dict, layer: str, relative: str) -> None:
    """One part's pixel contract: the canvas exactly, hard alpha, only its own colours."""
    expected = canvas_texels(spec)
    require(image.size == expected, f"{relative}: {image.size} is not the {expected[0]}x{expected[1]} canvas")
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    allowed = allowed_colours(spec, layer)
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            require(a == 255, f"{relative}: texel ({x}, {y}) is semi-transparent (alpha {a}); edges are 0 or 255")
            require((r, g, b) in allowed, f"{relative}: texel ({x}, {y}) is #{r:02x}{g:02x}{b:02x}, which is not "
                    f"a colour the {layer} layer may hold ({', '.join(sorted(layer_palette(spec, layer)))})")


def opaque(image: Image.Image) -> set[tuple[int, int]]:
    alpha = image.getchannel("A").load()
    return {(x, y) for y in range(image.height) for x in range(image.width) if alpha[x, y]}


def colours_at(image: Image.Image, colours: set[tuple[int, int, int]]) -> set[tuple[int, int]]:
    pixels = image.load()
    return {(x, y) for y in range(image.height) for x in range(image.width)
            if pixels[x, y][3] and pixels[x, y][:3] in colours}


def face_box_texels(spec: dict) -> tuple[int, int, int, int]:
    """face_box in texels: x0, y0 inclusive, x1, y1 exclusive."""
    d = spec["density"]
    return tuple(value * d for value in spec["face_box"])


# --- the cross-part checks ------------------------------------------------------------


def hats(spec: dict) -> tuple[list[str], list[str]]:
    """(the headwear that sits over the hair, the headwear that hides it)."""
    slot = spec["layers"]["headwear"]["shape"]
    shapes = spec["_people"]["slots"][slot]["shapes"]
    return ([shape for shape, flags in shapes.items() if not flags.get("hides_hair", False)],
            [shape for shape, flags in shapes.items() if flags.get("hides_hair", False)])


def check_brims(spec: dict, parts: dict[str, Image.Image]) -> None:
    """A cap covers every hair style above its brim: in each column the cap draws,
    every hair texel above the cap's lowest opaque row there is under a cap texel."""
    over, _hidden = hats(spec)
    for hat in over:
        cap = opaque(parts[f"headwear_{hat}"])
        lowest: dict[int, int] = {}
        for x, y in cap:
            lowest[x] = max(lowest.get(x, -1), y)
        for style in shapes_of(spec, "hair"):
            for x, y in sorted(opaque(parts[f"hair_{style}"])):
                require(x not in lowest or y >= lowest[x] or (x, y) in cap,
                        f"hair_{style}.png: texel ({x}, {y}) shows above the brim of headwear_{hat}.png "
                        f"(its lowest row in column {x} is {lowest.get(x)}); a cap covers the hair above its brim")


def check_hoods(spec: dict, parts: dict[str, Image.Image]) -> None:
    """A hood hides the hair, so it covers the bald head's crown: every head
    texel above face_box's top row is under a hood texel."""
    _over, hidden = hats(spec)
    top = face_box_texels(spec)[1]
    crown = {(x, y) for x, y in opaque(parts["head"]) if y < top}
    for hood in hidden:
        covered = opaque(parts[f"headwear_{hood}"])
        for x, y in sorted(crown - covered):
            raise PortraitError(f"head.png: texel ({x}, {y}) of the crown shows past headwear_{hood}.png; a hood "
                                f"hides the hair, so it covers the head above row {top}")


def eye_texels(spec: dict, image: Image.Image) -> set[tuple[int, int]]:
    named = spec["_people"]["fixed"]
    return colours_at(image, {rgb(named[name]) for name in FACE_ONLY if name in named})


def check_glasses(spec: dict, parts: dict[str, Image.Image]) -> None:
    """Glasses never cover an eye or its catchlight, whatever the expression."""
    for shape in shapes_of(spec, "glasses"):
        lenses = opaque(parts[f"glasses_{shape}"])
        for face in shapes_of(spec, "face"):
            for x, y in sorted(eye_texels(spec, parts[f"face_{face}"]) & lenses):
                raise PortraitError(f"glasses_{shape}.png: texel ({x}, {y}) covers an eye of face_{face}.png; "
                                    "glasses never cover an eye or its catchlight")


def check_face_box(spec: dict, parts: dict[str, Image.Image]) -> None:
    """Every face and brows texel lies inside face_box (HUD geometry: clear of the
    rings, the corner mark and the face-only crop's edges)."""
    x0, y0, x1, y1 = face_box_texels(spec)
    for layer in FACE_LAYERS:
        for shape in shapes_of(spec, layer):
            name = source_name(layer, shape)
            for x, y in sorted(opaque(parts[name])):
                require(x0 <= x < x1 and y0 <= y < y1,
                        f"{name}.png: texel ({x}, {y}) is outside face_box (texels x {x0}..{x1 - 1}, "
                        f"y {y0}..{y1 - 1}); every face and brows texel lies inside it")


def check_marks(spec: dict, parts: dict[str, Image.Image]) -> None:
    """Marks lie on the skin: every marks texel is over a head texel of a skin key."""
    role = role_of(spec, "head")
    skin = colours_at(parts["head"], {rgb(colour) for colour in spec["_people"]["keys"][role]})
    for shape in shapes_of(spec, "marks"):
        for x, y in sorted(opaque(parts[f"marks_{shape}"]) - skin):
            raise PortraitError(f"marks_{shape}.png: texel ({x}, {y}) is not over head.png's skin; marks lie on "
                                "the skin the head covers")


def head_rows_notes(spec: dict, parts: dict[str, Image.Image]) -> list[str]:
    """Where the base's crown and shoulders sit against head_rows: notes, never refusals."""
    d = spec["density"]
    width, height = canvas_texels(spec)
    crown, chin = spec["head_rows"]
    notes = []
    head = parts["head"].getchannel("A").getbbox()
    if head is None:
        return ["head.png draws nothing"]
    if abs(head[1] // d - crown) > HEAD_ROWS_SLACK:
        notes.append(f"head.png's crown is unit row {head[1] // d}, head_rows says {crown}")
    if head[3] // d < chin:
        notes.append(f"head.png ends at unit row {head[3] // d}, above head_rows' chin {chin}")
    top = opaque(parts["top"])
    bottom = {x for x, y in top if y == height - 1}
    if len(bottom) < width:
        notes.append(f"top.png's bottom row covers {len(bottom)} of {width} texels; the shoulders run edge to edge")
    return notes


def check_parts(spec: dict, parts: dict[str, Image.Image]) -> None:
    check_brims(spec, parts)
    check_hoods(spec, parts)
    check_glasses(spec, parts)
    check_face_box(spec, parts)
    check_marks(spec, parts)


def eye_contrast(spec: dict) -> list[tuple[str, float]]:
    """(skin swatch, the eye's contrast against its mid tone), as the people's build prints it."""
    return people_build.eye_contrast(spec["_people"])


# --- the placeholder ------------------------------------------------------------------
# Each placeholder is a set of texels filled with a role's ramp (lit from the top
# left: a texel on the fill's top or left edge is light, on its bottom or right
# edge dark, the rest mid) and ringed in ink (every empty 4-neighbour on the
# canvas), or a set of texels of named fixed colours. The geometry is in texels on
# the 80x80 canvas; x is symmetric about 40 (texels 0..39 | 40..79).

Texel = tuple[int, int]
WIDTH = HEIGHT = 80
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def ellipse(cx: float, cy: float, rx: float, ry: float) -> set[Texel]:
    return {(x, y) for y in range(HEIGHT) for x in range(WIDTH)
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0}


def rect(x0: int, y0: int, x1: int, y1: int) -> set[Texel]:
    """x0, y0 inclusive; x1, y1 exclusive."""
    return {(x, y) for y in range(max(0, y0), min(HEIGHT, y1)) for x in range(max(0, x0), min(WIDTH, x1))}


def mirrored(texels: set[Texel]) -> set[Texel]:
    return texels | {(WIDTH - 1 - x, y) for x, y in texels}


def ring(fill: set[Texel]) -> set[Texel]:
    return {(x + dx, y + dy) for x, y in fill for dx, dy in N4
            if (x + dx, y + dy) not in fill and 0 <= x + dx < WIDTH and 0 <= y + dy < HEIGHT}


class Sketch:
    """One placeholder part being drawn; image() is the key-colour picture."""

    def __init__(self, spec: dict):
        self.spec = spec
        self.pixels: dict[Texel, str] = {}

    def fixed(self, texels: set[Texel], name: str) -> Sketch:
        colour = fixed_colours(self.spec)[name]
        for texel in texels:
            self.pixels[texel] = colour
        return self

    def tone(self, texels: set[Texel], role: str, tone: int) -> Sketch:
        colour = self.spec["_people"]["keys"][role][tone]
        for texel in texels:
            self.pixels[texel] = colour
        return self

    def shaded(self, fill: set[Texel], role: str, outline: bool = True) -> Sketch:
        keys = self.spec["_people"]["keys"][role]
        for x, y in fill:
            if (x, y - 1) not in fill or (x - 1, y) not in fill:
                self.pixels[(x, y)] = keys[0]
            elif (x, y + 1) not in fill or (x + 1, y) not in fill:
                self.pixels[(x, y)] = keys[2]
            else:
                self.pixels[(x, y)] = keys[1]
        if outline:
            self.fixed(ring(fill), "ink")
        return self

    def cups(self, fill: set[Texel]) -> Sketch:
        """Fixed-colour headphone cups: gear, lit on the top-left edge, ringed in ink."""
        for x, y in fill:
            lit = (x, y - 1) not in fill or (x - 1, y) not in fill
            self.fixed({(x, y)}, "gear_light" if lit and "gear_light" in fixed_colours(self.spec) else "gear")
        return self.fixed(ring(fill), "ink")

    def image(self) -> Image.Image:
        picture = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
        for texel, colour in self.pixels.items():
            picture.putpixel(texel, (*rgb(colour), 255))
        return picture


# The base: a bald head (crown at row 14, an oval to row 64, ears, a neck) on a
# band of shoulders that fills the bottom rows edge to edge.
HEAD_FILL = ellipse(40, 39.5, 18.5, 25) | ellipse(21, 41, 3, 5) | ellipse(59, 41, 3, 5) | rect(33, 56, 47, 68)
NOSE = rect(39, 44, 41, 46)
SHOULDERS = {(x, y) for y in range(66, HEIGHT) for x in range(WIDTH) if abs(x + 0.5 - 40) <= min(40, 26 + (y - 66) * 2)}
COLLAR = mirrored({(34 + step, 66 + step) for step in range(6)})
EYES = mirrored(rect(28, 36, 31, 40))
CATCHLIGHTS = {(28, 36), (49, 36)}
MOUTHS = {
    "smile": ({(35, 46), (44, 46)} | rect(36, 47, 44, 48), rect(38, 48, 42, 49)),
    "smirk": ({(43, 46), (44, 45)} | rect(37, 47, 43, 48), set()),
    "focus": (rect(37, 47, 43, 48), set()),
}
BROWS = {
    "smile": mirrored(rect(27, 32, 33, 34)),
    "smirk": rect(27, 32, 33, 34) | rect(47, 31, 53, 33),
    "focus": mirrored(rect(27, 32, 31, 33) | rect(29, 33, 33, 34)),
}
FRECKLES = mirrored({(25, 44), (27, 45), (29, 44)})
HAIR_TOP = ellipse(40, 39.5, 21, 27.5) - rect(0, 30, WIDTH, HEIGHT)
HAIR = {
    "short": HAIR_TOP | mirrored(rect(19, 30, 23, 38)),
    "curl": (ellipse(40, 36, 27, 30) - rect(0, 31, WIDTH, HEIGHT)) | mirrored(ellipse(17, 46, 7, 14)),
    "long": HAIR_TOP | mirrored(rect(14, 28, 24, 74)),
}
BRIM_ROW = 28
HOOD_OPENING = rect(22, 28, 58, 66)
RIMS = {
    "round": mirrored(ring(rect(27, 35, 32, 41)) - {(26, 34), (32, 34), (26, 41), (32, 41)}),
    "square": mirrored(ring(rect(27, 35, 32, 41)) | {(26, 34), (32, 34), (26, 41), (32, 41)}),
}
TEMPLES = mirrored(rect(22, 37, 26, 38)) | rect(33, 37, 47, 38)
CUPS = mirrored(rect(21, 62, 29, 71))
BAND = rect(29, 64, 51, 66)


def placeholder(spec: dict, layer: str, shape: str | None) -> Image.Image:
    """The key-colour stand-in for one part, drawn from the contract's numbers so
    that it passes every check the painted part will have to."""
    sketch = Sketch(spec)
    role = role_of(spec, layer)
    if layer == "top":
        sketch.shaded(SHOULDERS, role).tone(COLLAR & SHOULDERS, role, 2)
    elif layer == "head":
        sketch.shaded(HEAD_FILL, role).tone(NOSE, role, 2)
    elif layer == "face":
        line, inner = MOUTHS.get(shape, MOUTHS["focus"])
        sketch.fixed(EYES, "eye").fixed(CATCHLIGHTS, "catchlight").fixed(line, "ink").fixed(inner, "mouth")
    elif layer == "brows":
        sketch.shaded(BROWS.get(shape, BROWS["focus"]), role, outline=False)
    elif layer == "marks":
        sketch.tone(FRECKLES, role, 2)
    elif layer == "neckwear":
        sketch.fixed(BAND, "frame").cups(CUPS)
    elif layer == "glasses":
        inner = mirrored(rect(27, 35, 32, 41)) - EYES
        sketch.fixed(inner, "lens").fixed(RIMS.get(shape, RIMS["square"]) | TEMPLES, "frame")
    elif layer == "hair":
        sketch.shaded(HAIR.get(shape, HAIR["short"]), role)
    elif layer == "headwear":
        sketch.shaded(hat_fill(spec, shape), role)
        if shape not in hats(spec)[1]:
            sketch.tone(rect(14, BRIM_ROW - 4, 66, BRIM_ROW), role, 2)
    return sketch.image()


def hat_fill(spec: dict, shape: str) -> set[Texel]:
    """A cap: every hair style's texels above the brim, the crown and a brim band;
    a hood: a cowl round the head down over the shoulders, open at the face."""
    if shape in hats(spec)[1]:
        return (ellipse(40, 40, 25, 32) | rect(8, 66, 72, HEIGHT)) - HOOD_OPENING
    above = rect(0, 0, WIDTH, BRIM_ROW)
    covered = set(HEAD_FILL)
    for style in HAIR.values():
        covered |= style
    return (covered & above) | rect(14, BRIM_ROW - 4, 66, BRIM_ROW)


# --- the build --------------------------------------------------------------------------


def from_source(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        return opened.convert("RGBA")


def load_parts(source: Path, spec: dict) -> tuple[dict[str, Image.Image], list[str]]:
    """Every part, painted or drawn: (name -> key-colour picture, the placeholders'
    files). Each is checked on its own; a PNG the contract does not name is refused."""
    root = source / PARTS_DIR
    listed = {f"{name}.png" for name, _layer in sources(spec)}
    strays = sorted(str(path.relative_to(root)) for path in root.rglob("*.png")
                    if str(path.relative_to(root)) not in listed) if root.is_dir() else []
    require(not strays, f"{root}: PNG(s) the contract does not name: {', '.join(strays)}")
    parts, mocked = {}, []
    for name, layer in sources(spec):
        relative = f"{PARTS_DIR}/{name}.png"
        painted = source / relative
        if painted.is_file():
            image = from_source(painted)
        else:
            image = placeholder(spec, layer, name.removeprefix(layer).removeprefix("_") or None)
            mocked.append(relative)
        check_source(image, spec, layer, relative)
        parts[name] = image
    check_parts(spec, parts)
    return parts, mocked


def grid(count: int) -> tuple[int, int]:
    """(columns, rows) of the sheet: as square as the cells allow."""
    columns = max(1, math.ceil(math.sqrt(count)))
    return columns, max(1, math.ceil(count / columns))


def product_manifest(spec: dict, shipped: list[Cell], mocked: list[str]) -> dict:
    """What the runtime reads (PixelPortraits.from_manifest)."""
    columns, _rows = grid(len(shipped))
    return {
        "schema_version": SCHEMA_VERSION,
        "density": spec["density"],
        "filter": spec["filter"],
        "canvas": spec["canvas"],
        "pivot": spec["pivot"],
        "columns": columns,
        "layers": spec["layers"],
        "extras": spec["extras"],
        "cells": {cell.name: index for index, cell in enumerate(shipped)},
        "files": [SHEET_NAME],
        "mock_files": sorted(mocked),
    }


def build(source: Path = SOURCE, output: Path = OUTPUT) -> dict:
    """Check or draw every part, recolour each into its cells, pack the sheet,
    write the product manifest and prune what it no longer names; return it."""
    spec = load_spec(source)
    parts, mocked = load_parts(source, spec)
    shipped = cells(spec)
    columns, rows = grid(len(shipped))
    width, height = canvas_texels(spec)
    sheet = Image.new("RGBA", (columns * width, rows * height), (0, 0, 0, 0))
    for index, cell in enumerate(shipped):
        picture = recolour(parts[cell.source], spec, cell, f"{PARTS_DIR}/{cell.source}.png")
        sheet.paste(picture, ((index % columns) * width, (index // columns) * height))
    target = output / SHEET_NAME
    save_if_pixels_moved(sheet, target, optimize=True)
    manifest = product_manifest(spec, shipped, mocked)
    text = json.dumps(manifest, indent=2) + "\n"
    written = output / PRODUCT_NAME
    if not written.is_file() or written.read_text() != text:
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text(text)
    report_pruned(output, prune_unreferenced(output, [target]))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", type=Path, default=SOURCE, help="the source directory (default art/portraits)")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="the runtime directory (default assets/portraits)")
    args = parser.parse_args()
    try:
        manifest = build(args.source, args.output)
        spec = load_spec(args.source)
        parts, _mocked = load_parts(args.source, spec)
    except PortraitError as error:
        print(f"PORTRAITS_BUILD_FAILED: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"PORTRAITS_BUILD_OK: {len(manifest['cells'])} cells in {manifest['files'][0]} "
          f"({manifest['columns']} columns) from {len(sources(spec))} parts, {len(manifest['mock_files'])} placeholder")
    ratios = eye_contrast(spec)
    low = [swatch for swatch, ratio in ratios if ratio < people_build.EYE_CONTRAST_MIN]
    print("PORTRAIT_EYE_CONTRAST: " + ", ".join(f"{swatch} {ratio:.2f}:1" for swatch, ratio in ratios)
          + (f"; below {people_build.EYE_CONTRAST_MIN:g}:1: {', '.join(low)} (every eye carries a catchlight texel)"
             if low else ""))
    for note in head_rows_notes(spec, parts):
        print(f"PORTRAIT_HEAD_ROWS: {note} (a note, not a refusal)")


if __name__ == "__main__":
    main()
