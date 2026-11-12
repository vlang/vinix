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
#include <llvm-c/Error.h>
#include <llvm-c/Transforms/PassBuilder.h>
fn C.LLVMContextCreate() voidptr
fn C.LLVMContextDispose(voidptr)
fn C.LLVMCreateMemoryBufferWithMemoryRangeCopy(voidptr, usize, &char) voidptr
fn C.LLVMDisposeMemoryBuffer(voidptr)
fn C.LLVMParseBitcodeInContext2(voidptr, voidptr, &voidptr) int
fn C.LLVMDisposeModule(voidptr)
fn C.LLVMDisposeMessage(&char)
fn C.LLVMVerifyModule(voidptr, int, &&char) int
fn C.LLVMCreatePassBuilderOptions() voidptr
fn C.LLVMDisposePassBuilderOptions(voidptr)
fn C.LLVMRunPasses(voidptr, &char, voidptr, voidptr) voidptr
fn C.LLVMGetErrorMessage(voidptr) &char
fn C.LLVMDisposeErrorMessage(&char)
fn C.LLVMPrintModuleToString(voidptr) &char
fn C.LLVMGetNamedFunction(voidptr, &char) voidptr
fn C.LLVMGetFirstBasicBlock(voidptr) voidptr
fn C.LLVMGetBasicBlockTerminator(voidptr) voidptr
fn C.LLVMGetOperand(voidptr, u32) voidptr
fn C.LLVMGetAggregateElement(voidptr, u32) voidptr
fn C.LLVMIsAConstantInt(voidptr) voidptr
fn C.LLVMConstIntGetZExtValue(voidptr) u64

