// SPDX-License-Identifier: Apache-2.0
// V replacement for the ARM64 subset of AOSP gen_mterp.py/gen_setup.py.
// Original algorithms: Copyright (C) 2016 The Android Open Source Project.
module artmterp

import os

fn word(text string) bool {
	return text.len > 0 && text.bytes().all(it.is_alnum() || it == `_`)
}

struct TemplateValue {
	text string
	is_bool bool
	boolean bool
}

struct TemplateLine {
	text string
	directive bool
	indent int
}

struct TemplateFunction {
	parameters []string
	body []TemplateLine
}

struct TemplateBranch {
	indent int
	parent bool
mut:
	taken bool
	active bool
}

struct TemplateEngine {
mut:
	functions map[string]TemplateFunction
	globals map[string]TemplateValue
	helpers map[string]string
	output []string
	depth int
	steps int
}

fn arguments(text string) ![]string {
	if text.trim_space() == '' { return []string{} }
	mut result := []string{}
	mut quote := u8(0)
	mut depth := 0
	mut start := 0
	mut escaped := false
	for i, c in text {
		if escaped { escaped = false; continue }
		if quote != 0 {
			if c == `\\` { escaped = true } else if c == quote { quote = 0 }
			continue
		}
		if c in [`"`, `'`] { quote = c; continue }
		if c == `(` { depth++ }
		if c == `)` { depth--; if depth < 0 { return error('unbalanced template arguments') } }
		if c == `,` && depth == 0 { result << text[start..i].trim_space(); start = i + 1 }
	}
	if quote != 0 || depth != 0 || escaped { return error('unterminated template arguments') }
	result << text[start..].trim_space()
	if result.any(it == '') { return error('empty template argument') }
	return result
}

fn template_call(text string) !(string, []string) {
	open := text.index('(') or { return error('expected template call: ' + text) }
	if !text.ends_with(')') { return error('invalid template call: ' + text) }
	return text[..open], arguments(text[open + 1..text.len - 1])!
}

fn template_functions(inputs []string) !map[string]TemplateFunction {
	mut files := inputs.clone()
	files.sort()
	mut functions := map[string]TemplateFunction{}
	for path in files {
		if os.file_size(path) > 1024 * 1024 { return error('template input exceeds size bound') }
		mut active := ''
		mut parameters := []string{}
		mut body := []TemplateLine{}
		mut indent := 0
		lines := os.read_file(path)!.split_into_lines()
		for raw in lines {
			line := raw.trim_right(' \t\r')
			if line.starts_with('%def ') {
				if active != '' { functions[active] = TemplateFunction{parameters, body} }
				if !line.ends_with(':') { return error('invalid template definition') }
				name, params := template_call(line[5..line.len - 1])!
				if !word(name) || name in functions { return error('invalid or duplicate template function: ' + name) }
				active = name
				parameters = params.clone()
				body = []TemplateLine{}
				indent = 2
			} else {
				if active == '' { return error('template text outside a function: ' + path) }
				if line.starts_with('%') {
					code := line[1..].trim_left(' ')
					indent = line.len - 1 - code.len
					if indent < 2 || indent % 2 != 0 { return error('invalid template directive indentation') }
					body << TemplateLine{code, true, indent}
					if code.ends_with(':') { indent += 2 }
				} else { body << TemplateLine{line, false, indent} }
			}
		}
		if active != '' { functions[active] = TemplateFunction{parameters, body} }
	}
	return functions
}

