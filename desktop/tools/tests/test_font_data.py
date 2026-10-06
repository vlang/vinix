#!/usr/bin/env python3
"""Check actual baked glyphs; optionally render them with VINIX_FONT_PREVIEW."""

import base64
import importlib.util
import os
from pathlib import Path
import re
import unittest

from PIL import Image, ImageDraw


DESKTOP = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("genfont", DESKTOP / "tools/genfont.py")
genfont = importlib.util.module_from_spec(spec)
spec.loader.exec_module(genfont)


def atlas_faces():
    source = (DESKTOP / "font_data.v").read_text()
    extras = [int(value, 16) for value in re.findall(
        r"0x([0-9a-f]+)", re.search(r"const font_extra_runes = \[(.*?)\]", source).group(1))]
    code_points = list(range(genfont.FIRST_CHAR, genfont.LAST_CHAR + 1)) + extras
    faces = {}
    for name, body in re.findall(r"const face_(\w+) = FaceBlob\{(.*?)\n\}", source, re.S):
        raw = base64.b64decode("".join(re.findall(r"'([A-Za-z0-9+/=]+)'", body)))
        face = {key: int(re.search(r"\b" + key + r":\s*(\d+)", body).group(1))
                for key in ("size", "raster_scale", "ascent", "descent")}
        face["glyphs"] = {}
        offset = len(code_points) * 5
        for index, cp in enumerate(code_points):
            width, height, bx, by, advance = raw[index * 5:index * 5 + 5]
            mask = raw[offset:offset + width * height]
            face["glyphs"][cp] = (width, height, bx, by, advance, mask)
            offset += width * height
        if offset != len(raw):
            raise AssertionError("atlas length mismatch: " + name)
        faces[name] = face
    return extras, faces


EXTRAS, FACES = atlas_faces()


class FontDataTests(unittest.TestCase):
    def test_every_catalog_and_native_name_character_is_baked(self):
        self.assertEqual(EXTRAS, sorted(set(EXTRAS)))
        missing = genfont.translation_runes() - set(EXTRAS)
        self.assertFalse(missing, "missing: " + ", ".join("U+%04X" % cp for cp in sorted(missing)))
        expected = {"%s_%dx" % (name, scale)
                    for name, _, _, _ in genfont.FACES for scale in genfont.RASTER_SCALES}
        self.assertEqual(set(FACES), expected)

    def test_chinese_masks_are_real_and_fit_existing_line_boxes(self):
        required = {cp for cp in genfont.chinese_runes() if genfont.is_cjk(cp)}
        self.assertTrue(required)
        for name, filename, size, bold in genfont.FACES:
            for scale in genfont.RASTER_SCALES:
                face = FACES["%s_%dx" % (name, scale)]
                primary_metrics = genfont.open_font(filename, size).getmetrics()
                self.assertEqual((face["ascent"], face["descent"]), primary_metrics)
                for cp in required:
                    with self.subTest(face=name, scale=scale, rune=chr(cp)):
                        glyph = face["glyphs"][cp]
                        source = genfont.glyph_font(filename, size * scale, bold, cp)
                        real = genfont.rasterise(source, cp)
                        notdef = genfont.missing_glyph(source)
                        self.assertNotEqual(real, notdef)
                        self.assertEqual(glyph[5], real[5])
                        self.assertTrue(any(glyph[5]))
                        self.assertGreater(glyph[4], 0)
                        self.assertLessEqual(glyph[3] + glyph[1], sum(primary_metrics) * scale)
                        if name == "mono":
                            self.assertEqual(glyph[4], 2 * face["glyphs"][ord("M")][4])

    def test_logical_advance_agrees_between_scales(self):
        for name, _, _, _ in genfont.FACES:
            at_1x = FACES[name + "_1x"]["glyphs"]
            at_2x = FACES[name + "_2x"]["glyphs"]
            for cp in at_1x:
                with self.subTest(face=name, rune=chr(cp)):
                    self.assertEqual(at_1x[cp][4] * 2, at_2x[cp][4])

    def test_japanese_only_masks_and_terminal_columns_are_preserved(self):
        japanese_only = set(genfont.japanese_runes()) - genfont.chinese_runes()
        self.assertIn(ord("の"), japanese_only)
        for name, filename, size, bold in genfont.FACES:
            for scale in genfont.RASTER_SCALES:
                face = FACES["%s_%dx" % (name, scale)]
                primary = genfont.open_font(filename, size * scale)
                for cp in japanese_only:
                    source = genfont.glyph_font(filename, size * scale, bold, cp)
                    with self.subTest(face=name, scale=scale, rune=chr(cp)):
                        glyph = face["glyphs"][cp]
                        real = genfont.rasterise(source, cp)
                        self.assertEqual(glyph[5], real[5])
                        self.assertNotEqual(real, genfont.missing_glyph(source))
                        if source is not primary:
                            self.assertIs(source, genfont.open_japanese_font(bold, size * scale))
                            self.assertLessEqual(glyph[3] + glyph[1], (face["ascent"] + face["descent"]) * scale)
                            if name == "mono":
                                cell = int(round(genfont.open_font(filename, size).getlength("M")))
                                self.assertEqual(glyph[4], 2 * cell * scale)

    def test_distinct_chinese_letters_and_weights(self):
        for scale in genfont.RASTER_SCALES:
            regular = FACES["ui_%dx" % scale]["glyphs"]
            bold = FACES["bold_%dx" % scale]["glyphs"]
            self.assertNotEqual(regular[ord("中")][5], regular[ord("文")][5])
            self.assertNotEqual(regular[ord("中")][5], bold[ord("中")][5])


def write_preview(path):
    image = Image.new("RGB", (820, 740), "#fafafa")
    draw = ImageDraw.Draw(image)
    sample = "中文（简体）"
    for column, scale in enumerate(genfont.RASTER_SCALES):
        y = 18
        for name, _, _, _ in genfont.FACES:
            face = FACES["%s_%dx" % (name, scale)]
            pen = 20 + column * 400
            draw.text((pen, y), "%s %dpx / %dx" % (name, face["size"], scale), fill="#666666")
            for ch in sample:
                glyph = face["glyphs"].get(ord(ch))
                if glyph is None:
                    continue
                width, height, bx, by, advance, mask = glyph
                if width and height:
                    alpha = Image.frombytes("L", (width, height), mask)
                    image.paste("#151515", (pen + (bx if bx < 128 else bx - 256), y + by + 18), alpha)
                pen += advance
            y += 90
    image.save(path)


if __name__ == "__main__":
    if os.environ.get("VINIX_FONT_PREVIEW"):
        write_preview(os.environ["VINIX_FONT_PREVIEW"])
    unittest.main()
