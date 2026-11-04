// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strconv

fn space(text string, offset int) int {
	mut i := offset
	for i < text.len && text[i] in [u8(9), 10, 13, 32]! { i++ }
	return i
}
fn identifier(text string, start int) !(string, int) {
	if start >= text.len { return error('missing LLVM identifier') }
	mut i := start
	if text[i] != `"` {
		for i < text.len && text[i] !in [u8(32), 9, `(`, `)`, `,`, `]`, `>`, `}`]! { i++ }
		if i == start { return error('empty LLVM identifier') }
		return text[start..i].clone(), i
	}
	i++
	mut bytes := []u8{}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for i < text.len && text[i] != `"` {
		if text[i] == `\\` {
			if i + 2 >= text.len { return error('truncated LLVM escape') }
			bytes << u8(strconv.parse_uint(text[i + 1..i + 3], 16, 8)!)
			i += 3
		} else { bytes << text[i]; i++ }
	}
	if i >= text.len { return error('unterminated LLVM identifier') }
	return bytes.bytestr(), i + 1
}
fn named_type(name string) string {
	mut bytes := [u8(`%`), `"`]
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for i in 0 .. name.len {
		byte := name[i]
		if byte >= 32 && byte <= 126 && byte !in [u8(`"`), `\\`]! { bytes << byte } else {
			hex := '0123456789ABCDEF'
			bytes << u8(`\\`); bytes << hex[int(byte >> 4)]; bytes << hex[int(byte & 15)]
		}
	}
	bytes << u8(`"`)
	return bytes.bytestr()
}
fn canonical(text string) string {
	mut bytes := []u8{cap: text.len}
	defer { unsafe { bytes.free() } }
	mut quoted := false
	for i in 0 .. text.len {
		byte := text[i]
		if byte == `"` { quoted = !quoted }
		if quoted || byte !in [u8(9), 10, 13, 32]! { bytes << byte }
	}
	return bytes.bytestr()
}
fn llvm_type(text string, start int, depth int) !(string, int) {
	if depth > 64 || text.len > 65536 { return error('LLVM type text limit') }
	mut i := space(text, start)
	if i >= text.len { return error('missing LLVM type') }
	if text[i] == `%` {
		name, end := identifier(text, i + 1)!
		defer { unsafe { name.free() } }
		return named_type(name), end
	}
	if text[i] in [u8(`<`), `[`, `{`]! {
		begin := i
		mut closing := if text[i] == `[` { u8(`]`) } else if text[i] == `<` { u8(`>`) } else { u8(`}`) }
		i = space(text, i + 1)
		if text[begin] == `{` || (text[begin] == `<` && i < text.len && text[i] == `{`) {
			packed := text[begin] == `<`
			if packed { i = space(text, i + 1) }
			mut result := if packed { '<{' } else { '{' }
			for i < text.len && text[i] != `}` {
				child, end := llvm_type(text, i, depth + 1)!
				result += child; unsafe { child.free() }; i = space(text, end)
				if i < text.len && text[i] == `,` { result += ','; i = space(text, i + 1) } else { break }
			}
			if i >= text.len || text[i] != `}` { return error('LLVM struct closing') }
			i = space(text, i + 1); result += '}'
			if packed { if i >= text.len || text[i] != `>` { return error('LLVM packed closing') }; i++; result += '>' }
			return result, i
		}
		mut prefix := ''
		if text[i..].starts_with('vscale') { prefix = 'vscalex'; i = space(text, i + 6); if i >= text.len || text[i] != `x` { return error('LLVM scalable vector') }; i = space(text, i + 1) }
		number := i
		for i < text.len && text[i] >= `0` && text[i] <= `9` { i++ }
		if i == number { return error('LLVM aggregate length') }
		prefix += text[number..i]
		i = space(text, i)
		if i >= text.len || text[i] != `x` { return error('LLVM aggregate separator') }
		child, end := llvm_type(text, i + 1, depth + 1)!
		defer { unsafe { child.free() } }
		i = space(text, end)
		if i >= text.len || text[i] != closing { return error('LLVM aggregate closing') }
		return text[begin..begin + 1] + prefix + 'x' + child + text[i..i + 1], i + 1
	}
	begin := i
	for i < text.len && ((text[i] >= `a` && text[i] <= `z`) || (text[i] >= `0` && text[i] <= `9`) || text[i] == `_`) { i++ }
	word := text[begin..i]
	if word == 'ptr' {
		j := space(text, i)
		if text[j..].starts_with('addrspace(') {
			mut end := j + 10
			for end < text.len && text[end] >= `0` && text[end] <= `9` { end++ }
			if end == j + 10 || end >= text.len || text[end] != `)` { return error('LLVM address space') }
			return 'ptr' + text[j..end + 1], end + 1
		}
		return 'ptr', i
	}
	if word.len > 1 && word[0] == `i` { strconv.parse_uint(word[1..], 10, 32)!; return word.clone(), i }
	if word !in ['void', 'half', 'bfloat', 'float', 'double', 'x86_fp80', 'fp128', 'ppc_fp128', 'label', 'metadata', 'token', 'x86_mmx', 'x86_amx'] { return error('unsupported LLVM text type') }
	return word.clone(), i
}
fn delimiter(text string, start int) !int {
	mut stack := []u8{}
	defer { unsafe { stack.free() } }
	stack.flags |= .noslices
	mut i := start
	for i < text.len {
		byte := text[i]
		if byte == `"` { name, end := identifier(text, i)!; unsafe { name.free() }; i = end; continue }
		if stack.len == 0 && byte in [u8(`,`), `)`]! { return i }
		if byte in [u8(`(`), `[`, `{`, `<`]! { stack << byte }
		if byte in [u8(`)`), `]`, `}`, `>`]! {
			if stack.len == 0 { return error('LLVM attribute scope') }
			open := stack.pop()
			if (open == `(` && byte != `)`) || (open == `[` && byte != `]`) || (open == `{` && byte != `}`) || (open == `<` && byte != `>`) { return error('LLVM mismatched attribute scope') }
		}
		i++
	}
	return error('LLVM parameter closing')
}
struct LLFunction {
	name string
	signature string
	declaration bool
mut:
	blocks int
}
fn function_header(line string) !LLFunction {
	mut at := -1
	mut i := 0
	for i < line.len {
		if line[i] == `"` { name, end := identifier(line, i)!; unsafe { name.free() }; i = end; continue }
		if line[i] == `@` { at = i; break }
		i++
	}
	if at < 0 { return error('LLVM function name') }
	name, end := identifier(line, at + 1)!
	mut keep := false
	defer { if !keep { unsafe { name.free() } } }
	mut result := ''
	for j in 0 .. at {
		if j != 0 && line[j - 1] !in [u8(9), 32]! { continue }
		typ, consumed := llvm_type(line[..at], j, 0) or { continue }
		if space(line[..at], consumed) == at { result = typ; break }
		unsafe { typ.free() }
	}
	if result.len == 0 || end >= line.len || line[end] != `(` { return error('LLVM function signature') }
	result += '('; i = space(line, end + 1)
	mut count := 0
	for i < line.len && line[i] != `)` {
		if count != 0 { result += ',' }
		if line[i..].starts_with('...') { result += '...'; i += 3 } else {
			typ, next := llvm_type(line, i, 0)!
			result += typ; unsafe { typ.free() }
			i = delimiter(line, next)!
		}
		count++
		i = space(line, i)
		if i < line.len && line[i] == `,` { i = space(line, i + 1) } else { break }
	}
	if i >= line.len || line[i] != `)` { return error('LLVM function closing') }
	result += ')'; keep = true
	return LLFunction{name: name, signature: result, declaration: line.starts_with('declare ')}
}

