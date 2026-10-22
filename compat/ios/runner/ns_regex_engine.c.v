// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct NSRegexFailure { message string }
fn (failure &NSRegexFailure) msg() string { return failure.message }
fn (_ &NSRegexFailure) code() int { return 1 }
// Failures borrow immutable global records, avoiding error-interface boxes under -gc none.
__global ns_regex_failures = [
	NSRegexFailure{message: 'limit: regular expression has too many nodes'}
	NSRegexFailure{message: 'limit: regular expression nesting exceeds 64'}
	NSRegexFailure{message: 'invalid: repetition of an absolute anchor'}
	NSRegexFailure{message: 'invalid: unclosed repetition bound'}
	NSRegexFailure{message: 'invalid: repetition maximum is smaller than minimum'}
	NSRegexFailure{message: 'unsupported: possessive repetition'}
	NSRegexFailure{message: 'limit: repetition bound exceeds 1024'}
	NSRegexFailure{message: 'invalid: missing repetition bound'}
	NSRegexFailure{message: 'unsupported: isolated surrogate pattern scalar'}
	NSRegexFailure{message: 'unsupported: Unicode with ASCII case or character classes'}
	NSRegexFailure{message: 'invalid: incomplete group extension'}
	NSRegexFailure{message: 'unsupported: regular expression group extension'}
	NSRegexFailure{message: 'limit: regular expression has more than 32 captures'}
	NSRegexFailure{message: 'invalid: unclosed capture group'}
	NSRegexFailure{message: 'invalid: repetition has no preceding expression'}
	NSRegexFailure{message: 'invalid: malformed hexadecimal escape'}
	NSRegexFailure{message: 'invalid: incomplete hexadecimal escape'}
	NSRegexFailure{message: 'invalid: unclosed hexadecimal escape'}
	NSRegexFailure{message: 'invalid: Unicode escape is out of range'}
	NSRegexFailure{message: 'invalid: trailing backslash'}
	NSRegexFailure{message: 'unsupported: ambiguous multi-digit back reference'}
	NSRegexFailure{message: 'unsupported: Unicode word boundary'}
	NSRegexFailure{message: 'unsupported: octal escape'}
	NSRegexFailure{message: 'invalid: incomplete octal escape'}
	NSRegexFailure{message: 'invalid: anchor escape inside character class'}
	NSRegexFailure{message: 'unsupported: regular expression escape'}
	NSRegexFailure{message: 'invalid: unknown alphabetic escape'}
	NSRegexFailure{message: 'invalid: unclosed character class'}
	NSRegexFailure{message: 'unsupported: nested character class'}
	NSRegexFailure{message: 'limit: character class storage exceeds bound'}
	NSRegexFailure{message: 'unsupported: character class set operation'}
	NSRegexFailure{message: 'unsupported: character class range with set endpoint'}
	NSRegexFailure{message: 'unsupported: character class subtraction'}
	NSRegexFailure{message: 'invalid: character class range endpoint is a set'}
	NSRegexFailure{message: 'invalid: reversed character class range'}
	NSRegexFailure{message: 'invalid: empty character class'}
	NSRegexFailure{message: 'limit: compiled regular expression exceeds bound'}
	NSRegexFailure{message: 'unsupported: regular expression options'}
	NSRegexFailure{message: 'invalid: empty regular expression'}
	NSRegexFailure{message: 'limit: regular expression pattern exceeds 4096 bytes'}
	NSRegexFailure{message: 'invalid: malformed UTF8 regular expression'}
	NSRegexFailure{message: 'invalid: unmatched closing group'}
	NSRegexFailure{message: 'unsupported: Unicode pattern with ASCII case or character classes'}
	NSRegexFailure{message: 'unsupported: Unicode escape with ASCII case or character classes'}
	NSRegexFailure{message: 'invalid: back reference exceeds capture count'}
	NSRegexFailure{message: 'limit: regular expression matching step budget exhausted'}
	NSRegexFailure{message: 'limit: regular expression subject exceeds 1048576 bytes'}
	NSRegexFailure{message: 'unsupported: malformed UTF8 regular expression subject'}
	NSRegexFailure{message: 'unsupported: Unicode subject with ASCII case or character classes'}
	NSRegexFailure{message: 'invalid: regular expression range is out of bounds'}
	NSRegexFailure{message: 'unsupported: regular expression range splits a surrogate pair'}
	NSRegexFailure{message: 'limit: regular expression backtracking storage exhausted'}
]!
fn ns_regex_failure(message string) IError {
	for index in 0 .. ns_regex_failures.len {
		if ns_regex_failures[index].message == message { return unsafe { &ns_regex_failures[index] } }
	}
	panic('iOS: unregistered regular expression failure')
}

