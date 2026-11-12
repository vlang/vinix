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
fn C.LLVMDisposeModule(voidptr)
fn C.LLVMDisposeMessage(&char)
fn C.LLVMVerifyModule(voidptr, int, &&char) int
fn C.LLVMInitializeNativeTarget() int
fn C.LLVMInitializeNativeAsmPrinter() int
fn C.LLVMGetDefaultTargetTriple() &char
fn C.LLVMSetTarget(voidptr, &char)
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
type NativeBits = fn (u64) u64
type NativeProperty = fn () u64

struct FreezeCase { name string typ string bits u32 kind airbitcode.IRScalarKind }
fn fixture(mut source strings.Builder) []FreezeCase {
	mut cases := []FreezeCase{}
	for width in u32(1) .. 65 { cases << FreezeCase{'i${width}', 'i${width}', width, .integer} }
	cases << FreezeCase{'half', 'half', 16, .binary16}; cases << FreezeCase{'float', 'float', 32, .binary32}
	for c in cases {
		name := c.name; typ := c.typ; width := c.bits
		cast := if width == 64 { '' } else { '  %raw = trunc i64 %ai to i${width}\n' }
		raw := if width == 64 { '%ai' } else { '%raw' }
		fpcast := if c.kind == .integer { '' } else { '  %a = bitcast i${width} ${raw} to ${typ}\n' }
		a := if c.kind == .integer { raw } else { '%a' }
		result_cast := if c.kind == .integer { '' } else { '  %bits = bitcast ${typ} %r to i${width}\n' }
		result := if c.kind == .integer { '%r' } else { '%bits' }
		ending := if width == 64 { '  ret i64 ${result}\n' } else { '  %wide = zext i${width} ${result} to i64\n  ret i64 %wide\n' }
		text := 'define ${typ} @keep_${name}(${typ} %a) {\n  %r = freeze ${typ} %a\n  ret ${typ} %r\n}\ndefine i64 @reference_keep_${name}(i64 %ai) {\n${cast}${fpcast}  %r = call ${typ} @keep_${name}(${typ} ${a})\n${result_cast}${ending}}\n'
		source.write_string(text)
		unsafe { cast.free(); if c.kind != .integer { fpcast.free(); result_cast.free() }; ending.free(); text.free() }
		for state in ['poison', 'undef'] {
			bits_cast := if c.kind == .integer { '' } else { '  %bits = bitcast ${typ} %f to i${width}\n' }
			bits := if c.kind == .integer { '%f' } else { '%bits' }
			stable_end := if width == 64 { '  ret i64 %x\n' } else { '  %wide = zext i${width} %x to i64\n  ret i64 %wide\n' }
			// Native arbitrary choices are never compared with Vinix's zero policy.
			// Self-XOR and reflexive integer equality must hold for every choice.
			control := 'define ${typ} @choice_${name}_${state}() {\n  %r = freeze ${typ} ${state}\n  ret ${typ} %r\n}\ndefine i64 @stable_${name}_${state}() {\n  %f = freeze ${typ} ${state}\n${bits_cast}  %x = xor i${width} ${bits}, ${bits}\n${stable_end}}\ndefine i64 @branch_${name}_${state}() {\n  %f = freeze ${typ} ${state}\n${bits_cast}  %eq = icmp eq i${width} ${bits}, ${bits}\n  br i1 %eq, label %good, label %bad\ngood:\n  br label %join\nbad:\n  br label %join\njoin:\n  %r = phi i64 [ 0, %good ], [ 1, %bad ]\n  ret i64 %r\n}\ndefine ${typ} @raw_${name}_${state}() {\n  ret ${typ} ${state}\n}\n'
			source.write_string(control); unsafe { if c.kind != .integer { bits_cast.free() }; stable_end.free(); control.free() }
		}
		if c.kind == .integer {
			shift := 'define i${width} @shift_${name}(i${width} %a, i${width} %amount) {\n  %s = shl i${width} %a, %amount\n  %r = freeze i${width} %s\n  ret i${width} %r\n}\n'
			source.write_string(shift); unsafe { shift.free() }
		}
	}
	source.write_string('define i8 @loop(i8 %a) {\nentry:\n  br label %body\nbody:\n  %i = phi i8 [ 0, %entry ], [ %next, %body ]\n  %sum = phi i8 [ %a, %entry ], [ %newsum, %body ]\n  %f = freeze i8 poison\n  %same = xor i8 %f, %f\n  %newsum = add i8 %sum, %same\n  %next = add i8 %i, 1\n  %done = icmp eq i8 %next, 4\n  br i1 %done, label %exit, label %body\nexit:\n  ret i8 %newsum\n}\ndefine i64 @reference_loop(i64 %a) {\n  %narrow = trunc i64 %a to i8\n  %r = call i8 @loop(i8 %narrow)\n  %wide = zext i8 %r to i64\n  ret i64 %wide\n}\ndefine i1 @frozen_condition() {\n  %f = freeze i1 poison\n  br i1 %f, label %yes, label %no\nyes:\n  ret i1 true\nno:\n  ret i1 false\n}\ndefine i8 @dead() {\n  ret i8 7\nunused:\n  %f = freeze i8 poison\n  ret i8 %f\n}\n')
	for typ in ['ptr', '<2 x i8>', 'double', 'i128'] {
		text := 'define ${typ} @outside_${typ.len}(${typ} %a) {\n  %r = freeze ${typ} %a\n  ret ${typ} %r\n}\n'; source.write_string(text); unsafe { text.free() }
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing freeze fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int) u64 { mut x := u64(sample) + u64(0x9e3779b97f4a7c15); x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, expected u64, kind airbitcode.IRScalarKind, bits u32, steps int) ! {
	if actual.kind != kind || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('freeze result/metadata differs') }
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-freeze self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(262144); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free(); c.typ.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('freeze fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-freeze'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM freeze parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tinput\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0; mut integer_api := 0
	for c in cases {
		name := 'keep_${c.name}'; reference_name := 'reference_${name}'; defer { unsafe { name.free(); reference_name.free() } }; index := function_index(ir, name)!
		address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing freeze reference') }; reference := unsafe { NativeBits(voidptr(address)) }
		limit := if c.kind == .integer { if c.bits <= 16 { int(u64(1) << c.bits) } else { 4096 } } else { 65536 }
		for sample in 0 .. limit + 16 {
			full := mask(c.bits); sign := u64(1) << (c.bits - 1)
			edges := [u64(0), full, sign, sign - 1, sign + 1, u64(1), full - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0x7c00, 0xfc00, 0x7c01, 0x7f800000, 0xff800000, 0x7f800001]!
			raw := if sample < 16 { edges[sample] } else if c.bits <= 16 { u64(sample - 16) } else { pattern(sample) }
			args := [raw | ~full]; defer { unsafe { args.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := reference(args[0])
			compare(actual, expected, c.kind, c.bits, 2)!
			if expected != args[0] & full { panic('native freeze did not preserve raw bits') }
			row := '${name}\t${args[0]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < 16 { boundaries++ }
			if c.kind == .integer && sample < 16 { run := p.run_integer_function(ir, stream, pools, bodies, index, args, 2)!; if run.bits != c.bits || run.poison || run.value != expected || run.steps != 2 { panic('integer freeze API mismatch') }; integer_api++ }
		}
	}
	mut choice_controls := 0; mut property_controls := 0; mut raw_controls := 0; mut budget_controls := 0
	empty := []u64{}; defer { unsafe { empty.free() } }
	for c in cases { for state in ['poison', 'undef'] {
		choice := 'choice_${c.name}_${state}'; raw := 'raw_${c.name}_${state}'; defer { unsafe { choice.free(); raw.free() } }
		index := function_index(ir, choice)!; compare(p.run_scalar_function(ir, stream, pools, bodies, index, empty, 2)!, 0, c.kind, c.bits, 2)!; choice_controls++
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, empty, 1) { panic('freeze budget ignored') } else { budget_controls++ }
		if state == 'undef' { if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, raw)!, empty, 2) { panic('unfrozen undef accepted') } } else { if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, raw)!, empty, 2)!.poison { panic('unfrozen poison lost') } }; raw_controls++
		for family in ['stable', 'branch'] {
			name := '${family}_${c.name}_${state}'; defer { unsafe { name.free() } }; slot := function_index(ir, name)!
			steps := if family == 'branch' { 6 } else { if c.bits == 64 { 3 } else { 4 } } + if c.kind == .integer { 0 } else { 1 }
			address := C.LLVMGetFunctionAddress(engine, name.str); if address == 0 { panic('missing freeze property reference') }; reference := unsafe { NativeProperty(voidptr(address)) }; expected := reference(); if expected != 0 { panic('native freeze property failed') }
			compare(p.run_scalar_function(ir, stream, pools, bodies, slot, empty, steps)!, expected, .integer, 64, steps)!; property_controls++
		}
	} }
	mut shift_controls := 0
	for width in u32(1) .. 65 {
		name := 'shift_i${width}'; defer { unsafe { name.free() } }; index := function_index(ir, name)!
		for amount in [u64(0), 1, u64(width - 1), u64(width), u64(width + 1), mask(width)]! {
			args := [u64(3), amount]; defer { unsafe { args.free() } }; n := amount & mask(width)
			expected := if n >= width { u64(0) } else { ((u64(3) & mask(width)) << n) & mask(width) }
			compare(p.run_scalar_function(ir, stream, pools, bodies, index, args, 3)!, expected, .integer, width, 3)!; shift_controls++
		}
	}
	loop_index := function_index(ir, 'loop')!; loop_address := C.LLVMGetFunctionAddress(engine, c'reference_loop'); if loop_address == 0 { panic('missing loop reference') }; loop_reference := unsafe { NativeBits(voidptr(loop_address)) }
	for raw in 0 .. 256 { args := [u64(raw) | ~u64(255)]; defer { unsafe { args.free() } }; compare(p.run_scalar_function(ir, stream, pools, bodies, loop_index, args, 34)!, loop_reference(args[0]), .integer, 8, 34)! }
	compare(p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'frozen_condition')!, empty, 3)!, 0, .integer, 1, 3)!
	mut profile_controls := 0
	for name in ['outside_3', 'outside_8', 'outside_6', 'outside_4'] { if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, [u64(0)], 3) { panic('non-profile freeze accepted') } else { profile_controls++ } }
	for c in cases { if c.kind == .integer { continue }; name := 'keep_${c.name}'; defer { unsafe { name.free() } }; if _ := p.run_integer_function(ir, stream, pools, bodies, function_index(ir, name)!, [u64(0)], 2) { panic('integer API accepted floating freeze') } else { profile_controls++ } }
	mut metadata_controls := 0
	for name in ['keep_i32', 'dead'] {
		index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start + if name == 'dead' { 1 } else { 0 }; original := p.instructions[slot]
		args := if name == 'dead' { []u64{} } else { [u64(19)] }; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: 1}, airbitcode.IRTypedInstruction{...original, opcode: 1}, airbitcode.IRTypedInstruction{...original, operands_count: 0}, airbitcode.IRTypedInstruction{...original, result_type: -1}] {
			p.instructions[slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 16) { panic('malformed freeze accepted') } else { metadata_controls++ }
		}; p.instructions[slot] = original
		operand_slot := original.operands_start; saved := p.operands[operand_slot]
		mut other_type := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 1 { other_type = i; break } }; if other_type < 0 { panic('missing control type') }
		p.operands[operand_slot] = airbitcode.IRTypedOperand{...saved, type_index: other_type}
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 16) { panic('freeze type mismatch accepted') } else { metadata_controls++ }; p.operands[operand_slot] = saved
	}
	index := function_index(ir, 'keep_i32')!; args := [u64(19)]; defer { unsafe { args.free() } }; baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 2)!
	mut result_controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: 20}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] {
		compare(changed, 19, .integer, 32, 2) or { result_controls++; continue }; panic('corrupted freeze result accepted')
	}
	if cases.len != 66 || comparisons != 459806 || boundaries != 1056 || integer_api != 1024 || choice_controls != 132 || property_controls != 264 || raw_controls != 132 || budget_controls != 132 || shift_controls != 384 || profile_controls != 6 || metadata_controls != 10 || result_controls != 5 { panic('freeze coverage incomplete') }
	println('LLVM-SCALAR-FREEZE: ${cases.len} scalar types, ${comparisons} exact defined comparisons (${boundaries} boundary inputs); ${integer_api} integer API/${choice_controls} fixed-choice/${property_controls} native consistency-branch-PHI/${raw_controls} unfrozen/${budget_controls} budget/${shift_controls} computed-shift/${profile_controls} profile/${metadata_controls} metadata/${result_controls} result-corruption controls, 256 native four-iteration loops and frozen branch condition PASS; no AIR shader or iOS app executed')
}
