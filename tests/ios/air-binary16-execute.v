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
#include <fenv.h>
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
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
type NativeBits = fn (u64, u64, u64) u64

enum CaseKind { arithmetic comparison exact }
struct FloatCase { name string kind CaseKind }
fn add_case(mut cases []FloatCase, name string, kind CaseKind) { entry := FloatCase{name, kind}; unsafe { cases.push_many(&entry, 1) } }
fn fixture(mut source strings.Builder) []FloatCase {
	mut cases := []FloatCase{}; cases.flags |= .noslices
	for mnemonic in ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'] {
		name := mnemonic.clone(); add_case(mut cases, name, .arithmetic)
		line := 'define half @${name}(half %x, half %y, i64 %c) {\n  %r = ${mnemonic} half %x, %y\n  ret half %r\n}\n'; source.write_string(line); unsafe { line.free() }
	}
	for predicate in ['false', 'oeq', 'ogt', 'oge', 'olt', 'ole', 'one', 'ord', 'uno', 'ueq', 'ugt', 'uge', 'ult', 'ule', 'une', 'true'] {
		name := 'cmp_${predicate}'; add_case(mut cases, name, .comparison)
		line := 'define i1 @${name}(half %x, half %y, i64 %c) {\n  %r = fcmp ${predicate} half %x, %y\n  ret i1 %r\n}\n'; source.write_string(line); unsafe { line.free() }
	}
	for name in ['negate', 'bit_roundtrip', 'choose', 'swap_loop', 'copy_bits', 'from_int', 'negative_zero'] { add_case(mut cases, name.clone(), .exact) }
	for name in ['diamond', 'constant_add', 'sum_loop'] { add_case(mut cases, name.clone(), .arithmetic) }
	source.write_string('define half @negate(half %x, half %y, i64 %c) { %r = fneg half %x
  ret half %r }
define half @bit_roundtrip(half %x, half %y, i64 %c) { %i = bitcast half %x to i16
  %r = bitcast i16 %i to half
  ret half %r }
define half @choose(half %x, half %y, i64 %c) { %cond = trunc i64 %c to i1
  %r = select i1 %cond, half %x, half %y
  ret half %r }
define half @copy_bits(half %x, half %y, i64 %c) { ret half %x }
define half @from_int(half %x, half %y, i64 %c) { %i = trunc i64 %c to i16
  %r = bitcast i16 %i to half
  ret half %r }
define half @negative_zero(half %x, half %y, i64 %c) { ret half 0xH8000 }
define half @constant_add(half %x, half %y, i64 %c) { %r = fadd half %x, 1.0
  ret half %r }
define half @diamond(half %x, half %y, i64 %c) {
  %cond = fcmp olt half %x, %y
  br i1 %cond, label %left, label %right
left: %l = fadd half %x, %y
  br label %join
right: %r = fsub half %x, %y
  br label %join
join: %v = phi half [ %l, %left ], [ %r, %right ]
  ret half %v
}
define half @sum_loop(half %x, half %y, i64 %c) {
entry: %n = and i64 %c, 15
  br label %loop
loop: %a = phi half [ %x, %entry ], [ %sum, %loop ]
  %i = phi i64 [ 0, %entry ], [ %inc, %loop ]
  %sum = fadd half %a, %y
  %inc = add i64 %i, 1
  %again = icmp ult i64 %inc, %n
  br i1 %again, label %loop, label %exit
exit: ret half %sum
}
define half @swap_loop(half %x, half %y, i64 %c) {
entry: %n = and i64 %c, 15
  br label %loop
loop:
  %a = phi half [ %x, %entry ], [ %b, %loop ]
  %b = phi half [ %y, %entry ], [ %a, %loop ]
  %i = phi i64 [ 0, %entry ], [ %inc, %loop ]
  %inc = add i64 %i, 1
  %again = icmp ult i64 %inc, %n
  br i1 %again, label %loop, label %exit
exit: ret half %a
}
define half @guard_fmf(half %x, half %y, i64 %c) { %r = fadd fast half %x, %y
  ret half %r }
