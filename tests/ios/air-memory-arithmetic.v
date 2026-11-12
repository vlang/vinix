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
type NativeMemory = fn (voidptr, voidptr, voidptr)
struct Case { name string bits int opcode int floating bool }
fn bytes_word(data []u8, offset int, count int) u64 { mut n := u64(0); for i in 0 .. count { n |= u64(data[offset + i]) << u32(8 * i) }; return n }
fn nan_bits(n u64, bits int) bool { return if bits == 16 { n & 0x7c00 == 0x7c00 && n & 0x3ff != 0 } else { n & 0x7f800000 == 0x7f800000 && n & 0x7fffff != 0 } }
fn main() {
	assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(131072); mut cases := []Case{}
	for bits in 1 .. 65 { for op, name in ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor'] { cases << Case{'i${bits}_${name}', bits, op, false} } }
	for bits in [16, 32] { for op, name in ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'] { cases << Case{'f${bits}_${name}', bits, op, true} } }
	for c in cases {
		typ := if !c.floating { 'i${c.bits}' } else if c.bits == 16 { 'half' } else { 'float' }; op := c.name.all_after_last('_')
		source.write_string('define void @${c.name}(ptr %a, ptr %b, ptr %out) {\n %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %v = ${op} ${typ} %x, %y\n store ${typ} %v, ptr %out, align 1\n ret void\n}\n')
	}
	for name, expr in {'div_zero': 'udiv i32 1, 0', 'signed_overflow': 'sdiv i32 -2147483648, -1', 'overshift': 'shl i32 1, 32', 'poison_operand': 'add i32 poison, 1', 'undef_operand': 'add i32 undef, 1'} {
		source.write_string('define void @guard_${name}(ptr %out) {\n %v = ${expr}\n %w = xor i32 %v, 1\n store i32 %w, ptr %out, align 1\n ret void\n}\n')
	}
	os.write_file(out + '/input.ll', source.str())!; mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT(); context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'fixture'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple); mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0; mut nan_matches := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		mask := if c.bits == 64 { ~u64(0) } else { (u64(1) << u32(c.bits)) - 1 }; count := (c.bits + 7) / 8
		for sample in 0 .. 128 {
			mut a := u64(sample) * u64(0x9e3779b97f4a7c15) & mask; mut b := (~a ^ u64(sample * 31)) & mask
			if sample < 8 { a = [u64(0), ~u64(0), u64(1) << u32(c.bits - 1), 1, 0x7f800000, 0xff800000, 0x7fc00001, 0x7e01]![sample] & mask }
			if !c.floating {
				if c.opcode in [3, 4, 5, 6] && b == 0 { b = 1 }
				if c.opcode in [4, 6] && a == u64(1) << u32(c.bits - 1) && b == mask { a = 0 }
				if c.opcode in [7, 8, 9] { b %= u64(c.bits) }
			}
			mut left := []u8{len: 16}; mut right := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := []u8{len: 16, init: 0xcc}
			for i in 0 .. count { left[1 + i] = u8(a >> u32(8 * i)); right[2 + i] = u8(b >> u32(8 * i)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5)!.steps == 5
			unsafe { NativeMemory(voidptr(address))(&left[1], &right[2], &expected[3]) }
			x := bytes_word(actual, 3, count); y := bytes_word(expected, 3, count)
			if c.floating && nan_bits(x, c.bits) && nan_bits(y, c.bits) { nan_matches++ } else { assert x & mask == y & mask, c.name }
			if !c.floating { assert x & ~mask == 0 }
			for i in 0 .. 16 { if i < 3 || i >= 3 + count { assert actual[i] == 0xcc && expected[i] == 0xcc } }
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4) { panic('budget accepted') }
			unsafe { left.free(); right.free(); actual.free(); expected.free(); bindings.free() }; comparisons++
		}
	}
	mut guards := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') { continue }
		mut output := []u8{len: 8, init: 0xcc}
		mut bindings := [airbitcode.IRMemoryBinding{data: output, writable: true}]
		if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4) { panic('poison/undef accepted: ' + f.name) }
		for byte in output { assert byte == 0xcc }
		unsafe { output.free(); bindings.free() }; guards++
	}
	assert guards == 5
	os.write_file(out + '/result.txt', 'AIR-MEMORY-ARITHMETIC: ${cases.len} functions, ${comparisons} native LLVM comparisons (${nan_matches} matching NaN classes), all i1-i64 binary opcodes and half/float arithmetic, five-step load/compute/store, padding and budget guards, ${guards} poison/undef consumption guards PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
