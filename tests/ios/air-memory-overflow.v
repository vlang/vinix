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
type NativeOverflow = fn (voidptr, voidptr, voidptr)
struct Case { name string op string bits int }
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn word(bytes []u8, offset int, count int) u64 {
	mut value := u64(0); for j in 0 .. count { value |= u64(bytes[offset + j]) << u32(8 * j) }; return value
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(4194304); mut cases := []Case{}
	source.write_string('target datalayout = "e-p:64:64"\n')
	for bits in 1 .. 65 {
		pair := '{i${bits}, i1}'
		for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
			name := '${op}_${bits}'; cases << Case{name, op, bits}
			source.write_string('declare ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits}, i${bits})\n')
			for mode in ['primitive', 'cached'] {
				ending := if mode == 'primitive' { '%f = extractvalue ${pair} %p, 1\n %flag = getelementptr i8, ptr %dst, i64 12\n store i1 %f, ptr %flag, align 1\n' } else { '%q = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} %v, i${bits} %y)\n' }
				source.write_string('define void @${mode}_${name}(ptr %a, ptr %b, ptr %dst) { %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n %p = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} %x, i${bits} %y)\n %v = extractvalue ${pair} %p, 0\n store i${bits} %v, ptr %dst, align 1\n ${ending}ret void }\n')
			}
			for field in 0 .. 2 {
				typ := if field == 0 { 'i${bits}' } else { 'i1' }
				for state in ['poison', 'undef'] { for side in 0 .. 2 {
					a := if side == 0 { state } else { '0' }; b := if side == 1 { state } else { '0' }
					source.write_string('define void @guard_${state}_${side}_${field}_${name}(ptr %dst) { %p = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} ${a}, i${bits} ${b})\n %v = extractvalue ${pair} %p, ${field}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
				} }
				for mode in ['freeze', 'select'] {
					choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1' }
					source.write_string('define void @${mode}_${field}_${name}(ptr %dst) { %p = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} poison, i${bits} 0)\n %bad = extractvalue ${pair} %p, ${field}\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
				}
			}
		}
		for field in 0 .. 2 { for state in ['zeroinitializer', 'poison', 'undef'] {
			typ := if field == 0 { 'i${bits}' } else { 'i1' }
			source.write_string('define void @constant_${state}_${field}_${bits}(ptr %dst) { %v = extractvalue ${pair} ${state}, ${field}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
		} }
	}
	for mode in ['store', 'freeze', 'select', 'insert'] {
		body := match mode { 'store' { 'store {i32, i1} zeroinitializer, ptr %dst, align 1' } 'freeze' { '%p = freeze {i32, i1} poison' } 'select' { '%p = select i1 true, {i32, i1} zeroinitializer, {i32, i1} poison' } else { '%p = insertvalue {i32, i1} zeroinitializer, i32 1, 0' } }
		source.write_string('define void @unsupported_${mode}(ptr %dst) { store i32 17, ptr %dst, align 1\n ${body}\n ret void }\n')
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'overflow'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) } + '\n')!; C.LLVMDisposeMessage(triple)
	// Keep the interpreter's explicit 64-bit layout, while letting MCJIT use
	// its native layout. All GEPs are byte offsets and no aggregate is stored.
	C.LLVMSetDataLayout(module_ptr, c'')
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	mut comparisons := 0; mut boundaries := 0; mut widened := 0; mut overflows := 0; mut call_controls := 0; mut extract_controls := 0; mut types := 0
	for entry in cases {
		bits := entry.bits; count := (bits + 7) / 8; full := mask(bits); sign := u64(1) << u32(bits - 1)
		function := find_function(ir, 'primitive_' + entry.name); cached := find_function(ir, 'cached_' + entry.name)
		address := C.LLVMGetFunctionAddress(engine, ('primitive_' + entry.name).str); assert address != 0
		edges := [u64(0), full, sign, sign - 1, (sign + 1) & full, u64(1), full - 1, 0xaaaaaaaaaaaaaaaa & full, 0x5555555555555555 & full, 0x0123456789abcdef & full, 0xfedcba9876543210 & full, sign >> 1]!
		mut a := []u8{len: 16}; mut b := []u8{len: 16}; mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		samples := if bits <= 8 { int(u64(1) << u32(bits * 2)) } else { 256 }
		for sample in 0 .. 144 + samples {
			x := if sample < 144 { edges[sample / 12] } else if bits <= 8 { u64(sample - 144) & full } else { u64(sample) * u64(0x9e3779b97f4a7c15) & full }
			y := if sample < 144 { edges[sample % 12] } else if bits <= 8 { u64(sample - 144) >> u32(bits) } else { (~x ^ (x >> 17)) & full }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)) }; for j in 0 .. 32 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 9)!.steps == 9
			unsafe { NativeOverflow(voidptr(address))(&a[1], &b[2], &expected[4]) }
			value := word(actual, 4, count); flag := actual[16]; assert value == word(expected, 4, count) & full && value <= full && flag <= 1 && flag == expected[16] & 1
			for j in 0 .. 32 { if (j < 4 || j >= 4 + count) && j != 16 { assert actual[j] == 0xcc && expected[j] == 0xcc } }
			if bits <= 8 {
				signed := entry.op.starts_with('s'); left := if signed && x >= sign { i64(x) - i64(2 * sign) } else { i64(x) }; right := if signed && y >= sign { i64(y) - i64(2 * sign) } else { i64(y) }
				exact := if entry.op.ends_with('add') { left + right } else if entry.op.ends_with('sub') { left - right } else { left * right }
				ov := if signed { exact < -i64(sign) || exact >= i64(sign) } else { exact < 0 || exact > i64(full) }
				assert value == u64(exact) & full && flag == u8(ov); widened++
			}
			if flag != 0 { overflows++ }; comparisons++
			if sample < 144 { for j in 0 .. 32 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 8) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }; boundaries++ }
		}
		// The flag extraction is after a store; malformed metadata must prevent it.
		slot := bodies.scopes[function + 1].instructions_start + 5; saved := p.instructions[slot]
		for j in 0 .. 32 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, indices_count: 0}, airbitcode.IRTypedInstruction{...saved, indices_start: -1}, airbitcode.IRTypedInstruction{...saved, source_type: -1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, flags: 1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 9) { panic('extract metadata accepted') }; for byte in actual { assert byte == 0xcc }; extract_controls++
		}; p.instructions[slot] = saved
		field := p.indices[saved.indices_start]; p.indices[saved.indices_start] = 2
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 9) { panic('extract field accepted') }; for byte in actual { assert byte == 0xcc }; p.indices[saved.indices_start] = field; extract_controls++
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 9)!.steps == 9
		for j in 0 .. 32 { assert actual[j] == if j >= 4 && j < 4 + count { u8(word(expected, 4, count) >> u32(8 * (j - 4))) & if j == 3 + count && bits % 8 != 0 { u8((1 << (bits % 8)) - 1) } else { u8(255) } } else if j == 16 { expected[j] & 1 } else { u8(0xcc) } }
		call := bodies.scopes[cached + 1].instructions_start + 5; original := p.instructions[call]
		for j in 0 .. 32 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: 0}, airbitcode.IRTypedInstruction{...original, flags: 32769}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, operands_count: 2}, airbitcode.IRTypedInstruction{...original, result_type: -1}, airbitcode.IRTypedInstruction{...original, callee_function: -1}, airbitcode.IRTypedInstruction{...original, call_signature: -1}] {
			p.instructions[call] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 7) { panic('cached call accepted') }; for byte in actual { assert byte == 0xcc }; call_controls++
		}; p.instructions[call] = original
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == if bits == 1 { u32(2) } else { u32(1) } { wrong = i; break } }; assert wrong >= 0
		for side in 1 .. 3 { operand_slot := original.operands_start + side; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 7) { panic('call operand accepted') }; for byte in actual { assert byte == 0xcc }; p.operands[operand_slot] = operand; types++ }
		assert p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 7)!.steps == 7 && word(actual, 4, count) == word(expected, 4, count) & full
		for j in 0 .. 32 { if j < 4 || j >= 4 + count { assert actual[j] == 0xcc } }
		unsafe { a.free(); b.free(); actual.free(); expected.free(); bindings.free() }
	}
	mut guards := 0; mut choices := 0; mut constants := 0; mut unsupported := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && !f.name.starts_with('freeze_') && !f.name.starts_with('select_') && !f.name.starts_with('constant_') && !f.name.starts_with('unsupported_') { continue }
		parts := f.name.split('_'); width := parts[parts.len - 1].int(); flag := !f.name.starts_with('unsupported_') && parts[parts.len - if f.name.starts_with('constant_') { 2 } else { 3 }] == '1'; count := if flag { 1 } else { (width + 7) / 8 }
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') || (f.name.starts_with('constant_') && !f.name.starts_with('constant_zeroinitializer_')) || f.name.starts_with('unsupported_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_poison_') || f.name.starts_with('constant_poison_') { assert err.msg() == 'AIR memory execution: poison store' } }; for byte in bytes { assert byte == 0xcc }
			if f.name.starts_with('guard_') { guards++ } else if f.name.starts_with('constant_') { constants++ } else { unsupported++ }
		} else {
			steps := if f.name.starts_with('constant_') { 3 } else { 5 }; assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, steps)!.steps == steps
			for j in 0 .. 16 { assert bytes[j] == if j >= 1 && j < 1 + count { if j == 1 && f.name.starts_with('select_') { u8(1) } else { u8(0) } } else { u8(0xcc) } }
			if f.name.starts_with('constant_') { constants++ } else { choices++ }
		}; unsafe { bytes.free(); bindings.free(); parts.free() }
	}
	assert comparisons == 665592 && boundaries == 55296 && widened == 531192 && extract_controls == 3456 && call_controls == 3456 && types == 768 && guards == 3072 && choices == 1536 && constants == 384 && unsupported == 4
	result := 'AIR-MEMORY-OVERFLOW: ${comparisons} exact native wrapped-value/flag pairs (${boundaries} boundary pairs, ${overflows} overflow cases), ${widened} independent widened checks, all six i1-i64 families/exhaustive i1-i8, offsets/padding/budgets, ${extract_controls} extraction/${call_controls} cached-call/${types} operand-type controls before stores, ${guards} poison/undef guards, ${choices} freeze/lazy choices, ${constants} constant cases and ${unsupported} aggregate exclusions PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
