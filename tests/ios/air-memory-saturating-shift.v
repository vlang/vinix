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
type NativeSaturatingShift = fn (voidptr, voidptr, voidptr)
struct ShiftCase { name string bits int }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut cases := []ShiftCase{}; mut source := strings.new_builder(524288)
	for bits in 1 .. 65 { for op in ['sshl', 'ushl'] {
		name := '${op}_${bits}'; cases << ShiftCase{name, bits}
		source.write_string('declare i${bits} @llvm.${op}.sat.i${bits}(i${bits}, i${bits})\n')
		source.write_string('define void @${name}(ptr %a, ptr %b, ptr %dst) { %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n %v = call i${bits} @llvm.${op}.sat.i${bits}(i${bits} %x, i${bits} %y)\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
		for kind in ['poison', 'undef'] { for position in 0 .. 2 {
			a := if position == 0 { kind } else { '1' }; b := if position == 1 { kind } else { '1' }
			source.write_string('define void @guard_${kind}_${position}_${name}(ptr %dst) { %v = call i${bits} @llvm.${op}.sat.i${bits}(i${bits} ${a}, i${bits} ${b})\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
		} }
		for amount_index, amount in [u64(bits), mask(bits)] { for value in [0, 1] {
			source.write_string('define void @guard_overshift_${amount_index}_${value}_${name}(ptr %dst) { %v = call i${bits} @llvm.${op}.sat.i${bits}(i${bits} ${value}, i${bits} ${amount})\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
		} }
		for mode in ['frozen', 'lazy'] {
			choice := if mode == 'frozen' { 'freeze i${bits} %bad' } else { 'select i1 false, i${bits} %bad, i${bits} 1' }
			source.write_string('define void @${mode}_${name}(ptr %dst) { %bad = call i${bits} @llvm.${op}.sat.i${bits}(i${bits} 0, i${bits} ${bits})\n %v = ${choice}\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
		}
	} }
	source.write_string('define void @preflight(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call i32 @llvm.sshl.sat.i32(i32 1, i32 2)\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'saturating-shift'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0; mut boundary_pairs := 0; mut dynamic_poison := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0; count := (c.bits + 7) / 8
		sign := u64(1) << u32(c.bits - 1); limit := mask(c.bits)
		edges := [u64(0), 1, 2 & limit, limit, limit - 1, sign, sign - 1, (sign + 1) & limit, (sign - 2) & limit]!
		shifts := [u64(0), u64(1) % u64(c.bits), u64(c.bits - 1), u64(2) % u64(c.bits), u64(c.bits / 2), u64(31) % u64(c.bits), u64(32) % u64(c.bits), u64(63) % u64(c.bits), u64(64) % u64(c.bits)]!
		for sample in 0 .. 256 {
			mut a := u64(sample) * u64(0x9e3779b97f4a7c15) & limit; mut b := u64(sample) % u64(c.bits)
			if sample < 81 { a = edges[sample / 9]; b = shifts[sample % 9]; boundary_pairs++ }
			mut left := []u8{len: 16}; mut right := []u8{len: 16}; mut actual := []u8{len: 24, init: 0xcc}; mut expected := actual.clone()
			// Native narrow loads require zero input padding to remain defined.
			for j in 0 .. count { left[1 + j] = u8(a >> u32(8 * j)); right[2 + j] = u8(b >> u32(8 * j)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5
			unsafe { NativeSaturatingShift(voidptr(address))(&left[1], &right[2], &expected[4]) }
			mut x := u64(0); mut y := u64(0); for j in 0 .. count { x |= u64(actual[4 + j]) << u32(8 * j); y |= u64(expected[4 + j]) << u32(8 * j) }
			assert x == y & limit, '${c.name} sample=${sample} a=${a.hex()} b=${b.hex()} actual=${x.hex()} native=${y.hex()}'
			for j in 0 .. 24 { if j < 4 || j >= 4 + count { assert actual[j] == 0xcc && expected[j] == 0xcc } }
			for j in 0 .. 24 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			if sample == 0 {
				// Native execution above used a valid amount. Loaded overshifts
				// are checked only in the interpreter, including zero input.
				for amount in [u64(c.bits), limit] {
					for j in 0 .. count { right[2 + j] = u8(amount >> u32(8 * j)) }
					if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5) { panic('loaded overshift accepted') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() }
					for byte in actual { assert byte == 0xcc }; dynamic_poison++
				}
			}
			unsafe { bindings.free(); left.free(); right.free(); actual.free(); expected.free() }; comparisons++
		}
	}
	mut guards := 0; mut choices := 0; mut anchor := -1
	for i, f in ir.functions {
		if f.name == 'preflight' { anchor = i }
		if !f.name.starts_with('guard_') && !f.name.starts_with('frozen_') && !f.name.starts_with('lazy_') { continue }
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 3) { panic('guard accepted: ' + f.name) } else { if !f.name.starts_with('guard_undef_') { assert err.msg() == 'AIR memory execution: poison store', err.msg() } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			mut count := 0; for c in cases { if f.name == 'frozen_' + c.name || f.name == 'lazy_' + c.name { count = (c.bits + 7) / 8; break } }; assert count > 0
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			for j in 0 .. 16 { assert bytes[j] == if j >= 1 && j < 1 + count { if j == 1 && f.name.starts_with('lazy_') { u8(1) } else { u8(0) } } else { u8(0xcc) }, f.name }; choices++
		}
		unsafe { bytes.free(); bindings.free() }
	}
	assert anchor >= 0; slot := bodies.scopes[anchor + 1].instructions_start + 1; saved := p.instructions[slot]; mut metadata := 0
	mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
		p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3) { panic('metadata accepted') }; for byte in bytes { assert byte == 0xcc }; metadata++
	}; p.instructions[slot] = saved
	assert p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3)!.steps == 3 && bytes[0] == 17
	assert cases.len == 128 && comparisons == 32768 && boundary_pairs == 10368 && guards == 1024 && choices == 256 && metadata == 9 && dynamic_poison == 256
	os.write_file(out + '/result.txt', 'AIR-MEMORY-SATURATING-SHIFT: ${cases.len} functions, ${comparisons} exact defined native LLVM comparisons (${boundary_pairs} boundary pairs), sshl/ushl.sat at i1-i64, five-step execution/padding/budgets, ${guards} poison/undef/overshift guards, ${choices} freeze/lazy selections, ${metadata} metadata and ${dynamic_poison} loaded-overshift controls PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
