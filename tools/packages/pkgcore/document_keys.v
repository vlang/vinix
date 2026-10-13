// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

struct DocumentKeyFrame {
mut:
	kind    u8
	context string // borrowed from the enclosing object's owned key
	pending string // borrowed from keys
	keys    []string
}

fn close_document_keys(frame DocumentKeyFrame) {
	unsafe {
		for key in frame.keys { key.free() }
		(&array(&frame.keys)).free()
	}
}

// Run after typed JSON decoding. The decoder validates syntax/types but drops
// unknown fields and overwrites duplicate keys. Keep object/array contexts so
// sibling records and nested objects have independent key sets. Decode escaped
// key spelling before comparison; never reinterpret already validated values.
fn document_keys(text string, allowed fn (string, string) bool) ! {
	mut stack := []DocumentKeyFrame{cap: 8}
	unsafe { stack.flags |= .noslices }
	defer {
		for frame in stack { close_document_keys(frame) }
		unsafe { stack.free() }
	}
	mut i := 0
	for i < text.len {
		byte := text[i]
		if byte in [u8(`{`), `[`] {
			if stack.len >= 16 { return error('administration document nesting exceeds its schema') }
			context := if stack.len == 0 { '' } else if stack.last().kind == `[` {
				stack.last().context
			} else { stack.last().pending }
			mut keys := []string{cap: 16}
			unsafe { keys.flags |= .noslices }
			// Raw push transfers the keys buffer; a typed struct push clones it.
			frame := DocumentKeyFrame{ kind: byte, context: context, keys: keys }
			pointer := unsafe { &frame }
			unsafe { stack.push_many(pointer, 1) }
		} else if byte in [u8(`}`), `]`] {
			if stack.len == 0 { return error('invalid administration document structure') }
			close_document_keys(stack.last())
			stack.delete_last()
		} else if byte == `"` {
			start := i
			i++
			for i < text.len && text[i] != `"` {
				if text[i] == `\\` { i++ }
				i++
			}
			if i >= text.len { return error('unterminated administration document string') }
			end := i + 1
			mut next := end
			for next < text.len && text[next] in [u8(` `), `\t`, `\r`, `\n`] { next++ }
			if next < text.len && text[next] == `:` {
				key := json2.decode[string](unsafe { tos(text.str + start, end - start) })!
				if stack.len == 0 || stack.last().kind != `{`
					|| !allowed(stack.last().context, key) {
					message := 'unknown administration document field: ' + key
					unsafe { key.free() }
					return error(message)
				}
				at := stack.len - 1
				if key in stack[at].keys {
					message := 'duplicate administration document field: ' + key
					unsafe { key.free() }
					return error(message)
				}
				stack[at].keys << key
				stack[at].pending = key
			}
		}
		i++
	}
	if stack.len != 0 { return error('incomplete administration document structure') }
}
