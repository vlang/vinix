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
fn C.LLVMDisposeMessage(&char)
fn C.LLVMVerifyModule(voidptr, int, &&char) int
fn C.LLVMInitializeNativeTarget() int
fn C.LLVMInitializeNativeAsmPrinter() int
fn C.LLVMGetDefaultTargetTriple() &char
fn C.LLVMSetTarget(voidptr, &char)
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
fn C.fegetround() int
fn C.fesetround(int) int
fn C.feclearexcept(int) int
fn C.fetestexcept(int) int
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeClass = fn (voidptr, voidptr)
struct ClassCase { name string bits int mask int }
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn reject(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, function int, mut bindings []airbitcode.IRMemoryBinding) {
	if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5) { panic('invalid cached call accepted') }
	for byte in bindings[1].data { assert byte == 0xcc, 'preflight wrote before rejection' }
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	saved_rounding := C.fegetround(); assert saved_rounding >= 0; defer { assert C.fesetround(saved_rounding) == 0 }; assert C.fesetround(C.FE_TONEAREST) == 0
	mut source := strings.new_builder(1048576); mut cases := []ClassCase{}
	for bits in [16, 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		source.write_string('declare i1 @llvm.is.fpclass.f${bits}(${typ}, i32 immarg)\n')
		for mask in 0 .. 1024 {
			name := 'class_${bits}_${mask}'; cases << ClassCase{name, bits, mask}
			source.write_string('define void @${name}(ptr %a, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %v = call i1 @llvm.is.fpclass.f${bits}(${typ} %x, i32 ${mask})\n store i1 %v, ptr %dst, align 1\n ret void }\n')
		}
		for mask in [0, 3, 1023]! { for state in ['poison', 'undef'] {
			source.write_string('define void @guard_${state}_${bits}_${mask}(ptr %dst) { %v = call i1 @llvm.is.fpclass.f${bits}(${typ} ${state}, i32 ${mask})\n store i1 %v, ptr %dst, align 1\n ret void }\n')
		} }
		for mask in [0, 1023]! { for mode in ['freeze', 'select'] {
			choice := if mode == 'freeze' { 'freeze i1 %bad' } else { 'select i1 false, i1 %bad, i1 true' }
			source.write_string('define void @${mode}_${bits}_${mask}(ptr %dst) { %bad = call i1 @llvm.is.fpclass.f${bits}(${typ} poison, i32 ${mask})\n %v = ${choice}\n store i1 %v, ptr %dst, align 1\n ret void }\n')
		} }
		// Second call must recheck its immediate despite a cached declaration
		// and despite a preceding store. Keep the two masks distinct in pools.
		source.write_string('define void @cached_${bits}(ptr %a, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %first = call i1 @llvm.is.fpclass.f${bits}(${typ} %x, i32 64)\n store i1 %first, ptr %dst, align 1\n %last = call i1 @llvm.is.fpclass.f${bits}(${typ} %x, i32 3)\n ret void }\n')
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'fpclass'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures()
	os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut native_function := C.LLVMGetFirstFunction(module_ptr)
	for native_function != unsafe { nil } { C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-cpu', cpu); C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-features', features); native_function = C.LLVMGetNextFunction(native_function) }
	C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	// Two independently labeled representatives of each of the ten classes.
	half_edges := [u64(0x7c01), 0xfcff, 0x7e00, 0xffff, 0xfc00, 0xfc00, 0x8400, 0xfbff, 0x8001, 0x83ff, 0x8000, 0x8000, 0, 0, 1, 0x3ff, 0x400, 0x7bff, 0x7c00, 0x7c00]!
	float_edges := [u64(0x7f800001), 0xffbfffff, 0x7fc00000, 0xffffffff, 0xff800000, 0xff800000, 0x80800000, 0xff7fffff, 0x80000001, 0x807fffff, 0x80000000, 0x80000000, 0, 0, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0x7f800000, 0x7f800000]!
	mut comparisons := 0; mut boundaries := 0; mut environments := 0
	for c in cases {
		function := find_function(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		count := c.bits / 8; exhaustive := c.mask in [0, 1023, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512]!
		mut left := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
		for sample in 0 .. 20 + if exhaustive { 65536 } else { 0 } {
			a := if sample < 20 { if c.bits == 16 { half_edges[sample] } else { float_edges[sample] } } else if c.bits == 16 { u64(sample - 20) } else { u64(u32(sample - 20) * u32(0x9e3779b9)) }
			for j in 0 .. count { left[1 + j] = u8(a >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4
			unsafe { NativeClass(voidptr(address))(&left[1], &expected[3]) }
			assert actual[3] <= 1 && actual[3] == expected[3] & 1, c.name
			for j in 0 .. 16 { if j != 3 { assert actual[j] == 0xcc && expected[j] == 0xcc } }
			if sample < 20 { assert actual[3] == u8(c.mask & (1 << (sample / 2)) != 0); boundaries++ }
			if sample == 0 { actual[3] = 0xcc; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc } }
			comparisons++
		}
		unsafe { bindings.free(); left.free(); actual.free(); expected.free() }
	}
	mut guards := 0; mut choices := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && !f.name.starts_with('freeze_') && !f.name.starts_with('select_') { continue }
		mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 3) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_poison_') { assert err.msg() == 'AIR memory execution: poison store' } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			for j in 0 .. 8 { assert bytes[j] == if j == 1 { u8(f.name.starts_with('select_')) } else { u8(0xcc) } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	mut metadata := 0; mut masks := 0
	for bits in [16, 32]! {
		function := find_function(ir, 'cached_${bits}'); scope := function + 1; slot := bodies.scopes[scope].instructions_start + 3; saved := p.instructions[slot]
		mut left := []u8{len: 8}; mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: left}, airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
			p.instructions[slot] = changed; reject(p, ir, stream, pools, bodies, function, mut bindings); metadata++
		}; p.instructions[slot] = saved
		mask_slot := saved.operands_start + 2; mask := p.operands[mask_slot]
		for changed in [airbitcode.IRTypedOperand{...mask, number: p.operands[saved.operands_start + 1].number}, airbitcode.IRTypedOperand{...mask, number: pools.module_values}, airbitcode.IRTypedOperand{...mask, number: 0}, airbitcode.IRTypedOperand{...mask, type_index: saved.result_type}] {
			p.operands[mask_slot] = changed; reject(p, ir, stream, pools, bodies, function, mut bindings); masks++
		}; p.operands[mask_slot] = mask
		value := pools.lookup(scope, mask.number)!; constant := pools.constants[value.constant_index]
		mut constants := pools.constants.clone(); mut words := pools.words.clone(); altered := airbitcode.IRConstantPools{...pools, constants: constants, words: words}
		for changed in [airbitcode.IRConstant{...constant, kind: .poison}, airbitcode.IRConstant{...constant, kind: .undef}, airbitcode.IRConstant{...constant, kind: .opaque}, airbitcode.IRConstant{...constant, splat: true}, airbitcode.IRConstant{...constant, type_index: saved.result_type}] {
			constants[value.constant_index] = changed; reject(p, ir, stream, altered, bodies, function, mut bindings); masks++
		}; constants[value.constant_index] = constant
		for bad in [u64(1024), 0xffffffff, 0x100000000]! { words[constant.words_start] = bad; reject(p, ir, stream, altered, bodies, function, mut bindings); masks++ }
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5 && bytes[1] == 1
		unsafe { constants.free(); words.free(); left.free(); bytes.free(); bindings.free() }
		for mode in [C.FE_TONEAREST, C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! { for sample in 0 .. 4 {
			assert C.fesetround(mode) == 0
			mask_value := [1, 2, 128, 32]![sample]; name := 'class_${bits}_${mask_value}'; index := find_function(ir, name); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0
			a := if sample < 2 { if bits == 16 { u64(0x7c01) | (u64(sample) << 15) } else { u64(0x7f800001) | (u64(sample) << 31) } } else if sample == 2 { u64(1) } else { u64(1) << u32(bits - 1) }
			mut input := []u8{len: 8}; mut actual := []u8{len: 8, init: 0xcc}; mut expected := actual.clone(); mut args := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
			for j in 0 .. bits / 8 { input[j] = u8(a >> u32(8 * j)) }
			assert C.feclearexcept(C.FE_ALL_EXCEPT) == 0
			assert p.run_memory_function(ir, stream, pools, bodies, index, mut args, 4)!.steps == 4 && actual[0] == u8(sample != 1)
			assert C.fetestexcept(C.FE_ALL_EXCEPT) == 0
			unsafe { NativeClass(voidptr(address))(&input[0], &expected[0]) }; assert actual[0] == expected[0] & 1 && C.fetestexcept(C.FE_ALL_EXCEPT) == 0; environments++
			unsafe { input.free(); actual.free(); expected.free(); args.free() }
		} }; assert C.fesetround(C.FE_TONEAREST) == 0
	}
	assert cases.len == 2048 && comparisons == 1613824 && boundaries == 40960 && guards == 12 && choices == 8 && metadata == 18 && masks == 24 && environments == 32
	result := 'AIR-MEMORY-FPCLASS: ${comparisons} exact native comparisons, ${boundaries} independently labeled class/mask boundaries, all 1024 masks and half/float, exhaustive half/sampled float under 12 masks, i1 padding/sentinels/budgets, ${guards} poison/undef guards, ${choices} freeze/lazy choices, ${metadata} metadata/${masks} immediate controls after a cached call/store, ${environments} rounding/exception controls PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
