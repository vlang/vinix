// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

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

// Pair with typed JSON decoding: this scan checks schema, not complete syntax.
// Generic decoding drops unknown fields and overwrites duplicate keys; bounded
// signed-index decoding follows this pass to preserve schema diagnostics.
// Keep object/array contexts so sibling records and nested objects have
// independent key sets. Decode escaped
// key spelling before comparison; never reinterpret already validated values.
fn document_keys(text string, allowed fn (string, string) bool) ! {
	document_keys_required(text, allowed, document_optional_fields)!
}

fn document_optional_fields(_ string, _ []string) ! {}

fn document_any_value(_ string, _ string, _ u8) bool { return true }

// Required-field checks use each object's decoded key set without decoding the
// complete document a second time. Callers also require strict typed syntax checks.
fn document_keys_required(text string, allowed fn (string, string) bool,
	required fn (string, []string) !) ! {
	document_keys_schema(text, allowed, required, document_any_value)!
}

fn document_keys_schema(text string, allowed fn (string, string) bool,
	required fn (string, []string) !, value_type fn (string, string, u8) bool) ! {
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
			if stack.last().kind == `{` { required(stack.last().context, stack.last().keys)! }
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
				key := pkgprotocol.decode_metadata_key(unsafe { tos(text.str + start, end - start) })!
				if stack.len == 0 || stack.last().kind != `{`
					|| !allowed(stack.last().context, key) {
					message := 'unknown administration document field: ' + key
					unsafe { key.free() }
					return error(message)
				}
				mut value := next + 1
				for value < text.len && text[value] in [u8(` `), `\t`, `\r`, `\n`] { value++ }
				if value == text.len || !value_type(stack.last().context, key, text[value]) {
					message := 'invalid metadata document field type: ' + key
					unsafe { key.free() }
					return error(message)
				}
				at := stack.len - 1
				if key in stack[at].keys {
					message := 'duplicate administration document field: ' + key
					unsafe { key.free() }
					return error(message)
				}
				// Transfer ownership: a typed string push clones the key and leaves
				// its original allocation live under manual memory management.
				pointer := unsafe { &key }
				unsafe { stack[at].keys.push_many(pointer, 1) }
				stack[at].pending = key
			}
		}
		i++
	}
	if stack.len != 0 { return error('incomplete administration document structure') }
}
