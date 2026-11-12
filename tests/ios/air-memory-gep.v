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

struct GEPCase { name string typ string bits int path string chain bool flags string }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/')
	os.mkdir_all(out)!
	mut source := strings.new_builder(131072)
	source.write_string('target datalayout = "e-p:64:64-i24:32"\n')
	mut cases := []GEPCase{}
	for i in 1 .. 67 {
		bits := if i <= 64 { i } else if i == 65 { 16 } else { 32 }
		typ := if i <= 64 { 'i${i}' } else if i == 65 { 'half' } else { 'float' }
		for flags in ['', 'inbounds', 'nuw', 'nusw', 'nusw nuw', 'inbounds nuw'] {
			cases << GEPCase{'copy_${i}_${cases.len}', typ, bits, '[4 x ${typ}]', false, flags}
		}
		cases << GEPCase{'chain_${i}', typ, bits, '[4 x ${typ}]', true, 'inbounds'}
	}
	for i, path in ['{i8, [4 x i24]}', '<{i8, [4 x i24]}>', '<3 x i24>'] {
		cases << GEPCase{'layout_${i}', 'i24', 24, path, false, 'inbounds'}
	}
	for c in cases {
		indexes := if c.path.starts_with('{') || c.path.starts_with('<{') { 'i8 0, i32 1, i16 2' } else { 'i8 0, i16 2' }
		first := '%p = getelementptr ${c.flags} ${c.path}, ptr %src, ${indexes}\n'
		extra := if c.chain { '%q = getelementptr inbounds ' + c.typ + ', ptr %p, i64 1\n' } else { '' }
		pointer := if c.chain { '%q' } else { '%p' }
		source.write_string('define void @${c.name}(ptr %src, ptr %dst) {\n ${first}${extra}%d = getelementptr ${c.flags} [4 x ${c.typ}], ptr %dst, i32 0, i64 1\n %v = load ${c.typ}, ptr ${pointer}, align 1\n store ${c.typ} %v, ptr %d, align 1\n ret void\n}\n')
	}
	for name, index in {'negative': 'i64 -1', 'poison': 'i64 poison', 'undef': 'i64 undef', 'wide': 'i128 1', 'overflow': 'i64 9223372036854775807', 'dynamic': 'i32 %v'} {
		source.write_string('define void @guard_${name}(ptr %dst) {\n %v = load i32, ptr %dst, align 1\n store i32 1, ptr %dst, align 1\n %p = getelementptr i32, ptr %dst, ${index}\n ret void\n}\n')
	}
	source.write_string('define void @one_past(ptr %dst) { %p = getelementptr inbounds i8, ptr %dst, i64 64\n ret void }\ndefine void @guard_dereference(ptr %dst) { store i8 1, ptr %dst, align 1\n %p = getelementptr inbounds i8, ptr %dst, i64 64\n %v = load i8, ptr %p, align 1\n ret void }\ndefine void @misaligned(ptr %dst) { store i32 1, ptr %dst, align 1\n %p = getelementptr i8, ptr %dst, i64 1\n store i32 2, ptr %p, align 4\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'gep'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	// MCJIT requires its complete native target layout. The fixture's explicit
	// scalar/pointer layout matches the host for these referenced types; let
	// MCJIT supply its target-specific components for native execution.
	C.LLVMSetDataLayout(module_ptr, c'')
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0
	defer { C.LLVMDisposeExecutionEngine(engine) }
	os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	mut comparisons := 0
	for c in cases {
		mut function := -1; for i, f in ir.functions { if f.name == c.name { function = i; break } }; assert function >= 0
		address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
		profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; defer { profile.free() }
		assert profile.steps == if c.chain { 6 } else { 5 }
		for sample in 0 .. 128 {
			mut input := []u8{len: 64}; mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone()
			mut state := u64(sample + 1) * u64(0x9e3779b97f4a7c15)
			for i in 0 .. 64 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; input[i] = u8(state >> 56) }
			mut bindings := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, profile.steps)!.steps == profile.steps
			unsafe { NativeCopy(voidptr(address))(input.data, expected.data) }
			// LLVM leaves high padding bits unspecified for narrow integers.
			width := (c.bits + 7) / 8; destination := int(profile.arguments[1].minimum_size) - width
			for i in 0 .. 64 {
				if i == destination + width - 1 && c.bits % 8 != 0 { assert actual[i] == expected[i] & u8((1 << (c.bits % 8)) - 1), c.name }
				else { assert actual[i] == expected[i], c.name }
			}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, profile.steps - 1) { panic('budget accepted') }
			bindings[1] = airbitcode.IRMemoryBinding{data: actual, offset: u64(65 - profile.arguments[1].minimum_size), writable: true}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, profile.steps) { panic('derived bounds accepted') }
			unsafe { bindings.free(); input.free(); actual.free(); expected.free() }; comparisons++
		}
	}
	mut guards := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && f.name !in ['misaligned', 'one_past'] { continue }
		mut bytes := []u8{len: 64, init: 0xcc}; mut binding := [airbitcode.IRMemoryBinding{data: bytes, writable: true, base_alignment: 4}]
		if f.name == 'one_past' {
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut binding, 2)!.steps == 2
			for layout in ['', 'e-p:32:32', 'e-p:64:64:64:32'] {
				view := airbitcode.IRModule{...ir, data_layout: layout}
				if _ := p.run_memory_function(view, stream, pools, bodies, i, mut binding, 2) { panic('layout profile accepted') }
			}
			mut decoded := p.instructions.clone()
			at := bodies.scopes[i + 1].instructions_start
			decoded[at] = airbitcode.IRTypedInstruction{...decoded[at], flags: 8}
			view := airbitcode.IRTypedProgram{...p, instructions: decoded}
			if _ := view.run_memory_function(ir, stream, pools, bodies, i, mut binding, 2) { panic('unknown GEP flag accepted') }
			decoded[at] = airbitcode.IRTypedInstruction{...decoded[at], flags: 1}
			assert view.run_memory_function(ir, stream, pools, bodies, i, mut binding, 2)!.steps == 2 // Legacy inbounds encoding.
			unsafe { decoded.free() }
			binding[0] = airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}
		}
		if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut binding, 10) { panic('guard accepted: ' + f.name) }
		for b in bytes { assert b == 0xcc }
		unsafe { bytes.free(); binding.free() }; guards++
	}
	assert guards == 9
	os.write_file(out + '/result.txt', 'AIR-MEMORY-GEP: ${cases.len} functions, ${comparisons} native LLVM copies, all i1-i64/half/float, arrays/chains/packed and unpacked structures/vector elements, six flag forms plus legacy inbounds, budgets/bounds, ${guards} preflight guards and layout/unknown-flag rejection PASS\n')!
	print(os.read_file(out + '/result.txt')!)
}