// LLVM 23 upgrades typed-pointer memory intrinsic names, moves declarations,
// and removes lifetime's i64 size operand. Keep the original AIR index intact;
// apply only these checked changes to the independent disassembly comparison.
fn upgraded(ir airbitcode.IRModule, f airbitcode.IRFunction, signature string) !(string, string, bool) {
	if f.name.starts_with('llvm.lifetime.start.') || f.name.starts_with('llvm.lifetime.end.') {
		typ := ir.types[f.signature]
		refs := ir.references[typ.refs_start..typ.refs_start + typ.refs_count]
		if !f.declaration || refs.len != 3 || ir.types[refs[0]].kind != .void_t || ir.types[refs[1]].kind != .integer_t || ir.types[refs[1]].bits != 64 || ir.types[refs[2]].kind != .pointer_t { return error('unexpected legacy lifetime signature') }
		pointer := ir.types[refs[2]]
		suffix := '.p' + pointer.address_space.str() + 'i8'
		if !f.name.ends_with(suffix) || pointer.refs_count != 1 || ir.types[ir.references[pointer.refs_start]].kind != .integer_t || ir.types[ir.references[pointer.refs_start]].bits != 8 { return error('unexpected legacy lifetime pointer') }
		return f.name[..f.name.len - 2].clone(), signature.replace_once('void(i64,', 'void('), true
	}
	if f.declaration && (f.name.starts_with('llvm.memcpy.') || f.name.starts_with('llvm.memmove.') || f.name.starts_with('llvm.memset.')) {
		mut parts := f.name.split('.')
		mut changed := false
		for i, part in parts {
			if part.starts_with('p') && part.ends_with('i8') && part.len > 3 {
				strconv.parse_uint(part[1..part.len - 2], 10, 24)!
				parts[i] = part[..part.len - 2]; changed = true
			}
		}
		return parts.join('.'), signature.clone(), changed
	}
	return f.name.clone(), signature.clone(), false
}

