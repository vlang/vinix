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
fn C.LLVMSetDataLayout(voidptr, &char)
fn C.LLVMGetDataLayoutStr(voidptr) &char
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
type NativePairSelect = fn (voidptr, voidptr, voidptr, voidptr)
struct PairCase { name string bits int }
struct Guard { name string bits int steps int reject bool zero bool }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn word(bytes []u8, offset int, count int) u64 {
	mut value := u64(0); for j in 0 .. count { value |= u64(bytes[offset + j]) << u32(8 * j) }; return value
}
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); mut cases := []PairCase{}; mut guards := []Guard{}
	source.write_string('target datalayout = "e-p:64:64"\n')
	for bits in 1 .. 65 {
		pair := '{i${bits}, i1}'
		for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
			name := '${op}_${bits}'; cases << PairCase{name, bits}
			source.write_string('declare ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits}, i${bits})\n')
			// An earlier store proves that every select is preflighted first.
			source.write_string('define void @${name}(ptr %a, ptr %b, ptr %cond, ptr %out) { %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n %c = load i1, ptr %cond, align 1\n %p = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} %x, i${bits} %y)\n %q = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} %y, i${bits} %x)\n store i8 17, ptr %out, align 1\n %s = select i1 %c, ${pair} %p, ${pair} %q\n %v = extractvalue ${pair} %s, 0\n store i${bits} %v, ptr %out, align 1\n %f = extractvalue ${pair} %s, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n ret void }\n')
		}
		for mode in ['left', 'right', 'zero', 'undef_left', 'undef_right'] { for condition in ['true', 'false', 'poison', 'undef'] { for freezing in [false, true] {
			name := 'guard_${bits}_${mode}_${condition}_${freezing}'
			left := if mode == 'left' || mode == 'undef_right' { '%p' } else if mode == 'right' { 'poison' } else if mode == 'undef_left' { 'undef' } else { 'zeroinitializer' }
			right := if mode == 'left' { 'poison' } else if mode == 'undef_right' { 'undef' } else { '%p' }
			poisoned := condition == 'poison' || (mode == 'left' && condition == 'false') || (mode == 'right' && condition == 'true')
			reject := mode.starts_with('undef_') || condition == 'undef' || (poisoned && !freezing)
			zero := poisoned || (mode == 'zero' && condition == 'true')
			freeze := if freezing { '%frozen = freeze ${pair} %s\n' } else { '' }; value := if freezing { '%frozen' } else { '%s' }
			guards << Guard{name, bits, if freezing { 9 } else { 8 }, reject, zero}
			source.write_string('define void @${name}(ptr %out) { %p = call ${pair} @llvm.umul.with.overflow.i${bits}(i${bits} ${mask(bits)}, i${bits} ${mask(bits)})\n %s = select i1 ${condition}, ${pair} ${left}, ${pair} ${right}\n ${freeze}%v = extractvalue ${pair} ${value}, 0\n store i${bits} %v, ptr %out, align 1\n %f = extractvalue ${pair} ${value}, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n ret void }\n')
		} } }
		name := 'earlier_undef_${bits}'; guards << Guard{name, bits, 5, true, false}
		source.write_string('define void @${name}(ptr %out) { %bad = call ${pair} @llvm.umul.with.overflow.i${bits}(i${bits} undef, i${bits} 0)\n %s = select i1 true, ${pair} zeroinitializer, ${pair} %bad\n %v = extractvalue ${pair} %s, 0\n store i${bits} %v, ptr %out, align 1\n ret void }\n')
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'pair-select'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) } + '\n')!; C.LLVMDisposeMessage(triple)
	C.LLVMSetDataLayout(module_ptr, c'')
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	mut comparisons := 0; mut metadata := 0; mut types := 0; mut budgets := 0; mut rejected := 0; mut choices := 0
	for entry in cases {
		bits := entry.bits; count := (bits + 7) / 8; full := mask(bits); sign := u64(1) << u32(bits - 1)
		function := find_function(ir, entry.name); address := C.LLVMGetFunctionAddress(engine, entry.name.str); assert address != 0
		edges := [u64(0), full, sign, sign - 1, (sign + 1) & full, u64(1), full - 1, 0xaaaaaaaaaaaaaaaa & full, 0x5555555555555555 & full, 0x0123456789abcdef & full, 0xfedcba9876543210 & full, sign >> 1]!
		mut a := []u8{len: 12}; mut b := []u8{len: 12}; mut c := [u8(0)]
		mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: c}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. 160 { for condition in 0 .. 2 {
			x := if sample < 144 { edges[sample / 12] } else { u64(sample) * u64(0x9e3779b97f4a7c15) & full }
			y := if sample < 144 { edges[sample % 12] } else { (~x ^ (x >> 17)) & full }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)) }; c[0] = u8(0xfe + condition)
			for j in 0 .. 32 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 13)!.steps == 13
			// Native i1 loads may use the byte's padding when selecting. Give
			// MCJIT the canonical bit; test our explicit input masking separately.
			c[0] = u8(condition)
			unsafe { NativePairSelect(voidptr(address))(&a[1], &b[2], c.data, &expected[4]) }
			assert word(actual, 4, count) == word(expected, 4, count) & full && word(actual, 4, count) <= full && actual[16] == expected[16] & 1 && actual[16] <= 1, '${entry.name} sample=${sample} condition=${condition}: actual=${word(actual, 4, count)},${actual[16]} native=${word(expected, 4, count)},${expected[16]}'
			for j in 0 .. 32 { if (j < 4 || j >= 4 + count) && j != 16 { assert actual[j] == 0xcc && expected[j] == 0xcc } }; comparisons++
		} }
		for j in 0 .. 32 { actual[j] = 0xcc }
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 12) { panic('short budget accepted') }; for byte in actual { assert byte == 0xcc }; budgets++
		slot := bodies.scopes[function + 1].instructions_start + 6; saved := p.instructions[slot]
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, operands_count: 4}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, result_type: p.operands[saved.operands_start + 2].type_index}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, operands_start: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 13) { panic('select metadata accepted') }; for byte in actual { assert byte == 0xcc }; metadata++
		}; p.instructions[slot] = saved
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 2 { wrong = i; break } }; assert wrong >= 0
		for side in 0 .. 3 {
			operand_slot := saved.operands_start + side; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 13) { panic('select operand type accepted') }; for byte in actual { assert byte == 0xcc }; p.operands[operand_slot] = operand; types++
		}
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 13)!.steps == 13
		assert word(actual, 4, count) == word(expected, 4, count) & full && actual[16] == expected[16] & 1
		unsafe { a.free(); b.free(); c.free(); actual.free(); expected.free(); bindings.free() }
	}
	for guard in guards {
		function := find_function(ir, guard.name); count := (guard.bits + 7) / 8
		mut bytes := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if guard.reject {
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, guard.steps) { panic('guard accepted: ' + guard.name) }; for byte in bytes { assert byte == 0xcc }; rejected++
		} else {
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, guard.steps)!.steps == guard.steps
			assert word(bytes, 1, count) == if guard.zero { u64(0) } else { u64(1) }
			assert bytes[13] == u8(!guard.zero && guard.bits > 1)
			for j in 0 .. 24 { if (j < 1 || j >= 1 + count) && j != 13 { assert bytes[j] == 0xcc } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	assert cases.len == 384 && comparisons == 122880 && metadata == 3456 && types == 1152 && budgets == 384 && guards.len == 2624 && rejected == 1792 && choices == 832
	result := 'AIR-MEMORY-PAIR-SELECT: ${comparisons} exact native value/flag pairs, all six i1-i64 families and both masked i1 conditions; ${metadata} metadata/${types} operand-type/${budgets} budget guards before earlier stores; ${guards.len} constant/poison/undef/freeze/earlier-error cases (${rejected} rejected, ${choices} defined choices), offsets/padding and restored metadata PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
