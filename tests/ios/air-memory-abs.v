// SPDX-License-Identifier: GPL-2.0-or-later
// Only defined inputs execute natively. Poison/undef and metadata controls use
// the interpreter alone, with unchanged destination sentinels on rejection.
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
type NativeAbs = fn (voidptr, voidptr)
struct AbsCase { name string bits int minimum_poison bool }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut cases := []AbsCase{}; mut source := strings.new_builder(262144)
	for bits in 1 .. 65 {
		source.write_string('declare i${bits} @llvm.abs.i${bits}(i${bits}, i1 immarg)\n')
		for flag in 0 .. 2 {
			name := 'abs_${bits}_${flag}'; cases << AbsCase{name, bits, flag == 1}
			extra := ', i1 ' + if flag == 1 { 'true' } else { 'false' }
			source.write_string('define void @${name}(ptr %src, ptr %dst) { %x = load i${bits}, ptr %src, align 1\n %v = call i${bits} @llvm.abs.i${bits}(i${bits} %x${extra})\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
			for kind in ['poison', 'undef'] { source.write_string('define void @guard_${kind}_${name}(ptr %dst) { %v = call i${bits} @llvm.abs.i${bits}(i${bits} ${kind}${extra})\n store i${bits} %v, ptr %dst, align 1\n ret void }\n') }
			if flag == 1 {
				minimum := u64(1) << u32(bits - 1)
				source.write_string('define void @guard_minimum_${name}(ptr %dst) { %v = call i${bits} @llvm.abs.i${bits}(i${bits} ${minimum}${extra})\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
				source.write_string('define void @frozen_${name}(ptr %dst) { %bad = call i${bits} @llvm.abs.i${bits}(i${bits} ${minimum}${extra})\n %v = freeze i${bits} %bad\n store i${bits} %v, ptr %dst, align 1\n ret void }\n')
			}
		}
	}
	source.write_string('define void @preflight(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call i32 @llvm.abs.i32(i32 1, i1 false)\n ret void }\n')
	source.write_string('declare float @llvm.fabs.f32(float)\ndefine void @guard_other_intrinsic(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call float @llvm.fabs.f32(float 1.0)\n ret void }\n')
	source.write_string('define i32 @ordinary(i32 %x) { ret i32 %x }\ndefine void @guard_ordinary(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call i32 @ordinary(i32 1)\n ret void }\n')
	source.write_string('define void @cached_abs(ptr %dst) { store i32 17, ptr %dst, align 1\n %a = call i32 @llvm.abs.i32(i32 -2147483648, i1 false)\n %bad = call i32 @llvm.abs.i32(i32 -2147483648, i1 true)\n %b = freeze i32 %bad\n %v = add i32 %a, %b\n store i32 %v, ptr %dst, align 1\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'abs'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		minimum := u64(1) << u32(c.bits - 1)
		for sample in 0 .. 256 {
			mut bits := u64(sample) * u64(0x9e3779b97f4a7c15) & mask(c.bits)
			if sample < c.bits { bits = u64(1) << u32(sample) } else if sample < c.bits * 2 { bits = mask(c.bits) ^ (u64(1) << u32(sample - c.bits)) } else if sample == 255 { bits = minimum }
			if c.minimum_poison && bits == minimum { bits = 0 }
			mut input := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone(); count := (c.bits + 7) / 8
			for i in 0 .. count { input[1 + i] = u8(bits >> u32(8 * i)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4
			unsafe { NativeAbs(voidptr(address))(&input[1], &expected[3]) }
			mut x := u64(0); mut y := u64(0)
			for i in 0 .. count { x |= u64(actual[3 + i]) << u32(8 * i); y |= u64(expected[3 + i]) << u32(8 * i) }
			assert x == y & mask(c.bits), '${c.name} sample=${sample} input=${bits.hex()} actual=${x.hex()} native=${y.hex()}'
			for i in 0 .. 16 { if i < 3 || i >= 3 + count { assert actual[i] == 0xcc && expected[i] == 0xcc } }
			for i in 0 .. 16 { actual[i] = 0xcc }
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			unsafe { bindings.free(); input.free(); actual.free(); expected.free() }; comparisons++
		}
	}
	mut guards := 0; mut frozen := 0; mut anchor := -1
	for i, f in ir.functions {
		if f.name == 'preflight' { anchor = i }
		if !f.name.starts_with('guard_') && !f.name.starts_with('frozen_') { continue }
		mut bytes := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 10) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_minimum_') || f.name.starts_with('guard_poison_') { assert err.msg() == 'AIR memory execution: poison store', err.msg() } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			mut count := 0; for c in cases { if f.name == 'frozen_' + c.name { count = (c.bits + 7) / 8; break } }; assert count > 0
			for j in 0 .. 24 { assert bytes[j] == if j >= 1 && j < 1 + count { u8(0) } else { u8(0xcc) }, f.name }; frozen++
		}
		unsafe { bytes.free(); bindings.free() }
	}
	assert anchor >= 0; slot := bodies.scopes[anchor + 1].instructions_start + 1; saved := p.instructions[slot]; mut metadata := 0
	mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
		p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3) { panic('metadata accepted') }; for byte in bytes { assert byte == 0xcc }; metadata++
	}; p.instructions[slot] = saved
	assert p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3)!.steps == 3 && bytes[0] == 17
	mut cached := 0
	for i, f in ir.functions {
		if !f.name.starts_with('cached_') { continue }
		for j in 0 .. bytes.len { bytes[j] = 0xcc }
		assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 7)!.steps == 7
		assert bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0x80
		for j in 0 .. bytes.len { bytes[j] = 0xcc }
		start := bodies.scopes[i + 1].instructions_start; flag_slot := p.instructions[start + 2].operands_start + 2; flag := p.operands[flag_slot]
		// The first call already admitted this declaration. The second flag
		// must still be a literal constant, and rejection precedes the store.
		p.operands[flag_slot] = airbitcode.IRTypedOperand{...flag, number: bodies.instructions[start + 1].next_value}
		if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 7) { panic('cached nonconstant flag accepted') } else { assert err.msg() == 'AIR constants: local value ID out of range (instruction values are not indexed)', err.msg() }
		for byte in bytes { assert byte == 0xcc }; p.operands[flag_slot] = flag; cached++
	}
	assert cases.len == 128 && comparisons == 32768 && guards == 322 && frozen == 64 && metadata == 9
	assert cached == 1
	os.write_file(out + '/result.txt', 'AIR-MEMORY-ABS: ${cases.len} functions, ${comparisons} exact defined native LLVM comparisons, abs at i1-i64 with both minimum-poison flags, four-step execution/padding/budget, ${guards} poison/undef/minimum/call guards, ${frozen} frozen minimum-poison results, ${metadata} metadata and ${cached} mixed/cached-flag controls PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
