// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references extract only defined in-range lanes. V models invalid
// selectors, poison and address bounds before running either memory API.
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

fn untouched(data []u8) { for b in data { assert b == 0xcc } }
fn check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, f int, plan &airbitcode.IRPreparedMemoryFunction, mut bindings []airbitcode.IRMemoryBinding, expected []u8, valid bool) ! {
 if _ := plan.validate(bindings, plan.steps()) { assert valid, ir.functions[f].name } else { assert !valid, ir.functions[f].name + ': ' + err.msg() }
 untouched(bindings[bindings.len - 1].data)
 for prepared in [false, true] {
  for j in 0 .. bindings[bindings.len - 1].data.len { bindings[bindings.len - 1].data[j] = 0xcc }
  if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  assert bindings[bindings.len - 1].data == expected, ir.functions[f].name
 }
}

fn sample_word(bits int, sample int, lane int) u64 {
	return [u64(0), 1, ~u64(0), u64(1) << u32(bits - 1), (u64(1) << u32(bits - 1)) - 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x0123456789abcdef]![(sample + lane) % 8] & mask(bits)
}
fn input_kind(sample int, lane int, count int) int {
	if (sample == 2 && lane == count - 1) || sample == 7 { return 2 }
	if (sample == 3 && lane == count - 1) || sample == 6 { return 1 }
	return 0
}
fn literal(bits int, count int, sample int, defined bool) string {
	mut words := []string{cap: count}
	for lane in 0 .. count {
		kind := if defined { 0 } else { input_kind(sample, lane, count) }
		words << 'i${bits} ' + if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { sample_word(bits, sample, lane).str() }
	}
	return '<' + words.join(', ') + '>'
}
// Independent flattened bit stream; native LLVM is called only with defined
// replacements, and never with an invalid extraction or memory address.
fn expected_lane(words [16]u64, source_bits int, bits int, lane int) u64 {
	mut stream := [1024]u8{}
	for i in 0 .. 16 { for bit in 0 .. source_bits { stream[i * source_bits + bit] = u8(words[i] >> u32(bit) & 1) } }
	mut result := u64(0)
	for bit in 0 .. bits { if stream[lane * bits + bit] == 1 { result |= u64(1) << u32(bit) } }
	return result
}

fn scalar_check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, name string, selector u64, undefined bool, poison bool, expected u64) ! {
	for mixed in [false, true] {
		f := fi(ir, name)
		if mixed {
			if result := p.run_scalar_function(ir, stream, pools, bodies, f, [selector], 100) { assert !undefined && result.poison == poison && (poison || result.value == expected), name } else { assert undefined, name + ': ' + err.msg() }
		} else {
			if result := p.run_integer_function(ir, stream, pools, bodies, f, [selector], 100) { assert !undefined && result.poison == poison && (poison || result.value == expected), name } else { assert undefined, name + ': ' + err.msg() }
		}
	}
}

