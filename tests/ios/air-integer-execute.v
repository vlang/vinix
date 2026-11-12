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
type NativeInteger = fn (u64, u64, u64) u64

enum CaseKind { binary comparison extension control switch_table dense_switch }
struct ExecutionCase { name string kind CaseKind bits u32 opcode int }
fn switch_fixtures(mut source strings.Builder, mut cases []ExecutionCase) {
	for bits in [u32(1), 2, 7, 8, 16, 31, 32, 63, 64]! {
		name := 'switch_${bits}'; entry := ExecutionCase{name, .switch_table, bits, 0}; unsafe { cases.push_many(&entry, 1) }
		header := 'define i64 @${name}(i64 %a, i64 %b, i64 %c) {\nentry:\n'; source.write_string(header); unsafe { header.free() }
		if bits != 64 { cast := '  %key = trunc i64 %a to i${bits}\n'; source.write_string(cast); unsafe { cast.free() } }
		line := '  switch i${bits} ${if bits == 64 { '%a' } else { '%key' }}, label %join [ i${bits} 0, label %zero\n'; source.write_string(line); unsafe { line.free() }
		if bits == 1 { source.write_string('    i1 1, label %hit ]\n') } else {
			mask := if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 }; sign := u64(1) << (bits - 1)
			table := '    i${bits} 1, label %join\n    i${bits} ${sign}, label %hit\n    i${bits} ${mask}, label %join ]\n'; source.write_string(table); unsafe { table.free() }
		}
		source.write_string('zero:\n  %z = add i64 %b, 3\n  br label %join\nhit:\n  %h = xor i64 %c, %a\n  br label %join\njoin:\n  %v = phi i64 [ %b, %entry ]')
		if bits != 1 { source.write_string(', [ %b, %entry ], [ %b, %entry ]') }
		source.write_string(', [ %z, %zero ], [ %h, %hit ]\n  ret i64 %v\n}\n')
	}
	for name in ['switch_empty', 'switch_loop'] { entry := ExecutionCase{name.clone(), .control, 64, 0}; unsafe { cases.push_many(&entry, 1) } }
	source.write_string('define i64 @switch_empty(i64 %a, i64 %b, i64 %c) {
  switch i64 %a, label %exit [ ]
exit:
  %v = xor i64 %b, %c
  ret i64 %v
}
define i64 @switch_loop(i64 %a, i64 %b, i64 %c) {
entry:
  %n = and i64 %c, 15
  br label %loop
loop:
  %x = phi i64 [ %a, %entry ], [ %y, %body ]
  %y = phi i64 [ %b, %entry ], [ %x, %body ]
  %i = phi i64 [ %n, %entry ], [ %dec, %body ]
  switch i64 %i, label %body [ i64 0, label %exit ]
body:
  %dec = sub i64 %i, 1
  br label %loop
exit:
  %v = sub i64 %x, %y
  ret i64 %v
}
define i64 @switch_dense8(i64 %a, i64 %b, i64 %c) {
  %key = trunc i64 %a to i8
  switch i8 %key, label %other [
')
	for i in 0 .. 256 { line := '    i8 ${i}, label %case${i}\n'; source.write_string(line); unsafe { line.free() } }
	source.write_string('  ]\nother:\n  ret i64 -1\n')
	for i in 0 .. 256 { line := 'case${i}:\n  ret i64 ${(i * 37) ^ 127}\n'; source.write_string(line); unsafe { line.free() } }
	source.write_string('}\n')
	dense := ExecutionCase{'switch_dense8'.clone(), .dense_switch, 8, 0}; unsafe { cases.push_many(&dense, 1) }
	source.write_string('define i64 @guard_poison_switch(i64 %a, i64 %b, i64 %c) {
  switch i64 poison, label %exit [ ]
exit: ret i64 %a
}
define i64 @guard_undef_switch(i64 %a, i64 %b, i64 %c) {
  switch i64 undef, label %exit [ i64 0, label %exit ]
exit: ret i64 %a
}
define i64 @guard_switch_loop(i64 %a, i64 %b, i64 %c) {
entry: br label %loop
loop: switch i64 %a, label %loop [ i64 1, label %loop ]
}
')
}
fn fixture(mut source strings.Builder) []ExecutionCase {
	mut cases := []ExecutionCase{}; cases.flags |= .noslices
	for bits in [u32(1), 8, 16, 32, 64] {
		for opcode, mnemonic in ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor'] {
			name := '${mnemonic}_${bits}'
			entry := ExecutionCase{name, .binary, bits, opcode}; unsafe { cases.push_many(&entry, 1) }
			header := 'define i64 @${name}(i64 %a, i64 %b, i64 %c) {\n'; source.write_string(header); unsafe { header.free() }
			if bits != 64 { line := '  %x = trunc i64 %a to i${bits}\n  %y = trunc i64 %b to i${bits}\n'; source.write_string(line); unsafe { line.free() } }
			line := '  %v = ${mnemonic} i${bits} ${if bits == 64 { '%a, %b' } else { '%x, %y' }}\n'; source.write_string(line); unsafe { line.free() }
			if bits != 64 { line2 := '  %r = zext i${bits} %v to i64\n  ret i64 %r\n}\n'; source.write_string(line2); unsafe { line2.free() } } else { source.write_string('  ret i64 %v\n}\n') }
		}
		for opcode, predicate in ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule', 'sgt', 'sge', 'slt', 'sle'] {
			name := 'cmp_${predicate}_${bits}'; entry := ExecutionCase{name, .comparison, bits, opcode}; unsafe { cases.push_many(&entry, 1) }
			header := 'define i64 @${name}(i64 %a, i64 %b, i64 %c) {\n'; source.write_string(header); unsafe { header.free() }
			if bits != 64 { line := '  %x = trunc i64 %a to i${bits}\n  %y = trunc i64 %b to i${bits}\n'; source.write_string(line); unsafe { line.free() } }
			line := '  %v = icmp ${predicate} i${bits} ${if bits == 64 { '%a, %b' } else { '%x, %y' }}\n  %r = zext i1 %v to i64\n  ret i64 %r\n}\n'; source.write_string(line); unsafe { line.free() }
		}
		if bits != 64 {
			name := 'sext_${bits}'; entry := ExecutionCase{name, .extension, bits, 0}; unsafe { cases.push_many(&entry, 1) }
			line := 'define i64 @${name}(i64 %a, i64 %b, i64 %c) {\n  %x = trunc i64 %a to i${bits}\n  %r = sext i${bits} %x to i64\n  ret i64 %r\n}\n'; source.write_string(line); unsafe { line.free() }
		}
	}
	for name in ['swap_loop', 'diamond', 'choose'] {
		entry := ExecutionCase{name.clone(), .control, 64, 0}; unsafe { cases.push_many(&entry, 1) }
	}
	source.write_string('define i64 @swap_loop(i64 %a, i64 %b, i64 %c) {
entry:
  %n = and i64 %c, 15
  br label %loop
loop:
  %x = phi i64 [ %a, %entry ], [ %y, %loop ]
  %y = phi i64 [ %b, %entry ], [ %x, %loop ]
  %i = phi i64 [ 0, %entry ], [ %inc, %loop ]
  %inc = add i64 %i, 1
  %again = icmp ult i64 %inc, %n
  br i1 %again, label %loop, label %exit
exit:
  %r = sub i64 %x, %y
  ret i64 %r
}
define i64 @diamond(i64 %a, i64 %b, i64 %c) {
entry:
  %cond = icmp slt i64 %a, %b
  br i1 %cond, label %left, label %right
left:
  %l = mul i64 %a, 3
  br label %join
right:
  %r = xor i64 %b, %c
  br label %join
join:
  %v = phi i64 [ %l, %left ], [ %r, %right ]
  ret i64 %v
}
define i64 @choose(i64 %a, i64 %b, i64 %c) {
  %cond = trunc i64 %c to i1
  %v = select i1 %cond, i64 %a, i64 %b
  ret i64 %v
}
define i64 @guard_zero(i64 %a, i64 %b, i64 %c) { %v = udiv i64 %a, 0
  ret i64 %v }