struct FlagCase { name string bits u32 opcode int flags int a u64 b u64 }
fn input_word(sample int, bits u32) u64 {
	mask := if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 }
	sign := u64(1) << (bits - 1)
	return match sample % 12 {
		0 { u64(0) } 1 { mask } 2 { sign } 3 { sign - 1 }
		4 { u64(1) } 5 { u64(2) & mask } 6 { mask - 1 }
		7 { u64(bits) & mask } 8 { u64(bits - 1) & mask }
		else { ((u64(sample) * u64(0x9e3779b97f4a7c15)) ^ u64(0xfedcba9876543210)) & mask }
	}
}
fn fixture(mut source strings.Builder, bits u32) []FlagCase {
	mut cases := []FlagCase{cap: 2048}; cases.flags |= .noslices
	mask := if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 }
	for op, mnemonic in ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr'] {
		if op in [5, 6]! { continue } // Remainder has no EXACT flag.
		for flags in 1 .. if op in [0, 1, 2, 7]! { 4 } else { 2 } {
			flag := if op !in [0, 1, 2, 7]! { 'exact' } else if flags == 1 { 'nuw' } else if flags == 2 { 'nsw' } else { 'nuw nsw' }
			for sample in 0 .. 128 {
				mut a := input_word(sample, bits); mut b := input_word(127 - sample, bits)
				if op in [3, 4]! {
					if b == 0 { b = 1 }
					if op == 4 && a == u64(1) << (bits - 1) && b == mask { a ^= 1 }
				}
				name := 'case_${cases.len}'
				entry := FlagCase{name, bits, op, flags, a, b}; unsafe { cases.push_many(&entry, 1) }
				line := 'define void @${name}(ptr %a, ptr %b, ptr %dst) {\n %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n %v = ${mnemonic} ${flag} i${bits} %x, %y\n store i${bits} %v, ptr %dst, align 1\n ret void\n}\n'; source.write_string(line); unsafe { line.free() }
			}
		}
	}
	return cases
}
// A defined {bits, poison-tag} oracle is essential: optimizing actual poison
// may refine it to any value. i128 holds every signed product and result here;
// unflagged operations, masked shift amounts and valid divisors stay defined.
fn oracle(cases []FlagCase, mut source strings.Builder) {
	for c in cases {
		bits := c.bits; op := c.opcode
		mask := if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 }; sign := u64(1) << (bits - 1)
		header := 'define {i64, i1} @${c.name}() {\n  %ux = zext i${bits} ${c.a} to i128\n  %uy = zext i${bits} ${c.b} to i128\n  %sx = sext i${bits} ${c.a} to i128\n  %sy = sext i${bits} ${c.b} to i128\n'; source.write_string(header); unsafe { header.free() }
		if op in [7, 8, 9]! {
			line := '  %amount = urem i128 %uy, ${bits}\n  %overshift = icmp uge i128 %uy, ${bits}\n'; source.write_string(line); unsafe { line.free() }
		}
		if op in [0, 1, 2, 7]! {
			mnemonic := match op { 0 { 'add' } 1 { 'sub' } 2 { 'mul' } else { 'shl' } }
			line := '  %u = ${mnemonic} i128 %ux, ${if op == 7 { '%amount' } else { '%uy' }}\n  %s = ${mnemonic} i128 %sx, ${if op == 7 { '%amount' } else { '%sy' }}\n  %ubad = icmp ugt i128 %u, ${mask}\n  %slo = icmp slt i128 %s, -${sign}\n  %shi = icmp sgt i128 %s, ${sign - 1}\n  %sbad = or i1 %slo, %shi\n'; source.write_string(line); unsafe { line.free() }
			bad := if c.flags == 1 { '%ubad, false' } else if c.flags == 2 { '%sbad, false' } else { '%ubad, %sbad' }
			combine := '  %overflow = or i1 ${bad}\n  %bad = or i1 %overflow, ${if op == 7 { '%overshift' } else { 'false' }}\n'; source.write_string(combine); unsafe { combine.free() }
		} else if op in [3, 4]! {
			prefix := if op == 3 { 'u' } else { 's' }; lhs := if op == 3 { '%ux' } else { '%sx' }; rhs := if op == 3 { '%uy' } else { '%sy' }
			line := '  %u = ${prefix}div i128 ${lhs}, ${rhs}\n  %remainder = ${prefix}rem i128 ${lhs}, ${rhs}\n  %bad = icmp ne i128 %remainder, 0\n'; source.write_string(line); unsafe { line.free() }
		} else {
			mnemonic := if op == 8 { 'lshr' } else { 'ashr' }; lhs := if op == 8 { '%ux' } else { '%sx' }
			line := '  %u = ${mnemonic} i128 ${lhs}, %amount\n  %factor = shl i128 1, %amount\n  %remainder = urem i128 %ux, %factor\n  %inexact = icmp ne i128 %remainder, 0\n  %bad = or i1 %inexact, %overshift\n'; source.write_string(line); unsafe { line.free() }
		}
		if bits == 64 { source.write_string('  %out = trunc i128 %u to i64\n') } else {
			line := '  %narrow = trunc i128 %u to i${bits}\n  %out = zext i${bits} %narrow to i64\n'; source.write_string(line); unsafe { line.free() }
		}
		source.write_string('  %pair = insertvalue {i64, i1} zeroinitializer, i64 %out, 0\n  %tagged = insertvalue {i64, i1} %pair, i1 %bad, 1\n  ret {i64, i1} %tagged\n}\n')
	}
}
fn assemble(assembler string, out string, stem string) ! {
	mut process := os.new_process(assembler); defer { process.close() }; process.set_args([out + '/${stem}.ll', '-o', out + '/${stem}.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/${stem}-assemble.log', log)!; os.write_file(out + '/${stem}-assemble.status', status)!; if process.code != 0 { return error('LLVM fixture assembly failed') }
}
fn compare(actual []u8, value u64, poison bool, rejected bool, count int) ! {
	if rejected != poison { return error('AIR memory flags: lost poison or rejected defined value') }
	for i, byte in actual {
		want := if !poison && i >= 3 && i < 3 + count { u8(value >> u32(8 * (i - 3))) } else { u8(0xcc) }
		if byte != want { return error('AIR memory flags: value/padding/sentinel mismatch') }
	}
}
struct FlagCounts { values int poison int controls int }
fn run_batch(assembler string, out string, bits u32) !FlagCounts {
	os.mkdir(out)!
	mut source := strings.new_builder(2 * 1024 * 1024); defer { unsafe { source.free() } }
	cases := fixture(mut source, bits); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	assemble(assembler, out, 'input')!
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	mut reference_source := strings.new_builder(4 * 1024 * 1024); defer { unsafe { reference_source.free() } }; oracle(cases, mut reference_source)
	reference_text := reference_source.str(); defer { unsafe { reference_text.free() } }; os.write_file(out + '/oracle.ll', reference_text)!; assemble(assembler, out, 'oracle')!
	reference_data := os.read_bytes(out + '/oracle.bc')!; defer { unsafe { reference_data.free() } }
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(reference_data.data, usize(reference_data.len), c'generated-flags-oracle'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM fixture parse failed') }; defer { C.LLVMDisposeModule(module_ptr) }
	mut message := &char(unsafe { nil })
	if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
	options := C.LLVMCreatePassBuilderOptions(); defer { C.LLVMDisposePassBuilderOptions(options) }
	err := C.LLVMRunPasses(module_ptr, c'function(instcombine)', unsafe { nil }, options)
	if err != unsafe { nil } { detail := C.LLVMGetErrorMessage(err); saved := unsafe { cstring_to_vstring(detail) }.clone(); C.LLVMDisposeErrorMessage(detail); panic(saved) }
	folded := C.LLVMPrintModuleToString(module_ptr); defer { C.LLVMDisposeMessage(folded) }; os.write_file(out + '/folded.ll', unsafe { cstring_to_vstring(folded) })!
	if ir.functions.len != cases.len || cases.len != 2048 { panic('fixture inventory mismatch') }
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tbits\topcode\tflags\ta\tb\trejected\tllvm\tllvm_poison')!
	mut poison_count := 0; mut value_count := 0
	mut baseline := []u8{}; mut baseline_value := u64(0); count := int((bits + 7) / 8)
	defer { unsafe { baseline.free() } }
	for i, c in cases {
		if ir.functions[i].name != c.name { panic('fixture function order') }
		reference := C.LLVMGetNamedFunction(module_ptr, c.name.str); if reference == unsafe { nil } { panic('missing LLVM reference function') }
		value := C.LLVMGetOperand(C.LLVMGetBasicBlockTerminator(C.LLVMGetFirstBasicBlock(reference)), 0)
		value_bits := C.LLVMGetAggregateElement(value, 0); poison_tag := C.LLVMGetAggregateElement(value, 1)
		if value_bits == unsafe { nil } || poison_tag == unsafe { nil } || C.LLVMIsAConstantInt(value_bits) == unsafe { nil } || C.LLVMIsAConstantInt(poison_tag) == unsafe { nil } { panic('LLVM failed to fold defined reference tags') }
		poison := C.LLVMConstIntGetZExtValue(poison_tag) != 0
		expected := C.LLVMConstIntGetZExtValue(value_bits)
		mut left := []u8{len: 16}; mut right := []u8{len: 16}; mut actual := []u8{len: 24, init: 0xcc}
		for j in 0 .. count { left[1 + j] = u8(c.a >> u32(8 * j)); right[2 + j] = u8(c.b >> u32(8 * j)) }
		mut bindings := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
		mut rejected := false
		if run := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 5) { assert run.steps == 5 } else { assert err.msg() == 'AIR memory execution: poison store', err.msg(); rejected = true }
		compare(actual, expected, poison, rejected, count)!
		row := '${c.name}\t${c.bits}\t${c.opcode}\t${c.flags}\t${c.a}\t${c.b}\t${rejected}\t${expected}\t${poison}'; results.writeln(row)!; unsafe { row.free() }
		if poison { poison_count++ } else { if baseline.len == 0 { baseline = actual.clone(); baseline_value = expected }; value_count++ }
		for j in 0 .. actual.len { actual[j] = 0xcc }
		if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc }
		unsafe { left.free(); right.free(); actual.free(); bindings.free() }
	}
	if poison_count == 0 || value_count == 0 { panic('fixture must exercise both poison and defined results') }
	mut controls := 0
	compare(baseline, baseline_value ^ 1, false, false, count) or { controls++ }
	compare(baseline, baseline_value, false, true, count) or { controls++ }
	compare(baseline, baseline_value, true, false, count) or { controls++ }
	baseline[3] ^= 1; compare(baseline, baseline_value, false, false, count) or { controls++ }
	assert controls == 4
	mut bytes := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	slot := bodies.scopes[1].instructions_start + 2; saved := p.instructions[slot]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 8}, airbitcode.IRTypedInstruction{...saved, opcode: 10, flags: 1}] {
		p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, 0, mut bindings, 5) { panic('unknown/wrong-family flags accepted') } else { assert err.msg() == 'AIR memory execution: unsupported flags', err.msg() }; for byte in bytes { assert byte == 0xcc }; controls++
	}; p.instructions[slot] = saved; unsafe { bytes.free(); bindings.free() }
	println('LLVM-MEMORY-FLAGS-i${bits}: ${cases.len} folded reference comparisons (${value_count} values, ${poison_count} rejected poison stores); ${controls} corruption/flag controls PASS')
	return FlagCounts{value_count, poison_count, controls}
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-memory-flags self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]
	if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut values := 0; mut poison := 0; mut controls := 0
	for bits in u32(1) .. 65 {
		batch := '${out}/i${bits}'; defer { unsafe { batch.free() } }
		counts := run_batch(os.args[2], batch, bits)!
		values += counts.values; poison += counts.poison; controls += counts.controls
	}
	assert values + poison == 131072 && controls == 384
	println('LLVM-MEMORY-FLAGS: ${values + poison} defined widened LLVM comparisons (${values} values, ${poison} rejected poison stores), all NUW/NSW/combined/EXACT families at i1..i64, load/compute/store/padding/budgets; ${controls} corruption/flag controls PASS; no native poison executed')
}
