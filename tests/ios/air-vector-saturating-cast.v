// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references use defined replacements. An independent rational oracle
// checks saturation, while poison/undef/freeze and write ordering stay explicit.
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

fn saturation_expected(source u32, dest u32, signed bool, word u64) u64 {
	fraction_bits := if source == 16 { u32(10) } else { u32(23) }
	exponent_bits := if source == 16 { u32(5) } else { u32(8) }
	bias := if source == 16 { 15 } else { 127 }
	fraction := word & ((u64(1) << fraction_bits) - 1)
	exponent := (word >> fraction_bits) & ((u64(1) << exponent_bits) - 1)
	negative := word & (u64(1) << (source - 1)) != 0
	if exponent == (u64(1) << exponent_bits) - 1 && fraction != 0 { return 0 }
	if !signed && negative { return 0 }
	sign := u64(1) << (dest - 1)
	limit := if signed { if negative { sign } else { sign - 1 } } else { mask(int(dest)) }
	mut magnitude := fraction | if exponent != 0 { u64(1) << fraction_bits } else { u64(0) }
	mut power := int(if exponent == 0 { u64(1) } else { exponent }) - bias - int(fraction_bits)
	if exponent == (u64(1) << exponent_bits) - 1 { magnitude = limit } else if power < 0 {
		magnitude = if power <= -64 { u64(0) } else { magnitude >> u32(-power) }
	} else { for power > 0 { if magnitude > limit / 2 { magnitude = limit; break }; magnitude *= 2; power-- } }
	if magnitude > limit { magnitude = limit }
	return if negative { (u64(0) - magnitude) & mask(int(dest)) } else { magnitude }
}
fn memory_check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, f int, plan &airbitcode.IRPreparedMemoryFunction, mut bindings []airbitcode.IRMemoryBinding, undefined bool, poison bool, expected u64) ! {
	for prepared in [false, true] {
		for i in 0 .. bindings[2].data.len { bindings[2].data[i] = 0xcc }
		plan.validate(bindings, plan.steps())!
		for b in bindings[2].data { assert b == 0xcc }
		if prepared {
			if result := plan.run(mut bindings, plan.steps()) { assert !undefined && !poison && result.steps == plan.steps() } else { assert undefined || poison, ir.functions[f].name + ': ' + err.msg(); assert err.msg() == if undefined { 'AIR vector intrinsic: undef source lane' } else { 'AIR memory execution: poison store' }, err.msg() }
		} else {
			if result := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert !undefined && !poison && result.steps == plan.steps() } else { assert undefined || poison, ir.functions[f].name + ': ' + err.msg(); assert err.msg() == if undefined { 'AIR vector intrinsic: undef source lane' } else { 'AIR memory execution: poison store' }, err.msg() }
		}
		for i, b in bindings[2].data { assert b == if i == 3 { u8(17) } else if !undefined && !poison && i >= 11 && i < 19 { u8(expected >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${ir.functions[f].name} byte=${i}' }
	}
}

fn fp(bits int) string { return if bits == 16 { 'half' } else { 'float' } }
fn operation(signed bool) string { return if signed { 'fptosi' } else { 'fptoui' } }
fn overload(source int, bits int, count int, signed bool) string { return 'llvm.${operation(signed)}.sat.v${count}i${bits}.v${count}f${source}' }
fn word(source int, sample int, lane int) u64 {
	if source == 16 { return [u64(0), 0x8000, 0x3800, 0xb800, 0x3e00, 0xbe00, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e55, 0x7c01, 0xfe55, 0xfc01, 1, 0x8001]![(sample * 3 + lane) % 16] }
	return [u64(0), 0x80000000, 0x3f000000, 0xbf000000, 0x3fc00000, 0xbfc00000, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc12345, 0x7f800001, 0xffc12345, 0xff800001, 1, 0x80000001]![(sample * 3 + lane) % 16]
}
fn state(sample int, lane int, count int) int {
	if (sample == 2 && lane == count - 1) || sample == 7 { return 2 }
	if (sample == 3 && lane == count - 1) || sample == 6 { return 1 }
	return 0
}
fn literal(source int, count int, sample int, defined bool) string {
	mut lanes := []string{cap: count}
	for lane in 0 .. count {
		kind := if defined { 0 } else { state(sample, lane, count) }
		lanes << fp(source) + ' ' + if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { 'bitcast (i${source} ${word(source, sample, lane)} to ${fp(source)})' }
	}
	return '<' + lanes.join(', ') + '>'
}
fn widen(bits int, input string, output string) string { return '%${output} = ' + if bits == 64 { 'or i64 ${input}, 0\n' } else { 'zext i${bits} ${input} to i64\n' } }

fn limits(assembler string, root string, storage bool, over bool) ! {
	mut s := strings.new_builder(8388608); s.write_string('target datalayout = "e-p:64:64"\n declare <16 x i32> @llvm.fptosi.sat.v16i32.v16f32(<16 x float>)\n')
	for memory in [false, true] {
		s.write_string('define void @${if memory { 'memory' } else { 'scalar' }}(${if memory { 'ptr %out' } else { '' }}) {\n')
		if memory { s.write_string('store i8 17, ptr %out\n') }
		for i in 0 .. if storage && over { 4097 } else { 4096 } { s.write_string('%v${i} = call <16 x i32> @llvm.fptosi.sat.v16i32.v16f32(<16 x float> zeroinitializer)\n') }
		if !storage { for i in 0 .. if over { 54309 } else { 54308 } { s.write_string('%e${i} = extractelement <16 x i32> %v4095, i32 0\n') } }
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
		assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bindings, 70000)!.steps == if storage { 4098 } else { 58406 }
		assert bytes[0] == 17
		assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 58405 }
	}
	p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free(); bytes.free(); bindings.free() }
}

