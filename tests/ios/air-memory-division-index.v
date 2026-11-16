// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Reference operations are guarded and defined. Flagged native targets
// execute only after the independent reference accepts their result/address.
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

// The oracle divides widened i128 operands with a selected nonzero divisor.
// Original-width UB and exactness are tagged separately. Native memory targets
// run only for defined, nonpoison, bounded addresses.
fn main() {
 assert os.args.len == 3
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 forms := ['udiv', 'udiv exact', 'sdiv', 'sdiv exact', 'urem', 'srem']
 mut exact := 0; mut refused := 0; mut poisoned := 0; mut undefined := 0
 for width in 1 .. 65 {
  mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }; sign := u64(1) << u32(width - 1)
  mut text := strings.new_builder(32768); text.write_string('target datalayout = "e-p:64:64"\n')
  for i, form in forms {
   op := form.all_before(' '); signed := op.starts_with('s'); cast := if signed { 'sext' } else { 'zext' }
   text.write_string('define void @test_${i}(i${width} %a, i${width} %b, ptr %out) { store i8 17, ptr %out\n %idx = ${form} i${width} %a, %b\n %p = getelementptr i8, ptr %out, i${width} %idx\n store i8 42, ptr %p\n ret void }\n')
   text.write_string('define void @native_${i}(ptr %ip, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n call void @test_${i}(i${width} %a, i${width} %b, ptr %out)\n ret void }\n')
   text.write_string('define void @ref_${i}(ptr %ip, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n %nonzero = icmp ne i${width} %b, 0\n %safe = select i1 %nonzero, i${width} %b, i${width} 1\n %wa = ${cast} i${width} %a to i128\n %wb = ${cast} i${width} %safe to i128\n %wide = ${op} i128 %wa, %wb\n %raw = trunc i128 %wide to i${width}\n')
   if signed { text.write_string('%minimum = icmp eq i${width} %a, ${sign}\n %negative_one = icmp eq i${width} %b, ${mask}\n %overflow = and i1 %minimum, %negative_one\n %nooverflow = xor i1 %overflow, true\n %defined = and i1 %nonzero, %nooverflow\n') } else { text.write_string('%defined = and i1 %nonzero, true\n') }
   if form.contains('exact') { text.write_string('%remainder = ${if signed { 'srem' } else { 'urem' }} i128 %wa, %wb\n %promise = icmp eq i128 %remainder, 0\n') }
   text.write_string('%nonnegative = icmp sge i${width} %raw, 0\n %bounded = icmp ule i${width} %raw, ${if mask < 63 { mask } else { u64(63) }}\n %valid = and i1 %nonnegative, %bounded\n %tag0 = select i1 %valid, i8 1, i8 0\n %tag1 = select i1 ${if form.contains('exact') { '%promise' } else { 'true' }}, i8 %tag0, i8 2\n %tag = select i1 %defined, i8 %tag1, i8 3\n store i8 %tag, ptr %out\n ret void }\n')
  }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  candidates := [u64(0), 1, 2, 3, 7, 15, 31, 63, 64, u64(width - 1), u64(width), mask, sign, sign - 1, sign + 1]!
  for i, form in forms {
   f := fi(ir, 'test_${i}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   address := C.LLVMGetFunctionAddress(native.engine, ('native_${i}').str); reference := C.LLVMGetFunctionAddress(native.engine, ('ref_${i}').str); assert address != 0 && reference != 0
   for a in candidates { for b in candidates {
    mut words := [a & mask, b & mask]!; mut tag := [u8(0)]!; unsafe { NativeCast(voidptr(reference))(&words[0], &words[0], &tag[0]) }
    valid := tag[0] == 1
    mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); av := [a | ~mask]; bv := [b | ~mask]
    mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid; if tag[0] == 2 { assert err.msg().contains('poison expression') }; if tag[0] == 3 { assert err.msg().contains('undefined division/remainder') } }; untouched(actual)
    if valid { unsafe { NativeCast(voidptr(address))(&words[0], &words[0], expected.data) } }
    for prepared in [false, true] {
     for j in 0 .. actual.len { actual[j] = 0xcc }
     if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
     if valid { assert actual == expected, '${width} ${form} ${a} ${b}' } else { untouched(actual) }
    }
    if valid { exact++ } else { refused++; if tag[0] == 2 { poisoned++ }; if tag[0] == 3 { undefined++ } }
    rows.writeln('${width} ${i} ${a & mask} ${b & mask} ${tag[0]} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bv.free(); bindings.free() }
   } }
   plan.free()
  }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 assert exact + refused == 86400
 line := 'AIR-DIVISION-INDEX: ${exact} native exact cases, ${refused} prewrite refusals (${poisoned} exact poison, ${undefined} undefined arithmetic), i1..i64, four operators and six forms, ordinary/prepared/validation APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
