// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strconv

fn function_name(line string) !string {
	name := line.all_after('@')
	if !name.starts_with('"') { return name.all_before('(').clone() }
	mut bytes := []u8{}
	defer { unsafe { bytes.free() } }
	mut i := 1
	for i < name.len && name[i] != `"` {
		if name[i] == `\\` {
			if i + 2 >= name.len { return error('LLVM name escape') }
			bytes << u8(strconv.parse_uint(name[i + 1..i + 3], 16, 8)!); i += 3
		} else { bytes << name[i]; i++ }
	}
	if i >= name.len { return error('LLVM quoted name') }
	return bytes.bytestr()
}
fn strip_flags(text string) string {
	mut result := text
	for _ in 0 .. 16 {
		word := result.all_before(' ')
		if word !in ['nuw', 'nsw', 'exact', 'disjoint', 'nneg', 'samesign', 'nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast', 'nonnull', 'volatile', 'inbounds', 'nusw', 'inalloca', 'swifterror'] { break }
		result = result.all_after(' ')
	}
	return result
}
// The IR printer always quotes identified type names. LLVM omits quotes for
// ordinary identifiers; normalize only that spelling, not type structure.
fn oracle_type(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, index int) !string {
	text := p.type_text(ir, index)!
	defer { unsafe { text.free() } }
	mut bytes := []u8{cap: text.len}
	defer { unsafe { bytes.free() } }
	mut i := 0
	for i < text.len {
		if text[i] == `%` && i + 1 < text.len && text[i + 1] == `"` {
			mut end := i + 2
			mut simple := true
			for end < text.len && text[end] != `"` {
				ch := text[end]
				if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch in [u8(`_`), `.`, `$`, `-`]! || (end > i + 2 && ch >= `0` && ch <= `9`)) { simple = false }
				end++
			}
			if simple && end > i + 2 && end < text.len {
				bytes << u8(`%`); for j in i + 2 .. end { bytes << text[j] }; i = end + 1; continue
			}
		}
		bytes << text[i]; i++
	}
	return bytes.bytestr()
}
fn typed_line(ir airbitcode.IRModule, stream airbitcode.Stream, bodies airbitcode.IRFunctionBodies, p airbitcode.IRTypedProgram, index int, line string) ! {
	op := p.instructions[index]
	if op.status != .decoded { return }
	raw := stream.records[bodies.instructions[index].record]
	text := if line.starts_with('%') { line.all_after(' = ') } else { line }
	if raw.code == 34 { compare_call(ir, p, op, text)!; return }
	if raw.code == 8 { compare_shuffle(ir, p, op, text)!; return }
	mut mnemonic := ''
	mut typ := -1
	match raw.code {
		2 {
			typ = op.result_type
			scalar := if p.types[typ].kind == .vector_t { p.types[p.references[p.types[typ].refs_start]] } else { p.types[typ] }
			fp := scalar.kind != .integer_t
			integer := ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor']
			floating := ['fadd', 'fsub', 'fmul', '', 'fdiv', '', 'frem']
			if (fp && int(op.opcode) >= floating.len) || (!fp && int(op.opcode) >= integer.len) { return error('decoded binary opcode out of range') }
			mnemonic = if fp { floating[int(op.opcode)] } else { integer[int(op.opcode)] }
		}
		3 {
			casts := ['trunc', 'zext', 'sext', 'fptoui', 'fptosi', 'uitofp', 'sitofp', 'fptrunc', 'fpext', 'ptrtoint', 'inttoptr', 'bitcast', 'addrspacecast', 'ptrtoaddr']
			if int(op.opcode) >= casts.len { return error('decoded cast opcode out of range') }
			mnemonic = casts[int(op.opcode)]
			typ = p.operands[op.operands_start].type_index
			dest := oracle_type(p, ir, op.result_type)!
			defer { unsafe { dest.free() } }
			if text.all_after_last(' to ').all_before(', !').trim_space() != dest { return error('LLVM cast destination type differs') }
		}
		9, 28 {
			typ = p.operands[op.operands_start].type_index
			if op.opcode <= 15 {
				predicates := ['false', 'oeq', 'ogt', 'oge', 'olt', 'ole', 'one', 'ord', 'uno', 'ueq', 'ugt', 'uge', 'ult', 'ule', 'une', 'true']
				mnemonic = 'fcmp'
				if !strip_flags(text.all_after(' ')).starts_with(predicates[int(op.opcode)] + ' ') { return error('LLVM floating predicate differs') }
			} else {
				predicates := ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule', 'sgt', 'sge', 'slt', 'sle']
				if op.opcode < 32 || op.opcode > 41 { return error('decoded integer predicate out of range') }
				mnemonic = 'icmp'
				if !strip_flags(text.all_after(' ')).starts_with(predicates[int(op.opcode - 32)] + ' ') { return error('LLVM integer predicate differs') }
			}
		}
		5, 29 {
			mnemonic = 'select'
			value_type := oracle_type(p, ir, op.result_type)!
			defer { unsafe { value_type.free() } }
			if !text.contains(', ' + value_type + ' ') { return error('LLVM select value type differs') }
			typ = p.operands[op.operands_start + 2].type_index
		}
		6, 7 { mnemonic = if raw.code == 6 { 'extractelement' } else { 'insertelement' }; typ = p.operands[op.operands_start].type_index }
		16 { mnemonic = 'phi'; typ = op.result_type }
		10 {
			mnemonic = 'ret'
			if op.operands_count == 0 { if text != 'ret void' && !text.starts_with('ret void, !') { return error('LLVM void return differs') } }
			else { typ = p.operands[op.operands_start].type_index }
		}
		11 { mnemonic = 'br'; if op.operands_count > 0 { typ = p.operands[op.operands_start].type_index } }
		15 { mnemonic = 'unreachable' }
		56 { mnemonic = 'fneg'; typ = op.result_type }
		58 { mnemonic = 'freeze'; typ = op.result_type }
		4, 30, 43 { mnemonic = 'getelementptr'; typ = op.source_type }
		19 { mnemonic = 'alloca'; typ = op.source_type }
		20 { mnemonic = 'load'; typ = op.result_type }
		24, 44 { mnemonic = 'store'; typ = op.source_type }
		26, 27 {
			mnemonic = if raw.code == 26 { 'extractvalue' } else { 'insertvalue' }; typ = op.source_type
			mut suffix := ''
			for field in p.indices[op.indices_start..op.indices_start + op.indices_count] { suffix += ', ${field}' }
			defer { unsafe { suffix.free() } }
			if !text.all_before(', !').ends_with(suffix) { return error('LLVM aggregate index path differs') }
		}
		else { return error('unhandled decoded instruction in comparator') }
	}
	if text.all_before(' ') != mnemonic { return error('LLVM exact opcode differs: ' + text) }
	if raw.code in [u64(19), 20, 24, 44]! && op.alignment != 0 {
		align_text := ', align ${op.alignment}'
		if !text.ends_with(align_text) && !text.contains(align_text + ',') { return error('LLVM explicit memory alignment differs') }
	}
	if raw.code in [u64(20), 24, 44]! && text.all_after(' ').starts_with('volatile ') != op.is_volatile { return error('LLVM volatile flag differs') }
	if raw.code in [u64(4), 20, 24, 30, 43, 44]! {
		pointer := oracle_type(p, ir, p.operands[op.operands_start].type_index)!
		defer { unsafe { pointer.free() } }
		if !text.contains(', ' + pointer + ' ') { return error('LLVM memory base pointer type/address space differs') }
	}
	if raw.code == 19 {
		space := p.types[op.result_type].address_space
		if space == 0 { if text.contains(', addrspace(') { return error('LLVM alloca address space differs') } }
		else if !text.all_before(', !').ends_with(', addrspace(${space})') { return error('LLVM alloca address space differs') }
	}
	if typ >= 0 {
		expected := oracle_type(p, ir, typ)!
		defer { unsafe { expected.free() } }
		mut body := strip_flags(text.all_after(' '))
		if raw.code in [u64(9), 28]! { body = body.all_after(' ') }
		comma_type := raw.code in [u64(4), 19, 20, 30, 43]!
		if !body.starts_with(expected + ' ') && !(comma_type && body.starts_with(expected + ', ')) { return error('LLVM operand/result type differs: ' + text + ' expected ' + expected) }
	}
}
fn compare(ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, p airbitcode.IRTypedProgram, oracle string) !int {
	mut functions := map[string]int{}
	defer { unsafe { functions.free() } }
	for i, f in ir.functions { if !f.declaration { functions[f.name] = i + 1 } }
	lines := oracle.split_into_lines(); defer { unsafe { lines.free() } }
	labels := oracle_switch_labels(functions, bodies, lines)!; defer { unsafe { labels.free() } }
	mut seen := []bool{len: bodies.scopes.len}
	defer { unsafe { seen.free() } }
	mut scope := -1
	mut ordinal := 0
	mut checked := 0
	for line_index, raw in lines {
		line := raw.trim_space()
		if line.starts_with('define ') {
			name := function_name(line)!
			defer { unsafe { name.free() } }
			if scope >= 0 { return error('nested LLVM function') }
			scope = functions[name] or { return error('extra LLVM function') }
			if seen[scope] { return error('duplicate LLVM function') }; seen[scope] = true; ordinal = 0; continue
		}
		if scope < 0 { continue }
		entry := bodies.scopes[scope]
		if line == '}' {
			if ordinal != entry.instructions_count { return error('LLVM instruction count differs') }
			scope = -1; continue
		}
		if !raw.starts_with('  ') || raw.len <= 2 || raw[2] == ` ` || line.starts_with(';') || line == ']' || line.starts_with('to label ') { continue }
		if ordinal >= entry.instructions_count { return error('extra LLVM instruction') }
		index := entry.instructions_start + ordinal
		if stream.records[bodies.instructions[index].record].code == 12 && p.instructions[index].status == .decoded {
			compare_switch(ir, pools, bodies, p, index, labels, lines, line_index)!
		} else { typed_line(ir, stream, bodies, p, index, line)! }
		if p.instructions[index].status == .decoded { checked++ }
		ordinal++
	}
	for i, s in bodies.scopes { if s.active && !seen[i] { return error('missing LLVM body') } }
	if scope >= 0 { return error('incomplete LLVM body') }
	return checked
}
fn fresh(path string) ! {
	if os.exists(path) || os.is_link(path) || os.abs_path(path).starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	os.mkdir_all(path)!
}
fn run_saved(args []string, base string) ! {
	r := os.exec(args)
	defer { unsafe { r.output.free() } }
	os.write_file(base + '.log', r.output)!; os.write_file(base + '.status', r.exit_code.str() + '\n')!
	if r.exit_code != 0 { return error('LLVM failed') }
}
fn inspect(path string, llvm string, base string) !(int, int, int, int) {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	os.cp(path, base + '.bc')!
	run_saved([llvm, base + '.bc', '-o', base + '.ll'], base + '.dis')!
	oracle := os.read_file(base + '.ll')!; defer { unsafe { oracle.free() } }
	decoded := compare(ir, stream, pools, bodies, p, oracle)!
	mut opaque := 0; mut deferred := 0; mut complete := 0
	for op in p.instructions { if op.status == .opaque { opaque++ }; if op.status == .deferred { deferred++ } }
	for scope in 1 .. bodies.scopes.len { if p.complete(bodies, scope) { complete++ } }
	println('LLVM-TYPED-CORE: ${decoded} decoded type/opcode checks, ${opaque} opaque, ${deferred} deferred, ${complete} complete function indexes; no execution')
	return decoded, opaque, deferred, complete
}
fn corpus(input string, llvm string, out string) ! {
	fresh(out)!
	mut files := os.ls(input)!; files.sort()
	mut modules := 0; mut decoded := 0; mut opaque := 0; mut deferred := 0; mut complete := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		println('MODULE: ' + file)
		d, o, f, c := inspect(input + '/' + file, llvm, out + '/' + file.all_before_last('.bc'))!
		modules++; decoded += d; opaque += o; deferred += f; complete += c
	}
	if modules == 0 { return error('no modules') }
	println('TYPED-CORPUS: ${modules} modules, ${decoded} decoded, ${opaque} opaque, ${deferred} deferred, ${complete} complete function indexes; partial typed profile only')
}
fn self_test(assembler string, llvm string, out string) ! {
	fresh(out)!
	source := 'target triple = "x86_64-unknown-linux-gnu"
declare i32 @dependency()
define i32 @core(i32 %x, i32 %y) {
entry:
  %sum = add nuw nsw i32 %x, %y
  %wide = zext nneg i32 %sum to i64
  %cmp = icmp slt i32 %sum, %y
  br label %loop
loop:
  %phi = phi i32 [ %sum, %entry ], [ %next, %loop ]
  %next = add i32 %phi, 1
  %done = icmp ult i32 %next, 100
  br i1 %done, label %loop, label %exit
exit:
  ret i32 %next
}
define <2 x i32> @vectors(<2 x i32> %x, <2 x float> %f) {
entry:
  %cmp = icmp eq <2 x i32> %x, zeroinitializer
  %selected = select <2 x i1> %cmp, <2 x i32> %x, <2 x i32> zeroinitializer
  %lane = extractelement <2 x i32> %selected, i32 0
  %insert = insertelement <2 x i32> %selected, i32 %lane, i32 1
  %frozen = freeze <2 x i32> %insert
  %bits = bitcast <2 x float> %f to <2 x i32>
  %r = add <2 x i32> %frozen, %bits
  ret <2 x i32> %r
}
define i32 @floating(float %f) {
entry:
  %neg = fneg fast float %f
  %q = fdiv fast float %neg, %f
  %cmp = fcmp ogt float %q, %f
  %s = select fast i1 %cmp, float %q, float %f
  %r = fptoui float %s to i32
  ret i32 %r
}
define i32 @partial() {
entry:
  %v = call i32 @dependency()
  %r = add i32 %v, 1
  ret i32 %r
}
define i32 @deferred(ptr %p) {
entry:
  %v = load i32, ptr %p
  %r = add i32 %v, 1
  ret i32 %r
}
'
	os.write_file(out + '/input.ll', source)!
	run_saved([assembler, out + '/input.ll', '-o', out + '/input.bc'], out + '/assemble')!
	d, o, f, c := inspect(out + '/input.bc', llvm, out + '/fixture')!
	if d != 29 || o != 0 || f != 0 || c != 5 { return error('fixture completeness/coverage differs') }
	data := os.read_bytes(out + '/fixture.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if p.instructions[0].flags != 3 || p.instructions[1].opcode != 1 { return error('fixture integer flags/cast differ') }
	phi := p.instructions[4]
	if phi.operands_count != 2 || p.operands[phi.operands_start + 1].number <= bodies.instructions[4].next_value { return error('fixture forward PHI identity differs') }
	oracle := os.read_file(out + '/fixture.ll')!; defer { unsafe { oracle.free() } }
	mut controls := 0
	for pair in [['add nuw nsw i32', 'sub nuw nsw i32'], ['icmp slt i32', 'icmp sgt i32'], [' to i64', ' to i32'], ['fdiv fast float', 'fdiv fast double'], ['define i32 @core(', 'define i32 @other(']] {
		if !oracle.contains(pair[0]) { return error('missing negative control input') }
		changed := oracle.replace_once(pair[0], pair[1]); defer { unsafe { changed.free() } }
		compare(ir, stream, pools, bodies, p, changed) or { controls++; continue }
		return error('accepted corrupted LLVM typed evidence')
	}
	for mode in ['opcode', 'result-type', 'operand-type'] {
		mut instructions := p.instructions.clone(); mut operands := p.operands.clone()
		defer { unsafe { instructions.free(); operands.free() } }
		if mode == 'operand-type' { operands[0] = airbitcode.IRTypedOperand{...operands[0], type_index: p.instructions[1].result_type} }
		else { instructions[0] = airbitcode.IRTypedInstruction{...instructions[0], opcode: if mode == 'opcode' { 1 } else { 0 }, result_type: if mode == 'result-type' { p.instructions[1].result_type } else { instructions[0].result_type }} }
		// The first binary type is both operand/result type. Mutate a cast's
		// source operand for the independent operand-type corruption control.
		if mode == 'operand-type' { index := instructions[1].operands_start; operands[index] = airbitcode.IRTypedOperand{...operands[index], type_index: p.instructions[1].result_type} }
		changed := airbitcode.IRTypedProgram{...p, instructions: instructions, operands: operands}
		compare(ir, stream, pools, bodies, changed, oracle) or { controls++; continue }
		return error('accepted corrupted typed index')
	}
	println('LLVM-OPERANDS-SELFTEST: 29 decoded, no opaque/deferred; five complete function indexes, scalar/vector/FP/flags/forward-PHI checks and ${controls} rejected evidence corruptions PASS')
}
fn main() {
	if os.args.len == 5 && os.args[1] == 'switch-self-test' { switch_self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'shuffle-self-test' { shuffle_self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'call-self-test' { call_self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'memory-self-test' { memory_self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3], os.args[4])!; return }
	panic('usage: air-operands-inspect corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR | self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR | memory-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR | call-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR | shuffle-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR | switch-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR')
}

fn switch_self_test(assembler string, llvm string, out string) ! {
	fresh(out)!
	source := 'target triple = "x86_64-unknown-linux-gnu"
define i32 @choose(i32 %x) {
entry:
  switch i32 %x, label %fallback [
    i32 0, label %zero
    i32 -1, label %neg
    i32 7, label %zero
  ]
zero:
  ret i32 1
neg:
  ret i32 2
fallback:
  ret i32 3
}
define i32 @wide(i128 %x) {
entry:
  switch i128 %x, label %fallback [
    i128 18446744073709551617, label %high
    i128 -1, label %neg
  ]
high:
  ret i32 4
neg:
  ret i32 5
fallback:
  ret i32 6
}
define void @empty(i1 %x) {
entry:
  switch i1 %x, label %"a; end" []
"a; end":
  ret void
}
define i1 @boolean(i1 %x) {
entry:
  switch i1 %x, label %fallback [ i1 true, label %yes ]
yes:
  ret i1 true
fallback:
  ret i1 false
}
'
	os.write_file(out + '/input.ll', source)!
	run_saved([assembler, out + '/input.ll', '-o', out + '/input.bc'], out + '/assemble')!
	d, o, f, c := inspect(out + '/input.bc', llvm, out + '/fixture')!
	if d != 13 || o != 0 || f != 0 || c != 4 { return error('switch fixture coverage differs') }
	data := os.read_bytes(out + '/fixture.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	first := p.instructions[0]
	if first.targets_count != 4 || p.targets[first.targets_start] != 3 || p.targets[first.targets_start + 1] != 1 || p.targets[first.targets_start + 2] != 2 || p.targets[first.targets_start + 3] != 1 { return error('switch fixture default/case ordering differs') }
	if p.operands[first.operands_start].number != pools.module_values { return error('switch fixture normalized condition differs') }
	oracle := os.read_file(out + '/fixture.ll')!; defer { unsafe { oracle.free() } }
	mut controls := 0
	for pair in [['i32 7, label %zero', 'i32 8, label %zero'], ['i128 18446744073709551617', 'i128 18446744073709551618'],
		['i32 -1, label %neg', 'i32 -1, label %fallback'], ['switch i32 %x, label %fallback', 'switch i32 %x, label %zero'], ['i1 true, label %yes', 'i1 false, label %yes']] {
		if !oracle.contains(pair[0]) { return error('missing switch negative input') }
		changed := oracle.replace(pair[0], pair[1]); defer { unsafe { changed.free() } }
		compare(ir, stream, pools, bodies, p, changed) or { controls++; continue }
		return error('accepted changed LLVM switch evidence')
	}
	for mode in ['target', 'case', 'type'] {
		mut instructions := p.instructions.clone(); mut operands := p.operands.clone(); mut targets := p.targets.clone()
		defer { unsafe { instructions.free(); operands.free(); targets.free() } }
		if mode == 'target' { targets[first.targets_start] = 1 }
		else if mode == 'case' { operands[first.operands_start + 1] = operands[first.operands_start + 2] }
		else { instructions[0] = airbitcode.IRTypedInstruction{...first, source_type: instructions[4].source_type} }
		changed := airbitcode.IRTypedProgram{...p, instructions: instructions, operands: operands, targets: targets}
		compare(ir, stream, pools, bodies, changed, oracle) or { controls++; continue }
		return error('accepted changed decoded switch evidence')
	}
	println('LLVM-SWITCH-SELFTEST: 13 decoded instructions, four complete function indexes; exact destinations/case bits, i128/negative/boolean literals, shared targets, empty tables, quoted labels and ${controls} rejected evidence corruptions PASS')
}

fn compare_shuffle(ir airbitcode.IRModule, p airbitcode.IRTypedProgram, op airbitcode.IRTypedInstruction, text string) ! {
	if !text.starts_with('shufflevector ') { return error('LLVM shuffle opcode differs') }
	body := '(' + text.all_after(' ').all_before(', !') + ')'; defer { unsafe { body.free() } }
	args := call_arguments(body, 0)!; defer { unsafe { args.free() } }
	if args.len != 3 || op.operands_count != 3 { return error('LLVM shuffle operand count differs') }
	source := oracle_type(p, ir, op.source_type)!; defer { unsafe { source.free() } }
	if !args[0].starts_with(source + ' ') || !args[1].starts_with(source + ' ') { return error('LLVM shuffle input type differs') }
	mask := p.types[p.operands[op.operands_start + 2].type_index]
	mask_text := oracle_type(p, ir, p.operands[op.operands_start + 2].type_index)!; defer { unsafe { mask_text.free() } }
	if !args[2].starts_with(mask_text + ' ') || u64(op.indices_count) != mask.count { return error('LLVM shuffle mask type/width differs') }
	result := p.types[op.result_type]; input := p.types[op.source_type]
	if result.kind != .vector_t || result.count != mask.count || result.scalable != mask.scalable || p.references[result.refs_start] != p.references[input.refs_start] { return error('decoded shuffle result shape differs') }
	value := args[2][mask_text.len + 1..].trim_space()
	if value in ['zeroinitializer', 'undef', 'poison'] {
		expected := if value == 'zeroinitializer' { u32(0) } else { ~u32(0) }
		for lane in p.indices[op.indices_start..op.indices_start + op.indices_count] { if lane != expected { return error('LLVM shuffle splat differs') } }
		return
	}
	if !value.starts_with('<') || !value.ends_with('>') || mask.scalable { return error('LLVM shuffle literal mask syntax') }
	lanes_text := '(' + value[1..value.len - 1] + ')'; defer { unsafe { lanes_text.free() } }
	lanes := call_arguments(lanes_text, 0)!; defer { unsafe { lanes.free() } }
	if lanes.len != op.indices_count { return error('LLVM shuffle literal width differs') }
	for i, lane in lanes {
		if !lane.starts_with('i32 ') { return error('LLVM shuffle lane type differs') }
		number := lane[4..].trim_space()
		expected := if number in ['poison', 'undef'] { ~u32(0) } else { u32(strconv.parse_uint(number, 10, 32)!) }
		if p.indices[op.indices_start + i] != expected { return error('LLVM shuffle lane differs') }
	}
}

fn shuffle_self_test(assembler string, llvm string, out string) ! {
	fresh(out)!
	source := 'target triple = "x86_64-unknown-linux-gnu"
define <3 x float> @permute(<4 x float> %a, <4 x float> %b) {
  %r = shufflevector <4 x float> %a, <4 x float> %b, <3 x i32> <i32 7, i32 0, i32 poison>
  ret <3 x float> %r
}
define <2 x float> @zero(<4 x float> %a) {
  %r = shufflevector <4 x float> %a, <4 x float> poison, <2 x i32> zeroinitializer
  ret <2 x float> %r
}
define <2 x float> @undefined(<4 x float> %a) {
  %r = shufflevector <4 x float> %a, <4 x float> poison, <2 x i32> undef
  ret <2 x float> %r
}
define <2 x ptr> @pointers(<2 x ptr> %a, <2 x ptr> %b) {
  %r = shufflevector <2 x ptr> %a, <2 x ptr> %b, <2 x i32> <i32 1, i32 2>
  ret <2 x ptr> %r
}
define <vscale x 2 x i32> @scalable(<vscale x 4 x i32> %a) {
  %r = shufflevector <vscale x 4 x i32> %a, <vscale x 4 x i32> poison, <vscale x 2 x i32> zeroinitializer
  ret <vscale x 2 x i32> %r
}
'
	os.write_file(out + '/input.ll', source)!
	run_saved([assembler, out + '/input.ll', '-o', out + '/input.bc'], out + '/assemble')!
	d, o, f, c := inspect(out + '/input.bc', llvm, out + '/fixture')!
	if d != 10 || o != 0 || f != 0 || c != 5 { return error('shuffle fixture coverage differs') }
	data := os.read_bytes(out + '/fixture.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if p.indices != [u32(7), 0, ~u32(0), 0, 0, ~u32(0), ~u32(0), 1, 2, 0, 0] { return error('shuffle fixture normalized masks differ') }
	if !p.types[p.instructions[8].result_type].scalable { return error('shuffle fixture scalable result differs') }
	oracle := os.read_file(out + '/fixture.ll')!; defer { unsafe { oracle.free() } }
	mut controls := 0
	for pair in [['i32 7, i32 0', 'i32 6, i32 0'], ['<3 x i32> <', '<3 x i64> <'], ['shufflevector <4 x float>', 'shufflevector <4 x double>'],
		['<4 x float> %b', '<3 x float> %b'], ['i32 poison>', 'i32 1>']] {
		if !oracle.contains(pair[0]) { return error('missing shuffle negative input') }
		changed := oracle.replace(pair[0], pair[1]); defer { unsafe { changed.free() } }
		compare(ir, stream, pools, bodies, p, changed) or { controls++; continue }
		return error('accepted changed LLVM shuffle evidence')
	}
	for mode in ['lane', 'result', 'width'] {
		mut instructions := p.instructions.clone(); mut indices := p.indices.clone()
		defer { unsafe { instructions.free(); indices.free() } }
		if mode == 'lane' { indices[0] = 6 }
		else if mode == 'result' { instructions[0] = airbitcode.IRTypedInstruction{...instructions[0], result_type: instructions[2].result_type} }
		else { instructions[0] = airbitcode.IRTypedInstruction{...instructions[0], indices_count: 2} }
		changed := airbitcode.IRTypedProgram{...p, instructions: instructions, indices: indices}
		compare(ir, stream, pools, bodies, changed, oracle) or { controls++; continue }
		return error('accepted changed decoded shuffle evidence')
	}
	println('LLVM-SHUFFLE-SELFTEST: 10 decoded instructions, five complete function indexes; fixed/pointer/scalable vectors, width changes, poison/undef/zero masks and ${controls} rejected evidence corruptions PASS')
}

// Find a named direct/indirect callee followed by its argument list, ignoring
// named return types, nested signature types and quoted/escaped identifiers.
fn call_callee(text string) !(int, int) {
	mut depth := 0
	mut i := 0
	for i < text.len {
		ch := text[i]
		if depth == 0 && ch in [u8(`@`), `%`]! {
			start := i; i++
			if i < text.len && text[i] == `"` {
				i++
				for i < text.len && text[i] != `"` { if text[i] == `\\` { i += 2 }; i++ }
				if i >= text.len { return error('LLVM call quoted identifier') }; i++
			} else { for i < text.len && text[i] !in [u8(` `), `(`, `,`]! { i++ } }
			if i < text.len && text[i] == `(` { return start, i }
			continue
		}
		if ch in [u8(`(`), `[`, `{`, `<`]! { depth++ }
		if ch in [u8(`)`), `]`, `}`, `>`]! { depth-- }
		if depth < 0 { return error('LLVM call header nesting') }
		i++
	}
	return error('LLVM call has no named callee')
}
fn call_arguments(text string, open int) ![]string {
	mut args := []string{}
	args.flags |= .noslices
	mut keep := false
	defer { if !keep { unsafe { args.free() } } }
	mut start := open + 1
	mut depth := 0
	mut quoted := false
	mut i := start
	for i < text.len {
		ch := text[i]
		if ch == `\\` && quoted { i += 3; continue }
		if ch == `"` { quoted = !quoted; i++; continue }
		if !quoted {
			if ch == `)` && depth == 0 {
				if i > start { args << text[start..i].trim_space().clone() }
				keep = true; return args
			}
			if ch == `,` && depth == 0 { args << text[start..i].trim_space().clone(); start = i + 1 }
			if ch in [u8(`(`), `[`, `{`, `<`]! { depth++ }
			if ch in [u8(`)`), `]`, `}`, `>`]! { depth-- }
			if depth < 0 { return error('LLVM call argument nesting') }
		}
		i++
	}
	return error('LLVM call has no argument list ending')
}
// LLVM upgrades a small set of legacy pointer intrinsic names and removes the
// lifetime size argument. Check the original signature before normalizing it.
fn call_oracle_name(ir airbitcode.IRModule, index int) !(string, int) {
	f := ir.functions[index]
	if f.declaration && (f.name.starts_with('llvm.lifetime.start.') || f.name.starts_with('llvm.lifetime.end.')) && f.name.ends_with('i8') {
		typ := ir.types[f.signature]; refs := ir.references[typ.refs_start..typ.refs_start + typ.refs_count]
		if refs.len != 3 || ir.types[refs[0]].kind != .void_t || ir.types[refs[1]].kind != .integer_t || ir.types[refs[1]].bits != 64 { return error('legacy lifetime call signature') }
		pointer := ir.types[refs[2]]
		if pointer.kind != .pointer_t || pointer.refs_count != 1 || ir.types[ir.references[pointer.refs_start]].kind != .integer_t || ir.types[ir.references[pointer.refs_start]].bits != 8 || !f.name.ends_with('.p${pointer.address_space}i8') { return error('legacy lifetime call pointer') }
		return f.name[..f.name.len - 2].clone(), 1
	}
	if f.declaration && (f.name.starts_with('llvm.memcpy.') || f.name.starts_with('llvm.memmove.') || f.name.starts_with('llvm.memset.')) {
		mut parts := f.name.split('.')
		defer { unsafe { parts.free() } }
		for i, part in parts {
			if part.starts_with('p') && part.ends_with('i8') && part.len > 3 { strconv.parse_uint(part[1..part.len - 2], 10, 24)!; parts[i] = part[..part.len - 2] }
		}
		return parts.join('.'), 0
	}
	return f.name.clone(), 0
}
fn compare_call(ir airbitcode.IRModule, p airbitcode.IRTypedProgram, op airbitcode.IRTypedInstruction, text string) ! {
	mut body := text
	if body.starts_with('tail ') || body.starts_with('musttail ') || body.starts_with('notail ') { body = body.all_after(' ') }
	if !body.starts_with('call ') { return error('LLVM call opcode differs') }
	callee, open := call_callee(body)!
	args := call_arguments(body, open)!
	defer { unsafe { args.free() } }
	mut skip := 0
	if op.callee_function >= 0 {
		if body[callee] != `@` { return error('LLVM direct callee differs') }
		name := function_name(body[callee..])!; defer { unsafe { name.free() } }
		expected, removed := call_oracle_name(ir, op.callee_function)!; defer { unsafe { expected.free() } }
		if name != expected { return error('LLVM direct callee name differs: ' + name + ' expected ' + expected) }
		skip = removed
	}
	if args.len != op.operands_count - 1 - skip { return error('LLVM call argument count differs') }
	for i, arg in args {
		typ := oracle_type(p, ir, p.operands[op.operands_start + 1 + skip + i].type_index)!; defer { unsafe { typ.free() } }
		if !arg.starts_with(typ + ' ') { return error('LLVM call argument type differs: ' + arg + ' expected ' + typ) }
	}
	signature := p.types[op.call_signature]
	ret := p.references[signature.refs_start]
	if op.result_type != (if p.types[ret].kind == .void_t { -1 } else { ret }) { return error('decoded call result differs from signature') }
	result := oracle_type(p, ir, if signature.vararg { op.call_signature } else { p.references[signature.refs_start] })!
	defer { unsafe { result.free() } }
	if !body[..callee].trim_space().ends_with(' ' + result) { return error('LLVM call result/signature type differs') }
}

fn call_self_test(assembler string, llvm string, out string) ! {
	fresh(out)!
	source := 'target triple = "x86_64-unknown-linux-gnu"
declare fastcc i32 @target(i32)
declare void @sink(i32)
declare float @variadic(i32, ...)
declare void @llvm.experimental.noalias.scope.decl(metadata)
define i32 @calls(ptr %fn, i32 %x, float %f) {
entry:
  %a = tail call fastcc i32 @target(i32 %x)
  call void @sink(i32 %a)
  %v = call fast float (i32, ...) @variadic(i32 %x, float %f, <2 x i32> <i32 1, i32 2>)
  %b = call i32 %fn(i32 %a)
  ret i32 %b
}
define void @bundled(i32 %x) {
entry:
  call void @sink(i32 %x) [ "deopt"(i32 %x) ]
  ret void
}
define void @with_metadata() {
entry:
  call void @llvm.experimental.noalias.scope.decl(metadata !0)
  ret void
}
!0 = !{!1}
!1 = distinct !{!1, !2, !"scope"}
!2 = distinct !{!2, !"domain"}
'
	os.write_file(out + '/input.ll', source)!
	run_saved([assembler, out + '/input.ll', '-o', out + '/input.bc'], out + '/assemble')!
	d, o, f, c := inspect(out + '/input.bc', llvm, out + '/fixture')!
	if d != 7 || o != 2 || f != 0 || c != 1 { return error('call fixture coverage differs') }
	data := os.read_bytes(out + '/fixture.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	first := p.instructions[0]
	if first.flags & 1 == 0 || first.calling_convention != 8 || p.instructions[1].result_type != -1 || p.instructions[2].fast_math_flags != 254 { return error('call fixture flags/CC/void differ') }
	if p.instructions[2].operands_count != 4 || p.instructions[3].callee_function != -1 || p.operands[p.instructions[3].operands_start].number != pools.module_values { return error('call fixture indirect/vararg fields differ') }
	if !bodies.instructions[5].has_operand_bundles || p.instructions[5].status != .opaque || p.instructions[7].status != .opaque { return error('call fixture lost unsupported states') }
	oracle := os.read_file(out + '/fixture.ll')!; defer { unsafe { oracle.free() } }
	mut controls := 0
	for pair in [['@target(', '@wrong('], ['call fastcc i32 @target', 'call fastcc i64 @target'], ['@target(i32 %x)', '@target(float %x)'],
		['@sink(i32 %a)', '@sink(i32 %a, i32 0)'], ['(i32, ...) @variadic', '(float, ...) @variadic']] {
		if !oracle.contains(pair[0]) { return error('missing call negative input') }
		// Change a call site, not a preceding declaration.
		changed := oracle.replace(pair[0], pair[1]); defer { unsafe { changed.free() } }
		compare(ir, stream, pools, bodies, p, changed) or { controls++; continue }
		return error('accepted changed LLVM call evidence')
	}
	for mode in ['callee', 'argument-type', 'result-type'] {
		mut instructions := p.instructions.clone(); mut operands := p.operands.clone()
		defer { unsafe { instructions.free(); operands.free() } }
		if mode == 'callee' { instructions[0] = airbitcode.IRTypedInstruction{...first, callee_function: p.instructions[1].callee_function} }
		else if mode == 'result-type' { instructions[0] = airbitcode.IRTypedInstruction{...first, result_type: p.instructions[2].result_type} }
		else { operands[first.operands_start + 1] = airbitcode.IRTypedOperand{...operands[first.operands_start + 1], type_index: p.instructions[2].result_type} }
		changed := airbitcode.IRTypedProgram{...p, instructions: instructions, operands: operands}
		compare(ir, stream, pools, bodies, changed, oracle) or { controls++; continue }
		return error('accepted changed decoded call evidence')
	}
	println('LLVM-CALL-SELFTEST: 7 decoded, two opaque, no deferred, one complete function index; direct/indirect/void/vararg calls, CC/tail/FMF, bundled/metadata states and ${controls} rejected evidence corruptions PASS')
}

fn memory_self_test(assembler string, llvm string, out string) ! {
	fresh(out)!
	source := 'target datalayout = "e-p:64:64-p3:64:64-A5"
target triple = "x86_64-unknown-linux-gnu"
%Packet = type { i32, [4 x i32] }
define i32 @memory(ptr addrspace(3) %base, i64 %count, i32 %index) {
entry:
  %slot = alloca i32, i64 %count, align 16, addrspace(5)
  %field = getelementptr inbounds %Packet, ptr addrspace(3) %base, i64 0, i32 1, i32 %index
  %value = load volatile i32, ptr addrspace(3) %field, align 4
  store volatile i32 %value, ptr addrspace(5) %slot, align 16
  %agg = insertvalue %Packet zeroinitializer, i32 %value, 1, 2
  %r = extractvalue %Packet %agg, 1, 2
  ret i32 %r
}
define <2 x ptr addrspace(3)> @vector_gep(ptr addrspace(3) %base, <2 x i64> %indices) {
entry:
  %p = getelementptr i32, ptr addrspace(3) %base, <2 x i64> %indices
  ret <2 x ptr addrspace(3)> %p
}
define i32 @byte_alias(ptr %p) {
entry:
  %a = load i32, ptr %p, align 1
  store float 1.0, ptr %p, align 1
  ret i32 %a
}
'
	os.write_file(out + '/input.ll', source)!
	run_saved([assembler, out + '/input.ll', '-o', out + '/input.bc'], out + '/assemble')!
	d, o, f, c := inspect(out + '/input.bc', llvm, out + '/fixture')!
	if d != 12 || o != 0 || f != 0 || c != 3 { return error('memory fixture coverage differs') }
	data := os.read_bytes(out + '/fixture.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	alloca := p.instructions[0]
	if alloca.alignment != 16 || p.types[alloca.result_type].address_space != 5 || p.operands[alloca.operands_start].number != pools.module_values + 1 { return error('memory fixture alloca fields/count ID differ') }
	if !p.instructions[2].is_volatile || p.instructions[2].alignment != 4 || !p.instructions[3].is_volatile { return error('memory fixture volatility/alignment differ') }
	if p.indices != [u32(1), 2, 1, 2] { return error('memory fixture aggregate paths differ') }
	vector := p.types[p.instructions[7].result_type]
	if vector.kind != .vector_t || vector.count != 2 || p.types[p.references[vector.refs_start]].address_space != 3 { return error('memory fixture vector GEP type differs') }
	oracle := os.read_file(out + '/fixture.ll')!; defer { unsafe { oracle.free() } }
	mut controls := 0
	for pair in [['load volatile i32', 'load i32'], [', align 16', ', align 8'], ['getelementptr inbounds %Packet', 'getelementptr inbounds i32'],
		['%agg, 1, 2', '%agg, 1, 3'], ['ptr addrspace(3) %field', 'ptr addrspace(4) %field']] {
		if !oracle.contains(pair[0]) { return error('missing memory negative input') }
		changed := oracle.replace_once(pair[0], pair[1]); defer { unsafe { changed.free() } }
		compare(ir, stream, pools, bodies, p, changed) or { controls++; continue }
		return error('accepted changed LLVM memory evidence')
	}
	for mode in ['alignment', 'volatile', 'index'] {
		mut instructions := p.instructions.clone(); mut indices := p.indices.clone()
		defer { unsafe { instructions.free(); indices.free() } }
		if mode == 'alignment' { instructions[0] = airbitcode.IRTypedInstruction{...instructions[0], alignment: 8} }
		else if mode == 'volatile' { instructions[2] = airbitcode.IRTypedInstruction{...instructions[2], is_volatile: false} }
		else { indices[0] = 0 }
		changed := airbitcode.IRTypedProgram{...p, instructions: instructions, indices: indices}
		compare(ir, stream, pools, bodies, changed, oracle) or { controls++; continue }
		return error('accepted changed decoded memory evidence')
	}
	println('LLVM-MEMORY-SELFTEST: 12 decoded instructions, three complete function indexes; alloca absolute ID/A5, scalar/vector GEP, aliasing, aggregate paths, alignment/volatile and ${controls} rejected evidence corruptions PASS')
}


fn switch_label_name(text string) !string {
	encoded := '@' + text + '('; defer { unsafe { encoded.free() } }
	return function_name(encoded)!
}
fn switch_label_key(scope int, name string) string {
	prefix := scope.str(); defer { unsafe { prefix.free() } }
	return prefix + ':' + name
}
fn oracle_switch_labels(functions map[string]int, bodies airbitcode.IRFunctionBodies, lines []string) !map[string]int {
	mut labels := map[string]int{}
	mut keep := false
	defer { if !keep { unsafe { labels.free() } } }
	mut scope := -1; mut block := 0
	for raw in lines {
		line := raw.trim_space()
		if line.starts_with('define ') {
			name := function_name(line)!; defer { unsafe { name.free() } }
			scope = functions[name] or { return error('extra LLVM label function') }; block = 0; continue
		}
		if scope < 0 { continue }
		if line == '}' { if block != bodies.scopes[scope].blocks_count { return error('LLVM block total differs') }; scope = -1; continue }
		if line.len == 0 || line.starts_with(';') { continue }
		if !raw.starts_with(' ') {
			mut quoted := false
			mut end := -1
			mut i := 0
			for i < line.len {
				if line[i] == `\\` && quoted { i += 3; continue }
				if line[i] == `"` { quoted = !quoted }
				if line[i] == `:` && !quoted { end = i; break }; i++
			}
			if end < 0 || block >= bodies.scopes[scope].blocks_count { return error('LLVM label syntax/order') }
			name := switch_label_name(line[..end])!; defer { unsafe { name.free() } }
			key := switch_label_key(scope, name); defer { unsafe { key.free() } }
			if key in labels { return error('duplicate LLVM block label') }
			labels[key] = bodies.scopes[scope].blocks_start + block
			continue
		}
		if !raw.starts_with('  ') || raw.len <= 2 || raw[2] == ` ` || line == ']' || line.starts_with('to label ') { continue }
		mut operation := if line.starts_with('%') { line.all_after(' = ') } else { line }
		if operation.starts_with('tail ') || operation.starts_with('musttail ') || operation.starts_with('notail ') { operation = operation.all_after(' ') }
		if operation.all_before(' ') in ['ret', 'br', 'switch', 'invoke', 'unreachable', 'indirectbr', 'resume', 'cleanupret', 'catchret', 'catchswitch', 'callbr'] { block++ }
	}
	keep = true; return labels
}
fn oracle_switch_target(labels map[string]int, scope int, text string) !int {
	if !text.starts_with('label %') { return error('LLVM switch destination syntax') }
	name := switch_label_name(text[7..].trim_space())!; defer { unsafe { name.free() } }
	key := switch_label_key(scope, name); defer { unsafe { key.free() } }
	return labels[key] or { return error('missing LLVM switch destination') }
}
// The oracle parser handles bounded decimal literals independently of the
// bitcode constant reader. Its comparison profile permits up to 4096 bits.
fn oracle_switch_integer(text string, bits u32) ![]u32 {
	if bits == 0 || bits > 4096 || text.len > 1235 { return error('LLVM switch decimal comparison limit') }
	mut words := []u32{len: int((bits + 31) / 32)}
	mut keep := false
	defer { if !keep { unsafe { words.free() } } }
	value := if text == 'true' { '1' } else if text == 'false' { '0' } else { text }
	negative := value.starts_with('-')
	digits := if negative { value[1..] } else { value }
	if digits.len == 0 { return error('LLVM switch empty integer') }
	for digit in digits {
		if digit < `0` || digit > `9` { return error('LLVM switch non-decimal integer') }
		mut carry := u64(digit - `0`)
		for i in 0 .. words.len { next := u64(words[i]) * 10 + carry; words[i] = u32(next); carry = next >> 32 }
		if carry != 0 { return error('LLVM switch integer overflow') }
	}
	if bits % 32 != 0 && words.last() >> (bits % 32) != 0 { return error('LLVM switch integer width') }
	if negative {
		mut carry := u64(1)
		for i in 0 .. words.len { next := u64(~words[i]) + carry; words[i] = u32(next); carry = next >> 32 }
	}
	if bits % 32 != 0 { words[words.len - 1] &= (u32(1) << (bits % 32)) - 1 }
	keep = true; return words
}
fn compare_switch(ir airbitcode.IRModule, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, p airbitcode.IRTypedProgram, index int, labels map[string]int, lines []string, line_index int) ! {
	op := p.instructions[index]; inst := bodies.instructions[index]
	typ := oracle_type(p, ir, op.source_type)!; defer { unsafe { typ.free() } }
	header := lines[line_index].trim_space()
	if !header.starts_with('switch ' + typ + ' ') || op.result_type != -1 || op.operands_count != op.targets_count { return error('LLVM switch header/type differs') }
	if oracle_switch_target(labels, inst.scope, header.all_after(', ').all_before(' ['))! != p.targets[op.targets_start] { return error('LLVM switch default destination differs') }
	if header.contains('[ ]') || header.contains('[]') { if op.operands_count != 1 { return error('LLVM empty switch differs') }; return }
	if !header.ends_with('[') { return error('LLVM switch table opening') }
	mut count := 0
	for row in lines[line_index + 1..] {
		line := row.trim_space()
		if line.starts_with(']') { if count != op.operands_count - 1 { return error('LLVM switch case count differs') }; return }
		if line.len == 0 || line.starts_with(';') { continue }
		if count >= op.operands_count - 1 || !line.starts_with(typ + ' ') { return error('LLVM switch case type/count differs') }
		if oracle_switch_target(labels, inst.scope, line.all_after(', '))! != p.targets[op.targets_start + 1 + count] { return error('LLVM switch case destination differs') }
		words := oracle_switch_integer(line[typ.len + 1..].all_before(','), p.types[op.source_type].bits)!; defer { unsafe { words.free() } }
		value := pools.lookup(inst.scope, p.operands[op.operands_start + 1 + count].number)!
		if value.kind != .constant { return error('decoded switch case is not constant') }
		constant := pools.constants[value.constant_index]
		for i, word in words {
			expected := if constant.kind == .zero { u32(0) } else { u32(pools.words[constant.words_start + i / 2] >> (u32(i % 2) * 32)) }
			if word != expected { return error('LLVM switch case bits differ') }
		}
		count++
	}
	return error('LLVM switch table has no ending')
}
