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
fn C.LLVMDisposeMessage(&char)
fn C.LLVMVerifyModule(voidptr, int, &&char) int
fn C.LLVMInitializeNativeTarget() int
fn C.LLVMInitializeNativeAsmPrinter() int
fn C.LLVMGetDefaultTargetTriple() &char
fn C.LLVMSetTarget(voidptr, &char)
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
fn C.fegetround() int
fn C.fesetround(int) int
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeFma = fn (voidptr, voidptr, voidptr, voidptr)
fn find_function(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn word(bytes []u8, count int) u64 {
	mut value := u64(0); for j in 0 .. count { value |= u64(bytes[4 + j]) << u32(8 * j) }; return value
}
fn compare(actual []u8, expected []u8, bits int) bool {
	count := bits / 8; a := word(actual, count); b := word(expected, count)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }; sign := u64(1) << u32(bits - 1); nan := b & (sign - 1) > inf
	if nan { assert a == if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }, 'preferred NaN differs' } else { assert a == b, 'FMA bits differ: ${a.hex()} vs ${b.hex()}' }
	for j in 0 .. 16 { if j < 4 || j >= 4 + count { assert actual[j] == 0xcc && expected[j] == 0xcc } }; return nan
}
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	saved_mode := C.fegetround(); assert saved_mode >= 0; defer { assert C.fesetround(saved_mode) == 0 }; assert C.fesetround(C.FE_TONEAREST) == 0
	mut source := strings.new_builder(32768)
	for fixture in ['fma_16', 'fmuladd_16', 'fma_32', 'fmuladd_32'] {
		bits := fixture.all_after_last('_').int(); op := fixture.all_before('_'); other := if op == 'fma' { 'fmuladd' } else { 'fma' }
		typ := if bits == 16 { 'half' } else { 'float' }
		source.write_string('declare ${typ} @llvm.${op}.f${bits}(${typ}, ${typ}, ${typ})\n')
		for mode in ['primitive', 'chain', 'mixed', 'unfused', 'cached'] {
			second := if mode == 'mixed' { other } else { op }
			body := if mode in ['chain', 'mixed'] { '%first = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y, ${typ} %z)\n %v = call ${typ} @llvm.${second}.f${bits}(${typ} %first, ${typ} %y, ${typ} %z)\n store ${typ} %v, ptr %dst, align 1\n' } else if mode == 'cached' { '%first = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y, ${typ} %z)\n store ${typ} %first, ptr %dst, align 1\n %v = call ${typ} @llvm.${op}.f${bits}(${typ} %first, ${typ} %y, ${typ} %z)\n' } else if mode == 'unfused' { '%product = fmul ${typ} %x, %y\n %v = fadd ${typ} %product, %z\n store ${typ} %v, ptr %dst, align 1\n' } else { '%v = call ${typ} @llvm.${op}.f${bits}(${typ} %x, ${typ} %y, ${typ} %z)\n store ${typ} %v, ptr %dst, align 1\n' }
			source.write_string('define void @${mode}_${fixture}(ptr %a, ptr %b, ptr %c, ptr %dst) { %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %z = load ${typ}, ptr %c, align 1\n ${body}ret void }\n')
		}
		for state in ['poison', 'undef'] { for side in 0 .. 3 {
			a := if side == 0 { state } else { '0.0' }; b := if side == 1 { state } else { '0.0' }; c := if side == 2 { state } else { '0.0' }
			source.write_string('define void @guard_${state}_${side}_${fixture}(ptr %dst) { %v = call ${typ} @llvm.${op}.f${bits}(${typ} ${a}, ${typ} ${b}, ${typ} ${c})\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
		} }
		for mode in ['freeze', 'select'] {
			choice := if mode == 'freeze' { 'freeze ${typ} %bad' } else { 'select i1 false, ${typ} %bad, ${typ} 1.0' }
			source.write_string('define void @${mode}_${fixture}(ptr %dst) { %bad = call ${typ} @llvm.${op}.f${bits}(${typ} poison, ${typ} 0.0, ${typ} 0.0)\n %v = ${choice}\n store ${typ} %v, ptr %dst, align 1\n ret void }\n')
		}
	}
	source.write_string('define void @preflight(ptr %dst) { store i32 17, ptr %dst, align 1\n %v = call float @llvm.fma.f32(float 1.0, float 2.0, float 3.0)\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run()
	log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'fma'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); C.LLVMDisposeMessage(triple)
	cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures(); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut native_function := C.LLVMGetFirstFunction(module_ptr)
	for native_function != unsafe { nil } { C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-cpu', cpu); C.LLVMAddTargetDependentFunctionAttr(native_function, c'target-features', features); native_function = C.LLVMGetNextFunction(native_function) }
	C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
	mut comparisons := 0; mut boundaries := 0; mut chains := 0; mut nan_cases := 0; mut distinctions := 0; mut modes := 0; mut cached_metadata := 0; mut types := 0
	mut diagnostics := os.create(out + '/native-optional.tsv')!; defer { diagnostics.close() }; diagnostics.writeln('function\tx\ty\tz\toptional\tfused\tseparate\tmatches_fused\tmatches_separate')!
	mut optional_cases := 0; mut fused_only := 0; mut separate_only := 0; mut both := 0
	for fixture in ['fma_16', 'fmuladd_16', 'fma_32', 'fmuladd_32'] {
		bits := fixture.all_after_last('_').int(); optional := fixture.starts_with('fmuladd_')
		function := find_function(ir, 'primitive_' + fixture); chain := find_function(ir, 'chain_' + fixture); mixed := find_function(ir, 'mixed_' + fixture); unfused := find_function(ir, 'unfused_' + fixture); cached := find_function(ir, 'cached_' + fixture)
		// Optional fusion consistently chooses the fused refinement. Its oracle
		// always uses native fma; native optional choices remain diagnostic only.
		address := C.LLVMGetFunctionAddress(engine, 'primitive_fma_${bits}'.str); chain_address := C.LLVMGetFunctionAddress(engine, 'chain_fma_${bits}'.str); unfused_address := C.LLVMGetFunctionAddress(engine, 'unfused_fma_${bits}'.str); optional_address := C.LLVMGetFunctionAddress(engine, 'primitive_fmuladd_${bits}'.str); assert address != 0 && chain_address != 0 && unfused_address != 0 && optional_address != 0
		count := bits / 8; sign := u64(1) << u32(bits - 1); one := if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) }; inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
		half := if bits == 16 { u64(0x3800) } else { u64(0x3f000000) }; normal := if bits == 16 { u64(0x400) } else { u64(0x800000) }; quiet := if bits == 16 { u64(0x7e55) } else { u64(0x7fc12345) }
		edges := [u64(0), sign, 1, sign | 1, normal - 1, normal, half, one, sign | one, one + 1, one - 2, inf - 1, sign | (inf - 1), inf, sign | inf, inf + 1, sign | (inf + 1), quiet]!
		samples := if bits == 16 { 131072 } else { 196608 }
		mut a := []u8{len: 16}; mut b := []u8{len: 16}; mut c := []u8{len: 16}; mut actual := []u8{len: 16, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: c, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. samples + 5832 {
			index := sample % 65536; mut x := if bits == 16 { u64(index) } else { u64(u32(index) * u32(0x9e3779b9)) }; mut y := if sample < 65536 { one } else { one + 1 }; mut z := if sample < 65536 { sign | one } else { x ^ sign }
			if bits == 32 && sample >= 131072 { y = u64(u32(index) * u32(0x85ebca6b) ^ u32(0xa5a5a5a5)); z = u64(u32(index) * u32(0xc2b2ae35) ^ u32(0x5a5a5a5a)) }
			if sample >= samples { k := sample - samples; x = edges[k / 324]; y = edges[(k / 18) % 18]; z = edges[k % 18]; boundaries++ }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)); c[3 + j] = u8(z >> u32(8 * j)) }; for j in 0 .. 16 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6)!.steps == 6
			unsafe { NativeFma(voidptr(address))(&a[1], &b[2], &c[3], &expected[4]) }; if compare(actual, expected, bits) { nan_cases++ }
			if optional && (sample < 128 || sample >= samples) {
				mut native := []u8{len: 16, init: 0xcc}; mut separate := native.clone()
				unsafe { NativeFma(voidptr(optional_address))(&a[1], &b[2], &c[3], &native[4]); NativeFma(voidptr(unfused_address))(&a[1], &b[2], &c[3], &separate[4]) }
				n := word(native, count); f := word(expected, count); s := word(separate, count)
				mf := same_class_or_bits(n, f, sign, inf); ms := same_class_or_bits(n, s, sign, inf); assert mf || ms, 'native optional result is neither fused nor separate'
				for j in 0 .. 16 { if j < 4 || j >= 4 + count { assert native[j] == 0xcc && separate[j] == 0xcc } }
				row := '${fixture}\t${x}\t${y}\t${z}\t${n}\t${f}\t${s}\t${mf}\t${ms}'; diagnostics.writeln(row)!
				if mf && ms { both++ } else if mf { fused_only++ } else { separate_only++ }; optional_cases++
				unsafe { native.free(); separate.free(); row.free() }
			}
			if sample < 2 || sample >= samples { for j in 0 .. 16 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5) { panic('budget accepted') }; for byte in actual { assert byte == 0xcc } }
			if sample < 128 || sample >= samples {
				for chained in [chain, mixed]! {
					assert p.run_memory_function(ir, stream, pools, bodies, chained, mut bindings, 7)!.steps == 7
					unsafe { NativeFma(voidptr(chain_address))(&a[1], &b[2], &c[3], &expected[4]) }; compare(actual, expected, bits); chains++
				}
			}; comparisons++
		}
		// Independent exact cases that distinguish fused from two-round arithmetic.
		epsilon_squared := if bits == 16 { u64(0x10) } else { u64(0x28800000) }; two := if bits == 16 { u64(0x4000) } else { u64(0x40000000) }
		for row in [[one + 1, one - 2, sign | one, sign | epsilon_squared], [inf - 1, two, sign | (inf - 1), inf - 1], [u64(1), half, 1, 2]] {
			for j in 0 .. count { a[1 + j] = u8(row[0] >> u32(8 * j)); b[2 + j] = u8(row[1] >> u32(8 * j)); c[3 + j] = u8(row[2] >> u32(8 * j)) }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6)!.steps == 6 && word(actual, count) == row[3]
			unsafe { NativeFma(voidptr(address))(&a[1], &b[2], &c[3], &expected[4]) }; assert word(expected, count) == row[3]
			assert p.run_memory_function(ir, stream, pools, bodies, unfused, mut bindings, 7)!.steps == 7 && word(actual, count) != row[3]
			unsafe { NativeFma(voidptr(unfused_address))(&a[1], &b[2], &c[3], &expected[4]) }; assert word(expected, count) != row[3]; compare(actual, expected, bits); distinctions++
			for mode in [C.FE_TONEAREST, C.FE_DOWNWARD, C.FE_UPWARD, C.FE_TOWARDZERO]! {
				assert C.fesetround(mode) == 0; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6)!.steps == 6 && word(actual, count) == row[3]; modes++
			}; assert C.fesetround(C.FE_TONEAREST) == 0
		}
		// Every later call is validated before an earlier store, even with the
		// declaration already cached. All three floating arguments must match.
		slot := bodies.scopes[cached + 1].instructions_start + 5; saved := p.instructions[slot]
		for j in 0 .. 16 { actual[j] = 0xcc }
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
			p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 7) { panic('cached metadata accepted') }; for byte in actual { assert byte == 0xcc }; cached_metadata++
		}; p.instructions[slot] = saved
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 32 { wrong = i; break } }; assert wrong >= 0
		for side in 1 .. 4 { operand_slot := saved.operands_start + side; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 7) { panic('operand type accepted') }; for byte in actual { assert byte == 0xcc }; p.operands[operand_slot] = operand; types++ }
		assert p.run_memory_function(ir, stream, pools, bodies, cached, mut bindings, 7)!.steps == 7
		unsafe { NativeFma(voidptr(address))(&a[1], &b[2], &c[3], &expected[4]) }; compare(actual, expected, bits)
		unsafe { a.free(); b.free(); c.free(); actual.free(); expected.free(); bindings.free() }
	}
	mut guards := 0; mut choices := 0
	for i, f in ir.functions {
		if !f.name.starts_with('guard_') && !f.name.starts_with('freeze_') && !f.name.starts_with('select_') { continue }
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if f.name.starts_with('guard_') {
			if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 3) { panic('guard accepted: ' + f.name) } else { if f.name.starts_with('guard_poison_') { assert err.msg() == 'AIR memory execution: poison store' } }; for byte in bytes { assert byte == 0xcc }; guards++
		} else {
			bits := if f.name.ends_with('_16') { 16 } else { 32 }; count := bits / 8; want := if f.name.starts_with('select_') { if bits == 16 { u64(0x3c00) } else { u64(0x3f800000) } } else { u64(0) }
			assert p.run_memory_function(ir, stream, pools, bodies, i, mut bindings, 4)!.steps == 4
			for j in 0 .. 16 { assert bytes[j] == if j >= 1 && j < 1 + count { u8(want >> u32(8 * (j - 1))) } else { u8(0xcc) } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	anchor := find_function(ir, 'preflight'); slot := bodies.scopes[anchor + 1].instructions_start + 1; saved := p.instructions[slot]; mut metadata := 0
	mut bytes := []u8{len: 8, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
		p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3) { panic('metadata accepted') }; for byte in bytes { assert byte == 0xcc }; metadata++
	}; p.instructions[slot] = saved
	assert p.run_memory_function(ir, stream, pools, bodies, anchor, mut bindings, 3)!.steps == 3 && bytes[0] == 17
	assert comparisons == 678688 && boundaries == 23328 && chains == 47680 && distinctions == 12 && modes == 48 && guards == 24 && choices == 8 && metadata == 9 && cached_metadata == 36 && types == 12 && optional_cases == 11920 && fused_only + separate_only + both == optional_cases
	result := 'AIR-MEMORY-FMA: ${comparisons} native fused-oracle comparisons (${nan_cases} arithmetic NaN-class cases, ${boundaries} boundary triples), half/float fma/fmuladd, exhaustive half/sampled float cancellation/scaling, ${chains} repeated/mixed cached chains, ${distinctions} independent fused/unfused distinctions, ${modes} rounding controls, ${optional_cases} native optional diagnostics (${fused_only} fused-only/${separate_only} separate-only/${both} both), sentinels/budgets, ${guards} poison/undef guards, ${choices} freeze/lazy choices and ${metadata}/${cached_metadata} initial/cached metadata plus ${types} operand-type controls PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
fn same_class_or_bits(a u64, b u64, sign u64, inf u64) bool {
	return a == b || (a & (sign - 1) > inf && b & (sign - 1) > inf)
}
