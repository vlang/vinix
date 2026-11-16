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
 mut accepted := 0; mut refused := 0
 for width in 1 .. 65 { for operation in ['ctpop', 'bitreverse', 'bswap'] {
  if operation == 'bswap' && width % 16 != 0 { continue }
  mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }; sign := u64(1) << u32(width - 1)
  mut text := strings.new_builder(16384)
  text.write_string('target datalayout = "e-p:64:64"\n declare i${width} @llvm.${operation}.i${width}(i${width})\n')
  text.write_string('define void @reference(ptr %in, ptr %unused, ptr %out) { %a = load i${width}, ptr %in, align 1\n %r = call i${width} @llvm.${operation}.i${width}(i${width} %a)\n %wide = ${if width == 64 { 'or i64 %r, 0' } else { 'zext i' + width.str() + ' %r to i64' }}\n store i64 %wide, ptr %out, align 1\n ret void }\n')
  for mode in 0 .. 6 {
   text.write_string('define void @test_${mode}(i${width} %a, ptr %out) { store i8 17, ptr %out\n')
   if mode == 5 { text.write_string('%next = add nuw i${width} %a, 1\n') }
   text.write_string('%r = call i${width} @llvm.${operation}.i${width}(i${width} ${if mode in [2, 3, 4] { 'poison' } else if mode == 5 { '%next' } else { '%a' }})\n')
   text.write_string(match mode {
    1 { '%idx = and i${width} %r, ${if mask < 63 { mask } else { u64(63) }}\n' }
    3 { '%idx = freeze i${width} %r\n' }
    4 { '%idx = select i1 false, i${width} %r, i${width} 0\n' }
    else { '%idx = or i${width} %r, 0\n' }
   })
   text.write_string('%p = getelementptr i8, ptr %out, i${width} %idx\n store i8 42, ptr %p\n ret void }\n')
  }
  for depth in [31, 32] {
   text.write_string('define void @depth_${depth}(i${width} %a, ptr %out) {\n')
   for i in 0 .. depth { text.write_string('%n${i} = call i${width} @llvm.${operation}.i${width}(i${width} ${if i == 0 { '%a' } else { '%n' + (i - 1).str() }})\n %p${i} = getelementptr i8, ptr %out, i${width} %n${i}\n') }
   text.write_string('ret void }\n')
  }
  dir := root + '/${operation}-i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
  mut candidates := [u64(0), 1, 2, 3, 7, 15, 31, 63, 64, u64(width - 1), u64(width), mask, sign, sign - 1, sign + 1]
  for sample in 0 .. 256 { mut x := u64(sample) + u64(0x9e3779b97f4a7c15); x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9); x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb); candidates << (x ^ (x >> 31)) }
  for mode in 0 .. 6 {
   f := fi(ir, 'test_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   for raw in candidates {
    a := raw & mask; mut input := [if mode == 5 { (a + 1) & mask } else { a }]!; mut result := [u64(0)]!
    unsafe { NativeCast(voidptr(reference))(&input[0], &input[0], &result[0]) }
    index := if mode in [3, 4] { u64(0) } else if mode == 1 { result[0] & 63 } else { result[0] }
    valid := mode != 2 && !(mode == 5 && a == mask) && index < 64 && index & sign == 0
    mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone()
    if valid { expected[0] = 17; expected[int(index)] = 42 }
    av := [raw | ~mask]; mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }; untouched(actual)
    for prepared in [false, true] {
     for j in 0 .. actual.len { actual[j] = 0xcc }
     if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
     assert actual == expected, '${operation} ${width} ${mode} ${a}'
    }
    if valid { accepted++ } else { refused++ }
    rows.writeln('${operation} ${width} ${mode} ${a} ${index} ${valid} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bindings.free() }
   }
   plan.free()
  }
  depth := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_31'))!; depth.free()
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_32')) { panic('cached intrinsic depth') }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free(); candidates.free() }
 } }
 assert accepted + refused == 214632
 line := 'AIR-BIT-INTRINSIC-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals, 132 overloads, six patterns, cached depth boundaries and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
