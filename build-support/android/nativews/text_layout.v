// SPDX-License-Identifier: GPL-2.0-or-later
// Text metrics use the same TrueType advances as the WS Canvas. Android text
// offsets are UTF-16 indices; native rendering keeps UTF-8 byte ranges separate.
@[translated]
module atlframework

struct WsTextLine {
	start usize
	end   usize
	first i32
	last  i32
	width f32
}

struct WsTextLayout {
mut:
	text     &char
	size     f32
	width    i32
	lines    &WsTextLine
	count    i32
	capacity i32
}

fn ws_glyph_advance(code i32, size f32) f32 {
	mut advance := i32(0)
	mut bearing := i32(0)
	C.stbtt_GetCodepointHMetrics(ws_font, code, &advance, &bearing)
	return f32(advance) * C.stbtt_ScaleForPixelHeight(ws_font, size)
}

fn ws_layout_line(layout &WsTextLayout, start usize, end usize, first i32, last i32, width f32) {
	unsafe {
		if layout.count == layout.capacity {
			capacity := if layout.capacity == 0 { i32(8) } else { layout.capacity * 2 }
			layout.lines = &WsTextLine(C.realloc(layout.lines, usize(capacity) * sizeof(WsTextLine)))
			layout.capacity = capacity
		}
		layout.lines[layout.count] = WsTextLine{start, end, first, last, width}
		layout.count++
	}
}

fn ws_layout_build(layout &WsTextLayout) {
	unsafe {
		layout.count = 0
		length := C.strlen(layout.text)
		mut pos := usize(0)
		mut start := usize(0)
		mut first := i32(0)
		mut index := i32(0)
		mut width := f32(0)
		mut break_end := usize(0)
		mut break_next := usize(0)
		mut break_index := i32(0)
		mut break_width := f32(0)
		for pos < length {
			begin := pos
			code := ws_codepoint(&u8(layout.text), length, &pos)
			if code == 10 {
				ws_layout_line(layout, start, begin, first, index + 1, width)
				index++
				first = index
				start = pos
				width = 0
				break_next = 0
				continue
			}
			advance := ws_glyph_advance(code, layout.size)
			if layout.width > 0 && width > 0 && width + advance > f32(layout.width) {
				if break_next > start {
					ws_layout_line(layout, start, break_end, first, break_index, break_width)
					pos = break_next
					start = pos
					index = break_index
					first = index
					width = 0
					break_next = 0
					continue
				}
				ws_layout_line(layout, start, begin, first, index, width)
				first = index
				start = begin
				width = 0
			}
			if code == 32 || code == 9 {
				break_end = begin
				break_next = pos
				break_index = index + 1
				break_width = width
			}
			width += advance
			index += if code > 0xffff { 2 } else { 1 }
		}
		ws_layout_line(layout, start, pos, first, index, width)
	}
}

fn ws_text_layout(text &char, size f32, width i32) i64 {
	unsafe {
		layout := &WsTextLayout(C.calloc(1, sizeof(WsTextLayout)))
		layout.text = C.strdup(text)
		layout.size = size
		layout.width = width
		ws_layout_build(layout)
		return i64(layout)
	}
}

fn ws_layout_new(e voidptr, text voidptr, paint i64, width i32) i64 {
	chars := ws_utf(e, text)
	size := unsafe { (&WsPaint(paint)).size }
	result := ws_text_layout(chars, size, width)
	ws_release(e, text, chars)
	return result
}

fn ws_layout_free(pointer i64) {
	unsafe {
		if pointer == 0 { return }
		layout := &WsTextLayout(pointer)
		C.free(layout.text)
		C.free(layout.lines)
		C.free(layout)
	}
}

fn ws_layout_index(pointer i64, requested i32) i32 {
	unsafe {
		layout := &WsTextLayout(pointer)
		return if requested < 0 {
			0
		} else if requested >= layout.count {
			layout.count - 1
		} else {
			requested
		}
	}
}

fn ws_layout_line_for_offset(pointer i64, offset i32) i32 {
	unsafe {
		layout := &WsTextLayout(pointer)
		for i := i32(0); i < layout.count - 1; i++ {
			if offset < layout.lines[i + 1].first { return i }
		}
		return layout.count - 1
	}
}

fn ws_layout_horizontal(pointer i64, offset i32) f32 {
	unsafe {
		layout := &WsTextLayout(pointer)
		line := layout.lines[ws_layout_line_for_offset(pointer, offset)]
		mut pos := line.start
		mut index := line.first
		mut x := f32(0)
		for pos < line.end && index < offset {
			code := ws_codepoint(&u8(layout.text), line.end, &pos)
			x += ws_glyph_advance(code, layout.size)
			index += if code > 0xffff { 2 } else { 1 }
		}
		return x
	}
}

fn ws_layout_offset(pointer i64, requested i32, x f32) i32 {
	unsafe {
		layout := &WsTextLayout(pointer)
		line := layout.lines[ws_layout_index(pointer, requested)]
		mut pos := line.start
		mut index := line.first
		mut advance := f32(0)
		for pos < line.end {
			code := ws_codepoint(&u8(layout.text), line.end, &pos)
			width := ws_glyph_advance(code, layout.size)
			if advance + width / 2 > x { break }
			advance += width
			index += if code > 0xffff { 2 } else { 1 }
		}
		return index
	}
}

fn ws_layout_draw(pointer i64, color u32, x f32, y f32) {
	unsafe {
		layout := &WsTextLayout(pointer)
		for i := i32(0); i < layout.count; i++ {
			line := layout.lines[i]
			end := layout.text[line.end]
			layout.text[line.end] = 0
			ws_text(&layout.text[line.start], x, y + f32(i) * layout.size * 1.25, layout.size, color)
			layout.text[line.end] = end
		}
	}
}

fn ws_layout_desired_width(pointer i64) f32 {
	unsafe {
		layout := &WsTextLayout(pointer)
		mut width := f32(0)
		for i := i32(0); i < layout.count; i++ {
			if layout.lines[i].width > width { width = layout.lines[i].width }
		}
		return width
	}
}
