// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
module fonthost

import crypto.sha256
import encoding.base64
import encoding.hex
import fixturehost
import json2
import math
import math.big
import os

fn floor_half(value big.Integer) big.Integer {
    quotient, remainder := value.div_mod(big.integer_from_int(2))
    return if value.signum < 0 && remainder.signum != 0 { quotient - big.one_int } else { quotient }
}
fn length(id int, cp int) !big.Integer {
    return rounded(callback('length', {'font': json2.Any(id), 'code_point': json2.Any(cp)})!)!
}
fn metrics(id int) ![]int { return integers(callback('metrics', {'font': json2.Any(id)})!) }

fn (mut e Engine) build_face(file string, size int, bold bool, scale int, extras []int, japanese []int) !map[string]json2.Any {
	logical := e.open_font(file, size)!
	font := e.open_font(file, size * scale)!
	logical_metrics := metrics(logical)!
	ascent := logical_metrics[0]; descent := logical_metrics[1]
	mut header := []u8{}
	mut pixels := []u8{}
	mut points := []int{}
	for cp in 32 .. 127 { points << cp }
	points << extras
	for cp in points {
		raster_font := e.glyph_font(file, size * scale, bold, cp, japanese, false)!
		advance_font := e.glyph_font(file, size, bold, cp, japanese, false)!
		glyph := rasterise(raster_font, cp)!
		logical_advance := length(advance_font, cp)!
        mut advance := logical_advance * big.integer_from_int(scale)
        mut bearing := big.integer_from_int(glyph.bx); mut by := glyph.by
		if raster_font != font {
			by += metrics(font)![0] - metrics(raster_font)![0]
			if file.contains('Mono') {
                advance = big.integer_from_int(2) * length(logical, int(`M`))! * big.integer_from_int(scale)
                bearing += floor_half(advance - logical_advance * big.integer_from_int(scale))
			}
			line_height := (ascent + descent) * scale
			if e.is_chinese(cp)! {
				if glyph.height > line_height { return fail('Chinese glyph U+${cp:04X} exceeds the ${size}px line box') }
				by = math.max(0, math.min(by, line_height - glyph.height))
			} else if by < 0 || by + glyph.height > line_height { return fail('Japanese glyph U+${cp:04X} exceeds the ${size}px line box') }
		}
        if bearing < big.integer_from_int(-128) || bearing > big.integer_from_int(127) { return fail('left bearing out of range for U+${cp:04X}') }
        if glyph.width < 0 || glyph.width > 255 || glyph.height < 0 || glyph.height > 255 || advance < big.zero_int || advance > big.integer_from_int(255) {
			return fail('glyph metrics out of range for U+${cp:04X}')
		}
        bx := bearing.int()
        header << [u8(glyph.width), u8(glyph.height), u8(bx & 255), u8(by & 255), u8(advance.int())]
		pixels << hex.decode(glyph.pixels)!
	}
	header << pixels
	return {'ascent': json2.Any(ascent), 'descent': json2.Any(descent), 'blob': json2.Any(base64.encode(header))}
}

pub fn wrap(value string, width int) ![]string {
	if width == 0 { return FontError{'ValueError', 'range() arg 3 must not be zero'} }
	if width < 0 { return []string{} }
	mut result := []string{}
    offsets := text_offsets(value)
    count := offsets.len - 1
    for start := 0; start < count; start += width {
        result << value[offsets[start]..offsets[math.min(start + width, count)]]
	}
	return result
}

// The import API accepts Python strings containing lone surrogates. Their
// transport is WTF-8; keep one slot per code point and retain the original
// bytes rather than asking V's strict rune decoder to replace them.
fn text_offsets(value string) []int {
    mut result := [0]
    mut offset := 0
    for offset < value.len {
        byte := value[offset]
        offset += if byte < 0x80 { 1 } else if byte < 0xe0 { 2 } else if byte < 0xf0 { 3 } else { 4 }
        result << math.min(offset, value.len)
    }
    return result
}

