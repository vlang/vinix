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
struct FmaCase { name string bits u32 steps int }

fn fixture(mut source strings.Builder) []FmaCase {
	mut cases := []FmaCase{}; cases.flags |= .noslices
	for bits in [u32(16), 32]! {
		typ := if bits == 16 { 'half' } else { 'float' }
		decl := 'declare ${typ} @llvm.fma.f${bits}(${typ}, ${typ}, ${typ})\n'; source.write_string(decl); unsafe { decl.free() }
		optional_decl := 'declare ${typ} @llvm.fmuladd.f${bits}(${typ}, ${typ}, ${typ})\n'; source.write_string(optional_decl); unsafe { optional_decl.free() }
		for op in ['fma', 'swapped', 'chain', 'loop', 'fmuladd'] {
			name := '${op}_${bits}'; entry := FmaCase{name, bits, if op == 'chain' { 3 } else if op == 'loop' { 26 } else { 2 }}; unsafe { cases.push_many(&entry, 1) }
			mut body := '  %r = call ${typ} @llvm.fma.f${bits}(${typ} %a, ${typ} %b, ${typ} %c)\n  ret ${typ} %r\n'
			if op == 'fmuladd' { unsafe { body.free() }; body = '  %r = call ${typ} @llvm.fmuladd.f${bits}(${typ} %a, ${typ} %b, ${typ} %c)\n  ret ${typ} %r\n' }
			if op == 'swapped' { unsafe { body.free() }; body = '  %r = call ${typ} @llvm.fma.f${bits}(${typ} %b, ${typ} %a, ${typ} %c)\n  ret ${typ} %r\n' }
			if op == 'chain' { unsafe { body.free() }; body = '  %first = call ${typ} @llvm.fma.f${bits}(${typ} %a, ${typ} %b, ${typ} %c)\n  %r = call ${typ} @llvm.fma.f${bits}(${typ} %first, ${typ} %b, ${typ} %c)\n  ret ${typ} %r\n' }
			if op == 'loop' { unsafe { body.free() }; body = 'entry: br label %loop\nloop: %acc = phi ${typ} [ %a, %entry ], [ %r, %loop ]\n  %i = phi i64 [ 0, %entry ], [ %inc, %loop ]\n  %r = call ${typ} @llvm.fma.f${bits}(${typ} %acc, ${typ} %b, ${typ} %c)\n  %inc = add i64 %i, 1\n  %again = icmp ult i64 %inc, 4\n  br i1 %again, label %loop, label %exit\nexit: ret ${typ} %r\n' }
			text := 'define ${typ} @${name}(${typ} %a, ${typ} %b, ${typ} %c) {\n${body}}\n'; source.write_string(text); unsafe { body.free(); text.free() }
			wrapper := 'define i64 @reference_${name}(i64 %ai, i64 %bi, i64 %ci) {\n  %ax = trunc i64 %ai to i${bits}\n  %bx = trunc i64 %bi to i${bits}\n  %cx = trunc i64 %ci to i${bits}\n  %a = bitcast i${bits} %ax to ${typ}\n  %b = bitcast i${bits} %bx to ${typ}\n  %c = bitcast i${bits} %cx to ${typ}\n  %r = call ${typ} @${name}(${typ} %a, ${typ} %b, ${typ} %c)\n  %out = bitcast ${typ} %r to i${bits}\n  %wide = zext i${bits} %out to i64\n  ret i64 %wide\n}\n'; source.write_string(wrapper); unsafe { wrapper.free() }
		}
		for family in ['fma', 'fmuladd'] {
		prefix := if family == 'fma' { '' } else { 'optional_' }
		for side in 0 .. 3 {
			for state in ['poison', 'undef'] {
				left := if side == 0 { state } else { '%a' }; right := if side == 1 { state } else { '%b' }; third := if side == 2 { state } else { '%c' }
				text := 'define ${typ} @${prefix}${state}_${side}_${bits}(${typ} %a, ${typ} %b, ${typ} %c) {\n  %r = call ${typ} @llvm.${family}.f${bits}(${typ} ${left}, ${typ} ${right}, ${typ} ${third})\n  ret ${typ} %r\n}\n'; source.write_string(text); unsafe { text.free() }
			}
		}
		}
		for op in ['product', 'unfused'] {
			ending := if op == 'product' { '  %out = bitcast ${typ} %p to i${bits}\n' } else { '  %r = fadd ${typ} %p, %c\n  %out = bitcast ${typ} %r to i${bits}\n' }
			text := 'define i64 @${op}_${bits}(i64 %ai, i64 %bi, i64 %ci) {\n  %ax = trunc i64 %ai to i${bits}\n  %bx = trunc i64 %bi to i${bits}\n  %cx = trunc i64 %ci to i${bits}\n  %a = bitcast i${bits} %ax to ${typ}\n  %b = bitcast i${bits} %bx to ${typ}\n  %c = bitcast i${bits} %cx to ${typ}\n  %p = fmul ${typ} %a, %b\n${ending}  %wide = zext i${bits} %out to i64\n  ret i64 %wide\n}\n'; source.write_string(text); unsafe { ending.free(); text.free() }
		}
	}
	return cases
}
fn pattern(sample int, salt u64) u32 { mut x := u64(sample) + salt; x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return u32(x ^ (x >> 31)) }
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing FMA fixture') }
fn compare(actual airbitcode.IRScalarRun, reference u64, c FmaCase) !bool {
	if actual.kind != if c.bits == 16 { airbitcode.IRScalarKind.binary16 } else { airbitcode.IRScalarKind.binary32 } || actual.bits != c.bits || actual.poison || actual.steps != c.steps { return error('FMA result metadata differs') }
	nan := if c.bits == 16 { reference & 0x7fff > 0x7c00 } else { reference & 0x7fffffff > 0x7f800000 }
	if nan { if actual.value != if c.bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) } { return error('FMA preferred NaN differs') }; return true }
	if actual.value != reference { return error('FMA bits differ from native LLVM') }; return false
}
fn native(engine voidptr, name string) !NativeBits { address := C.LLVMGetFunctionAddress(engine, name.str); if address == 0 { return error('missing native FMA reference') }; return unsafe { NativeBits(voidptr(address)) } }
fn same_value(a u64, b u64, bits u32) bool {
	mask := if bits == 16 { u64(0x7fff) } else { u64(0x7fffffff) }; inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	return a == b || (a & mask > inf && b & mask > inf)
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-fma self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 || C.fegetround() != C.FE_TONEAREST { panic('cannot establish native environment') }; defer { C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) }
	mut source := strings.new_builder(32768); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }; os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('FMA fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-fma'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM FMA parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\nreference_fenv=FE_DFL_ENV,FE_TONEAREST\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tc\tvinix\tllvm\tnan_class_only\tsteps')!
	mut comparisons := 0; mut nan_cases := 0; mut differences := 0
	mut optional_results := os.create(out + '/native-optional.tsv')!; defer { optional_results.close() }; optional_results.writeln('function\ta\tb\tc\tnative_fmuladd\tfused\tunfused')!
	mut optional_choices := 0
	for c in cases {
		optional := c.name.starts_with('fmuladd_')
		index := function_index(ir, c.name)!; ref_name := if optional { 'reference_fma_${c.bits}' } else { 'reference_${c.name}' }; defer { unsafe { ref_name.free() } }; reference := native(engine, ref_name)!
		diagnostic_name := 'reference_${c.name}'; diagnostic_separate_name := 'unfused_${c.bits}'; defer { unsafe { diagnostic_name.free(); diagnostic_separate_name.free() } }; diagnostic := native(engine, diagnostic_name)!; separate_reference := native(engine, diagnostic_separate_name)!
		// Exhaust twenty-value boundary triples before random coverage.
		edges := if c.bits == 16 { [u64(0), 0x8000, 1, 0x8001, 0x03ff, 0x0400, 0x3800, 0x3c00, 0xbc00, 0x3c01, 0x3e00, 0x4000, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7c01, 0xfc01, 0x7e55, 0xfe55] } else { [u64(0), 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000, 0x3f000000, 0x3f800000, 0xbf800000, 0x3f800001, 0x3fc00000, 0x40000000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7f800001, 0xff800001, 0x7fc12345, 0xffc12345] }; defer { unsafe { edges.free() } }
		for sample in 0 .. 8000 + if c.bits == 16 { 196608 } else { 131072 } {
			mut args := [u64(0), 0, 0]; defer { unsafe { args.free() } }
			if sample < 8000 { args[0] = edges[sample / 400]; args[1] = edges[(sample / 20) % 20]; args[2] = edges[sample % 20] }
			else {
				k := sample - 8000
				for side in 0 .. 3 { args[side] = u64(pattern(k, u64(side + 1) * 0x123456789abcdef)) }
				if c.bits == 16 { args[k / 65536] = u64(k % 65536) }
				for side in 0 .. 3 { args[side] |= u64(side + 1) << 40 }
			}
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 256)!; expected := reference(args[0], args[1], args[2])
			if optional {
				observed := diagnostic(args[0], args[1], args[2]); separate := separate_reference(args[0], args[1], args[2])
				if !same_value(observed, expected, c.bits) && !same_value(observed, separate, c.bits) { panic('native optional result outside fused/unfused choices') }
				row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${observed}\t${expected}\t${separate}'; optional_results.writeln(row)!; unsafe { row.free() }; optional_choices++
			}
			nan_class := compare(actual, expected, c) or { row := 'FAIL ${c.name} ${args} got=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${actual.value}\t${expected}\t${nan_class}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if nan_class { nan_cases++ }
		}
		if !c.name.starts_with('fma_') && !optional { continue }
		product_name := 'product_${c.bits}'; separate_name := 'unfused_${c.bits}'; defer { unsafe { product_name.free(); separate_name.free() } }; product := native(engine, product_name)!; separate := native(engine, separate_name)!
		one := if c.bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }; mask := if c.bits == 16 { u64(0x3ff) } else { u64(0x7fffff) }; sign := u64(1) << (c.bits - 1)
		for sample in 0 .. 65536 {
			a := one | (u64(pattern(sample, 0xabcdef)) & mask); b := one | (u64(pattern(sample, 0xfedcba)) & mask); third := product(a, b, 0) | sign
			args := [a, b, third]; defer { unsafe { args.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 256)!; expected := reference(a, b, third)
			if compare(actual, expected, c)! { panic('finite cancellation produced NaN') }; if separate(a, b, third) != expected { differences++ }
			if optional {
				observed := diagnostic(a, b, third); unfused := separate(a, b, third)
				if !same_value(observed, expected, c.bits) && !same_value(observed, unfused, c.bits) { panic('native optional cancellation outside choices') }
				row := '${c.name}\t${a}\t${b}\t${third}\t${observed}\t${expected}\t${unfused}'; optional_results.writeln(row)!; unsafe { row.free() }; optional_choices++
			}
			row := 'cancel_${c.name}\t${a}\t${b}\t${third}\t${actual.value}\t${expected}\tfalse\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++
		}
	}
	if differences < 100000 { panic('unfused controls did not distinguish fusion') }
	mut poison_controls := 0; mut undef_controls := 0
	args := [u64(0x3f800000), 0x3f800000, 0]; defer { unsafe { args.free() } }
	for prefix in ['', 'optional_'] { for bits in [16, 32]! { for side in 0 .. 3 {
		poison_name := '${prefix}poison_${side}_${bits}'; undef_name := '${prefix}undef_${side}_${bits}'; defer { unsafe { poison_name.free(); undef_name.free() } }
		if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 64)!.poison { panic('FMA poison lost') }; poison_controls++
		p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 64) or { undef_controls++; continue }; panic('FMA undef accepted')
	} } }
	optional_index := function_index(ir, 'fmuladd_32')!; if _ := p.run_scalar_function(ir, stream, pools, bodies, optional_index, args, 1) { panic('optional budget accepted') }; if _ := p.run_integer_function(ir, stream, pools, bodies, optional_index, args, 64) { panic('integer API accepted optional multiply-add') }
	index := function_index(ir, 'fma_32')!; if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('FMA budget accepted') }; if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer API accepted FMA') }
	slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]; mut metadata_controls := 0
	for changed in [airbitcode.IRTypedInstruction{...original, operands_count: 3}, airbitcode.IRTypedInstruction{...original, operands_count: 2}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}] {
		p.instructions[slot] = changed; p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('invalid FMA call admitted')
	}; p.instructions[slot] = original
	third_slot := original.operands_start + 3; third_operand := p.operands[third_slot]
	mut integer_type := -1
	for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 64 { integer_type = i; break } }
	if integer_type < 0 { panic('missing integer type for third-argument guard') }
	for wrong_type in [-1, integer_type]! {
		p.operands[third_slot] = airbitcode.IRTypedOperand{...third_operand, type_index: wrong_type}
		p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('invalid FMA third argument admitted')
	}; p.operands[third_slot] = third_operand
	baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; mut result_controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, kind: .integer}, airbitcode.IRScalarRun{...baseline, steps: 1}] { compare(changed, baseline.value, FmaCase{'fma_32', 32, 2}) or { result_controls++; continue }; panic('corrupted FMA result accepted') }
	mut rounding_controls := 0
	for mode in [C.FE_UPWARD, C.FE_DOWNWARD]! {
		if C.fesetround(mode) != 0 { panic('cannot set rounding control') }
		for family in ['fma', 'fmuladd'] { for bits in [16, 32]! {
			name := '${family}_${bits}'; defer { unsafe { name.free() } }; one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }
			// Half an ULP above even/odd values distinguishes both modes.
			a := one + u64(mode == C.FE_DOWNWARD); half_ulp := if bits == 16 { u64(0x1000) } else { u64(0x33800000) }; rounding_args := [a, one, half_ulp]; defer { unsafe { rounding_args.free() } }
			expected := one + if mode == C.FE_UPWARD { u64(0) } else { u64(2) }
			if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, name)!, rounding_args, 64)!.value != expected { panic('FMA used host rounding mode') }; rounding_controls++
		}
		}
	}
	println('LLVM-FMA: ${cases.len} functions, ${comparisons} comparisons (${nan_cases} NaN-class cases), ${optional_choices} native optional-choice checks, ${differences} distinguishing unfused cancellations; ${poison_controls} poison/${undef_controls} undef/${metadata_controls} metadata/${result_controls} result/${rounding_controls} rounding controls and budget/integer isolation PASS; production optional calls use fused semantics; no AIR shader or iOS app executed')
}
