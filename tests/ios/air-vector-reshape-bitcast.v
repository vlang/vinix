// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references use defined replacement lanes. V independently models
// poison, undef and freeze, then checks both memory APIs' write ordering.
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
#include <llvm-c/BitWriter.h>

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
fn C.LLVMSetDataLayout(voidptr, &char)
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
fn C.LLVMWriteBitcodeToFile(voidptr, &char) int

struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel           u32
	CodeModel          int
	NoFramePointerElim int
	EnableFastISel     int
	MCJMM              voidptr
}

fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)

type NativeCast = fn (voidptr, voidptr, voidptr)

fn assemble(assembler_path string, out string, source string) ![]u8 {
	assert !os.exists(out)
	os.mkdir_all(out)!
	os.write_file(out + '/input.ll', source)!
	mut a := os.new_process(assembler_path)
	a.set_args([out + '/input.ll', '-o', out + '/input.bc'])
	a.set_redirect_stdio_merged()
	a.run()
	log := a.stdout_slurp()
	a.wait()
	code := a.code
	a.close()
	os.write_file(out + '/assemble.log', log)!
	assert code == 0, log
	return os.read_bytes(out + '/input.bc')!
}

fn verify(data []u8) ! {
	context := C.LLVMContextCreate()
	defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify')
	defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }
	assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	defer { C.LLVMDisposeModule(module_ptr) }
	mut message := &char(unsafe { nil })
	assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}

struct NativeModule {
	context voidptr
	buffer  voidptr
	engine  voidptr
}

fn native_module(data []u8, out string) !NativeModule {
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0
	C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate()
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'indexed-memory')
	mut module_ptr := unsafe { nil }
	assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil })
	assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
	message = unsafe { nil }

	C.LLVMSetDataLayout(module_ptr, c'')
	triple := C.LLVMGetDefaultTargetTriple()
	C.LLVMSetTarget(module_ptr, triple)
	os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!
	C.LLVMDisposeMessage(triple)
	path := out + '/native-input.bc'
	assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
	cpu := C.LLVMGetHostCPUName()
	features := C.LLVMGetHostCPUFeatures()
	os.write_file(out + '/native-features.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut f := C.LLVMGetFirstFunction(module_ptr)
	for f != unsafe { nil } {
		C.LLVMAddTargetDependentFunctionAttr(f, c'target-cpu', cpu)
		C.LLVMAddTargetDependentFunctionAttr(f, c'target-features', features)
		f = C.LLVMGetNextFunction(f)
	}
	C.LLVMDisposeMessage(cpu)
	C.LLVMDisposeMessage(features)
	assert C.LLVMWriteBitcodeToFile(module_ptr, (out + '/native-input-features.bc').str) == 0
	mut options := C.LLVMMCJITCompilerOptions{}
	C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions))
	options.OptLevel = 2
	options.EnableFastISel = 0
	mut engine := unsafe { nil }
	assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
	os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	return NativeModule{context, buffer, engine}
}

fn (n NativeModule) close() {
	C.LLVMDisposeExecutionEngine(n.engine)
	C.LLVMDisposeMemoryBuffer(n.buffer)
	C.LLVMContextDispose(n.context)
}

fn fi(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }
	panic(name)
}

fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }

