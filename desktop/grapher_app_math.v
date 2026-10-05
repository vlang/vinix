// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed-size bytecode and stacks bound both expression work and ownership.
module main

import math

const grapher_expression_limit = 256
const grapher_program_limit = 256
const grapher_depth_limit = 32
const grapher_sample_count = 513
const grapher_step_limit = 16

enum GrapherOpKind {
	number
	variable
	add
	subtract
	multiply
	divide
	power
	negate
	sine
	cosine
	tangent
	arcsine
	arccosine
	arctangent
	square_root
	absolute
	logarithm
	common_log
	exponential
	floor_value
	ceil_value
}

struct GrapherOp {
	kind   GrapherOpKind
	number f64
}

struct GrapherProgram {
mut:
	ops    [grapher_program_limit]GrapherOp
	length int
	uses_x bool
	steps  int
}

struct GrapherParser {
	source string // borrowed until parsing returns
mut:
	at      int
	depth   int
	program GrapherProgram
}

struct GrapherValue {
	value f64
	valid bool
	// Exact per-operation signs prevent connecting across division/tan poles.
	branches [4]u64
	steps    [grapher_step_limit]f64
}

fn (mut p GrapherParser) space() {
	for p.at < p.source.len && (p.source[p.at] == ` ` || p.source[p.at] == `\t`) { p.at++ }
}

fn (mut p GrapherParser) take(ch u8) bool {
	p.space()
	if p.at < p.source.len && p.source[p.at] == ch {
		p.at++
		return true
	}
	return false
}

fn (mut p GrapherParser) emit(kind GrapherOpKind, number f64) bool {
	if p.program.length >= grapher_program_limit { return false }
	if kind == .floor_value || kind == .ceil_value {
		if p.program.steps >= grapher_step_limit { return false }
		p.program.steps++
	}
	p.program.ops[p.program.length] = GrapherOp{ kind: kind, number: number }
	p.program.length++
	if kind == .variable { p.program.uses_x = true }
	return true
}

fn (mut p GrapherParser) number() ?f64 {
	p.space()
	mut value := f64(0)
	mut digits := 0
	for p.at < p.source.len && p.source[p.at].is_digit() {
		value = value * 10 + f64(p.source[p.at] - `0`)
		p.at++
		digits++
	}
	if p.at < p.source.len && p.source[p.at] == `.` {
		p.at++
		mut scale := f64(0.1)
		for p.at < p.source.len && p.source[p.at].is_digit() {
			value += f64(p.source[p.at] - `0`) * scale
			scale *= 0.1
			p.at++
			digits++
		}
	}
	if digits == 0 { return none }
	if p.at < p.source.len && (p.source[p.at] == `e` || p.source[p.at] == `E`) {
		p.at++
		negative := p.at < p.source.len && p.source[p.at] == `-`
		if p.at < p.source.len && (p.source[p.at] == `+` || p.source[p.at] == `-`) { p.at++ }
		mut exponent := 0
		mut count := 0
		for p.at < p.source.len && p.source[p.at].is_digit() {
			exponent = exponent * 10 + int(p.source[p.at] - `0`)
			p.at++
			count++
			if exponent > 308 { return none }
		}
		if count == 0 { return none }
		value *= math.pow(10, if negative { -f64(exponent) } else { f64(exponent) })
	}
	if !math.is_finite(value) { return none }
	return value
}

fn (mut p GrapherParser) primary() bool {
	p.space()
	if p.take(`(`) {
		if !p.expression(0) { return false }
		return p.take(`)`)
	}
	if p.at >= p.source.len { return false }
	ch := p.source[p.at]
	if ch.is_digit() || ch == `.` {
		value := p.number() or { return false }
		return p.emit(.number, value)
	}
	start := p.at
	for p.at < p.source.len && p.source[p.at] >= `a` && p.source[p.at] <= `z` { p.at++ }
	name := unsafe { tos(p.source.str + start, p.at - start) }
	match name {
		'x' { return p.emit(.variable, 0) }
		'pi' { return p.emit(.number, math.pi) }
		'e' { return p.emit(.number, math.e) }
		else {}
	}
	function := match name {
		'sin' { GrapherOpKind.sine }
		'cos' { .cosine }
		'tan' { .tangent }
		'asin' { .arcsine }
		'acos' { .arccosine }
		'atan' { .arctangent }
		'sqrt' { .square_root }
		'abs' { .absolute }
		'ln' { .logarithm }
		'log' { .common_log }
		'exp' { .exponential }
		'floor' { .floor_value }
		'ceil' { .ceil_value }
		else { return false }
	}
	if !p.take(`(`) || !p.expression(0) || !p.take(`)`) { return false }
	return p.emit(function, 0)
}

