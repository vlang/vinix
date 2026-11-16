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

fn untouched(data []u8) { for b in data { assert b == 0xcc } }

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

fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }

fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(32768)
 text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %v, i32 %s, i1 %c, ptr %out)'
 kinds := ['root_before', 'root_after', 'cold_bad', 'cold_good', 'load', 'phi', 'undef', 'invalid_ignored', 'arithmetic', 'loaded', 'nested', 'binding']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'phi' { text.write_string('br label %join\n join: %selector = phi i32 [0, %entry]\n') }
  if kind == 'load' { text.write_string('%selector = load i32, ptr %out, align 1\n') }
  if kind == 'invalid_ignored' { text.write_string('%bad = udiv i32 1, 0\n %selector = select i1 false, i32 %bad, i32 0\n') }
  if kind == 'arithmetic' { text.write_string('%vec = add <3 x i32> %v, zeroinitializer\n') }
  if kind == 'loaded' { text.write_string('%vec = load <3 x i32>, ptr %out, align 1\n') }
  source := if kind in ['arithmetic', 'loaded'] { '%vec' } else { '%v' }
  selector := if kind in ['load', 'phi', 'invalid_ignored'] { '%selector' } else if kind == 'undef' { 'undef' } else if kind in ['root_before', 'root_after', 'cold_bad', 'cold_good'] { '3' } else { '%s' }
  text.write_string('%r = extractelement <3 x i32> ${source}, i32 ${selector}\n')
  if kind == 'root_before' { text.write_string('%badp = getelementptr i8, ptr %out, i32 %r\n') }
  if kind in ['root_before', 'root_after', 'cold_good'] { text.write_string('%fixed = freeze i32 %r\n') }
  if kind == 'nested' { text.write_string('%nested = extractelement <3 x i32> %v, i32 %r\n') }
  value := if kind in ['root_before', 'root_after', 'cold_good'] { '%fixed' } else if kind == 'nested' { '%nested' } else { '%r' }
  text.write_string('%idx = zext i32 ${value} to i64\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%badp = getelementptr i8, ptr %out, i32 %r\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 for over in [false, true] {
  n := if over { 30 } else { 29 }
  text.write_string('define void @depth_${over}${args} {\n')
  for i in 0 .. n { prev := if i == 0 { '%s' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %s${i}\n') }
  text.write_string('%r = extractelement <3 x i32> %v, i32 %s${n - 1}\n %idx = zext i32 %r to i64\n %p = getelementptr i8, ptr %out, i64 %idx\n ret void }\n')
  text.write_string('define void @nodes_${over}${args} {\n')
  for i in 0 .. 128 { text.write_string('%r${i} = extractelement <3 x i32> %v, i32 %s\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') }
  // One shared selector + 128 extracts + 127/128 binary nodes = 256/257.
  for i in 0 .. if over { 128 } else { 127 } { text.write_string('%q${i} = or i32 %r${i}, %s\n %t${i} = getelementptr i8, ptr %out, i32 %q${i}\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['depth', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over; plan.free() } else { assert over, '${name}: ${err}' }
  total++
 } }
 for kind in kinds {
  f := fi(ir, kind)
  mut actual := []u8{len: 64, init: 0xcc}; words := [u64(2), 0, 1]; sv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: words}, airbitcode.IRMemoryBinding{values: sv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  unsupported := kind in ['load', 'phi', 'undef', 'arithmetic', 'loaded']
  if unsupported {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported lane dependency: ' + kind) }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported lane ran') }; untouched(actual)
   total++
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   if kind == 'nested' {
    for selector in 0 .. 5 {
     bindings[1] = airbitcode.IRMemoryBinding{values: [u64(selector)]}
     for j in 0 .. actual.len { actual[j] = 0xcc }
     valid := selector < 3
     mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(words[int(words[selector])])] = 42 }
     check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; total++; unsafe { expected.free() }
    }
   } else if kind == 'binding' {
    for length in [0, 2, 4] {
     bindings[0] = airbitcode.IRMemoryBinding{values: []u64{len: length}}
     expected := actual.clone(); check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, false)!; total++; unsafe { expected.free() }
    }
   } else {
    valid := kind == 'cold_good'; mut expected := actual.clone(); if valid { expected[0] = 17 }
    check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; total++; unsafe { expected.free() }
   }
   plan.free()
  }
  unsafe { actual.free(); words.free(); sv.free(); cv.free(); bindings.free() }
 }
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}

