// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strconv

fn llvm_name(line string) !string {
	mut quoted := false
	mut at := -1
	for i in 0 .. line.len {
		if line[i] == `"` { quoted = !quoted }
		if !quoted && line[i] == `@` { at = i + 1; break }
	}
	if at < 0 { return error('LLVM function name missing') }
	if line[at] != `"` { return line[at..].all_before('(').clone() }
	mut bytes := []u8{}
	defer { unsafe { bytes.free() } }
	mut i := at + 1
	for i < line.len && line[i] != `"` {
		if line[i] == `\\` {
			if i + 2 >= line.len { return error('LLVM function escape') }
			bytes << u8(strconv.parse_uint(line[i + 1..i + 3], 16, 8)!); i += 3
		} else { bytes << line[i]; i++ }
	}
	if i >= line.len { return error('unterminated LLVM function name') }
	return bytes.bytestr()
}
fn opcode_matches(code u64, opcode string) bool {
	return match code {
		2 { opcode in ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor', 'fadd', 'fsub', 'fmul', 'fdiv', 'frem'] }
		3 { opcode in ['trunc', 'zext', 'sext', 'fptrunc', 'fpext', 'fptoui', 'fptosi', 'uitofp', 'sitofp', 'ptrtoint', 'inttoptr', 'bitcast', 'addrspacecast'] }
		4, 30, 43 { opcode == 'getelementptr' } 5, 29 { opcode == 'select' }
		6 { opcode == 'extractelement' } 7 { opcode == 'insertelement' } 8 { opcode == 'shufflevector' }
		9, 28 { opcode in ['icmp', 'fcmp'] } 10 { opcode == 'ret' } 11 { opcode == 'br' }
		12 { opcode == 'switch' } 13 { opcode == 'invoke' } 15 { opcode == 'unreachable' }
		16 { opcode == 'phi' } 19 { opcode == 'alloca' } 20, 41 { opcode == 'load' }
		23 { opcode == 'va_arg' } 24, 42, 44, 45 { opcode == 'store' }
		26 { opcode == 'extractvalue' } 27 { opcode == 'insertvalue' } 31 { opcode == 'indirectbr' }
		34 { opcode == 'call' } 36 { opcode == 'fence' } 37, 46 { opcode == 'cmpxchg' }
		38, 59 { opcode == 'atomicrmw' } 39 { opcode == 'resume' } 40, 47 { opcode == 'landingpad' }
		48 { opcode == 'cleanupret' } 49 { opcode == 'catchret' } 50 { opcode == 'catchpad' }
		51 { opcode == 'cleanuppad' } 52 { opcode == 'catchswitch' } 56 { opcode == 'fneg' }
		57 { opcode == 'callbr' } 58 { opcode == 'freeze' }
		else { false }
	}
}
fn compare(ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, oracle string) ! {
	mut functions := map[string]int{}
	defer { unsafe { functions.free() } }
	for i, function in ir.functions { if !function.declaration { functions[function.name] = i + 1 } }
	mut seen := []bool{len: bodies.scopes.len}
	defer { unsafe { seen.free() } }
	mut scope := -1
	mut ordinal := 0
	mut block := 0
	mut results := 0
	mut checked := 0
	mut next_value := u32(0)
	for raw in oracle.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('define ') {
			if scope >= 0 { return error('nested LLVM function') }
			name := llvm_name(line)!
			defer { unsafe { name.free() } }
			scope = functions[name] or { return error('extra LLVM body') }
			if seen[scope] { return error('duplicate LLVM body') }; seen[scope] = true
			ordinal = 0; block = 0; results = 0
			next_value = pools.scopes[scope].base_id + u32(pools.scopes[scope].count)
			if bodies.scopes[scope].base_id != next_value { return error('LLVM body prefix differs from constant/argument inventory') }
			continue
		}
		if scope < 0 { continue }
		entry := bodies.scopes[scope]
		if line == '}' {
			if ordinal != entry.instructions_count || block != entry.blocks_count || results != entry.results_count { return error('LLVM body totals differ') }
			scope = -1; continue
		}
		if line.len == 0 || line.starts_with(';') { continue }
		if !raw.starts_with('  ') {
			if !line.all_before(';').trim_space().ends_with(':') { return error('unsupported LLVM body line') }
			if ordinal > 0 && (block == 0 || bodies.blocks[entry.blocks_start + block - 1].first + bodies.blocks[entry.blocks_start + block - 1].count != entry.instructions_start + ordinal) { return error('LLVM block label before terminator') }
			continue
		}
		// LLVM prints primary instructions at exactly two spaces. Switch tables,
		// EH clauses, invoke/callbr destinations and closing brackets continue them.
		if raw.len > 2 && raw[2] == ` ` { continue }
		if line == ']' || line.starts_with('to label ') { continue }
		if ordinal >= entry.instructions_count || block >= entry.blocks_count { return error('extra LLVM instruction') }
		has_result := line.starts_with('%') && line.contains(' = ')
		mut operation := if has_result { line.all_after(' = ') } else { line }
		for prefix in ['tail ', 'musttail ', 'notail '] { if operation.starts_with(prefix) { operation = operation[prefix.len..] } }
		opcode := operation.all_before(' ')
		instruction := bodies.instructions[entry.instructions_start + ordinal]
		terminator := opcode in ['ret', 'br', 'switch', 'invoke', 'unreachable', 'indirectbr', 'resume', 'cleanupret', 'catchret', 'catchswitch', 'callbr']
		if !opcode_matches(stream.records[instruction.record].code, opcode) || instruction.has_result != has_result
			|| instruction.terminator != terminator || instruction.block != entry.blocks_start + block || instruction.next_value != next_value { return error('LLVM instruction opcode/result/terminator/block/value-ID differs at ${ordinal}: ${line}') }
		if has_result {
			value := bodies.lookup(pools, scope, next_value)!
			if value.kind != .instruction || value.instruction != entry.instructions_start + ordinal { return error('LLVM instruction lookup differs') }
			next_value++; results++
		}
		ordinal++; checked++
		if terminator {
			bb := bodies.blocks[entry.blocks_start + block]
			if bb.first + bb.count != entry.instructions_start + ordinal { return error('LLVM block instruction extent differs') }
			block++
		}
	}
	for i, entry in bodies.scopes { if entry.active && !seen[i] { return error('missing LLVM function body') } }
	if scope >= 0 || checked != bodies.instructions.len { return error('incomplete LLVM body comparison') }
	println('LLVM-AIR-BODIES: ${checked} instructions, ${bodies.results.len} result IDs, ${bodies.blocks.len} basic blocks match opcode families, result presence/order and block extents; operands unverified')
}
fn fresh(path string) ! {
	out := os.abs_path(path)
	if os.exists(out) || os.is_link(out) || out == os.getwd() || out.starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	os.mkdir_all(out)!
}
fn run_saved(args []string, base string) ! {
	result := os.exec(args)
	defer { unsafe { result.output.free() } }
	os.write_file(base + '.log', result.output)!
	os.write_file(base + '.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('LLVM command failed: ' + args[0]) }
}
fn check_file(path string, llvm string, base string) !(int, int, int) {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!
	defer { bodies.free() }
	os.cp(path, base + '.bc')!
	run_saved([llvm, base + '.bc', '-o', base + '.ll'], base + '.dis')!
	oracle := os.read_file(base + '.ll')!
	defer { unsafe { oracle.free() } }
	compare(ir, stream, pools, bodies, oracle)!
	return bodies.instructions.len, bodies.results.len, bodies.blocks.len
}
fn corpus(input string, llvm string, output string) ! {
	fresh(output)!
	mut files := os.ls(input)!
	files.sort()
	mut modules := 0
	mut instructions := 0
	mut results := 0
	mut blocks := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		println('MODULE: ' + file)
		i, r, b := check_file(input + '/' + file, llvm, output + '/' + file.all_before_last('.bc'))!
		modules++; instructions += i; results += r; blocks += b
	}
	if modules == 0 { return error('no raw modules') }
	println('AIR-BODY-CORPUS: ${modules} modules, ${instructions} instructions, ${results} result IDs, ${blocks} blocks; independent LLVM comparison PASS; no execution')
}
fn self_test(assembler string, llvm string, output string) ! {
	fresh(output)!
	// LLVM fixture data, not an executable iOS shader.
	source := 'target triple = "x86_64-unknown-linux-gnu"
declare void @sink(i32)
declare i32 @value(i32)
declare i32 @__gxx_personality_v0(...)
define i32 @branch(i32 %x) personality ptr @__gxx_personality_v0 {
entry:
  %a = add i32 %x, 7
  call void @sink(i32 %a) [ "deopt"(i32 %x) ]
  %r = call i32 @value(i32 %a)
  br i1 true, label %left, label %right
left:
  %ret = invoke i32 @value(i32 %r) to label %join unwind label %cleanup
right:
  %b = freeze i32 %r
  switch i32 %b, label %join [ i32 0, label %exit ]
join:
  %v = phi i32 [ %ret, %left ], [ %b, %right ]
  ret i32 %v
exit:
  unreachable
cleanup:
  %pad = landingpad { ptr, i32 } cleanup
  resume { ptr, i32 } %pad
}
define void @asm_branch() {
entry:
  callbr void asm sideeffect "", "!i"() to label %normal [label %indirect]
normal:
  ret void
indirect:
  ret void
}
'
	os.write_file(output + '/input.ll', source)!
	run_saved([assembler, output + '/input.ll', '-o', output + '/input.bc'], output + '/assemble')!
	i, r, b := check_file(output + '/input.bc', llvm, output + '/fixture')!
	if i != 15 || r != 6 || b != 9 { return error('fixture instruction/result/block totals differ') }
	data := os.read_bytes(output + '/fixture.bc')!
	defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!
	defer { bodies.free() }
	oracle := os.read_file(output + '/fixture.ll')!
	defer { unsafe { oracle.free() } }
	mut rejected := 0
	for pair in [['%a = add ', 'add '], ['%a = add ', '%a = load '], ['br i1 true,', 'call i1 true,'], ['define i32 @branch(', 'define i32 @other(']] {
		if !oracle.contains(pair[0]) { return error('missing LLVM negative control input') }
		changed := oracle.replace_once(pair[0], pair[1])
		defer { unsafe { changed.free() } }
		compare(ir, stream, pools, bodies, changed) or { rejected++; continue }
		return error('accepted changed LLVM body: ' + pair[0])
	}
	for mode in ['id', 'result', 'block', 'terminator', 'lookup', 'extent'] {
		mut instructions := bodies.instructions.clone()
		mut results := bodies.results.clone()
		mut blocks := bodies.blocks.clone()
		defer { unsafe { instructions.free(); results.free(); blocks.free() } }
		first := instructions[0]
		match mode {
			'id' { instructions[0] = airbitcode.IRInstruction{...first, next_value: first.next_value + 1} }
			'result' { instructions[0] = airbitcode.IRInstruction{...first, has_result: false} }
			'block' { instructions[0] = airbitcode.IRInstruction{...first, block: first.block + 1} }
			'terminator' { instructions[0] = airbitcode.IRInstruction{...first, terminator: true} }
			'lookup' { results[0] = results[0] + 1 }
			'extent' { blocks[0] = airbitcode.IRBasicBlock{...blocks[0], count: blocks[0].count - 1} }
			else {}
		}
		changed := airbitcode.IRFunctionBodies{...bodies, instructions: instructions, results: results, blocks: blocks}
		compare(ir, stream, pools, changed, oracle) or { rejected++; continue }
		return error('accepted changed body index: ' + mode)
	}
	println('LLVM-BODY-SELFTEST: 15 instructions, six result IDs, nine blocks; void/value/bundled calls, invoke, callbr, PHI, switch, EH and ${rejected} rejected evidence corruptions PASS')
}
fn main() {
	if os.args.len == 5 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3], os.args[4])!; return }
	if os.args.len == 5 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3], os.args[4])!; return }
	panic('usage: air-bodies-inspect corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR | self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR')
}
