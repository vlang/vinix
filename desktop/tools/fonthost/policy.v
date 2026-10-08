// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
module fonthost

import crypto.sha256
import encoding.hex
import fixturehost
import hosttest
import json2
import math
import math.big
import os

pub struct FontError {
pub:
	kind string
	message string
}
pub fn (e FontError) msg() string { return e.message }
pub fn (e FontError) code() int { return 0 }

pub struct BindingError {
pub:
	value map[string]json2.Any
}
pub fn (e BindingError) msg() string { return value(e.value, 'message').str() }
pub fn (e BindingError) code() int { return 0 }

// The caller owns Pillow/fontTools objects. Native policy stores opaque IDs,
// never addresses or borrowed buffers from either Python or a library.
pub struct Engine {
mut:
	context map[string]json2.Any
	chinese []int
	chinese_ready bool
	japanese []int
	japanese_ready bool
	fonts map[string]int
	cjk_paths map[string]string
	missing map[int]Glyph
	available map[string]bool
}

pub fn callback(operation string, arguments map[string]json2.Any) !json2.Any {
	println(json2.encode({'callback': json2.Any(operation), 'arguments': json2.Any(arguments)}, escape_unicode: true))
	row := hosttest.decode_json(os.get_raw_line())!.as_map()
	if 'error' in row { return BindingError{value(row, 'error').as_map()} }
	return row['value']!
}

fn emit(text string) ! {
	callback('print', {'text': json2.Any(text)})!
}

fn fail(text string) IError { return FontError{'SystemExit', text} }
fn value(row map[string]json2.Any, name string) json2.Any { return row[name] or { json2.Null{} } }
fn number(row map[string]json2.Any, name string) int { return int(value(row, name).i64()) }
fn text(row map[string]json2.Any, name string) string { return value(row, name).str() }
fn integers(value json2.Any) []int { return value.as_array().map(int(it.i64())) }
fn integer_value(values []int) json2.Any { return json2.Any(values.map(json2.Any(it))) }
fn join(parent string, child string) string {
    return if child.starts_with('/') || parent == '' { child } else { parent.trim_right('/') + '/' + child }
}
fn path_literal(path string) string {
    parts := path.split('/').filter(it != '' && it != '.')
    prefix := if path.starts_with('//') && !path.starts_with('///') { '//' } else if path.starts_with('/') { '/' } else { '' }
    result := prefix + parts.join('/')
    return if result == '' { '.' } else { result }
}
fn (e Engine) path(name string) string { return hex.decode(value(e.context, name).str()) or { []u8{} }.bytestr() }
fn read_text(path string) !string {
	raw := fixturehost.read(path)!
	hosttest.module_decode_utf8(raw)!
	return raw.replace('\r\n', '\n').replace('\r', '\n')
}

