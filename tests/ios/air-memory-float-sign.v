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
type NativeSign = fn (voidptr, voidptr, voidptr)
struct SignCase { name string bits int copy bool }
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(16384); mut cases := []SignCase{}
	for bits in [16, 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		for op in ['fabs', 'copysign'] {
			copy := op == 'copysign'; name := '${op}_${bits}'; cases << SignCase{name, bits, copy}
			params := if copy { '${typ}, ${typ}' } else { typ }
			load := if copy { '%y = load ${typ}, ptr %b, align 1\n' } else { '' }
			args := if copy { '${typ} %x, ${typ} %y' } else { '${typ} %x' }
			source.write_string('declare ${typ} @llvm.${op}.f${bits}(${params})\ndefine void @${name}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n ${load}%v = call ${typ} @llvm.${op}.f${bits}(${args})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			for state in ['poison', 'undef'] { for side in 0 .. if copy { 2 } else { 1 } {
				a := if side == 0 { state } else { '0.0' }; b := if side == 1 { state } else { '0.0' }
				values := if copy { '${typ} ${a}, ${typ} ${b}' } else { '${typ} ${a}' }
				source.write_string('define void @guard_${state}_${side}_${name}(ptr %dst) { %v = call ${typ} @llvm.${op}.f${bits}(${values})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			} }
			for mode in ['freeze', 'select'] {
				values := if copy { '${typ} poison, ${typ} 0.0' } else { '${typ} poison' }
				choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1.0' }
				source.write_string('define void @${mode}_${name}(ptr %dst) { %bad = call ${typ} @llvm.${op}.f${bits}(${values})\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
			}
		}
		// Two calls to the same declaration exercise the cached declaration path.
		source.write_string('define void @chain_${bits}(ptr %a, ptr %b, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %first = call ${typ} @llvm.copysign.f${bits}(${typ} %x, ${typ} %y)\n %v = call ${typ} @llvm.copysign.f${bits}(${typ} %first, ${typ} %x)\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
	}
	source.write_string('define void @preflight(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call float @llvm.fabs.f32(float 1.0)\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'float-sign'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	// Generic ARM64 half copysign can lower through float32 and quiet sNaNs.
	// Use this host's supported ISA; preserve exact payload/quiet-bit assertions.
	cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures()
	os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut native_function := C.LLVMGetFirstFunction(module_ptr)
	for native_function != unsafe { nil } {
		C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-cpu', cpu)
		C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-features', features)
		native_function = C.LLVMGetNextFunction(native_function)
	}
	C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	// All ten IEEE classes, both zero signs, payload/quiet variants and limits.
	edges := [u32(0), 0x80000000, 1, 0x80000001, 0x007fffff, 0x807fffff, 0x00800000, 0x80800000, 0x3f800000, 0xbf800000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7f800001, 0xff800001, 0x7fc00000, 0xffc00000, 0x7fffffff, 0xffffffff, 0x7f812345, 0xff812345, 0x7fc12345, 0xffc12345, 0x3f000000, 0xbf000000, 0x3fffffff, 0xbfffffff, 0x00800001, 0x80800001, 0x7f7ffffe, 0xff7ffffe]!
	mut comparisons := 0; mut boundary_pairs := 0; mut chains := 0
	for c in cases {
		function := find_function(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		chain_name := 'chain_${c.bits}'; chain := find_function(ir, chain_name); chain_address := C.LLVMGetFunctionAddress(engine, chain_name.str); assert chain_address != 0
		count := c.bits / 8; sign := u64(1) << u32(c.bits - 1); limit := (sign - 1) | sign
		steps := if c.copy { 5 } else { 4 }; samples := if c.copy { 131072 } else { 65536 }
		extra := if c.bits == 32 { if c.copy { 1024 } else { 32 } } else { 0 }
		for sample in 0 .. samples + extra {
			index := if c.copy { sample / 2 } else { sample }
			mut a := if c.bits == 16 { u64(index) } else { u64(u32(index) * u32(0x9e3779b9)) }
			mut b := if sample % 2 == 0 { u64(1) } else { sign | 1 }
			if sample >= samples { a = edges[(sample - samples) / if c.copy { 32 } else { 1 }]; b = edges[(sample - samples) % 32]; boundary_pairs++ }
			a &= limit; b &= limit
			want := (a & (sign - 1)) | if c.copy { b & sign } else { u64(0) }
			mut left := []u8{len: 16}; mut right := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
			for j in 0 .. count { left[1 + j] = u8(a >> u32(8 * j)); right[2 + j] = u8(b >> u32(8 * j)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, steps)!.steps == steps
			unsafe { NativeSign(voidptr(address))(&left[1], &right[2], &expected[3]) }
			for j in 0 .. 16 { assert actual[j] == expected[j] && actual[j] == if j >= 3 && j < 3 + count { u8(want >> u32(8 * (j - 3))) } else { u8(0xcc) }, '${c.name} sample=${sample} byte=${j}' }
			// Test budgets once per boundary or input sign, avoiding mirrored work.
			if sample < 2 || sample >= samples {
				for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, steps - 1) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			}
			if c.copy && (sample < 256 || sample >= samples) {
				for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
				assert p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 6)!.steps == 6
				unsafe { NativeSign(voidptr(chain_address))(&left[1], &right[2], &expected[3]) }
				for j in 0 .. 16 { assert actual[j] == expected[j] && actual[j] == if j >= 3 && j < 3 + count { u8(a >> u32(8 * (j - 3))) } else { u8(0xcc) }, chain_name }
				chains++
			}
			unsafe { bindings.free(); left.free(); right.free(); actual.free(); expected.free() }; comparisons++
		}
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
	assert cases.len == 4 && comparisons == 394272 && boundary_pairs == 1056 && chains == 1536 && guards == 12 && choices == 8 && metadata == 9
	result := 'AIR-MEMORY-FLOAT-SIGN: ${comparisons} exact native/raw-bit comparisons (${boundary_pairs} float boundary pairs), all half encodings and both sign donors, 1536 cached-declaration round trips, four/five/six-step execution, sentinels/budgets, ${guards} poison/undef guards, ${choices} freeze/lazy choices and ${metadata} metadata controls PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
