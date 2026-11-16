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

fn select_controls(assembler string, root string) ! {
 mut source := strings.new_builder(8192); source.write_string('target datalayout = "e-p:64:64"\n')
 fixtures := {
  'shared': '%bad = add nuw i64 %a, 1\n %old = getelementptr i8, ptr %out, i64 %bad\n %idx = select i1 false, i64 %bad, i64 0'
  'dead_div': '%bad = udiv i64 0, %a\n %idx = select i1 false, i64 %bad, i64 0'
  'div_poison': '%bad = udiv i64 poison, 1\n %idx = select i1 false, i64 %bad, i64 0'
  'propagate': '%bad = add nuw i64 %a, 1\n %eq = icmp eq i64 %bad, 0\n %cast = zext i1 %eq to i64\n %idx = select i1 false, i64 %cast, i64 0'
  'condition_poison': '%bad = add nuw i64 %a, 1\n %eq = icmp eq i64 %bad, 0\n %idx = select i1 %eq, i64 %a, i64 0'
  'root_poison': '%idx = add i64 %a, poison'
 }
 for name, body in fixtures { source.write_string('define void @${name}(i64 %a, ptr %out) { store i8 17, ptr %out\n ${body}\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n') }
 source.write_string('define void @cold_select(i64 %a, ptr %out) { store i8 17, ptr %out\n br i1 true, label %exit, label %cold\ncold: %idx = select i1 true, i64 poison, i64 %a\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n br label %exit\nexit: ret void }\n')
 for depth in [31, 32] {
  source.write_string('define void @depth_${depth}(i1 %a, ptr %out) {\n')
  for i in 0 .. depth { source.write_string('%n${i} = select i1 ${if i == 0 { '%a' } else { '%n' + (i - 1).str() }}, i1 true, i1 false\n %p${i} = getelementptr i8, ptr %out, i1 %n${i}\n') }
  source.write_string('ret void }\n')
 }
 data := assemble(assembler, root, source.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!
 defer { p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() } }
 mut checks := 0
 for name in ['shared', 'dead_div', 'div_poison', 'propagate', 'condition_poison', 'root_poison', 'cold_select'] {
  f := fi(ir, name); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
  for a in [u64(0), 63, 64, ~u64(0)]! {
   valid := match name { 'shared' { a < 64 } 'dead_div' { a != 0 } 'propagate' { true } 'condition_poison' { a != ~u64(0) } else { false } }
   av := [a]; mut actual := []u8{len: 64, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
   if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }; untouched(actual)
   for prepared in [false, true] {
    for j in 0 .. actual.len { actual[j] = 0xcc }
    if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
    if valid { assert actual[0] == 42; for j in 1 .. actual.len { assert actual[j] == 0xcc } } else { untouched(actual) }
   }
   checks++; unsafe { av.free(); actual.free(); bindings.free() }
  }
  plan.free()
 }
 accepted := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_31'))!; accepted.free()
 if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_32')) { panic('select cached-condition depth') }
 assert checks == 28
 os.write_file(root + '/result.txt', 'AIR-SELECT-CONTROLS: 28 shared-root/one-past/bounds/cold/alias-independent poison and immediate-error cases, exact cached-condition depth boundary PASS\n')!
}
// Defined oracle values plus explicit poison tags avoid observing native poison.
fn main() {
 assert os.args.len == 3
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut exact := 0; mut refused := 0; mut poisoned := 0
 for width in 1 .. 65 {
  mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }; sign := u64(1) << u32(width - 1)
  mut text := strings.new_builder(65536); text.write_string('target datalayout = "e-p:64:64"\n')
  for mode in 0 .. 8 {
   text.write_string('define void @test_${mode}(i${width} %a, i${width} %b, i1 %cond, ptr %out) { store i8 17, ptr %out\n')
   match mode {
    0 { text.write_string('%idx = select i1 %cond, i${width} %a, i${width} %b\n') }
    1 { text.write_string('%idx = select i1 %cond, i${width} poison, i${width} %b\n') }
    2 { text.write_string('%idx = select i1 %cond, i${width} %a, i${width} poison\n') }
    3 { text.write_string('%idx = select i1 poison, i${width} %a, i${width} %b\n') }
    4, 7 { text.write_string('%bad = add nuw i${width} %a, %b\n %left = and i${width} %bad, ${if mode == 7 && mask > 63 { u64(63) } else { mask }}\n %idx = select i1 %cond, i${width} %left, i${width} %b\n') }
    5 { text.write_string('%c = icmp samesign ult i${width} %a, %b\n %idx = select i1 %c, i${width} %a, i${width} %b\n') }
    else { text.write_string('%inner = select i1 %cond, i${width} poison, i${width} %a\n %idx = select i1 %cond, i${width} %b, i${width} %inner\n') }
   }
   text.write_string('%p = getelementptr i8, ptr %out, i${width} %idx\n store i8 42, ptr %p\n ret void }\n')
   text.write_string('define void @native_${mode}(ptr %ip, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %cp = getelementptr i8, ptr %ip, i64 16\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n %cond = load i1, ptr %cp, align 1\n call void @test_${mode}(i${width} %a, i${width} %b, i1 %cond, ptr %out)\n ret void }\n')
   text.write_string('define void @ref_${mode}(ptr %ip, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %cp = getelementptr i8, ptr %ip, i64 16\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n %cond = load i1, ptr %cp, align 1\n')
   mut poison := 'false'
   match mode {
    0 { text.write_string('%raw = select i1 %cond, i${width} %a, i${width} %b\n') }
    1 { text.write_string('%raw = select i1 %cond, i${width} 0, i${width} %b\n'); poison = '%cond' }
    2 { text.write_string('%raw = select i1 %cond, i${width} %a, i${width} 0\n %pflag = xor i1 %cond, true\n'); poison = '%pflag' }
    3 { text.write_string('%raw = add i${width} %a, 0\n'); poison = 'true' }
    4, 7 { text.write_string('%wa = zext i${width} %a to i128\n %wb = zext i${width} %b to i128\n %sum = add i128 %wa, %wb\n %over = icmp ugt i128 %sum, ${mask}\n %low = trunc i128 %sum to i${width}\n %left = and i${width} %low, ${if mode == 7 && mask > 63 { u64(63) } else { mask }}\n %raw = select i1 %cond, i${width} %left, i${width} %b\n %pflag = and i1 %cond, %over\n'); poison = '%pflag' }
    5 { text.write_string('%c = icmp ult i${width} %a, %b\n %raw = select i1 %c, i${width} %a, i${width} %b\n %different = xor i${width} %a, %b\n %signbits = and i${width} %different, ${sign}\n %pflag = icmp ne i${width} %signbits, 0\n'); poison = '%pflag' }
    else { text.write_string('%raw = select i1 %cond, i${width} %b, i${width} %a\n') }
   }
   text.write_string('%nonnegative = icmp sge i${width} %raw, 0\n %bounded = icmp ule i${width} %raw, ${if mask < 63 { mask } else { u64(63) }}\n %valid = and i1 %nonnegative, %bounded\n %tag0 = select i1 %valid, i8 1, i8 0\n %tag = select i1 ${poison}, i8 2, i8 %tag0\n store i8 %tag, ptr %out\n ret void }\n')
  }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  candidates := [u64(0), 1, 2, 3, 7, 15, 31, 63, 64, u64(width - 1), u64(width), mask, sign, sign - 1, sign + 1]!
  for mode in 0 .. 8 {
   f := fi(ir, 'test_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   address := C.LLVMGetFunctionAddress(native.engine, ('native_${mode}').str); reference := C.LLVMGetFunctionAddress(native.engine, ('ref_${mode}').str); assert address != 0 && reference != 0
   for a in candidates { for b in candidates { for cond in [u64(0), 1]! {
    mut words := [a & mask, b & mask, cond]!; mut tag := [u8(0)]!; unsafe { NativeCast(voidptr(reference))(&words[0], &words[0], &tag[0]) }
    valid := tag[0] == 1
    mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); av := [a | ~mask]; bv := [b | ~mask]; cv := [cond | ~u64(1)]
    mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid; if tag[0] == 2 { assert err.msg().contains('poison expression') } }; untouched(actual)
    if valid { unsafe { NativeCast(voidptr(address))(&words[0], &words[0], expected.data) } }
    for prepared in [false, true] {
     for j in 0 .. actual.len { actual[j] = 0xcc }
     if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
     if valid { assert actual == expected, '${width} ${mode} ${a} ${b} ${cond}' } else { untouched(actual) }
    }
    if valid { exact++ } else { refused++; if tag[0] == 2 { poisoned++ } }
    rows.writeln('${width} ${mode} ${a & mask} ${b & mask} ${cond} ${tag[0]} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bv.free(); cv.free(); bindings.free() }
   } } }
   plan.free()
  }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 assert exact + refused == 230400
 select_controls(os.args[1], root + '/controls')!
 line := 'AIR-SELECT-INDEX: ${exact} native exact cases, ${refused} prewrite refusals (${poisoned} selected/condition poison), i1..i64, eight select patterns, both conditions, ordinary/prepared/validation APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