struct NSRegexSpan {
	location u64
	length u64
}

struct NSRegexMatch {
	found bool
	steps u64
	ranges []NSRegexSpan
}

enum NSRegexOp { accept character any_character character_class split jump save progress start end absolute_start absolute_end final_end back_reference }
enum NSRegexNodeKind { sequence alternate character any_character character_class group repeat start end absolute_start absolute_end final_end back_reference }

struct NSRegexScalarRange { first rune last rune }

struct NSRegexInstruction {
mut:
	op NSRegexOp
	x int
	y int
	value rune
	first int
	count int
	negative bool
}

struct NSRegexProgram {
	groups int
	options u64
	ascii_only bool
	progress_count int
mut:
	code []NSRegexInstruction
	classes []NSRegexScalarRange
}

struct NSRegexNode {
mut:
	kind NSRegexNodeKind
	left int = -1
	next int = -1
	value rune
	first int
	count int
	negative bool
	minimum int
	maximum int
	lazy bool
}

struct NSRegexParser {
mut:
	source []rune
	position int
	depth int
	groups int
	options u64
	ascii_only bool
	nodes []NSRegexNode
	classes []NSRegexScalarRange
}

struct NSRegexCompiler {
mut:
	code []NSRegexInstruction
	progress_count int
}

fn ns_regex_program_free(mut program NSRegexProgram) {
	unsafe { program.code.free(); program.classes.free() }
}

fn ns_regex_match_free(mut result NSRegexMatch) {
	unsafe { result.ranges.free() }
}

fn (mut parser NSRegexParser) add(node NSRegexNode) !int {
	if parser.nodes.len >= 4096 { return ns_regex_failure('limit: regular expression has too many nodes') }
	parser.nodes << node
	return parser.nodes.len - 1
}

fn ns_regex_line_terminator(value rune, unix bool) bool {
	return value == `\n` || (!unix && value in [`\r`, rune(0x85), rune(0x2028), rune(0x2029)])
}

fn (mut parser NSRegexParser) skip_comments() {
	if parser.options & 2 == 0 { return }
	for parser.position < parser.source.len {
		value := parser.source[parser.position]
		// ICU comments mode uses Pattern_White_Space, including LRM/RLM but not NBSP.
		if (value >= rune(9) && value <= rune(13)) || value in [` `, rune(0x85), rune(0x200e), rune(0x200f), rune(0x2028), rune(0x2029)] { parser.position++; continue }
		if value != `#` { break }
		for parser.position < parser.source.len && !ns_regex_line_terminator(parser.source[parser.position], false) { parser.position++ }
	}
}

fn (mut parser NSRegexParser) expression() !int {
	parser.depth++
	defer { parser.depth-- }
	if parser.depth > 64 { return ns_regex_failure('limit: regular expression nesting exceeds 64') }
	first := parser.sequence()!
	mut last := first
	mut alternatives := 1
	parser.skip_comments()
	for parser.position < parser.source.len && parser.source[parser.position] == `|` {
		parser.position++
		next := parser.sequence()!
		parser.nodes[last].next = next
		last = next
		alternatives++
		parser.skip_comments()
	}
	if alternatives == 1 { return first }
	return parser.add(NSRegexNode{kind: .alternate, left: first})
}

