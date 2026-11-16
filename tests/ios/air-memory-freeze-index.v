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

fn freeze_controls(assembler string, root string) ! {
 mut source := strings.new_builder(8192); source.write_string('target datalayout = "e-p:64:64"\n')
 fixtures := {
  'shared': '%bad = add nuw i64 %a, 1\n %old = getelementptr i8, ptr %out, i64 %bad\n %idx = freeze i64 %bad'
  'dead_div': '%bad = udiv i64 0, %a\n %idx = freeze i64 %bad'
  'div_poison': '%bad = udiv i64 poison, 1\n %idx = freeze i64 %bad'
  'onepast': '%idx = freeze i64 %a'
 }
 for name, body in fixtures { source.write_string('define void @${name}(i64 %a, ptr %out) { store i8 17, ptr %out\n ${body}\n %p = getelementptr i8, ptr %out, i64 %idx\n ret void }\n') }
 source.write_string('define void @cold(i64 %a, ptr %out) { store i8 17, ptr %out\n br i1 true, label %exit, label %cold\ncold: %idx = freeze i64 poison\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n br label %exit\nexit: ret void }\n')
 for name, body in {
  'shared_undef': '%f = freeze i64 undef\n %old = getelementptr i8, ptr %out, i64 %f\n %idx = add i64 %a, undef'
  'nested_undef': '%bad = add i64 %a, undef\n %idx = freeze i64 %bad'
  'unselected_undef': '%f = freeze i64 undef\n %old = getelementptr i8, ptr %out, i64 %f\n %idx = select i1 false, i64 undef, i64 0'
 } { source.write_string('define void @${name}(i64 %a, ptr %out) { ${body}\n %p = getelementptr i8, ptr %out, i64 %idx\n ret void }\n') }
 for depth in [31, 32] {
  source.write_string('define void @depth_${depth}(i64 %a, ptr %out) {\n')
  for i in 0 .. depth { source.write_string('%n${i} = freeze i64 ${if i == 0 { 'undef' } else { '%n' + (i - 1).str() }}\n %p${i} = getelementptr i8, ptr %out, i64 %n${i}\n') }
  source.write_string('ret void }\n')
 }
 data := assemble(assembler, root, source.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!
 defer { p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() } }
 mut checks := 0
 for name in ['shared', 'dead_div', 'div_poison', 'onepast', 'cold'] {
  f := fi(ir, name); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
  for a in [u64(0), 63, 64, 65, ~u64(0)]! {
   valid := match name { 'shared' { a <= 63 } 'dead_div' { a != 0 } 'onepast' { a <= 64 } 'cold' { true } else { false } }
   av := [a]; mut actual := []u8{len: 64, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
   if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }; untouched(actual)
   for prepared in [false, true] {
    for j in 0 .. actual.len { actual[j] = 0xcc }
    if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
    if valid { assert actual[0] == 17; for j in 1 .. actual.len { assert actual[j] == 0xcc } } else { untouched(actual) }
   }
   checks++; unsafe { av.free(); actual.free(); bindings.free() }
  }
  plan.free()
 }
 for name in ['shared_undef', 'nested_undef', 'unselected_undef'] {
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, name)) { panic('undef escaped direct freeze: ' + name) }
 }
 accepted := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_31'))!; accepted.free()
 if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'depth_32')) { panic('freeze cached depth') }
 assert checks == 25
 os.write_file(root + '/result.txt', 'AIR-FREEZE-CONTROLS: 25 root/bounds/cold/immediate-error cases, three undef-cache/nested/unchosen refusals, exact cached depth boundary PASS\n')!
}