define half @guard_frem_fmf(half %x, half %y, i64 %c) { %r = frem fast half %x, %y
  ret half %r }
define half @guard_precision(half %x, half %y, i64 %c) { %d = fpext half %x to double
  %r = fptrunc double %d to half
  ret half %r }
define half @guard_cast_flags(half %x, half %y, i64 %c) { %i = fptosi half %x to i16
  %r = sitofp nnan i16 %i to half
  ret half %r }
define half @guard_undef(half %x, half %y, i64 %c) { ret half undef }
define half @guard_freeze(half %x, half %y, i64 %c) { %r = freeze half poison
  ret half %r }
define noundef half @guard_attributes(half %x, half %y, i64 %c) { ret half %x }
define half @poison_add(half %x, half %y, i64 %c) { %r = fadd half %x, poison
  ret half %r }
define half @poison_divide(half %x, half %y, i64 %c) { %r = fdiv half %x, poison
  ret half %r }
define half @poison_remainder_left(half %x, half %y, i64 %c) { %r = frem half poison, %y
  ret half %r }
define half @poison_remainder_right(half %x, half %y, i64 %c) { %r = frem half %x, poison
  ret half %r }
define i1 @poison_compare(half %x, half %y, i64 %c) { %r = fcmp oeq half %x, poison
  ret i1 %r }
define half @lazy_select(half %x, half %y, i64 %c) { %r = select i1 true, half %x, half undef
  ret half %r }
define i1 @lazy_false(half %x, half %y, i64 %c) { %r = fcmp false half poison, undef
  ret i1 %r }
define i1 @lazy_true(half %x, half %y, i64 %c) { %r = fcmp true half undef, poison
  ret i1 %r }