fn compare(ir airbitcode.IRModule, oracle string) ! {
	mut functions := []LLFunction{}
	functions.flags |= .noslices
	defer { unsafe { for f in functions { f.name.free(); f.signature.free() }; functions.free() } }
	mut active := -1
	mut triple := ''
	mut layout := ''
	mut source := ''
	defer { unsafe { triple.free(); layout.free(); source.free() } }
	for raw in oracle.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('target triple = ') { triple, _ = identifier(line, 16)! }
		if line.starts_with('target datalayout = ') { layout, _ = identifier(line, 20)! }
		if line.starts_with('source_filename = ') { source, _ = identifier(line, 18)! }
		if line.starts_with('define ') || line.starts_with('declare ') {
			if active != -1 { return error('nested LLVM function') }
			f := function_header(line)!
			functions << f
			if !f.declaration { active = functions.len - 1 }
		} else if active != -1 {
			if line == '}' { active = -1; continue }
			if line.len == 0 || line.starts_with(';') { continue }
			mut f := functions[active]
			if line.all_before(';').trim_space().ends_with(':') || f.blocks == 0 { f.blocks++ }
			functions[active] = f
		}
	}
	if active != -1 || functions.len != ir.functions.len || triple != ir.triple || layout != ir.data_layout || source != ir.source_filename { return error('LLVM module headers/function count differ') }
	mut lookup := map[string]int{}
	defer { unsafe { lookup.free() } }
	for i, f in functions {
		if f.name in lookup { return error('duplicate LLVM function') }
		lookup[f.name] = i
	}
	mut seen := []bool{len: functions.len}
	defer { unsafe { seen.free() } }
	mut bodies := 0
	mut upgrades := 0
	for f in ir.functions {
		text := ir.type_text(f.signature)!
		signature := canonical(text)
		defer { unsafe { text.free(); signature.free() } }
		name, expected, changed := upgraded(ir, f, signature)!
		defer { unsafe { name.free(); expected.free() } }
		index := lookup[name] or { return error('LLVM function missing: ' + f.name + ' -> ' + name) }
		if seen[index] { return error('nonunique LLVM function mapping') }
		seen[index] = true
		other := functions[index]
		if f.declaration != other.declaration || expected != other.signature || int(f.basic_blocks) != other.blocks { return error('LLVM function differs: ' + f.name + ' [' + expected + '] vs ' + other.name + ' [' + other.signature + '] blocks=${f.basic_blocks}/${other.blocks}') }
		if changed { upgrades++ }
		if !f.declaration { bodies++ }
	}
	println('LLVM-IR-COMPARE: ${functions.len} function names/signatures/declarations and ${bodies} body block counts match; triple/layout/source match; ${upgrades} checked intrinsic upgrades; instructions unverified')
}
fn compare_file(path string, llvm string, base string) !(int, int) {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	os.cp(path, base + '.bc')!
	result := os.exec([llvm, base + '.bc', '-o', base + '.ll'])
	defer { unsafe { result.output.free() } }
	os.write_file(base + '.llvm.log', result.output)!
	os.write_file(base + '.llvm.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('LLVM rejects ' + path) }
	oracle := os.read_file(base + '.ll')!
	defer { unsafe { oracle.free() } }
	compare(ir, oracle)!
	return ir.types.len, ir.functions.len
}
fn corpus(input string, llvm string, output string) ! {
	out := os.abs_path(output)
	if os.exists(out) || os.is_link(out) || out == os.getwd() || out.starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	mut files := os.ls(input)!
	defer { unsafe { files.free() } }
	files.sort()
	os.mkdir_all(out)!
	mut modules := 0
	mut types := 0
	mut functions := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		t, f := compare_file(input + '/' + file, llvm, out + '/' + file.all_before_last('.bc'))!
		modules++; types += t; functions += f
	}
	if modules == 0 { return error('no module streams') }
	println('AIR-IR-CORPUS: ${modules} modules, ${types} types indexed, ${functions} function signatures match LLVM; shader execution unverified')
}

