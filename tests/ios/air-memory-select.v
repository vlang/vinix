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
type NativeSelect = fn (voidptr, voidptr, voidptr, voidptr)
struct SelectCase { name string bits int typ string predicate string floating bool }

fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut cases := []SelectCase{}
	for bits in 1 .. 65 { for pred in ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule', 'sgt', 'sge', 'slt', 'sle'] { cases << SelectCase{'i${bits}_${pred}', bits, 'i${bits}', pred, false} } }
	for bits in [16, 32] { for pred in ['false', 'oeq', 'ogt', 'oge', 'olt', 'ole', 'one', 'ord', 'uno', 'ueq', 'ugt', 'uge', 'ult', 'ule', 'une', 'true'] { cases << SelectCase{'f${bits}_${pred}', bits, if bits == 16 { 'half' } else { 'float' }, pred, true} } }
	mut source := strings.new_builder(131072)
	for c in cases {
		cmp := if c.floating { 'fcmp' } else { 'icmp' }
		source.write_string('define void @${c.name}(ptr %a, ptr %b, ptr %pred, ptr %out) {\n %x = load ${c.typ}, ptr %a, align 1\n %y = load ${c.typ}, ptr %b, align 1\n %c = ${cmp} ${c.predicate} ${c.typ} %x, %y\n %v = select i1 %c, ${c.typ} %x, ${c.typ} %y\n store i1 %c, ptr %pred, align 1\n store ${c.typ} %v, ptr %out, align 1\n ret void\n}\n')
	}
	for name, expr in {'lazy_true': 'select i1 true, i32 17, i32 undef', 'lazy_false': 'select i1 false, i32 poison, i32 17', 'selected_poison': 'select i1 true, i32 poison, i32 17', 'selected_undef': 'select i1 false, i32 17, i32 undef', 'poison_condition': 'select i1 poison, i32 17, i32 18', 'undef_condition': 'select i1 undef, i32 17, i32 18'} {
		source.write_string('define void @${name}(ptr %out) { %v = ${expr}\n store i32 %v, ptr %out, align 1\n ret void }\n')
	}
	source.write_string('define void @constant_predicate(ptr %out) { %c = fcmp true float poison, undef\n %v = select i1 %c, i32 17, i32 poison\n store i32 %v, ptr %out, align 1\n ret void }\ndefine void @poison_compare(ptr %out) { %c = icmp eq i32 poison, 0\n store i1 %c, ptr %out, align 1\n ret void }\ndefine void @undef_compare(ptr %out) { %c = fcmp oeq half undef, 0.0\n store i1 %c, ptr %out, align 1\n ret void }\ndefine void @flagged_compare(ptr %out) { store i32 1, ptr %out, align 1\n %c = fcmp nnan olt float 0.0, 1.0\n ret void }\ndefine void @flagged_select(ptr %out) { store i32 1, ptr %out, align 1\n %v = select nnan i1 true, float 0.0, float 1.0\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'select'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0
	defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		mask := if c.bits == 64 { ~u64(0) } else { (u64(1) << u32(c.bits)) - 1 }; count := (c.bits + 7) / 8
		for sample in 0 .. 128 {
			mut a := u64(sample) * u64(0x9e3779b97f4a7c15) & mask; mut b := (~a ^ u64(sample * 31)) & mask
			if sample % 8 == 0 { b = a }
			if sample < 8 {
				if c.floating {
					edges := if c.bits == 16 { [u64(0), 0x8000, 0x7c00, 0xfc00, 0x7e01, 0x3c00, 0x7c01, 1] } else { [u64(0), 0x80000000, 0x7f800000, 0xff800000, 0x7fc00001, 0x3f800000, 0x7f800001, 1] }
					a = edges[sample]; b = edges[(sample + 3) % 8]; unsafe { edges.free() }
				} else { a = [u64(0), mask, u64(1) << u32(c.bits - 1), 1, mask >> 1, 2, 3, 0]![sample] & mask }
			}
			mut left := []u8{len: 16}; mut right := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
			mut actual_pred := []u8{len: 8, init: 0xcc}; mut expected_pred := actual_pred.clone()
			for i in 0 .. count { left[1 + i] = u8(a >> u32(8 * i)); right[2 + i] = u8(b >> u32(8 * i)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual_pred, offset: 3, writable: true}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 7)!.steps == 7
			unsafe { NativeSelect(voidptr(address))(&left[1], &right[2], &expected_pred[3], &expected[4]) }
			for i in 0 .. 8 { assert actual_pred[i] == if i == 3 { expected_pred[i] & 1 } else { expected_pred[i] }, c.name }
			for i in 0 .. 16 {
				if i == 4 + count - 1 && c.bits % 8 != 0 { assert actual[i] == expected[i] & u8((1 << (c.bits % 8)) - 1), c.name }
				else { assert actual[i] == expected[i], c.name }
			}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6) { panic('budget accepted') }
			unsafe { bindings.free(); left.free(); right.free(); actual.free(); expected.free(); actual_pred.free(); expected_pred.free() }; comparisons++
		}
	}
	mut guards := 0
	for i, f in ir.functions {
		if f.name !in ['lazy_true', 'lazy_false', 'selected_poison', 'selected_undef', 'poison_condition', 'undef_condition', 'constant_predicate', 'poison_compare', 'undef_compare', 'flagged_compare', 'flagged_select'] { continue }
		mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		if f.name in ['lazy_true', 'lazy_false', 'constant_predicate'] {
			steps := if f.name == 'constant_predicate' { 4 } else { 3 }
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 10)!.steps == steps
			assert bytes[0] == 17 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0
			for b in bytes[4..] { assert b == 0xcc }
		} else {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 10) { panic('guard accepted: ' + f.name) }
			for b in bytes { assert b == 0xcc }
		}
		unsafe { bytes.free(); bindings.free() }; guards++
	}
	assert guards == 11
	os.write_file(out + '/result.txt', 'AIR-MEMORY-SELECT: ${cases.len} functions, ${comparisons} native LLVM comparisons and selects, all integer and half/float predicates, raw chosen bits/padding, exact budgets and ${guards} lazy/poison/undef/flag controls PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
