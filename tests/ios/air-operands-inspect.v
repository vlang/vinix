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
		if word !in ['nuw', 'nsw', 'exact', 'disjoint', 'nneg', 'samesign', 'nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast', 'nonnull'] { break }
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
		else { return error('unhandled decoded instruction in comparator') }
	}
	if text.all_before(' ') != mnemonic { return error('LLVM exact opcode differs: ' + text) }
	if typ >= 0 {
		expected := oracle_type(p, ir, typ)!
		defer { unsafe { expected.free() } }
		mut body := strip_flags(text.all_after(' '))
		if raw.code in [u64(9), 28]! { body = body.all_after(' ') }
		if !body.starts_with(expected + ' ') { return error('LLVM operand/result type differs: ' + text + ' expected ' + expected) }
	}
}
fn compare(ir airbitcode.IRModule, stream airbitcode.Stream, bodies airbitcode.IRFunctionBodies, p airbitcode.IRTypedProgram, oracle string) !int {
	mut functions := map[string]int{}
	defer { unsafe { functions.free() } }
	for i, f in ir.functions { if !f.declaration { functions[f.name] = i + 1 } }
	mut seen := []bool{len: bodies.scopes.len}
	defer { unsafe { seen.free() } }
	mut scope := -1
	mut ordinal := 0
	mut checked := 0
	for raw in oracle.split_into_lines() {
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
		typed_line(ir, stream, bodies, p, index, line)!
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
	decoded := compare(ir, stream, bodies, p, oracle)!
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
	if d != 25 || o != 2 || f != 2 || c != 3 { return error('fixture completeness/coverage differs') }
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
		compare(ir, stream, bodies, p, changed) or { controls++; continue }
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
		compare(ir, stream, bodies, changed, oracle) or { controls++; continue }
		return error('accepted corrupted typed index')
	}
	println('LLVM-OPERANDS-SELFTEST: 25 decoded, two opaque, two deferred; three complete function indexes, scalar/vector/FP/flags/forward-PHI checks and ${controls} rejected evidence corruptions PASS')
}
fn main() {
	if os.args.len == 5 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3], os.args[4])!; return }
	panic('usage: air-operands-inspect corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR | self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR')
}