fn controls(assembler string, root string) !int {
	mut s := strings.new_builder(32768); s.write_string('target datalayout = "e-p:64:64"\n')
	for source in [16, 32] { for signed in [false, true] { s.write_string('declare <3 x i8> @${overload(source, 8, 3, signed)}(<3 x ${fp(source)}>)\n') } }
	s.write_string('declare <3 x i8> @alias(<3 x float>)\n')
	names := ['defined', 'nan', 'infinities', 'fraction', 'poison_neighbor', 'selected_poison', 'undef_neighbor', 'source_freeze', 'result_freeze_poison', 'result_freeze_undef', 'discard_poison', 'discard_undef', 'old', 'cold', 'compose', 'mixed', 'address', 'duplicate']
	for name in names {
		s.write_string('define void @${name}(ptr %out) { entry: store i8 17, ptr %out\n')
		if name == 'cold' { s.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
		input := if name in ['undef_neighbor', 'source_freeze', 'result_freeze_undef', 'discard_undef', 'cold'] { '<float 1.0, float undef, float 3.0>' } else if name in ['poison_neighbor', 'selected_poison', 'result_freeze_poison', 'discard_poison', 'old'] { '<float 1.0, float poison, float 3.0>' } else if name == 'nan' { '<float bitcast (i32 2139095041 to float), float bitcast (i32 4290772993 to float), float 0.0>' } else if name == 'infinities' { '<float bitcast (i32 2139095040 to float), float bitcast (i32 4286578688 to float), float 0.0>' } else if name == 'fraction' { '<float -1.75, float 1.75, float -0.5>' } else { '<float 1.0, float 2.0, float 3.0>' }
		if name == 'source_freeze' { s.write_string('%sf = freeze <3 x float> ${input}\n') }
		s.write_string('%v = call <3 x i8> @llvm.fptosi.sat.v3i8.v3f32(<3 x float> ${if name == 'source_freeze' { '%sf' } else { input }})\n')
		if name == 'duplicate' { s.write_string('%alias = call <3 x i8> @alias(<3 x float> zeroinitializer)\n') }
		if name == 'mixed' {
			s.write_string('%a = call <3 x i8> @llvm.fptoui.sat.v3i8.v3f32(<3 x float> <float -1.0, float 256.0, float 1.0>)\n %b = call <3 x i8> @llvm.fptosi.sat.v3i8.v3f16(<3 x half> <half 1.0, half -1.0, half 1.0>)\n %c = call <3 x i8> @llvm.fptoui.sat.v3i8.v3f16(<3 x half> <half -1.0, half 256.0, half 1.0>)\n %aa = extractelement <3 x i8> %a, i32 1\n %bb = extractelement <3 x i8> %b, i32 1\n %cc = extractelement <3 x i8> %c, i32 1\n %m = xor i8 %aa, %bb\n %mm = xor i8 %m, %cc\n')
		}
		if name == 'compose' { s.write_string('%cmp = icmp eq <3 x i8> %v, <i8 1, i8 2, i8 3>\n %sel = select <3 x i1> %cmp, <3 x i8> %v, <3 x i8> zeroinitializer\n %sh = shufflevector <3 x i8> %sel, <3 x i8> %v, <3 x i32> <i32 2, i32 0, i32 4>\n') }
		if name in ['result_freeze_poison', 'result_freeze_undef', 'old'] { s.write_string('%rf = freeze <3 x i8> %v\n') }
		if !name.starts_with('discard') {
			selector := if name in ['selected_poison', 'source_freeze', 'result_freeze_poison', 'old'] { 1 } else { 0 }
			chosen := if name.starts_with('result_freeze') { '%rf' } else if name == 'compose' { '%sh' } else { '%v' }
			s.write_string('%e = extractelement <3 x i8> ${chosen}, i32 ${selector}\n')
			if name == 'address' { s.write_string('%bad = getelementptr i8, ptr %out, i8 %e\n') }
			s.write_string('%w = zext i8 ${if name == 'mixed' { '%mm' } else { '%e' }} to i64\n %p = getelementptr i8, ptr %out, i64 8\n store i64 %w, ptr %p, align 1\n')
		}
		if name == 'cold' { s.write_string('br label %exit\n exit:\n') }
		s.write_string('ret void }\n')
	}
	s.write_string('define i64 @loop(i64 %limit) { entry: br label %body\n body: %i = phi i64 [0, %entry], [%next, %body]\n %sum = phi i64 [0, %entry], [%add, %body]\n %x = uitofp i64 %i to float\n %v = insertelement <3 x float> zeroinitializer, float %x, i32 0\n %c = call <3 x i8> @llvm.fptoui.sat.v3i8.v3f32(<3 x float> %v)\n %e = extractelement <3 x i8> %c, i32 0\n %w = zext i8 %e to i64\n %add = add i64 %sum, %w\n %next = add i64 %i, 1\n %cond = icmp ult i64 %next, %limit\n br i1 %cond, label %body, label %done\n done: ret i64 %add }\n')
	data := assemble(assembler, root, s.str())!; verify(data)!
	stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
	mut total := 0
	for name in names {
		f := fi(ir, name); mut bytes := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		if name in ['address', 'duplicate'] { if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported dependency: ' + name) }; total++; continue }
		plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
		for prepared in [false, true] {
			for i in 0 .. bytes.len { bytes[i] = 0xcc }
			bad := name in ['selected_poison', 'undef_neighbor', 'result_freeze_undef', 'discard_undef', 'old']
			if prepared { if _ := plan.run(mut bindings, 100) { assert !bad, name } else { assert bad, name + ': ' + err.msg() } }
			else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 100) { assert !bad, name } else { assert bad, name + ': ' + err.msg() } }
			value := match name { 'nan', 'source_freeze', 'result_freeze_poison' { u64(0) } 'infinities' { u64(127) } 'fraction', 'mixed' { u64(255) } 'compose' { u64(3) } else { u64(1) } }
			for i, b in bytes { assert b == if i == 0 { u8(17) } else if !bad && !name.starts_with('discard') && name != 'cold' && i >= 8 && i < 16 { u8(value >> u32((i - 8) * 8)) } else { u8(0xcc) }, '${name} ${i}' }
			total++
		}
		plan.free(); unsafe { bytes.free(); bindings.free() }
	}
	for count in [u64(1), 2, 3, 16, 257, 513, 1024]! { mut expected := u64(0); for i in u64(0) .. count { expected += if i < 256 { i } else { u64(255) } }; result := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], 20000)!; assert !result.poison && result.value == expected; total++ }
	f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut call := -1
	for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 34 { call = i; break } }
	assert call >= 0; saved := p.instructions[call]
	for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, calling_convention: 8}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}] {
		p.instructions[call] = changed; if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed call') }; total++
	}
	p.instructions[call] = saved
	arg := p.operands[saved.operands_start + 1]
	for changed in [airbitcode.IRTypedOperand{...arg, type_index: saved.result_type}, airbitcode.IRTypedOperand{...arg, type_index: -1}, airbitcode.IRTypedOperand{...arg, number: bodies.instructions[call].next_value}] {
		p.operands[saved.operands_start + 1] = changed; if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed source') }; total++
	}
	p.operands[saved.operands_start + 1] = arg
	mut functions := ir.functions.clone(); alias := fi(ir, 'alias'); original := functions[alias]
	functions[alias] = airbitcode.IRFunction{...original, name: 'llvm.fptosi.sat.v3i8.v3f32'}
	duplicate := airbitcode.IRModule{...ir, functions: functions}
	if _ := p.prepare_memory_function(duplicate, stream, pools, bodies, fi(ir, 'duplicate')) { panic('duplicate canonical identity') } else { assert err.msg() == 'AIR vector intrinsic: duplicate reserved declaration', err.msg() }; total++
	unsafe { functions.free() }; p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
	return total
}

