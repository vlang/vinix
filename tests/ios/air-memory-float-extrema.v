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
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeExtrema = fn (voidptr, voidptr, voidptr)
struct ExtremaCase { name string bits int }
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn read_word(bytes []u8, count int) u64 {
	mut word := u64(0); for j in 0 .. count { word |= u64(bytes[4 + j]) << u32(8 * j) }; return word
}
fn compare(actual []u8, expected []u8, bits int, nan bool) {
	count := bits / 8; a := read_word(actual, count); b := read_word(expected, count)
	sign := u64(1) << u32(bits - 1); inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	if nan { assert b & (sign - 1) > inf && a == if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }, 'NaN class/preferred representation differs' }
	else { assert a == b, 'defined raw bits differ: ${a.hex()} vs ${b.hex()}' }
	for j in 0 .. 16 { if j < 4 || j >= 4 + count { assert actual[j] == 0xcc && expected[j] == 0xcc } }
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(32768); mut cases := []ExtremaCase{}
	for bits in [16, 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		for op in ['minimum', 'maximum'] { source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ}, ${typ})\n') }
		for op in ['minimum', 'maximum'] {
			name := '${op}_${bits}'; cases << ExtremaCase{name, bits}; second := if op == 'minimum' { 'maximum' } else { 'minimum' }
			source.write_string('define void @${name}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			// Repeated declaration followed by the other family; without NaNs,
			// max(min(min(x,y),y),x) and its dual must return the exact x bits.
			source.write_string('define void @chain_${name}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %first = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y)\n %again = call ${typ} @llvm.${op}.f${bits}(${typ} %first, ${typ} %y)\n %v = call ${typ} @llvm.${second}.f${bits}(${typ} %again, ${typ} %x)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			for state in ['poison', 'undef'] { for side in 0 .. 2 {
				a := if side == 0 { state } else { '0.0' }; b := if side == 1 { state } else { '0.0' }
				source.write_string('define void @guard_${state}_${side}_${name}(ptr %dst) { %v = call ${typ} @llvm.${op}.f${bits}(${typ} ${a}, ${typ} ${b})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			} }
			for mode in ['freeze', 'select'] {
				choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1.0' }
				source.write_string('define void @${mode}_${name}(ptr %dst) { %bad = call ${typ} @llvm.${op}.f${bits}(${typ} poison, ${typ} 0.0)\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			}
		}
	}
	source.write_string('define void @preflight(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call float @llvm.minimum.f32(float 1.0, float 2.0)\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'float-extrema'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
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
	mut comparisons := 0; mut boundaries := 0; mut nan_cases := 0; mut chains := 0
	for c in cases {
		function := find_function(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		chain_name := 'chain_' + c.name; chain := find_function(ir, chain_name); chain_address := C.LLVMGetFunctionAddress(engine, chain_name.str); assert chain_address != 0
		count := c.bits / 8; sign := u64(1) << u32(c.bits - 1); inf := if c.bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
		one := if c.bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }; normal := if c.bits == 16 { u64(0x400) } else { u64(0x800000) }
		quiet := if c.bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }; half := if c.bits == 16 { u64(0x3800) } else { u64(0x3f000000) }
		edges := [u64(0), sign, 1, sign | 1, normal - 1, sign | (normal - 1), normal, sign | normal, one, sign | one, one + 1, sign | (one + 1), inf - 1, sign | (inf - 1), inf, sign | inf, inf + 1, sign | (inf + 1), quiet, sign | quiet, quiet + 0x55, sign | (quiet + 0x55), half, sign | half]!
		samples := if c.bits == 16 { 262144 } else { 65536 }
		mut left := []u8{len: 16}; mut right := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. samples + 576 {
			mut a := if c.bits == 16 { u64(sample / 4) } else { u64(u32(sample) * u32(0x9e3779b9)) }
			mut b := if c.bits == 16 { [u64(0), sign, one, sign | one]![sample % 4] } else { u64(u32(sample) * u32(0x85ebca6b) ^ u32(0xa5a5a5a5)) }
			if sample >= samples { a = edges[(sample - samples) / 24]; b = edges[(sample - samples) % 24]; boundaries++ }
			nan := a & (sign - 1) > inf || b & (sign - 1) > inf
			for j in 0 .. count { left[1 + j] = u8(a >> u32(8 * j)); right[2 + j] = u8(b >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5
			unsafe { NativeExtrema(voidptr(address))(&left[1], &right[2], &expected[4]) }; compare(actual, expected, c.bits, nan)
			if nan { nan_cases++ } else { assert read_word(actual, count) == a || read_word(actual, count) == b }
			if sample < 4 || sample >= samples {
				for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			}
			assert p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 7)!.steps == 7
			unsafe { NativeExtrema(voidptr(chain_address))(&left[1], &right[2], &expected[4]) }; compare(actual, expected, c.bits, nan)
			if !nan { assert read_word(actual, count) == a, 'mixed chain must restore exact first input' }; chains++; comparisons++
		}
		unsafe { bindings.free(); left.free(); right.free(); actual.free(); expected.free() }
	}
	mut guards := 0; mut choices := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && !f.name.starts_with('freeze_') && !f.name.starts_with('select_') { continue }
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 3) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_poison_') { assert err.msg() == 'AIR memory execution: poison store', err.msg() } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			bits := if f.name.ends_with('_16') { 16 } else { 32 }; count := bits / 8
			want := if f.name.starts_with('select_') { if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) } } else { u64(0) }
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			for j in 0 .. 16 { assert bytes[j] == if j >= 1 && j < 1 + count { u8(want >> u32(8 * (j - 1))) } else { u8(0xcc) }, f.name }; choices++
		}
		unsafe { bytes.free(); bindings.free() }
	}
	anchor := find_function(ir, 'preflight'); slot := bodies.scopes[anchor + 1].instructions_start + 1; saved := p.instructions[slot]; mut metadata := 0
	mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
		p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3) { panic('metadata accepted') }; for byte in bytes { assert byte == 0xcc }; metadata++
	}; p.instructions[slot] = saved
	assert p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3)!.steps == 3 && bytes[0] == 17
	assert cases.len == 4 && comparisons == 657664 && boundaries == 2304 && chains == 657664 && guards == 16 && choices == 8 && metadata == 9
	result := 'AIR-MEMORY-FLOAT-EXTREMA: ${comparisons} native comparisons (${nan_cases} arithmetic NaN-class cases, ${boundaries} boundary pairs), all half encodings with four anchors, half/float minimum/maximum, ${chains} native/identity mixed cached chains, sentinels/budgets, ${guards} poison/undef guards, ${choices} freeze/lazy choices and ${metadata} metadata controls PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
