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
	source.write_string('%Named = type {i32, i1}\n')
	for n in u32(1) .. 65 {
		declaration := 'declare {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n}, i${n})\n'; source.write_string(declaration); unsafe { declaration.free() }
		for field in 0 .. 2 {
			ret_bits := if field == 0 { n } else { u32(1) }; own := if field == 0 { '%a' } else { '%flag' }
			for mode in ['keep', 'overflow', 'zero', 'partial', 'select', 'phi', 'loop', 'stable_poison', 'stable_undef'] {
				name := '${mode}_${n}_${field}'; cases << PairCase{name, mode, n, field}; control_bits := if mode == 'loop' { 8 } else { 1 }
				header := 'define i${ret_bits} @${name}(i${n} %a, i1 %flag, i${control_bits} %c) {\nentry:\n'; source.write_string(header); unsafe { header.free() }
				body := match mode {
					'keep' { '  %data = insertvalue {i${n}, i1} zeroinitializer, i${n} %a, 0\n  %p = insertvalue {i${n}, i1} %data, i1 %flag, 1\n  %f = freeze {i${n}, i1} %p\n  %x = extractvalue {i${n}, i1} %f, ${field}\n' }
					'overflow' { '  %p = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} %a, i${n} 1)\n  %f = freeze {i${n}, i1} %p\n  %x = extractvalue {i${n}, i1} %f, ${field}\n' }
					'zero' { '  %f = freeze {i${n}, i1} zeroinitializer\n  %x = extractvalue {i${n}, i1} %f, ${field}\n' }
					'partial' { '  %p = insertvalue {i${n}, i1} poison, i${ret_bits} ${own}, ${field}\n  %f = freeze {i${n}, i1} %p\n  %x = extractvalue {i${n}, i1} %f, ${field}\n' }
					'select' { '  %p = insertvalue {i${n}, i1} poison, i${ret_bits} ${own}, ${field}\n  %s = select i1 %c, {i${n}, i1} %p, {i${n}, i1} zeroinitializer\n  %f = freeze {i${n}, i1} %s\n  %x = extractvalue {i${n}, i1} %f, ${field}\n' }
					'phi' { '  br i1 %c, label %yes, label %no\nyes:\n  %p = insertvalue {i${n}, i1} poison, i${ret_bits} ${own}, ${field}\n  br label %join\nno:\n  br label %join\njoin:\n  %s = phi {i${n}, i1} [ %p, %yes ], [ zeroinitializer, %no ]\n  %f = freeze {i${n}, i1} %s\n  %x = extractvalue {i${n}, i1} %f, ${field}\n' }
					'loop' {
						last := if field == 0 { '  %x = extractvalue {i${n}, i1} %f, 0\n' } else { '  %flagout = extractvalue {i${n}, i1} %f, 1\n  %x = xor i1 %flagout, %flagout\n' }
						text := '  %empty = icmp eq i8 %c, 0\n  br i1 %empty, label %join, label %body\nbody:\n  %p = phi {i${n}, i1} [ zeroinitializer, %entry ], [ %nextpair, %body ]\n  %i = phi i8 [ 0, %entry ], [ %next, %body ]\n  %badflag = insertvalue {i${n}, i1} %p, i1 poison, 1\n  %frozen = freeze {i${n}, i1} %badflag\n  %old = extractvalue {i${n}, i1} %frozen, 0\n  %sum = add i${n} %old, %a\n  %nextpair = insertvalue {i${n}, i1} %frozen, i${n} %sum, 0\n  %next = add i8 %i, 1\n  %done = icmp eq i8 %next, %c\n  br i1 %done, label %join, label %body\njoin:\n  %s = phi {i${n}, i1} [ zeroinitializer, %entry ], [ %nextpair, %body ]\n  %f = freeze {i${n}, i1} %s\n${last}'; unsafe { last.free() }; text
					}
					else {
						seed := if mode == 'stable_poison' { 'poison' } else { 'undef' }
						// Two extractions of the same dynamic choice must agree. Native
						// arbitrary choices themselves never cross this comparison ABI.
						'  %f = freeze {i${n}, i1} ${seed}\n  %a1 = extractvalue {i${n}, i1} %f, ${field}\n  %a2 = extractvalue {i${n}, i1} %f, ${field}\n  %x = xor i${ret_bits} %a1, %a2\n'
					}
				}
				ending := '  ret i${ret_bits} %x\n}\n'; source.write_string(body); source.write_string(ending); wrapper(mut source, cases.last()); unsafe { body.free(); ending.free() }
			}
			for mode in ['poison', 'undef', 'partial', 'call', 'condition'] {
				prefix := match mode {
					'poison', 'undef' { '' }
					'partial' { other := 1 - field; other_bits := if other == 0 { n } else { u32(1) }; value := if other == 0 { '%a' } else { '%flag' }; '  %p = insertvalue {i${n}, i1} poison, i${other_bits} ${value}, ${other}\n' }
					'call' { '  %p = call {i${n}, i1} @llvm.uadd.with.overflow.i${n}(i${n} poison, i${n} %a)\n' }
					else { '  %p = select i1 poison, {i${n}, i1} zeroinitializer, {i${n}, i1} poison\n' }
				}
				seed := if mode in ['poison', 'undef']! { mode } else { '%p' }
				text := 'define i${ret_bits} @choice_${mode}_${n}_${field}(i${n} %a, i1 %flag, i1 %c) {\n${prefix}  %f = freeze {i${n}, i1} ${seed}\n  %x = extractvalue {i${n}, i1} %f, ${field}\n  ret i${ret_bits} %x\n}\n'; source.write_string(text); unsafe { if prefix.len > 0 { prefix.free() }; text.free() }
			}
			for bad in ['undef_insert', 'division'] {
				prefix := if bad == 'undef_insert' { '  %p = insertvalue {i${n}, i1} poison, i${n} undef, 0\n' } else { '  %d = udiv i${n} %a, 0\n  %p = insertvalue {i${n}, i1} poison, i${n} %d, 0\n' }
				text := 'define i${ret_bits} @reject_${bad}_${n}_${field}(i${n} %a, i1 %flag, i1 %c) {\n${prefix}  %f = freeze {i${n}, i1} %p\n  %x = extractvalue {i${n}, i1} %f, ${field}\n  ret i${ret_bits} %x\n}\n'; source.write_string(text); unsafe { prefix.free(); text.free() }
			}
		}
	}
	for i, typ in ['<{i32, i1}>', '%Named', '[2 x i32]', '{{i32, i1}, i1}', '{i65, i1}', '{float, i1}'] {
		text := 'define i32 @outside_${i}() {\n  %f = freeze ${typ} poison\n  ret i32 7\n}\n'; source.write_string(text); unsafe { text.free() }
	}
	source.write_string('define i32 @dead() {\n  ret i32 7\nunused:\n  %f = freeze {i32, i1} poison\n  %x = extractvalue {i32, i1} %f, 0\n  ret i32 %x\n}\ndefine i32 @bad_constant() {\n  %f = freeze {i32, i1} {i32 7, i1 true}\n  %x = extractvalue {i32, i1} %f, 0\n  ret i32 %x\n}\n')
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing pair freeze fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int) u64 { mut x := u64(sample) + u64(0x9e3779b97f4a7c15); x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn count(c PairCase, choice int) int { return match c.mode { 'zero' { 3 } 'overflow', 'partial' { 4 } 'keep', 'select', 'stable_poison', 'stable_undef' { 5 } 'phi' { 6 + choice } else { 6 + c.field + 10 * choice } } }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! { if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('pair freeze value/kind/width/poison/steps differ') } }
fn native(engine voidptr, name string) !NativeBits { key := 'reference_${name}'; defer { unsafe { key.free() } }; address := C.LLVMGetFunctionAddress(engine, key.str); if address == 0 { return error('missing pair freeze wrapper') }; return unsafe { NativeBits(voidptr(address)) } }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-pair-freeze self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait(); stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }; os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('pair freeze assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT(); context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-pair-freeze'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM pair freeze parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }; mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }; triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }; identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tdata\tflag\tcontrol\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0; mut isolation := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference := native(engine, c.name)!; bits := if c.field == 0 { c.bits } else { u32(1) }; full := mask(c.bits); sign := u64(1) << (c.bits - 1)
		for sample in 0 .. 256 {
			edges := [u64(0), full, sign, sign - 1, sign + 1, u64(1), full - 1, u64(2), u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, u64(0), full, sign, sign - 1]!
			for choice in 0 .. if c.mode == 'loop' { 6 } else if c.mode in ['select', 'phi']! { 2 } else { 1 } {
				a := if sample < 16 { edges[sample] } else { pattern(sample) }; args := [a | ~full, u64(sample) | ~u64(1), u64(choice) | if c.mode == 'loop' { ~u64(255) } else { ~u64(1) }]; defer { unsafe { args.free() } }; steps := count(c, choice); expected := reference(args[0], args[1], args[2]); actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, steps)!; compare(actual, expected, bits, steps)!
				own := if c.field == 0 { args[0] & full } else { args[1] & 1 }
				if c.mode in ['keep', 'partial']! && expected != own { panic('native freeze changed defined field') }
				if c.mode in ['select', 'phi']! && expected != if choice == 1 { own } else { u64(0) } { panic('native flow changed defined field') }
				if (c.mode in ['zero', 'stable_poison', 'stable_undef']! || (c.mode == 'loop' && c.field == 1)) && expected != 0 { panic('native freeze zero/consistency property failed') }
				if c.mode == 'loop' && c.field == 0 && expected != (args[0] * u64(choice)) & full { panic('native loop changed defined accumulation') }
				row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < 16 { boundaries++ }
			}
		}
		choice := if c.mode == 'loop' { 3 } else { 0 }; args := [u64(1), 1, u64(choice)]; defer { unsafe { args.free() } }
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, count(c, choice) - 1) { panic('pair freeze budget ignored') } else { isolation++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 100) { panic('integer API accepted pair freeze') } else { isolation++ }
		if c.mode == 'loop' { long_args := [u64(1), 1, u64(255)]; defer { unsafe { long_args.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, long_args, 64) { panic('freeze loop unbounded') } else { isolation++ } }
	}
	mut choices := 0; mut preceding := 0
	for n in u32(1) .. 65 { for field in 0 .. 2 {
		args := [u64(19), 1, 0]; defer { unsafe { args.free() } }; bits := if field == 0 { n } else { u32(1) }
		for mode in ['poison', 'undef', 'partial', 'call', 'condition'] { name := 'choice_${mode}_${n}_${field}'; defer { unsafe { name.free() } }; steps := if mode in ['poison', 'undef']! { 3 } else { 4 }; compare(p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, steps)!, 0, bits, steps)!; choices++ }
		for mode in ['undef_insert', 'division'] { name := 'reject_${mode}_${n}_${field}'; defer { unsafe { name.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 32) { panic('freeze bypassed earlier unsupported/undefined input') } else { preceding++ } }
	} }
	mut profiles := 0
	for i in 0 .. 6 { name := 'outside_${i}'; defer { unsafe { name.free() } }; if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, []u64{}, 10) { panic('freeze admitted unsupported layout') } else { profiles++ } }
	if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'bad_constant')!, []u64{}, 10) { panic('freeze admitted aggregate record') } else { profiles++ }
	mut metadata := 0
	for name in ['keep_32_0', 'dead'] {
		index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start + if name == 'dead' { 1 } else { 2 }; saved := p.instructions[slot]; args := if name == 'dead' { []u64{} } else { [u64(19), 1, 0] }; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}] { p.instructions[slot] = changed; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('pair freeze metadata accepted') } else { metadata++ } }; p.instructions[slot] = saved
		operand := p.operands[saved.operands_start]; mut wrong_type := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 1 { wrong_type = i; break } }; assert wrong_type >= 0
		p.operands[saved.operands_start] = airbitcode.IRTypedOperand{...operand, type_index: wrong_type}; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 100) { panic('pair freeze operand type accepted') } else { metadata++ }; p.operands[saved.operands_start] = operand
	}
	index := function_index(ir, 'keep_32_0')!; args := [u64(19), 1, 0]; defer { unsafe { args.free() } }; baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 5)!; mut corruptions := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: 20}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 1}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 4}] { compare(changed, 19, 32, 5) or { corruptions++; continue }; panic('freeze output corruption accepted') }
	if cases.len != 1152 || comparisons != 524288 || boundaries != 32768 || isolation != 2432 || choices != 640 || preceding != 256 || profiles != 7 || metadata != 16 || corruptions != 5 { panic('pair freeze coverage incomplete: ${cases.len}/${comparisons}/${boundaries}/${isolation}/${choices}/${preceding}/${profiles}/${metadata}/${corruptions}') }
	println('LLVM-PAIR-FREEZE: ${cases.len} functions, ${comparisons} exact native defined/property comparisons (${boundaries} edge results), i1..i64 field preservation/partial poison/select/PHIs/loops and choice-independent repeated uses; ${isolation} budget-integer/${choices} zero-choice/${preceding} preceding-error/${profiles} profile/${metadata} live-dead-metadata/${corruptions} output-corruption controls PASS; no AIR shader or iOS app executed')
}
