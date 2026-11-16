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

struct ExpectedLane { word u64 state int }

fn insertion_source(width int, count int, state int, mode int, index_bits int, safe bool) string {
 t := '<${count} x i${width}>'; arg := if safe { literal(width, count, 0, true) } else { '%a' }
 base := if mode == 0 { arg } else if mode == 4 { if safe { 'zeroinitializer' } else { 'poison' } } else if mode == 5 { if safe { 'zeroinitializer' } else { 'undef' } } else { literal(width, count, state, safe) }
 mut text := ''
 mut source := base
 if mode == 7 { text += '%base = select i1 %c, ${t} ${base}, ${t} ${arg}\n'; source = '%base' }
 if mode == 9 { text += '%base = freeze ${t} ${base}\n'; source = '%base' }
 replacement := if mode in [2, 6] { if safe { '0' } else { 'poison' } } else if mode in [3, 8] { if safe { '0' } else { 'undef' } } else { '%d' }
 if safe {
  text += '%kvalid = icmp ult i64 %k, ${count}\n %bounded_k = select i1 %kvalid, i64 %k, i64 0\n %patch = insertelement ${t} ${source}, i${width} ${replacement}, i64 %bounded_k\n %v = select i1 %kvalid, ${t} %patch, ${t} zeroinitializer\n'
 } else { text += '%v = insertelement ${t} ${source}, i${width} ${replacement}, i${index_bits} %k\n' }
 if mode == 6 { text += '%s = insertelement ${t} %v, i${width} %d, i32 0\n' }
 else if mode in [3, 7] { text += '%s = freeze ${t} %v\n' }
 else if mode == 8 { text += '%s = select i1 %c, ${t} ${arg}, ${t} %v\n' }
 else { text += '%s = select i1 true, ${t} %v, ${t} %v\n' }
 return text
}

// Independent state model: insertion overwrites exactly one lane, invalid
// insertion poisons all lanes, and subsequent operations use their own order.
fn expected_lane(width int, count int, state int, mode int, j u64, k u64, d u64) ExpectedLane {
 mut lanes := [16]ExpectedLane{}
 for i in 0 .. count {
  selected := if mode == 0 || (mode == 7 && j >= k) { 0 } else { state }
  lanes[i] = if mode == 4 { ExpectedLane{state: 1} } else if mode == 5 { ExpectedLane{state: 2} } else { ExpectedLane{word: lane_word(width, selected, i), state: lane_state(selected, i)} }
  if mode == 9 && lanes[i].state != 0 { lanes[i] = ExpectedLane{} }
 }
 if k >= u64(count) { for i in 0 .. count { lanes[i] = ExpectedLane{state: 1} } }
 else { lanes[int(k)] = if mode in [2, 6] { ExpectedLane{state: 1} } else if mode in [3, 8] { ExpectedLane{state: 2} } else { ExpectedLane{word: d} } }
 if mode == 6 { lanes[0] = ExpectedLane{word: d} }
 if mode in [3, 7] { for i in 0 .. count { if lanes[i].state != 0 { lanes[i] = ExpectedLane{} } } }
 if mode == 8 && j < k { for i in 0 .. count { lanes[i] = ExpectedLane{word: lane_word(width, 0, i)} } }
 mut result := if j >= u64(count) { ExpectedLane{state: 1} } else { lanes[int(j)] }
 if mode == 2 && result.state == 1 { result = ExpectedLane{} }
 return result
}

fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(65536); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %a, i32 %d, i32 %j, i32 %k, ptr %out)'
 for over in [false, true] {
  for side in ['source', 'replacement', 'insertion', 'selector'] {
   text.write_string('define void @depth_${side}_${over}${args} {\n')
   n := if side == 'selector' { if over { 28 } else { 27 } } else { if over { 29 } else { 28 } }
   if side == 'source' {
    for i in 0 .. n { prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = insertelement <3 x i32> ${prev}, i32 %d, i32 %k\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
    text.write_string('%wide = zext i32 %v${n - 1} to i64\n')
   } else {
    arg := if side == 'replacement' { '%d' } else if side == 'insertion' { '%k' } else { '%j' }
    for i in 0 .. n { prev := if i == 0 { arg } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') }
    text.write_string('%s = insertelement <3 x i32> %a, i32 ${if side == 'replacement' { '%r' + (n - 1).str() } else { '%d' }}, i32 ${if side == 'insertion' { '%r' + (n - 1).str() } else { '%k' }}\n %v = extractelement <3 x i32> %s, i32 ${if side == 'selector' { '%r' + (n - 1).str() } else { '%j' }}\n %wide = zext i32 %v to i64\n')
   }
   text.write_string('%last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  }
  text.write_string('define void @nodes_${over}${args} { %s = insertelement <3 x i32> %a, i32 %d, i32 %k\n')
  for i in 0 .. if over { 252 } else { 251 } { text.write_string('%v${i} = extractelement <3 x i32> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['replaced_undef', 'unreplaced_undef', 'ignored_replacement_undef', 'chosen_replacement_undef', 'scalar_ignored_undef', 'source_freeze', 'scalar_freeze', 'invalid_insertion', 'poison_insertion', 'source_freeze_invalid', 'invalid_extraction', 'outer_freeze', 'repair_invalid', 'unrepaired_invalid', 'root_before', 'root_after', 'cold_bad', 'cold_good', 'cache_selectors', 'loaded_base', 'shuffled_base', 'loaded_replacement', 'loaded_index', 'undef_index', 'invalid_replacement', 'invalid_index', 'frozen_cache_before', 'frozen_cache_after']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_base' { text.write_string('%base = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'shuffled_base' { text.write_string('%base = shufflevector <3 x i32> %a, <3 x i32> %a, <3 x i32> zeroinitializer\n') }
  if kind in ['loaded_replacement', 'loaded_index'] { text.write_string('%loaded = load i32, ptr %out, align 1\n') }
  if kind in ['invalid_replacement', 'invalid_index'] { text.write_string('%bad = udiv i32 1, 0\n') }
  if kind == 'frozen_cache_before' { text.write_string('%uf = freeze i32 undef\n %up = getelementptr i8, ptr %out, i32 %uf\n') }
  base := if kind in ['replaced_undef', 'unreplaced_undef'] { 'undef' } else if kind in ['loaded_base', 'shuffled_base'] { '%base' } else { '%a' }
  replacement := if kind in ['ignored_replacement_undef', 'chosen_replacement_undef', 'scalar_ignored_undef', 'source_freeze', 'scalar_freeze', 'root_before', 'root_after', 'cold_bad', 'cold_good', 'frozen_cache_before', 'frozen_cache_after'] { 'undef' } else if kind == 'loaded_replacement' { '%loaded' } else if kind == 'invalid_replacement' { '%bad' } else { '%d' }
  index := if kind in ['invalid_insertion', 'source_freeze_invalid', 'repair_invalid', 'unrepaired_invalid'] { '3' } else if kind == 'poison_insertion' { 'poison' } else if kind == 'undef_index' { 'undef' } else if kind == 'loaded_index' { '%loaded' } else if kind == 'invalid_index' { '%bad' } else { '%k' }
  text.write_string('%s = insertelement <3 x i32> ${base}, i32 ${replacement}, i32 ${index}\n')
  if kind == 'root_before' { text.write_string('%bad = extractelement <3 x i32> %s, i32 0\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  frozen := kind in ['source_freeze', 'source_freeze_invalid', 'invalid_extraction', 'root_before', 'root_after', 'cold_good']
  if frozen { text.write_string('%f = freeze <3 x i32> %s\n') }
  repaired := kind in ['repair_invalid', 'unrepaired_invalid']
  if repaired { text.write_string('%fixed = insertelement <3 x i32> %s, i32 %d, i32 0\n') }
  selector := if kind in ['unreplaced_undef', 'ignored_replacement_undef', 'unrepaired_invalid'] { '1' } else if kind in ['invalid_extraction', 'outer_freeze'] { '3' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${if repaired { '%fixed' } else if frozen { '%f' } else { '%s' }}, i32 ${selector}\n')
  if kind in ['scalar_freeze', 'outer_freeze'] { text.write_string('%idx = freeze i32 %v\n') }
  else if kind == 'scalar_ignored_undef' { text.write_string('%idx = select i1 false, i32 %v, i32 0\n') }
  else if kind == 'cache_selectors' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i32> %s, i32 %next\n %idx = add i32 %v, %other\n') }
  else { text.write_string('%idx = or i32 %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%bad = extractelement <3 x i32> %s, i32 0\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  if kind == 'frozen_cache_after' { text.write_string('%uf = freeze i32 undef\n %up = getelementptr i8, ptr %out, i32 %uf\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['depth_source', 'depth_replacement', 'depth_insertion', 'depth_selector', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over, name; plan.free() } else { assert over, '${name}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; dv := [u64(5)]; jv := [u64(0)]; kv := [u64(0)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: dv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: kv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_base', 'shuffled_base', 'loaded_replacement', 'loaded_index', 'undef_index'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported insertion') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported insertion ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['replaced_undef', 'ignored_replacement_undef', 'source_freeze', 'source_freeze_invalid', 'outer_freeze', 'repair_invalid', 'cold_good', 'cache_selectors']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { expected[if kind in ['replaced_undef', 'repair_invalid'] { 5 } else if kind == 'ignored_replacement_undef' { 2 } else if kind == 'cache_selectors' { 7 } else { 0 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); dv.free(); jv.free(); kv.free(); bindings.free() }
 }
 f := fi(ir, 'replaced_undef'); scope := bodies.scopes[f + 1]; mut insertion := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 7 { insertion = i; break } }
 assert insertion >= 0; saved := p.instructions[insertion]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[insertion + 1].result_type}] {
  p.instructions[insertion] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed insertion') }; total++
 }
 p.instructions[insertion] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}

fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-INSERT-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0
 for width in 1 .. 65 {
  counts := if width == 32 { []int{len: 16, init: index + 1} } else { [1, 2, 3, 16] }
  wide := if width == 64 { 'or i64 %value, 0' } else { 'zext i${width} %value to i64' }
  mut index_widths := [1, 32, 64]; if width !in index_widths { index_widths << width }
  mut text := strings.new_builder(524288); text.write_string('target datalayout = "e-p:64:64"\n')
  for count in counts { for state in 0 .. 8 { for mode in 0 .. 10 {
   vector := '<${count} x i${width}>'
   text.write_string('define void @ref_${count}_${state}_${mode}(ptr %in, ptr %unused, ptr %out) { %j = load i64, ptr %in, align 1\n %kp = getelementptr i64, ptr %in, i64 1\n %k = load i64, ptr %kp, align 1\n %dp = getelementptr i64, ptr %in, i64 2\n %raw_d = load i64, ptr %dp, align 1\n %d = ${if width == 64 { 'or i64 %raw_d, 0' } else { 'trunc i64 %raw_d to i' + width.str() }}\n %c = icmp ult i64 %j, %k\n')
   text.write_string(insertion_source(width, count, state, mode, 64, true))
   text.write_string('%jvalid = icmp ult i64 %j, ${count}\n %bounded_j = select i1 %jvalid, i64 %j, i64 0\n %value = extractelement ${vector} %s, i64 %bounded_j\n %wide = ${wide}\n %result = select i1 %jvalid, i64 %wide, i64 0\n store i64 %result, ptr %out, align 1\n ret void }\n')
   for index_bits in index_widths {
    selector_bits := if index_bits == width && width !in [1, 32, 64] { 64 } else { index_bits }
    text.write_string('define void @test_${count}_${state}_${index_bits}_${mode}(${vector} %a, i${width} %d, i${selector_bits} %j, i${index_bits} %k, ptr %out) { store i8 17, ptr %out\n %j64 = ${if selector_bits == 64 { 'or i64 %j, 0' } else { 'zext i' + selector_bits.str() + ' %j to i64' }}\n %k64 = ${if index_bits == 64 { 'or i64 %k, 0' } else { 'zext i' + index_bits.str() + ' %k to i64' }}\n %c = icmp ult i64 %j64, %k64\n')
    text.write_string(insertion_source(width, count, state, mode, index_bits, false))
    text.write_string('%r = extractelement ${vector} %s, i${selector_bits} %j\n %value = ${if mode == 2 { 'freeze i' + width.str() + ' %r' } else { 'or i' + width.str() + ' %r, 0' }}\n')
    if mode == 0 { text.write_string('%p = getelementptr i8, ptr %out, i${width} %value\n') }
    else { text.write_string('%wide = ${wide}\n %idx = ${if mode == 9 { 'and i64 %wide, 63' } else { 'or i64 %wide, 0' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n') }
    text.write_string('store i8 42, ptr %p\n ret void }\n')
   }
  } } }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  for count in counts { for state in 0 .. 8 { for mode in 0 .. 10 {
   reference := C.LLVMGetFunctionAddress(native.engine, ('ref_${count}_${state}_${mode}').str); assert reference != 0
   for index_bits in index_widths {
    selector_bits := if index_bits == width && width !in [1, 32, 64] { 64 } else { index_bits }
    f := fi(ir, 'test_${count}_${state}_${index_bits}_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
    sm := mask(selector_bits); im := mask(index_bits)
    mut js := []u64{cap: count + 4}; for j in 0 .. count + 1 { js << u64(j) }; js << [sm, u64(1) << u32(selector_bits - 1)]
    mut ks := []u64{cap: 8}; ks << [u64(0), 1, u64(count / 2), u64(count - 1), u64(count), im, u64(1) << u32(index_bits - 1)]
    mut av := []u64{len: count}; for lane in 0 .. count { av[lane] = lane_word(width, 0, lane) | ~mask(width) }
    d := lane_word(width, state, 1)
    for raw_j in js { for raw_k in ks {
     j := raw_j & sm; k := raw_k & im
     lane := expected_lane(width, count, state, mode, j, k, d)
     inputs := [j, k, d]!; mut result := [u64(0)]!
     unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
     word := if lane.state != 0 { u64(0) } else { lane.word }
     assert result[0] == word, '${width}/${count}/${state}/${mode}/${j}/${k}: ${result[0]} != ${word}'
     index := if mode == 9 { word & 63 } else { word }
     valid := lane.state == 0 && index < 64 && (mode != 0 || index & (u64(1) << u32(width - 1)) == 0)
     mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
     dv := [d | ~mask(width)]; jv := [j | ~sm]; kv := [k | ~im]
     mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: dv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: kv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
     check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
     if valid { accepted++ } else { refused++ }; if lane.state == 2 { undefined++ }
     rows.writeln('${width} ${count} ${state} ${index_bits} ${selector_bits} ${mode} ${j} ${k} ${lane.state} ${index} ${valid} PASS')!
     unsafe { actual.free(); expected.free(); dv.free(); jv.free(); kv.free(); bindings.free() }
    } }; unsafe { av.free(); js.free(); ks.free() }; plan.free()
   }
  } } }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 line := 'AIR-VECTOR-INSERT-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} selected undef), all 64 lane/insertion widths, selector widths 1/32/64, lengths 1/2/3/16 plus all lengths at i32, 8 lane patterns, 10 expression patterns, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
