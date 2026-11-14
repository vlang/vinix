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
type NativeCopy = fn (voidptr, voidptr)

struct Case { name string typ string bits int index_bits int distance int flags string carrier string kind int }
fn function_index(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name) }
fn unchanged(bytes []u8) { for byte in bytes { assert byte == 0xcc } }
fn equal(actual []u8, expected []u8, destination int, bits int, name string) {
	last := destination + (bits + 7) / 8 - 1
	for i in 0 .. actual.len {
		if i == last && bits % 8 != 0 { assert actual[i] == expected[i] & u8((1 << (bits % 8)) - 1), name }
		else { assert actual[i] == expected[i], '${name} byte ${i}' }
	}
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); mut cases := []Case{}
	// Match native ARM64 integer field alignment, including i33..i64 structures.
	source.write_string('target datalayout = "e-p:64:64-i24:32-i64:64"\n')
	for i in 1 .. 67 {
		bits := if i <= 64 { i } else if i == 65 { 16 } else { 32 }; typ := if i <= 64 { 'i${i}' } else if i == 65 { 'half' } else { 'float' }
		for kind, carrier in ['[4 x ${typ}]', '[2 x [2 x ${typ}]]', '{[4 x ${typ}], i8}'] {
			for index_bits in [1, 8, 32, 64] { for distance in [1, if index_bits == 1 { 1 } else { 2 }] { for flags in ['', 'nusw', 'inbounds'] {
				cases << Case{'copy_${cases.len}', typ, bits, index_bits, distance, flags, carrier, kind}
			} } }
		}
	}
	for c in cases {
		path := if c.kind == 0 { 'i64 1, i${c.index_bits} -${c.distance}' } else if c.kind == 1 { 'i64 1, i${c.index_bits} -1, i${c.index_bits} -${c.distance}' } else { 'i64 0, i32 0, i${c.index_bits} -${c.distance}' }
		source.write_string('define void @${c.name}(ptr %src, ptr %dst) {\n store i8 0, ptr %dst, align 1\n %sb = getelementptr inbounds ${c.typ}, ptr %src, i64 16\n %db = getelementptr inbounds ${c.typ}, ptr %dst, i64 16\n %p = getelementptr ${c.flags} ${c.carrier}, ptr %sb, ${path}\n %q = getelementptr ${c.flags} ${c.carrier}, ptr %db, ${path}\n %v = load ${c.typ}, ptr %p, align 1\n store ${c.typ} %v, ptr %q, align 1\n ret void }\n')
	}
	// Rejected functions are valid IR, but never invoked by the native reference.
	for name, index in {'underflow': 'i64 -17', 'minimum': 'i64 -9223372036854775808', 'poison': 'i64 poison', 'undef': 'i64 undef', 'wide': 'i128 -1', 'dynamic': 'i8 %v'} {
		source.write_string('define void @guard_${name}(ptr %dst) { %v = load i8, ptr %dst, align 1\n store i8 17, ptr %dst, align 1\n %b = getelementptr i8, ptr %dst, i64 16\n %p = getelementptr i8, ptr %b, ${index}\n ret void }\n')
	}
	for name, typ in {'array': '[0 x i8]', 'struct': '{}', 'vector': '<134217728 x i8>', 'scalar128': 'i128'} {
		source.write_string('define void @guard_${name}(ptr %dst) { store i8 17, ptr %dst, align 1\n %b = getelementptr i8, ptr %dst, i64 16\n %p = getelementptr ${typ}, ptr %b, i64 -1\n ret void }\n')
	}
	source.write_string('define void @guard_multi(ptr %dst) { store i8 17, ptr %dst, align 1\n %b = getelementptr i8, ptr %dst, i64 16\n %p = getelementptr {[32 x i8], [2 x i8]}, ptr %b, i64 -1, i32 1, i64 -1\n ret void }\ndefine void @guard_direct(ptr %dst) { store i8 17, ptr %dst, align 1\n %p = getelementptr i8, ptr %dst, i64 -1\n ret void }\ndefine void @guard_alignment(ptr %dst) { store i8 17, ptr %dst, align 1\n %b = getelementptr i8, ptr %dst, i64 16\n %p = getelementptr i8, ptr %b, i64 -1\n store i32 1, ptr %p, align 4\n ret void }\ndefine void @guard_dereference(ptr %dst) { store i8 17, ptr %dst, align 1\n %b = getelementptr i8, ptr %dst, i64 65\n %p = getelementptr i8, ptr %b, i64 -1\n store i8 1, ptr %p, align 1\n ret void }\n')
	for n, carrier in ['[2 x i32]', '{i64, i8}', '<3 x i24>'] { for k, index in ['-17', '-9223372036854775808'] {
		source.write_string('define void @guard_scaled_${n}_${k}(ptr %dst) { store i8 17, ptr %dst, align 1\n %b = getelementptr i8, ptr %dst, i64 16\n %p = getelementptr ${carrier}, ptr %b, i64 ${index}\n ret void }\n')
	} }
	source.write_string('define void @guard_recovery(ptr %dst) { store i8 17, ptr %dst, align 1\n %p = getelementptr [2 x i8], ptr %dst, i64 -1, i64 2\n ret void }\ndefine void @guard_peak(ptr %dst) { store i8 17, ptr %dst, align 1\n %p = getelementptr [67108864 x i8], ptr %dst, i64 1, i64 -67108864\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'backward-gep'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) } + '\n')!; C.LLVMDisposeMessage(triple)
	// Let MCJIT supply its full host layout, matching the fixture's scalar strides.
	C.LLVMSetDataLayout(module_ptr, c''); mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	mut comparisons := 0; mut metadata := 0; mut budgets := 0; mut bounds := 0
	for c in cases {
		function := function_index(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 8 && profile.arguments.len == 2
		assert profile.arguments[0].minimum_size == profile.arguments[1].minimum_size && profile.arguments[0].minimum_size % u64(if c.kind == 2 { 16 } else { 20 }) == 0
		peak := if c.kind == 2 { 16 } else { 20 }; stride := int(profile.arguments[0].minimum_size) / peak; width := (c.bits + 7) / 8; relative := (if c.kind == 0 { 20 - c.distance } else if c.kind == 1 { 18 - c.distance } else { 16 - c.distance }) * stride
		assert stride >= width && stride <= 128; profile.free()
		mut input := []u8{len: 4096}; mut actual := []u8{len: 4096, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 5, writable: true}]
		for sample in 0 .. 16 {
			mut state := u64(sample + 1) * u64(0x9e3779b97f4a7c15)
			for j in 0 .. 4096 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; input[j] = u8(state >> 56); actual[j] = 0xcc; expected[j] = 0xcc }
			if c.bits % 8 != 0 { input[3 + relative + width - 1] &= u8((1 << (c.bits % 8)) - 1) }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 8)!.steps == 8
			unsafe { NativeCopy(voidptr(address))(&input[3], &expected[5]) }; equal(actual, expected, 5 + relative, c.bits, c.name); comparisons++
		}
		// Borrowed bindings may alias; the initial zero store must precede the load.
		mut alias := input.clone(); mut alias_expected := alias.clone(); mut aliased := [airbitcode.IRMemoryBinding{data: alias, offset: 3}, airbitcode.IRMemoryBinding{data: alias, offset: 5, writable: true}]
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut aliased, 8)!.steps == 8
		unsafe { NativeCopy(voidptr(address))(&alias_expected[3], &alias_expected[5]) }; equal(alias, alias_expected, 5 + relative, c.bits, c.name); comparisons++
		for j in 0 .. 4096 { actual[j] = 0xcc }
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 7) { panic('short budget accepted') }; unchanged(actual); budgets++
		for arg in 0 .. 2 {
			saved := bindings[arg]; bindings[arg] = airbitcode.IRMemoryBinding{...saved, offset: u64(4097 - peak * stride)}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 8) { panic('intermediate extent accepted') }; unchanged(actual); bounds++; bindings[arg] = saved
		}
		bindings[1] = airbitcode.IRMemoryBinding{data: actual, offset: 5}
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 8) { panic('readonly destination accepted') }; unchanged(actual); bounds++; bindings[1] = airbitcode.IRMemoryBinding{data: actual, offset: 5, writable: true}
		scope := bodies.scopes[function + 1]
		for ordinal in [3, 4] {
			slot := scope.instructions_start + ordinal; saved := p.instructions[slot]
			for flag in [u64(4), 5, 6, 7, 8] {
				p.instructions[slot] = airbitcode.IRTypedInstruction{...saved, flags: flag}
				if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 8) { panic('backward NUW/unknown flags accepted') }; unchanged(actual); metadata++
			}
			p.instructions[slot] = saved
		}
		// The historical bitcode inbounds encoding has flag 1 rather than 3.
		// Restrict both views so their forward intermediates are exactly one-past.
		bindings[0] = airbitcode.IRMemoryBinding{data: unsafe { input[..3 + peak * stride] }, offset: 3}
		bindings[1] = airbitcode.IRMemoryBinding{data: unsafe { actual[..5 + peak * stride] }, offset: 5, writable: true}
		left := scope.instructions_start + 3; right := scope.instructions_start + 4; saved_left := p.instructions[left]; saved_right := p.instructions[right]
		p.instructions[left] = airbitcode.IRTypedInstruction{...saved_left, flags: 1}; p.instructions[right] = airbitcode.IRTypedInstruction{...saved_right, flags: 1}
		for j in 0 .. 4096 { expected[j] = 0xcc }
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 8)!.steps == 8; unsafe { NativeCopy(voidptr(address))(&input[3], &expected[5]) }; equal(actual, expected, 5 + relative, c.bits, c.name); comparisons++
		p.instructions[left] = saved_left; p.instructions[right] = saved_right
		unsafe { input.free(); actual.free(); expected.free(); bindings.free(); alias.free(); alias_expected.free(); aliased.free() }
	}
	mut guards := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') { continue }
		mut bytes := []u8{len: 64, init: 0xcc}; mut binding := [airbitcode.IRMemoryBinding{data: bytes, writable: true, base_alignment: 4}]
		if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut binding, 20) { panic('guard accepted: ' + f.name) }; unchanged(bytes); guards++
		if f.name == 'guard_direct' { binding[0] = airbitcode.IRMemoryBinding{data: bytes, offset: 16, writable: true}; if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut binding, 20) { panic('binding offset used as GEP headroom') }; unchanged(bytes); guards++ }
		unsafe { bytes.free(); binding.free() }
	}
	function := function_index(ir, cases[0].name); mut bytes := []u8{len: 4096, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	for layout in ['', 'e-p:32:32', 'e-p:64:64:64:32'] { view := airbitcode.IRModule{...ir, data_layout: layout}; if _ := p.run_memory_function(view, stream, pools, bodies, function, mut bindings, 8) { panic('layout accepted') }; unchanged(bytes); guards++ }
	unsafe { bytes.free(); bindings.free() }
	assert cases.len == 4752 && comparisons == 85536 && metadata == 47520 && budgets == 4752 && bounds == 14256 && guards == 26
	os.write_file(out + '/result.txt', 'AIR-MEMORY-MULTI-INDEX: ${cases.len} functions, ${comparisons} native LLVM copies including aliasing/legacy inbounds, i1-i64/half/float elements, four index widths, arrays/nested arrays/zero-offset structure fields, plain/nusw/inbounds, ${metadata} flag controls, ${budgets} budgets, ${bounds} bounds/writability controls, ${guards} preflight guards PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
