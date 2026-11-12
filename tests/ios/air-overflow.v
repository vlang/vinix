// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strings

#flag -I/opt/homebrew/opt/llvm/include
#flag -L/opt/homebrew/opt/llvm/lib
#flag -lLLVM
#flag -Wl,-rpath,/opt/homebrew/opt/llvm/lib
#include <llvm-c/Core.h>
#include <llvm-c/BitReader.h>
#include <llvm-c/Analysis.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/ExecutionEngine.h>
fn C.LLVMContextCreate() voidptr
fn C.LLVMContextDispose(voidptr)
fn C.LLVMCreateMemoryBufferWithMemoryRangeCopy(voidptr, usize, &char) voidptr
fn C.LLVMDisposeMemoryBuffer(voidptr)
fn C.LLVMParseBitcodeInContext2(voidptr, voidptr, &voidptr) int
fn C.LLVMDisposeModule(voidptr)
fn C.LLVMDisposeMessage(&char)
fn C.LLVMVerifyModule(voidptr, int, &&char) int
fn C.LLVMInitializeNativeTarget() int
fn C.LLVMInitializeNativeAsmPrinter() int
fn C.LLVMGetDefaultTargetTriple() &char
fn C.LLVMSetTarget(voidptr, &char)
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
type NativeBits = fn (u64, u64) u64