fn reject_oracle(ir airbitcode.IRModule, oracle string, name string) ! {
	compare(ir, oracle) or {
		println('LLVM-IR-NEGATIVE: ${name} rejected')
		return
	}
	return error('accepted corrupt LLVM disassembly: ' + name)
}

// The Contacts module provides all required header/type/body cases.
fn negative_controls(ir airbitcode.IRModule, oracle string) ! {
	compare(ir, oracle)!
	for prefix in ['target triple = "', 'target datalayout = "', 'source_filename = "'] {
		changed := oracle.replace_once(prefix, prefix + 'CORRUPT')
		if changed == oracle { return error('missing header control input') }
		reject_oracle(ir, changed, prefix)!
		unsafe { changed.free() }
	}
	mut header_seen := false
	mut declaration_seen := false
	mut label_seen := false
	for raw in oracle.split_into_lines() {
		line := raw.trim_space()
		if !header_seen && line.starts_with('define ') {
			header_seen = true
			for pair in [['@', '@CORRUPT'], ['void @', 'i32 @'], ['addrspace(1)', 'addrspace(2)'], ['<2 x i32>', '<3 x i32>'], ['define ', 'declare ']] {
				header := raw.replace_once(pair[0], pair[1])
				if header == raw { return error('missing signature control input: ' + pair[0]) }
				changed := oracle.replace_once(raw, header)
				reject_oracle(ir, changed, pair[0])!
				unsafe { header.free(); changed.free() }
			}
		}
		if !declaration_seen && line.starts_with('declare ') {
			declaration_seen = true
			missing := oracle.replace_once(raw + '\n', '')
			extra := oracle.replace_once(raw, raw + '\n' + raw)
			reject_oracle(ir, missing, 'missing declaration')!
			reject_oracle(ir, extra, 'extra declaration')!
			unsafe { missing.free(); extra.free() }
		}
		if !label_seen && line.all_before(';').trim_space().ends_with(':') {
			label_seen = true
			changed := oracle.replace_once(raw + '\n', '')
			reject_oracle(ir, changed, 'basic block count')!
			unsafe { changed.free() }
		}
	}
	if !header_seen || !declaration_seen || !label_seen { return error('incomplete control fixture') }
	reject_oracle(ir, oracle[..oracle.len / 2], 'truncation')!
	println('LLVM-IR-NEGATIVE: all 12 corruption controls rejected')
}

fn main() {
	if os.args.len == 5 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len < 3 || os.args[1] !in ['inspect', 'compare', 'negative-controls'] || (os.args[1] == 'inspect' && os.args.len != 3) || (os.args[1] != 'inspect' && os.args.len != 4) { panic('usage: air-ir-inspect inspect FILE.bc | compare FILE.bc LLVM.ll | negative-controls CONTACTS.bc LLVM.ll | corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR') }
	if os.file_size(os.args[2]) > airbitcode.max_input_size { panic('input size limit') }
	data := os.read_bytes(os.args[2])!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	if os.args[1] in ['compare', 'negative-controls'] {
		oracle := os.read_file(os.args[3])!
		defer { unsafe { oracle.free() } }
		if os.args[1] == 'compare' { compare(ir, oracle)! } else { negative_controls(ir, oracle)! }
		return
	}
	println('AIR-IR: types=${ir.types.len} functions=${ir.functions.len} triple=${ir.triple}')
	for f in ir.functions {
		text := ir.type_text(f.signature)!
		println('${if f.declaration { "declare" } else { "define" }} ${f.name}: ${text} blocks=${f.basic_blocks}')
		unsafe { text.free() }
	}
}
