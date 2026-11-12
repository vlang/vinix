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
	n := c.bits; result_bits := if c.field == 0 { n } else { u32(1) }; control_bits := if c.mode == 'loop' { 8 } else { 1 }
	cast := if n == 64 { '' } else { '  %a = trunc i64 %ai to i${n}\n' }; a := if n == 64 { '%ai' } else { '%a' }
	ending := if result_bits == 64 { '  ret i64 %x\n' } else { '  %wide = zext i${result_bits} %x to i64\n  ret i64 %wide\n' }
	text := 'define i64 @reference_${c.name}(i64 %ai, i64 %fi, i64 %ci) {\n${cast}  %flag = trunc i64 %fi to i1\n  %c = trunc i64 %ci to i${control_bits}\n  %x = call i${result_bits} @${c.name}(i${n} ${a}, i1 %flag, i${control_bits} %c)\n${ending}}\n'; source.write_string(text); unsafe { cast.free(); ending.free(); text.free() }
}
fn fixture(mut source strings.Builder) []PairCase {
	mut cases := []PairCase{}
	for n in u32(1) .. 65 {
		declaration := 'declare {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n}, i${n})\n'; source.write_string(declaration); unsafe { declaration.free() }
		for field in 0 .. 2 {
			ret_bits := if field == 0 { n } else { u32(1) }
			for mode in ['zero', 'build_zero', 'build_poison', 'partial', 'select', 'phi', 'repair_phi', 'loop'] {
				name := '${mode}_${n}_${field}'; cases << PairCase{name, mode, n, field}; control_bits := if mode == 'loop' { 8 } else { 1 }
				header := 'define i${ret_bits} @${name}(i${n} %a, i1 %flag, i${control_bits} %c) {\nentry:\n'; source.write_string(header); unsafe { header.free() }
				body := match mode {
					'zero' { '  %x = extractvalue {i${n}, i1} zeroinitializer, ${field}\n' }
					'build_zero', 'build_poison' {
						seed := if mode == 'build_zero' { 'zeroinitializer' } else { 'poison' }
						'  %data = insertvalue {i${n}, i1} ${seed}, i${n} %a, 0\n  %pair = insertvalue {i${n}, i1} %data, i1 %flag, 1\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n'
					}
					'partial' {
						value := if field == 0 { '%a' } else { '%flag' }
						'  %pair = insertvalue {i${n}, i1} poison, i${ret_bits} ${value}, ${field}\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n'
					}
					'select' { '  %p = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} %a, i${n} 1)\n  %pair = select i1 %c, {i${n}, i1} %p, {i${n}, i1} zeroinitializer\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' }
					'phi', 'repair_phi' {
						seed := if mode == 'phi' { 'zeroinitializer' } else { 'poison' }
						repair := if mode == 'phi' { '' } else { '  %data = insertvalue {i${n}, i1} %pair, i${n} %a, 0\n  %fixed = insertvalue {i${n}, i1} %data, i1 %flag, 1\n' }; pair := if mode == 'phi' { '%pair' } else { '%fixed' }
						text := '  br i1 %c, label %yes, label %no\nyes:\n  %p = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} %a, i${n} 1)\n  br label %join\nno:\n  br label %join\njoin:\n  %pair = phi {i${n}, i1} [ %p, %yes ], [ ${seed}, %no ]\n${repair}  %x = extractvalue {i${n}, i1} ${pair}, ${field}\n'; unsafe { repair.free() }; text
					}
					else { '  %empty = icmp eq i8 %c, 0\n  br i1 %empty, label %join, label %body\nbody:\n  %p = phi {i${n}, i1} [ zeroinitializer, %entry ], [ %nextpair, %body ]\n  %i = phi i8 [ 0, %entry ], [ %next, %body ]\n  %old = extractvalue {i${n}, i1} %p, 0\n  %sum = add i${n} %old, %a\n  %nextpair = insertvalue {i${n}, i1} %p, i${n} %sum, 0\n  %next = add i8 %i, 1\n  %done = icmp eq i8 %next, %c\n  br i1 %done, label %join, label %body\njoin:\n  %pair = phi {i${n}, i1} [ zeroinitializer, %entry ], [ %nextpair, %body ]\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' }
				}
				ending := '  ret i${ret_bits} %x\n}\n'; source.write_string(body); source.write_string(ending); wrapper(mut source, cases.last()); unsafe { body.free(); ending.free() }
			}
			for mode in ['extract', 'select', 'phi'] {
				body := if mode == 'extract' { '  %x = extractvalue {i${n}, i1} poison, ${field}\n' } else if mode == 'select' { '  %pair = select i1 %c, {i${n}, i1} poison, {i${n}, i1} zeroinitializer\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' } else { '  br i1 %c, label %yes, label %no\nyes:\n  br label %join\nno:\n  br label %join\njoin:\n  %pair = phi {i${n}, i1} [ poison, %yes ], [ zeroinitializer, %no ]\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' }
				text := 'define i${ret_bits} @poison_${mode}_${n}_${field}(i${n} %a, i1 %flag, i1 %c) {\n${body}  ret i${ret_bits} %x\n}\n'; source.write_string(text); unsafe { body.free(); text.free() }
			}
			for frozen in 0 .. 2 {
				other := 1 - field; inserted_bits := if other == 0 { n } else { u32(1) }; value := if other == 0 { '%a' } else { '%flag' }; freeze_line := if frozen == 1 { '  %f = freeze i${ret_bits} %x\n' } else { '' }; result := if frozen == 1 { '%f' } else { '%x' }
				text := 'define i${ret_bits} @partial_poison_${n}_${field}_${frozen}(i${n} %a, i1 %flag, i1 %c) {\n  %pair = insertvalue {i${n}, i1} poison, i${inserted_bits} ${value}, ${other}\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n${freeze_line}  ret i${ret_bits} ${result}\n}\n'; source.write_string(text); unsafe { freeze_line.free(); text.free() }
			}
			for kind in ['undef', 'aggregate'] { for consumer in ['extract', 'insert', 'select', 'phi'] {
				seed := if kind == 'undef' { 'undef' } else { '{i${n} 1, i1 true}' }
				body := match consumer {
					'extract' { '  %x = extractvalue {i${n}, i1} ${seed}, ${field}\n' }
					'insert' { '  %p = insertvalue {i${n}, i1} ${seed}, i${n} %a, 0\n  %pair = insertvalue {i${n}, i1} %p, i1 %flag, 1\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' }
					'select' { '  %pair = select i1 %c, {i${n}, i1} zeroinitializer, {i${n}, i1} ${seed}\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' }
					else { '  br label %join\njoin:\n  %pair = phi {i${n}, i1} [ ${seed}, %0 ]\n  %x = extractvalue {i${n}, i1} %pair, ${field}\n' }
				}
				text := 'define i${ret_bits} @reject_${kind}_${consumer}_${n}_${field}(i${n} %a, i1 %flag, i1 %c) {\n${body}  ret i${ret_bits} %x\n}\n'; source.write_string(text); unsafe { if kind == 'aggregate' { seed.free() }; body.free(); text.free() }
			} }
		}
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing pair constant fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int) u64 { mut x := u64(sample) + u64(0x9e3779b97f4a7c15); x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn count(mode string, choice int) int { return match mode { 'zero' { 2 } 'build_zero', 'build_poison', 'select' { 4 } 'partial' { 3 } 'phi' { 5 + choice } 'repair_phi' { 7 + choice } else { 5 + 8 * choice } } }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! { if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('pair constant result/metadata mismatch') } }
fn poisoned(actual airbitcode.IRScalarRun, bits u32, steps int) ! { if actual.kind != .integer || actual.bits != bits || !actual.poison || actual.steps != steps { return error('pair constant poison/metadata lost') } }
fn native(engine voidptr, name string) !NativeBits { key := 'reference_${name}'; defer { unsafe { key.free() } }; address := C.LLVMGetFunctionAddress(engine, key.str); if address == 0 { return error('missing pair constant wrapper') }; return unsafe { NativeBits(voidptr(address)) } }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-pair-constants self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait(); stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }; os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('pair constant assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT(); context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-pair-constants'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM pair constant parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }; mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }; triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }; identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tdata\tflag\tcontrol\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0; mut isolation := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference := native(engine, c.name)!; bits := if c.field == 0 { c.bits } else { u32(1) }; full := mask(c.bits); sign := u64(1) << (c.bits - 1)
		for sample in 0 .. 256 {
			edges := [u64(0), full, sign, sign - 1, sign + 1, u64(1), full - 1, u64(2), u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, u64(0), full, sign, sign - 1]!
			for choice in 0 .. if c.mode == 'loop' { 6 } else if c.mode in ['select', 'phi', 'repair_phi']! { 2 } else { 1 } {
				a := if sample < 16 { edges[sample] } else { pattern(sample) }; args := [a | ~full, u64(sample) | ~u64(1), u64(choice) | if c.mode == 'loop' { ~u64(255) } else { ~u64(1) }]; defer { unsafe { args.free() } }; steps := count(c.mode, choice); expected := reference(args[0], args[1], args[2]); actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, steps)!; compare(actual, expected, bits, steps)!
				if c.mode == 'zero' || (c.mode == 'loop' && c.field == 1) { if expected != 0 { panic('native zero seed changed') } }
				if c.mode in ['build_zero', 'build_poison', 'partial', 'repair_phi']! { if expected != if c.field == 0 { args[0] & full } else { args[1] & 1 } { panic('native repaired seed differs') } }
				if c.mode == 'loop' && c.field == 0 && expected != (args[0] * u64(choice)) & full { panic('native zero-seeded loop sum differs') }
				row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < 16 { boundaries++ }
			}
		}
		choice := if c.mode == 'loop' { 3 } else { 0 }; args := [u64(1), 1, u64(choice)]; defer { unsafe { args.free() } }
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, count(c.mode, choice) - 1) { panic('constant consumer budget ignored') } else { isolation++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 100) { panic('integer API accepted pair constants') } else { isolation++ }
		if c.mode == 'loop' { long_args := [u64(1), 1, u64(255)]; defer { unsafe { long_args.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, long_args, 64) { panic('constant-seeded loop unbounded') } else { isolation++ } }
	}
	mut poison_controls := 0; mut zero_controls := 0; mut frozen_controls := 0; mut rejection_controls := 0
	for width in u32(1) .. 65 { for field in 0 .. 2 {
		bits := if field == 0 { width } else { u32(1) }
		for mode in ['extract', 'select', 'phi'] { for choice in 0 .. if mode == 'extract' { 1 } else { 2 } {
			name := 'poison_${mode}_${width}_${field}'; defer { unsafe { name.free() } }; args := [u64(7), 1, u64(choice)]; defer { unsafe { args.free() } }; steps := if mode == 'extract' { 2 } else if mode == 'select' { 3 } else { 5 }; actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, steps)!
			if mode == 'extract' || choice == 1 { poisoned(actual, bits, steps)!; poison_controls++ } else { compare(actual, 0, bits, steps)!; zero_controls++ }
		} }
		for frozen in 0 .. 2 { name := 'partial_poison_${width}_${field}_${frozen}'; defer { unsafe { name.free() } }; args := [u64(7), 1, 0]; defer { unsafe { args.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 3 + frozen)!; if frozen == 0 { poisoned(actual, bits, 3)!; poison_controls++ } else { compare(actual, 0, bits, 4)!; frozen_controls++ } }
		for kind in ['undef', 'aggregate'] { for consumer in ['extract', 'insert', 'select', 'phi'] { name := 'reject_${kind}_${consumer}_${width}_${field}'; defer { unsafe { name.free() } }; args := [u64(7), 1, 1]; defer { unsafe { args.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 100) { panic('unsupported pair constant admitted') } else { rejection_controls++ } } }
	} }
	index := function_index(ir, 'zero_32_0')!; slot := bodies.scopes[index + 1].instructions_start; saved := p.instructions[slot]; args := [u64(1), 1, 0]; defer { unsafe { args.free() } }; mut metadata := 0
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, indices_count: 0}, airbitcode.IRTypedInstruction{...saved, source_type: -1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}] { p.instructions[slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('constant extraction metadata accepted') } else { metadata++ } }; p.instructions[slot] = saved
	field_index := p.indices[saved.indices_start]; p.indices[saved.indices_start] = 2; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('constant extract index accepted') } else { metadata++ }; p.indices[saved.indices_start] = field_index
	operand := p.operands[saved.operands_start]; value := pools.lookup(index + 1, operand.number)!; mut constants := pools.constants.clone(); defer { unsafe { constants.free() } }; changed_pools := airbitcode.IRConstantPools{...pools, constants: constants}; original := constants[value.constant_index]; mut constant_controls := 0
	for changed in [airbitcode.IRConstant{...original, kind: .undef}, airbitcode.IRConstant{...original, kind: .aggregate}, airbitcode.IRConstant{...original, splat: true}, airbitcode.IRConstant{...original, type_index: -1}] { constants[value.constant_index] = changed; if _ := p.run_scalar_function(ir, stream, changed_pools, bodies, index, args, 100) { panic('pair constant metadata accepted') } else { constant_controls++ } }; constants[value.constant_index] = original
	baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 2)!; mut output_controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 1}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] { compare(changed, 0, 32, 2) or { output_controls++; continue }; panic('constant output corruption accepted') }
	if cases.len != 1024 || comparisons != 524288 || boundaries != 32768 || isolation != 2176 || poison_controls != 512 || zero_controls != 256 || frozen_controls != 128 || rejection_controls != 1024 || metadata != 6 || constant_controls != 4 || output_controls != 5 { panic('pair constant coverage incomplete') }
	println('LLVM-PAIR-CONSTANTS: ${cases.len} functions, ${comparisons} exact native comparisons (${boundaries} edge results), i1..i64 zero/poison construction/extraction/select/PHIs/loops; ${isolation} budget-integer/${poison_controls} poison/${zero_controls} zero/${frozen_controls} frozen/${rejection_controls} unsupported-kind/${metadata} extraction-metadata/${constant_controls} constant-metadata/${output_controls} output-corruption controls PASS; no AIR shader or iOS app executed')
}
