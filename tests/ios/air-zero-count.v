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
type NativeBits = fn (u64) u64

struct CountCase { name string bits u32 flag int }
fn fixture(mut source strings.Builder) []CountCase {
	mut cases := []CountCase{}; cases.flags |= .noslices
	for width in u32(1) .. 65 { for op in ['ctlz', 'cttz'] {
		declaration := 'declare i${width} @llvm.${op}.i${width}(i${width}, i1 immarg)\n'; source.write_string(declaration); unsafe { declaration.free() }
		for flag in 0 .. 2 {
			name := '${op}_${width}_${flag}'; entry := CountCase{name, width, flag}; unsafe { cases.push_many(&entry, 1) }
			cast := if width == 64 { '' } else { '  %x = trunc i64 %a to i${width}\n' }
			operand := if width == 64 { '%a' } else { '%x' }
			wide := if width == 64 { '' } else { '  %wide = zext i${width} %r to i64\n' }
			result := if width == 64 { '%r' } else { '%wide' }
			// A poison-producing zero is replaced by one before any native call.
			// The independent tag records poison; its result bits are not consumed.
			text := 'define i${width} @${name}(i${width} %x) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} %x, i1 ${flag})\n  ret i${width} %r\n}\ndefine i64 @reference_${name}(i64 %a) {\n${cast}  %zero = icmp eq i${width} ${operand}, 0\n  %poison = and i1 %zero, ${flag}\n  %safe = select i1 %poison, i${width} 1, i${width} ${operand}\n  %r = call i${width} @llvm.${op}.i${width}(i${width} %safe, i1 ${flag})\n${wide}  %value = select i1 %poison, i64 0, i64 ${result}\n  %tag = select i1 %poison, i64 128, i64 0\n  %out = or i64 %value, %tag\n  ret i64 %out\n}\n'; source.write_string(text); unsafe { if width != 64 { cast.free(); wide.free() }; text.free() }
		}
		for state in ['poison', 'undef'] {
			text := 'define i${width} @${state}_${op}_${width}(i${width} %x) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} ${state}, i1 false)\n  ret i${width} %r\n}\n'; source.write_string(text); unsafe { text.free() }
		}
		// The second call uses the other immediate. Validating attributes once
		// must never skip checking this call's flag.
		mixed := 'define i${width} @mixed_${op}_${width}(i${width} %x) {\n  %a = call i${width} @llvm.${op}.i${width}(i${width} %x, i1 false)\n  %b = call i${width} @llvm.${op}.i${width}(i${width} %x, i1 true)\n  %r = add i${width} %a, %b\n  ret i${width} %r\n}\n'; source.write_string(mixed); unsafe { mixed.free() }
	} }
	for op in ['ctlz', 'cttz'] {
		dead := 'define i32 @dead_${op}(i32 %x) {\nentry: ret i32 0\ndead: %r = call i32 @llvm.${op}.i32(i32 %x, i1 false)\n  ret i32 %r\n}\n'; source.write_string(dead); unsafe { dead.free() }
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing zero count fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int) u64 { mut x := u64(sample) + u64(0x9e3779b97f4a7c15); x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, tagged u64, bits u32) !bool {
	poison := tagged & 128 != 0
	if (poison && tagged != 128) || (!poison && tagged > u64(bits)) || actual.kind != .integer || actual.bits != bits || actual.steps != 2 || actual.poison != poison || (!poison && actual.value != tagged) { return error('zero count value/tag/metadata differs from LLVM') }
	return poison
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-zero-count self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(262144); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('zero count fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-zero-count'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM zero count parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\npoison_reference=explicit tag and safe nonzero substitution\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tinput\tvinix\tpoison\tllvm_tagged\tsteps')!
	mut comparisons := 0; mut poison_cases := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }; address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing zero count reference') }; reference := unsafe { NativeBits(voidptr(address)) }
		limit := if c.bits <= 16 { int(u64(1) << c.bits) } else { 4096 }; boundary := int(c.bits) * 2 + 8
		for sample in 0 .. boundary + limit {
			edges := [u64(0), mask(c.bits), u64(1) << (c.bits - 1), (u64(1) << (c.bits - 1)) - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210]!
			a := if sample < 8 { edges[sample] } else if sample < boundary { bit := u64(1) << u32((sample - 8) / 2); if sample & 1 == 0 { bit } else { ~bit } } else if c.bits <= 16 { u64(sample - boundary) } else { pattern(sample - boundary) }
			args := [a | ~mask(c.bits)]; defer { unsafe { args.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := reference(args[0])
			poison := compare(actual, expected, c.bits) or { row := 'FAIL ${c.name} a=${a} value=${actual.value} poison=${actual.poison} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${args[0]}\t${actual.value}\t${actual.poison}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if poison { poison_cases++ }
		}
	}
	mut poison_controls := 0; mut undef_controls := 0; mut isolation_controls := 0; mut cache_controls := 0; mut cached_flag_controls := 0
	for c in cases {
		if c.flag != 0 { continue }
		base := c.name[..c.name.len - 2]; poison_name := 'poison_${base}'; undef_name := 'undef_${base}'; mixed_name := 'mixed_${base}'; defer { unsafe { base.free(); poison_name.free(); undef_name.free(); mixed_name.free() } }
		args := [u64(0)]; defer { unsafe { args.free() } }
		if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 64)!.poison { panic('zero count input poison lost') }; poison_controls++
		if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 64) { panic('zero count undef accepted') } else { undef_controls++ }
		index := function_index(ir, c.name)!
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('zero count budget accepted') } else { isolation_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer-only API accepted zero count') } else { isolation_controls++ }
		mixed_index := function_index(ir, mixed_name)!
		if !p.run_scalar_function(ir, stream, pools, bodies, mixed_index, args, 64)!.poison { panic('cached declaration skipped true flag') }; cache_controls++
		mixed_args := [mask(c.bits)]; defer { unsafe { mixed_args.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, mixed_index, mixed_args, 64)!
		if actual.poison || actual.kind != .integer || actual.bits != c.bits || actual.value != 0 || actual.steps != 4 { panic('mixed flags result differs') }; cache_controls++
		second := p.instructions[bodies.scopes[mixed_index + 1].instructions_start + 1]; flag_slot := second.operands_start + 2; original_flag := p.operands[flag_slot]
		p.operands[flag_slot] = airbitcode.IRTypedOperand{...original_flag, number: p.operands[second.operands_start + 1].number}
		if _ := p.run_scalar_function(ir, stream, pools, bodies, mixed_index, args, 64) { panic('cached declaration accepted nonconstant flag') } else { cached_flag_controls++ }; p.operands[flag_slot] = original_flag
	}
	mut metadata_controls := 0; mut flag_controls := 0; mut result_controls := 0; mut dead_controls := 0
	for op in ['ctlz', 'cttz'] {
		name := '${op}_32_1'; defer { unsafe { name.free() } }; index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]
		args := [u64(0)]; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: original.flags | 1}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, call_signature: -1}, airbitcode.IRTypedInstruction{...original, operands_count: 2}, airbitcode.IRTypedInstruction{...original, callee_function: -1}] {
			p.instructions[slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('accepted zero count call metadata')
		}; p.instructions[slot] = original
		flag_slot := original.operands_start + 2; flag := p.operands[flag_slot]
		for changed in [airbitcode.IRTypedOperand{...flag, number: p.operands[original.operands_start + 1].number}, airbitcode.IRTypedOperand{...flag, number: bodies.scopes[index + 1].base_id}, airbitcode.IRTypedOperand{...flag, number: 0}, airbitcode.IRTypedOperand{...flag, type_index: original.result_type}] {
			p.operands[flag_slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { flag_controls++; continue }; panic('accepted nonconstant/mistyped zero count flag')
		}; p.operands[flag_slot] = flag
		value := pools.lookup(index + 1, flag.number)!; constant := pools.constants[value.constant_index]
		mut altered_constants := pools.constants.clone(); mut altered_words := pools.words.clone(); defer { unsafe { altered_constants.free(); altered_words.free() } }
		altered_pools := airbitcode.IRConstantPools{...pools, constants: altered_constants, words: altered_words}
		for changed in [airbitcode.IRConstant{...constant, kind: .poison}, airbitcode.IRConstant{...constant, kind: .undef}, airbitcode.IRConstant{...constant, kind: .opaque}, airbitcode.IRConstant{...constant, splat: true}, airbitcode.IRConstant{...constant, type_index: original.result_type}] {
			altered_constants[value.constant_index] = changed
			p.run_scalar_function(ir, stream, altered_pools, bodies, index, args, 64) or { flag_controls++; continue }; panic('accepted invalid zero count flag constant')
		}; altered_constants[value.constant_index] = constant
		for bad in [u64(2), 0xffffffff, 0x100000000]! {
			altered_words[constant.words_start] = bad
			p.run_scalar_function(ir, stream, altered_pools, bodies, index, args, 64) or { flag_controls++; continue }; panic('accepted nonboolean zero count flag')
		}
		poison := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; compare(poison, 128, 32)!
		if _ := compare(airbitcode.IRScalarRun{...poison, poison: false}, 128, 32) { panic('accepted lost zero-count poison tag') } else { result_controls++ }
		false_name := '${op}_32_0'; defer { unsafe { false_name.free() } }; baseline := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, false_name)!, args, 64)!; compare(baseline, 32, 32)!
		for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] {
			compare(changed, 32, 32) or { result_controls++; continue }; panic('accepted corrupted zero count result')
		}
		dead_name := 'dead_${op}'; defer { unsafe { dead_name.free() } }; dead_index := function_index(ir, dead_name)!
		dead_op := p.instructions[bodies.scopes[dead_index + 1].instructions_start + 1]; dead_flag_slot := dead_op.operands_start + 2; dead_flag := p.operands[dead_flag_slot]
		p.operands[dead_flag_slot] = airbitcode.IRTypedOperand{...dead_flag, number: p.operands[dead_op.operands_start + 1].number}
		if _ := p.run_scalar_function(ir, stream, pools, bodies, dead_index, args, 64) { panic('accepted dynamic flag in dead block') } else { dead_controls++ }; p.operands[dead_flag_slot] = dead_flag
	}
	if metadata_controls != 14 || flag_controls != 24 || result_controls != 12 || dead_controls != 2 || cached_flag_controls != 128 { panic('zero count controls incomplete') }
	println('LLVM-ZERO-COUNT: ${cases.len} primitives, ${comparisons} exact value/tag comparisons (${poison_cases} poison); ${poison_controls} input-poison/${undef_controls} undef/${isolation_controls} budget-integer-isolation/${cache_controls} mixed-flag/${cached_flag_controls} cached-flag/${metadata_controls} metadata/${flag_controls} flag/${result_controls} result-corruption/${dead_controls} dead-block controls PASS; no AIR shader or iOS app executed')
}