fn (mut parser NSRegexParser) sequence() !int {
	mut first := -1
	mut last := -1
	for {
		parser.skip_comments()
		if parser.position == parser.source.len || parser.source[parser.position] in [`|`, `)`] { break }
		mut atom := parser.atom()!
		parser.skip_comments()
		if parser.position < parser.source.len && parser.source[parser.position] in [`*`, `+`, `?`, `{`] {
			if parser.nodes[atom].kind in [.absolute_start, .absolute_end, .final_end] { return ns_regex_failure('invalid: repetition of an absolute anchor') }
			value := parser.source[parser.position]
			parser.position++
			mut minimum := 0
			mut maximum := -1
			match value {
				`+` { minimum = 1 }
				`?` { maximum = 1 }
				`{` {
					minimum = parser.decimal()!
					maximum = minimum
					if parser.position < parser.source.len && parser.source[parser.position] == `,` {
						parser.position++
						maximum = if parser.position < parser.source.len && parser.source[parser.position] == `}` { -1 } else { parser.decimal()! }
					}
					if parser.position >= parser.source.len || parser.source[parser.position] != `}` { return ns_regex_failure('invalid: unclosed repetition bound') }
					parser.position++
					if maximum != -1 && maximum < minimum { return ns_regex_failure('invalid: repetition maximum is smaller than minimum') }
				}
				else {}
			}
			parser.skip_comments()
			mut lazy := false
			if parser.position < parser.source.len && parser.source[parser.position] == `?` { lazy = true; parser.position++ }
			else if parser.position < parser.source.len && parser.source[parser.position] == `+` { return ns_regex_failure('unsupported: possessive repetition') }
			atom = parser.add(NSRegexNode{kind: .repeat, left: atom, minimum: minimum, maximum: maximum, lazy: lazy})!
		}
		if first == -1 { first = atom } else { parser.nodes[last].next = atom }
		last = atom
	}
	return parser.add(NSRegexNode{kind: .sequence, left: first})
}

fn (mut parser NSRegexParser) decimal() !int {
	start := parser.position
	mut result := 0
	for parser.position < parser.source.len && parser.source[parser.position] >= `0` && parser.source[parser.position] <= `9` {
		result = result * 10 + int(parser.source[parser.position] - `0`)
		if result > 1024 { return ns_regex_failure('limit: repetition bound exceeds 1024') }
		parser.position++
	}
	if parser.position == start { return ns_regex_failure('invalid: missing repetition bound') }
	return result
}

fn (mut parser NSRegexParser) character(value rune) !int {
	if value < 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff) { return ns_regex_failure('unsupported: isolated surrogate pattern scalar') }
	if parser.ascii_only && value > 127 { return ns_regex_failure('unsupported: Unicode with ASCII case or character classes') }
	return parser.add(NSRegexNode{kind: .character, value: value})
}

fn (mut parser NSRegexParser) atom() !int {
	value := parser.source[parser.position]
	parser.position++
	match value {
		`(` {
			mut group := -1
			if parser.position < parser.source.len && parser.source[parser.position] == `?` {
				parser.position++
				if parser.position >= parser.source.len { return ns_regex_failure('invalid: incomplete group extension') }
				if parser.source[parser.position] != `:` { return ns_regex_failure('unsupported: regular expression group extension') }
				parser.position++
			} else {
				parser.groups++
				if parser.groups > 32 { return ns_regex_failure('limit: regular expression has more than 32 captures') }
				group = parser.groups
			}
			child := parser.expression()!
			if parser.position >= parser.source.len || parser.source[parser.position] != `)` { return ns_regex_failure('invalid: unclosed capture group') }
			parser.position++
			return parser.add(NSRegexNode{kind: .group, left: child, first: group})
		}
		`[` { return parser.character_class() }
		`\\` { return parser.escape(false) }
		`.` { return parser.add(NSRegexNode{kind: .any_character}) }
		`^` { return parser.add(NSRegexNode{kind: .start}) }
		`$` { return parser.add(NSRegexNode{kind: .end}) }
		`*`, `+`, `?`, `{`, `}` { return ns_regex_failure('invalid: repetition has no preceding expression') }
		else { return parser.character(value) }
	}
}

