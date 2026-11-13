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
type NativeClmul = fn (voidptr, voidptr, voidptr)
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
// Independent convolution: parity of bit-pairs on each output diagonal.
fn polynomial(bits int, a u64, b u64) u64 {
	mut result := u64(0)
	for output in 0 .. bits {
		mut parity := u64(0)
		for left in 0 .. output + 1 { parity ^= ((a >> u32(left)) & 1) & ((b >> u32(output - left)) & 1) }
		result |= parity << u32(output)
	}; return result
}
fn compare(actual []u8, native []u8, bits int, want u64) {
	count := (bits + 7) / 8; mut expected := u64(0)
	for j in 0 .. count { assert actual[4 + j] == u8(want >> u32(8 * j)); expected |= u64(native[4 + j]) << u32(8 * j) }
	assert expected & mask(bits) == want
	for j in 0 .. 16 { if j < 4 || j >= 4 + count { assert actual[j] == 0xcc && native[j] == 0xcc } }
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(262144)
	for bits in 1 .. 65 {
		source.write_string('declare i${bits} @llvm.clmul.i${bits}(i${bits}, i${bits})\n')
		for mode in ['product', 'chain', 'cached'] {
			body := if mode == 'chain' { '%other = xor i${bits} %y, 1\n %again = call i${bits} @llvm.clmul.i${bits}(i${bits} %x, i${bits} %other)\n %v = xor i${bits} %first, %again\n store i${bits} %v, ptr %dst, align 1\n' } else if mode == 'cached' { 'store i${bits} %first, ptr %dst, align 1\n %v = call i${bits} @llvm.clmul.i${bits}(i${bits} %first, i${bits} %y)\n' } else { 'store i${bits} %first, ptr %dst, align 1\n' }
			source.write_string('define void @${mode}_${bits}(ptr %a, ptr %b, ptr %dst) { %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n %first = call i${bits} @llvm.clmul.i${bits}(i${bits} %x, i${bits} %y)\n ${body}ret void }\n')
		}
		for state in ['poison', 'undef'] { for side in 0 .. 2 {
			a := if side == 0 { state } else { '0' }; b := if side == 1 { state } else { '0' }
			source.write_string('define void @guard_${state}_${side}_${bits}(ptr %dst) { %v = call i${bits} @llvm.clmul.i${bits}(i${bits} ${a}, i${bits} ${b})\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
		} }
		for mode in ['freeze', 'select'] {
			choice := if mode == 'freeze' { 'freeze i${bits} %bad' } else { 'select i1 false, i${bits} %bad, i${bits} 1' }
			source.write_string('define void @${mode}_${bits}(ptr %dst) { %bad = call i${bits} @llvm.clmul.i${bits}(i${bits} poison, i${bits} 0)\n %v = ${choice}\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
		}
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'clmul'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) } + '\n')!; C.LLVMDisposeMessage(triple)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0; mut boundaries := 0; mut chains := 0; mut metadata := 0; mut types := 0
	for bits in 1 .. 65 {
		function := find_function(ir, 'product_${bits}'); chain := find_function(ir, 'chain_${bits}'); cached := find_function(ir, 'cached_${bits}')
		address := C.LLVMGetFunctionAddress(engine, 'product_${bits}'.str); chain_address := C.LLVMGetFunctionAddress(engine, 'chain_${bits}'.str); assert address != 0 && chain_address != 0
		count := (bits + 7) / 8; full := mask(bits); sign := u64(1) << u32(bits - 1)
		edges := [u64(0), full, sign, sign - 1, (sign + 1) & full, u64(1), full - 1, 0xaaaaaaaaaaaaaaaa & full, 0x5555555555555555 & full, 0x0123456789abcdef & full, 0xfedcba9876543210 & full, sign >> 1]!
		mut a := []u8{len: 16}; mut b := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		samples := if bits <= 8 { int(u64(1) << u32(2 * bits)) } else { 4096 }
		for sample in 0 .. 144 + samples {
			x := if sample < 144 { edges[sample / 12] } else if bits <= 8 { u64(sample - 144) & full } else { u64(sample) * u64(0x9e3779b97f4a7c15) & full }
			y := if sample < 144 { edges[sample % 12] } else if bits <= 8 { u64(sample - 144) >> u32(bits) } else { (~x ^ (x >> 17)) & full }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5
			unsafe { NativeClmul(voidptr(address))(&a[1], &b[2], &expected[4]) }; compare(actual, expected, bits, polynomial(bits, x, y))
			if sample < 144 { for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }; boundaries++ }
			assert p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 8)!.steps == 8
			unsafe { NativeClmul(voidptr(chain_address))(&a[1], &b[2], &expected[4]) }; compare(actual, expected, bits, x)
			if sample < 144 { for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, chain, mut bindings, 7) { panic('chain budget accepted') }; for byte in actual { assert byte == 0xcc } }; comparisons++; chains++
		}
		// Validate a later call even after its declaration was cached and before a store.
		slot := bodies.scopes[cached + 1].instructions_start + 4; saved := p.instructions[slot]
		for j in 0 .. 16 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6) { panic('metadata accepted') }; for byte in actual { assert byte == 0xcc }; metadata++
		}; p.instructions[slot] = saved
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == if bits == 1 { u32(2) } else { u32(1) } { wrong = i; break } }; assert wrong >= 0
		for side in 1 .. 3 { operand_slot := saved.operands_start + side; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6) { panic('operand type accepted') }; for byte in actual { assert byte == 0xcc }; p.operands[operand_slot] = operand; types++ }
		assert p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 6)!.steps == 6
		unsafe { NativeClmul(voidptr(address))(&a[1], &b[2], &expected[4]) }; compare(actual, expected, bits, polynomial(bits, read_input(a, 1, count), read_input(b, 2, count)))
		unsafe { a.free(); b.free(); actual.free(); expected.free(); bindings.free() }
	}
	mut guards := 0; mut choices := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && !f.name.starts_with('freeze_') && !f.name.starts_with('select_') { continue }
		bits := f.name.all_after_last('_').int(); count := (bits + 7) / 8
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 3) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_poison_') { assert err.msg() == 'AIR memory execution: poison store' } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			for j in 0 .. 16 { assert bytes[j] == if j >= 1 && j < 1 + count { if j == 1 && f.name.starts_with('select_') { u8(1) } else { u8(0) } } else { u8(0xcc) } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	assert comparisons == 325972 && boundaries == 9216 && chains == 325972 && metadata == 576 && types == 128 && guards == 256 && choices == 128
	result := 'AIR-MEMORY-CLMUL: ${comparisons} native LLVM/independent polynomial comparisons (${boundaries} boundary pairs), exhaustive i1-i8/all i1-i64, ${chains} native/distributive cached chains, five/eight-step execution, offsets/padding/budgets, ${metadata} metadata/${types} operand-type controls before cached stores, ${guards} poison/undef guards and ${choices} freeze/lazy choices PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
fn read_input(bytes []u8, offset int, count int) u64 {
	mut value := u64(0); for j in 0 .. count { value |= u64(bytes[offset + j]) << u32(8 * j) }; return value
}