fn main() {
 assert os.args.len == 3
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0
 for width in 1 .. 65 {
  lane_mask := mask(width); wide := if width == 64 { 'or i64 %value, 0' } else { 'zext i${width} %value to i64' }
  mut text := strings.new_builder(262144); text.write_string('target datalayout = "e-p:64:64"\n')
  for count in [1, 2, 3, 16] {
   vector := '<${count} x i${width}>'
   text.write_string('define void @ref_${count}(ptr %in, ptr %selector, ptr %out) {\n')
   for lane in 0 .. count {
    text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n')
    value := if width == 64 { '%w' + lane.str() } else { '%t' + lane.str() }
    if width != 64 { text.write_string('%t${lane} = trunc i64 %w${lane} to i${width}\n') }
    text.write_string('%v${lane} = insertelement ${vector} ${if lane == 0 { 'zeroinitializer' } else { '%v' + (lane - 1).str() }}, i${width} ${value}, i32 ${lane}\n')
   }
   text.write_string('%s = load i64, ptr %selector, align 1\n %value = extractelement ${vector} %v${count - 1}, i64 %s\n %wide = ${wide}\n store i64 %wide, ptr %out, align 1\n ret void }\n')
   for selector_bits in [1, 2, 8, 16, 32, 64] { for mode in 0 .. 12 {
    typ := 'i${selector_bits}'
    text.write_string('define void @test_${count}_${selector_bits}_${mode}(${vector} %v, ${typ} %s, i1 %c, ptr %out) { store i8 17, ptr %out\n')
    text.write_string(match mode {
     1 { '%j = add ${typ} %s, 1\n' }
     2 { '%j = xor ${typ} %s, 1\n' }
     3 { '%j = select i1 %c, ${typ} %s, ${typ} 0\n' }
     4 { '%j = freeze ${typ} poison\n' }
     10 { '%j = freeze ${typ} undef\n' }
     11 { '%j = add nuw ${typ} %s, 1\n' }
     else { '' }
    })
    selector := if mode in [1, 2, 3, 4, 10, 11] { '%j' } else if mode == 5 { 'poison' } else if mode == 8 { if u64(count) <= mask(selector_bits) { count.str() } else { 'poison' } } else if mode == 9 { '0' } else { '%s' }
    text.write_string('%r = extractelement ${vector} %v, ${typ} ${selector}\n')
    if mode in [6, 11] { text.write_string('%value = freeze i${width} %r\n') }
    else if mode == 7 { text.write_string('%value = select i1 %c, i${width} %r, i${width} 0\n') }
    else { text.write_string('%value = or i${width} %r, 0\n') }
    if mode % 3 == 0 { text.write_string('%p = getelementptr i8, ptr %out, i${width} %value\n') }
    else if mode % 3 == 1 {
     text.write_string('%limited = and i${width} %value, ${lane_mask & 63}\n %idx = ${if width == 64 { 'or i64 %limited, 0' } else { 'zext i${width} %limited to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n')
    } else { text.write_string('%idx = ${wide}\n %p = getelementptr i8, ptr %out, i64 %idx\n') }
    text.write_string('store i8 42, ptr %p\n ret void }\n')
   } }
  }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  for count in [1, 2, 3, 16] {
   reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + count.str()).str); assert reference != 0
   for selector_bits in [1, 2, 8, 16, 32, 64] { for mode in 0 .. 12 {
    f := fi(ir, 'test_${count}_${selector_bits}_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
    sm := mask(selector_bits)
    for condition in [false, true] { for seed in 0 .. 4 {
     mut words := []u64{len: count}; mut noisy := []u64{len: count}
     for lane in 0 .. count { words[lane] = (if seed == 3 { lane_mask - u64(lane) } else { u64(lane * 13 + seed * 17) }) & lane_mask; noisy[lane] = words[lane] | ~lane_mask }
     mut candidates := []u64{cap: 24}; for j in 0 .. 18 { candidates << u64(j) }; candidates << [u64(63), u64(64), sm, u64(1) << u32(selector_bits - 1), ~u64(0)]
     for raw in candidates {
      s := raw & sm
      selector := match mode { 1, 11 { (s + 1) & sm } 2 { s ^ 1 } 3 { if condition { s } else { u64(0) } } 4, 9, 10 { u64(0) } 8 { u64(count) } else { s } }
      mut poison := mode == 5 || selector >= u64(count) || (mode == 11 && s == sm)
      safe := [if poison { u64(0) } else { selector }]!
      mut result := [u64(0)]!
      unsafe { NativeCast(voidptr(reference))(words.data, &safe[0], &result[0]) }
      assert result[0] == words[int(safe[0])]
      mut value := result[0]
      if mode in [6, 11] && poison { value = 0; poison = false }
      if mode == 7 && !condition { value = 0; poison = false }
      index := if mode % 3 == 1 { value & 63 } else { value }
      valid := !poison && index < 64 && (mode % 3 != 0 || index & (u64(1) << u32(width - 1)) == 0)
      mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
      sv := [s | ~sm]; cv := [u64(condition) | ~u64(1)]
      mut bindings := [airbitcode.IRMemoryBinding{values: noisy}, airbitcode.IRMemoryBinding{values: sv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
      check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
      if valid { accepted++ } else { refused++ }; rows.writeln('${width} ${count} ${selector_bits} ${mode} ${condition} ${seed} ${s} ${selector} ${index} ${valid} PASS')!
      unsafe { actual.free(); expected.free(); sv.free(); cv.free(); bindings.free() }
     }
     unsafe { words.free(); noisy.free(); candidates.free() }
    } }; plan.free()
   } }
  }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 control_count := controls(os.args[1], root)!
 assert accepted + refused == 3391488
 line := 'AIR-DYNAMIC-LANE-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals, 64 lane widths, 6 selector widths, 4 vector lengths, 12 patterns, ${control_count} depth/node/root/cold/binding/dependency controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
