// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references evaluate only defined pure intrinsics; V checks their
// result addresses and models poison before running either memory API.
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

fn untouched(data []u8) {
	for b in data {
		assert b == 0xcc
	}
}

fn check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, f int, plan &airbitcode.IRPreparedMemoryFunction, mut bindings []airbitcode.IRMemoryBinding, expected []u8, valid bool) ! {
 if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }
 untouched(bindings[3].data)
 for prepared in [false, true] {
  for j in 0 .. bindings[3].data.len { bindings[3].data[j] = 0xcc }
  if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  assert bindings[3].data == expected
 }
}
fn main() {
 assert os.args.len == 3
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut controls := 0
 for width in 1 .. 65 { for operation in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
  mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }; sign := u64(1) << u32(width - 1)
  pair := '{i${width}, i1}'; intrinsic := '@llvm.${operation}.with.overflow.i${width}'
  wide := if width == 64 { 'or i64' } else { 'zext i${width}' }
  args := '(i${width} %a, i${width} %b, i1 %c, ptr %out)'
  mut text := strings.new_builder(131072)
  text.write_string('target datalayout = "e-p:64:64"\n declare ${pair} ${intrinsic}(i${width}, i${width})\n')
  text.write_string('define void @reference(ptr %in, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %in, i64 8\n %cp = getelementptr i8, ptr %in, i64 16\n %a = load i${width}, ptr %in, align 1\n %b = load i${width}, ptr %bp, align 1\n %c = load i1, ptr %cp, align 1\n %left = call ${pair} ${intrinsic}(i${width} %a, i${width} %b)\n %right = call ${pair} ${intrinsic}(i${width} %b, i${width} 1)\n %chosen = select i1 %c, ${pair} %left, ${pair} %right\n')
  for n, value in ['left', 'right', 'chosen'] {
   text.write_string('%v${n} = extractvalue ${pair} %${value}, 0\n %f${n} = extractvalue ${pair} %${value}, 1\n %w${n} = ${wide} %v${n}${if width == 64 { ', 0' } else { ' to i64' }}\n %wf${n} = zext i1 %f${n} to i64\n %vp${n} = getelementptr i8, ptr %out, i64 ${16 * n}\n %fp${n} = getelementptr i8, ptr %out, i64 ${16 * n + 8}\n store i64 %w${n}, ptr %vp${n}, align 1\n store i64 %wf${n}, ptr %fp${n}, align 1\n')
  }
  text.write_string('ret void }\n')
  for field in 0 .. 2 {
   bits := if field == 0 { width } else { 1 }; typ := 'i${bits}'
   for mode in 0 .. 12 {
    text.write_string('define void @test_${field}_${mode}${args} { store i8 17, ptr %out\n %left = call ${pair} ${intrinsic}(i${width} ${if mode == 4 { 'poison' } else { '%a' }}, i${width} %b)\n %right = call ${pair} ${intrinsic}(i${width} %b, i${width} 1)\n')
    if mode == 7 { text.write_string('%next = add nuw i1 %c, true\n') }
    if mode < 10 {
     lhs := if mode == 3 { 'poison' } else { '%left' }
     rhs := if mode == 1 { 'zeroinitializer' } else if mode in [2, 9] { 'poison' } else { '%right' }
     condition := if mode in [5, 6] { 'poison' } else if mode == 7 { '%next' } else { '%c' }
     text.write_string('%chosen = select i1 ${condition}, ${pair} ${lhs}, ${pair} ${rhs}\n')
     if mode == 8 { text.write_string('%nested = select i1 %c, ${pair} %chosen, ${pair} %left\n') }
    }
    value := if mode == 10 { 'zeroinitializer' } else if mode == 11 { 'poison' } else if mode == 8 { '%nested' } else { '%chosen' }
    text.write_string('%extracted = extractvalue ${pair} ${value}, ${field}\n')
    if mode in [6, 9] { text.write_string('%r = freeze ${typ} %extracted\n') } else { text.write_string('%r = or ${typ} %extracted, 0\n') }
    form := mode % 3
    text.write_string(match form {
     0 { '%idx = or ${typ} %r, 0\n' }
     1 { '%idx = and ${typ} %r, ${if bits == 1 { u64(1) } else if mask < 63 { mask } else { u64(63) }}\n' }
     else { '%idx = ${if bits == 64 { 'or i64 %r, 0' } else { 'zext ' + typ + ' %r to i64' }}\n' }
    })
    text.write_string('%p = getelementptr i8, ptr %out, ${if form == 2 { 'i64' } else { typ }} %idx\n store i8 42, ptr %p\n ret void }\n')
   }
   for side in ['left', 'right', 'condition'] { for over in [false, true] {
    text.write_string('define void @depth_${field}_${side}_${over}${args} { %base = call ${pair} ${intrinsic}(i${width} %a, i${width} %b)\n')
    for i in 0 .. if over { 30 } else { 29 } {
     if side == 'condition' {
      prev := if i == 0 { '%c' } else { '%c' + (i - 1).str() }
      text.write_string('%c${i} = xor i1 ${prev}, false\n %q${i} = getelementptr i8, ptr %out, i1 %c${i}\n')
     } else {
      prev := if i == 0 { '%base' } else { '%s' + (i - 1).str() }
      text.write_string('%s${i} = select i1 %c, ${pair} ${if side == 'left' { prev } else { 'zeroinitializer' }}, ${pair} ${if side == 'right' { prev } else { 'zeroinitializer' }}\n %v${i} = extractvalue ${pair} %s${i}, ${field}\n %q${i} = getelementptr i8, ptr %out, ${typ} %v${i}\n')
     }
    }
    if side == 'condition' {
     text.write_string('%s = select i1 %c${if over { 29 } else { 28 }}, ${pair} %base, ${pair} zeroinitializer\n %v = extractvalue ${pair} %s, ${field}\n %q = getelementptr i8, ptr %out, ${typ} %v\n')
    }
    text.write_string('ret void }\n')
   } }
   for over in [false, true] {
    text.write_string('define void @nodes_${field}_${over}${args} {\n')
    for i in 0 .. 126 { text.write_string('%s${i} = select i1 %c, ${pair} zeroinitializer, ${pair} poison\n %v${i} = extractvalue ${pair} %s${i}, ${field}\n %p${i} = getelementptr i8, ptr %out, ${typ} %v${i}\n') }
    text.write_string('%last = or ${typ} %v0, %v0\n %q = getelementptr i8, ptr %out, ${typ} %last\n')
    if over { text.write_string('%over = or ${typ} %last, %last\n %r = getelementptr i8, ptr %out, ${typ} %over\n') }
    text.write_string('ret void }\n')
   }
   for kind in ['cold', 'root', 'unsupported_branch', 'unsupported_condition'] {
    text.write_string('define void @guard_${field}_${kind}${args} { store i8 17, ptr %out\n')
    if kind == 'cold' { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
    if kind == 'unsupported_branch' { text.write_string('%bad = freeze ${pair} poison\n') }
    if kind == 'unsupported_condition' { text.write_string('%bad = load i1, ptr %out\n') }
    text.write_string('%s = select i1 ${if kind == 'unsupported_condition' { '%bad' } else { 'true' }}, ${pair} ${if kind in ['cold', 'root'] { 'poison' } else { 'zeroinitializer' }}, ${pair} ${if kind == 'unsupported_branch' { '%bad' } else { 'zeroinitializer' }}\n %v = extractvalue ${pair} %s, ${field}\n %p = getelementptr i8, ptr %out, ${typ} %v\n')
    if kind == 'root' { text.write_string('%fixed = freeze ${typ} %v\n %q = getelementptr i8, ptr %out, ${typ} %fixed\n') }
    if kind == 'cold' { text.write_string('br label %exit\n exit:\n') }
    text.write_string('ret void }\n')
   }
  }
  for reverse in [false, true] {
   text.write_string('define void @cache_${reverse}${args} { store i8 17, ptr %out\n %l = call ${pair} ${intrinsic}(i${width} %a, i${width} %b)\n %r = call ${pair} ${intrinsic}(i${width} %b, i${width} 1)\n %s = select i1 %c, ${pair} %l, ${pair} %r\n')
   for field in if reverse { [1, 0] } else { [0, 1] } { text.write_string('%e${field} = extractvalue ${pair} %s, ${field}\n') }
   text.write_string('%v = ${wide} %e0${if width == 64 { ', 0' } else { ' to i64' }}\n %f = zext i1 %e1 to i64\n %mix = xor i64 %v, %f\n %idx = and i64 %mix, 63\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n')
  }
  dir := root + '/${operation}-i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
  candidates := [u64(0), 1, 2, 3, 7, 31, 63, 64, mask, sign, sign - 1, sign + 1]!
  for field in 0 .. 2 { for mode in 0 .. 12 {
   f := fi(ir, 'test_${field}_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   for condition in [false, true] { for raw_a in candidates { for raw_b in candidates {
    a := raw_a & mask; b := raw_b & mask; mut input := [a, b, u64(condition)]!; mut result := [6]u64{}
    unsafe { NativeCast(voidptr(reference))(&input[0], &input[0], &result[0]) }
    chosen := if condition { 0 } else { 2 }
    assert result[4] == result[chosen] && result[5] == result[chosen + 1]
    poisoned := (mode == 2 && !condition) || (mode in [3, 4] && condition) || mode in [5, 11] || (mode == 7 && condition)
    word := if mode in [6, 10, 11] || (mode in [1, 9] && !condition) { u64(0) } else if mode in [7, 8] { result[field] } else { result[4 + field] }
    index := if mode % 3 == 1 { word & 63 } else { word }
    bits := if mode % 3 == 2 { 64 } else if field == 0 { width } else { 1 }
    valid := !poisoned && index < 64 && index & (u64(1) << u32(bits - 1)) == 0
    mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone()
    if valid { expected[0] = 17; expected[int(index)] = 42 }
    av := [raw_a | ~mask]; bv := [raw_b | ~mask]; cv := [u64(condition) | ~u64(1)]
    mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
    if valid { accepted++ } else { refused++ }
    rows.writeln('${operation} ${width} ${field} ${mode} ${condition} ${a} ${b} ${index} ${valid} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bv.free(); cv.free(); bindings.free() }
   } } }
   plan.free()
  } }
  for reverse in [false, true] {
   f := fi(ir, 'cache_${reverse}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   for condition in [false, true] { for raw_a in candidates { for raw_b in candidates {
    a := raw_a & mask; b := raw_b & mask; mut input := [a, b, u64(condition)]!; mut result := [6]u64{}
    unsafe { NativeCast(voidptr(reference))(&input[0], &input[0], &result[0]) }
    index := (result[4] ^ result[5]) & 63
    mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); expected[0] = 17; expected[int(index)] = 42
    av := [raw_a | ~mask]; bv := [raw_b | ~mask]; cv := [u64(condition) | ~u64(1)]
    mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, true)!; accepted++
    rows.writeln('${operation} ${width} cache ${reverse} ${condition} ${a} ${b} ${index} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bv.free(); cv.free(); bindings.free() }
   } } }; plan.free()
  }
  for field in 0 .. 2 {
   for side in ['left', 'right', 'condition'] {
    plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_${field}_${side}_false'))!; plan.free()
    if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_${field}_${side}_true')) { panic('cached pair select depth') }; controls++
   }
   node_plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'nodes_${field}_false'))!; node_plan.free()
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'nodes_${field}_true')) { panic('pair node budget') }; controls++
   for kind in ['cold', 'root', 'unsupported_branch', 'unsupported_condition'] {
    f := fi(ir, 'guard_${field}_${kind}')
    mut actual := []u8{len: 64, init: 0xcc}; av := [u64(0)]; mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if kind in ['cold', 'root'] {
     plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
     if _ := plan.validate(bindings, plan.steps()) { panic('poison root validated') }; untouched(actual)
     if _ := plan.run(mut bindings, plan.steps()) { panic('poison root ran') }; untouched(actual); plan.free()
    } else { if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported pair graph') } }
    if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('bad graph ran') }; untouched(actual)
    controls++; unsafe { actual.free(); av.free(); bindings.free() }
   }
  }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 } }
 assert accepted + refused == 2875392 && controls == 6144
 line := 'AIR-PAIR-SELECT-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals, 384 overloads, both fields, twelve patterns, both shared-field extraction orders, ${controls} depth/node/cold/root/unsupported controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