fn (mut engine TemplateEngine) value(expression string, locals map[string]TemplateValue) !TemplateValue {
	text := expression.trim_space()
	if text in ['True', 'False'] { return TemplateValue{is_bool: true, boolean: text == 'True'} }
	if text.len >= 2 && text[0] in [`"`, `'`] && text[text.len - 1] == text[0] {
		mut decoded := ''
		mut escaped := false
		for c in text[1..text.len - 1] {
			if escaped {
				if c !in [`"`, `'`, `\\`] { return error('unsupported template string escape') }
				decoded += c.ascii_str(); escaped = false
			} else if c == `\\` { escaped = true }
			else if c == text[0] { return error('unexpected quote inside template literal') }
			else { decoded += c.ascii_str() }
		}
		if escaped { return error('unterminated template string escape') }
		return TemplateValue{text: decoded}
	}
	if text in locals { return locals[text] }
	if text.contains('.startswith(') {
		name, args := template_call(text)!
		variable := name.trim_string_right('.startswith')
		if variable !in locals || args.len != 1 { return error('invalid startswith expression') }
		prefix := engine.value(args[0], locals)!
		return TemplateValue{is_bool: true, boolean: locals[variable].text.starts_with(prefix.text)}
	}
	if text.starts_with('add_helper(') {
		_, args := template_call(text)!
		if args.len !in [1, 2] { return error('invalid add_helper arguments') }
		name := if args.len == 2 { engine.value(args[1], locals)!.text } else {
			'mterp_' + engine.globals['opcode'].text + '_helper'
		}
		if !word(name) { return error('invalid generated helper name') }
		call := if args[0].starts_with('lambda: ') { args[0][8..] } else { args[0] + '()' }
		old := engine.output
		engine.output = []string{}
		engine.invoke('helper_start', [TemplateValue{text: name}], map[string]TemplateValue{})!
		engine.value(call, locals)!
		engine.invoke('helper_end', [TemplateValue{text: name}], map[string]TemplateValue{})!
		engine.helpers[name] = engine.output.join('\n') + '\n'
		engine.output = old.clone()
		return TemplateValue{text: name}
	}
	name, args := template_call(text)!
	if !word(name) { return error('unsupported template expression: ' + text) }
	mut positional := []TemplateValue{}
	mut named := map[string]TemplateValue{}
	for arg in args {
		key := arg.all_before('=')
		if arg.contains('=') && word(key) {
			if key in named { return error('duplicate named template argument') }
			named[key] = engine.value(arg.all_after('='), locals)!
		} else {
			if named.len > 0 { return error('positional argument follows named argument') }
			positional << engine.value(arg, locals)!
		}
	}
	engine.invoke(name, positional, named)!
	return TemplateValue{}
}

fn truth(value TemplateValue) bool {
	return if value.is_bool { value.boolean } else { value.text.len != 0 }
}

fn substitute(input string, locals map[string]TemplateValue) !string {
	mut chunks := []string{}
	mut literal := 0
	mut i := 0
	for i < input.len {
		if input[i] != `$` || (i > 0 && input[i - 1] == `$`) { i++; continue }
		start := i
		i++
		braces := i < input.len && input[i] == `{`
		if braces { i++ }
		begin := i
		for i < input.len && (input[i].is_alnum() || input[i] == `_`) { i++ }
		if i == begin || (braces && (i >= input.len || input[i] != `}`)) { continue }
		name := input[begin..i]
		if name !in locals || locals[name].is_bool { return error('missing string template variable: ' + name) }
		if braces { i++ }
		chunks << input[literal..start].replace('$$', '$')
		chunks << locals[name].text
		literal = i
	}
	chunks << input[literal..].replace('$$', '$')
	return chunks.join('')
}

fn (mut engine TemplateEngine) invoke(name string, positional []TemplateValue, named map[string]TemplateValue) ! {
	if name !in engine.functions { return error('missing template function: ' + name) }
	if engine.depth >= 32 { return error('template call depth exceeded') }
	engine.depth++
	defer { engine.depth-- }
	function := engine.functions[name]
	if positional.len + named.len > function.parameters.len { return error('too many template arguments') }
	mut locals := engine.globals.clone()
	mut used := map[string]bool{}
	for i, param in function.parameters {
		key := param.all_before('=')
		if !word(key) || key in used { return error('invalid template parameter') }
		used[key] = true
		if i < positional.len {
			if key in named { return error('duplicate positional/named argument') }
			locals[key] = positional[i]
		} else if key in named { locals[key] = named[key] }
		else if param.contains('=') { locals[key] = engine.value(param.all_after('='), engine.globals)! }
		else { return error('missing template argument: ' + key) }
	}
	for key in named.keys() { if key !in used { return error('unknown named template argument: ' + key) } }
	mut branches := []TemplateBranch{}
	for line in function.body {
		engine.steps++
		if engine.steps > 200000 || engine.output.len > 100000 { return error('template expansion bound exceeded') }
		alternative := line.directive && (line.text == 'else:' || line.text.starts_with('elif '))
		for branches.len > 0 && (line.indent < branches.last().indent ||
			(line.indent == branches.last().indent && !alternative)) { branches.delete_last() }
		if alternative {
			if branches.len == 0 || branches.last().indent != line.indent { return error('orphan template alternative') }
			mut branch := branches.last()
			condition := if line.text == 'else:' { true } else {
				truth(engine.value(line.text[5..].trim_string_right(':'), locals)!)
			}
			branch.active = branch.parent && !branch.taken && condition
			branch.taken = branch.taken || condition
			branches[branches.len - 1] = branch
			continue
		}
		active := branches.len == 0 || branches.last().active
		if line.directive && line.text.starts_with('if ') && line.text.ends_with(':') {
			condition := if active { truth(engine.value(line.text[3..line.text.len - 1], locals)!) } else { false }
			branches << TemplateBranch{line.indent, active, condition, active && condition}
			continue
		}
		if !active { continue }
		if !line.directive { engine.output << substitute(line.text, locals)!; continue }
		if line.text.starts_with('#') { continue }
		if line.text.contains(' = ') {
			key := line.text.all_before(' = ')
			if !word(key) { return error('invalid template assignment') }
			locals[key] = engine.value(line.text.all_after(' = '), locals)!
		} else { engine.value(line.text, locals)! }
	}
}