fn width(element int) int { return if element < 64 { element + 1 } else if element == 64 { 16 } else { 32 } }
fn typ(element int) string { return if element < 64 { 'i${element + 1}' } else if element == 64 { 'half' } else { 'float' } }
fn word(element int, sample int, lane int) u64 {
	if element == 64 { return [u64(0x7c01), 0xfc01, 0x7e55, 0xfe55, 0x8000, 0, 0x7c00, 0xfc00, 1, 0x3ff, 0x400, 0x7bff, 0xbc00, 0x3555, 0x8001, 0x3c00]![(sample + lane) % 16] }
	if element == 65 { return [u64(0x7f800001), 0xff800001, 0x7fc12345, 0xffc12345, 0x80000000, 0, 0x7f800000, 0xff800000, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0xbf800000, 0x3eaaaaab, 0x80000001, 0x3f800000]![(sample + lane) % 16] }
	return [u64(0), 1, ~u64(0), u64(1) << u32(width(element) - 1), 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x0123456789abcdef, 0x80017c017f800001]![(sample + lane) % 8] & mask(width(element))
}
fn state(sample int, lane int, count int) int {
	if (sample == 2 && lane == count - 1) || sample == 7 { return 2 }
	if (sample == 3 && lane == count - 1) || sample == 6 { return 1 }
	return 0
}
fn scalar_literal(element int, value u64) string { return if element < 64 { value.str() } else { 'bitcast (i${width(element)} ${value} to ${typ(element)})' } }
fn literal(element int, count int, sample int, defined bool) string {
	mut lanes := []string{cap: count}
	for lane in 0 .. count {
		kind := if defined { 0 } else { state(sample, lane, count) }
		lanes << typ(element) + ' ' + if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { scalar_literal(element, word(element, sample, lane)) }
	}
	return '<' + lanes.join(', ') + '>'
}
fn expected_lane(words [16]u64, source_bits int, bits int, lane int) u64 {
	mut stream := [1024]u8{}
	for i in 0 .. 16 { for bit in 0 .. source_bits { stream[i * source_bits + bit] = u8(words[i] >> u32(bit) & 1) } }
	mut result := u64(0)
	for bit in 0 .. bits { if stream[lane * bits + bit] == 1 { result |= u64(1) << u32(bit) } }
	return result
}
fn scalar_to_bits(element int, input string, output string) string { return if element < 64 { '%${output} = or i${width(element)} ${input}, 0\n' } else { '%${output} = bitcast ${typ(element)} ${input} to i${width(element)}\n' } }
fn bits_to_scalar(element int, input string, output string) string { return if element < 64 { '%${output} = or i${width(element)} ${input}, 0\n' } else { '%${output} = bitcast i${width(element)} ${input} to ${typ(element)}\n' } }
fn widen(bits int, input string, output string) string { return '%${output} = ' + if bits == 64 { 'or i64 ${input}, 0\n' } else { 'zext i${bits} ${input} to i64\n' } }

// Address roots stay constant. An executed undef cast or poison store fails
// after the preceding marker store, preserving existing write ordering.
fn memory_check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, f int, plan &airbitcode.IRPreparedMemoryFunction, mut bindings []airbitcode.IRMemoryBinding, undefined bool, poison bool, expected u64) ! {
	for prepared in [false, true] {
		for i in 0 .. bindings[2].data.len { bindings[2].data[i] = 0xcc }
		plan.validate(bindings, plan.steps())!
		for b in bindings[2].data { assert b == 0xcc }
		if prepared {
			if result := plan.run(mut bindings, plan.steps()) { assert !undefined && !poison && result.steps == plan.steps() } else { assert undefined || poison, ir.functions[f].name + ': ' + err.msg(); assert err.msg() == if undefined { 'AIR vector: undef bitcast lane' } else { 'AIR memory execution: poison store' }, err.msg() }
		} else {
			if result := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert !undefined && !poison && result.steps == plan.steps() } else { assert undefined || poison, ir.functions[f].name + ': ' + err.msg(); assert err.msg() == if undefined { 'AIR vector: undef bitcast lane' } else { 'AIR memory execution: poison store' }, err.msg() }
		}
		for i, b in bindings[2].data { assert b == if i == 3 { u8(17) } else if !undefined && !poison && i >= 11 && i < 19 { u8(expected >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${ir.functions[f].name} byte=${i}' }
	}
}

fn limits(assembler string, root string, storage bool, over bool) ! {
	mut s := strings.new_builder(8388608); s.write_string('target datalayout = "e-p:64:64"\n')
	for memory in [false, true] {
		s.write_string('define void @${if memory { 'memory' } else { 'scalar' }}(${if memory { 'ptr %out' } else { '' }}) {\n')
		if memory { s.write_string('store i8 17, ptr %out\n') }
		for i in 0 .. if storage && over { 4097 } else { 4096 } { s.write_string('%v${i} = bitcast <8 x float> zeroinitializer to <16 x half>\n') }
		if !storage { for i in 0 .. if over { 56357 } else { 56356 } { s.write_string('%e${i} = extractelement <16 x half> %v4095, i32 0\n') } }
		s.write_string('ret void }\n')
	}
	data := assemble(assembler, root, s.str())!; verify(data)!
	stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!
	mut bytes := [u8(0xcc)]; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
	if over {
		if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bindings, 70000) { panic('memory limit') } else { assert err.msg() == diagnostic, err.msg() }
		assert bytes[0] == 0xcc
		if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('void limit') } else { assert err.msg() == diagnostic, err.msg() }
	} else {
		assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bindings, 70000)!.steps == if storage { 4098 } else { 60454 }
		assert bytes[0] == 17
		assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 60453 }
	}
	p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free(); bytes.free(); bindings.free() }
}

