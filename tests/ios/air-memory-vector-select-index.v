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

fn lane_state(state int, lane int) int {
 return match state { 1 { match lane % 4 { 1 { 1 } 2 { 2 } else { 0 } } } 2 { 1 } 3 { 2 } 7 { if lane % 2 == 0 { 2 } else { 1 } } else { 0 } }
}
fn lane_word(width int, state int, lane int) u64 {
 return (match state { 4 { u64(0) } 5 { u64(7) } 6 { mask(width) - u64(lane) } else { u64(lane * 7 + 1) } }) & mask(width)
}
fn literal(width int, count int, state int, safe bool) string {
 if !safe && state in [2, 3, 4] { return ['poison', 'undef', 'zeroinitializer'][state - 2] }
 mut lanes := []string{cap: count}
 for lane in 0 .. count {
  kind := lane_state(state, lane)
  value := if kind == 0 { lane_word(width, state, lane).str() } else if safe { '0' } else if kind == 1 { 'poison' } else { 'undef' }
  lanes << 'i${width} ${value}'
 }
 return '<' + lanes.join(', ') + '>'
}
fn untouched(data []u8) { for b in data { assert b == 0xcc } }
fn check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, f int, plan &airbitcode.IRPreparedMemoryFunction, mut bindings []airbitcode.IRMemoryBinding, expected []u8, valid bool) ! {
 if _ := plan.validate(bindings, plan.steps()) { assert valid } else { assert !valid }
 untouched(bindings[4].data)
 for prepared in [false, true] {
  for j in 0 .. bindings[4].data.len { bindings[4].data[j] = 0xcc }
  if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  assert bindings[4].data == expected
 }
}

fn source_expression(width int, count int, state int, mode int, safe bool) string {
 t := '<${count} x i${width}>'; l := literal(width, count, state, safe); r := literal(width, count, (state + 1) % 8, safe)
 a := if safe { literal(width, count, 0, true) } else { '%a' }; b := if safe { literal(width, count, 5, true) } else { '%b' }
 return match mode {
  0 { '%s = select i1 %c, ${t} ${l}, ${t} ${b}\n' }
  1 { '%s = select i1 %c, ${t} ${a}, ${t} ${r}\n' }
  3 { '%t = select i1 %c, ${t} ${l}, ${t} ${r}\n %s = freeze ${t} %t\n' }
  4 { '%l = freeze ${t} ${l}\n %r0 = freeze ${t} ${r}\n %s = select i1 %c, ${t} %l, ${t} %r0\n' }
  5 { if safe { '%s = select i1 %c, ${t} zeroinitializer, ${t} zeroinitializer\n' } else { '%s = select i1 poison, ${t} ${l}, ${t} ${r}\n' } }
  6 { if safe { '%t = select i1 %c, ${t} ${l}, ${t} zeroinitializer\n %s = freeze ${t} %t\n' } else { '%condition = select i1 %c, i1 true, i1 poison\n %t = select i1 %condition, ${t} ${l}, ${t} ${r}\n %s = freeze ${t} %t\n' } }
  7 { '%inv = xor i1 %c, true\n %inner = select i1 %c, ${t} ${l}, ${t} ${a}\n %s = select i1 %inv, ${t} %inner, ${t} ${r}\n' }
  8 { '%inner = select i1 %c, ${t} ${l}, ${t} ${r}\n %f = freeze ${t} %inner\n %s = select i1 %c, ${t} ${b}, ${t} %f\n' }
  9 { '%s = select i1 %c, ${t} ${l}, ${t} ${r}\n %f = freeze ${t} %s\n' }
  else { '%s = select i1 %c, ${t} ${l}, ${t} ${r}\n' }
 }
}

fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(65536); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] {
  text.write_string('define void @source_depth_${over}${args} {\n')
  n := if over { 29 } else { 28 }
  for i in 0 .. n { prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %b\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('%wide = zext i32 %v${n - 1} to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  n2 := if over { 28 } else { 27 }
  text.write_string('define void @freeze_depth_${over}${args} { %s = select i1 %c, <3 x i32> %a, <3 x i32> %b\n %v = extractelement <3 x i32> %s, i32 %j\n %p = getelementptr i8, ptr %out, i32 %v\n')
  for i in 0 .. n2 { prev := if i == 0 { '%s' } else { '%f' + (i - 1).str() }; text.write_string('%f${i} = freeze <3 x i32> ${prev}\n %v${i} = extractelement <3 x i32> %f${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('%wide = zext i32 %v${n2 - 1} to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  text.write_string('define void @selector_depth_${over}${args} { %s = select i1 %c, <3 x i32> %a, <3 x i32> %b\n')
  for i in 0 .. n2 { prev := if i == 0 { '%j' } else { '%j' + (i - 1).str() }; text.write_string('%j${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %j${i}\n') }
  text.write_string('%v = extractelement <3 x i32> %s, i32 %j${n2 - 1}\n %wide = zext i32 %v to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  text.write_string('define void @nodes_${over}${args} { %s = select i1 %c, <3 x i32> %a, <3 x i32> %b\n')
  for i in 0 .. if over { 252 } else { 251 } { text.write_string('%v${i} = extractelement <3 x i32> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['unselected_undef', 'chosen_undef', 'scalar_ignored_undef', 'freeze_selected', 'bad_selector', 'outer_freeze', 'poison_condition', 'frozen_condition', 'root_before', 'root_after', 'cold_bad', 'cold_good', 'cache_selectors', 'loaded_arm', 'arithmetic_arm', 'vector_condition', 'undef_condition', 'invalid_condition']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_arm' { text.write_string('%other = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'arithmetic_arm' { text.write_string('%other = add <3 x i32> %a, zeroinitializer\n') }
  if kind == 'frozen_condition' { text.write_string('%condition = freeze i1 undef\n') }
  if kind == 'invalid_condition' { text.write_string('%bad = udiv i1 false, false\n %inner = select i1 %bad, <3 x i32> %a, <3 x i32> %b\n') }
  left := if kind in ['chosen_undef', 'scalar_ignored_undef', 'freeze_selected', 'bad_selector', 'outer_freeze', 'cold_bad', 'cold_good'] { 'undef' } else { '%a' }
  right := if kind == 'unselected_undef' { 'undef' } else if kind in ['loaded_arm', 'arithmetic_arm'] { '%other' } else if kind == 'invalid_condition' { '%inner' } else { '%b' }
  cond := if kind in ['root_before', 'root_after', 'poison_condition'] { 'poison' } else if kind == 'frozen_condition' { '%condition' } else if kind == 'undef_condition' { 'undef' } else { 'true' }
  if kind == 'vector_condition' { text.write_string('%s = select <3 x i1> zeroinitializer, <3 x i32> %a, <3 x i32> %b\n') }
  else { text.write_string('%s = select i1 ${cond}, <3 x i32> ${left}, <3 x i32> ${right}\n') }
  if kind == 'root_before' { text.write_string('%bad = extractelement <3 x i32> %s, i32 0\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  frozen := kind in ['root_before', 'root_after', 'freeze_selected', 'bad_selector', 'outer_freeze', 'cold_good']
  if frozen { text.write_string('%f = freeze <3 x i32> %s\n') }
  selector := if kind in ['bad_selector', 'outer_freeze'] { '3' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${if frozen { '%f' } else { '%s' }}, i32 ${selector}\n')
  if kind in ['outer_freeze', 'poison_condition'] { text.write_string('%idx = freeze i32 %v\n') }
  else if kind == 'scalar_ignored_undef' { text.write_string('%idx = select i1 false, i32 %v, i32 0\n') }
  else if kind == 'cache_selectors' { text.write_string('%next = add i32 %j, 1\n %neighbor = extractelement <3 x i32> %s, i32 %next\n %idx = add i32 %v, %neighbor\n') }
  else { text.write_string('%idx = or i32 %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%bad = extractelement <3 x i32> %s, i32 0\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['source_depth', 'freeze_depth', 'selector_depth', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over; plan.free() } else { assert over, '${name}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_arm', 'arithmetic_arm', 'vector_condition', 'undef_condition'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported vector select') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported vector select ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['unselected_undef', 'freeze_selected', 'outer_freeze', 'poison_condition', 'frozen_condition', 'cold_good', 'cache_selectors']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { expected[if kind == 'unselected_undef' { 1 } else if kind == 'frozen_condition' { 4 } else if kind == 'cache_selectors' { 3 } else { 0 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'unselected_undef'); scope := bodies.scopes[f + 1]; mut selection := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code in [u64(5), 29] { selection = i; break } }
 assert selection >= 0; saved := p.instructions[selection]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[selection + 1].result_type}] {
  p.instructions[selection] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed vector select') }; total++
 }
 p.instructions[selection] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}

fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-SELECT-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0
 for width in 1 .. 65 {
  counts := if width == 32 { []int{len: 16, init: index + 1} } else { [1, 2, 3, 16] }
  wide := if width == 64 { 'or i64 %value, 0' } else { 'zext i${width} %value to i64' }
  mut text := strings.new_builder(524288); text.write_string('target datalayout = "e-p:64:64"\n')
  for count in counts { for state in 0 .. 8 { for mode in 0 .. 10 {
   vector := '<${count} x i${width}>'
   text.write_string('define void @ref_${count}_${state}_${mode}(ptr %unused, ptr %selector, ptr %out) { %j = load i64, ptr %selector, align 1\n %cp = getelementptr i64, ptr %selector, i64 1\n %raw_c = load i64, ptr %cp, align 1\n %c = trunc i64 %raw_c to i1\n')
   text.write_string(source_expression(width, count, state, mode, true))
   text.write_string('%value = extractelement ${vector} ${if mode == 9 { '%f' } else { '%s' }}, i64 %j\n %wide = ${wide}\n store i64 %wide, ptr %out, align 1\n ret void }\n')
   for selector_bits in [1, 32, 64] {
    typ := 'i${selector_bits}'
    text.write_string('define void @test_${count}_${state}_${selector_bits}_${mode}(${vector} %a, ${vector} %b, ${typ} %j, i1 %c, ptr %out) { store i8 17, ptr %out\n')
    text.write_string(source_expression(width, count, state, mode, false))
    if mode == 9 { text.write_string('%bad = extractelement ${vector} %s, ${typ} %j\n %r = extractelement ${vector} %f, ${typ} %j\n %value = select i1 %c, i${width} %r, i${width} %bad\n') }
    else { text.write_string('%r = extractelement ${vector} %s, ${typ} %j\n %value = ${if mode in [2, 5] { 'freeze i' + width.str() + ' %r' } else { 'or i' + width.str() + ' %r, 0' }}\n') }
    if mode == 0 { text.write_string('%p = getelementptr i8, ptr %out, i${width} %value\n') }
    else if mode == 1 { text.write_string('%limited = and i${width} %value, ${mask(width) & 63}\n %idx = ${if width == 64 { 'or i64 %limited, 0' } else { 'zext i${width} %limited to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n') }
    else { text.write_string('%idx = ${wide}\n %p = getelementptr i8, ptr %out, i64 %idx\n') }
    text.write_string('store i8 42, ptr %p\n ret void }\n')
   }
  } } }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  for count in counts { for state in 0 .. 8 { for mode in 0 .. 10 {
   reference := C.LLVMGetFunctionAddress(native.engine, ('ref_${count}_${state}_${mode}').str); assert reference != 0
   for selector_bits in [1, 32, 64] {
    f := fi(ir, 'test_${count}_${state}_${selector_bits}_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
    sm := mask(selector_bits); mut candidates := []u64{cap: 21}; for j in 0 .. 18 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1), ~u64(0)]
    mut av := []u64{len: count}; mut bv := []u64{len: count}; for lane in 0 .. count { av[lane] = lane_word(width, 0, lane) | ~mask(width); bv[lane] = lane_word(width, 5, lane) | ~mask(width) }
    for condition in [false, true] { for raw in candidates {
     j := raw & sm; invalid := j >= u64(count)
     chosen := match mode { 0 { if condition { state } else { 5 } } 1 { if condition { 0 } else { (state + 1) % 8 } } 7 { if condition { (state + 1) % 8 } else { 0 } } 8 { if condition { 5 } else { (state + 1) % 8 } } else { if condition { state } else { (state + 1) % 8 } } }
     safe := [if invalid { u64(0) } else { j }, u64(condition)]!; mut result := [u64(0)]!
     unsafe { NativeCast(voidptr(reference))(&safe[0], &safe[0], &result[0]) }
     special_zero := mode == 5 || (mode == 6 && !condition)
     safe_kind := lane_state(chosen, int(safe[0])); expected_word := if special_zero || safe_kind != 0 { u64(0) } else { lane_word(width, chosen, int(safe[0])) }; assert result[0] == expected_word
     kind := if invalid { 1 } else { lane_state(chosen, int(j)) }
     source_frozen := mode in [3, 4, 6, 8]
     undef := !invalid && !special_zero && !source_frozen && kind == 2
     mut poison := invalid || (!source_frozen && (special_zero || kind == 1))
     if mode == 9 { poison = invalid || (!condition && kind == 1) }
     mut value := result[0]
     if mode in [2, 5] && poison { value = 0; poison = false }
     index := if mode == 1 { value & 63 } else { value }
     valid := !undef && !poison && index < 64 && (mode != 0 || index & (u64(1) << u32(width - 1)) == 0)
     mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
     jv := [j | ~sm]; cv := [u64(condition) | ~u64(1)]
     mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
     check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
     if valid { accepted++ } else { refused++ }; if undef { undefined++ }
     rows.writeln('${width} ${count} ${state} ${selector_bits} ${mode} ${condition} ${j} ${kind} ${index} ${valid} PASS')!
     unsafe { actual.free(); expected.free(); jv.free(); cv.free(); bindings.free() }
    } }; unsafe { av.free(); bv.free(); candidates.free() }; plan.free()
   }
  } } }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 assert accepted + refused == 2701440
 line := 'AIR-VECTOR-SELECT-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} selected undef), all 64 lane widths, selector widths 1/32/64, lengths 1/2/3/16 plus all lengths at i32, 8 lane patterns, 10 expression patterns, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
