"""Contract checks for the portraits (tools/build_portraits.py, tools/portrait_parts.py).

The shipped product is checked against the hand-written contract: 81 cells, one
per option of every bound look slot and extra in every swatch, each its part
recoloured exactly. Every rule of the builder and of the cutter is then pinned
on synthetic fixtures in a temporary directory (a copy of portraits.json beside
a copy of people.json): a contract field, a source's size, alpha and colours,
the cross-part rules (a cap's brim, a hood's crown, glasses over an eye, the
face box, marks on the skin), the placeholders, a quiet re-run, and the cutter's
six rules. Nothing here writes to art/ or assets/; the people's products are
hashed before and after a build to prove the portraits never touch them.
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

import build_portraits as portraits
from build_portraits import (
    PARTS_DIR,
    PRODUCT_NAME,
    SHEET_NAME,
    PortraitError,
    build,
    load_parts,
    load_spec,
    placeholder,
)
from portrait_parts import base_picture, cut, look_of, pick, reference, sheet, split_base, ticks


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art" / "portraits"
OUTPUT = ROOT / "assets" / "portraits"
PEOPLE = ROOT / "art" / "pixel_people" / "people.json"
PEOPLE_PRODUCTS = ROOT / "assets" / "pixel_people"
BUILDER = ROOT / "tools" / "build_portraits.py"
CELL_COUNT = 81
SIZE = (80, 80)


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def rgb(colour: str) -> tuple[int, int, int]:
    return tuple(bytes.fromhex(colour))


def digest(directory: Path) -> dict[str, str]:
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(directory.iterdir())
            if path.is_file()}


class Fixture:
    """A portraits source in a temporary directory, with people.json beside it."""

    def __init__(self, root: Path, change=None):
        self.source = root / "portraits"
        self.output = root / "out"
        self.source.mkdir()
        (root / "pixel_people").mkdir()
        shutil.copy(PEOPLE, root / "pixel_people" / "people.json")
        data = load(SOURCE / "portraits.json")
        if change is not None:
            change(data)
        (self.source / "portraits.json").write_text(json.dumps(data))

    def spec(self) -> dict:
        return load_spec(self.source)

    def paint(self, name: str, image: Image.Image) -> Path:
        target = self.source / PARTS_DIR / f"{name}.png"
        target.parent.mkdir(exist_ok=True)
        image.save(target)
        return target


@contextlib.contextmanager
def fixture(change=None):
    with tempfile.TemporaryDirectory() as work:
        yield Fixture(Path(work), change)


def ink(spec: dict) -> tuple[int, int, int, int]:
    return (*rgb(spec["_people"]["fixed"]["ink"]), 255)


def key(spec: dict, role: str, tone: int) -> tuple[int, int, int, int]:
    return (*rgb(spec["_people"]["keys"][role][tone]), 255)


class ShippedPortraitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = load_spec(SOURCE)
        cls.manifest = load(OUTPUT / PRODUCT_NAME)
        with Image.open(OUTPUT / SHEET_NAME) as opened:
            cls.sheet = opened.convert("RGBA")

    def cell(self, name: str) -> Image.Image:
        index, columns = self.manifest["cells"][name], self.manifest["columns"]
        return self.sheet.crop(((index % columns) * 80, (index // columns) * 80,
                                (index % columns + 1) * 80, (index // columns + 1) * 80))

    def test_the_cells_are_every_option_of_every_bound_slot(self):
        people = self.spec["_people"]
        expected = []
        for layer, info in self.spec["layers"].items():
            shapes = [None]
            if info["shape"] in people["slots"]:
                shapes = list(people["slots"][info["shape"]]["shapes"])
            elif info["shape"] is not None:
                shapes = list(self.spec["extras"][info["shape"]]["options"])
            swatches = [None] if info["colour"] is None else list(people["slots"][info["colour"]]["swatches"])
            for shape in shapes:
                for swatch in swatches:
                    expected.append("_".join(part for part in (layer, shape, swatch) if part))
        self.assertEqual(list(self.manifest["cells"]), expected)
        self.assertEqual(len(expected), CELL_COUNT, "T + S + E*S + E*Hc + S + 1 + G + Hs*Hc + W*Wc")
        self.assertEqual(list(self.manifest["cells"].values()), list(range(CELL_COUNT)), "row-major, no gap")

    def test_the_sheet_is_nine_by_nine_cells(self):
        self.assertEqual(self.manifest["columns"], 9)
        self.assertEqual(self.sheet.size, (720, 720))
        self.assertEqual(self.manifest["files"], [SHEET_NAME])
        self.assertEqual([self.manifest[key] for key in ("density", "filter", "canvas", "pivot")],
                         [2, "nearest", [40, 40], [20, 40]])
        self.assertFalse((OUTPUT / "manifest.json").exists(), "the family is not a theme")

    def test_every_cell_is_its_part_recoloured_exactly(self):
        parts, mocked = load_parts(SOURCE, self.spec)
        self.assertEqual(self.manifest["mock_files"], sorted(mocked))
        for cell in portraits.cells(self.spec):
            built = self.cell(cell.name)
            source = parts[cell.source]
            self.assertEqual(built.getchannel("A").tobytes(), source.getchannel("A").tobytes(), cell.name)
            mapping = {}
            if cell.swatch is not None:
                role = portraits.role_of(self.spec, cell.layer)
                target = self.spec["_people"]["slots"][self.spec["layers"][cell.layer]["colour"]]["swatches"][cell.swatch]
                mapping = {rgb(k): rgb(t) for k, t in zip(self.spec["_people"]["keys"][role], target)}
            src, out = source.load(), built.load()
            for y in range(80):
                for x in range(80):
                    if src[x, y][3]:
                        self.assertEqual(out[x, y][:3], mapping.get(src[x, y][:3], src[x, y][:3]),
                                         f"{cell.name} ({x}, {y})")

    def test_the_extras_are_one_in_six_and_a_smile_by_default(self):
        extras = self.spec["extras"]
        self.assertEqual(extras["expression"]["options"], ["smile", "smirk", "focus"])
        self.assertEqual(extras["expression"]["default"], "smile")
        for name, option in (("marks", "freckles"), ("neckwear", "headphones")):
            self.assertEqual(extras[name]["pool"].count("none"), 5)
            self.assertEqual(extras[name]["pool"].count(option), 1)
            self.assertEqual(extras[name]["default"], "none")

    def test_the_picks_are_the_people_s_hash_under_new_names(self):
        pane = "local\x1fw0:t9:p7"
        self.assertEqual(pick("claude", pane, "skin"), 1107191239, "the people's own pinned hash")
        self.assertEqual(pick("claude", pane, "portrait.expression"), 3433880066)
        look = look_of(self.spec, "claude", "local\x1fw0:t9:p8")
        self.assertEqual([look["expression"], look["marks"], look["neckwear"], look["headwear"]],
                         ["focus", "freckles", "headphones", "hood"])
        self.assertEqual(look_of(self.spec, "claude", "")["expression"], "smile", "no pane: the default")


class ContractTests(unittest.TestCase):
    def refused(self, change, words: str):
        with fixture(change) as made:
            with self.assertRaises(PortraitError) as caught:
                made.spec()
            self.assertIn(words, str(caught.exception))

    def test_an_unknown_field_is_refused(self):
        self.refused(lambda data: data.update(glow=True), "unknown field")

    def test_a_layer_bound_to_a_shape_slot_as_its_colour_is_refused(self):
        self.refused(lambda data: data["layers"]["hair"].update(colour="hair_style"), "colour slot")

    def test_a_pivot_off_the_centre_is_refused(self):
        self.refused(lambda data: data.update(pivot=[19, 40]), "half the canvas")

    def test_a_canvas_other_than_40_is_refused(self):
        self.refused(lambda data: data.update(canvas=[48, 48]), "canvas must be [40, 40]")

    def test_layers_out_of_order_are_refused(self):
        def swap(data):
            data["layers"] = dict(reversed(list(data["layers"].items())))
        self.refused(swap, "in that order")

    def test_the_eyes_are_the_face_s_alone(self):
        self.refused(lambda data: data["layers"]["glasses"]["fixed"].append("eye"), "the face's alone")

    def test_a_portrait_colour_near_a_key_is_refused(self):
        self.refused(lambda data: data["fixed"].update(gear="2b2332"), "at least 12 apart")

    def test_more_than_three_portrait_colours_are_refused(self):
        self.refused(lambda data: data["fixed"].update(tongue="c05050"), "at most 3")

    def test_an_extra_that_shadows_a_look_slot_is_refused(self):
        self.refused(lambda data: data["extras"].update(glasses=data["extras"]["marks"]), "people look slot")


class BuildTests(unittest.TestCase):
    def test_missing_sources_are_drawn_listed_and_pass_every_check(self):
        with fixture() as made:
            manifest = build(made.source, made.output)
            spec = made.spec()
            names = [f"{PARTS_DIR}/{name}.png" for name, _layer in portraits.sources(spec)]
            self.assertEqual(manifest["mock_files"], sorted(names))
            self.assertEqual(len(names), 17)
            parts, _mocked = load_parts(made.source, spec)
            portraits.check_parts(spec, parts)
            self.assertEqual(len(manifest["cells"]), CELL_COUNT)

    def test_a_painted_source_replaces_its_placeholder(self):
        with fixture() as made:
            spec = made.spec()
            painted = placeholder(spec, "hair", "long")
            painted.putpixel((40, 12), key(spec, "hair", 2))
            made.paint("hair_long", painted)
            manifest = build(made.source, made.output)
            self.assertNotIn(f"{PARTS_DIR}/hair_long.png", manifest["mock_files"])
            self.assertEqual(len(manifest["mock_files"]), 16)

    def build_refuses(self, made: Fixture, words: str):
        with self.assertRaises(PortraitError) as caught:
            build(made.source, made.output)
        self.assertIn(words, str(caught.exception))
        return str(caught.exception)

    def test_a_source_of_the_wrong_size_is_refused(self):
        with fixture() as made:
            made.paint("head", Image.new("RGBA", (64, 64), (0, 0, 0, 0)))
            self.build_refuses(made, "is not the 80x80 canvas")

    def test_soft_alpha_is_refused(self):
        with fixture() as made:
            spec = made.spec()
            painted = placeholder(spec, "top", None)
            painted.putpixel((40, 75), (*key(spec, "top", 1)[:3], 128))
            made.paint("top", painted)
            self.build_refuses(made, "texel (40, 75) is semi-transparent")

    def test_a_foreign_colour_is_refused_with_its_texel(self):
        with fixture() as made:
            spec = made.spec()
            painted = placeholder(spec, "hair", "short")
            painted.putpixel((40, 20), key(spec, "skin", 1))
            made.paint("hair_short", painted)
            message = self.build_refuses(made, "parts/hair_short.png: texel (40, 20) is #2fd0e0")
            self.assertIn("not a colour the hair layer may hold", message)

    def test_a_part_the_contract_does_not_name_is_refused(self):
        with fixture() as made:
            made.paint("hair_mohawk", placeholder(made.spec(), "hair", "short"))
            self.build_refuses(made, "PNG(s) the contract does not name: hair_mohawk.png")

    def test_a_cap_that_leaves_long_hair_above_its_brim_is_refused(self):
        with fixture() as made:
            spec = made.spec()
            painted = placeholder(spec, "hair", "long")
            cap = placeholder(spec, "headwear", "cap")
            # A tuft of long hair over the crown, in the cap's column and above its
            # brim, where the cap does not cover it.
            hole = (40, 2)
            self.assertTrue(any(cap.getpixel((40, y))[3] for y in range(80)), "the cap draws in that column")
            self.assertEqual(cap.getpixel(hole)[3], 0, "and not there")
            painted.putpixel(hole, key(spec, "hair", 1))
            made.paint("hair_long", painted)
            self.build_refuses(made, f"hair_long.png: texel {hole} shows above the brim of headwear_cap.png")

    def test_a_hood_that_leaves_the_crown_bare_is_refused(self):
        with fixture() as made:
            spec = made.spec()
            hood = placeholder(spec, "headwear", "hood")
            crown = next((x, y) for y in range(28) for x in range(80)
                         if placeholder(spec, "head", None).getpixel((x, y))[3])
            hood.putpixel(crown, (0, 0, 0, 0))
            made.paint("headwear_hood", hood)
            self.build_refuses(made, f"head.png: texel {crown} of the crown shows past headwear_hood.png")

    def test_glasses_over_an_eye_are_refused(self):
        with fixture() as made:
            spec = made.spec()
            glasses = placeholder(spec, "glasses", "round")
            glasses.putpixel((29, 37), (*rgb(spec["_people"]["fixed"]["lens"]), 255))
            made.paint("glasses_round", glasses)
            self.build_refuses(made, "glasses_round.png: texel (29, 37) covers an eye of face_smile.png")

    def test_a_face_texel_outside_the_face_box_is_refused(self):
        with fixture() as made:
            spec = made.spec()
            face = placeholder(spec, "face", "smirk")
            face.putpixel((40, 52), ink(spec))
            made.paint("face_smirk", face)
            self.build_refuses(made, "face_smirk.png: texel (40, 52) is outside face_box")

    def test_marks_off_the_skin_are_refused(self):
        with fixture() as made:
            spec = made.spec()
            marks = placeholder(spec, "marks", "freckles")
            marks.putpixel((2, 2), key(spec, "skin", 2))
            made.paint("marks_freckles", marks)
            self.build_refuses(made, "marks_freckles.png: texel (2, 2) is not over head.png's skin")

    def test_a_re_run_writes_nothing(self):
        with fixture() as made:
            build(made.source, made.output)
            before = {path.name: (path.stat().st_mtime_ns, path.read_bytes()) for path in made.output.iterdir()}
            build(made.source, made.output)
            after = {path.name: (path.stat().st_mtime_ns, path.read_bytes()) for path in made.output.iterdir()}
            self.assertEqual(before, after)

    def test_the_people_products_are_byte_identical_after_a_build(self):
        before = digest(PEOPLE_PRODUCTS)
        with tempfile.TemporaryDirectory() as work:
            result = subprocess.run([sys.executable, str(BUILDER), "--output", work], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PORTRAITS_BUILD_OK", result.stdout)
        self.assertEqual(digest(PEOPLE_PRODUCTS), before)
        self.assertEqual(sorted(before), ["back.png", "back.png.import", "front.png", "front.png.import",
                                          "people_manifest.json", "side.png", "side.png.import"])


class CutterTests(unittest.TestCase):
    def picture(self, made: Fixture, wear=()) -> Image.Image:
        return base_picture(made.source, made.spec(), list(wear))

    def test_an_erased_base_texel_is_refused(self):
        with fixture() as made:
            painted = self.picture(made)
            painted.putpixel((40, 70), (0, 0, 0, 0))
            path = made.source.parent / "painted.png"
            painted.save(path)
            with self.assertRaises(PortraitError) as caught:
                cut(path, made.source, "hair", "short")
            self.assertIn("never erases", str(caught.exception))
            self.assertFalse((made.source / PARTS_DIR).exists(), "nothing written")

    def test_drift_is_refused_or_dropped_and_printed(self):
        with fixture() as made:
            spec = made.spec()
            painted = self.picture(made)
            painted.alpha_composite(placeholder(spec, "hair", "short"))
            painted.putpixel((40, 75), key(spec, "top", 0))  # the model repainted the collar
            path = made.source.parent / "painted.png"
            painted.save(path)
            with self.assertRaises(PortraitError) as caught:
                cut(path, made.source, "hair", "short")
            self.assertIn("texel (40, 75) #8ff08a", str(caught.exception))
            printed = io.StringIO()
            with contextlib.redirect_stdout(printed):
                files = cut(path, made.source, "hair", "short", drop_drift=True)
            self.assertIn("PORTRAIT_DRIFT:", printed.getvalue())
            self.assertIn("texel (40, 75) #8ff08a", printed.getvalue())
            with Image.open(files[0]) as hair:
                self.assertEqual(hair.convert("RGBA").getpixel((40, 75))[3], 0, "the drift is not the hair's")

    def test_a_hair_outline_over_the_skin_is_the_hair_s(self):
        with fixture() as made:
            spec = made.spec()
            painted = self.picture(made)
            hair = placeholder(spec, "hair", "short")
            painted.alpha_composite(hair)
            path = made.source.parent / "painted.png"
            painted.save(path)
            with contextlib.redirect_stdout(io.StringIO()):
                files = cut(path, made.source, "hair", "short")
            with Image.open(files[0]) as cut_hair:
                cut_hair = cut_hair.convert("RGBA")
            head = placeholder(spec, "head", None)
            over_skin = [(x, y) for y in range(80) for x in range(80) if hair.getpixel((x, y)) == ink(spec)
                         and head.getpixel((x, y))[3] and head.getpixel((x, y)) != ink(spec)]
            self.assertTrue(over_skin, "the fixture has hair ink over skin")
            for texel in over_skin:
                self.assertEqual(cut_hair.getpixel(texel), ink(spec), f"{texel}: ink over skin is the hair's")
            shared = [(x, y) for y in range(80) for x in range(80)
                      if hair.getpixel((x, y)) == ink(spec) == head.getpixel((x, y))]
            for texel in shared:
                self.assertEqual(cut_hair.getpixel(texel)[3], 0, f"{texel}: ink identical to the base stays the base's")

    def test_an_expression_splits_into_face_and_brows(self):
        with fixture() as made:
            spec = made.spec()
            painted = self.picture(made)
            painted.alpha_composite(placeholder(spec, "face", "smirk"))
            painted.alpha_composite(placeholder(spec, "brows", "smirk"))
            path = made.source.parent / "painted.png"
            painted.save(path)
            with contextlib.redirect_stdout(io.StringIO()):
                files = cut(path, made.source, "expression", "smirk")
            self.assertEqual([file.name for file in files], ["face_smirk.png", "brows_smirk.png"])
            hair = {rgb(colour) for colour in spec["_people"]["keys"]["hair"]}
            with Image.open(files[0]) as face, Image.open(files[1]) as brows:
                face, brows = face.convert("RGBA"), brows.convert("RGBA")
                for y in range(80):
                    for x in range(80):
                        if brows.getpixel((x, y))[3]:
                            self.assertIn(brows.getpixel((x, y))[:3], hair)
                        if face.getpixel((x, y))[3]:
                            self.assertNotIn(face.getpixel((x, y))[:3], hair)
                self.assertEqual(brows.tobytes(), placeholder(spec, "brows", "smirk").tobytes())
            build(made.source, made.output)

    def test_a_part_is_never_overwritten(self):
        with fixture() as made:
            spec = made.spec()
            painted = self.picture(made)
            painted.alpha_composite(placeholder(spec, "hair", "curl"))
            path = made.source.parent / "painted.png"
            painted.save(path)
            made.paint("hair_curl", placeholder(spec, "hair", "curl"))
            before = (made.source / PARTS_DIR / "hair_curl.png").read_bytes()
            with self.assertRaises(PortraitError) as caught:
                cut(path, made.source, "hair", "curl")
            self.assertIn("never overwritten", str(caught.exception))
            self.assertEqual((made.source / PARTS_DIR / "hair_curl.png").read_bytes(), before)

    def test_the_base_splits_by_rule_five(self):
        with fixture() as made:
            spec = made.spec()
            s, t, k = key(spec, "skin", 1), key(spec, "top", 1), ink(spec)
            rows = (
                "........",
                ".kkkk...",
                ".kssk...",
                ".kssk.k.",
                "kkkkkkk.",
                "ktttttk.",
                "ktttttk.",
                "kkkkkkkk",
            )
            colours = {"s": s, "t": t, "k": k}
            picture = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
            for y, row in enumerate(rows):
                for x, letter in enumerate(row):
                    if letter in colours:
                        picture.putpixel((x, y), colours[letter])
            head, top = split_base(picture, spec, "fixture")
            owner = {}
            for y in range(8):
                for x in range(8):
                    if head.getpixel((x, y))[3]:
                        owner[(x, y)] = "h"
                    if top.getpixel((x, y))[3]:
                        self.assertNotIn((x, y), owner, "a texel is one layer's")
                        owner[(x, y)] = "t"
            drawn = ["".join(owner.get((x, y), ".") for x in range(8)) for y in range(8)]
            self.assertEqual(drawn, [
                "........",
                ".hhhh...",  # ink touching the skin is the head's
                ".hhhh...",
                ".hhhh.t.",  # ink touching neither belongs to the ink it touches (the top's)
                "thhhhtt.",  # ink touching both is the head's (the upper layer)
                "ttttttt.",  # ink touching only the top is the top's
                "ttttttt.",
                "tttttttt",
            ])
            foreign = picture.copy()
            foreign.putpixel((0, 0), key(spec, "hair", 1))
            with self.assertRaises(PortraitError):
                split_base(foreign, spec, "fixture")

    def test_the_base_cut_writes_head_and_top_and_needs_its_ticks(self):
        with fixture() as made:
            spec = made.spec()
            painted = self.picture(made)
            path = made.source.parent / "painted.png"
            painted.save(path)
            with contextlib.redirect_stdout(io.StringIO()):
                files = cut(path, made.source, "base", None)
            self.assertEqual([file.name for file in files], ["head.png", "top.png"])
            with Image.open(files[0]) as head:
                self.assertEqual(head.convert("RGBA").tobytes(), placeholder(spec, "head", None).tobytes())
            for file in files:
                file.unlink()
            lost = painted.copy()
            for texel in ticks(spec):
                lost.putpixel(texel, (0, 0, 0, 0))
            lost.save(path)
            with self.assertRaises(PortraitError) as caught:
                cut(path, made.source, "base", None)
            self.assertIn("registration ticks", str(caught.exception))

    def test_reference_writes_only_into_an_empty_directory(self):
        with fixture() as made:
            out = made.source.parent / "ref"
            printed = io.StringIO()
            with contextlib.redirect_stdout(printed):
                reference(made.source, "headwear", out, [])
            self.assertIn("PIXELIZE: --size 80x80 --pivot 40,80 --fit 80x80 --stretch --key 9a9a9a", printed.getvalue())
            self.assertIn("key.hat.0", printed.getvalue())
            with Image.open(out / "reference.png") as shown:
                self.assertEqual(shown.size, (640, 640))
            with self.assertRaises(PortraitError):
                reference(made.source, "headwear", out, [])

    def test_the_sheet_writes_only_into_an_empty_directory(self):
        with fixture() as made:
            out = made.source.parent / "sheet"
            out.mkdir()
            (out / "keep.txt").write_text("work")
            with self.assertRaises(PortraitError):
                sheet(made.source, out)
            self.assertEqual((out / "keep.txt").read_text(), "work")
            fresh = made.source.parent / "fresh"
            with contextlib.redirect_stdout(io.StringIO()):
                target = sheet(made.source, fresh)
            self.assertEqual([path.name for path in fresh.iterdir()], [target.name])


if __name__ == "__main__":
    unittest.main()
