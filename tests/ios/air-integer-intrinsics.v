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
type NativeBits = fn (u64) u64

struct BitCase { name string bits u32 }
fn fixture(mut source strings.Builder) []BitCase {
	mut cases := []BitCase{}; cases.flags |= .noslices
	for width in u32(1) .. 65 {
		for op in ['ctpop', 'bitreverse', 'bswap'] {
			if op == 'bswap' && width % 16 != 0 { continue }
			name := '${op}_${width}'; entry := BitCase{name, width}; unsafe { cases.push_many(&entry, 1) }
			argument := if width == 64 { '%a' } else { '%x' }
			cast := if width == 64 { '' } else { '  %x = trunc i64 %a to i${width}\n' }
			ending := if width == 64 { '  ret i64 %r\n' } else { '  %wide = zext i${width} %r to i64\n  ret i64 %wide\n' }
			text := 'declare i${width} @llvm.${op}.i${width}(i${width})\ndefine i${width} @${name}(i${width} %x) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} %x)\n  ret i${width} %r\n}\ndefine i64 @reference_${name}(i64 %a) {\n${cast}  %r = call i${width} @${name}(i${width} ${argument})\n${ending}}\n'; source.write_string(text); unsafe { if width != 64 { cast.free() }; ending.free(); text.free() }
			for state in ['poison', 'undef'] {
				control := 'define i${width} @${state}_${name}(i${width} %x) {\n  %r = call i${width} @llvm.${op}.i${width}(i${width} ${state})\n  ret i${width} %r\n}\n'; source.write_string(control); unsafe { control.free() }
			}
		}
	}
	// All 132 declarations coexist in a single function. Reversal and byte
	// swapping preserve popcount; independent prefix-popcounts give a known sum.
	source.write_string('define i64 @cache_mix(i64 %a) {\n')
	for width in 1 .. 65 {
		previous := if width == 1 { '0' } else { '%sum${width - 1}' }
		if width != 64 { cast := '  %x${width} = trunc i64 %a to i${width}\n'; source.write_string(cast); unsafe { cast.free() } }
		operand := if width == 64 { '%a' } else { '%x${width}' }
		reverse := '  %r${width} = call i${width} @llvm.bitreverse.i${width}(i${width} ${operand})\n'; source.write_string(reverse); unsafe { reverse.free(); if width != 64 { operand.free() } }
		if width % 16 == 0 { swap := '  %b${width} = call i${width} @llvm.bswap.i${width}(i${width} %r${width})\n'; source.write_string(swap); unsafe { swap.free() } }
		pop_input := if width % 16 == 0 { '%b${width}' } else { '%r${width}' }
		pop := '  %p${width} = call i${width} @llvm.ctpop.i${width}(i${width} ${pop_input})\n'; source.write_string(pop); unsafe { pop_input.free(); pop.free() }
		if width != 64 { wide := '  %w${width} = zext i${width} %p${width} to i64\n'; source.write_string(wide); unsafe { wide.free() } }
		wide_name := if width == 64 { '%p64' } else { '%w${width}' }
		sum := '  %sum${width} = add i64 ${previous}, ${wide_name}\n'; source.write_string(sum); unsafe { sum.free(); if width != 1 { previous.free() }; if width != 64 { wide_name.free() } }
	}
	source.write_string('  ret i64 %sum64\n}\ndefine i64 @reference_cache_mix(i64 %a) {\n  %r = call i64 @cache_mix(i64 %a)\n  ret i64 %r\n}\n')
	return cases
}
fn function_index(ir airbitcode.IRModule, name string) !int { for i, f in ir.functions { if f.name == name { return i } }; return error('missing integer intrinsic fixture') }
fn native(engine voidptr, name string) !NativeBits { address := C.LLVMGetFunctionAddress(engine, name.str); if address == 0 { return error('missing integer intrinsic native reference') }; return unsafe { NativeBits(voidptr(address)) } }
fn mask(bits u32) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << bits) - 1 } }
fn pattern(sample int) u64 { mut x := u64(sample) + u64(0x9e3779b97f4a7c15); x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); return x ^ (x >> 31) }
fn compare(actual airbitcode.IRScalarRun, expected u64, bits u32, steps int) ! {
	if actual.kind != .integer || actual.bits != bits || actual.poison || actual.value != expected || actual.steps != steps { return error('integer intrinsic differs from native LLVM') }
}
fn main() {
	if os.args.len != 4 || os.args[1] != 'self-test' { panic('usage: air-integer-intrinsics self-test LLVM_AS FRESH_EXTERNAL_DIR') }
	out := os.args[3]; if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { panic('requires fresh external output') }; os.mkdir_all(out)!
	mut source := strings.new_builder(262144); defer { unsafe { source.free() } }; cases := fixture(mut source); defer { unsafe { for c in cases { c.name.free() }; cases.free() } }
	text := source.str(); defer { unsafe { text.free() } }; os.write_file(out + '/input.ll', text)!
	mut process := os.new_process(os.args[2]); defer { process.close() }; process.set_args([out + '/input.ll', '-o', out + '/input.bc']); process.set_redirect_stdio(); process.run(); process.wait()
	stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
	os.write_file(out + '/assemble.log', log)!; os.write_file(out + '/assemble.status', status)!; if process.code != 0 { panic('integer intrinsic fixture assembly failed') }
	data := os.read_bytes(out + '/input.bc')!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	if C.LLVMInitializeNativeTarget() != 0 || C.LLVMInitializeNativeAsmPrinter() != 0 { panic('LLVM native initialization failed') }; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'generated-integer-intrinsics'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; if C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) != 0 { panic('LLVM integer intrinsic fixture parse failed') }; mut owns_module := true; defer { if owns_module { C.LLVMDisposeModule(module_ptr) } }
	mut message := &char(unsafe { nil }); if C.LLVMVerifyModule(module_ptr, 2, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); defer { C.LLVMDisposeMessage(triple) }; C.LLVMSetTarget(module_ptr, triple); mut engine := unsafe { nil }; owns_module = false
	if C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) != 0 { detail := unsafe { cstring_to_vstring(message) }.clone(); C.LLVMDisposeMessage(message); panic(detail) }; defer { C.LLVMDisposeExecutionEngine(engine) }
	identity := 'triple=${unsafe { cstring_to_vstring(triple) }}\ndata_layout=${unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) }}\n'; defer { unsafe { identity.free() } }; os.write_file(out + '/jit-target.txt', identity)!
	mut results := os.create(out + '/comparisons.tsv')!; defer { results.close() }; results.writeln('function\tinput\tvinix\tllvm\tsteps')!
	mut comparisons := 0
	for c in cases {
		index := function_index(ir, c.name)!; reference_name := 'reference_${c.name}'; defer { unsafe { reference_name.free() } }; reference := native(engine, reference_name)!
		limit := if c.bits <= 16 { int(u64(1) << c.bits) } else { 4096 }; boundary := int(c.bits) * 2 + 8
		for sample in 0 .. boundary + limit {
			edges := [u64(0), mask(c.bits), u64(1) << (c.bits - 1), (u64(1) << (c.bits - 1)) - 1, u64(0xaaaaaaaaaaaaaaaa), 0x5555555555555555, 0x0123456789abcdef, 0xfedcba9876543210]!
			a := if sample < 8 { edges[sample] } else if sample < boundary { shift := u32((sample - 8) / 2); bit := u64(1) << shift; if sample & 1 == 0 { bit } else { ~bit } } else if c.bits <= 16 { u64(sample - boundary) } else { pattern(sample - boundary) }
			args := [a | ~mask(c.bits)]; defer { unsafe { args.free() } }
			actual := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!; expected := reference(args[0])
			compare(actual, expected, c.bits, 2) or { row := 'FAIL ${c.name} a=${a} got=${actual.value} expected=${expected}'; results.writeln(row)!; panic(row) }
			row := '${c.name}\t${args[0]}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++
		}
	}
	mut poison_controls := 0; mut undef_controls := 0; mut isolation_controls := 0
	for c in cases {
		args := [u64(0)]; defer { unsafe { args.free() } }; poison_name := 'poison_${c.name}'; undef_name := 'undef_${c.name}'; defer { unsafe { poison_name.free(); undef_name.free() } }
		if !p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, poison_name)!, args, 64)!.poison { panic('integer intrinsic poison lost') }; poison_controls++
		if _ := p.run_scalar_function(ir, stream, pools, bodies, function_index(ir, undef_name)!, args, 64) { panic('integer intrinsic undef accepted') } else { undef_controls++ }
		index := function_index(ir, c.name)!
		if _ := p.run_scalar_function(ir, stream, pools, bodies, index, args, 1) { panic('integer intrinsic budget accepted') } else { isolation_controls++ }
		if _ := p.run_integer_function(ir, stream, pools, bodies, index, args, 64) { panic('integer-only API accepted intrinsic') } else { isolation_controls++ }
	}
	mut metadata_controls := 0; mut name_controls := 0; mut result_controls := 0
	for op in ['ctpop', 'bitreverse', 'bswap'] {
		name := '${op}_32'; defer { unsafe { name.free() } }; index := function_index(ir, name)!; slot := bodies.scopes[index + 1].instructions_start; original := p.instructions[slot]
		args := [u64(0)]; defer { unsafe { args.free() } }
		for changed in [airbitcode.IRTypedInstruction{...original, flags: original.flags | 1}, airbitcode.IRTypedInstruction{...original, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...original, attribute_set: 1}, airbitcode.IRTypedInstruction{...original, calling_convention: 8}, airbitcode.IRTypedInstruction{...original, call_signature: -1}, airbitcode.IRTypedInstruction{...original, operands_count: 1}, airbitcode.IRTypedInstruction{...original, callee_function: -1}] {
			p.instructions[slot] = changed
			p.run_scalar_function(ir, stream, pools, bodies, index, args, 64) or { metadata_controls++; continue }; panic('accepted integer intrinsic metadata')
		}; p.instructions[slot] = original
		mut functions := ir.functions.clone(); defer { unsafe { functions.free() } }; altered_ir := airbitcode.IRModule{...ir, functions: functions}
		for wrong in [if op == 'bswap' { 'llvm.bswap.i16' } else { 'llvm.${op}.i31' }, 'llvm.${op}.i032', 'air.${op}.i32'] {
			defer { unsafe { if wrong != 'llvm.bswap.i16' { wrong.free() } } }
			functions[original.callee_function] = airbitcode.IRFunction{...ir.functions[original.callee_function], name: wrong}
			p.run_scalar_function(altered_ir, stream, pools, bodies, index, args, 64) or { name_controls++; continue }; panic('accepted mismatched integer intrinsic name/width')
		}
		baseline := p.run_scalar_function(ir, stream, pools, bodies, index, args, 64)!
		for changed in [airbitcode.IRScalarRun{...baseline, value: 1}, airbitcode.IRScalarRun{...baseline, kind: .binary32}, airbitcode.IRScalarRun{...baseline, bits: 16}, airbitcode.IRScalarRun{...baseline, poison: true}, airbitcode.IRScalarRun{...baseline, steps: 1}] {
			compare(changed, 0, 32, 2) or { result_controls++; continue }; panic('accepted corrupted integer intrinsic result')
		}
	}
	if metadata_controls != 21 || name_controls != 9 || result_controls != 15 { panic('integer intrinsic controls incomplete') }
	cache_index := function_index(ir, 'cache_mix')!; cache_reference := native(engine, 'reference_cache_mix')!; mut cache_controls := 0
	for i in 0 .. 258 {
		a := if i == 0 { u64(0) } else if i == 1 { ~u64(0) } else { pattern(i) }; args := [a]; defer { unsafe { args.free() } }
		actual := p.run_scalar_function(ir, stream, pools, bodies, cache_index, args, 1024)!; expected := cache_reference(a); compare(actual, expected, 64, 323)!
		if i < 2 && actual.value != if i == 0 { u64(0) } else { u64(2080) } { panic('integer declaration cache mixed result') }
		row := 'cache_mix\t${a}\t${actual.value}\t${expected}\t${actual.steps}'; results.writeln(row)!; unsafe { row.free() }; comparisons++; cache_controls++
	}
	println('LLVM-INTEGER-INTRINSICS: ${cases.len} primitives, ${comparisons} exact comparisons including ${cache_controls} all-declaration chains; ${poison_controls} poison/${undef_controls} undef/${isolation_controls} budget-integer-isolation/${metadata_controls} metadata/${name_controls} name-width/${result_controls} result-corruption controls PASS; no AIR shader or iOS app executed')
}