fn (mut parser NSRegexParser) hexadecimal(digits int, braced bool) !rune {
	mut count := 0
	mut value := u32(0)
	for parser.position < parser.source.len && count < digits {
		item := parser.source[parser.position]
		if braced && item == `}` { break }
		mut digit := -1
		if item >= `0` && item <= `9` { digit = int(item - `0`) }
		else if item >= `a` && item <= `f` { digit = int(item - `a`) + 10 }
		else if item >= `A` && item <= `F` { digit = int(item - `A`) + 10 }
		if digit < 0 { return ns_regex_failure('invalid: malformed hexadecimal escape') }
		value = (value << 4) | u32(digit)
		parser.position++
		count++
	}
	if count == 0 || (!braced && count != digits) { return ns_regex_failure('invalid: incomplete hexadecimal escape') }
	if braced {
		if parser.position >= parser.source.len || parser.source[parser.position] != `}` { return ns_regex_failure('invalid: unclosed hexadecimal escape') }
		parser.position++
	}
	if value > 0x10ffff { return ns_regex_failure('invalid: Unicode escape is out of range') }
	return rune(value)
}

fn (mut parser NSRegexParser) shorthand(value rune) !int {
	parser.ascii_only = true
	first := parser.classes.len
	mut run := -1
	for candidate in 0 .. 128 {
		word := (candidate >= int(`a`) && candidate <= int(`z`)) || (candidate >= int(`A`) && candidate <= int(`Z`)) || (candidate >= int(`0`) && candidate <= int(`9`)) || candidate == int(`_`)
		digit := candidate >= int(`0`) && candidate <= int(`9`)
		space := candidate in [9, 10, 11, 12, 13, 32]
		selected := match value { `w` { word } `W` { !word } `d` { digit } `D` { !digit } `s` { space } else { !space } }
		if selected && run == -1 { run = candidate }
		if !selected && run != -1 { parser.class_range(rune(run), rune(candidate - 1))!; run = -1 }
	}
	if run != -1 { parser.class_range(rune(run), rune(127))! }
	return parser.add(NSRegexNode{kind: .character_class, first: first, count: parser.classes.len - first})
}

fn (mut parser NSRegexParser) escape(in_class bool) !int {
	if parser.position >= parser.source.len { return ns_regex_failure('invalid: trailing backslash') }
	value := parser.source[parser.position]
	parser.position++
	if value in [`w`, `W`, `d`, `D`, `s`, `S`] { return parser.shorthand(value) }
	if in_class && value >= `1` && value <= `9` { return parser.character(value) }
	if !in_class && value >= `1` && value <= `9` {
		group := int(value - `0`)
		if parser.position < parser.source.len && parser.source[parser.position] >= `0` && parser.source[parser.position] <= `9` {
			return ns_regex_failure('unsupported: ambiguous multi-digit back reference')
		}
		return parser.add(NSRegexNode{kind: .back_reference, first: group})
	}
	match value {
		`n` { return parser.character(`\n`) }
		`r` { return parser.character(`\r`) }
		`t` { return parser.character(`\t`) }
		`f` { return parser.character(`\f`) }
		`a` { return parser.character(rune(7)) }
		`e` { return parser.character(rune(27)) }
		`b` { if in_class { return parser.character(rune(8)) }; return ns_regex_failure('unsupported: Unicode word boundary') }
		`0` {
			if parser.position < parser.source.len && parser.source[parser.position] >= `0` && parser.source[parser.position] <= `9` { return ns_regex_failure('unsupported: octal escape') }
			return ns_regex_failure('invalid: incomplete octal escape')
		}
		`x` {
			braced := parser.position < parser.source.len && parser.source[parser.position] == `{`
			if braced { parser.position++ }
			return parser.character(parser.hexadecimal(if braced { 6 } else { 2 }, braced)!)
		}
		`u` { return parser.character(parser.hexadecimal(4, false)!) }
		`U` { return parser.character(parser.hexadecimal(8, false)!) }
		`A`, `z`, `Z` {
			if in_class { return ns_regex_failure('invalid: anchor escape inside character class') }
			kind := if value == `A` { NSRegexNodeKind.absolute_start } else if value == `z` { NSRegexNodeKind.absolute_end } else { NSRegexNodeKind.final_end }
			return parser.add(NSRegexNode{kind: kind})
		}
		`p`, `P`, `h`, `H`, `v`, `V`, `B`, `G`, `R`, `X`, `Q`, `E`, `k`, `c`, `N` { return ns_regex_failure('unsupported: regular expression escape') }
		else {
			if (value >= `a` && value <= `z`) || (value >= `A` && value <= `Z`) || (value >= `0` && value <= `9`) { return ns_regex_failure('invalid: unknown alphabetic escape') }
			return parser.character(value)
		}
	}
}

