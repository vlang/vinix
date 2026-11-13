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
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeScale = fn (voidptr, voidptr, voidptr)
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn word(bytes []u8, count int) u64 {
	mut value := u64(0); for j in 0 .. count { value |= u64(bytes[4 + j]) << u32(8 * j) }; return value
}
fn compare(actual []u8, expected []u8, bits int) bool {
	count := bits / 8; a := word(actual, count); b := word(expected, count)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; sign := u64(1) << u32(bits - 1); nan := b & (sign - 1) > inf
	if nan { assert a == if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }, 'preferred NaN differs' } else { assert a == b, 'ldexp bits differ: ${a.hex()} vs ${b.hex()}' }
	for j in 0 .. 16 { if j < 4 || j >= 4 + count { assert actual[j] == 0xcc && expected[j] == 0xcc } }; return nan
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	saved_mode := C.fegetround(); assert saved_mode >= 0; defer { assert C.fesetround(saved_mode) == 0 }; assert C.fesetround(C.FE_TONEAREST) == 0
	mut source := strings.new_builder(32768)
	for bits in [16, 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		source.write_string('declare ${typ} @llvm.ldexp.f${bits}.i32(${typ}, i32)\n')
		for mode in ['scale', 'chain', 'cached'] {
			body := if mode == 'chain' { '%first = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} %x, i32 %e)\n %v = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} %first, i32 0)\n store ${typ} %v, ptr %dst, align 1\n' } else if mode == 'cached' { '%first = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} %x, i32 %e)\n store ${typ} %first, ptr %dst, align 1\n %v = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} %first, i32 %e)\n' } else { '%v = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} %x, i32 %e)\n store ${typ} %v, ptr %dst, align 1\n' }
			source.write_string('define void @${mode}_${bits}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %e = load i32, ptr %b, align 1\n ${body}ret void }\n')
		}
		for state in ['poison', 'undef'] { for side in 0 .. 2 {
			a := if side == 0 { state } else { '0.0' }; b := if side == 1 { state } else { '0' }
			source.write_string('define void @guard_${state}_${side}_${bits}(ptr %dst) { %v = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} ${a}, i32 ${b})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
		} }
		for mode in ['freeze', 'select'] {
			choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1.0' }
			source.write_string('define void @${mode}_${bits}(ptr %dst) { %bad = call ${typ} @llvm.ldexp.f${bits}.i32(${typ} 0.0, i32 poison)\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
		}
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'ldexp'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures(); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut native_function := C.LLVMGetFirstFunction(module_ptr)
	for native_function != unsafe { nil } { C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-cpu', cpu); C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-features', features); native_function = C.LLVMGetNextFunction(native_function) }
	C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0; mut boundaries := 0; mut chains := 0; mut nan_cases := 0; mut modes := 0; mut metadata := 0; mut types := 0
	for bits in [16, 32]! {
		function := find_function(ir, 'scale_${bits}'); chain := find_function(ir, 'chain_${bits}'); cached := find_function(ir, 'cached_${bits}')
		address := C.LLVMGetFunctionAddress(engine, 'scale_${bits}'.str); chain_address := C.LLVMGetFunctionAddress(engine, 'chain_${bits}'.str); assert address != 0 && chain_address != 0
		count := bits / 8; sign := u64(1) << u32(bits - 1); one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }; inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
		normal := if bits == 16 { u64(0x400) } else { u64(0x800000) }; quiet := if bits == 16 { u64(0x7e55) } else { u64(0x7fc12345) }; half := if bits == 16 { u64(0x3800) } else { u64(0x3f000000) }
		edges := [u64(0), sign, 1, sign | 1, 3, sign | 3, normal - 1, sign | (normal - 1), normal, sign | normal, one, sign | one, one + 1, sign | (one + 1), inf - 1, sign | (inf - 1), inf, sign | inf, inf + 1, sign | (inf + 1), quiet, sign | quiet, half, sign | half]!
		scales := [u32(0x80000000), u32(-513), u32(-512), u32(-150), u32(-25), u32(-24), u32(-1), 0, 1, 14, 15, 24, 127, 128, 512, 0x7fffffff]!
		mut a := []u8{len: 16}; mut b := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. 327680 + 384 {
			index := sample % 65536; mut x := if bits == 16 { u64(index) } else { u64(u32(index) * u32(0x9e3779b9)) }; mut e := [u32(-25), u32(-1), u32(0), 1, 24]![sample / 65536 % 5]
			if sample >= 327680 { k := sample - 327680; x = edges[k / 16]; e = scales[k % 16]; boundaries++ }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)) }; for j in 0 .. 4 { b[2 + j] = u8(e >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5
			unsafe { NativeScale(voidptr(address))(&a[1], &b[2], &expected[4]) }; if compare(actual, expected, bits) { nan_cases++ }
			if sample < 2 || sample >= 327680 { for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc } }
			if sample < 128 || sample >= 327680 {
				assert p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 6)!.steps == 6
				unsafe { NativeScale(voidptr(chain_address))(&a[1], &b[2], &expected[4]) }; compare(actual, expected, bits)
				assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5; compare(actual, expected, bits); chains++
			}; comparisons++
		}
		// Exact subnormal tie and sign expectations, independent of the packer.
		for row in [[u64(3), 0xffffffff, 2], [sign | 3, u64(0xffffffff), sign | 2], [sign | 1, u64(0xffffffff), sign]] {
			for j in 0 .. count { a[1 + j] = u8(row[0] >> u32(8 * j)) }; for j in 0 .. 4 { b[2 + j] = u8(row[1] >> u32(8 * j)) }
			for mode in [C.FE_TONEAREST, C.FE_DOWNWARD, C.FE_UPWARD, C.FE_TOWARDZERO]! { assert C.fesetround(mode) == 0; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5 && word(actual, count) == row[2]; modes++ }; assert C.fesetround(C.FE_TONEAREST) == 0
		}
		// Validate the later cached call before allowing its preceding store.
		slot := bodies.scopes[cached + 1].instructions_start + 4; saved := p.instructions[slot]
		for j in 0 .. 16 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6) { panic('metadata accepted') }; for byte in actual { assert byte == 0xcc }; metadata++
		}; p.instructions[slot] = saved
		mut i1 := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 1 { i1 = i; break } }; assert i1 >= 0
		exponent_slot := saved.operands_start + 2; exponent := p.operands[exponent_slot]
		for wrong in [saved.result_type, i1]! { p.operands[exponent_slot] = airbitcode.IRTypedOperand{...exponent, type_index: wrong}; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6) { panic('exponent type accepted') }; for byte in actual { assert byte == 0xcc }; types++ }; p.operands[exponent_slot] = exponent
		assert p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6)!.steps == 6 && word(actual, count) == sign
		unsafe { a.free(); b.free(); actual.free(); expected.free(); bindings.free() }
	}
	mut guards := 0; mut choices := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && !f.name.starts_with('freeze_') && !f.name.starts_with('select_') { continue }
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 3) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_poison_') { assert err.msg() == 'AIR memory execution: poison store' } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			bits := if f.name.ends_with('_16') { 16 } else { 32 }; count := bits / 8; want := if f.name.starts_with('select_') { if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) } } else { u64(0) }
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			for j in 0 .. 16 { assert bytes[j] == if j >= 1 && j < 1 + count { u8(want >> u32(8 * (j - 1))) } else { u8(0xcc) } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	assert comparisons == 656128 && boundaries == 768 && chains == 1024 && modes == 24 && metadata == 18 && types == 4 && guards == 8 && choices == 4
	result := 'AIR-MEMORY-LDEXP: ${comparisons} native comparisons (${nan_cases} arithmetic NaN-class cases, ${boundaries} value/exponent boundaries), exhaustive half/sampled float under five signed scales, ${chains} cached zero-scale chains, ${modes} tie/rounding controls, sentinels/budgets, ${metadata} metadata/${types} exponent-type controls after cached call/store, ${guards} poison/undef guards and ${choices} freeze/lazy choices PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
