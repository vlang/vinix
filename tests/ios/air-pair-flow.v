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
type NativeBits = fn (u64, u64, u64) u64

struct PairCase { name string mode string bits u32 field int }
fn wrapper(mut source strings.Builder, c PairCase) {
	width := c.bits; result_bits := if c.field == 0 { width } else { u32(1) }; cond_bits := if c.mode == 'loop' { 8 } else { 1 }
	cast := if width == 64 { '' } else { '  %a = trunc i64 %ai to i${width}\n  %b = trunc i64 %bi to i${width}\n' }
	a := if width == 64 { '%ai' } else { '%a' }; b := if width == 64 { '%bi' } else { '%b' }
	ending := if result_bits == 64 { '  ret i64 %r\n' } else { '  %wide = zext i${result_bits} %r to i64\n  ret i64 %wide\n' }
	text := 'define i64 @reference_${c.name}(i64 %ai, i64 %bi, i64 %ci) {\n${cast}  %c = trunc i64 %ci to i${cond_bits}\n  %r = call i${result_bits} @${c.name}(i${width} ${a}, i${width} ${b}, i${cond_bits} %c)\n${ending}}\n'
	source.write_string(text); unsafe { cast.free(); ending.free(); text.free() }
}
fn fixture(mut source strings.Builder) []PairCase {
	mut cases := []PairCase{}
	for width in u32(1) .. 65 {
		declarations := 'declare {i${width}, i1} @llvm.uadd.with.overflow.i${width}(i${width}, i${width})\ndeclare {i${width}, i1} @llvm.usub.with.overflow.i${width}(i${width}, i${width})\n'; source.write_string(declarations); unsafe { declarations.free() }
		for field in 0 .. 2 {
			ret_bits := if field == 0 { width } else { u32(1) }
			for mode in ['select', 'diamond', 'loop'] {
				name := '${mode}_${width}_${field}'; cases << PairCase{name, mode, width, field}
				cond_bits := if mode == 'loop' { 8 } else { 1 }
				header := 'define i${ret_bits} @${name}(i${width} %a, i${width} %b, i${cond_bits} %c) {\nentry:\n  %left = call {i${width}, i1} @llvm.uadd.with.overflow.i${width}(i${width} %a, i${width} %b)\n  %right = call {i${width}, i1} @llvm.usub.with.overflow.i${width}(i${width} %a, i${width} %b)\n'
				source.write_string(header); unsafe { header.free() }
				body := if mode == 'select' {
					'  %out = select i1 %c, {i${width}, i1} %left, {i${width}, i1} %right\n'
				} else if mode == 'diamond' {
					'  br i1 %c, label %yes, label %no\nyes:\n  br label %join\nno:\n  br label %join\njoin:\n  %out = phi {i${width}, i1} [ %left, %yes ], [ %right, %no ]\n'
				} else {
					'  %empty = icmp eq i8 %c, 0\n  br i1 %empty, label %zero, label %body\nzero:\n  br label %join\nbody:\n  %p = phi {i${width}, i1} [ %left, %entry ], [ %q, %body ]\n  %q = phi {i${width}, i1} [ %right, %entry ], [ %p, %body ]\n  %i = phi i8 [ 0, %entry ], [ %next, %body ]\n  %next = add i8 %i, 1\n  %done = icmp eq i8 %next, %c\n  br i1 %done, label %join, label %body\njoin:\n  %out = phi {i${width}, i1} [ %left, %zero ], [ %p, %body ]\n'
				}
				ending := '  %r = extractvalue {i${width}, i1} %out, ${field}\n  ret i${ret_bits} %r\n}\n'; source.write_string(body); source.write_string(ending); wrapper(mut source, cases.last())
				if mode == 'loop' {
					poison_header := 'define i${ret_bits} @poison_loop_${width}_${field}(i${width} %a, i${width} %b, i8 %c) {\nentry:\n  %left = call {i${width}, i1} @llvm.uadd.with.overflow.i${width}(i${width} %a, i${width} %b)\n  %right = call {i${width}, i1} @llvm.usub.with.overflow.i${width}(i${width} poison, i${width} %b)\n'
					source.write_string(poison_header); source.write_string(body); source.write_string(ending); unsafe { poison_header.free() }
				}
				unsafe { body.free(); ending.free() }
			}
			for side in 0 .. 2 {
				left := if side == 0 { 'poison' } else { '%a' }; right := if side == 1 { 'poison' } else { '%a' }
				text := 'define i${ret_bits} @poison_${width}_${field}_${side}(i${width} %a, i${width} %b, i1 %c) {\n  %left = call {i${width}, i1} @llvm.uadd.with.overflow.i${width}(i${width} ${left}, i${width} %b)\n  %right = call {i${width}, i1} @llvm.usub.with.overflow.i${width}(i${width} ${right}, i${width} %b)\n  %out = select i1 %c, {i${width}, i1} %left, {i${width}, i1} %right\n  %r = extractvalue {i${width}, i1} %out, ${field}\n  ret i${ret_bits} %r\n}\n'; source.write_string(text); unsafe { text.free() }
			}
			for state in ['poison', 'undef'] { for frozen in 0 .. if state == 'poison' { 2 } else { 1 } {
				freeze_line := if frozen == 1 { '  %f = freeze i${ret_bits} %r\n' } else { '' }; result := if frozen == 1 { '%f' } else { '%r' }
				text := 'define i${ret_bits} @condition_${state}_${width}_${field}_${frozen}(i${width} %a, i${width} %b, i1 %c) {\n  %left = call {i${width}, i1} @llvm.uadd.with.overflow.i${width}(i${width} %a, i${width} %b)\n  %right = call {i${width}, i1} @llvm.usub.with.overflow.i${width}(i${width} %a, i${width} %b)\n  %out = select i1 ${state}, {i${width}, i1} %left, {i${width}, i1} %right\n  %r = extractvalue {i${width}, i1} %out, ${field}\n${freeze_line}  ret i${ret_bits} ${result}\n}\n'; source.write_string(text); unsafe { freeze_line.free(); text.free() }
			} }
			text := 'define i${ret_bits} @poison_phi_${width}_${field}(i${width} %a, i${width} %b, i1 %c) {\n  br i1 %c, label %yes, label %no\nyes:\n  %left = call {i${width}, i1} @llvm.uadd.with.overflow.i${width}(i${width} %a, i${width} %b)\n  br label %join\nno:\n  %right = call {i${width}, i1} @llvm.usub.with.overflow.i${width}(i${width} poison, i${width} %b)\n  br label %join\njoin:\n  %out = phi {i${width}, i1} [ %left, %yes ], [ %right, %no ]\n  %r = extractvalue {i${width}, i1} %out, ${field}\n  ret i${ret_bits} %r\n}\n'; source.write_string(text); unsafe { text.free() }
		}
	}
	source.write_string('define i32 @constant_select(i32 %a, i32 %b, i1 %c) {\n  %p = call {i32, i1} @llvm.uadd.with.overflow.i32(i32 %a, i32 %b)\n  %s = select i1 %c, {i32, i1} %p, {i32, i1} undef\n  %r = extractvalue {i32, i1} %s, 0\n  ret i32 %r\n}\ndefine i32 @constant_phi(i32 %a, i32 %b, i1 %c) {\n  br label %join\njoin:\n  %p = phi {i32, i1} [ undef, %0 ]\n  %r = extractvalue {i32, i1} %p, 0\n  ret i32 %r\n}\ndefine i32 @wrong_pair(i32 %a, i32 %b, i1 %c) {\n  %p = select i1 %c, {i32, i8} zeroinitializer, {i32, i8} zeroinitializer\n  %r = extractvalue {i32, i8} %p, 0\n  ret i32 %r\n}\ndefine i32 @packed_pair(i32 %a, i32 %b, i1 %c) {\n  %p = select i1 %c, <{i32, i1}> zeroinitializer, <{i32, i1}> zeroinitializer\n  %r = extractvalue <{i32, i1}> %p, 0\n  ret i32 %r\n}\n')
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing pair flow fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int, salt u64) u64 { mut x := u64(sample) + salt; x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn steps(mode string, count int) int { return if mode == 'select' { 5 } else if mode == 'diamond' { 7 } else if count == 0 { 8 } else { 7 + 6 * count } }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, count int) ! {
	if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != count { return error('pair flow bits/metadata differ from native LLVM') }
}
fn native(engine voidptr, name string) !NativeBits { key := 'reference_${name}'; defer { unsafe { key.free() } }; address := C.LLVMGetFunctionAddress(engine, key.str); if address == 0 { return error('missing pair flow wrapper') }; return unsafe { NativeBits(voidptr(address)) } }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-pair-flow self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(1048576); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('pair flow assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-pair-flow'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM pair flow parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tcontrol\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0; mut isolation_controls := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference := native(engine, c.name)!; result_bits := if c.field == 0 { c.bits } else { u32(1) }; full := mask(c.bits); sign := u64(1) << (c.bits - 1)
		for sample in 0 .. 256 {
			edges := [u64(0), full, sign, sign - 1, u64(0), sign + 1, u64(1), full - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, u64(0), full, sign, sign - 1]!
			other := [u64(0), 1, full, u64(1), full, sign, u64(1), 2, u64(0x5555555555555555), 0xaaaaaaaaaaaaaaaa, 0xfedcba9876543210, 0x0123456789abcdef, sign, full, u64(2), sign]!
			a := if sample < 16 { edges[sample] } else { pattern(sample, 0x9e3779b97f4a7c15) }; b := if sample < 16 { other[sample] } else { pattern(sample, 0x123456789abcdef0) }
			for choice in 0 .. if c.mode == 'loop' { 6 } else { 2 } {
				control := u64(choice) | if c.mode == 'loop' { ~u64(255) } else { ~u64(1) }; args := [a | ~full, b | ~full, control]; defer { unsafe { args.free() } }; count := steps(c.mode, choice)
				actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, count)!; expected := reference(args[0], args[1], args[2]); compare(actual, expected, result_bits, count)!
				row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < 16 { boundaries++ }
			}
		}
		choice := if c.mode == 'loop' { 3 } else { 0 }; args := [u64(0), full, u64(choice)]; defer { unsafe { args.free() } }
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, steps(c.mode, choice) - 1) { panic('pair flow budget ignored') } else { isolation_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 100) { panic('integer API accepted pair flow') } else { isolation_controls++ }
		if c.mode == 'loop' { long_args := [u64(0), full, u64(255)]; defer { unsafe { long_args.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, long_args, 64) { panic('pair loop unbounded') } else { isolation_controls++ } }
	}
	mut poison_controls := 0; mut lazy_controls := 0; mut undef_controls := 0; mut frozen_controls := 0
	for width in u32(1) .. 65 { for field in 0 .. 2 {
		result_bits := if field == 0 { width } else { u32(1) }; name := 'select_${width}_${field}'; defer { unsafe { name.free() } }; reference := native(engine, name)!
		for choice in 0 .. 2 {
			args := [u64(0), mask(width), u64(choice)]; defer { unsafe { args.free() } }
			for side in 0 .. 2 {
				key := 'poison_${width}_${field}_${side}'; defer { unsafe { key.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, key)!, args, 5)!
				if (choice == 1 && side == 0) || (choice == 0 && side == 1) { if !actual.poison || actual.bits != result_bits || actual.steps != 5 { panic('selected pair poison lost') }; poison_controls++ } else { compare(actual, reference(args[0], args[1], args[2]), result_bits, 5)!; lazy_controls++ }
			}
			key := 'poison_phi_${width}_${field}'; defer { unsafe { key.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, key)!, args, 6)!
			if choice == 0 { if !actual.poison || actual.bits != result_bits || actual.steps != 6 { panic('PHI pair poison lost') }; poison_controls++ } else { compare(actual, reference(args[0], args[1], 1), result_bits, 6)!; lazy_controls++ }
		}
		args := [u64(0), mask(width), u64(0)]; defer { unsafe { args.free() } }
		for frozen in 0 .. 2 {
			key := 'condition_poison_${width}_${field}_${frozen}'; defer { unsafe { key.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, key)!, args, 5 + frozen)!
			if frozen == 0 { if !actual.poison || actual.bits != result_bits || actual.steps != 5 { panic('poison pair condition lost') }; poison_controls++ } else { compare(actual, 0, result_bits, 6)!; frozen_controls++ }
		}
		key := 'condition_undef_${width}_${field}_0'; defer { unsafe { key.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, key)!, args, 10) { panic('undef condition accepted') } else { undef_controls++ }
		loop_name := 'poison_loop_${width}_${field}'; defer { unsafe { loop_name.free() } }; loop_index := function_index(ir, loop_name)!
		for rounds in 0 .. 6 {
			inputs := [u64(0), mask(width), u64(rounds)]; defer { unsafe { inputs.free() } }; count := steps('loop', rounds)
			actual := p.run_scalar_function(ir, stream, pools, bodies, loop_index, inputs, count)!
			if rounds > 0 && rounds % 2 == 0 { if !actual.poison || actual.bits != result_bits || actual.steps != count { panic('parallel pair PHI poison lost') }; poison_controls++ } else { compare(actual, reference(inputs[0], inputs[1], 1), result_bits, count)!; lazy_controls++ }
		}
	} }
	args := [u64(0), 0xffffffff, u64(1)]; defer { unsafe { args.free() } }; mut profile_controls := 0
	for name in ['constant_select', 'constant_phi', 'wrong_pair', 'packed_pair'] { if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 100) { panic('unsupported pair flow accepted') } else { profile_controls++ } }
	mut metadata_controls := 0
	for name in ['select_32_0', 'diamond_32_0'] {
		index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start + if name.starts_with('select') { 2 } else { 5 }; saved := p.instructions[slot]
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, targets_count: if name.starts_with('select') { 1 } else { 0 }}] {
			p.instructions[slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('pair flow metadata accepted') } else { metadata_controls++ }
		}; p.instructions[slot] = saved
		for side in 0 .. 2 {
			operand_slot := saved.operands_start + side; operand := p.operands[operand_slot]
			for changed in [airbitcode.IRTypedOperand{...operand, number: 0}, airbitcode.IRTypedOperand{...operand, type_index: -1}] {
				p.operands[operand_slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('pair flow operand accepted') } else { metadata_controls++ }
			}; p.operands[operand_slot] = operand
		}
		if name.starts_with('select') {
			condition_slot := saved.operands_start + 2; condition := p.operands[condition_slot]
			mut i32_type := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 32 { i32_type = i; break } }; if i32_type < 0 { panic('missing condition control type') }
			p.operands[condition_slot] = airbitcode.IRTypedOperand{...condition, type_index: i32_type}
			if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('pair condition wider than i1 accepted') } else { metadata_controls++ }; p.operands[condition_slot] = condition
		}
	}
	index := function_index(ir, 'select_32_0')!; baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 5)!; mut result_controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 1}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 4}] {
		compare(changed, baseline.value, 32, 5) or { result_controls++; continue }; panic('pair flow output corruption accepted')
	}
	if cases.len != 384 || comparisons != 327680 || boundaries != 20480 || isolation_controls != 896 || poison_controls != 768 || lazy_controls != 896 || undef_controls != 128 || frozen_controls != 128 || profile_controls != 4 || metadata_controls != 19 || result_controls != 5 { panic('pair flow coverage incomplete') }
	println('LLVM-PAIR-FLOW: ${cases.len} functions, ${comparisons} exact native comparisons (${boundaries} boundary results), i1..i64 data/flag selection, branch PHIs and parallel pair/scalar loop PHIs; ${isolation_controls} budget-integer/${poison_controls} poison/${lazy_controls} lazy/${undef_controls} undef/${frozen_controls} frozen/${profile_controls} profile/${metadata_controls} metadata/${result_controls} output-corruption controls PASS; no AIR shader or iOS app executed')
}