fn controls(assembler string, root string) !int {
	mut s := strings.new_builder(32768); s.write_string('target datalayout = "e-p:64:64"\n')
	names := ['pack', 'split', 'same_float', 'same_half', 'fneg', 'old', 'source_freeze', 'result_freeze', 'roundtrip_poison', 'roundtrip_freeze', 'discard_poison', 'discard_undef', 'cold_undef', 'floating_address']
	for name in names {
		s.write_string('define void @${name}(ptr %out) { entry: store i8 17, ptr %out\n')
		if name == 'cold_undef' { s.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
		if name == 'same_float' { s.write_string('%v = bitcast <1 x float> <float bitcast (i32 2139095041 to float)> to <1 x float>\n') }
		else if name == 'same_half' { s.write_string('%v = bitcast <1 x half> <half bitcast (i16 31745 to half)> to <1 x half>\n') }
		else if name == 'split' { s.write_string('%v = bitcast <1 x float> <float bitcast (i32 2147515393 to float)> to <2 x half>\n') }
		else {
			input := if name == 'discard_undef' || name == 'cold_undef' { 'undef' } else if name == 'discard_poison' { 'poison' } else if name in ['source_freeze', 'result_freeze', 'roundtrip_poison', 'roundtrip_freeze'] { '<half bitcast (i16 31745 to half), half poison>' } else { '<half bitcast (i16 31745 to half), half bitcast (i16 32768 to half)>' }
			if name == 'source_freeze' { s.write_string('%sf = freeze <2 x half> ${input}\n') }
			s.write_string('%v = bitcast <2 x half> ${if name == 'source_freeze' { '%sf' } else { input }} to <1 x float>\n')
		}
		if name == 'old' { s.write_string('%changed = insertelement <1 x float> %v, float 0.0, i32 0\n') }
		if name == 'fneg' { s.write_string('%neg = fneg <1 x float> %v\n') }
		if name == 'result_freeze' { s.write_string('%rf = freeze <1 x float> %v\n') }
		if name.starts_with('roundtrip') { s.write_string('%back = bitcast <1 x float> %v to <2 x half>\n'); if name == 'roundtrip_freeze' { s.write_string('%rf = freeze <2 x half> %back\n') } }
		if !name.starts_with('discard') {
			half_result := name in ['split', 'same_half', 'roundtrip_poison', 'roundtrip_freeze']
			result_type := if half_result { if name == 'same_half' { '<1 x half>' } else { '<2 x half>' } } else { '<1 x float>' }
			chosen := if name in ['result_freeze', 'roundtrip_freeze'] { '%rf' } else if name == 'roundtrip_poison' { '%back' } else if name == 'fneg' { '%neg' } else { '%v' }
			bits := if half_result { 16 } else { 32 }; element := if half_result { 'half' } else { 'float' }
			s.write_string('%e = extractelement ${result_type} ${chosen}, i32 0\n %raw = bitcast ${element} %e to i${bits}\n %wide = zext i${bits} %raw to i64\n')
			if name == 'floating_address' { s.write_string('%bad = getelementptr i8, ptr %out, i64 %wide\n') }
			s.write_string('%p = getelementptr i8, ptr %out, i64 8\n store i64 %wide, ptr %p, align 1\n')
		}
		if name == 'cold_undef' { s.write_string('br label %exit\n exit:\n') }
		s.write_string('ret void }\n')
	}
	s.write_string('define i64 @loop(i64 %limit) { entry: br label %body\n body: %i = phi i64 [0, %entry], [%next, %body]\n %sum = phi i64 [0, %entry], [%added, %body]\n %bits = trunc i64 %i to i16\n %half = bitcast i16 %bits to half\n %a = insertelement <2 x half> zeroinitializer, half %half, i32 0\n %v = bitcast <2 x half> %a to <1 x float>\n %back = bitcast <1 x float> %v to <2 x half>\n %first = extractelement <2 x half> %back, i32 0\n %word = bitcast half %first to i16\n %wide = zext i16 %word to i64\n %added = add i64 %sum, %wide\n %next = add i64 %i, 1\n %cond = icmp ult i64 %next, %limit\n br i1 %cond, label %body, label %done\n done: ret i64 %added }\n')
	data := assemble(assembler, root, s.str())!; verify(data)!
	stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
	mut total := 0
	for name in names {
		f := fi(ir, name); mut bytes := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		if name == 'floating_address' { if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('floating address graph') }; total++; continue }
		plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
		for prepared in [false, true] {
			for i in 0 .. bytes.len { bytes[i] = 0xcc }
			bad := name in ['roundtrip_poison', 'discard_undef']
			if prepared { if _ := plan.run(mut bindings, 100) { assert !bad, name } else { assert bad, name + ': ' + err.msg() } }
			else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 100) { assert !bad, name } else { assert bad, name + ': ' + err.msg() } }
			value := match name { 'same_float' { u64(0x7f800001) } 'same_half', 'split', 'source_freeze' { u64(0x7c01) } 'result_freeze', 'roundtrip_freeze' { u64(0) } 'fneg' { u64(0x7c01) } else { u64(0x80007c01) } }
			for i, b in bytes { assert b == if i == 0 { u8(17) } else if !bad && !name.starts_with('discard') && name != 'cold_undef' && i >= 8 && i < 16 { u8(value >> u32((i - 8) * 8)) } else { u8(0xcc) }, '${name}: ${i}' }
			total++
		}
		plan.free(); unsafe { bytes.free(); bindings.free() }
	}
	for count in [u64(1), 2, 3, 16, 257, 513, 1024]! { result := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], 20000)!; assert !result.poison && result.value == count * (count - 1) / 2; total++ }
	f := fi(ir, 'pack'); scope := bodies.scopes[f + 1]; mut cast := -1
	for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 3 && p.types[p.instructions[i].result_type].kind == .vector_t { cast = i; break } }
	assert cast >= 0; saved := p.instructions[cast]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 9}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}] {
		p.instructions[cast] = changed; if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed reshape') }; total++
	}
	p.instructions[cast] = saved
	big := airbitcode.IRModule{...ir, data_layout: 'E-p:64:64'}
	if _ := p.prepare_memory_function(big, stream, pools, bodies, f) { panic('big-endian reshape') }; total++
	if _ := p.run_scalar_function(big, stream, pools, bodies, fi(ir, 'loop'), [u64(1)], 100) { panic('big-endian scalar reshape') }; total++
	p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
	return total
}