fn whitespace(ch rune) bool {
	return ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, rune(0x85), rune(0xa0), rune(0x1680),
		rune(0x2028), rune(0x2029), rune(0x202f), rune(0x205f), rune(0x3000)]
		|| (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a)
}
fn strip_space(value string) string {
	runes := value.runes()
	mut first := 0
	mut last := runes.len
	for first < last && whitespace(runes[first]) { first++ }
	for last > first && whitespace(runes[last-1]) { last-- }
	return runes[first..last].string()
}
fn split_lines(value string) []string {
	mut result := []string{}
	mut start := 0
	mut offset := 0
	mut skip_lf := false
	for ch in value.runes() {
		byte_length := ch.str().len
		if skip_lf && ch == `\n` { offset += byte_length; start = offset; skip_lf = false; continue }
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133), rune(0x2028), rune(0x2029)] {
			result << value[start..offset]
			start = offset + byte_length
			skip_lf = ch == `\r`
		}
		offset += byte_length
	}
	if start < value.len { result << value[start..] }
	return result
}
pub fn catalog_runes(paths []string) ![]int {
	mut characters := map[int]bool{}
	for path in paths {
		for block in read_text(path)!.split('-----') {
			lines := split_lines(strip_space(block))
			if lines.len >= 2 {
				for ch in lines[1..].join('\n').runes() {
					if ch > 126 && !whitespace(ch) { characters[int(ch)] = true }
				}
			}
		}
	}
	mut result := characters.keys(); result.sort(); return result
}
fn add_characters(values []int, extra string) []int {
	mut all := map[int]bool{}
	for value in values { all[value] = true }
	for ch in extra.runes() { all[int(ch)] = true }
	mut result := all.keys(); result.sort(); return result
}
fn cjk(cp int) bool { return (cp >= 0x3000 && cp <= 0x303f) || (cp >= 0x3400 && cp <= 0x9fff) || (cp >= 0xff00 && cp <= 0xffef) }
fn (mut e Engine) chinese_runes() ![]int {
	if !e.chinese_ready {
		e.chinese = add_characters(catalog_runes([join(e.path('desktop'), 'translations/zh.tr')])!, '中文（简体）')
		e.chinese_ready = true
	}
	return e.chinese.clone()
}
fn (mut e Engine) is_chinese(cp int) !bool { return cjk(cp) && cp in e.chinese_runes()! }
fn (mut e Engine) japanese_runes() ![]int {
	if !e.japanese_ready {
		path := e.path('japanese_catalog')
		if !os.exists(path) { return fail('Japanese catalog not found: ' + path) }
		mut values := map[int]bool{}
		for ch in (read_text(path)! + '日本語').runes() { if ch > 126 { values[int(ch)] = true } }
		e.japanese = values.keys(); e.japanese.sort(); e.japanese_ready = true
	}
	return e.japanese.clone()
}
fn (e Engine) translation_runes() ![]int {
	directory := join(e.path('desktop'), 'translations')
	mut paths := []string{}
	for name in os.ls(directory) or { []string{} } {
		if name.ends_with('.tr') { paths << join(directory, name) }
	}
	paths.sort()
	return add_characters(catalog_runes(paths)!, '中文（简体）日本語')
}
fn (mut e Engine) cjk_path(file string) !string {
	if file in e.cjk_paths { return e.cjk_paths[file] }
    path := path_literal(join(join(e.path('cache'), 'noto-cjk-2.004'), file))
	if !os.exists(path) {
		emit('Downloading ${file}...')!
		data := hex.decode(callback('fetch', {'url': json2.Any(text(e.context, 'cjk_url') + file), 'timeout': json2.Any(60)})!.str())!
        if sha256.hexhash(data.bytestr()) != e.cjk_source(file)! { return fail('download checksum mismatch: ' + file) }
		make_directory(path.all_before_last('/'), true)!
		fixturehost.write(path, data.bytestr())!
	}
    if sha256.hexhash(fixturehost.read(path)!) != e.cjk_source(file)! { return fail('cached font checksum mismatch: ' + path) }
	e.cjk_paths[file] = path
	return path
}
fn (e Engine) cjk_source(file string) !string {
    sources := value(e.context, 'cjk_sources').as_map()
    if file !in sources { return FontError{'KeyError', file} }
    return value(sources, file).str()
}
fn (e Engine) japanese_path(bold bool) string {
	return join(e.path('japanese_fonts'), 'VinixJapanese-' + if bold { 'Bold' } else { 'Regular' } + '.ttf')
}
fn (mut e Engine) open_font(file string, size int) !int {
	key := 'primary:${file}:${size}'
	if key in e.fonts { return e.fonts[key] }
	path := join(e.path('fonts'), file)
	if !os.exists(path) { return fail('font not found: ' + path) }
	id := int(callback('open', {'path': json2.Any(path.bytes().hex()), 'size': json2.Any(size), 'owner': json2.Any('primary')})!.i64())
	e.fonts[key] = id; return id
}
fn (mut e Engine) open_japanese(bold bool, size int) !int {
	key := 'japanese:${bold}:${size}'
	if key in e.fonts { return e.fonts[key] }
	path := e.japanese_path(bold)
	if !os.exists(path) { return fail('Japanese subset not found: ' + path + '; run with --update-japanese-subsets') }
	id := int(callback('open', {'path': json2.Any(path.bytes().hex()), 'size': json2.Any(size), 'owner': json2.Any('japanese')})!.i64())
	e.fonts[key] = id; return id
}

