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

struct FunnelCase { name string bits u32 rotate bool }
fn fixture(mut source strings.Builder) []FunnelCase {
	mut cases := []FunnelCase{}; cases.flags |= .noslices
	for width in u32(1) .. 65 {
		for op in ['fshl', 'fshr'] {
			decl := 'declare i${width} @llvm.${op}.i${width}(i${width}, i${width}, i${width})\n'; source.write_string(decl); unsafe { decl.free() }
			for rotate in [false, true]! {
				name := '${op}_${width}_${int(rotate)}'; entry := FunnelCase{name, width, rotate}; unsafe { cases.push_many(&entry, 1) }
				second := if rotate { '%a' } else { '%b' }
				cast := if width == 64 { '' } else { '  %a = trunc i64 %ai to i${width}\n  %b = trunc i64 %bi to i${width}\n  %s = trunc i64 %si to i${width}\n' }
				a := if width == 64 { '%ai' } else { '%a' }; b := if width == 64 { '%bi' } else { '%b' }; s := if width == 64 { '%si' } else { '%s' }
				ending := if width == 64 { '  ret i64 %r\n' } else { '  %wide = zext i${width} %r to i64\n  ret i64 %wide\n' }
				text := 'define i${width} @${name}(i${width} %a, i${width} %b, i${width} %s) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} %a, i${width} ${second}, i${width} %s)\n  ret i${width} %r\n}\ndefine i64 @reference_${name}(i64 %ai, i64 %bi, i64 %si) {\n${cast}  %r = call i${width} @${name}(i${width} ${a}, i${width} ${b}, i${width} ${s})\n${ending}}\n'; source.write_string(text); unsafe { if width != 64 { cast.free() }; ending.free(); text.free() }
			}
			for state in ['poison', 'undef'] { for side in 0 .. 3 {
				a := if side == 0 { state } else { '%a' }; b := if side == 1 { state } else { '%b' }; s := if side == 2 { state } else { '0' }
				text := 'define i${width} @${state}_${op}_${width}_${side}(i${width} %a, i${width} %b, i${width} %s) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} ${a}, i${width} ${b}, i${width} ${s})\n  ret i${width} %r\n}\n'; source.write_string(text); unsafe { text.free() }
			} }
		}
		chain := 'define i${width} @chain_${width}(i${width} %a, i${width} %b, i${width} %s) {\n  %x = call i${width} @llvm.fshl.i${width}(i${width} %a, i${width} %b, i${width} %s)\n  %y = call i${width} @llvm.fshl.i${width}(i${width} %b, i${width} %a, i${width} %s)\n  %r = call i${width} @llvm.fshr.i${width}(i${width} %y, i${width} %x, i${width} %s)\n  ret i${width} %r\n}\n'; source.write_string(chain); unsafe { chain.free() }
	}
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing funnel fixture') }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int, salt u64) u64 { mut x := u64(sample) + salt; x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! {
	if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('funnel bits/metadata differ from native LLVM') }
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-funnel self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(262144); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('funnel fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-funnel'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM funnel parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\ta\tb\tshift\tvinix\tllvm\tsteps')!
	mut comparisons := 0; mut boundaries := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }; address := C.LLVMGetFunctionAddress(engine, reference_name.str); if address == 0 { panic('missing funnel reference') }; reference := unsafe { NativeBits(voidptr(address)) }
		limit := if c.bits <= 5 { int(u64(1) << (3 * c.bits)) } else { 4096 }; shifts := int(2 * c.bits + 3); boundary := 64 * shifts
		for sample in 0 .. boundary + limit {
			edges := [u64(0), mask(c.bits), u64(1) << (c.bits - 1), (u64(1) << (c.bits - 1)) - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210]!
			raw_a := pattern(sample, 0x9e3779b97f4a7c15); raw_b := pattern(sample, 0x123456789abcdef0); raw_s := pattern(sample, 0xfedcba9876543210)
			a := if sample < boundary { edges[sample / (8 * shifts)] } else if c.bits <= 5 { u64(sample - boundary) & mask(c.bits) } else { raw_a }
			b := if sample < boundary { edges[(sample / shifts) % 8] } else if c.bits <= 5 { (u64(sample - boundary) >> c.bits) & mask(c.bits) } else { raw_b }
			k := sample % shifts
			s := if sample < boundary { if k < int(2 * c.bits) { u64(k) } else if k == int(2 * c.bits) { mask(c.bits) } else if k == int(2 * c.bits + 1) { u64(1) << (c.bits - 1) } else { raw_s } } else if c.bits <= 5 { u64(sample - boundary) >> (2 * c.bits) } else { raw_s }
			args := [a | ~mask(c.bits), b | ~mask(c.bits), s | ~mask(c.bits)]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := reference(args[0], args[1], args[2])
			compare(actual, expected, c.bits, 2) or { row := 'FAIL ${c.name} a=${a} b=${b} s=${s} value=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${args[0]}\t${args[1]}\t${args[2]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; if sample < boundary { boundaries++ }
		}
	}
	mut poison_controls := 0; mut undef_controls := 0; mut isolation_controls := 0; mut chain_controls := 0
	for c in cases {
		if c.rotate { continue }
		base := c.name[..c.name.len - 2]; defer { unsafe { base.free() } }
		args := [u64(0), 0, 0]; defer { unsafe { args.free() } }
		for side in 0 .. 3 {
			poison_name := 'poison_${base}_${side}'; undef_name := 'undef_${base}_${side}'; defer { unsafe { poison_name.free(); undef_name.free() } }
			if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 64)!.poison { panic('funnel poison lost') }; poison_controls++
			if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 64) { panic('funnel undef accepted') } else { undef_controls++ }
		}
		index := function_index(ir, c.name)!
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('funnel budget accepted') } else { isolation_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer API accepted funnel') } else { isolation_controls++ }
	}
	for width in u32(1) .. 65 {
		name := 'chain_${width}'; defer { unsafe { name.free() } }; index := function_index(ir, name)!
		for sample in 0 .. 8 {
			args := [pattern(sample, 0x9e3779b97f4a7c15), pattern(sample, 0x123456789abcdef0), if sample == 0 { u64(0) } else if sample == 1 { u64(width) } else if sample == 2 { ~u64(0) } else { u64(sample) }]; defer { unsafe { args.free() } }
			compare(p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!, args[0] & mask(width), width, 4)!; chain_controls++
		}
	}
	mut metadata_controls := 0; mut type_controls := 0; mut name_controls := 0; mut result_controls := 0
	mut i1_type := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == 1 { i1_type = i; break } }; if i1_type < 0 { panic('missing i1 fixture type') }
	for op in ['fshl', 'fshr'] {
		name := '${op}_32_0'; defer { unsafe { name.free() } }; index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]
		args := [u64(0x12345678), 0xabcdef01, 0]; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: original.flags | 1}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, call_signature: -1}, airbitcode.IRTypedInstruction{...original, operands_count: 3}, airbitcode.IRTypedInstruction{...original, callee_function: -1}] {
			p.instructions[slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('accepted funnel call metadata')
		}; p.instructions[slot] = original
		for side in 1 .. 4 {
			operand_slot := original.operands_start + side; saved := p.operands[operand_slot]
			p.operands[operand_slot] = airbitcode.IRTypedOperand{...saved, type_index: i1_type}
			if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) { panic('accepted mismatched funnel argument type') } else { type_controls++ }; p.operands[operand_slot] = saved
		}
		mut functions := ir.functions.clone(); defer { unsafe { functions.free() } }; altered_ir := airbitcode.IRModule{...ir, functions: functions}
		for wrong in ['llvm.${op}.i31', 'llvm.${op}.i032', 'air.${op}.i32'] {
			defer { unsafe { wrong.free() } }; functions[original.callee_function] = airbitcode.IRFunction{...ir.functions[original.callee_function], name: wrong}
			p.run_scalar_function(altered_ir, stream, pools, bodies, index, args, 64) or { name_controls++; continue }; panic('accepted mismatched funnel name/width')
		}
		baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := if op == 'fshl' { args[0] } else { args[1] }; compare(baseline, expected, 32, 2)!
		for changed in [airbitcode.IRScalarRun{...baseline, value: baseline.value ^ 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] {
			compare(changed, expected, 32, 2) or { result_controls++; continue }; panic('accepted corrupted funnel result')
		}
	}
	if metadata_controls != 14 || type_controls != 6 || name_controls != 6 || result_controls != 10 { panic('funnel controls incomplete') }
	println('LLVM-FUNNEL: ${cases.len} primitive/rotation functions, ${comparisons} exact comparisons (${boundaries} boundary triples); ${poison_controls} poison/${undef_controls} undef/${isolation_controls} budget-integer-isolation/${chain_controls} complementary-chain/${metadata_controls} metadata/${type_controls} type/${name_controls} name-width/${result_controls} result-corruption controls PASS; no AIR shader or iOS app executed')
}