fn main() {
	assert os.args.len in [3, 4]
	root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!; controls_count := controls(os.args[1], root + '/controls')!
	if os.args.len == 4 { println('AIR-RESHAPE-BITCAST-CONTROLS: ${controls_count} PASS'); return }
	mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
	mut shapes := 0; mut values := 0; mut poison := 0; mut undefined := 0; mut native_checks := 0; mut scalar_checks := 0; mut budgets := 0
	for source in 0 .. 66 { for dest in 0 .. 66 {
		if source < 64 && dest < 64 { continue }
		source_bits := width(source); bits := width(dest)
		for source_count in 1 .. 17 {
			total := source_bits * source_count
			if total % bits != 0 || total / bits > 16 { continue }
			count := total / bits; shapes++
			input_type := '<${source_count} x ${typ(source)}>'; output_type := '<${count} x ${typ(dest)}>'
			mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n define void @reference(ptr %in, ptr %unused, ptr %out) {\n')
			for lane in 0 .. source_count {
				text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = ${if source_bits == 64 { 'or i64 %w' + lane.str() + ', 0' } else { 'trunc i64 %w' + lane.str() + ' to i' + source_bits.str() }}\n')
				text.write_string(bits_to_scalar(source, '%b' + lane.str(), 's' + lane.str()))
				text.write_string('%v${lane} = insertelement ${input_type} ${if lane == 0 { 'zeroinitializer' } else { '%v' + (lane - 1).str() }}, ${typ(source)} %s${lane}, i32 ${lane}\n')
			}
			text.write_string('%raw = bitcast ${input_type} %v${source_count - 1} to ${output_type}\n')
			for lane in 0 .. count {
				text.write_string('%e${lane} = extractelement ${output_type} %raw, i32 ${lane}\n' + scalar_to_bits(dest, '%e' + lane.str(), 'b_out' + lane.str()) + widen(bits, '%b_out' + lane.str(), 'z' + lane.str()) + '%o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n')
			}
			text.write_string('ret void }\n')
			for sample in 0 .. 8 { for mode in 0 .. 4 { for selector_bits in [1, 32, 64] { for memory in [false, true] {
				name := '${sample}_${mode}_${selector_bits}'
				text.write_string(if memory { 'define void @memory_${name}(i64 %seed, i${selector_bits} %j, ptr %out) { store i8 17, ptr %out\n' } else { 'define i64 @scalar_${name}(i64 %seed, i${selector_bits} %j) {\n' })
				input := literal(source, source_count, sample, mode == 0)
				if mode == 0 {
					text.write_string('%seed_bits = ${if source_bits == 64 { 'or i64 %seed, 0' } else { 'trunc i64 %seed to i' + source_bits.str() }}\n' + bits_to_scalar(source, '%seed_bits', 'seed_value'))
					text.write_string('%inserted = insertelement ${input_type} ${input}, ${typ(source)} %seed_value, i32 ${sample % source_count}\n')
				}
				if mode == 2 { text.write_string('%sf = freeze ${input_type} ${input}\n') }
				text.write_string('%raw = bitcast ${input_type} ${if mode == 0 { '%inserted' } else if mode == 2 { '%sf' } else { input }} to ${output_type}\n')
				if mode == 3 { text.write_string('%rf = freeze ${output_type} %raw\n') }
				text.write_string('%e = extractelement ${output_type} ${if mode == 3 { '%rf' } else { '%raw' }}, i${selector_bits} %j\n' + scalar_to_bits(dest, '%e', 'bits') + widen(bits, '%bits', 'result'))
				text.write_string(if memory { '%p = getelementptr i8, ptr %out, i64 8\n store i64 %result, ptr %p, align 1\n ret void }\n' } else { 'ret i64 %result }\n' })
			} } } }
			dir := root + '/s${source}x${source_count}-d${dest}x${count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
			stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
			reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
			for sample in 0 .. 8 { for mode in 0 .. 4 {
				seed := word(source, sample + 5, 0)
				mut inputs := [16]u64{}; mut result := [16]u64{}; mut poisoned := [16]bool{}; mut hard_undef := false
				for lane in 0 .. source_count {
					kind := if mode == 0 { 0 } else { state(sample, lane, source_count) }
					inputs[lane] = if kind != 0 { u64(0) } else if mode == 0 && lane == sample % source_count { seed } else { word(source, sample, lane) }
					if mode != 2 && kind == 2 { hard_undef = true }
					if kind == 1 && mode in [1, 3] { for target in 0 .. count { if target * bits < (lane + 1) * source_bits && (target + 1) * bits > lane * source_bits { poisoned[target] = true } } }
				}
				unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
				for lane in 0 .. count { assert result[lane] == expected_lane(inputs, source_bits, bits, lane), dir; native_checks++ }
				for selector_bits in [1, 32, 64] {
					name := '${sample}_${mode}_${selector_bits}'; f := fi(ir, 'memory_' + name); sf := fi(ir, 'scalar_' + name); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
					sm := mask(selector_bits); mut candidates := []u64{cap: count + 3}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
					for raw in candidates {
						j := raw & sm; selected_poison := j >= u64(count) || (mode != 3 && poisoned[int(j)])
						expected := if j >= u64(count) || poisoned[int(j)] { u64(0) } else { result[int(j)] }
						args := [seed | ~mask(source_bits), j | ~sm]
						if r := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 100) { assert !hard_undef && r.poison == selected_poison && (selected_poison || r.value == expected), name } else { assert hard_undef, name + ': ' + err.msg(); assert err.msg() == 'AIR vector: undef bitcast lane', err.msg() }
						if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 100) { panic('floating vector entered integer API') }; scalar_checks += 2
						mut bytes := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{values: [args[0]]}, airbitcode.IRMemoryBinding{values: [args[1]]}, airbitcode.IRMemoryBinding{data: bytes, offset: 3, writable: true}]
						memory_check(p, ir, stream, pools, bodies, f, plan, mut bindings, hard_undef, selected_poison, expected)!
						if hard_undef { undefined++ } else if selected_poison { poison++ } else { values++ }
						rows.writeln('${source} ${source_count} ${dest} ${count} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${selected_poison} ${expected} PASS')!
						unsafe { args.free(); bytes.free(); bindings[0].values.free(); bindings[1].values.free(); bindings.free() }
					}
					mut bytes := [u8(0xcc), 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc]!
					mut bindings := [airbitcode.IRMemoryBinding{values: [seed]}, airbitcode.IRMemoryBinding{values: [u64(0)]}, airbitcode.IRMemoryBinding{data: bytes, offset: 3, writable: true}]
					if _ := plan.run(mut bindings, plan.steps() - 1) { panic('short prepared budget') }; for b in bytes { assert b == 0xcc }; budgets++
					unsafe { bindings[0].values.free(); bindings[1].values.free(); bindings.free(); candidates.free() }; plan.free()
				}
			} }
			native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
		}
	} }
	assert shapes == 364 && values + poison + undefined == 392352 && native_checks == 95840 && scalar_checks == 784704 && budgets == 34944 && controls_count == 42
	for storage in [false, true] { for over in [false, true] { limits(os.args[1], root + '/${if storage { 'storage' } else { 'work' }}-${over}', storage, over)! } }
	line := 'AIR-RESHAPE-BITCAST: ${shapes} shapes, ${values} exact/frozen outputs, ${poison} poison-store failures, ${undefined} strict undef failures, ${native_checks} defined LLVM/oracle lanes, ${scalar_checks} scalar/integer checks, ${budgets} short budgets, ${controls_count} controls and eight shared limits PASS\n'
	os.write_file(root + '/result.txt', line)!; print(line)
}