define i64 @guard_overflow(i64 %a, i64 %b, i64 %c) { %v = sdiv i64 -9223372036854775808, -1
  ret i64 %v }
define i64 @guard_flags(i64 %a, i64 %b, i64 %c) { %v = or disjoint i64 %a, %b
  ret i64 %v }
define noundef i64 @guard_attributes(i64 %a, i64 %b, i64 %c) { ret i64 %a }
define i64 @guard_undef(i64 %a, i64 %b, i64 %c) { ret i64 undef }
define i64 @guard_unreachable(i64 %a, i64 %b, i64 %c) { unreachable }
define i64 @guard_freeze(i64 %a, i64 %b, i64 %c) { %v = freeze i128 poison
 %narrow = trunc i128 %v to i64
 ret i64 %narrow }
define i64 @guard_loop(i64 %a, i64 %b, i64 %c) {
entry: br label %loop
loop: br label %loop }
define i64 @guard_poison_branch(i64 %a, i64 %b, i64 %c) {
  br i1 poison, label %yes, label %no
yes: ret i64 %a
no: ret i64 %b }
define i64 @poison_shift(i64 %a, i64 %b, i64 %c) { %v = shl i64 %a, 64
  ret i64 %v }
define i64 @poison_select(i64 %a, i64 %b, i64 %c) { %v = select i1 poison, i64 %a, i64 %b
  ret i64 %v }
