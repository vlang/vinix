// SPDX-License-Identifier: GPL-2.0-or-later
module main

// This source-only reader owns every node/attribute. Names borrow the immutable
// source buffer; callers must free the tree before that buffer. No external
// entities, DTDs, text content or compiled Interface Builder archives are read.
struct StoryboardNode {
mut:
	name string
	attributes map[string]string
	children []&StoryboardNode
}

fn storyboard_node_free(node &StoryboardNode) {
	for child in node.children { storyboard_node_free(child) }
	for _, value in node.attributes { unsafe { value.free() } }
	unsafe { node.attributes.free(); node.children.free(); free(node) }
}

struct StoryboardReader {
	text string
mut:
	position int
	remaining int = 4096
}

fn (r &StoryboardReader) at(token string) bool {
	return r.position <= r.text.len && r.borrow(r.position, r.text.len).starts_with(token)
}

fn (mut r StoryboardReader) whitespace() {
	for r.position < r.text.len && r.text[r.position] in [u8(9), 10, 13, 32]! { r.position++ }
}

fn (r &StoryboardReader) borrow(start int, end int) string {
	return unsafe { tos(r.text.str + start, end - start) }
}

fn (mut r StoryboardReader) name() !string {
	start := r.position
	for r.position < r.text.len {
		c := r.text[r.position]
		if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c in [u8(`_`), `:`, `-`, `.`]!
			|| (r.position > start && c >= `0` && c <= `9`)) { break }
		r.position++
	}
	if r.position == start { return error('storyboard XML name is missing') }
	return r.borrow(start, r.position)
}

fn (mut r StoryboardReader) skip(end string) ! {
	for r.position < r.text.len && !r.at(end) { r.position++ }
	if !r.at(end) { return error('unterminated storyboard XML declaration/comment') }
	r.position += end.len
}

fn storyboard_attribute(raw string) !string {
	mut bytes := []u8{cap: raw.len}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	mut i := 0
	for i < raw.len {
		if raw[i] != `&` { bytes << raw[i]; i++; continue }
		mut matched := false
		entities := ['&amp;', '&lt;', '&gt;', '&quot;', '&apos;']!
		values := [u8(`&`), `<`, `>`, `"`, `'`]!
		for index, entity in entities {
			if unsafe { tos(raw.str + i, raw.len - i) }.starts_with(entity) {
				bytes << values[index]; i += entity.len; matched = true; break
			}
		}
		if !matched { return error('unsupported storyboard XML entity') }
	}
	return bytes.bytestr()
}

fn (mut r StoryboardReader) node(depth int) !&StoryboardNode {
	if depth > 64 || r.remaining <= 0 { return error('storyboard XML tree exceeds limit') }
	r.remaining--
	if !r.at('<') { return error('storyboard XML element is missing') }
	r.position++
	name := r.name()!
	mut node := &StoryboardNode{name: name}
	node.children.flags |= .noslices
	mut complete := false
	defer { if !complete { storyboard_node_free(node) } }
	for {
		before := r.position
		r.whitespace()
		if r.at('/>') { r.position += 2; complete = true; return node }
		if r.at('>') { r.position++; break }
		if r.position == before || node.attributes.len >= 64 { return error('invalid storyboard XML attributes') }
		key := r.name()!
		if key in node.attributes { return error('duplicate storyboard XML attribute') }
		r.whitespace()
		if !r.at('=') { return error('storyboard XML attribute requires equals') }
		r.position++; r.whitespace()
		if r.position >= r.text.len || r.text[r.position] !in [u8(`'`), `"`]! { return error('storyboard XML attribute requires quotes') }
		quote := r.text[r.position]
		r.position++
		start := r.position
		for r.position < r.text.len && r.text[r.position] != quote {
			if r.text[r.position] == `<` || r.text[r.position] == 0 { return error('invalid storyboard XML attribute value') }
			r.position++
		}
		if r.position == r.text.len { return error('unterminated storyboard XML attribute') }
		node.attributes[key] = storyboard_attribute(r.borrow(start, r.position))!
		r.position++
	}
	for {
		r.whitespace()
		if r.at('</') {
			r.position += 2
			if r.name()! != name { return error('mismatched storyboard XML closing element') }
			r.whitespace()
			if !r.at('>') { return error('invalid storyboard XML closing element') }
			r.position++; complete = true; return node
		}
		if r.at('<!--') { r.position += 4; r.skip('-->')!; continue }
		if r.at('<!') || r.at('<?') { return error('unsupported storyboard XML declaration') }
		node.children << r.node(depth + 1)!
	}
	return error('unterminated storyboard XML element')
}

fn storyboard_parse(text string) !&StoryboardNode {
	if text.len == 0 || text.len > 1024 * 1024 { return error('storyboard resource exceeds size limit') }
	mut reader := StoryboardReader{text: text}
	reader.whitespace()
	if reader.at('<?xml ') { reader.position += 6; reader.skip('?>')!; reader.whitespace() }
	for reader.at('<!--') { reader.position += 4; reader.skip('-->')!; reader.whitespace() }
	root := reader.node(0)!
	mut complete := false
	defer { if !complete { storyboard_node_free(root) } }
	reader.whitespace()
	if reader.position != text.len || root.name != 'document' { return error('invalid storyboard XML document') }
	complete = true
	return root
}

fn storyboard_child(node &StoryboardNode, name string) ?&StoryboardNode {
	for child in node.children { if child.name == name { return child } }
	return none
}

fn storyboard_find(node &StoryboardNode, key string, value string, mut matches []&StoryboardNode) {
	if node.name == 'viewController' && node.attributes[key] == value { matches << node }
	for child in node.children { storyboard_find(child, key, value, mut matches) }
}