fn (mut parser NSRegexParser) class_atom() !int {
	if parser.position >= parser.source.len { return ns_regex_failure('invalid: unclosed character class') }
	value := parser.source[parser.position]
	parser.position++
	if value == `\\` { return parser.escape(true) }
	if value == `[` { return ns_regex_failure('unsupported: nested character class') }
	return parser.character(value)
}

fn (mut parser NSRegexParser) class_range(first rune, last rune) ! {
	if parser.classes.len >= 16384 { return ns_regex_failure('limit: character class storage exceeds bound') }
	parser.classes << NSRegexScalarRange{first, last}
}

fn (mut parser NSRegexParser) character_class() !int {
	mut negative := false
	parser.skip_comments()
	if parser.position < parser.source.len && parser.source[parser.position] == `^` { negative = true; parser.position++ }
	first := parser.classes.len
	mut items := 0
	for {
		parser.skip_comments()
		if parser.position >= parser.source.len || (items > 0 && parser.source[parser.position] == `]`) { break }
		if parser.position + 1 < parser.source.len && ((parser.source[parser.position] == `&` && parser.source[parser.position + 1] == `&`) || (parser.source[parser.position] == `-` && parser.source[parser.position + 1] == `-`)) { return ns_regex_failure('unsupported: character class set operation') }
		left_index := parser.class_atom()!
		left := parser.nodes[left_index]
		parser.skip_comments()
		if left.kind == .character_class {
			if parser.position + 1 < parser.source.len && parser.source[parser.position] == `-` && parser.source[parser.position + 1] != `]` { return ns_regex_failure('unsupported: character class range with set endpoint') }
			items++
			continue
		}
		if parser.position + 1 < parser.source.len && parser.source[parser.position] == `-` && parser.source[parser.position + 1] != `]` {
			if parser.source[parser.position + 1] == `-` { return ns_regex_failure('unsupported: character class subtraction') }
			parser.position++
			parser.skip_comments()
			right := parser.nodes[parser.class_atom()!]
			if right.kind != .character { return ns_regex_failure('invalid: character class range endpoint is a set') }
			if right.value < left.value { return ns_regex_failure('invalid: reversed character class range') }
			parser.class_range(left.value, right.value)!
		} else { parser.class_range(left.value, left.value)! }
		items++
	}
	if parser.position >= parser.source.len { return ns_regex_failure('invalid: unclosed character class') }
	parser.position++
	if items == 0 { return ns_regex_failure('invalid: empty character class') }
	return parser.add(NSRegexNode{kind: .character_class, first: first, count: parser.classes.len - first, negative: negative})
}

fn (mut compiler NSRegexCompiler) emit(instruction NSRegexInstruction) !int {
	if compiler.code.len >= 16384 { return ns_regex_failure('limit: compiled regular expression exceeds bound') }
	compiler.code << instruction
	return compiler.code.len - 1
}

