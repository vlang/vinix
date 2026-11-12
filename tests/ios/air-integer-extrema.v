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
type NativeBits = fn (u64, u64) u64

struct ExtremaCase { name string bits u32 }
fn fixture(mut source strings.Builder) []ExtremaCase {
	mut cases := []ExtremaCase{}; cases.flags |= .noslices
	for width in u32(1) .. 65 {
		for op in ['smin', 'smax', 'umin', 'umax'] {
			name := '${op}_${width}'; entry := ExtremaCase{name, width}; unsafe { cases.push_many(&entry, 1) }
			cast := if width == 64 { '' } else { '  %a = trunc i64 %ai to i${width}\n  %b = trunc i64 %bi to i${width}\n' }
			a := if width == 64 { '%ai' } else { '%a' }; b := if width == 64 { '%bi' } else { '%b' }
			ending := if width == 64 { '  ret i64 %r\n' } else { '  %wide = zext i${width} %r to i64\n  ret i64 %wide\n' }
			text := 'declare i${width} @llvm.${op}.i${width}(i${width}, i${width})\ndefine i${width} @${name}(i${width} %a, i${width} %b) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} %a, i${width} %b)\n  ret i${width} %r\n}\ndefine i64 @reference_${name}(i64 %ai, i64 %bi) {\n${cast}  %r = call i${width} @${name}(i${width} ${a}, i${width} ${b})\n${ending}}\n'; source.write_string(text); unsafe { if width != 64 { cast.free() }; ending.free(); text.free() }
			for state in ['poison', 'undef'] { for side in 0 .. 2 {
				left := if side == 0 { state } else { '%a' }; right := if side == 1 { state } else { '%b' }
				control := 'define i${width} @${state}_${name}_${side}(i${width} %a, i${width} %b) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} ${left}, i${width} ${right})\n  ret i${width} %r\n}\n'; source.write_string(control); unsafe { control.free() }
			} }
		}
		// Signed extrema preserve the input pair. Unsigned extrema of that
		// pair therefore XOR back to A xor B, regardless of signedness/order.
		chain := 'define i${width} @chain_${width}(i${width} %a, i${width} %b) {\n  %lo = call i${width} @llvm.smin.i${width}(i${width} %a, i${width} %b)\n  %hi = call i${width} @llvm.smax.i${width}(i${width} %a, i${width} %b)\n  %u = call i${width} @llvm.umin.i${width}(i${width} %lo, i${width} %hi)\n  %v = call i${width} @llvm.umax.i${width}(i${width} %lo, i${width} %hi)\n  %r = xor i${width} %u, %v\n  ret i${width} %r\n}\n'; source.write_string(chain); unsafe { chain.free() }
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing integer extrema fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int, salt u64) u64 { mut x := u64(sample) + salt; x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! {
	if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('integer extrema bits/metadata differ from native LLVM') }
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-integer-extrema self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(262144); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('integer extrema fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-integer-extrema'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM integer extrema parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }; address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing integer extrema reference') }; reference := unsafe { NativeBits(voidptr(address)) }
		limit := if c.bits <= 8 { int(u64(1) << (2 * c.bits)) } else { 4096 }
		for sample in 0 .. 144 + limit {
			sign := u64(1) << (c.bits - 1); full := mask(c.bits)
			edges := [u64(0), full, sign, sign - 1, sign + 1, u64(1), full - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210, sign >> 1]!
			a := if sample < 144 { edges[sample / 12] } else if c.bits <= 8 { u64(sample - 144) & full } else { pattern(sample, 0x9e3779b97f4a7c15) }
			b := if sample < 144 { edges[sample % 12] } else if c.bits <= 8 { u64(sample - 144) >> c.bits } else { pattern(sample, 0x123456789abcdef0) }
			args := [a | ~full, b | ~full]; defer { unsafe { args.free() } }; actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := reference(args[0], args[1])
			compare(actual, expected, c.bits, 2) or { row := 'FAIL ${c.name} a=${a} b=${b} value=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${args[0]}\t${args[1]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < 144 { boundaries++ }
		}
	}
	mut poison_controls := 0; mut undef_controls := 0; mut isolation_controls := 0; mut chain_controls := 0
	for c in cases {
		args := [u64(0), 0]; defer { unsafe { args.free() } }
		for side in 0 .. 2 {
			poison_name := 'poison_${c.name}_${side}'; undef_name := 'undef_${c.name}_${side}'; defer { unsafe { poison_name.free(); undef_name.free() } }
			if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 64)!.poison { panic('integer extrema poison lost') }; poison_controls++
			if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 64) { panic('integer extrema undef accepted') } else { undef_controls++ }
		}
		index := function_index(ir, c.name)!
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('integer extrema budget accepted') } else { isolation_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer API accepted integer extrema') } else { isolation_controls++ }
	}
	for width in u32(1) .. 65 {
		name := 'chain_${width}'; defer { unsafe { name.free() } }; index := function_index(ir, name)!
		for sample in 0 .. 8 {
			args := [pattern(sample, 0x9e3779b97f4a7c15), pattern(sample, 0x123456789abcdef0)]; defer { unsafe { args.free() } }
			compare(p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!, (args[0] ^ args[1]) & mask(width), width, 6)!; chain_controls++
		}
	}
	mut metadata_controls := 0; mut type_controls := 0; mut name_controls := 0; mut result_controls := 0
	mut i1_type := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 1 { i1_type = i; break } }; if i1_type < 0 { panic('missing i1 fixture type') }
	for op in ['smin', 'smax', 'umin', 'umax'] {
		name := '${op}_32'; defer { unsafe { name.free() } }; index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]
		args := [u64(0x80000000), 0x7fffffff]; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: original.flags | 1}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, call_signature: -1}, airbitcode.IRTypedInstruction{...original, operands_count: 2}, airbitcode.IRTypedInstruction{...original, callee_function: -1}] {
			p.instructions[slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('accepted integer extrema call metadata')
		}; p.instructions[slot] = original
		for side in 1 .. 3 {
			operand_slot := original.operands_start + side; saved := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...saved, type_index: i1_type}
			if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) { panic('accepted integer extrema type mismatch') } else { type_controls++ }; p.operands[operand_slot] = saved
		}
		mut functions := ir.functions.clone(); defer { unsafe { functions.free() } }; altered_ir := airbitcode.IRModule{...ir, functions: functions}
		for wrong in ['llvm.${op}.i31', 'llvm.${op}.i032', 'air.${op}.i32'] {
			defer { unsafe { wrong.free() } }; functions[original.callee_function] = airbitcode.IRFunction{...ir.functions[original.callee_function], name: wrong}
			p.run_scalar_function(altered_ir, stream, pools, bodies, index, args, 64) or { name_controls++; continue }; panic('accepted integer extrema name/width mismatch')
		}
		baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!
		expected := if op in ['smin', 'umax'] { args[0] } else { args[1] }; compare(baseline, expected, 32, 2)!
		for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] {
			compare(changed, expected, 32, 2) or { result_controls++; continue }; panic('accepted corrupted integer extrema result')
		}
	}
	if metadata_controls != 28 || type_controls != 8 || name_controls != 12 || result_controls != 20 { panic('integer extrema controls incomplete') }
	println('LLVM-INTEGER-EXTREMA: ${cases.len} functions, ${comparisons} exact comparisons (${boundaries} boundary pairs); ${poison_controls} poison/${undef_controls} undef/${isolation_controls} budget-integer-isolation/${chain_controls} mixed-family-chain/${metadata_controls} metadata/${type_controls} type/${name_controls} name-width/${result_controls} result-corruption controls PASS; no AIR shader or iOS app executed')
}
