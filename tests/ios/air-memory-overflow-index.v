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

fn main() {
 assert os.args.len == 3
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut controls := 0
 for width in 1 .. 65 { for operation in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
  mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }; sign := u64(1) << u32(width - 1)
  pair := '{i${width}, i1}'; intrinsic := '@llvm.${operation}.with.overflow.i${width}'
  mut text := strings.new_builder(32768)
  text.write_string('target datalayout = "e-p:64:64"\n declare ${pair} ${intrinsic}(i${width}, i${width})\n')
  text.write_string('define void @reference(ptr %in, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %in, i64 8\n %a = load i${width}, ptr %in, align 1\n %b = load i${width}, ptr %bp, align 1\n %pair = call ${pair} ${intrinsic}(i${width} %a, i${width} %b)\n %v = extractvalue ${pair} %pair, 0\n %f = extractvalue ${pair} %pair, 1\n %wide = ${if width == 64 { 'or i64 %v, 0' } else { 'zext i' + width.str() + ' %v to i64' }}\n %flag = zext i1 %f to i64\n store i64 %wide, ptr %out, align 1\n %fp = getelementptr i8, ptr %out, i64 8\n store i64 %flag, ptr %fp, align 1\n ret void }\n')
  for field in 0 .. 2 {
   bits := if field == 0 { width } else { 1 }; typ := 'i${bits}'
   for mode in 0 .. 8 {
    text.write_string('define void @test_${field}_${mode}(i${width} %a, i${width} %b, ptr %out) { store i8 17, ptr %out\n')
    if mode == 6 { text.write_string('%next = add nuw i${width} %b, 1\n') }
    text.write_string('%pair = call ${pair} ${intrinsic}(i${width} ${if mode == 2 { 'poison' } else { '%a' }}, i${width} ${if mode in [3, 4, 5] { 'poison' } else if mode == 6 { '%next' } else { '%b' }})\n %r = extractvalue ${pair} %pair, ${field}\n')
    text.write_string(match mode {
     1 { '%idx = and ${typ} %r, ${if bits == 1 { u64(1) } else if mask < 63 { mask } else { u64(63) }}\n' }
     4 { '%idx = freeze ${typ} %r\n' }
     5 { '%idx = select i1 false, ${typ} %r, ${typ} 0\n' }
     7 { '%idx = ${if bits == 64 { 'or i64 %r, 0' } else { 'zext ' + typ + ' %r to i64' }}\n' }
     else { '%idx = or ${typ} %r, 0\n' }
    })
    text.write_string('%p = getelementptr i8, ptr %out, ${if mode == 7 { 'i64' } else { typ }} %idx\n store i8 42, ptr %p\n ret void }\n')
   }
   // Cache each smaller subtree before extending either dependency. The
   // call and extraction each consume a private node and a depth level.
   for right in [false, true] { for padding in [1, 2] {
    text.write_string('define void @depth_${field}_${padding}_${right}(i${width} %a, ptr %out) { %base = add i${width} %a, 0\n')
    if padding == 2 { text.write_string('%base2 = add i${width} %base, 0\n') }
    for i in 0 .. 15 {
     prev := if i == 0 { if padding == 1 { '%base' } else { '%base2' } } else { '%n' + (i - 1).str() }
     out_field := if i == 14 { field } else { 0 }; out_type := if out_field == 0 { 'i${width}' } else { 'i1' }
     text.write_string('%pair${i} = call ${pair} ${intrinsic}(i${width} ${if right { '0' } else { prev }}, i${width} ${if right { prev } else { '0' }})\n %n${i} = extractvalue ${pair} %pair${i}, ${out_field}\n %p${i} = getelementptr i8, ptr %out, ${out_type} %n${i}\n')
    }
    text.write_string('ret void }\n')
   } }
   for kind in ['cold', 'root', 'pair_insert', 'pair_freeze', 'pair_flag_insert', 'loaded', 'undef'] {
    text.write_string('define void @guard_${field}_${kind}(i${width} %a, i${width} %b, ptr %out) { store i8 17, ptr %out\n')
    if kind == 'cold' { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
    if kind == 'loaded' { text.write_string('%loaded = load i${width}, ptr %out, align 1\n') }
    text.write_string('%pair = call ${pair} ${intrinsic}(i${width} ${if kind in ['cold', 'root'] { 'poison' } else if kind == 'undef' { 'undef' } else if kind == 'loaded' { '%loaded' } else { '%a' }}, i${width} %b)\n')
    if kind == 'pair_insert' { text.write_string('%flow = insertvalue ${pair} %pair, i${width} %a, 0\n') }
    if kind == 'pair_flag_insert' { text.write_string('%flow = insertvalue ${pair} %pair, i1 false, 1\n') }
    if kind == 'pair_freeze' { text.write_string('%flow = freeze ${pair} %pair\n') }
    text.write_string('%r = extractvalue ${pair} ${if kind in ['pair_insert', 'pair_flag_insert', 'pair_freeze'] { '%flow' } else { '%pair' }}, ${field}\n %p = getelementptr i8, ptr %out, ${typ} %r\n')
    if kind == 'root' { text.write_string('%fixed = freeze ${typ} %r\n %safe = getelementptr i8, ptr %out, ${typ} %fixed\n') }
    if kind == 'cold' { text.write_string('br label %exit\n exit:\n') }
    text.write_string('ret void }\n')
   }
  }
  dir := root + '/${operation}-i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
  candidates := [u64(0), 1, 2, 3, 7, 15, 31, 63, 64, u64(width - 1), u64(width), mask, sign, sign - 1, sign + 1]!
  for field in 0 .. 2 { for mode in 0 .. 8 {
   bits := if mode == 7 { 64 } else if field == 0 { width } else { 1 }; index_sign := u64(1) << u32(bits - 1)
   f := fi(ir, 'test_${field}_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   for raw_a in candidates { for raw_b in candidates {
    a := raw_a & mask; b := raw_b & mask; mut input := [a, if mode == 6 { (b + 1) & mask } else { b }]!; mut result := [u64(0), 0]!
    unsafe { NativeCast(voidptr(reference))(&input[0], &input[0], &result[0]) }
    assert result[0] <= mask && result[1] <= 1
    poisoned := mode in [2, 3] || (mode == 6 && b == mask)
    index := if mode in [4, 5] { u64(0) } else if mode == 1 { result[field] & 63 } else { result[field] }
    valid := !poisoned && index < 64 && index & index_sign == 0
    mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone()
    if valid { expected[0] = 17; expected[int(index)] = 42 }
    av := [raw_a | ~mask]; bv := [raw_b | ~mask]; mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }; untouched(actual)
    for prepared in [false, true] {
     for j in 0 .. actual.len { actual[j] = 0xcc }
     if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
     assert actual == expected, '${operation} ${width} ${field} ${mode} ${a} ${b}'
    }
    if valid { accepted++ } else { refused++ }
    rows.writeln('${operation} ${width} ${field} ${mode} ${a} ${b} ${index} ${valid} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bv.free(); bindings.free() }
   } }
   plan.free()
  } }
  for field in 0 .. 2 {
   for right in [false, true] {
    depth := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_${field}_1_${right}'))!; depth.free()
    if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_${field}_2_${right}')) { panic('cached overflow depth') }; controls++
   }
   for kind in ['cold', 'root', 'pair_insert', 'pair_freeze', 'pair_flag_insert', 'loaded', 'undef'] {
    f := fi(ir, 'guard_${field}_${kind}')
    mut actual := []u8{len: 64, init: 0xcc}; av := [u64(0)]; mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if kind in ['cold', 'root'] {
     plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
     if _ := plan.validate(bindings, plan.steps()) { panic('poison root validated') }; untouched(actual)
     if _ := plan.run(mut bindings, plan.steps()) { panic('poison root ran') }; untouched(actual); plan.free()
    } else { if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported pair dependency') } }
    if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported/poison dependency ran') }; untouched(actual)
    controls++; unsafe { actual.free(); av.free(); bindings.free() }
   }
  }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 } }
 assert accepted + refused == 1382400 && controls == 6912
 line := 'AIR-OVERFLOW-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals, 384 overloads, both fields, eight patterns, ${controls} depth/cold/root/unsupported controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