fn (mut compiler NSRegexCompiler) node(nodes []NSRegexNode, index int) ! {
	node := nodes[index]
	match node.kind {
		.sequence {
			mut child := node.left
			for child != -1 { compiler.node(nodes, child)!; child = nodes[child].next }
		}
		.alternate {
			mut branches := []int{}
			branches.flags |= .noslices
			defer { unsafe { branches.free() } }
			mut child := node.left
			for child != -1 {
				next := nodes[child].next
				if next == -1 { compiler.node(nodes, child)!; break }
				split := compiler.emit(NSRegexInstruction{op: .split, x: compiler.code.len + 1})!
				compiler.node(nodes, child)!
				branches << compiler.emit(NSRegexInstruction{op: .jump})!
				compiler.code[split].y = compiler.code.len
				child = next
			}
			for branch in branches { compiler.code[branch].x = compiler.code.len }
		}
		.group {
			if node.first >= 0 { compiler.emit(NSRegexInstruction{op: .save, first: node.first * 2})! }
			compiler.node(nodes, node.left)!
			if node.first >= 0 { compiler.emit(NSRegexInstruction{op: .save, first: node.first * 2 + 1})! }
		}
		.repeat {
			for _ in 0 .. node.minimum { compiler.node(nodes, node.left)! }
			if node.maximum == -1 {
				split := compiler.emit(NSRegexInstruction{op: .split})!
				progress := compiler.progress_count
				compiler.progress_count++
				compiler.emit(NSRegexInstruction{op: .progress, first: progress})!
				compiler.node(nodes, node.left)!
				compiler.emit(NSRegexInstruction{op: .jump, x: split})!
				compiler.code[split].x = if node.lazy { compiler.code.len } else { split + 1 }
				compiler.code[split].y = if node.lazy { split + 1 } else { compiler.code.len }
			} else {
				mut splits := []int{}
				splits.flags |= .noslices
				defer { unsafe { splits.free() } }
				for _ in node.minimum .. node.maximum {
					split := compiler.emit(NSRegexInstruction{op: .split})!
					if node.lazy { compiler.code[split].y = split + 1 } else { compiler.code[split].x = split + 1 }
					splits << split
					compiler.node(nodes, node.left)!
				}
				for split in splits { if node.lazy { compiler.code[split].x = compiler.code.len } else { compiler.code[split].y = compiler.code.len } }
			}
		}
		else {
			op := match node.kind { .character { NSRegexOp.character } .any_character { NSRegexOp.any_character } .character_class { NSRegexOp.character_class } .start { NSRegexOp.start } .end { NSRegexOp.end } .absolute_start { NSRegexOp.absolute_start } .absolute_end { NSRegexOp.absolute_end } .final_end { NSRegexOp.final_end } else { NSRegexOp.back_reference } }
			compiler.emit(NSRegexInstruction{op: op, value: node.value, first: node.first, count: node.count, negative: node.negative})!
		}
	}
}

fn ns_regex_compile(pattern string, options u64) !NSRegexProgram {
	if options & ~u64(63) != 0 { return ns_regex_failure('unsupported: regular expression options') }
	if pattern.len == 0 { return ns_regex_failure('invalid: empty regular expression') }
	if pattern.len > 4096 { return ns_regex_failure('limit: regular expression pattern exceeds 4096 bytes') }
	if !utf8.validate_str(pattern) { return ns_regex_failure('invalid: malformed UTF8 regular expression') }
	mut parser := &NSRegexParser{source: pattern.runes(), options: options, ascii_only: options & 1 != 0}
	mut compiler := NSRegexCompiler{}
	parser.nodes.flags |= .noslices
	parser.classes.flags |= .noslices
	compiler.code.flags |= .noslices
	mut transferred := false
	defer {
		unsafe { parser.source.free(); parser.nodes.free() }
		if !transferred { unsafe { parser.classes.free(); compiler.code.free() } }
		unsafe { free(parser) }
	}
	mut root := -1
	if options & 4 != 0 {
		mut first := -1
		mut last := -1
		for scalar in parser.source {
			index := parser.character(scalar)!
			if first == -1 { first = index } else { parser.nodes[last].next = index }
			last = index
		}
		root = parser.add(NSRegexNode{kind: .sequence, left: first})!
	} else {
		root = parser.expression()!
		if parser.position != parser.source.len { return ns_regex_failure('invalid: unmatched closing group') }
	}
	if parser.ascii_only {
		for scalar in parser.source { if scalar > 127 { return ns_regex_failure('unsupported: Unicode pattern with ASCII case or character classes') } }
		for node in parser.nodes { if node.kind == .character && node.value > 127 { return ns_regex_failure('unsupported: Unicode escape with ASCII case or character classes') } }
	}
	for node in parser.nodes {
		if node.kind == .back_reference && node.first > parser.groups { return ns_regex_failure('invalid: back reference exceeds capture count') }
	}
	compiler.emit(NSRegexInstruction{op: .save, first: 0})!
	compiler.node(parser.nodes, root)!
	compiler.emit(NSRegexInstruction{op: .save, first: 1})!
	compiler.emit(NSRegexInstruction{op: .accept})!
	transferred = true
	return NSRegexProgram{groups: parser.groups, options: options, ascii_only: parser.ascii_only, progress_count: compiler.progress_count, code: compiler.code, classes: parser.classes}
}