fn controls(assembler string, root string) !int {
	mut s := strings.new_builder(131072); s.write_string('target datalayout = "e-p:64:64"\n')
	args := '(<4 x i8> %a, <4 x i8> %b, i32 %j, i1 %c, ptr %out)'
	for over in [false, true] {
		s.write_string('define void @depth_${over}${args} {\n')
		// Cache every earlier source at shallow depth before extending it.
		for i in 0 .. if over { 27 } else { 26 } {
			previous := if i == 0 { '%a' } else { '%s' + (i - 1).str() }
			s.write_string('%s${i} = select i1 %c, <4 x i8> ${previous}, <4 x i8> %b\n %v${i} = extractelement <4 x i8> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i8 %v${i}\n')
		}
		s.write_string('%raw = bitcast <4 x i8> %s${if over { 26 } else { 25 }} to <2 x i16>\n %r = extractelement <2 x i16> %raw, i32 %j\n %p = getelementptr i8, ptr %out, i16 %r\n ret void }\n')
		s.write_string('define void @nodes_${over}${args} { %raw = bitcast <4 x i8> %a to <2 x i16>\n')
		for i in 0 .. if over { 240 } else { 239 } { s.write_string('%r${i} = extractelement <2 x i16> %raw, i32 %j\n %p${i} = getelementptr i8, ptr %out, i16 %r${i}\n') }
		s.write_string('ret void }\n')
	}
	kinds := ['defined', 'pack', 'split', 'crossing', 'poison_neighbor', 'poison_overlap', 'ignored_undef', 'source_freeze', 'result_freeze_undef', 'result_freeze_poison', 'scalar_freeze_poison', 'invalid_freeze', 'old_snapshot', 'insert_repair', 'shuffle', 'binary', 'select', 'mask', 'cold_undef', 'unchosen_undef', 'shared_selectors', 'roundtrip', 'loaded_source', 'loaded_scalar', 'phi', 'floating_source']
	for kind in kinds {
		s.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
		if kind == 'cold_undef' { s.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
		mut input := '<i8 1, i8 0, i8 3, i8 0>'
		if kind in ['poison_neighbor', 'poison_overlap', 'result_freeze_poison', 'scalar_freeze_poison', 'old_snapshot'] { input = '<i8 1, i8 0, i8 poison, i8 0>' }
		if kind in ['ignored_undef', 'source_freeze', 'result_freeze_undef', 'cold_undef', 'unchosen_undef'] { input = '<i8 1, i8 0, i8 undef, i8 0>' }
		if kind == 'source_freeze' { s.write_string('%sf = freeze <4 x i8> ${input}\n'); input = '%sf' }
		if kind == 'insert_repair' { s.write_string('%sf = insertelement <4 x i8> <i8 1, i8 0, i8 undef, i8 0>, i8 3, i32 2\n'); input = '%sf' }
		if kind == 'shuffle' { s.write_string('%sf = shufflevector <4 x i8> <i8 1, i8 0, i8 3, i8 0>, <4 x i8> undef, <4 x i32> <i32 2, i32 3, i32 0, i32 1>\n'); input = '%sf' }
		if kind == 'binary' { s.write_string('%sf = add <4 x i8> <i8 1, i8 0, i8 3, i8 0>, zeroinitializer\n'); input = '%sf' }
		if kind == 'select' { s.write_string('%sf = select i1 true, <4 x i8> <i8 1, i8 0, i8 3, i8 0>, <4 x i8> undef\n'); input = '%sf' }
		if kind == 'loaded_source' { s.write_string('%sf = load <4 x i8>, ptr %out, align 1\n'); input = '%sf' }
		if kind == 'loaded_scalar' { s.write_string('%load = load i8, ptr %out, align 1\n %sf = insertelement <4 x i8> zeroinitializer, i8 %load, i32 0\n'); input = '%sf' }
		if kind == 'phi' { s.write_string('br label %join\n join: %sf = phi <4 x i8> [zeroinitializer, %entry]\n'); input = '%sf' }
		if kind == 'floating_source' { s.write_string('%sf = bitcast <2 x half> zeroinitializer to <4 x i8>\n'); input = '%sf' }
		mut result_type := '<2 x i16>'
		if kind == 'split' { s.write_string('%raw = bitcast <1 x i32> <i32 67305985> to <4 x i8>\n'); result_type = '<4 x i8>' }
		else if kind == 'crossing' { s.write_string('%raw = bitcast <2 x i3> <i3 5, i3 2> to <3 x i2>\n'); result_type = '<3 x i2>' }
		else if kind == 'pack' { s.write_string('%raw = bitcast <4 x i8> <i8 1, i8 0, i8 0, i8 0> to <1 x i32>\n'); result_type = '<1 x i32>' }
		else { s.write_string('%raw = bitcast <4 x i8> ${input} to <2 x i16>\n') }
		mut chosen := '%raw'
		if kind in ['result_freeze_undef', 'result_freeze_poison', 'old_snapshot', 'invalid_freeze'] { s.write_string('%rf = freeze ${result_type} %raw\n'); if kind != 'old_snapshot' { chosen = '%rf' } }
		if kind == 'unchosen_undef' { s.write_string('%sel = select i1 true, <2 x i16> zeroinitializer, <2 x i16> %raw\n'); chosen = '%sel' }
		if kind == 'roundtrip' { s.write_string('%back = bitcast <2 x i16> %raw to <4 x i8>\n'); chosen = '%back'; result_type = '<4 x i8>' }
		if kind == 'mask' { s.write_string('%cmp = icmp eq <2 x i16> %raw, <i16 1, i16 3>\n %mask = select <2 x i1> %cmp, <2 x i16> <i16 1, i16 3>, <2 x i16> zeroinitializer\n'); chosen = '%mask' }
		bits := if result_type == '<4 x i8>' { 8 } else if result_type == '<3 x i2>' { 2 } else if result_type == '<1 x i32>' { 32 } else { 16 }
		selector := if kind in ['poison_overlap', 'result_freeze_poison', 'scalar_freeze_poison', 'old_snapshot', 'split', 'crossing', 'roundtrip'] { 1 } else if kind == 'invalid_freeze' { 2 } else { 0 }
		s.write_string('%r = extractelement ${result_type} ${chosen}, i32 ${selector}\n')
		if kind == 'scalar_freeze_poison' { s.write_string('%f = freeze i${bits} %r\n') }
		if kind == 'shared_selectors' { s.write_string('%r2 = extractelement <2 x i16> %raw, i32 1\n %p2 = getelementptr i8, ptr %out, i16 %r2\n') }
		s.write_string('%p = getelementptr i8, ptr %out, i${bits} ${if kind == 'scalar_freeze_poison' { '%f' } else { '%r' }}\n store i8 42, ptr %p\n')
		if kind == 'cold_undef' { s.write_string('br label %exit\n exit:\n') }
		s.write_string('ret void }\n')
	}
	for kind in ['defined', 'poison', 'undef', 'source_freeze', 'result_freeze'] {
		input := if kind == 'defined' { '<i8 1, i8 2, i8 3, i8 4>' } else if kind == 'poison' { 'poison' } else { 'undef' }
		s.write_string('define void @discard_${kind}() { ${if kind == 'source_freeze' { '%s = freeze <4 x i8> undef\n' } else { '' }}%v = bitcast <4 x i8> ${if kind == 'source_freeze' { '%s' } else { input }} to <2 x i16>\n ${if kind == 'result_freeze' { '%f = freeze <2 x i16> %v\n' } else { '' }}ret void }\n')
	}
	dir := root + '/controls'; data := assemble(assembler, dir, s.str())!; verify(data)!
	stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
	mut total := 0
	for name in ['depth_false', 'depth_true', 'nodes_false', 'nodes_true'] {
		if plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, name)) { assert name.ends_with('false'), name; plan.free() } else { assert name.ends_with('true'), name + ': ' + err.msg() }
		total++
	}
	for kind in kinds {
		mut bytes := []u8{len: 64, init: 0xcc}; mut expected := bytes.clone()
		mut bindings := [airbitcode.IRMemoryBinding{values: [u64(1), 0, 3, 0]}, airbitcode.IRMemoryBinding{values: [u64(1), 0, 3, 0]}, airbitcode.IRMemoryBinding{values: [u64(0)]}, airbitcode.IRMemoryBinding{values: [u64(1)]}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		f := fi(ir, kind)
		if kind in ['loaded_source', 'loaded_scalar', 'phi', 'floating_source'] { if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic(kind) }; total++; continue }
		valid := kind !in ['poison_overlap', 'ignored_undef', 'result_freeze_undef', 'invalid_freeze', 'old_snapshot', 'cold_undef', 'unchosen_undef']
		if valid {
			expected[0] = 17
			index := if kind in ['result_freeze_poison', 'scalar_freeze_poison', 'roundtrip'] { 0 } else if kind == 'shuffle' { 3 } else if kind == 'split' { 2 } else { 1 }
			expected[index] = 42
		}
		plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
		check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); total++
		unsafe { bytes.free(); expected.free(); for b in bindings { b.values.free() }; bindings.free() }
	}
	for kind in ['defined', 'poison', 'undef', 'source_freeze', 'result_freeze'] {
		if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'discard_' + kind), [], 100) { assert kind !in ['undef', 'result_freeze'] } else { assert kind in ['undef', 'result_freeze'] }; total++
	}
	f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut cast := -1
	for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 3 { cast = i; break } }
	assert cast >= 0; saved := p.instructions[cast]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 0}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, is_volatile: true}] {
		p.instructions[cast] = changed; if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed bitcast') }; total++
	}
	p.instructions[cast] = saved
	big := airbitcode.IRModule{...ir, data_layout: 'E-p:64:64'}
	if _ := p.prepare_memory_function(big, stream, pools, bodies, f) { panic('big-endian memory bitcast') }; total++
	if _ := p.run_void_function(big, stream, pools, bodies, fi(ir, 'discard_defined'), [], 100) { panic('big-endian scalar bitcast') }; total++
	p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
	return total
}

