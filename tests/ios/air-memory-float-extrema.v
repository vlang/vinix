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
		for op in ['minimum', 'maximum', 'minimumnum', 'maximumnum', 'minnum', 'maxnum'] { source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ}, ${typ})\n') }
		for op in ['minimum', 'maximum', 'minimumnum', 'maximumnum', 'minnum', 'maxnum'] {
			name := '${op}_${bits}'; cases << ExtremaCase{name, bits}; second := match op { 'minimum' { 'maximum' } 'maximum' { 'minimum' } 'minimumnum' { 'maximumnum' } 'maximumnum' { 'minimumnum' } 'minnum' { 'maxnum' } else { 'minnum' } }
			source.write_string('define void @${name}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			// Repeated declaration followed by the other family; without NaNs,
			// max(min(min(x,y),y),x) and its dual must return the exact x bits.
			source.write_string('define void @chain_${name}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %first = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y)\n %again = call ${typ} @llvm.${op}.f${bits}(${typ} %first, ${typ} %y)\n %v = call ${typ} @llvm.${second}.f${bits}(${typ} %again, ${typ} %x)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			source.write_string('define void @cached_${name}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %first = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y)\n store ${typ} %first, ptr %dst, align 1\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %first, ${typ} %y)\n ret void }\n')
			for state in ['poison', 'undef'] { for side in 0 .. 2 { for other in 0 .. 2 {
				constant := if other == 0 { '0.0' } else if bits == 16 { '0xH7E55' } else { '0x7FF8000000000000' }
				a := if side == 0 { state } else { constant }; b := if side == 1 { state } else { constant }
				source.write_string('define void @guard_${state}_${side}_${other}_${name}(ptr %dst) { %v = call ${typ} @llvm.${op}.f${bits}(${typ} ${a}, ${typ} ${b})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			} } }
			for mode in ['freeze', 'select'] {
				choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1.0' }
				source.write_string('define void @${mode}_${name}(ptr %dst) { %bad = call ${typ} @llvm.${op}.f${bits}(${typ} poison, ${typ} 0.0)\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			}
		}
		for mode in ['mixed', 'mixed_reference'] {
			minop := if mode == 'mixed' { 'minnum' } else { 'minimumnum' }; maxop := if mode == 'mixed' { 'maxnum' } else { 'maximumnum' }
			source.write_string('define void @${mode}_${bits}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %a0 = call ${typ} @llvm.${minop}.f${bits}(${typ} %x, ${typ} %y)\n %a1 = call ${typ} @llvm.minimumnum.f${bits}(${typ} %a0, ${typ} %y)\n %a2 = call ${typ} @llvm.${maxop}.f${bits}(${typ} %a1, ${typ} %x)\n %v = call ${typ} @llvm.maximumnum.f${bits}(${typ} %a2, ${typ} %y)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
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
	mut comparisons := 0; mut boundaries := 0; mut nan_cases := 0; mut chains := 0; mut cached_metadata := 0; mut mixed_chains := 0
	mut diagnostics := os.create(out + '/legacy-native.tsv')!; defer { diagnostics.close() }
	diagnostics.writeln('function\ta\tb\tnative\trefinement\tsnan_choice\tzero_violation')!
	mut legacy_cases := 0; mut snan_choices := 0; mut zero_violations := 0
	for c in cases {
		// Qualify the chosen number-preferring refinement with modern native calls.
		// Actual native legacy choices are retained separately, never used to relax it.
		legacy := c.name.starts_with('minnum_') || c.name.starts_with('maxnum_')
		reference_name := c.name.replace('minnum_', 'minimumnum_').replace('maxnum_', 'maximumnum_')
		function := find_function(ir, c.name); address := C.LLVMGetFunctionAddress(engine, reference_name.str); assert address != 0
		chain_name := 'chain_' + c.name; chain := find_function(ir, chain_name); reference_chain := 'chain_' + reference_name
		chain_address := C.LLVMGetFunctionAddress(engine, reference_chain.str); assert chain_address != 0
		legacy_address := if legacy { C.LLVMGetFunctionAddress(engine, c.name.str) } else { u64(0) }; assert !legacy || legacy_address != 0
		mixed := find_function(ir, 'mixed_${c.bits}'); mixed_address := C.LLVMGetFunctionAddress(engine, 'mixed_reference_${c.bits}'.str); assert mixed_address != 0
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
			left_nan := a & (sign - 1) > inf; right_nan := b & (sign - 1) > inf
			nan := if legacy || c.name.starts_with('minimumnum_') || c.name.starts_with('maximumnum_') { left_nan && right_nan } else { left_nan || right_nan }
			for j in 0 .. count { left[1 + j] = u8(a >> u32(8 * j)); right[2 + j] = u8(b >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5
			unsafe { NativeExtrema(voidptr(address))(&left[1], &right[2], &expected[4]) }; compare(actual, expected, c.bits, nan)
			if nan { nan_cases++ } else { assert read_word(actual, count) == a || read_word(actual, count) == b }
			if legacy && sample >= samples {
				mut native := []u8{len: 16, init: 0xcc}; unsafe { NativeExtrema(voidptr(legacy_address))(&left[1], &right[2], &native[4]) }
				value := read_word(native, count); reference := read_word(expected, count); quiet_bit := quiet ^ inf
				native_nan := value & (sign - 1) > inf
				snan := (left_nan && a & quiet_bit == 0) || (right_nan && b & quiet_bit == 0)
				choice := native_nan && !nan && snan; zero := a & (sign - 1) == 0 && b & (sign - 1) == 0 && value != reference
				assert value == reference || (native_nan && nan) || choice || zero, 'unexpected native legacy mismatch'
				for j in 0 .. 16 { if j < 4 || j >= 4 + count { assert native[j] == 0xcc } }
				row := '${c.name}\t${a}\t${b}\t${value}\t${reference}\t${choice}\t${zero}'; diagnostics.writeln(row)!
				if choice { snan_choices++ }; if zero { zero_violations++ }; legacy_cases++
				unsafe { native.free(); row.free() }
			}
			if sample < 4 || sample >= samples {
				for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			}
			assert p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 7)!.steps == 7
			unsafe { NativeExtrema(voidptr(chain_address))(&left[1], &right[2], &expected[4]) }; compare(actual, expected, c.bits, nan)
			if !nan { assert read_word(actual, count) == if left_nan { b } else { a }, 'mixed chain must restore exact first numeric input' }; chains++; comparisons++
			if c.name.starts_with('minnum_') && (sample < 128 || sample >= samples) {
				assert p.run_memory_function(ir, stream, pools, bodies, mixed, mut bindings, 8)!.steps == 8
				unsafe { NativeExtrema(voidptr(mixed_address))(&left[1], &right[2], &expected[4]) }; compare(actual, expected, c.bits, left_nan && right_nan); mixed_chains++
			}
		}
		// A repeated declaration must still validate the later call before a store.
		cached := find_function(ir, 'cached_' + c.name); slot := bodies.scopes[cached + 1].instructions_start + 4; saved := p.instructions[slot]
		for j in 0 .. 16 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6) { panic('cached metadata accepted') }; for byte in actual { assert byte == 0xcc }; cached_metadata++
		}; p.instructions[slot] = saved
		assert p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6)!.steps == 6
		unsafe { NativeExtrema(voidptr(address))(&left[1], &right[2], &expected[4]) }; compare(actual, expected, c.bits, false)
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
	assert cases.len == 12 && comparisons == 1972992 && boundaries == 6912 && chains == 1972992 && guards == 96 && choices == 24 && metadata == 9 && cached_metadata == 108 && mixed_chains == 1408 && legacy_cases == 2304
	result := 'AIR-MEMORY-FLOAT-EXTREMA: ${comparisons} native comparisons (${nan_cases} arithmetic NaN-class cases, ${boundaries} boundary pairs), all half encodings with four anchors, six half/float extrema families (legacy qualified against modern number-preferring refinement), ${chains} native/identity cached chains, ${mixed_chains} four-declaration mixed chains, ${legacy_cases} native legacy diagnostics (${snan_choices} sNaN choices, ${zero_violations} zero violations), sentinels/budgets, ${guards} poison/undef guards with zero/NaN counterparts, ${choices} freeze/lazy choices and ${metadata}/${cached_metadata} initial/cached metadata controls PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