fn ns_regex_fold(value rune) rune { return if value >= `A` && value <= `Z` { value + 32 } else { value } }

fn ns_regex_work(steps u64, amount int) !u64 {
	result := steps + u64(amount)
	if result > 1000000 { return ns_regex_failure('limit: regular expression matching step budget exhausted') }
	return result
}

fn ns_regex_final_boundary(source []rune, start int, end int, position int, unix bool) bool {
	if position == end { return true }
	if end == start { return false }
	if !unix && source[end - 1] == `\n` && end - start >= 2 && source[end - 2] == `\r` { return position == end - 2 }
	return position == end - 1 && ns_regex_line_terminator(source[end - 1], unix)
}

// Range and result offsets are UTF16 code units. A range may not split a scalar.
// Each call owns its workspace; the compiled program is immutable during matching.
fn ns_regex_search(program &NSRegexProgram, text string, range_location u64, range_length u64, search_location u64, anchored bool) !NSRegexMatch {
	if text.len > 1048576 { return ns_regex_failure('limit: regular expression subject exceeds 1048576 bytes') }
	if !utf8.validate_str(text) { return ns_regex_failure('unsupported: malformed UTF8 regular expression subject') }
	if program.ascii_only { for value in text { if value > 127 { return ns_regex_failure('unsupported: Unicode subject with ASCII case or character classes') } } }
	source := text.runes()
	mut offsets := []u64{len: source.len + 1}
	mut captures := []int{len: (program.groups + 1) * 2, init: -1}
	mut progress := []int{len: program.progress_count, init: -1}
	mut stack := []int{}
	stack.flags |= .noslices
	defer { unsafe { source.free(); offsets.free(); captures.free(); progress.free(); stack.free() } }
	for index, value in source { offsets[index + 1] = offsets[index] + if value > 0xffff { u64(2) } else { u64(1) } }
	length := offsets[source.len]
	if range_location > length || range_length > length - range_location || search_location < range_location || search_location > range_location + range_length { return ns_regex_failure('invalid: regular expression range is out of bounds') }
	mut start := -1
	mut end := -1
	mut search := -1
	for index, offset in offsets {
		if offset == range_location { start = index }
		if offset == range_location + range_length { end = index }
		if offset == search_location { search = index }
	}
	if start == -1 || end == -1 || search == -1 { return ns_regex_failure('unsupported: regular expression range splits a surrogate pair') }
	case_insensitive := program.options & 1 != 0
	unix := program.options & 32 != 0
	multiline := program.options & 16 != 0
	dot_all := program.options & 8 != 0
	frame_size := captures.len + progress.len + 2
	// Charge decoding, validation and range-index scans to the caller's aggregate budget.
	mut steps := ns_regex_work(0, text.len * 3 + source.len * 2)!
	for candidate := search; candidate <= end; candidate++ {
		if anchored && candidate != search { break }
		steps = ns_regex_work(steps, captures.len + progress.len)!
		for index in 0 .. captures.len { captures[index] = -1 }
		for index in 0 .. progress.len { progress[index] = -1 }
		stack.clear()
		mut pc := 0
		mut position := candidate
		for {
			steps = ns_regex_work(steps, 1)!
			instruction := program.code[pc]
			mut matched := true
			match instruction.op {
				.accept {
					mut ranges := []NSRegexSpan{cap: program.groups + 1}
					for group in 0 .. program.groups + 1 {
						left := captures[group * 2]
						right := captures[group * 2 + 1]
						ranges << if left < 0 || right < left { NSRegexSpan{location: u64(0x7fffffffffffffff)} } else { NSRegexSpan{location: offsets[left], length: offsets[right] - offsets[left]} }
					}
					return NSRegexMatch{found: true, steps: steps, ranges: ranges}
				}
				.character {
					matched = position < end && if case_insensitive { ns_regex_fold(source[position]) == ns_regex_fold(instruction.value) } else { source[position] == instruction.value }
					if matched { position++; pc++ }
				}
				.any_character { matched = position < end && (dot_all || !ns_regex_line_terminator(source[position], unix)); if matched { position++; pc++ } }
				.character_class {
					matched = false
					if position < end {
						value := source[position]
						mut selected := false
						for index in instruction.first .. instruction.first + instruction.count {
							steps = ns_regex_work(steps, 1)!
							range := program.classes[index]
							if value >= range.first && value <= range.last { selected = true; break }
							if case_insensitive {
								lower := ns_regex_fold(value)
								upper := if lower >= `a` && lower <= `z` { lower - 32 } else { lower }
								if (lower >= range.first && lower <= range.last) || (upper >= range.first && upper <= range.last) { selected = true; break }
							}
						}
						matched = selected != instruction.negative
					}
					if matched { position++; pc++ }
				}
				.split {
					if stack.len + frame_size > 1048576 { return ns_regex_failure('limit: regular expression backtracking storage exhausted') }
					steps = ns_regex_work(steps, frame_size)!
					stack << captures
					stack << progress
					stack << position
					stack << instruction.y
					pc = instruction.x
				}
				.jump { pc = instruction.x }
				.save { captures[instruction.first] = position; pc++ }
				.progress { matched = progress[instruction.first] != position; if matched { progress[instruction.first] = position; pc++ } }
				.start, .absolute_start {
					matched = position == start
					if !matched && instruction.op == .start && multiline && position > start && (unix || position < end) && ns_regex_line_terminator(source[position - 1], unix) {
						matched = unix || source[position - 1] != `\r` || position == end || source[position] != `\n`
					}
					if matched { pc++ }
				}
				.end, .absolute_end, .final_end {
					matched = position == end
					if instruction.op != .absolute_end {
						if instruction.op == .end && multiline {
							if position < end && ns_regex_line_terminator(source[position], unix) { matched = unix || source[position] != `\n` || position == start || source[position - 1] != `\r` }
						} else { matched = ns_regex_final_boundary(source, start, end, position, if instruction.op == .final_end { false } else { unix }) }
						}
					if matched { pc++ }
				}
				.back_reference {
					left := captures[instruction.first * 2]
					right := captures[instruction.first * 2 + 1]
					matched = left >= 0 && right >= left && right - left <= end - position
					if matched {
						for index in 0 .. right - left {
							steps = ns_regex_work(steps, 1)!
							a := source[left + index]
							b := source[position + index]
							different := if case_insensitive { ns_regex_fold(a) != ns_regex_fold(b) } else { a != b }
							if different { matched = false; break }
						}
					}
					if matched { position += right - left; pc++ }
				}
			}
			if matched { continue }
			if stack.len == 0 { break }
			steps = ns_regex_work(steps, frame_size)!
			base := stack.len - frame_size
			for index in 0 .. captures.len { captures[index] = stack[base + index] }
			for index in 0 .. progress.len { progress[index] = stack[base + captures.len + index] }
			position = stack[base + frame_size - 2]
			pc = stack[base + frame_size - 1]
			stack.trim(base)
		}
	}
	return NSRegexMatch{steps: steps}
}