struct OverflowCase { name string op string bits u32 }
fn wrapper(mut source strings.Builder, name string, width u32, result_bits u32) {
	cast := if width == 64 { '' } else { '  %a = trunc i64 %ai to i${width}\n  %b = trunc i64 %bi to i${width}\n' }
	a := if width == 64 { '%ai' } else { '%a' }; b := if width == 64 { '%bi' } else { '%b' }
	ending := if result_bits == 64 { '  ret i64 %r\n' } else { '  %wide = zext i${result_bits} %r to i64\n  ret i64 %wide\n' }
	text := 'define i64 @reference_${name}(i64 %ai, i64 %bi) {\n${cast}  %r = call i${result_bits} @${name}(i${width} ${a}, i${width} ${b})\n${ending}}\n'
	source.write_string(text); unsafe { cast.free(); ending.free(); text.free() }
}
fn fixture(mut source strings.Builder) []OverflowCase {
	mut cases := []OverflowCase{}
	for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] { for width in u32(1) .. 65 {
		name := '${op}_${width}'; cases << OverflowCase{name, op, width}
		declaration := 'declare {i${width}, i1} @llvm.${op}.with.overflow.i${width}(i${width}, i${width})\n'; source.write_string(declaration); unsafe { declaration.free() }
		for field in 0 .. 2 {
			result_bits := if field == 0 { width } else { u32(1) }; primitive := '${name}_${field}'
			text := 'define i${result_bits} @${primitive}(i${width} %a, i${width} %b) {\n  %pair = call {i${width}, i1} @llvm.${op}.with.overflow.i${width}(i${width} %a, i${width} %b)\n  %r = extractvalue {i${width}, i1} %pair, ${field}\n  ret i${result_bits} %r\n}\n'
			source.write_string(text); wrapper(mut source, primitive, width, result_bits); unsafe { primitive.free(); text.free() }
			for state in ['poison', 'undef'] { for side in 0 .. 2 {
				left := if side == 0 { state } else { '%a' }; right := if side == 1 { state } else { '%b' }
				control := 'define i${result_bits} @${state}_${name}_${field}_${side}(i${width} %a, i${width} %b) {\n  %pair = call {i${width}, i1} @llvm.${op}.with.overflow.i${width}(i${width} ${left}, i${width} ${right})\n  %r = extractvalue {i${width}, i1} %pair, ${field}\n  ret i${result_bits} %r\n}\n'; source.write_string(control); unsafe { control.free() }
			} }
			frozen := 'define i${result_bits} @frozen_${name}_${field}(i${width} %a, i${width} %b) {\n  %pair = call {i${width}, i1} @llvm.${op}.with.overflow.i${width}(i${width} poison, i${width} %b)\n  %x = extractvalue {i${width}, i1} %pair, ${field}\n  %f = freeze i${result_bits} %x\n  ret i${result_bits} %f\n}\n'; source.write_string(frozen); unsafe { frozen.free() }
		}
		branch_name := 'branch_${name}'
		branch := 'define i${width} @${branch_name}(i${width} %a, i${width} %b) {\n  %pair = call {i${width}, i1} @llvm.${op}.with.overflow.i${width}(i${width} %a, i${width} %b)\n  %x = extractvalue {i${width}, i1} %pair, 0\n  %flag = extractvalue {i${width}, i1} %pair, 1\n  br i1 %flag, label %yes, label %no\nyes:\n  %again = call {i${width}, i1} @llvm.${op}.with.overflow.i${width}(i${width} %x, i${width} %a)\n  %y = extractvalue {i${width}, i1} %again, 0\n  br label %join\nno:\n  br label %join\njoin:\n  %r = phi i${width} [ %y, %yes ], [ %x, %no ]\n  ret i${width} %r\n}\n'
		source.write_string(branch); wrapper(mut source, branch_name, width, width); unsafe { branch_name.free(); branch.free() }
	} }
	// These remain outside the deliberately bounded overflow-result profile.
	source.write_string('define i32 @constant_pair() {\n  %r = extractvalue {i32, i1} zeroinitializer, 0\n  ret i32 %r\n}\ndefine i1 @poison_pair() {\n  %r = extractvalue {i32, i1} poison, 1\n  ret i1 %r\n}\ndefine i32 @argument_pair({i32, i1} %a) {\n  %r = extractvalue {i32, i1} %a, 0\n  ret i32 %r\n}\ndefine {i32, i1} @return_pair(i32 %a, i32 %b) {\n  %p = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)\n  ret {i32, i1} %p\n}\ndefine i32 @freeze_pair(i32 %a, i32 %b) {\n  %p = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)\n  %f = freeze {i32, i1} %p\n  %r = extractvalue {i32, i1} %f, 0\n  ret i32 %r\n}\ndefine i32 @select_pair(i32 %a, i32 %b) {\n  %p = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)\n  %s = select i1 true, {i32, i1} %p, {i32, i1} poison\n  %r = extractvalue {i32, i1} %s, 0\n  ret i32 %r\n}\ndefine i32 @insert_pair(i32 %a, i32 %b) {\n  %p = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)\n  %s = insertvalue {i32, i1} %p, i1 true, 1\n  %r = extractvalue {i32, i1} %s, 0\n  ret i32 %r\n}\n')
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing overflow fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int, salt u64) u64 { mut x := u64(sample) + salt; x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! {
	if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('overflow field bits/metadata differ from native LLVM') }
}
fn native(engine voidptr, name string) !NativeBits {
	key := 'reference_${name}'; defer { unsafe { key.free() } }; address := C.LLVMGetFunctionAddress(engine, key.str)
	if address == 0 { return error('missing overflow native wrapper') }
	return unsafe { NativeBits(voidptr(address)) }
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-overflow self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('overflow fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-overflow'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM overflow parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tvinix_value\tllvm_value\tvinix_flag\tllvm_flag')!
	mut comparisons := 0; mut boundaries := 0; mut overflow_count := 0
	for c in cases {
		value_name := '${c.name}_0'; flag_name := '${c.name}_1'; defer { unsafe { value_name.free(); flag_name.free() } }
		value_index := function_index(ir, value_name)!; flag_index := function_index(ir, flag_name)!
		value_reference := native(engine, value_name)!; flag_reference := native(engine, flag_name)!
		limit := if c.bits <= 8 { int(u64(1) << (2 * c.bits)) } else { 4096 }
		for sample in 0 .. 144 + limit {
			sign := u64(1) << (c.bits - 1); full := mask(c.bits)
			edges := [u64(0), full, sign, sign - 1, sign + 1, u64(1), full - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, sign >> 1]!
			a := if sample < 144 { edges[sample / 12] } else if c.bits <= 8 { u64(sample - 144) & full } else { pattern(sample, 0x9e3779b97f4a7c15) }
			b := if sample < 144 { edges[sample % 12] } else if c.bits <= 8 { u64(sample - 144) >> c.bits } else { pattern(sample, 0x123456789abcdef0) }
			args := [a | ~full, b | ~full]; defer { unsafe { args.free() } }
			value := p.run_scalar_function(ir, stream, pools, bodies, value_index, args, 3)!; flag := p.run_scalar_function(ir, stream, pools, bodies, flag_index, args, 3)!
			expected_value := value_reference(args[0], args[1]); expected_flag := flag_reference(args[0], args[1]); if expected_flag > 1 { panic('native overflow flag not boolean') }
			compare(value, expected_value, c.bits, 3)!; compare(flag, expected_flag, 1, 3)!
			row := '${c.name}\t${args[0]}\t${args[1]}\t${value.value}\t${expected_value}\t${flag.value}\t${expected_flag}'; results.writeln(row)!; unsafe { row.free() }
			comparisons++; if sample < 144 { boundaries++ }; if expected_flag == 1 { overflow_count++ }
		}
	}
	mut poison_controls := 0; mut undef_controls := 0; mut isolation_controls := 0; mut chain_controls := 0; mut cache_controls := 0; mut frozen_controls := 0
	for c in cases {
		args := [u64(0), 0]; defer { unsafe { args.free() } }
		for field in 0 .. 2 {
			name := '${c.name}_${field}'; defer { unsafe { name.free() } }; index := function_index(ir, name)!
			if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 2) { panic('overflow budget ignored') } else { isolation_controls++ }
			if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 3) { panic('integer API accepted overflow call') } else { isolation_controls++ }
			frozen_name := 'frozen_${c.name}_${field}'; defer { unsafe { frozen_name.free() } }
			compare(p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, frozen_name)!, args, 4)!, 0, if field == 0 { c.bits } else { u32(1) }, 4)!; frozen_controls++
			for side in 0 .. 2 {
				poison_name := 'poison_${c.name}_${field}_${side}'; undef_name := 'undef_${c.name}_${field}_${side}'; defer { unsafe { poison_name.free(); undef_name.free() } }
				actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 3)!; if !actual.poison || actual.bits != if field == 0 { c.bits } else { u32(1) } || actual.steps != 3 { panic('overflow field poison lost') }; poison_controls++
				if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 3) { panic('overflow undef accepted') } else { undef_controls++ }
			}
		}
		name := 'branch_${c.name}'; flag_name := '${c.name}_1'; defer { unsafe { name.free(); flag_name.free() } }; index := function_index(ir, name)!; reference := native(engine, name)!; flag_reference := native(engine, flag_name)!
		full := mask(c.bits); sign := u64(1) << (c.bits - 1)
		for pair in [[u64(0), 0]!, [full, u64(1)]!, [sign - 1, u64(1)]!, [sign, full]!, [u64(0), full]!, [sign, u64(2)]!, [full, full]!, [u64(1), 1]!]! {
			inputs := [pair[0] | ~full, pair[1] | ~full]; defer { unsafe { inputs.free() } }; steps := if flag_reference(inputs[0], inputs[1]) == 1 { 9 } else { 7 }
			compare(p.run_scalar_function(ir, stream, pools, bodies, index, inputs, steps)!, reference(inputs[0], inputs[1]), c.bits, steps)!; chain_controls++
		}
		second_slot := bodies.scopes[index + 1].instructions_start + 4; saved := p.instructions[second_slot]
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: saved.flags | 1}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}] {
			p.instructions[second_slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('cached overflow call validation skipped') } else { cache_controls++ }
		}; p.instructions[second_slot] = saved
	}
	mut profile_controls := 0
	for name in ['constant_pair', 'poison_pair', 'argument_pair', 'return_pair', 'freeze_pair', 'select_pair', 'insert_pair'] {
		inputs := if name in ['constant_pair', 'poison_pair']! { []u64{} } else if name == 'argument_pair' { [u64(0)] } else { [u64(0), 0] }; defer { unsafe { inputs.free() } }
		if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, inputs, 32) { panic('general aggregate execution accepted') } else { profile_controls++ }
	}
	index := function_index(ir, 'sadd_32_0')!; slot := bodies.scopes[index + 1].instructions_start; call := p.instructions[slot]; extract := p.instructions[slot + 1]
	args := [u64(0x7fffffff), 1]; defer { unsafe { args.free() } }
	mut metadata_controls := 0
	for changed in [airbitcode.IRTypedInstruction{...call, flags: 1}, airbitcode.IRTypedInstruction{...call, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...call, calling_convention: 8}, airbitcode.IRTypedInstruction{...call, attribute_set: 1}, airbitcode.IRTypedInstruction{...call, call_signature: -1}, airbitcode.IRTypedInstruction{...call, callee_function: -1}, airbitcode.IRTypedInstruction{...call, operands_count: 2}] {
		p.instructions[slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('overflow call metadata accepted') } else { metadata_controls++ }
	}; p.instructions[slot] = call
	for changed in [airbitcode.IRTypedInstruction{...extract, flags: 1}, airbitcode.IRTypedInstruction{...extract, opcode: 1}, airbitcode.IRTypedInstruction{...extract, operands_count: 0}, airbitcode.IRTypedInstruction{...extract, indices_count: 0}, airbitcode.IRTypedInstruction{...extract, indices_start: -1}, airbitcode.IRTypedInstruction{...extract, source_type: -1}, airbitcode.IRTypedInstruction{...extract, result_type: -1}, airbitcode.IRTypedInstruction{...extract, targets_count: 1}] {
		p.instructions[slot + 1] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('overflow extract metadata accepted') } else { metadata_controls++ }
	}; p.instructions[slot + 1] = extract
	field := p.indices[extract.indices_start]; p.indices[extract.indices_start] = 2
	if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('overflow field outside pair accepted') } else { metadata_controls++ }; p.indices[extract.indices_start] = field
	mut layout_controls := 0; pair_type := p.types[call.result_type]
	for changed in [airbitcode.IRType{...pair_type, packed: true}, airbitcode.IRType{...pair_type, refs_count: 1}, airbitcode.IRType{...pair_type, name: 'named'}, airbitcode.IRType{...pair_type, refs_start: -1}] {
		p.types[call.result_type] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('overflow layout accepted') } else { layout_controls++ }
	}; p.types[call.result_type] = pair_type
	mut type_controls := 0
	for side in 1 .. 3 {
		operand_slot := call.operands_start + side; saved := p.operands[operand_slot]
		p.operands[operand_slot] = airbitcode.IRTypedOperand{...saved, type_index: call.result_type}
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('overflow argument mismatch accepted') } else { type_controls++ }; p.operands[operand_slot] = saved
	}
	for field_index in 0 .. 2 {
		reference_slot := pair_type.refs_start + field_index; saved := p.references[reference_slot]
		p.references[reference_slot] = p.references[pair_type.refs_start + 1 - field_index]
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 32) { panic('overflow data/flag field type accepted') } else { type_controls++ }; p.references[reference_slot] = saved
	}
	mut functions := ir.functions.clone(); defer { unsafe { functions.free() } }; altered_ir := airbitcode.IRModule{...ir, functions: functions}; mut name_controls := 0
	for wrong in ['llvm.sadd.with.overflow.i31', 'llvm.sadd.with.overflow.i032', 'air.sadd.with.overflow.i32'] {
		functions[call.callee_function] = airbitcode.IRFunction{...ir.functions[call.callee_function], name: wrong}
		if _ := p.run_scalar_function(altered_ir, stream, pools, bodies, index, args, 32) { panic('overflow overload mismatch accepted') } else { name_controls++ }
	}
	baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 3)!; compare(baseline, 0x80000000, 32, 3)!; mut result_controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 1}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 2}] {
		compare(changed, 0x80000000, 32, 3) or { result_controls++; continue }; panic('overflow result corruption accepted')
	}
	flag_baseline := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'sadd_32_1')!, args, 3)!; compare(flag_baseline, 1, 1, 3)!
	compare(airbitcode.IRScalarRun{...flag_baseline, value: 0}, 1, 1, 3) or { result_controls++ }
	if cases.len != 384 || comparisons != 1955832 || boundaries != 55296 || poison_controls != 1536 || undef_controls != 1536 || isolation_controls != 1536 || chain_controls != 3072 || cache_controls != 768 || frozen_controls != 768 || profile_controls != 7 || metadata_controls != 16 || layout_controls != 4 || type_controls != 4 || name_controls != 3 || result_controls != 6 { panic('overflow coverage incomplete') }
	println('LLVM-INTEGER-OVERFLOW: ${cases.len} intrinsic overloads, ${comparisons} exact value/flag pairs (${2 * comparisons} extracted fields, ${overflow_count} overflow flags, ${boundaries} boundary pairs); ${poison_controls} poison/${undef_controls} undef/${isolation_controls} budget-integer/${chain_controls} native branch-PHI/${cache_controls} cached-call/${frozen_controls} frozen-field/${profile_controls} aggregate-profile/${metadata_controls} metadata/${layout_controls} layout/${type_controls} type/${name_controls} name/${result_controls} result-corruption controls PASS; no AIR shader or iOS app executed')
}
