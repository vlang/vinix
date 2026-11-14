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
type NativePairInsert = fn (voidptr, voidptr, voidptr, voidptr)
struct InsertCase { name string bits int field int }
struct Guard { name string bits int steps int output int reject bool value u64 flag u8 }
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
	mut source := strings.new_builder(4194304); mut cases := []InsertCase{}; mut guards := []Guard{}
	source.write_string('target datalayout = "e-p:64:64"\n')
	for bits in 1 .. 65 {
		pair := '{i${bits}, i1}'
		for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
			source.write_string('declare ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits}, i${bits})\n')
			for field in 0 .. 2 {
				name := '${op}_${bits}_${field}'; cases << InsertCase{name, bits, field}; input_bits := if field == 0 { bits } else { 1 }
				// Metadata failures must prevent the store preceding insertion.
				source.write_string('define void @${name}(ptr %a, ptr %b, ptr %replacement, ptr %out) { %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n %r = load i${input_bits}, ptr %replacement, align 1\n %p = call ${pair} @llvm.${op}.with.overflow.i${bits}(i${bits} %x, i${bits} %y)\n store i8 17, ptr %out, align 1\n %s = insertvalue ${pair} %p, i${input_bits} %r, ${field}\n %v = extractvalue ${pair} %s, 0\n store i${bits} %v, ptr %out, align 1\n %f = extractvalue ${pair} %s, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n ret void }\n')
			}
		}
		for field in 0 .. 2 { for base in ['zeroinitializer', 'poison', 'undef'] { for state in ['value', 'poison', 'undef'] { for mode in ['chosen', 'neighbor', 'frozen', 'repair'] {
			name := 'guard_${bits}_${field}_${base}_${state}_${mode}'; input_bits := if field == 0 { bits } else { 1 }
			replacement := if state == 'value' { '1' } else { state }
			prefix := '%p = insertvalue ${pair} ${base}, i${input_bits} ${replacement}, ${field}\n'
			reject := base == 'undef' || state == 'undef' || (mode == 'chosen' && state == 'poison') || (mode == 'neighbor' && base == 'poison')
			if mode in ['chosen', 'neighbor'] {
				out_field := if mode == 'chosen' { field } else { 1 - field }; out_bits := if out_field == 0 { bits } else { 1 }
				guards << Guard{name, bits, 4, out_field, reject, if mode == 'chosen' { u64(1) } else { u64(0) }, 0}
				source.write_string('define void @${name}(ptr %out) { ${prefix}%v = extractvalue ${pair} %p, ${out_field}\n store i${out_bits} %v, ptr %out, align 1\n ret void }\n')
			} else {
				change := if mode == 'frozen' { '%s = freeze ${pair} %p\n' } else { '%data = insertvalue ${pair} %p, i${bits} ${u64(7) & mask(bits)}, 0\n %s = insertvalue ${pair} %data, i1 true, 1\n' }
				value := if mode == 'repair' { u64(7) & mask(bits) } else if field == 0 && state == 'value' { u64(1) } else { u64(0) }
				flag := u8(mode == 'repair' || (field == 1 && state == 'value'))
				guards << Guard{name, bits, if mode == 'frozen' { 8 } else { 9 }, 2, reject, value, flag}
				source.write_string('define void @${name}(ptr %out) { ${prefix}${change}%v = extractvalue ${pair} %s, 0\n store i${bits} %v, ptr %out, align 1\n %f = extractvalue ${pair} %s, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n ret void }\n')
			}
		} } } }
	}
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'pair-insert'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
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
		input_bits := if entry.field == 0 { bits } else { 1 }; input_count := (input_bits + 7) / 8
		function := find_function(ir, entry.name); address := C.LLVMGetFunctionAddress(engine, entry.name.str); assert address != 0
		edges := [u64(0), full, sign, sign - 1, (sign + 1) & full, u64(1), full - 1, 0xaaaaaaaaaaaaaaaa & full, 0x5555555555555555 & full, 0x0123456789abcdef & full, 0xfedcba9876543210 & full, sign >> 1]!
		mut a := []u8{len: 12}; mut b := []u8{len: 12}; mut r := []u8{len: 12}
		mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: r, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. 160 { for variant in 0 .. 2 {
			x := if sample < 144 { edges[sample / 12] } else { u64(sample) * u64(0x9e3779b97f4a7c15) & full }
			y := if sample < 144 { edges[sample % 12] } else { (~x ^ (x >> 17)) & full }
			replacement := if entry.field == 1 { u64(0xfe + variant) } else { (edges[(sample + variant) % 12] ^ (if variant == 0 { u64(0) } else { ~u64(0) })) }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)) }; for j in 0 .. input_count { r[3 + j] = u8(replacement >> u32(8 * j)) }
			for j in 0 .. 32 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 12)!.steps == 12
			// Canonical bytes keep native padding out of the reference. The
			// interpreter independently receives the unmasked replacement above.
			for j in 0 .. input_count { r[3 + j] = u8((replacement & mask(input_bits)) >> u32(8 * j)) }
			unsafe { NativePairInsert(voidptr(address))(&a[1], &b[2], &r[3], &expected[4]) }
			assert word(actual, 4, count) == word(expected, 4, count) & full && word(actual, 4, count) <= full && actual[16] == expected[16] & 1 && actual[16] <= 1, '${entry.name} sample=${sample} variant=${variant}'
			for j in 0 .. 32 { if (j < 4 || j >= 4 + count) && j != 16 { assert actual[j] == 0xcc && expected[j] == 0xcc } }; comparisons++
		} }
		for j in 0 .. 32 { actual[j] = 0xcc }
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 11) { panic('short budget accepted') }; for byte in actual { assert byte == 0xcc }; budgets++
		slot := bodies.scopes[function + 1].instructions_start + 5; saved := p.instructions[slot]
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, source_type: -1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, indices_count: 0}, airbitcode.IRTypedInstruction{...saved, indices_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_start: -1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, operands_start: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 12) { panic('insert metadata accepted') }; for byte in actual { assert byte == 0xcc }; metadata++
		}; p.instructions[slot] = saved
		field := p.indices[saved.indices_start]; p.indices[saved.indices_start] = 2
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 12) { panic('insert field accepted') }; for byte in actual { assert byte == 0xcc }; p.indices[saved.indices_start] = field; metadata++
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == if input_bits == 2 { u32(3) } else { u32(2) } { wrong = i; break } }; assert wrong >= 0
		for side in 0 .. 2 {
			operand_slot := saved.operands_start + side; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 12) { panic('insert operand type accepted') }; for byte in actual { assert byte == 0xcc }; p.operands[operand_slot] = operand; types++
		}
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 12)!.steps == 12
		assert word(actual, 4, count) == word(expected, 4, count) & full && actual[16] == expected[16] & 1
		unsafe { a.free(); b.free(); r.free(); actual.free(); expected.free(); bindings.free() }
	}
	for guard in guards {
		function := find_function(ir, guard.name); count := if guard.output == 1 { 1 } else { (guard.bits + 7) / 8 }
		mut bytes := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if guard.reject {
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, guard.steps) { panic('guard accepted: ' + guard.name) }; for byte in bytes { assert byte == 0xcc }; rejected++
		} else {
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, guard.steps)!.steps == guard.steps
			assert word(bytes, 1, count) == guard.value, guard.name
			if guard.output == 2 { assert bytes[13] == guard.flag, guard.name }
			for j in 0 .. 24 { if (j < 1 || j >= 1 + count) && !(guard.output == 2 && j == 13) { assert bytes[j] == 0xcc } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	assert cases.len == 768 && comparisons == 245760 && metadata == 9216 && types == 1536 && budgets == 768 && guards.len == 4608 && rejected == 3072 && choices == 1536
	result := 'AIR-MEMORY-PAIR-INSERT: ${comparisons} exact native value/flag pairs, all six i1-i64 families and both inserted fields; ${metadata} metadata/index/${types} operand-type/${budgets} budget guards before earlier stores; ${guards.len} zero/poison/undef/neighbor/freeze/repair cases (${rejected} rejected, ${choices} defined choices), masked replacements, offsets/padding and restored metadata PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
