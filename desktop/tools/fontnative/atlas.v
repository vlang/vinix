// SPDX-License-Identifier: GPL-2.0-or-later
module fontnative

import compress.zlib
import encoding.base64
import os
import strconv

pub struct BakedGlyph {
pub:
	width   int
	height  int
	bx      int
	by      int
	advance int
	pixels  []u8
}

pub struct BakedFace {
pub:
	name    string
	size    int
	scale   int
	ascent  int
	descent int
	bold    bool
	mono    bool
	glyphs  map[int]BakedGlyph
}

pub struct Atlas {
pub:
	extras []int
	faces  map[string]BakedFace
}

fn scalar(body string, name string) !string {
	for line in body.split_into_lines() {
		text := line.trim_space()
		if text.starts_with(name + ':') { return text.all_after(':').trim_space() }
	}
	return error('atlas field missing: ' + name)
}

pub fn atlas(path string) !Atlas {
	source := os.read_file(path)!
	marker := 'const font_extra_runes = ['
	if !source.contains(marker) { return error('atlas supplemental rune list missing') }
	mut extras := []int{}
	for item in source.all_after(marker).all_before(']').split(',') {
		raw := item.trim_space().all_after('0x').trim_right(')')
		extras << int(strconv.parse_uint(raw, 16, 32)!)
	}
	mut points := []int{}
	for point in 32 .. 127 { points << point }
	points << extras
	mut faces := map[string]BakedFace{}
	for section in source.split('const face_')[1..] {
		name := section.all_before(' = FaceBlob{')
		body := section.all_after(' = FaceBlob{').all_before('\n}')
		if name in faces { return error('duplicate atlas face') }
		data := scalar(body, 'data')!.trim("'")
		mut raw := base64.decode(data)
		if body.contains('decoded_size:') {
			raw = zlib.decompress(raw)!
			if raw.len != scalar(body, 'decoded_size')!.int() {
				return error('decoded atlas size mismatch: ' + name)
			}
			metrics := base64.decode(scalar(body, 'metrics')!.trim("'"))
			if raw.len < points.len * 5 || metrics != raw[..points.len * 5] {
				return error('atlas metrics mismatch: ' + name)
			}
		}
		if raw.len < points.len * 5 { return error('atlas header truncated') }
		mut offset := points.len * 5
		mut glyphs := map[int]BakedGlyph{}
		for index, point in points {
			header := unsafe { raw[index * 5..index * 5 + 5] }
			width, height := int(header[0]), int(header[1])
			end := offset + width * height
			if end > raw.len { return error('atlas mask truncated') }
			glyphs[point] = BakedGlyph{width, height, int(i8(header[2])), int(header[3]), int(header[4]), raw[offset..end].clone()}
			offset = end
		}
		if offset != raw.len { return error('atlas has trailing mask bytes') }
		faces[name] = BakedFace{name, scalar(body, 'size')!.int(), scalar(body, 'raster_scale')!.int(), scalar(body, 'ascent')!.int(), scalar(body, 'descent')!.int(), scalar(body, 'bold')! == 'true', scalar(body, 'mono')! == 'true', glyphs}
	}
	if faces.len == 0 { return error('atlas has no faces') }
	return Atlas{extras, faces}
}