// fontTools owns parsing, subsetting and variable-font instantiation. V owns
// pinned-source verification, missing coverage, subset options, naming and
// publication order; callbacks only apply the specified library operations.
fn (mut e Engine) update_japanese(points []int, source_path string) ! {
	callback('fonttools_import', {})!
	mut data := ''
	if source_path != '' { data = fixturehost.read(hex.decode(source_path)!.bytestr())! } else {
		emit('Downloading pinned Noto Sans JP source...')!
		data = hex.decode(callback('fetch', {'url': value(e.context, 'japanese_url'), 'timeout': json2.Any(60)})!.str())!.bytestr()
	}
	if sha256.hexhash(data) != text(e.context, 'japanese_sha256') { return fail('Noto Sans JP source SHA-256 does not match the pinned font') }
	id := int(callback('tt_open', {'data': json2.Any(data.bytes().hex()), 'recalc_timestamp': json2.Any(false)})!.i64())
	defer { callback('tt_close', {'font': json2.Any(id)}) or {} }
	coverage := integers(callback('tt_cmap', {'font': json2.Any(id)})!)
	mut missing := points.filter(it !in coverage); missing.sort()
	if missing.len > 0 { return fail('upstream Japanese font lacks: ' + missing.map('U+${it:04X}').join(', ')) }
	callback('tt_subset', {'font': json2.Any(id), 'runes': integer_value(points), 'name_ids': integer_value([13, 14, 16, 17]), 'layout_features': json2.Any([]json2.Any{})})!
	make_directory(e.path('japanese_fonts'), false)!
	for weight in [400, 700] {
		bold := weight == 700
		style := if bold { 'Bold' } else { 'Regular' }
		static_id := int(callback('tt_instantiate', {'font': json2.Any(id), 'weight': json2.Any(weight), 'inplace': json2.Any(false)})!.i64())
		defer { callback('tt_close', {'font': json2.Any(static_id)}) or {} }
		names := {'1': json2.Any('Vinix Japanese'), '2': json2.Any(style), '3': json2.Any('VinixJapanese-' + style), '4': json2.Any('Vinix Japanese ' + style), '6': json2.Any('VinixJapanese-' + style), '16': json2.Any('Vinix Japanese'), '17': json2.Any(style)}
		for raw_record in callback('tt_records', {'font': json2.Any(static_id)})!.as_array() {
			record := raw_record.as_array()
			key := record[0].str()
			if key in names { callback('tt_set_name', {'font': json2.Any(static_id), 'name': value(names, key), 'record': raw_record})! }
		}
		path := e.japanese_path(bold)
		callback('tt_save', {'font': json2.Any(static_id), 'path': json2.Any(path.bytes().hex())})!
		state := os.stat(path)!
		emit('wrote ${path} (${state.size} bytes, ${points.len} characters)')!
	}
}

fn (mut e Engine) generate(args map[string]json2.Any) !json2.Any {
	japanese := e.japanese_runes()!
	if value(args, 'update').bool() { e.update_japanese(japanese, text(args, 'source'))! }
	emit('Checking supplemental runes...')!
	faces := value(e.context, 'faces').as_array()
	extras := e.supported_extras(faces, japanese, e.translation_runes()!)!
	emit('  kept ${extras.len} supplemental runes, including ${japanese.len} Japanese catalog characters')!
	mut out := prelude()
	out << 'const font_first_char = 32'
	out << 'const font_last_char = 126'
	if extras.len == 0 { out << 'const font_extra_runes = []u32{}' } else {
		mut listed := []string{}
		for i, cp in extras { listed << if i == 0 { 'u32(0x${cp:04x})' } else { '0x${cp:04x}' } }
		out << 'const font_extra_runes = [${listed.join(', ')}]'
	}
	out << ''
	mut names := []string{}
	for scale in integers(value(e.context, 'scales')) {
		for raw in faces {
			face := raw.as_array()
			name := face[0].str(); file := face[1].str(); size := int(face[2].i64()); bold := face[3].bool()
			blob := e.build_face(file, size, bold, scale, extras, japanese)!
			scaled := '${name}_${scale}x'; names << scaled
			out << '// ${name}: ${file} at ${size}px (${scale}x raster)'
			out << 'const face_${scaled} = FaceBlob{'
			out << '\tbold:    ${bold}'
			out << '\tmono:    ${file.contains('Mono')}'
			out << '\tsize:    ${size}'
			out << '\traster_scale: ${scale}'
			out << '\tascent:  ${value(blob, 'ascent').str()}'
			out << '\tdescent: ${value(blob, 'descent').str()}'
			out << '\tparts:   ['
			for part in wrap(value(blob, 'blob').str(), 100)! { out << "\t\t'${part}'," }
			out << ['\t]', '}', '']
		}
	}
	out << ['// font_blobs is the set the renderer chooses from.', 'const font_blobs = [']
	for name in names { out << '\tface_${name},' }
	out << [']', '']
	path := e.path('target')
	fixturehost.write(path, out.join('\n'))!
	state := os.stat(path)!
	emit('wrote ${path} (${state.size} bytes)')!
	return json2.Null{}
}