struct Glyph {
	width int
	height int
	bx int
	by int
    advance big.Integer
	pixels string
}
fn rounded(raw json2.Any) !big.Integer {
    row := raw.as_map()
    if 'integer' in row { return big.integer_from_string(value(row, 'integer').str())! }
    x := value(row, 'float').f64()
	if math.is_nan(x) { return FontError{'ValueError', 'cannot convert float NaN to integer'} }
	if math.is_inf(x, 0) { return FontError{'OverflowError', 'cannot convert float infinity to integer'} }
    result := math.round_to_even(x)
    if result == 0 { return big.zero_int }
    bits := math.f64_bits(result)
    exponent := int((bits >> 52) & 0x7ff) - 1023
    mantissa := (bits & u64(0x000fffffffffffff)) | (u64(1) << 52)
    integer := big.integer_from_u64(mantissa)
    rounded_integer := if exponent >= 52 { integer.left_shift(u32(exponent - 52)) } else { integer.right_shift(u32(52 - exponent)) }
    return if bits >> 63 == 1 { big.zero_int - rounded_integer } else { rounded_integer }
}
fn rasterise(id int, cp int) !Glyph {
	if cp < 0 || cp > 0x10ffff { return FontError{'ValueError', 'chr() arg not in range(0x110000)'} }
    arguments := {'font': json2.Any(id), 'code_point': json2.Any(cp)}
    box_value := callback('bbox', arguments)!
    advance := rounded(callback('length', arguments)!)!
    row := callback('mask', arguments)!.as_map()
    mask_id := number(row, 'mask')
    defer { callback('mask_release', {'mask': json2.Any(mask_id)}) or {} }
	width := number(row, 'width'); height := number(row, 'height')
	if width == 0 || height == 0 { return Glyph{advance: advance} }
    if box_value is json2.Null { return FontError{'TypeError', "'NoneType' object is not subscriptable"} }
    box := box_value.as_array()
    if box.len < 2 { return FontError{'IndexError', 'tuple index out of range'} }
    return Glyph{width, height, int(box[0].i64()), int(box[1].i64()), advance, callback('pixels', {'mask': json2.Any(mask_id)})!.str()}
}
fn glyph_value(g Glyph) json2.Any { return json2.Any([json2.Any(g.width), json2.Any(g.height), json2.Any(g.bx), json2.Any(g.by), json2.Any(g.advance.str()), json2.Any(g.pixels)]) }
fn (mut e Engine) missing_glyph(id int) !Glyph {
	if id !in e.missing {
		glyph := rasterise(id, 0xe000)!
		callback('pin', {'font': json2.Any(id), 'owner': json2.Any('missing')})!
		e.missing[id] = glyph
	}
	return e.missing[id]
}
fn (mut e Engine) has_glyph(id int, cp int) !bool {
	key := '${id}:${cp}'
	if key !in e.available {
		candidate := rasterise(id, cp)!
		available := candidate != e.missing_glyph(id)! && (candidate.width != 0 || candidate.height != 0)
		callback('pin', {'font': json2.Any(id), 'owner': json2.Any('has')})!
		e.available[key] = available
	}
	return e.available[key]
}
fn (mut e Engine) glyph_font(file string, size int, bold bool, cp int, japanese []int, needs_japanese bool) !int {
	if e.is_chinese(cp)! {
		return e.open_font(e.cjk_path(if bold { 'NotoSansCJKsc-Bold.otf' } else { 'NotoSansCJKsc-Regular.otf' })!, size)!
	}
	id := e.open_font(file, size)!
    coverage := if needs_japanese { e.japanese_runes()! } else { japanese }
	if cp in coverage && !e.has_glyph(id, cp)! { return e.open_japanese(bold, size)! }
	return id
}

fn (mut e Engine) supported_extras(faces []json2.Any, japanese []int, required []int) ![]int {
	mut candidates := map[int]bool{}
	for cp in integers(value(e.context, 'extra_runes')) { candidates[cp] = true }
	for cp in required { candidates[cp] = true }
	for cp in japanese { candidates[cp] = true }
	mut ordered := candidates.keys(); ordered.sort()
	mut kept := []int{}
	for cp in ordered {
		mut ok := true
		for raw in faces {
			face := raw.as_array()
			for scale in integers(value(e.context, 'scales')) {
				id := e.glyph_font(face[1].str(), int(face[2].i64()) * scale, face[3].bool(), cp, japanese, false)!
				if !e.has_glyph(id, cp)! { ok = false; break }
			}
			if !ok { break }
		}
		if ok { kept << cp } else if cp in required || cp in japanese {
			return fail('translation needs missing glyph U+${cp:04X} (${rune(cp)})')
		} else { emit('  dropped U+${cp:04X} (not in every face)')! }
	}
	return kept
}