')
	// Native wrappers convert raw bits to the real half argument/return ABI.
	// Vinix executes the original function, never a wrapper or a CALL instruction.
	for c in cases {
		result_type := if c.kind == .comparison { 'i1' } else { 'half' }
		header := 'define i64 @reference_${c.name}(i64 %a, i64 %b, i64 %c) {\n  %ai = trunc i64 %a to i16\n  %bi = trunc i64 %b to i16\n  %x = bitcast i16 %ai to half\n  %y = bitcast i16 %bi to half\n  %r = call ${result_type} @${c.name}(half %x, half %y, i64 %c)\n'; source.write_string(header); unsafe { header.free() }
		if c.kind == .comparison { source.write_string('  %out = zext i1 %r to i64\n') } else { source.write_string('  %bits = bitcast half %r to i16\n  %out = zext i16 %bits to i64\n') }
		source.write_string('  ret i64 %out\n}\n')
	}
	return cases
}
fn pattern(sample int, salt u64) u16 {
	mut x := u64(sample) + salt
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9)
	x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return u16(x ^ (x >> 31))
}
fn is_nan(value u64) bool { return value <= 0xffff && u16(value) & 0x7fff > 0x7c00 }
fn compare(actual airbitcode.IRScalarRun, reference u64, kind CaseKind) !bool {
	expected_kind := if kind == .comparison { airbitcode.IRScalarKind.integer } else { airbitcode.IRScalarKind.binary16 }
	expected_bits := if kind == .comparison { u32(1) } else { u32(16) }
	if actual.kind != expected_kind || actual.bits != expected_bits || actual.poison || actual.steps < 1 || actual.steps > 512 { return error('binary16 result metadata differs') }
	if kind == .arithmetic && is_nan(reference) {
		if actual.value != 0x7e00 { return error('binary16 did not produce its preferred quiet NaN') }
		return true // Arithmetic NaN sign/payload is not compared with hardware.
	}
	if actual.value != reference { return error('binary16 result bits differ from native LLVM') }
	return false
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing binary16 fixture function') }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-binary16-execute self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 || C.fegetround() != C.FE_TONEAREST { panic('cannot establish default native FP environment') }
	defer { C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) }
	mut source := strings.new_builder(65536); defer { unsafe { source.free() } }
	cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('LLVM binary16 fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-binary16'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM binary16 fixture parse failed') }
	mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple)
	mut engine := unsafe { nil }; owns_module = false // MCJIT consumes the module.
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\nreference_fenv=FE_DFL_ENV,FE_TONEAREST\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	edges := [u16(0), 0x8000, 1, 2, 3, 0x03ff, 0x0400, 0x0401, 0x3800, 0xb800, 0x3c00, 0x3c01, 0x3bff, 0xbc00, 0x4000, 0xc000, 0x4200, 0x3555, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e00, 0xfe00, 0x7c01, 0xfc01, 0x7e55, 0x3801, 0x0402, 0x1000, 0x1600, 0x8400]!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tc\tvinix\tllvm\tnan_class_only\tsteps')!
	mut comparisons := 0; mut nan_cases := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }
		address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing binary16 native wrapper') }; reference := unsafe { NativeBits(voidptr(address)) }
		for sample in 0 .. 1024 + 65536 + if c.kind == .arithmetic { 65536 } else { 0 } {
			// Every half encoding occupies operand A once, paired with mixed B.
			// Arithmetic adds another independent mixed-bit pair corpus.
			a := if sample < 1024 { edges[sample / 32] } else if sample < 1024 + 65536 { u16(sample - 1024) } else { pattern(sample, 0x123456789abcdef0) }
			b := if sample < 1024 { edges[sample % 32] } else { pattern(sample, 0xfedcba9876543210) }
			third := u64(pattern(sample, 0x9876543210abcdef)); args := [u64(a) | 0x100000000, u64(b) | 0x200000000, third]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 512)!
			if c.name in ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'] && actual.steps != 2 { panic('half binary instruction count differs') }
			expected := reference(args[0], args[1], third)
			nan_class := compare(actual, expected, c.kind) or { row := 'FAIL ${c.name} a=${a} b=${b} got=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${a}\t${b}\t${third}\t${actual.value}\t${expected}\t${nan_class}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }
			comparisons++; if nan_class { nan_cases++ }
		}
	}
	args := [u64(0x3c00), 0x4000, 0]; defer { unsafe { args.free() } }
	mut guards := 0
	for name in ['guard_fmf', 'guard_frem_fmf', 'guard_precision', 'guard_cast_flags', 'guard_undef', 'guard_freeze', 'guard_attributes'] { p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64) or { guards++; continue }; panic('accepted unsupported binary16 fixture') }
	for name in ['poison_add', 'poison_divide', 'poison_remainder_left', 'poison_remainder_right', 'poison_compare'] { if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64)!.poison { panic('binary16 poison lost') } }
	if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'lazy_select')!, args, 64)!.value != args[0] { panic('binary16 select was not lazy') }
	for i, name in ['lazy_false', 'lazy_true'] { result := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64)!; if result.poison || result.value != u64(i) { panic('constant half predicate read poison/undef') } }
	baseline := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'fadd')!, args, 64)!; mut controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .integer}, airbitcode.IRScalarRun{...baseline, bits: 64}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 0}] { compare(changed, baseline.value, .arithmetic) or { controls++; continue }; panic('accepted corrupted binary16 result') }
	for mode in [C.FE_UPWARD, C.FE_DOWNWARD]! {
		if C.fesetround(mode) != 0 { panic('cannot set non-default rounding control') }
		rounding_args := [u64(0x3c00), if mode == C.FE_UPWARD { u64(0x1000) } else { u64(0x1600) }, 0]; defer { unsafe { rounding_args.free() } }
		expected := if mode == C.FE_UPWARD { u64(0x3c00) } else { u64(0x3c02) }
		if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'fadd')!, rounding_args, 64)!.value != expected { panic('software binary16 depended on host rounding mode') }
		remainder_args := [u64(0x7bff), 11, 0]; defer { unsafe { remainder_args.free() } }
		if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'frem')!, remainder_args, 64)!.value != 6 { panic('software remainder depended on host rounding mode') }
	}
	println('LLVM-BINARY16-EXECUTION: ${cases.len} functions, ${comparisons} native comparisons (${nan_cases} arithmetic NaN-class comparisons); ${guards} guarded failures, five poison results, lazy select/predicates, ${controls} corruptions and four host-rounding controls PASS; no AIR shader or iOS app executed')
}