// Reference freeze choices are explicit zero. Native arbitrary choices are
// checked only by choice-independent properties, never equated with zero.
fn main() {
 assert os.args.len == 3
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut exact := 0; mut choices := 0; mut refused := 0; mut properties := 0
 for width in 1 .. 65 {
  mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }; sign := u64(1) << u32(width - 1)
  mut text := strings.new_builder(65536); text.write_string('target datalayout = "e-p:64:64"\n')
  for mode in 0 .. 9 {
   text.write_string('define void @test_${mode}(i${width} %a, i${width} %b, i1 %cond, ptr %out) { store i8 17, ptr %out\n')
   match mode {
    0 { text.write_string('%idx = freeze i${width} %a\n') }
    1, 2 { text.write_string('%idx = freeze i${width} ${if mode == 1 { 'poison' } else { 'undef' }}\n') }
    3 { text.write_string('%raw = add nuw i${width} %a, %b\n %idx = freeze i${width} %raw\n') }
    4 { text.write_string('%raw = shl i${width} %a, %b\n %idx = freeze i${width} %raw\n') }
    5 { text.write_string('%raw = icmp samesign ult i${width} %a, %b\n %f = freeze i1 %raw\n %idx = ${if width == 1 { 'or i1 %f, false' } else { 'zext i1 %f to i' + width.str() }}\n') }
    6 { text.write_string('%raw = select i1 poison, i${width} %a, i${width} %b\n %idx = freeze i${width} %raw\n') }
    7 { text.write_string('%raw = add nuw i${width} %a, %b\n %f = freeze i${width} %raw\n %next = add i${width} %f, %b\n %idx = freeze i${width} %next\n') }
    else { text.write_string('%raw = select i1 %cond, i${width} %a, i${width} poison\n %idx = freeze i${width} %raw\n') }
   }
   ending := '%p = getelementptr i8, ptr %out, i${width} %idx\n store i8 42, ptr %p\n %low = ${if width < 8 { 'zext i' + width.str() + ' %idx to i8' } else if width > 8 { 'trunc i' + width.str() + ' %idx to i8' } else { 'or i8 %idx, 0' }}\n store i8 %low, ptr %out\n ret void }\n'
   text.write_string(ending)
   text.write_string('define i${width} @policy_${mode}(i${width} %a, i${width} %b, i1 %cond, ptr %tag) {\n')
   mut poison := 'false'
   match mode {
    0 { text.write_string('%idx = add i${width} %a, 0\n') }
    1, 2, 6 { text.write_string('%idx = add i${width} 0, 0\n'); poison = 'true' }
    3, 7 {
     text.write_string('%wa = zext i${width} %a to i128\n %wb = zext i${width} %b to i128\n %sum = add i128 %wa, %wb\n %over = icmp ugt i128 %sum, ${mask}\n %low = trunc i128 %sum to i${width}\n %f = select i1 %over, i${width} 0, i${width} %low\n %idx = add i${width} %f, ${if mode == 7 { '%b' } else { '0' }}\n'); poison = '%over'
    }
    4 { text.write_string('%over = icmp uge i${width} %b, ${if u64(width) <= mask { width.str() } else { '0' }}\n %amount = select i1 %over, i${width} 0, i${width} %b\n %shifted = shl i${width} %a, %amount\n %idx = select i1 %over, i${width} 0, i${width} %shifted\n'); poison = '%over' }
    5 { text.write_string('%different = xor i${width} %a, %b\n %signbits = and i${width} %different, ${sign}\n %over = icmp ne i${width} %signbits, 0\n %raw = icmp ult i${width} %a, %b\n %f = select i1 %over, i1 false, i1 %raw\n %idx = ${if width == 1 { 'or i1 %f, false' } else { 'zext i1 %f to i' + width.str() }}\n'); poison = '%over' }
    else { text.write_string('%idx = select i1 %cond, i${width} %a, i${width} 0\n %over = xor i1 %cond, true\n'); poison = '%over' }
   }
   text.write_string('%nonnegative = icmp sge i${width} %idx, 0\n %bounded = icmp ule i${width} %idx, ${if mask < 63 { mask } else { u64(63) }}\n %valid = and i1 %nonnegative, %bounded\n %v = zext i1 %valid to i8\n store i8 %v, ptr %tag\n %tp = getelementptr i8, ptr %tag, i64 1\n %p = zext i1 ${poison} to i8\n store i8 %p, ptr %tp\n ret i${width} %idx }\n')
   for name in ['native', 'reference'] {
    text.write_string('define void @${name}_${mode}(ptr %ip, ptr %tag, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %cp = getelementptr i8, ptr %ip, i64 16\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n %cond = load i1, ptr %cp, align 1\n')
    if name == 'native' { text.write_string('call void @test_${mode}(i${width} %a, i${width} %b, i1 %cond, ptr %out)\n ret void }\n') } else {
     text.write_string('%idx = call i${width} @policy_${mode}(i${width} %a, i${width} %b, i1 %cond, ptr %tag)\n %valid = load i8, ptr %tag\n %ok = icmp eq i8 %valid, 1\n br i1 %ok, label %write, label %exit\nwrite: store i8 17, ptr %out\n')
     text.write_string(ending.replace('ret void }', 'br label %exit\nexit: ret void }'))
    }
   }
  }
  for state in ['poison', 'undef'] { text.write_string('define void @property_${state}(ptr %unused, ptr %unused2, ptr %out) { %f = freeze i${width} ${state}\n %x = xor i${width} %f, %f\n %z = ${if width == 64 { 'or i64 %x, 0' } else { 'zext i' + width.str() + ' %x to i64' }}\n store i64 %z, ptr %out, align 1\n ret void }\n') }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  candidates := [u64(0), 1, 2, 3, 7, 15, 31, 63, 64, u64(width - 1), u64(width), mask, sign, sign - 1, sign + 1]!
  for mode in 0 .. 9 {
   f := fi(ir, 'test_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   address := C.LLVMGetFunctionAddress(native.engine, ('native_${mode}').str); reference := C.LLVMGetFunctionAddress(native.engine, ('reference_${mode}').str); assert address != 0 && reference != 0
   for a in candidates { for b in candidates { for cond in [u64(0), 1]! {
    mut words := [a & mask, b & mask, cond]!; mut tag := [u8(0), 0]!; mut expected := []u8{len: 64, init: 0xcc}
    unsafe { NativeCast(voidptr(reference))(&words[0], &tag[0], expected.data) }
    valid := tag[0] == 1
    mut actual := []u8{len: 64, init: 0xcc}; av := [a | ~mask]; bv := [b | ~mask]; cv := [cond | ~u64(1)]
    mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
    if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }; untouched(actual)
    if valid && tag[1] == 0 {
     unsafe { NativeCast(voidptr(address))(&words[0], &tag[0], actual.data) }
     assert actual == expected
    }
    for prepared in [false, true] {
     for j in 0 .. actual.len { actual[j] = 0xcc }
     if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
     assert actual == expected, '${width} ${mode} ${a} ${b} ${cond} ${tag[0]} ${tag[1]}'
    }
    if valid { if tag[1] == 0 { exact++ } else { choices++ } } else { refused++ }
    rows.writeln('${width} ${mode} ${a & mask} ${b & mask} ${cond} ${tag[0]} ${tag[1]} PASS')!
    unsafe { actual.free(); expected.free(); av.free(); bv.free(); cv.free(); bindings.free() }
   } } }
   plan.free()
  }
  for state in ['poison', 'undef'] {
   address := C.LLVMGetFunctionAddress(native.engine, ('property_${state}').str); assert address != 0
   mut actual := [u8(0xcc), 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc]!
   unsafe { NativeCast(voidptr(address))(&actual[0], &actual[0], &actual[0]) }
   for byte in actual { assert byte == 0 }; properties++
  }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 assert exact + choices + refused == 259200 && properties == 128
 freeze_controls(os.args[1], root + '/controls')!
 line := 'AIR-FREEZE-INDEX: ${exact} native exact outputs, ${choices} explicit zero-choice outputs, ${refused} prewrite refusals; ${properties} native choice-independent properties; i1..i64, nine patterns, both conditions, all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
