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
#include <fenv.h>
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
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
fn C.feclearexcept(int) int
fn C.fetestexcept(int) int
type NativeBits = fn (u64) u64

struct ClassCase { name string bits u32 mask u32 }
fn fixture(mut source strings.Builder) []ClassCase {
	mut cases := []ClassCase{}; cases.flags |= .noslices
	for bits in [u32(16), 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		declaration := 'declare i1 @llvm.is.fpclass.f${bits}(${typ}, i32 immarg)\n'; source.write_string(declaration); unsafe { declaration.free() }
		for mask in 0 .. 1024 {
			name := 'class_${bits}_${mask}'; entry := ClassCase{name, bits, u32(mask)}; unsafe { cases.push_many(&entry, 1) }
			text := 'define i1 @${name}(${typ} %x) {\n  %r = call i1 @llvm.is.fpclass.f${bits}(${typ} %x, i32 ${mask})\n  ret i1 %r\n}\ndefine i64 @reference_${name}(i64 %a) {\n  %ai = trunc i64 %a to i${bits}\n  %x = bitcast i${bits} %ai to ${typ}\n  %r = call i1 @${name}(${typ} %x)\n  %out = zext i1 %r to i64\n  ret i64 %out\n}\n'; source.write_string(text); unsafe { text.free() }
		}
		for state in ['poison', 'undef'] {
			text := 'define i1 @${state}_${bits}(${typ} %x) {\n  %r = call i1 @llvm.is.fpclass.f${bits}(${typ} ${state}, i32 3)\n  ret i1 %r\n}\n'; source.write_string(text); unsafe { text.free() }
		}
		// A true predicate selects an FP input into a PHI and feeds another
		// class test; the false path supplies positive zero.
		flow := 'define i1 @flow_${bits}(${typ} %x) {\nentry: %test = call i1 @llvm.is.fpclass.f${bits}(${typ} %x, i32 3)\n  br i1 %test, label %yes, label %no\nyes: br label %exit\nno: br label %exit\nexit: %a = phi ${typ} [ %x, %yes ], [ 0.0, %no ]\n  %r = call i1 @llvm.is.fpclass.f${bits}(${typ} %a, i32 3)\n  ret i1 %r\n}\n'; source.write_string(flow); unsafe { flow.free() }
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int {
	for i, f in ir.functions { if f.name == name { return i } }; return error('missing classification fixture')
}
fn compare(actual airbitcode.IRScalarRun, expected u64) ! {
	if expected > 1 || actual.kind != .integer || actual.bits != 1 || actual.poison || actual.steps != 2 || actual.value != expected { return error('classification result differs from native LLVM') }
}
fn pattern(sample int) u64 {
	mut x := u64(sample) + u64(0x9e3779b97f4a7c15)
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return u64(u32(x ^ (x >> 31)))
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-fpclass self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 || C.fegetround() != C.FE_TONEAREST { panic('cannot establish native environment') }; defer { C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) }
	mut source := strings.new_builder(1048576); defer { unsafe { source.free() } }
	cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('classification fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-fpclass'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM classification fixture parse failed') }
	mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple)
	mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\nreference_fenv=FE_DFL_ENV,FE_TONEAREST\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	half_edges := [u64(0x7c01), 0xfcff, 0x7e00, 0xffff, 0xfc00, 0xfc00, 0x8400, 0xfbff, 0x8001, 0x83ff, 0x8000, 0x8000, 0, 0, 1, 0x3ff, 0x400, 0x7bff, 0x7c00, 0x7c00]!
	float_edges := [u64(0x7f800001), 0xffbfffff, 0x7fc00000, 0xffffffff, 0xff800000, 0xff800000, 0x80800000, 0xff7fffff, 0x80000001, 0x807fffff, 0x80000000, 0x80000000, 0, 0, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0x7f800000, 0x7f800000]!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tinput\tvinix\tllvm\tsteps')!
	mut comparisons := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }
		address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing classification reference') }; reference := unsafe { NativeBits(voidptr(address)) }
		exhaustive := c.mask in [u32(0), 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 3, 96, 144, 264, 516, 504, 1023]!
		for sample in 0 .. 20 + if exhaustive { 65536 } else { 0 } {
			a := if sample < 20 { if c.bits == 16 { half_edges[sample] } else { float_edges[sample] } } else if c.bits == 16 { u64(sample - 20) } else { pattern(sample - 20) }
			args := [a | (u64(0x12345678) << 32)]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := reference(args[0])
			compare(actual, expected) or { row := 'FAIL ${c.name} a=${a} got=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${a}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++
		}
	}
	mut poison_controls := 0; mut undef_controls := 0; mut flow_controls := 0
	for bits in [u32(16), 32]! {
		poison_name := 'poison_${bits}'; undef_name := 'undef_${bits}'; flow_name := 'flow_${bits}'; defer { unsafe { poison_name.free(); undef_name.free(); flow_name.free() } }
		args := [u64(0)]; defer { unsafe { args.free() } }
		if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 64)!.poison { panic('classification poison lost') }; poison_controls++
		if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 64) { panic('classification undef accepted') } else { undef_controls++ }
		for i in 0 .. 20 {
			flow_args := [if bits == 16 { half_edges[i] } else { float_edges[i] }]; defer { unsafe { flow_args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, flow_name)!, flow_args, 64)!
			if actual.kind != .integer || actual.bits != 1 || actual.poison || actual.value != u64(i < 4) || actual.steps != 6 { panic('classification branch/PHI differs') }; flow_controls++
		}
	}
	mut metadata_controls := 0; mut mask_controls := 0; mut result_controls := 0; mut environment_controls := 0
	for bits in [u32(16), 32]! {
		name := 'class_${bits}_3'; defer { unsafe { name.free() } }; index := function_index(ir, name)!
		slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]
		args := [u64(0)]; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: original.flags | 1}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, call_signature: -1}, airbitcode.IRTypedInstruction{...original, result_type: p.operands[original.operands_start + 1].type_index}, airbitcode.IRTypedInstruction{...original, operands_count: 2}] {
			p.instructions[slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('accepted classification call metadata')
		}; p.instructions[slot] = original
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('classification budget accepted') } else { metadata_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer API accepted classification') } else { metadata_controls++ }
		mask_slot := original.operands_start + 2; mask := p.operands[mask_slot]
		for changed in [airbitcode.IRTypedOperand{...mask, number: p.operands[original.operands_start + 1].number}, airbitcode.IRTypedOperand{...mask, number: bodies.scopes[index + 1].base_id}, airbitcode.IRTypedOperand{...mask, number: 0}, airbitcode.IRTypedOperand{...mask, type_index: original.result_type}] {
			p.operands[mask_slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { mask_controls++; continue }; panic('accepted nonconstant/mistyped class mask')
		}; p.operands[mask_slot] = mask
		value := pools.lookup(index + 1, mask.number)!; constant := pools.constants[value.constant_index]
		mut altered_constants := pools.constants.clone(); mut altered_words := pools.words.clone(); defer { unsafe { altered_constants.free(); altered_words.free() } }
		altered_pools := airbitcode.IRConstantPools{...pools, constants: altered_constants, words: altered_words}
		for changed in [airbitcode.IRConstant{...constant, kind: .poison}, airbitcode.IRConstant{...constant, kind: .undef}, airbitcode.IRConstant{...constant, kind: .opaque}, airbitcode.IRConstant{...constant, splat: true}, airbitcode.IRConstant{...constant, type_index: original.result_type}] {
			altered_constants[value.constant_index] = changed
			p.run_scalar_function(ir, stream, altered_pools, bodies, index, args, 64) or { mask_controls++; continue }; panic('accepted invalid classification mask constant')
		}; altered_constants[value.constant_index] = constant
		for bad in [u64(1024), 0xffffffff, 0x100000000]! {
			altered_words[constant.words_start] = bad
			p.run_scalar_function(ir, stream, altered_pools, bodies, index, args, 64) or { mask_controls++; continue }; panic('accepted out-of-range class mask')
		}
		baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!
		for changed in [airbitcode.IRScalarRun{...baseline, value: 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 32}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] {
			compare(changed, 0) or { result_controls++; continue }; panic('accepted corrupted class result')
		}
		for mode in [C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
			if C.fesetround(mode) != 0 { panic('cannot set class environment control') }
			for i in 0 .. 4 {
				masks := [u32(1), 2, 128, 32]!; inputs := [if bits == 16 { u64(0x7c01) } else { u64(0x7f800001) }, if bits == 16 { u64(0xfc01) } else { u64(0xff800001) }, u64(1), u64(1) << (bits - 1)]!
				control_name := 'class_${bits}_${masks[i]}'; reference_name := 'reference_${control_name}'; defer { unsafe { control_name.free(); reference_name.free() } }
				address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing class environment reference') }; reference := unsafe { NativeBits(voidptr(address)) }
				control_args := [inputs[i]]; defer { unsafe { control_args.free() } }
				if C.feclearexcept(C.FE_ALL_EXCEPT) != 0 { panic('cannot clear FP exceptions') }
				actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, control_name)!, control_args, 64)!
				compare(actual, if i == 1 { u64(0) } else { u64(1) })!; compare(actual, reference(inputs[i]))!
				if C.fetestexcept(C.FE_ALL_EXCEPT) != 0 { panic('classification raised FP exception') }; environment_controls++
			}
		}; if C.fesetround(C.FE_TONEAREST) != 0 { panic('cannot restore class rounding mode') }
	}
	if metadata_controls != 18 || mask_controls != 24 || result_controls != 10 || environment_controls != 24 { panic('classification controls incomplete') }
	println('LLVM-FPCLASS: ${cases.len} functions, ${comparisons} exact native LLVM comparisons, ${poison_controls} poison/${undef_controls} undef/${flow_controls} branch-PHI/${metadata_controls} metadata-budget/${mask_controls} mask/${result_controls} result-corruption/${environment_controls} environment-exception controls PASS; no AIR shader or iOS app executed')
}
