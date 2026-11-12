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

struct HalfCase {
	name string
	input string = 'half'
	kind airbitcode.IRScalarKind = .binary16
	bits u32 = 16
	conversion bool
	steps int = 2 // Zero denotes a loop whose steps depend on the input.
}
fn fixture(mut source strings.Builder) []HalfCase {
	cases := [
		HalfCase{name: 'widen', kind: .binary32, bits: 32, conversion: true},
		HalfCase{name: 'narrow', input: 'float', conversion: true},
		HalfCase{name: 'half_roundtrip', conversion: true, steps: 3},
		HalfCase{name: 'float_roundtrip', input: 'float', kind: .binary32, bits: 32, conversion: true, steps: 3},
		HalfCase{name: 'copy', steps: 1}, HalfCase{name: 'negate'},
		HalfCase{name: 'from_bits', input: 'i16'}, HalfCase{name: 'to_bits', kind: .integer},
		HalfCase{name: 'choose', steps: 3}, HalfCase{name: 'swap_loop', steps: 0},
		HalfCase{name: 'negative_zero', steps: 1}, HalfCase{name: 'snan_constant', steps: 1},
	]
	source.write_string('define float @widen(half %x, half %y, i64 %c) { %r = fpext half %x to float
  ret float %r }
define half @narrow(float %x, float %y, i64 %c) { %r = fptrunc float %x to half
  ret half %r }
define half @half_roundtrip(half %x, half %y, i64 %c) { %f = fpext half %x to float
  %h = fptrunc float %f to half
  ret half %h }
define float @float_roundtrip(float %x, float %y, i64 %c) { %h = fptrunc float %x to half
  %f = fpext half %h to float
  ret float %f }
define half @copy(half %x, half %y, i64 %c) { ret half %x }
define half @negate(half %x, half %y, i64 %c) { %r = fneg half %x
  ret half %r }
define half @from_bits(i16 %x, i16 %y, i64 %c) { %r = bitcast i16 %x to half
  ret half %r }
define i16 @to_bits(half %x, half %y, i64 %c) { %r = bitcast half %x to i16
  ret i16 %r }
define half @choose(half %x, half %y, i64 %c) { %cond = trunc i64 %c to i1
  %r = select i1 %cond, half %x, half %y
  ret half %r }
define half @negative_zero(half %x, half %y, i64 %c) { ret half 0xH8000 }
define half @snan_constant(half %x, half %y, i64 %c) { ret half 0xH7C01 }
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
define float @poison_widen(half %x, half %y, i64 %c) { %r = fpext half poison to float
  ret float %r }
define half @poison_narrow(float %x, float %y, i64 %c) { %r = fptrunc float poison to half
  ret half %r }
define half @poison_negate(half %x, half %y, i64 %c) { %r = fneg half poison
  ret half %r }
define half @lazy_select(half %x, half %y, i64 %c) { %r = select i1 true, half %x, half undef
  ret half %r }
define float @guard_undef(half %x, half %y, i64 %c) { %r = fpext half undef to float
  ret float %r }
define half @guard_trunc_fmf(float %x, float %y, i64 %c) { %r = fptrunc nnan float %x to half
  ret half %r }
define float @guard_ext_fmf(half %x, half %y, i64 %c) { %r = fpext nnan half %x to float
  ret float %r }
define half @guard_negate_fmf(half %x, half %y, i64 %c) { %r = fneg fast half %x
  ret half %r }
define i1 @guard_compare_flags(half %x, half %y, i64 %c) { %r = fcmp fast true half %x, %y
  ret i1 %r }
define i16 @guard_to_integer_flags(half %x, half %y, i64 %c) { %r = fptosi half %x to i16
  %h = sitofp nnan i16 %r to half
  ret i16 %r }
define half @guard_from_integer_flags(i16 %x, i16 %y, i64 %c) { %r = uitofp nneg i16 %x to half
  ret half %r }
define half @guard_dead_precision(half %x, half %y, i64 %c) {
entry: ret half %x
dead: %r = fpext half %x to double
  ret half %y }
define half @guard_freeze(half %x, half %y, i64 %c) { %r = freeze half poison
  ret half %r }
define float @guard_double(half %x, half %y, i64 %c) { %d = fpext half %x to double
  %r = fptrunc double %d to float
  ret float %r }
define float @guard_bfloat(float %x, float %y, i64 %c) { %h = fptrunc float %x to bfloat
  %r = fpext bfloat %h to float
  ret float %r }
')
	for c in cases {
		input_bits := if c.input == 'float' { 32 } else { 16 }
		result_type := if c.kind == .integer { 'i16' } else if c.bits == 16 { 'half' } else { 'float' }
		header := 'define i64 @reference_${c.name}(i64 %a, i64 %b, i64 %c) {\n  %ai = trunc i64 %a to i${input_bits}\n  %bi = trunc i64 %b to i${input_bits}\n'; source.write_string(header); unsafe { header.free() }
		if c.input != 'i16' {
			casts := '  %x = bitcast i${input_bits} %ai to ${c.input}\n  %y = bitcast i${input_bits} %bi to ${c.input}\n'; source.write_string(casts); unsafe { casts.free() }
		}
		call := '  %r = call ${result_type} @${c.name}(${c.input} ${if c.input == 'i16' { '%ai' } else { '%x' }}, ${c.input} ${if c.input == 'i16' { '%bi' } else { '%y' }}, i64 %c)\n'; source.write_string(call); unsafe { call.free() }
		if c.kind != .integer { cast := '  %bits = bitcast ${result_type} %r to i${c.bits}\n'; source.write_string(cast); unsafe { cast.free() } }
		ending := '  %out = zext i${c.bits} ${if c.kind == .integer { '%r' } else { '%bits' }} to i64\n  ret i64 %out\n}\n'; source.write_string(ending); unsafe { ending.free() }
	}
	// Test-only native midpoint generator. Each finite adjacent half pair has
	// an exactly representable binary32 midpoint. Include the overflow boundary
	// by using the hypothetical next finite value 65536 above maximum half.
	source.write_string('define i64 @rounding_midpoint(i64 %raw, i64 %unused, i64 %unused2) {
  %lo = trunc i64 %raw to i16
  %hi = add i16 %lo, 1
  %lh = bitcast i16 %lo to half
  %hh = bitcast i16 %hi to half
  %l = fpext half %lh to float
  %h = fpext half %hh to float
  %overflow = icmp eq i16 %hi, 31744
  %upper = select i1 %overflow, float 65536.0, float %h
  %sum = fadd float %l, %upper
  %mid = fmul float %sum, 0.5
  %bits = bitcast float %mid to i32
  %out = zext i32 %bits to i64
  ret i64 %out
}
')
	return cases
}
fn pattern(sample int) u32 {
	mut x := u64(sample) + u64(0x9e3779b97f4a7c15)
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9)
	x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return u32(x ^ (x >> 31))
}
fn compare(actual airbitcode.IRScalarRun, expected u64, c HalfCase) !bool {
	if actual.kind != c.kind || actual.bits != c.bits || actual.poison || actual.steps < 1 || actual.steps > 512 || (c.steps != 0 && actual.steps != c.steps) { return error('half result metadata differs') }
	nan := if c.bits == 16 { expected & 0x7fff > 0x7c00 } else { expected & 0x7fffffff > 0x7f800000 }
	if c.conversion && nan {
		if actual.value != if c.bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } { return error('half conversion did not choose preferred NaN') }
		return true
	}
	if actual.value != expected { return error('half result bits differ from native LLVM') }
	return false
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing half fixture function') }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-binary16-casts self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 || C.fegetround() != C.FE_TONEAREST { panic('cannot establish default native FP environment') }
	defer { C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) }
	mut source := strings.new_builder(65536); defer { unsafe { source.free() } }
	cases := fixture(mut source); defer { unsafe { cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('half fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-half'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM half fixture parse failed') }
	mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple)
	mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\nreference_fenv=FE_DFL_ENV,FE_TONEAREST\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	address := C.LLVMGetFunctionAddress(engine, c'rounding_midpoint'); if address == 0 { panic('missing native midpoint generator') }; midpoint := unsafe { NativeBits(voidptr(address)) }
	edges := [u32(0), 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000, 0x32ffffff, 0x33000000, 0x33000001, 0x33800000, 0x33c00000, 0x387fc000, 0x387fe000, 0x38800000, 0x3f800000, 0x3f801000, 0x3f803000, 0xbf801000, 0xbf803000, 0x477fe000, 0x477fefff, 0x477ff000, 0x47800000, 0xc77ff000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0xffc12345, 0x7f800001, 0xff800001]!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tc\tvinix\tllvm\tnan_class_only\tsteps')!
	mut comparisons := 0; mut nan_cases := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }
		reference_address := C.LLVMGetFunctionAddress(engine, reference_name.str); if reference_address == 0 { panic('missing half native wrapper') }; reference := unsafe { NativeBits(voidptr(reference_address)) }
		for sample in 0 .. if c.input == 'float' { 65536 + 190464 + 32 } else { 65536 } {
			mut a := u32(sample)
			if c.input == 'float' {
				if sample < 65536 { a = pattern(sample) }
				else if sample < 65536 + 190464 {
					boundary := sample - 65536
					a = u32(midpoint(u64(boundary / 6), 0, 0)) + u32(boundary % 3) - 1
					if boundary % 6 >= 3 { a |= 0x80000000 }
				} else { a = edges[sample - 65536 - 190464] }
			}
			b := u32(65535 - (sample & 65535)); third := u64(sample & 15)
			args := [u64(a) | 0x100000000, u64(b) | 0x200000000, third]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 512)!
			expected := reference(args[0], args[1], third)
			nan_class := compare(actual, expected, c) or { row := 'FAIL ${c.name} a=${a} b=${b} got=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${a}\t${b}\t${third}\t${actual.value}\t${expected}\t${nan_class}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }
			comparisons++; if nan_class { nan_cases++ }
		}
	}
	args := [u64(0x7c01), 0, 0]; defer { unsafe { args.free() } }
	mut guards := 0
	for name in ['guard_undef', 'guard_trunc_fmf', 'guard_ext_fmf', 'guard_negate_fmf', 'guard_compare_flags', 'guard_to_integer_flags', 'guard_from_integer_flags', 'guard_dead_precision', 'guard_freeze', 'guard_double', 'guard_bfloat'] { p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64) or { guards++; continue }; panic('accepted unsupported half fixture') }
	for name in ['poison_widen', 'poison_narrow', 'poison_negate'] { if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64)!.poison { panic('half poison lost') } }
	if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'lazy_select')!, args, 64)!.value != args[0] { panic('half select not lazy') }
	baseline := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'widen')!, [u64(0x3c00), 0, 0], 64)!; mut controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary16}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] { compare(changed, baseline.value, cases[0]) or { controls++; continue }; panic('accepted corrupted half result') }
	for mode in [C.FE_UPWARD, C.FE_DOWNWARD]! {
		if C.fesetround(mode) != 0 { panic('cannot set rounding control') }
		rounding_args := [if mode == C.FE_UPWARD { u64(0x3f801000) } else { u64(0x3f803000) }, 0, 0]; defer { unsafe { rounding_args.free() } }
		expected := if mode == C.FE_UPWARD { u64(0x3c00) } else { u64(0x3c02) }
		if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'narrow')!, rounding_args, 64)!.value != expected { panic('half conversion depended on host rounding mode') }
	}
	println('LLVM-BINARY16-CASTS: ${cases.len} functions, ${comparisons} comparisons (${nan_cases} conversion NaN-class results), all half encodings and signed midpoint neighbors, ${guards} guards, three poison results, lazy select, ${controls} corruptions and two rounding controls PASS; no AIR shader or iOS app executed')
}