fn main() {
	assert os.args.len in [3, 4]
	root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
	if os.args.len == 4 { println('AIR-INTEGER-BITCAST-INDEX-CONTROLS: ${control_count} PASS'); return }
	mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
	mut accepted := 0; mut refused := 0; mut undefined := 0; mut lane_checks := 0; mut scalar_checks := 0; mut shapes := 0
	for source_bits in 1 .. 65 { for source_count in 1 .. 17 { for bits in 1 .. 65 {
		total := source_bits * source_count
		if total % bits != 0 || total / bits > 16 { continue }
		if source_count != 3 && !(source_bits in [1, 8, 16, 32, 64] && bits in [1, 8, 16, 32, 64]) { continue }
		count := total / bits; shapes++
		input_type := '<${source_count} x i${source_bits}>'; output_type := '<${count} x i${bits}>'
		mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n')
		text.write_string('define void @reference(ptr %in, ptr %unused, ptr %out) {\n')
		for lane in 0 .. source_count { text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = ${if source_bits == 64 { 'or i64 %w' + lane.str() + ', 0' } else { 'trunc i64 %w' + lane.str() + ' to i' + source_bits.str() }}\n %v${lane} = insertelement ${input_type} ${if lane == 0 { 'zeroinitializer' } else { '%v' + (lane - 1).str() }}, i${source_bits} %b${lane}, i32 ${lane}\n') }
		text.write_string('%raw = bitcast ${input_type} %v${source_count - 1} to ${output_type}\n')
		for lane in 0 .. count { text.write_string('%e${lane} = extractelement ${output_type} %raw, i32 ${lane}\n %z${lane} = ${if bits == 64 { 'or i64 %e' + lane.str() + ', 0' } else { 'zext i' + bits.str() + ' %e' + lane.str() + ' to i64' }}\n %o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n') }
		text.write_string('ret void }\n')
		for sample in 0 .. 8 { for mode in 0 .. 4 { for selector_bits in [1, 32, 64] {
			name := '${sample}_${mode}_${selector_bits}'
			for scalar in [false, true] {
				text.write_string(if scalar { 'define i64 @scalar_${name}(i${selector_bits} %j) {\n' } else { 'define void @test_${name}(${input_type} %a, ${input_type} %b, i${selector_bits} %j, i1 %c, ptr %out) { store i8 17, ptr %out\n' })
				input := literal(source_bits, source_count, sample, mode == 0)
				if mode == 2 { text.write_string('%sf = freeze ${input_type} ${input}\n') }
				text.write_string('%raw = bitcast ${input_type} ${if mode == 0 && !scalar { '%a' } else if mode == 2 { '%sf' } else { input }} to ${output_type}\n')
				if mode == 3 { text.write_string('%rf = freeze ${output_type} %raw\n') }
				text.write_string('%r = extractelement ${output_type} ${if mode == 3 { '%rf' } else { '%raw' }}, i${selector_bits} %j\n')
				if mode == 2 { text.write_string('%hi = lshr i${bits} %r, ${bits / 2}\n %fold = xor i${bits} %r, %hi\n') }
				text.write_string('%v = ${if mode == 3 { 'or i' + bits.str() + ' %r, 0' } else { 'and i' + bits.str() + ' ' + if mode == 2 { '%fold, ' } else { '%r, ' } + (mask(bits) & 63).str() }}\n %idx = ${if bits == 64 { 'or i64 %v, 0' } else { 'zext i' + bits.str() + ' %v to i64' }}\n')
				text.write_string(if scalar { 'ret i64 %idx }\n' } else { '%p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n' })
			}
		} } }
		dir := root + '/s${source_bits}x${source_count}-d${bits}x${count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
		stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
		reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
		for sample in 0 .. 8 { for mode in 0 .. 4 {
			mut inputs := [16]u64{}; mut result := [16]u64{}; mut poisoned := [16]bool{}; mut hard_undef := false
			mut av := []u64{len: source_count}
			for lane in 0 .. source_count {
				word := sample_word(source_bits, sample, lane); av[lane] = word | ~mask(source_bits)
				kind := if mode == 0 { 0 } else { input_kind(sample, lane, source_count) }
				inputs[lane] = if kind == 0 { word } else { u64(0) }
				if mode != 2 && kind == 2 { hard_undef = true }
				if mode == 1 && kind == 1 {
					for dest in 0 .. count { if dest * bits < (lane + 1) * source_bits && (dest + 1) * bits > lane * source_bits { poisoned[dest] = true } }
				}
			}
			unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
			for lane in 0 .. count { assert result[lane] == expected_lane(inputs, source_bits, bits, lane), dir; lane_checks++ }
			// A result freeze clears the entire overlapping destination lane,
			// including defined source bits packed into that lane.
			if mode == 3 { for lane in 0 .. source_count { if input_kind(sample, lane, source_count) == 1 { for dest in 0 .. count { if dest * bits < (lane + 1) * source_bits && (dest + 1) * bits > lane * source_bits { result[dest] = 0 } } } } }
			for selector_bits in [1, 32, 64] {
				name := '${sample}_${mode}_${selector_bits}'; f := fi(ir, 'test_' + name); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
				sm := mask(selector_bits); mut candidates := []u64{cap: count + 3}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
				for raw in candidates {
					j := raw & sm; poison := j >= u64(count) || poisoned[int(j)]
					word := if j >= u64(count) || poisoned[int(j)] { u64(0) } else { result[int(j)] }
					index := if mode in [0, 1] { word & 63 } else if mode == 2 { (word ^ (word >> u32(bits / 2))) & 63 } else { word }
					valid := !hard_undef && !poison && index < 64
					mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
					jv := [j | ~sm]; cv := [u64(1)]
					mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
					check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
					scalar_check(p, ir, stream, pools, bodies, 'scalar_' + name, jv[0], hard_undef, poison, index)!; scalar_checks += 2
					if valid { accepted++ } else { refused++ }; if hard_undef { undefined++ }
					rows.writeln('${source_bits} ${source_count} ${bits} ${count} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${poison} ${index} ${valid} PASS')!
					unsafe { actual.free(); expected.free(); jv.free(); cv.free(); bindings.free() }
				}; unsafe { candidates.free() }; plan.free()
			}; unsafe { av.free() }
		} }
		native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
	} } }
	line := 'AIR-INTEGER-BITCAST-INDEX: ${shapes} shapes, ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} whole-vector undef), ${lane_checks} native/oracle lanes, ${scalar_checks} integer/mixed results, ${control_count} controls; validation, ordinary/prepared memory and scalar execution PASS\n'
	os.write_file(root + '/result.txt', line)!; print(line)
}
