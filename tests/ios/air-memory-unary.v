// SPDX-License-Identifier: GPL-2.0-or-later
// Defined inputs use both native LLVM and independent raw-bit expectations.
// Indeterminate freeze choices are checked separately, never against a native choice.
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
fn C.LLVMSetDataLayout(voidptr, &char)
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
type NativeUnary = fn (voidptr, voidptr)
struct UnaryCase { name string typ string bits int negate bool }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut cases := []UnaryCase{}
	for bits in 1 .. 65 { cases << UnaryCase{'freeze_i${bits}', 'i${bits}', bits, false} }
	for bits in [16, 32] { typ := if bits == 16 { 'half' } else { 'float' }; cases << UnaryCase{'freeze_${typ}', typ, bits, false}; cases << UnaryCase{'negate_${typ}', typ, bits, true} }
	mut source := strings.new_builder(65536)
	source.write_string('target datalayout = "e-p:64:64"\n')
	for c in cases {
		op := if c.negate { 'fneg' } else { 'freeze' }
		source.write_string('define void @${c.name}(ptr %src, ptr %dst) { %x = load ${c.typ}, ptr %src, align 1\n %v = ${op} ${c.typ} %x\n store ${c.typ} %v, ptr %dst, align 1\n ret void }\n')
		if c.negate { continue }
		for kind in ['undef', 'poison'] {
			// Two distinct stores of the same frozen SSA value must agree.
			source.write_string('define void @choice_${c.name}_${kind}(ptr %dst) { %v = freeze ${c.typ} ${kind}\n store ${c.typ} %v, ptr %dst, align 1\n %other = getelementptr i8, ptr %dst, i64 8\n store ${c.typ} %v, ptr %other, align 1\n ret void }\n')
		}
	}
	source.write_string('define void @computed(ptr %dst) { %bad = shl i32 1, 32\n %v = freeze i32 %bad\n %twice = xor i32 %v, %v\n store i32 %twice, ptr %dst, align 1\n ret void }\n')
	source.write_string('define void @negated_poison(ptr %dst) { %bad = fneg float poison\n %v = freeze float %bad\n store float %v, ptr %dst, align 1\n ret void }\n')
	source.write_string('define void @guard_poison(ptr %dst) { %v = fneg half poison\n store half %v, ptr %dst, align 1\n ret void }\n')
	source.write_string('define void @guard_undef(ptr %dst) { %bad = fneg float undef\n %v = freeze float %bad\n store float %v, ptr %dst, align 1\n ret void }\n')
	for name, expr in {'flags': 'fneg nnan float 1.0', 'double': 'fneg double 1.0', 'vector': 'freeze <2 x i32> poison', 'pointer': 'freeze ptr poison', 'aggregate': 'freeze { i32, i1 } poison'} {
		source.write_string('define void @guard_${name}(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = ${expr}\n ret void }\n')
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'unary'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	// The interpreter's portable layout only supplies i8 GEP offsets. Let the
	// native target choose its own complete ABI layout for JIT compilation.
	C.LLVMSetDataLayout(module_ptr, c'')
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		samples := if c.typ == 'half' { 65536 } else if c.typ == 'float' { 4096 } else { 128 }
		for sample in 0 .. samples {
			mut bits := u64(sample) * u64(0x9e3779b97f4a7c15) & mask(c.bits)
			if c.typ == 'half' { bits = u64(sample) }
			else if sample < 12 { bits = [u64(0), ~u64(0), u64(1) << u32(c.bits - 1), 1, 0x7f800000, 0xff800000, 0x7fc00001, 0x7f800001, 0xffc12345, 0x80000001, 0x007fffff, 0x00800000]![sample] & mask(c.bits) }
			want := bits ^ if c.negate { u64(1) << u32(c.bits - 1) } else { 0 }
			mut input := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone(); count := (c.bits + 7) / 8
			for i in 0 .. count { input[1 + i] = u8(bits >> u32(8 * i)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4
			unsafe { NativeUnary(voidptr(address))(&input[1], &expected[3]) }
			mut x := u64(0); mut y := u64(0)
			for i in 0 .. count { x |= u64(actual[3 + i]) << u32(8 * i); y |= u64(expected[3 + i]) << u32(8 * i) }
			assert x == want && y & mask(c.bits) == want, '${c.name} sample=${sample} input=${bits.hex()} actual=${x.hex()} native=${y.hex()}'
			for i in 0 .. 16 { if i < 3 || i >= 3 + count { assert actual[i] == 0xcc && expected[i] == 0xcc } }
			for i in 0 .. 16 { actual[i] = 0xcc }
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
			unsafe { bindings.free(); input.free(); actual.free(); expected.free() }; comparisons++
		}
	}
	mut choices := 0; mut controls := 0
	for i, f in ir.functions {
		if !f.name.starts_with('choice_') && !f.name.starts_with('guard_') && f.name !in ['computed', 'negated_poison'] { continue }
		mut bytes := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 10) { panic('guard accepted: ' + f.name) }; for byte in bytes { assert byte == 0xcc }; controls++
		} else {
			steps := if f.name == 'negated_poison' { 4 } else { 5 }
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, steps)!.steps == steps
			mut count := 4
			if f.name.starts_with('choice_') {
				mut found := false; for c in cases { if !c.negate && f.name.starts_with('choice_' + c.name + '_') { count = (c.bits + 7) / 8; found = true; break } }; assert found; choices++
			} else { controls++ }
			for j in 0 .. 24 {
				written := (j >= 1 && j < 1 + count) || (f.name.starts_with('choice_') && j >= 9 && j < 9 + count)
				assert bytes[j] == if written { u8(0) } else { u8(0xcc) }, f.name
			}
		}
		unsafe { bytes.free(); bindings.free() }
	}
	assert cases.len == 68 && comparisons == 147456 && choices == 132 && controls == 9
	os.write_file(out + '/result.txt', 'AIR-MEMORY-UNARY: ${cases.len} functions, ${comparisons} exact native LLVM/raw-bit comparisons, all half encodings, i1-i64 and float, four-step execution/padding/budget, ${choices} poison/undef freeze choices and ${controls} computed-poison/unsupported controls PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
