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
fn C.feraiseexcept(int) int
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeRound = fn (voidptr, voidptr)
struct RoundCase { name string bits int }
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn read_word(bytes []u8, offset int, count int) u64 {
	mut word := u64(0); for j in 0 .. count { word |= u64(bytes[offset + j]) << u32(8 * j) }; return word
}
fn compare(actual []u8, expected []u8, bits int) bool {
	count := bits / 8; a := read_word(actual, 3, count); b := read_word(expected, 3, count)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; sign := u64(1) << u32(bits - 1)
	nan := b & (sign - 1) > inf
	if nan { assert a == if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }, 'preferred NaN differs' } else { assert a == b, 'finite/zero/infinity bits differ: ${a.hex()} vs ${b.hex()}' }
	for j in 0 .. 16 { if j < 3 || j >= 3 + count { assert actual[j] == 0xcc && expected[j] == 0xcc } }; return nan
}
fn main() {
	assert os.args.len == 3 || (os.args.len == 4 && os.args[3] == 'sqrt')
	square_root := os.args.len == 4
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	saved_rounding := C.fegetround(); saved_flags := C.fetestexcept(C.FE_ALL_EXCEPT); assert saved_rounding >= 0
	defer { assert C.fesetround(saved_rounding) == 0; assert C.feclearexcept(C.FE_ALL_EXCEPT) == 0; if saved_flags != 0 { assert C.feraiseexcept(saved_flags) == 0 } }
	assert C.fesetround(C.FE_TONEAREST) == 0
	mut source := strings.new_builder(32768); mut cases := []RoundCase{}
	for bits in [16, 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		if square_root { source.write_string('declare ${typ} @llvm.fabs.f${bits}(${typ})\n') }
		for op in if square_root { ['sqrt'] } else { ['floor', 'ceil', 'trunc', 'round', 'roundeven', 'rint', 'nearbyint'] } {
			name := '${op}_${bits}'; cases << RoundCase{name, bits}
			source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ})\ndefine void @${name}(ptr %a, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %x)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			first := if square_root { 'fabs' } else { op }
			source.write_string('define void @chain_${name}(ptr %a, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %first = call ${typ} @llvm.${first}.f${bits}(${typ} %x)\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %first)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			source.write_string('define void @cached_${name}(ptr %a, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %first = call ${typ} @llvm.${op}.f${bits}(${typ} %x)\n store ${typ} %first, ptr %dst, align 1\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %first)\n ret void }\n')
			for state in ['poison', 'undef'] { source.write_string('define void @guard_${state}_${name}(ptr %dst) { %v = call ${typ} @llvm.${op}.f${bits}(${typ} ${state})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n') }
			for mode in ['freeze', 'select'] {
				choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1.0' }
				source.write_string('define void @${mode}_${name}(ptr %dst) { %bad = call ${typ} @llvm.${op}.f${bits}(${typ} poison)\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			}
		}
	}
	preflight_op := if square_root { 'sqrt' } else { 'floor' }
	source.write_string('define void @preflight(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call float @llvm.${preflight_op}.f32(float 1.0)\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'rounding'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
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
	// Both signs of zero/subnormal/infinity/NaNs, neighbors of half ties, and
	// the last fractional and first integral-only binades, expanded to both signs.
	edges := [u32(0), 1, 0x007fffff, 0x00800000, 0x3effffff, 0x3f000000, 0x3f000001, 0x3f7fffff, 0x3f800000, 0x3f800001, 0x3fbfffff, 0x3fc00000, 0x3fc00001, 0x3fffffff, 0x40000000, 0x40000001, 0x401fffff, 0x40200000, 0x40200001, 0x405fffff, 0x40600000, 0x40600001, 0x4affffff, 0x4b000000, 0x4b000001, 0x4b7fffff, 0x7f7fffff, 0x7f800000, 0x7f800001, 0x7fc00000, 0x7fc12345, 0x7fffffff]!
	mut comparisons := 0; mut boundaries := 0; mut nan_cases := 0; mut chains := 0; mut mode_controls := 0; mut environments := 0; mut cached_metadata := 0; mut types := 0
	for c in cases {
		function := find_function(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		chain_name := 'chain_' + c.name; chain := find_function(ir, chain_name); chain_address := C.LLVMGetFunctionAddress(engine, chain_name.str); assert chain_address != 0
		count := c.bits / 8; extra := if c.bits == 32 { if square_root { 196672 } else { 64 } } else { 0 }
		mut left := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
		for sample in 0 .. 65536 + extra {
			mut a := if c.bits == 16 { u64(sample) } else { u64(u32(sample) * u32(0x9e3779b9)) }
			if sample >= 65536 {
				if sample < 65600 { a = u64(edges[(sample - 65536) / 2]) | if sample % 2 != 0 { u64(0x80000000) } else { u64(0) } }
				else {
					// Square a midpoint between neighboring float roots using only
					// integer products/shifts, then test the input below/at/above it.
					// Even input exponents span the entire normal range.
					index := (sample - 65600) / 3
					midpoint := (u64(1) << 24) | ((u64(index) * 0x9e3779b9 & 0x7fffff) << 1) | 1
					square := midpoint * midpoint; wide := int(square >= u64(1) << 49)
					exponent := 127 + 2 * (index % 127 - 63) + wide
					floor_bits := (u32(exponent) << 23) | (u32(square >> (25 + wide)) & 0x7fffff)
					a = u64(i64(floor_bits) + (sample - 65600) % 3 - 1)
				}; boundaries++
			}
			for j in 0 .. count { left[1 + j] = u8(a >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4
			unsafe { NativeRound(voidptr(address))(&left[1], &expected[3]) }; if compare(actual, expected, c.bits) { nan_cases++ }
			if sample < 2 || sample >= 65536 {
				for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			}
			if square_root || sample < 128 || sample >= 65536 {
				assert p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 5)!.steps == 5
				unsafe { NativeRound(voidptr(chain_address))(&left[1], &expected[3]) }; compare(actual, expected, c.bits)
				if square_root {
					// fabs makes every defined non-NaN argument nonnegative.
					assert read_word(actual, 3, count) & (u64(1) << u32(c.bits - 1)) == 0
				} else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4; compare(actual, expected, c.bits) }; chains++
			}
			comparisons++
		}
		for raw in if c.bits == 16 { [u64(0x3e00), 0xbe00, 0x4100, 0xc100] } else { [u64(0x3fc00000), 0xbfc00000, 0x40200000, 0xc0200000] } {
			for j in 0 .. count { left[1 + j] = u8(raw >> u32(8 * j)) }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4; baseline := read_word(actual, 3, count)
			for mode in [C.FE_TONEAREST, C.FE_DOWNWARD, C.FE_UPWARD, C.FE_TOWARDZERO]! {
				assert C.fesetround(mode) == 0; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4; assert read_word(actual, 3, count) == baseline; mode_controls++
			}; assert C.fesetround(C.FE_TONEAREST) == 0
		}
		if c.name.starts_with('rint_') || c.name.starts_with('nearbyint_') {
			// Exact ties, zero signs, NaNs and tiny inputs under every host mode.
			// The default LLVM environment is simulated without touching host flags.
			inputs := if c.bits == 16 { [u64(0x4100), 0xc100, 0x3800, 0xb800, 0xfc01, 1] } else { [u64(0x40200000), 0xc0200000, 0x3f000000, 0xbf000000, 0xff800001, 1] }
			values := if c.bits == 16 { [u64(0x4000), 0xc000, 0, 0x8000, 0x7e00, 0] } else { [u64(0x40000000), 0xc0000000, 0, 0x80000000, 0x7fc00000, 0] }
			for mode in [C.FE_TONEAREST, C.FE_DOWNWARD, C.FE_UPWARD, C.FE_TOWARDZERO]! { for i, raw in inputs { for seeded in [false, true]! {
				for j in 0 .. count { left[1 + j] = u8(raw >> u32(8 * j)) }
				assert C.fesetround(mode) == 0 && C.feclearexcept(C.FE_ALL_EXCEPT) == 0
				if seeded { assert C.feraiseexcept(C.FE_DIVBYZERO) == 0 }; flags := C.fetestexcept(C.FE_ALL_EXCEPT)
				assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4 && read_word(actual, 3, count) == values[i]
				assert C.fegetround() == mode && C.fetestexcept(C.FE_ALL_EXCEPT) == flags; environments++
			} } }; assert C.fesetround(C.FE_TONEAREST) == 0
		}
		// Reject malformed later calls before their preceding store, even when
		// the exact declaration has already been validated and cached.
		cached := find_function(ir, 'cached_' + c.name); slot := bodies.scopes[cached + 1].instructions_start + 3; saved := p.instructions[slot]
		for j in 0 .. 16 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 5) { panic('cached metadata accepted') }; for byte in actual { assert byte == 0xcc }; cached_metadata++
		}; p.instructions[slot] = saved
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 32 { wrong = i; break } }; assert wrong >= 0
		operand_slot := saved.operands_start + 1; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}
		if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 5) { panic('operand type accepted') }; for byte in actual { assert byte == 0xcc }; p.operands[operand_slot] = operand; types++
		assert p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 5)!.steps == 5
		unsafe { NativeRound(voidptr(address))(&left[1], &expected[3]) }; compare(actual, expected, c.bits)
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4
		compare(actual, expected, c.bits)
		unsafe { bindings.free(); left.free(); actual.free(); expected.free() }
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
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
		p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3) { panic('metadata accepted') }; for byte in bytes { assert byte == 0xcc }; metadata++
	}; p.instructions[slot] = saved
	assert p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3)!.steps == 3 && bytes[0] == 17
	if square_root { assert cases.len == 2 && comparisons == 327744 && boundaries == 196672 && chains == 327744 && mode_controls == 32 && guards == 4 && choices == 4 && metadata == 9 && cached_metadata == 18 && types == 2 && environments == 0 }
	else { assert cases.len == 14 && comparisons == 917952 && boundaries == 448 && chains == 2240 && mode_controls == 224 && guards == 28 && choices == 28 && metadata == 9 && cached_metadata == 126 && types == 14 && environments == 192 }
	label := if square_root { 'AIR-MEMORY-SQRT' } else { 'AIR-MEMORY-ROUNDING' }
	composition := if square_root { 'sqrt/fabs compositions' } else { 'cached/idempotent chains' }
	result := '${label}: ${comparisons} native comparisons (${nan_cases} arithmetic NaN-class cases, ${boundaries} float boundaries), half/float and all half encodings, ${chains} ${composition}, ${mode_controls} host-rounding/${environments} exact default-environment and exception controls, sentinels/budgets, ${guards} poison/undef guards, ${choices} freeze/lazy choices and ${metadata}/${cached_metadata} initial/cached metadata plus ${types} operand-type controls PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