fn hex_byte(value int) string {
	return if value < 16 { '0' + value.hex() } else { value.hex() }
}

pub fn mterp(opcode_input string, templates []string) !string {
	if templates.len == 0 || templates.len > 32 { return error('bounded template list required') }
	mut engine := TemplateEngine{functions: template_functions(templates)!,
		globals: {'handler_size_bytes': TemplateValue{text: 'MTERP_HANDLER_SIZE'},
		'handler_size_bits': TemplateValue{text: 'MTERP_HANDLER_SIZE_LOG2'},
		'opcode': TemplateValue{}, 'opnum': TemplateValue{}}}
	mut opcodes := []string{}
	lines := opcode_input.split_into_lines()
	for raw in lines {
		line := raw.trim_left(' \t')
		if !line.starts_with('V(') { continue }
		fields := line[2..].split(', ')
		if fields.len < 2 || fields[0].len != 4 || !word(fields[1]) { return error('invalid packed opcode declaration') }
		expected := '0x' + hex_byte(opcodes.len)
		if fields[0].to_upper() != expected.to_upper() { return error('packed opcodes out of sequence') }
		opcodes << 'op_' + fields[1].to_lower()
	}
	if opcodes.len != 256 { return error('expected 256 packed opcodes') }
	for opcode in opcodes { if opcode !in engine.functions { return error('missing packed handler: ' + opcode) } }
	engine.output << '/* DO NOT EDIT: This file was generated by gen-mterp.py. */'
	for name in ['header', 'entry', 'instruction_start'] {
		engine.invoke(name, []TemplateValue{}, map[string]TemplateValue{})!
	}
	for i, opcode in opcodes {
		engine.globals['opcode'] = TemplateValue{text: opcode}
		engine.globals['opnum'] = TemplateValue{text: i.str()}
		engine.output << ['/* ------------------------------ */', '    .balign MTERP_HANDLER_SIZE',
			'.L_${opcode}: /* 0x' + hex_byte(i) + ' */']
		for name in ['opcode_start', 'opcode_pre', opcode, 'opcode_end'] {
			engine.invoke(name, []TemplateValue{}, map[string]TemplateValue{})!
		}
		engine.output << ''
	}
	engine.globals['opcode'] = TemplateValue{}
	engine.globals['opnum'] = TemplateValue{}
	engine.output << '    .balign MTERP_HANDLER_SIZE'
	engine.invoke('instruction_end', []TemplateValue{}, map[string]TemplateValue{})!
	mut helpers := engine.helpers.keys()
	helpers.sort()
	for name in helpers { engine.output << engine.helpers[name].trim_string_right('\n') }
	for name in ['helpers', 'footer'] { engine.invoke(name, []TemplateValue{}, map[string]TemplateValue{})! }
	// Helpers may contain internal newlines; flatten before squashing empty lines.
	expanded := engine.output.join('\n').split('\n')
	mut output := []string{}
	for line in expanded {
		if line == '' && output.len > 0 && output.last() == '' { continue }
		output << line
	}
	return output.join('\n') + '\n'
}