')
	switch_fixtures(mut source, mut cases)
	return cases
}
fn word(sample int, salt u64) u64 {
	return match sample % 8 { 0 { u64(0) } 1 { ~u64(0) } 2 { u64(1) << 63 } 3 { u64(0x7f80ff01) } else { (u64(sample) * u64(0x9e3779b97f4a7c15)) ^ salt } }
}
fn compare(actual airbitcode.IRIntegerRun, reference u64) ! {
	if actual.bits != 64 || actual.poison || actual.value != reference || actual.steps <= 0 || actual.steps > 4096 { return error('Vinix integer execution differs from native LLVM reference') }
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing fixture function') }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-integer-execute self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]
	if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(65536); defer { unsafe { source.free() } }
	cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('LLVM fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native target initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-fixture'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM fixture parse failed') }
	mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil })
	if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple)
	mut engine := unsafe { nil }
	owns_module = false // MCJIT's EngineBuilder takes module ownership on this call.
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tc\tvinix\tllvm\tsteps')!
	mut comparisons := 0
	for c in cases {
		index := function_index(ir, c.name)!
		address := C.LLVMGetFunctionAddress(engine, c.name.str); if address == 0 { panic('missing JIT function') }
		reference := unsafe { NativeInteger(voidptr(address)) }
		for sample in 0 .. if c.kind == .dense_switch { 256 } else { 128 } {
			mut a := word(sample, 0xfedcba9876543210); mut b := word(127 - sample, 0x123456789abcdef0); third := u64(sample)
			mask := if c.bits == 64 { ~u64(0) } else { (u64(1) << c.bits) - 1 }
			if c.kind == .switch_table {
				sign := u64(1) << (c.bits - 1)
				a = match sample % 8 { 0 { u64(0) } 1 { u64(1) } 2 { sign } 3 { mask } 4 { u64(2) } 5 { sign - 1 } else { a } }
				if c.bits < 64 { a |= u64(1) << c.bits }
			}
			if c.kind == .dense_switch { a = u64(sample) | 0x100 }
			if c.kind == .binary {
				if c.opcode in [7, 8, 9] { b %= c.bits }
				if c.opcode in [3, 4, 5, 6] && b & mask == 0 { b = 1 }
				if c.opcode in [4, 6] && a & mask == u64(1) << (c.bits - 1) && b & mask == mask { a ^= 1 }
			}
			args := [a, b, third]; defer { unsafe { args.free() } }
			actual := p.run_integer_function(ir, stream, pools, bodies, index, args, 4096)!
			expected := reference(a, b, third)
			compare(actual, expected)!
			if c.kind == .dense_switch && actual.steps != sample + 4 { panic('dense switch comparison budget accounting') }
			row := '${c.name}\t${a}\t${b}\t${third}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++
		}
	}
	args := [u64(1), 2, 3]; defer { unsafe { args.free() } }
	mut guards := 0
	for name in ['guard_zero', 'guard_overflow', 'guard_flags', 'guard_attributes', 'guard_undef', 'guard_unreachable', 'guard_freeze', 'guard_loop', 'guard_poison_branch', 'guard_poison_switch', 'guard_undef_switch', 'guard_switch_loop'] {
		p.run_integer_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64) or { guards++; continue }; panic('accepted guarded fixture')
	}
	dense_args := [u64(255), 2, 3]; defer { unsafe { dense_args.free() } }
	if _ := p.run_integer_function(ir, stream, pools, bodies, function_index(ir, 'switch_dense8')!, dense_args, 258) { panic('accepted exhausted dense switch budget') }
	for name in ['poison_shift', 'poison_select'] { actual := p.run_integer_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64)!; if !actual.poison { panic('lost poison result') } }
	baseline := p.run_integer_function(ir, stream, pools, bodies, function_index(ir, 'add_64')!, args, 64)!
	mut controls := 0
	for changed in [airbitcode.IRIntegerRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRIntegerRun{...baseline, bits: 32}, airbitcode.IRIntegerRun{...baseline, poison: true}, airbitcode.IRIntegerRun{...baseline, steps: 0}] {
		compare(changed, baseline.value) or { controls++; continue }; panic('accepted corrupted execution result')
	}
	println('LLVM-INTEGER-EXECUTION: ${cases.len} scalar fixture functions, ${comparisons} interpreter/native-JIT comparisons; sparse/dense/empty/loop switches, shared-edge/parallel PHIs, branches/selects/casts; ${guards} guarded failures, one dense-scan budget, two poison results and ${controls} corruptions rejected; no AIR shader or iOS app executed')
}