pub fn (mut e Engine) dispatch(row map[string]json2.Any) !json2.Any {
	e.context = value(row, 'context').as_map()
	op := text(row, 'operation')
	args := value(row, 'arguments').as_map()
	return match op {
		'clear' { e.clear(text(args, 'name'))!; json2.Null{} }
		'catalog' { integer_value(catalog_runes(value(args, 'paths').as_array().map(hex.decode(it.str()) or { []u8{} }.bytestr()))!) }
		'translations' { integer_value(e.translation_runes()!) }
		'chinese' { integer_value(e.chinese_runes()!) }
		'japanese' { integer_value(e.japanese_runes()!) }
		'is_cjk' { json2.Any(cjk(number(args, 'code_point'))) }
		'is_chinese' { json2.Any(e.is_chinese(number(args, 'code_point'))!) }
		'cjk_path' { json2.Any(e.cjk_path(text(args, 'file'))!.bytes().hex()) }
		'japanese_path' { json2.Any(e.japanese_path(value(args, 'bold').bool()).bytes().hex()) }
		'open' { json2.Any(e.open_font(text(args, 'file'), number(args, 'size'))!) }
		'open_japanese' { json2.Any(e.open_japanese(value(args, 'bold').bool(), number(args, 'size'))!) }
		'raster' { glyph_value(rasterise(number(args, 'font'), number(args, 'code_point'))!) }
		'missing' { glyph_value(e.missing_glyph(number(args, 'font'))!) }
		'has' { json2.Any(e.has_glyph(number(args, 'font'), number(args, 'code_point'))!) }
		'glyph_font' { json2.Any(e.glyph_font(text(args, 'file'), number(args, 'size'), value(args, 'bold').bool(), number(args, 'code_point'), integers(value(args, 'japanese')), value(args, 'japanese') is json2.Null)!) }
		'supported' { integer_value(e.supported_extras(value(args, 'faces').as_array(), integers(value(args, 'japanese')), if value(args, 'required') is json2.Null { e.translation_runes()! } else { integers(value(args, 'required')) })!) }
		'face' { json2.Any(e.build_face(text(args, 'file'), number(args, 'size'), value(args, 'bold').bool(), number(args, 'scale'), integers(value(args, 'extras')), integers(value(args, 'japanese')))!) }
        'wrap' {
            string_value := hex.decode(text(args, 'text_hex'))!.bytestr()
            width := big.integer_from_string(text(args, 'width_decimal'))!
            if width.signum == 0 { return FontError{'ValueError', 'range() arg 3 must not be zero'} }
            count := text_offsets(string_value).len
            limited := if width.signum < 0 { -1 } else if width > big.integer_from_int(count) { count } else { width.int() }
            json2.Any(wrap(string_value, limited)!.map(json2.Any(it.bytes().hex())))
        }
		'generate' { e.generate(args)! }
		'update_japanese' { e.update_japanese(integers(value(args, 'runes')), text(args, 'source'))!; json2.Null{} }
		else { return FontError{'ValueError', 'Unknown font operation'} }
	}
}

fn (mut e Engine) clear(name string) ! {
	match name {
		'chinese_runes' { e.chinese_ready = false; e.chinese = []int{} }
		'japanese_runes' { e.japanese_ready = false; e.japanese = []int{} }
		'cjk_font_path' { e.cjk_paths.clear() }
		'missing_glyph' { callback('release', {'fonts': integer_value(e.missing.keys()), 'owner': json2.Any('missing')})!; e.missing.clear() }
		'has_glyph' {
			mut ids := map[int]bool{}
			for key in e.available.keys() { ids[key.all_before(':').int()] = true }
			callback('release', {'fonts': integer_value(ids.keys()), 'owner': json2.Any('has')})!
			e.available.clear()
		}
		'open_font', 'open_japanese_font' {
			prefix := if name == 'open_font' { 'primary:' } else { 'japanese:' }
			mut ids := map[int]bool{}
			for key in e.fonts.keys() { if key.starts_with(prefix) { ids[e.fonts[key]] = true; e.fonts.delete(key) } }
			callback('release', {'fonts': integer_value(ids.keys()), 'owner': json2.Any(prefix.trim_right(':'))})!
		}
		else {}
	}
}
