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

struct IntrinsicCase { name string bits u32 rounding bool steps int }
fn fixture(mut source strings.Builder) []IntrinsicCase {
	mut cases := []IntrinsicCase{}; cases.flags |= .noslices
	for bits in [u32(16), 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		for op in ['fabs', 'copysign', 'floor', 'ceil', 'trunc', 'round', 'roundeven', 'rint', 'nearbyint'] {
			name := '${op}_${bits}'; entry := IntrinsicCase{name, bits, op !in ['fabs', 'copysign'], 2}; unsafe { cases.push_many(&entry, 1) }
			args := if op == 'copysign' { '${typ} %x, ${typ} %y' } else { '${typ} %x' }
			params := if op == 'copysign' { '${typ}, ${typ}' } else { typ }
			text := 'declare ${typ} @llvm.${op}.f${bits}(${params})\ndefine ${typ} @${name}(${typ} %x, ${typ} %y, i64 %c) {\n  %r = call ${typ} @llvm.${op}.f${bits}(${args})\n  ret ${typ} %r\n}\n'; source.write_string(text); unsafe { args.free(); if op == 'copysign' { params.free() }; text.free() }
		}
		for op in ['chain', 'loop'] { name := '${op}_${bits}'; entry := IntrinsicCase{name, bits, true, if op == 'chain' { 4 } else { 0 }}; unsafe { cases.push_many(&entry, 1) } }
		flow := 'define ${typ} @chain_${bits}(${typ} %x, ${typ} %y, i64 %c) {\n  %a = call ${typ} @llvm.fabs.f${bits}(${typ} %x)\n  %b = call ${typ} @llvm.copysign.f${bits}(${typ} %a, ${typ} %y)\n  %r = call ${typ} @llvm.roundeven.f${bits}(${typ} %b)\n  ret ${typ} %r\n}\ndefine ${typ} @loop_${bits}(${typ} %x, ${typ} %y, i64 %c) {\nentry: %n = and i64 %c, 7\n  br label %loop\nloop: %a = phi ${typ} [ %x, %entry ], [ %sum, %loop ]\n  %i = phi i64 [ 0, %entry ], [ %inc, %loop ]\n  %r = call ${typ} @llvm.floor.f${bits}(${typ} %a)\n  %sum = fadd ${typ} %r, %y\n  %inc = add i64 %i, 1\n  %again = icmp ult i64 %inc, %n\n  br i1 %again, label %loop, label %exit\nexit: ret ${typ} %sum\n}\n'; source.write_string(flow); unsafe { flow.free() }
	}
	source.write_string('declare float @llvm.sqrt.f32(float)
define float @helper(float %x) { ret float %x }
define float @guard_defined(float %x, float %y, i64 %c) { %r = call float @helper(float %x)
  ret float %r }
define float @guard_unknown(float %x, float %y, i64 %c) { %r = call float @llvm.sqrt.f32(float %x)
  ret float %r }
define float @guard_tail(float %x, float %y, i64 %c) { %r = tail call float @llvm.fabs.f32(float %x)
  ret float %r }
define float @guard_fmf(float %x, float %y, i64 %c) { %r = call fast float @llvm.fabs.f32(float %x)
  ret float %r }
define float @guard_return_attr(float %x, float %y, i64 %c) { %r = call noundef float @llvm.fabs.f32(float %x)
  ret float %r }
define float @guard_parameter_attr(float %x, float %y, i64 %c) { %r = call float @llvm.fabs.f32(float noundef %x)
  ret float %r }
define float @guard_undef(float %x, float %y, i64 %c) { %r = call float @llvm.floor.f32(float undef)
  ret float %r }
define float @guard_dead(float %x, float %y, i64 %c) {
entry: ret float %x
dead: %r = call float @llvm.sqrt.f32(float %y)
  ret float %r }
define float @guard_indirect(float %x, float %y, i64 %c) {
  %test = trunc i64 %c to i1
  %fn = select i1 %test, ptr @helper, ptr @helper
  %r = call float %fn(float %x)
  ret float %r }
define float @poison_unary(float %x, float %y, i64 %c) { %r = call float @llvm.fabs.f32(float poison)
  ret float %r }
define float @poison_left(float %x, float %y, i64 %c) { %r = call float @llvm.copysign.f32(float poison, float %y)
  ret float %r }
define float @poison_right(float %x, float %y, i64 %c) { %r = call float @llvm.copysign.f32(float %x, float poison)
  ret float %r }
define float @lazy_select(float %x, float %y, i64 %c) { %r = select i1 true, float %x, float undef
  %out = call float @llvm.fabs.f32(float %r)
  ret float %out }
define i64 @diagnostic_half_copysign(i64 %a, i64 %b, i64 %c) {
  %ai = trunc i64 %a to i16
  %bi = trunc i64 %b to i16
  %x = bitcast i16 %ai to half
  %y = bitcast i16 %bi to half
  %r = call half @copysign_16(half %x, half %y, i64 %c)
  %bits = bitcast half %r to i16
  %out = zext i16 %bits to i64
  ret i64 %out }
')
	for c in cases {
		if c.name == 'copysign_16' {
			// The observed host half copysign quiets sNaNs, contrary to its
			// bit-preserving contract. Use a defined native
			// integer oracle for this case, retaining the native FP diagnostic.
			source.write_string('define i64 @reference_copysign_16(i64 %a, i64 %b, i64 %c) { %mag = and i64 %a, 32767
  %sign = and i64 %b, 32768
  %r = or i64 %mag, %sign
  ret i64 %r }
')
			continue
		}
		typ := if c.bits == 16 { 'half' } else { 'float' }
		wrapper := 'define i64 @reference_${c.name}(i64 %a, i64 %b, i64 %c) {\n  %ai = trunc i64 %a to i${c.bits}\n  %bi = trunc i64 %b to i${c.bits}\n  %x = bitcast i${c.bits} %ai to ${typ}\n  %y = bitcast i${c.bits} %bi to ${typ}\n  %r = call ${typ} @${c.name}(${typ} %x, ${typ} %y, i64 %c)\n  %bits = bitcast ${typ} %r to i${c.bits}\n  %out = zext i${c.bits} %bits to i64\n  ret i64 %out\n}\n'; source.write_string(wrapper); unsafe { wrapper.free() }
	}
	return cases
}
fn pattern(sample int, salt u64) u32 {
	mut x := u64(sample) + salt
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9)
	x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return u32(x ^ (x >> 31))
}
fn compare(actual airbitcode.IRScalarRun, reference u64, c IntrinsicCase) !bool {
	kind := if c.bits == 16 { airbitcode.IRScalarKind.binary16 } else { airbitcode.IRScalarKind.binary32 }
	if actual.kind != kind || actual.bits != c.bits || actual.poison || actual.steps < 1 || actual.steps > 256 || (c.steps != 0 && actual.steps != c.steps) { return error('intrinsic result metadata differs') }
	nan := if c.bits == 16 { reference & 0x7fff > 0x7c00 } else { reference & 0x7fffffff > 0x7f800000 }
	if c.rounding && nan { if actual.value != if c.bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } { return error('intrinsic preferred NaN differs') }; return true }
	if actual.value != reference { return error('intrinsic bits differ from native LLVM') }
	return false
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing intrinsic fixture function') }
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-scalar-intrinsics self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 || C.fegetround() != C.FE_TONEAREST { panic('cannot establish native environment') }; defer { C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) }
	mut source := strings.new_builder(65536); defer { unsafe { source.free() } }
	cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('intrinsic fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-intrinsics'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM intrinsic fixture parse failed') }
	mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple)
	mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\nreference_fenv=FE_DFL_ENV,FE_TONEAREST\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	diagnostic_address := C.LLVMGetFunctionAddress(engine, c'diagnostic_half_copysign'); if diagnostic_address == 0 { panic('missing half copysign diagnostic') }; diagnostic := unsafe { NativeBits(voidptr(diagnostic_address)) }
	diagnostic_bits := diagnostic(0x7c01, 0x8000, 0)
	diagnostic_text := 'input=0x7c01 sign=0x8000 spec_bits=0xfc01 native_bits=${diagnostic_bits}\nhalf_copysign_reference=native LLVM integer bit operations\n'; defer { unsafe { diagnostic_text.free() } }; os.write_file(out + '/half-copysign-native-diagnostic.txt', diagnostic_text)!
	edges := [u32(0), 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000, 0x3effffff, 0x3f000000, 0x3f000001, 0xbeffffff, 0xbf000000, 0xbf000001, 0x3f800000, 0xbf800000, 0x3fc00000, 0xbfc00000, 0x40200000, 0xc0200000, 0x4affffff, 0x4b000000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0xffc00000, 0x7f800001, 0xff800001, 0x7fc12345, 0xffc12345, 0x3fffffff, 0xbfffffff]!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tc\tvinix\tllvm\tnan_class_only\tsteps')!
	mut comparisons := 0; mut nan_cases := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }
		address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing intrinsic reference') }; reference := unsafe { NativeBits(voidptr(address)) }
		for sample in 0 .. if c.bits == 16 { 65536 } else { 131104 } {
			mut a := if c.bits == 16 { u32(sample) } else if sample < 32 { edges[sample] } else { pattern(sample, 0x123456789abcdef0) }
			if c.bits == 32 && sample >= 65568 {
				k := sample - 65568; exponent := k % 23; distance := 23 - exponent
				a = ((u32(exponent + 127) << 23) | (a & 0x7fffff)) & ~((u32(1) << distance) - 1)
				a = (a | (u32(1) << (distance - 1))) + u32(k % 3) - 1
				if k & 1 != 0 { a |= 0x80000000 }
			}
			b := pattern(sample, 0xfedcba9876543210); third := u64(sample & 7)
			args := [u64(a) | 0x100000000, u64(b) | 0x200000000, third]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 256)!
			expected := reference(args[0], args[1], third)
			nan_class := compare(actual, expected, c) or { row := 'FAIL ${c.name} a=${a} b=${b} got=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${a}\t${b}\t${third}\t${actual.value}\t${expected}\t${nan_class}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }
			comparisons++; if nan_class { nan_cases++ }
		}
	}
	args := [u64(0xbf000000), 0, 0]; defer { unsafe { args.free() } }; mut guards := 0
	for name in ['guard_defined', 'guard_unknown', 'guard_tail', 'guard_fmf', 'guard_return_attr', 'guard_parameter_attr', 'guard_undef', 'guard_dead', 'guard_indirect'] { p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64) or { guards++; continue }; panic('accepted unsupported intrinsic fixture') }
	for name in ['poison_unary', 'poison_left', 'poison_right'] { if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, args, 64)!.poison { panic('intrinsic poison lost') } }
	if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'lazy_select')!, args, 64)!.value != 0x3f000000 { panic('intrinsic select not lazy') }
	index := function_index(ir, 'fabs_32')!; slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]
	if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('intrinsic budget accepted') }
	if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer-only API accepted intrinsic') }
	mut metadata_controls := 0
	for changed in [airbitcode.IRTypedInstruction{...original, callee_function: -1}, airbitcode.IRTypedInstruction{...original, callee_function: ir.functions.len}, airbitcode.IRTypedInstruction{...original, call_signature: -1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, operands_count: 1}] {
		p.instructions[slot] = changed
		p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('accepted corrupted call metadata')
	}
	p.instructions[slot] = original
	operand_slot := original.operands_start; operand := p.operands[operand_slot]
	p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, number: u32(pools.declarations.len)}
	if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) { panic('accepted mismatched declaration identity') } else { metadata_controls++ }
	if metadata_controls != 8 { panic('accepted mismatched declaration identity') }; p.operands[operand_slot] = operand
	// Corrupt the selected declaration's actual attribute group, so the call
	// profile must exercise its attribute validator as well as pure unit tests.
	declaration := stream.records[ir.functions[original.callee_function].record]
	attribute_set := stream.values[declaration.values_start + 6]
	mut attribute_number := u64(0); mut group := u64(0); mut group_start := -1
	for record in stream.records { if stream.blocks[record.block].id == 9 && record.code == 2 { attribute_number++; if attribute_number == attribute_set { group = stream.values[record.values_start]; break } } }
	for record in stream.records { if stream.blocks[record.block].id == 10 && record.code == 3 && record.values_count > 3 && stream.values[record.values_start] == group { group_start = record.values_start; break } }
	if group == 0 || group_start < 0 || stream.values[group_start + 2] != 0 { panic('expected canonical intrinsic attribute fixture') }
	mut altered_values := stream.values.clone(); defer { unsafe { altered_values.free() } }
	altered_stream := airbitcode.Stream{...stream, values: altered_values}; mut attribute_controls := 0
	altered_values[group_start + 3] = 54 // strictfp
	if _ := p.run_scalar_function(ir, altered_stream, pools, bodies, index, args, 64) { panic('accepted strict declaration attribute') } else { attribute_controls++ }
	altered_values[group_start + 3] = stream.values[group_start + 3]
	altered_values[group_start + 1] = 1 // parameter attribute slot
	if _ := p.run_scalar_function(ir, altered_stream, pools, bodies, index, args, 64) { panic('accepted parameter declaration attribute') } else { attribute_controls++ }
	baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; mut controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .integer}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] { compare(changed, baseline.value, cases[11]) or { controls++; continue }; panic('accepted corrupted intrinsic result') }
	for mode in [C.FE_UPWARD, C.FE_DOWNWARD]! {
		if C.fesetround(mode) != 0 { panic('cannot set rounding control') }
		for name in ['rint_32', 'nearbyint_32', 'roundeven_32'] {
			rounding_args := [if mode == C.FE_UPWARD { u64(0x3f000000) } else { u64(0x3fc00000) }, 0, 0]; defer { unsafe { rounding_args.free() } }
			expected := if mode == C.FE_UPWARD { u64(0) } else { u64(0x40000000) }
			if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, rounding_args, 64)!.value != expected { panic('intrinsic used host rounding mode') }
		}
	}
	println('LLVM-SCALAR-INTRINSICS: ${cases.len} functions, ${comparisons} comparisons (${nan_cases} arithmetic NaN-class cases), ${guards} guards, three poison results, lazy select, budget/integer isolation, ${metadata_controls} metadata/${attribute_controls} declaration/${controls} result corruptions and six host-rounding controls PASS; no AIR shader or iOS app executed')
}