// Pratt parsing: unary minus binds below power; powers associate right.
fn (mut p GrapherParser) expression(minimum int) bool {
	p.depth++
	if p.depth > grapher_depth_limit {
		p.depth--
		return false
	}
	defer { p.depth-- }
	p.space()
	if p.take(`-`) {
		if !p.expression(3) || !p.emit(.negate, 0) { return false }
	} else if p.take(`+`) {
		if !p.expression(3) { return false }
	} else if !p.primary() {
		return false
	}
	for {
		p.space()
		if p.at >= p.source.len { break }
		ch := p.source[p.at]
		precedence := match ch {
			`+`, `-` { 1 }
			`*`, `/` { 2 }
			`^` { 3 }
			else { 0 }
		}
		if precedence == 0 || precedence < minimum { break }
		p.at++
		if !p.expression(if ch == `^` { precedence } else { precedence + 1 }) { return false }
		kind := match ch {
			`+` { GrapherOpKind.add }
			`-` { .subtract }
			`*` { .multiply }
			`/` { .divide }
			else { .power }
		}
		if !p.emit(kind, 0) { return false }
	}
	return true
}

fn grapher_parse(source string) ?GrapherProgram {
	if source.len == 0 || source.len > grapher_expression_limit { return none }
	mut parser := GrapherParser{ source: source }
	if !parser.expression(0) { return none }
	parser.space()
	if parser.at != source.len { return none }
	return parser.program
}

fn (program &GrapherProgram) evaluate(x f64) GrapherValue {
	mut stack := [grapher_program_limit]f64{}
	mut length := 0
	mut branches := [4]u64{}
	mut steps := [grapher_step_limit]f64{}
	mut step_count := 0
	for index in 0 .. program.length {
		op := program.ops[index]
		if op.kind == .number || op.kind == .variable {
			if length >= stack.len { return GrapherValue{} }
			stack[length] = if op.kind == .variable { x } else { op.number }
			length++
			continue
		}
		if length < 1 { return GrapherValue{} }
		right := stack[length - 1]
		mut result := f64(0)
		if op.kind in [.add, .subtract, .multiply, .divide, .power] {
			if length < 2 { return GrapherValue{} }
			left := stack[length - 2]
			if op.kind == .divide {
				if right == 0 { return GrapherValue{} }
				if right < 0 { branches[index / 64] |= u64(1) << u64(index % 64) }
			}
			result = match op.kind {
				.add { left + right }
				.subtract { left - right }
				.multiply { left * right }
				.divide { left / right }
				else { math.pow(left, right) }
			}
			length--
		} else {
			if op.kind == .tangent {
				cosine := math.cos(right)
				if math.abs(cosine) < 1e-12 { return GrapherValue{} }
				if cosine < 0 { branches[index / 64] |= u64(1) << u64(index % 64) }
			}
			result = match op.kind {
				.negate { -right }
				.sine { math.sin(right) }
				.cosine { math.cos(right) }
				.tangent { math.tan(right) }
				.arcsine { math.asin(right) }
				.arccosine { math.acos(right) }
				.arctangent { math.atan(right) }
				.square_root { math.sqrt(right) }
				.absolute { math.abs(right) }
				.logarithm { math.log(right) }
				.common_log { math.log10(right) }
				.exponential { math.exp(right) }
				.floor_value { math.floor(right) }
				.ceil_value { math.ceil(right) }
				else { return GrapherValue{} }
			}
		}
		if !math.is_finite(result) { return GrapherValue{} }
		if op.kind == .floor_value || op.kind == .ceil_value {
			steps[step_count] = result
			step_count++
		}
		stack[length - 1] = result
	}
	return if length == 1 && math.is_finite(stack[0]) {
		GrapherValue{ value: stack[0], valid: true, branches: branches, steps: steps }
	} else {
		GrapherValue{}
	}
}

fn grapher_constant(source string) ?f64 {
	program := grapher_parse(source) or { return none }
	if program.uses_x { return none }
	value := program.evaluate(0)
	if !value.valid { return none }
	return value.value
}

fn grapher_range_valid(minimum f64, maximum f64) bool {
	return math.is_finite(minimum) && math.is_finite(maximum) && minimum < maximum
		&& math.abs(minimum) <= 1e12 && math.abs(maximum) <= 1e12 && maximum - minimum >= 1e-9
}

fn grapher_connect(program &GrapherProgram, left GrapherValue, right GrapherValue, x f64, step f64, span f64) bool {
	if !left.valid || !right.valid || left.branches != right.branches || left.steps != right.steps || math.abs(left.value - right.value) > span * 0.25 {
		return false
	}
	for fraction in [0.25, 0.5, 0.75]! {
		middle := program.evaluate(x + step * fraction)
		if !middle.valid || middle.branches != left.branches || middle.steps != left.steps {
			return false
		}
		expected := left.value + (right.value - left.value) * fraction
		if math.abs(middle.value - expected) > span * 0.02 { return false }
	}
	return true
}
