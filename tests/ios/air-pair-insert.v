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

struct InsertCase { name string mode string bits u32 field int out int }
fn wrapper(mut source strings.Builder, c InsertCase) {
	n := c.bits; input_bits := if c.field == 0 { n } else { u32(1) }; output_bits := if c.out == 0 { n } else { u32(1) }
	cast := if n == 64 { '' } else { '  %a = trunc i64 %ai to i${n}\n  %b = trunc i64 %bi to i${n}\n' }; a := if n == 64 { '%ai' } else { '%a' }; b := if n == 64 { '%bi' } else { '%b' }
	cast_r := if input_bits == 64 { '' } else { '  %r = trunc i64 %ri to i${input_bits}\n' }; r := if input_bits == 64 { '%ri' } else { '%r' }
	ending := if output_bits == 64 { '  ret i64 %x\n' } else { '  %wide = zext i${output_bits} %x to i64\n  ret i64 %wide\n' }
	text := 'define i64 @reference_${c.name}(i64 %ai, i64 %bi, i64 %ri) {\n${cast}${cast_r}  %x = call i${output_bits} @${c.name}(i${n} ${a}, i${n} ${b}, i${input_bits} ${r})\n${ending}}\n'; source.write_string(text); unsafe { cast.free(); cast_r.free(); ending.free(); text.free() }
}
fn fixture(mut source strings.Builder) []InsertCase {
	mut cases := []InsertCase{}
	for n in u32(1) .. 65 {
		declaration := 'declare {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n}, i${n})\n'; source.write_string(declaration); unsafe { declaration.free() }
		for mode in ['normal', 'clear', 'repair', 'full'] { for field in 0 .. 2 { for out in 0 .. 2 {
			if (mode == 'repair' && out != field) || (mode == 'full' && field != 1) { continue }
			name := '${mode}_${n}_${field}_${out}'; cases << InsertCase{name, mode, n, field, out}
			input_bits := if field == 0 { n } else { u32(1) }; output_bits := if out == 0 { n } else { u32(1) }; first := if mode in ['repair', 'full']! { 'poison' } else { '%a' }
			body := if mode == 'clear' { '  %bad = insertvalue {i${n}, i1} %base, i${input_bits} poison, ${field}\n  %pair = insertvalue {i${n}, i1} %bad, i${input_bits} %r, ${field}\n' } else if mode == 'full' { '  %data = insertvalue {i${n}, i1} %base, i${n} %a, 0\n  %pair = insertvalue {i${n}, i1} %data, i1 %r, 1\n' } else { '  %pair = insertvalue {i${n}, i1} %base, i${input_bits} %r, ${field}\n' }
			text := 'define i${output_bits} @${name}(i${n} %a, i${n} %b, i${input_bits} %r) {\n  %base = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} ${first}, i${n} %b)\n${body}  %x = extractvalue {i${n}, i1} %pair, ${out}\n  ret i${output_bits} %x\n}\n'; source.write_string(text); wrapper(mut source, cases.last()); unsafe { body.free(); text.free() }
			if mode == 'normal' { for state in ['poison', 'undef'] {
				control := 'define i${output_bits} @${state}_${n}_${field}_${out}(i${n} %a, i${n} %b, i${input_bits} %r) {\n  %base = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} %a, i${n} %b)\n  %pair = insertvalue {i${n}, i1} %base, i${input_bits} ${state}, ${field}\n  %x = extractvalue {i${n}, i1} %pair, ${out}\n  ret i${output_bits} %x\n}\n'; source.write_string(control); unsafe { control.free() }
			} }
		} } }
		for field in 0 .. 2 {
			input_bits := if field == 0 { n } else { u32(1) }; other := 1 - field; output_bits := if other == 0 { n } else { u32(1) }
			for frozen in 0 .. 2 {
				freeze_line := if frozen == 1 { '  %f = freeze i${output_bits} %x\n' } else { '' }; result := if frozen == 1 { '%f' } else { '%x' }
				text := 'define i${output_bits} @partial_${n}_${field}_${frozen}(i${n} %a, i${n} %b, i${input_bits} %r) {\n  %base = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} poison, i${n} %b)\n  %pair = insertvalue {i${n}, i1} %base, i${input_bits} %r, ${field}\n  %x = extractvalue {i${n}, i1} %pair, ${other}\n${freeze_line}  ret i${output_bits} ${result}\n}\n'; source.write_string(text); unsafe { freeze_line.free(); text.free() }
			}
		}
		for out in 0 .. 2 {
			output_bits := if out == 0 { n } else { u32(1) }
			prefix := '  %base = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} %a, i${n} %b)\n  %left = insertvalue {i${n}, i1} %base, i${n} poison, 0\n  %right = insertvalue {i${n}, i1} %base, i1 poison, 1\n'
			select_text := 'define i${output_bits} @select_${n}_${out}(i${n} %a, i${n} %b, i1 %c) {\n${prefix}  %pair = select i1 %c, {i${n}, i1} %left, {i${n}, i1} %right\n  %x = extractvalue {i${n}, i1} %pair, ${out}\n  ret i${output_bits} %x\n}\n'
			loop_text := 'define i${output_bits} @loop_${n}_${out}(i${n} %a, i${n} %b, i8 %c) {\nentry:\n${prefix}  %empty = icmp eq i8 %c, 0\n  br i1 %empty, label %zero, label %body\nzero:\n  br label %join\nbody:\n  %p = phi {i${n}, i1} [ %left, %entry ], [ %q, %body ]\n  %q = phi {i${n}, i1} [ %right, %entry ], [ %p, %body ]\n  %i = phi i8 [ 0, %entry ], [ %next, %body ]\n  %next = add i8 %i, 1\n  %done = icmp eq i8 %next, %c\n  br i1 %done, label %join, label %body\njoin:\n  %pair = phi {i${n}, i1} [ %left, %zero ], [ %p, %body ]\n  %x = extractvalue {i${n}, i1} %pair, ${out}\n  ret i${output_bits} %x\n}\n'
			source.write_string(select_text); source.write_string(loop_text); unsafe { prefix.free(); select_text.free(); loop_text.free() }
		}
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing pair insertion fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int, salt u64) u64 { mut x := u64(sample) + salt; x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! { if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('pair insertion bits/metadata differ from native LLVM') } }
fn poisoned(actual airbitcode.IRScalarRun, bits u32, steps int) ! { if actual.kind != .integer || actual.bits != bits || !actual.poison || actual.steps != steps { return error('pair insertion poison/metadata lost') } }
fn native(engine voidptr, name string) !NativeBits { key := 'reference_${name}'; defer { unsafe { key.free() } }; address := C.LLVMGetFunctionAddress(engine, key.str); if address == 0 { return error('missing pair insertion wrapper') }; return unsafe { NativeBits(voidptr(address)) } }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-pair-insert self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }; os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('pair insertion assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-pair-insert'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM pair insertion parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\treplacement\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0; mut isolation_controls := 0; mut poison_controls := 0; mut unaffected_controls := 0; mut undef_controls := 0; mut frozen_controls := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference := native(engine, c.name)!; full := mask(c.bits); sign := u64(1) << (c.bits - 1); bits := if c.out == 0 { c.bits } else { u32(1) }; steps := if c.mode in ['clear', 'full']! { 5 } else { 4 }
		for sample in 0 .. 1024 {
			edges := [u64(0), full, sign, sign - 1, sign + 1, u64(1), full - 1, u64(2), u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, u64(0), full, sign, sign - 1]!
			a := if sample < 16 { edges[sample] } else { pattern(sample, 0x9e3779b97f4a7c15) }; b := if sample < 16 { edges[15 - sample] } else { pattern(sample, 0x123456789abcdef0) }; r := if sample < 16 { edges[(sample + 3) % 16] } else { pattern(sample, 0xfedcba9876543210) }
			args := [a | ~full, b | ~full, r | ~mask(if c.field == 0 { c.bits } else { u32(1) })]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, steps)!; expected := reference(args[0], args[1], args[2]); compare(actual, expected, bits, steps)!
			row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < 16 { boundaries++ }
		}
		args := [u64(0), full, u64(1)]; defer { unsafe { args.free() } }
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, steps - 1) { panic('insert budget ignored') } else { isolation_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 100) { panic('integer API accepted pair insertion') } else { isolation_controls++ }
		if c.mode == 'normal' {
			key := 'poison_${c.bits}_${c.field}_${c.out}'; undef_key := 'undef_${c.bits}_${c.field}_${c.out}'; defer { unsafe { key.free(); undef_key.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, key)!, args, 4)!
			if c.field == c.out { poisoned(actual, bits, 4)!; poison_controls++ } else { compare(actual, reference(args[0], args[1], args[2]), bits, 4)!; unaffected_controls++ }
			if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_key)!, args, 100) { panic('undef replacement accepted') } else { undef_controls++ }
		}
		if c.mode == 'repair' {
			for frozen in 0 .. 2 {
				key := 'partial_${c.bits}_${c.field}_${frozen}'; defer { unsafe { key.free() } }; other_bits := if c.field == 0 { u32(1) } else { c.bits }; actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, key)!, args, 4 + frozen)!
				if frozen == 0 { poisoned(actual, other_bits, 4)!; poison_controls++ } else { compare(actual, 0, other_bits, 5)!; frozen_controls++ }
			}
		}
	}
	for n in u32(1) .. 65 { for output_field in 0 .. 2 {
		bits := if output_field == 0 { n } else { u32(1) }; base_name := 'normal_${n}_${1 - output_field}_${output_field}'; defer { unsafe { base_name.free() } }; reference := native(engine, base_name)!
		for mode in ['select', 'loop'] {
			name := '${mode}_${n}_${output_field}'; defer { unsafe { name.free() } }; index := function_index(ir, name)!
			for choice in 0 .. if mode == 'loop' { 6 } else { 2 } {
				args := [u64(0), mask(n), u64(choice)]; defer { unsafe { args.free() } }; left := if mode == 'select' { choice == 1 } else { choice == 0 || choice % 2 == 1 }; is_poison := if output_field == 0 { left } else { !left }; steps := if mode == 'select' { 6 } else if choice == 0 { 9 } else { 8 + 6 * choice }
				actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, steps)!
				if is_poison { poisoned(actual, bits, steps)!; poison_controls++ } else { compare(actual, reference(args[0], args[1], 0), bits, steps)!; unaffected_controls++ }
			}
			if mode == 'loop' { args := [u64(0), mask(n), u64(255)]; defer { unsafe { args.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) { panic('partial-poison loop unbounded') } else { isolation_controls++ } }
		}
	} }
	args := [u64(0), 0xffffffff, u64(3)]; defer { unsafe { args.free() } }; index := function_index(ir, 'normal_32_1_0')!; slot := bodies.scopes[index + 1].instructions_start + 1; saved := p.instructions[slot]; mut metadata_controls := 0
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, source_type: -1}, airbitcode.IRTypedInstruction{...saved, indices_count: 0}, airbitcode.IRTypedInstruction{...saved, indices_start: -1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}] {
		p.instructions[slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('insert metadata accepted') } else { metadata_controls++ }
	}; p.instructions[slot] = saved
	field := p.indices[saved.indices_start]; p.indices[saved.indices_start] = 2
	if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('out-of-range insert accepted') } else { metadata_controls++ }; p.indices[saved.indices_start] = field
	for side in 0 .. 2 {
		operand_slot := saved.operands_start + side; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: -1}
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('insert operand type accepted') } else { metadata_controls++ }; p.operands[operand_slot] = operand
	}
	base_slot := saved.operands_start; original_base := p.operands[base_slot]; p.operands[base_slot] = airbitcode.IRTypedOperand{...original_base, number: 0}
	if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('constant pair insertion accepted') } else { metadata_controls++ }; p.operands[base_slot] = original_base
	baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 4)!; mut result_controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 1}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 3}] { compare(changed, baseline.value, 32, 4) or { result_controls++; continue }; panic('insert result corruption accepted') }
	bad := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'poison_32_1_1')!, args, 4)!
	poisoned(airbitcode.IRScalarRun{...bad, poison: false}, 1, 4) or { result_controls++ }
	if cases.len != 768 || comparisons != 786432 || boundaries != 12288 || isolation_controls != 1664 || poison_controls != 768 || unaffected_controls != 640 || undef_controls != 256 || frozen_controls != 128 || metadata_controls != 12 || result_controls != 6 { panic('pair insertion coverage incomplete') }
	println('LLVM-PAIR-INSERT: ${cases.len} functions, ${comparisons} exact native comparisons (${boundaries} boundary results), i1..i64 replacement/neighbor preservation/poison repair; ${isolation_controls} budget-integer/${poison_controls} poison/${unaffected_controls} unaffected/${undef_controls} undef/${frozen_controls} frozen/${metadata_controls} metadata/${result_controls} output-corruption controls, including partial poison through select and parallel loop PHIs PASS; no AIR shader or iOS app executed')
}
