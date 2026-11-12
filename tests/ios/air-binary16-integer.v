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
type NativeCast = fn (u64) u64

struct CastCase { name string opcode u32 bits u32 }
struct Counts { values int poison int controls int rounding int }
fn fixture(first int, end int, mut source strings.Builder) []CastCase {
	source.write_string('declare float @llvm.trunc.f32(float)\ndeclare i64 @llvm.fptoui.sat.i64.f32(float)\ndeclare i64 @llvm.fptosi.sat.i64.f32(float)\n')
	mut cases := []CastCase{}; cases.flags |= .noslices
	for width in first .. end {
		bits := u32(width)
		for index, mnemonic in ['fptoui', 'fptosi', 'uitofp', 'sitofp'] {
			op := u32(index + 3); name := '${mnemonic}_${bits}'; entry := CastCase{name, op, bits}; unsafe { cases.push_many(&entry, 1) }
			if op <= 4 {
				original := 'define i${bits} @${name}(half %x) {\n  %r = ${mnemonic} half %x to i${bits}\n  ret i${bits} %r\n}\n'; source.write_string(original); unsafe { original.free() }
				value_header := 'define i64 @value_${name}(i64 %raw) {\n  %i = trunc i64 %raw to i16\n  %h = bitcast i16 %i to half\n  %x = fpext half %h to float\n  %wide = call i64 @llvm.${mnemonic}.sat.i64.f32(float %x)\n'; source.write_string(value_header); unsafe { value_header.free() }
				if bits == 64 { source.write_string('  ret i64 %wide\n}\n') } else {
					ending := '  %n = trunc i64 %wide to i${bits}\n  %out = zext i${bits} %n to i64\n  ret i64 %out\n}\n'; source.write_string(ending); unsafe { ending.free() }
				}
				// Truncate as FLOAT first, so fractional values just below signed
				// minima and unsigned negative fractions get the correct range tag.
				exponent := if op == 3 { bits } else { bits - 1 }; boundary := (exponent + 127) << 23
				tag_header := 'define i64 @poison_${name}(i64 %raw) {\n  %i = trunc i64 %raw to i16\n  %h = bitcast i16 %i to half\n  %x = fpext half %h to float\n  %t = call float @llvm.trunc.f32(float %x)\n  %bound = bitcast i32 ${boundary} to float\n'; source.write_string(tag_header); unsafe { tag_header.free() }
				if op == 4 { source.write_string('  %lower = fneg float %bound\n') }
				tag := '  %low = fcmp olt float %t, ${if op == 4 { '%lower' } else { '0.0' }}\n  %high = fcmp oge float %t, %bound\n  %nan = fcmp uno float %x, %x\n  %range = or i1 %low, %high\n  %bad = or i1 %range, %nan\n  %out = zext i1 %bad to i64\n  ret i64 %out\n}\n'; source.write_string(tag); unsafe { tag.free() }
			} else {
				original := 'define half @${name}(i${bits} %x) {\n  %r = ${mnemonic} i${bits} %x to half\n  ret half %r\n}\n'; source.write_string(original); unsafe { original.free() }
				header := 'define i64 @value_${name}(i64 %raw) {\n'; source.write_string(header); unsafe { header.free() }
				if bits != 64 { cast := '  %x = trunc i64 %raw to i${bits}\n'; source.write_string(cast); unsafe { cast.free() } }
				ending := '  %f = ${mnemonic} i${bits} ${if bits == 64 { '%raw' } else { '%x' }} to half\n  %i = bitcast half %f to i16\n  %out = zext i16 %i to i64\n  ret i64 %out\n}\ndefine i64 @poison_${name}(i64 %raw) { ret i64 0 }\n'; source.write_string(ending); unsafe { ending.free() }
			}
		}
	}
	return cases
}
fn pattern(sample int) u64 {
	mut x := u64(sample) + u64(0x9e3779b97f4a7c15)
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9)
	x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return x ^ (x >> 31)
}
fn input(c CastCase, sample int) u64 {
	if c.opcode >= 5 {
		mask := if c.bits == 64 { ~u64(0) } else { (u64(1) << c.bits) - 1 }; sign := u64(1) << (c.bits - 1)
		mut value := if sample < 64 { match sample % 16 { 0 { u64(0) } 1 { u64(1) } 2 { mask } 3 { mask - 1 } 4 { sign } 5 { sign - 1 } 6 { sign + 1 } 7 { u64(2049) } 8 { u64(2051) } 9 { u64(65504) } 10 { u64(65519) } 11 { u64(65520) } 12 { u64(65521) } 13 { u64(0) - 2049 } 14 { u64(0) - 2051 } else { u64(0) - 65520 } } } else if sample & 2 == 0 { pattern(sample) & 0xffff } else { pattern(sample) }
		if sample >= 64 && sample & 1 != 0 { value = u64(0) - value }
		return if c.bits == 64 { value } else { value | (u64(1) << c.bits) }
	}
	// Every raw half encoding for both destination signednesses and all widths.
	return u64(sample) | u64(0xdeadbeef00000000)
}
fn compare(actual airbitcode.IRScalarRun, expected u64, poison bool, c CastCase) ! {
	kind := if c.opcode <= 4 { airbitcode.IRScalarKind.integer } else { airbitcode.IRScalarKind.binary16 }
	bits := if c.opcode <= 4 { c.bits } else { u32(16) }
	if actual.kind != kind || actual.bits != bits || actual.steps != 2 || actual.poison != poison || (!poison && actual.value != expected) { return error('binary16 conversion differs from defined LLVM reference') }
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing cast fixture') }
fn run_batch(assembler string, out string, first int, end int) !Counts {
	os.mkdir(out)!
	mut source := strings.new_builder(262144); defer { unsafe { source.free() } }
	cases := fixture(first, end, mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(assembler); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { return error('cast fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-casts'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { return error('LLVM cast fixture parse failed') }
	mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { saved := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); return error(saved) }
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple)
	mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { saved := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); return error(saved) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\nreference_fenv=FE_DFL_ENV,FE_TONEAREST\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\traw\tvinix\tpoison\tllvm\tllvm_poison\tsteps')!
	mut values := 0; mut poison_count := 0
	mut baseline := airbitcode.IRScalarRun{}; mut baseline_expected := u64(0); mut baseline_case := CastCase{}
	mut poisoned := airbitcode.IRScalarRun{}; mut poisoned_case := CastCase{}
	for c in cases {
		index := function_index(ir, c.name)!; value_name := 'value_${c.name}'; tag_name := 'poison_${c.name}'; defer { unsafe { value_name.free(); tag_name.free() } }
		value_address := C.LLVMGetFunctionAddress(engine, value_name.str); tag_address := C.LLVMGetFunctionAddress(engine, tag_name.str)
		if value_address == 0 || tag_address == 0 { return error('missing native cast oracle') }
		value_ref := unsafe { NativeCast(voidptr(value_address)) }; tag_ref := unsafe { NativeCast(voidptr(tag_address)) }
		for sample in 0 .. if c.opcode <= 4 { 65536 } else { 8256 } {
			raw := input(c, sample); args := [raw]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 2)!
			expected := value_ref(raw); tag := tag_ref(raw); if tag > 1 { return error('non-boolean reference poison tag') }
			row := '${c.name}\t${raw}\t${actual.value}\t${actual.poison}\t${expected}\t${tag != 0}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }
			compare(actual, expected, tag != 0, c)!
			if tag != 0 { poison_count++; poisoned = actual; poisoned_case = c } else { values++; baseline = actual; baseline_expected = expected; baseline_case = c }
		}
	}
	if values == 0 || poison_count == 0 { return error('cast fixture must exercise both values and poison') }
	mut controls := 0
	for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .integer}, airbitcode.IRScalarRun{...baseline, bits: 64}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 0}] { compare(changed, baseline_expected, false, baseline_case) or { controls++; continue }; return error('accepted corrupted cast result') }
	compare(airbitcode.IRScalarRun{...poisoned, poison: false}, 0, true, poisoned_case) or { controls++ }
	if controls != 6 { return error('accepted lost poison tag') }
	mut rounding := 0
	if end == 65 {
		for mode in [C.FE_UPWARD, C.FE_DOWNWARD]! {
			if C.fesetround(mode) != 0 { return error('rounding control setup failed') }
			args := [if mode == C.FE_UPWARD { u64(2049) } else { u64(2051) }]; defer { unsafe { args.free() } }
			expected := if mode == C.FE_UPWARD { u64(0x6800) } else { u64(0x6802) }
			if p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, 'uitofp_64')!, args, 2)!.value != expected { return error('conversion used host rounding') }; rounding++
		}
		if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 { return error('cannot restore reference environment') }
	}
	println('LLVM-BINARY16-INTEGER-${first}-${end - 1}: ${values + poison_count} comparisons (${values} values, ${poison_count} poison), ${controls} corruptions rejected')
	return Counts{values, poison_count, controls, rounding}
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-binary16-integer self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	if C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) != 0 || C.fegetround() != C.FE_TONEAREST { panic('cannot establish reference environment') }; defer { C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	mut values := 0; mut poison := 0; mut controls := 0; mut rounding := 0
	for first in [1, 17, 33, 49]! {
		batch := '${out}/widths-${first}-${first + 15}'; defer { unsafe { batch.free() } }
		counts := run_batch(os.args[2], batch, first, first + 16)!
		values += counts.values; poison += counts.poison; controls += counts.controls; rounding += counts.rounding
	}
	println('LLVM-BINARY16-INTEGER: all i1..i64, ${values + poison} defined-reference comparisons (${values} values, ${poison} poison), ${controls} corruptions and ${rounding} rounding controls PASS; no invalid ordinary native cast, AIR shader or iOS app executed')
}
