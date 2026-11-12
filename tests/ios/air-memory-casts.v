// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import math
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
fn C.LLVMGetNamedFunction(voidptr, &char) voidptr
fn C.LLVMPrintValueToString(voidptr) &char
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeCast = fn (voidptr, voidptr)
struct CastCase { name string source string dest string source_bits int dest_bits int op string }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn is_nan(word u64, bits int) bool { return if bits == 16 { word & 0x7c00 == 0x7c00 && word & 0x3ff != 0 } else { word & 0x7f800000 == 0x7f800000 && word & 0x7fffff != 0 } }
// Construct exact finite inputs in half-unit increments, independently of the
// production converters. All results truncate into the destination's range.
fn defined_float(c CastCase, sample int) u64 {
	mut units := u32(0); mut negative := false
	if c.dest_bits == 1 && c.op == 'fptosi' {
		units = [u32(0), 1, 1, 2]![sample % 4]; negative = sample % 4 in [1, 3]
	} else {
		width := if c.op == 'fptosi' { c.dest_bits - 1 } else { c.dest_bits }
		range := 1 << u32(if width > 4 { 4 } else { width })
		n := sample % range; fraction := (sample / 2) % 2
		negative = c.op == 'fptosi' && sample >= 16
		units = u32(if negative { (n + 1) * 2 - fraction } else { n * 2 + fraction })
		if c.op == 'fptoui' && n == 0 && sample >= 16 { units = 1; negative = true }
	}
	if c.source_bits == 32 { return u64(math.f32_bits(f32(units) * 0.5)) | if negative { u64(1) << 31 } else { 0 } }
	mut word := u64(0)
	if units != 0 {
		mut exponent := u32(0); for units >> (exponent + 1) != 0 { exponent++ }
		word = u64((exponent + 14) << 10) | u64((units - (u32(1) << exponent)) << (10 - exponent))
	}
	return word | if negative { u64(1) << 15 } else { 0 }
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut cases := []CastCase{}
	for a in 1 .. 65 { for b in 1 .. 65 {
		if a > b { cases << CastCase{'trunc_${a}_${b}', 'i${a}', 'i${b}', a, b, 'trunc'} }
		if a < b { for op in ['zext', 'sext'] { cases << CastCase{'${op}_${a}_${b}', 'i${a}', 'i${b}', a, b, op} } }
	} }
	for width in 1 .. 65 { for fp in [16, 32] {
		typ := if fp == 16 { 'half' } else { 'float' }
		for op in ['uitofp', 'sitofp'] { cases << CastCase{'${op}_${width}_${fp}', 'i${width}', typ, width, fp, op} }
		for op in ['fptoui', 'fptosi'] { cases << CastCase{'${op}_${fp}_${width}', typ, 'i${width}', fp, width, op} }
	} }
	for fp in [16, 32] { typ := if fp == 16 { 'half' } else { 'float' }; cases << CastCase{'bits_to_${fp}', 'i${fp}', typ, fp, fp, 'bitcast'}; cases << CastCase{'bits_from_${fp}', typ, 'i${fp}', fp, fp, 'bitcast'} }
	cases << CastCase{'precision_trunc', 'float', 'half', 32, 16, 'fptrunc'}
	cases << CastCase{'precision_ext', 'half', 'float', 16, 32, 'fpext'}
	mut source := strings.new_builder(2097152)
	for c in cases { source.write_string('define void @${c.name}(ptr %src, ptr %dst) { %x = load ${c.source}, ptr %src, align 1\n %v = ${c.op} ${c.source} %x to ${c.dest}\n store ${c.dest} %v, ptr %dst, align 1\n ret void }\n') }
	for name, expr in {'nan': 'fptosi float 0x7FF8000000000000 to i32', 'infinity': 'fptoui float 0x7FF0000000000000 to i32', 'unsigned_negative': 'fptoui half -1.0 to i32', 'signed_overflow': 'fptosi float 0x43E0000000000000 to i64', 'poison': 'zext i8 poison to i32', 'undef': 'sitofp i32 undef to float'} {
		typ := if name == 'signed_overflow' { 'i64' } else if name == 'undef' { 'float' } else { 'i32' }
		source.write_string('define void @guard_${name}(ptr %dst) { %v = ${expr}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
	}
	source.write_string('define void @masked_poison(ptr %dst) { %bad = fptosi float 0x7FF8000000000000 to i32\n %v = select i1 false, i32 %bad, i32 17\n store i32 %v, ptr %dst, align 1\n ret void }\ndefine void @guard_pointer(ptr %src, ptr %dst) { store i32 1, ptr %dst, align 1\n %v = ptrtoint ptr %src to i64\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'casts'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	mut options := C.LLVMMCJITCompilerOptions{}
	C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions))
	options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0; mut nan_matches := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		for sample in 0 .. 32 {
			mut bits := u64(sample) * u64(0x9e3779b97f4a7c15) & mask(c.source_bits)
			if sample < 8 { bits = [u64(0), ~u64(0), u64(1) << u32(c.source_bits - 1), 1, 0x7f800000, 0xff800000, 0x7fc00001, 0x7e01]![sample] & mask(c.source_bits) }
			if c.op in ['fptosi', 'fptoui'] { bits = defined_float(c, sample) }
			mut input := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
			for i in 0 .. (c.source_bits + 7) / 8 { input[1 + i] = u8(bits >> u32(8 * i)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 4)!.steps == 4
			unsafe { NativeCast(voidptr(address))(&input[1], &expected[3]) }
			mut x := u64(0); mut y := u64(0); count := (c.dest_bits + 7) / 8
			for i in 0 .. count { x |= u64(actual[3 + i]) << u32(8 * i); y |= u64(expected[3 + i]) << u32(8 * i) }
			if c.op in ['fptrunc', 'fpext'] && is_nan(x, c.dest_bits) && is_nan(y, c.dest_bits) { nan_matches++ } else {
				if x & mask(c.dest_bits) != y & mask(c.dest_bits) {
					text := C.LLVMPrintValueToString(C.LLVMGetNamedFunction(module_ptr, c.name.str))
					os.write_file(out + '/failure-function.ll', unsafe { cstring_to_vstring(text) })!; C.LLVMDisposeMessage(text)
					code_bytes := unsafe { (&u8(address)).vbytes(64).clone() }; os.write_file_array(out + '/failure-code.bin', code_bytes)!; unsafe { code_bytes.free() }
				}
				assert x & mask(c.dest_bits) == y & mask(c.dest_bits), '${c.name} sample=${sample} input=${bits.hex()}'
			}
			assert x & ~mask(c.dest_bits) == 0, c.name
			for i in 0 .. 16 { if i < 3 || i >= 3 + count { assert actual[i] == 0xcc && expected[i] == 0xcc } }
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('budget accepted') }
			unsafe { bindings.free(); input.free(); actual.free(); expected.free() }; comparisons++
		}
	}
	mut guards := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && f.name != 'masked_poison' { continue }
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		if f.name == 'guard_pointer' { bindings << airbitcode.IRMemoryBinding{data: bytes, writable: true} }
		if f.name == 'masked_poison' {
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			assert bytes[0] == 17 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0
		} else { if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 10) { panic('guard accepted: ' + f.name) }; for b in bytes { assert b == 0xcc } }
		unsafe { bytes.free(); bindings.free() }; guards++
	}
	assert cases.len == 6566 && guards == 8
	os.write_file(out + '/result.txt', 'AIR-MEMORY-CASTS: ${cases.len} functions, ${comparisons} defined native LLVM comparisons (${nan_matches} precision-conversion NaN classes), i1-i64 width/numeric casts, half/float precision/raw bitcasts, four-step execution, padding/budgets and ${guards} poison/undef/pointer/select controls PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