fn main() {
	assert os.args.len in [3, 4]
	root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!; controls_count := controls(os.args[1], root + '/controls')!
	if os.args.len == 4 { println('AIR-VECTOR-SATURATING-CAST-CONTROLS: ${controls_count} PASS'); return }
	mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
	mut shapes := 0; mut values := 0; mut poison := 0; mut undefined := 0; mut native_checks := 0; mut scalar_checks := 0; mut exhaustive := 0
	for bits in 1 .. 65 { for source in [16, 32] { for signed in [false, true] {
		counts := if bits in [1, 8, 16, 32, 64] { []int{len: 16, init: index + 1} } else { [3] }
		for count in counts {
			shapes++
			input_type := '<${count} x ${fp(source)}>'; output_type := '<${count} x i${bits}>'; name := overload(source, bits, count, signed)
			mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n declare ${output_type} @${name}(${input_type})\n define void @reference(ptr %in, ptr %unused, ptr %out) {\n')
			for lane in 0 .. count { text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = trunc i64 %w${lane} to i${source}\n %s${lane} = bitcast i${source} %b${lane} to ${fp(source)}\n %v${lane} = insertelement ${input_type} ${if lane == 0 { 'zeroinitializer' } else { '%v' + (lane - 1).str() }}, ${fp(source)} %s${lane}, i32 ${lane}\n') }
			text.write_string('%converted = call ${output_type} @${name}(${input_type} %v${count - 1})\n')
			for lane in 0 .. count { text.write_string('%e${lane} = extractelement ${output_type} %converted, i32 ${lane}\n' + widen(bits, '%e' + lane.str(), 'z' + lane.str()) + '%o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n') }
			text.write_string('ret void }\n')
			for sample in 0 .. 8 { for mode in 0 .. 4 { for selector_bits in [1, 32, 64] { for memory in [false, true] {
				label := '${sample}_${mode}_${selector_bits}'
				text.write_string(if memory { 'define void @memory_${label}(i64 %seed, i${selector_bits} %j, ptr %out) { store i8 17, ptr %out\n' } else { 'define i64 @scalar_${label}(i64 %seed, i${selector_bits} %j) {\n' })
				input := literal(source, count, sample, mode == 0)
				if mode == 0 { text.write_string('%seed_bits = trunc i64 %seed to i${source}\n %seed_value = bitcast i${source} %seed_bits to ${fp(source)}\n %inserted = insertelement ${input_type} ${input}, ${fp(source)} %seed_value, i32 0\n') }
				if mode == 2 { text.write_string('%sf = freeze ${input_type} ${input}\n') }
				text.write_string('%converted = call ${output_type} @${name}(${input_type} ${if mode == 0 { '%inserted' } else if mode == 2 { '%sf' } else { input }})\n')
				if mode == 3 { text.write_string('%rf = freeze ${output_type} %converted\n') }
				text.write_string('%e = extractelement ${output_type} ${if mode == 3 { '%rf' } else { '%converted' }}, i${selector_bits} %j\n' + widen(bits, '%e', 'result'))
				text.write_string(if memory { '%p = getelementptr i8, ptr %out, i64 8\n store i64 %result, ptr %p, align 1\n ret void }\n' } else { 'ret i64 %result }\n' })
			} } } }
			dir := root + '/s${source}-d${bits}-n${count}-${signed}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
			stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
			reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
			for sample in 0 .. 8 { for mode in 0 .. 4 {
				seed := word(source, sample + 5, 0)
				mut inputs := [16]u64{}; mut result := [16]u64{}; mut poisoned := [16]bool{}; mut hard_undef := false
				for lane in 0 .. count {
					kind := if mode == 0 { 0 } else { state(sample, lane, count) }
					inputs[lane] = if kind != 0 { u64(0) } else if mode == 0 && lane == 0 { seed } else { word(source, sample, lane) }
					if mode != 2 && kind == 2 { hard_undef = true }
					poisoned[lane] = kind == 1 && mode in [1, 3]
				}
				unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
				for lane in 0 .. count { assert result[lane] == saturation_expected(u32(source), u32(bits), signed, inputs[lane]), '${dir} ${sample} ${mode} ${lane}'; native_checks++ }
				for selector_bits in [1, 32, 64] {
					label := '${sample}_${mode}_${selector_bits}'; f := fi(ir, 'memory_' + label); sf := fi(ir, 'scalar_' + label); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
					sm := mask(selector_bits); mut candidates := []u64{cap: count + 3}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
					for raw in candidates {
						j := raw & sm; selected_poison := j >= u64(count) || (mode != 3 && poisoned[int(j)])
						expected := if j >= u64(count) || poisoned[int(j)] { u64(0) } else { result[int(j)] }
						args := [seed | ~mask(source), j | ~sm]
						if r := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 100) { assert !hard_undef && r.poison == selected_poison && (selected_poison || r.value == expected), label } else { assert hard_undef, label + ': ' + err.msg(); assert err.msg() == 'AIR vector intrinsic: undef source lane', err.msg() }
						if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 100) { panic('floating conversion entered integer API') }; scalar_checks += 2
						mut bytes := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{values: [args[0]]}, airbitcode.IRMemoryBinding{values: [args[1]]}, airbitcode.IRMemoryBinding{data: bytes, offset: 3, writable: true}]
						memory_check(p, ir, stream, pools, bodies, f, plan, mut bindings, hard_undef, selected_poison, expected)!
						if hard_undef { undefined++ } else if selected_poison { poison++ } else { values++ }
						rows.writeln('${source} ${bits} ${count} ${signed} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${selected_poison} ${expected} PASS')!
						unsafe { args.free(); bytes.free(); bindings[0].values.free(); bindings[1].values.free(); bindings.free() }
					}
					unsafe { candidates.free() }; plan.free()
				}
			} }
			if source == 16 && count == 16 {
				f := fi(ir, 'memory_0_0_32'); sf := fi(ir, 'scalar_0_0_32'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
				mut inputs := [16]u64{}; mut result := [16]u64{}
				for lane in 0 .. 16 { inputs[lane] = word(16, 0, lane) }
				mut seed_values := []u64{len: 1}; mut arguments := [u64(0), 0]
				mut bytes := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{values: seed_values}, airbitcode.IRMemoryBinding{values: [u64(0)]}, airbitcode.IRMemoryBinding{data: bytes, offset: 3, writable: true}]
				for raw in u64(0) .. 65536 {
					inputs[0] = raw; unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
					expected := saturation_expected(16, u32(bits), signed, raw); assert result[0] == expected
					seed_values[0] = raw | ~mask(16); arguments[0] = seed_values[0]
					r := p.run_scalar_function(ir, stream, pools, bodies, sf, arguments, 100)!; assert !r.poison && r.value == expected
					memory_check(p, ir, stream, pools, bodies, f, plan, mut bindings, false, false, expected)!
					rows.writeln('half-exhaustive ${bits} ${signed} ${raw} ${expected} PASS')!; exhaustive++
				}
				plan.free(); unsafe { arguments.free(); bytes.free(); seed_values.free(); bindings[1].values.free(); bindings.free() }
			}
			native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
		}
	} } }
	for storage in [false, true] { for over in [false, true] { limits(os.args[1], root + '/${if storage { 'storage' } else { 'work' }}-${over}', storage, over)! } }
	line := 'AIR-VECTOR-SATURATING-CAST: ${shapes} shapes, ${values} exact/frozen outputs, ${poison} poison-store failures, ${undefined} strict undef failures, ${native_checks} defined native/rational lanes, ${scalar_checks} scalar/integer checks, ${exhaustive} additional exhaustive native/V half inputs, ${controls_count} controls and eight shared limits PASS\n'
	os.write_file(root + '/result.txt', line)!; print(line)
}
