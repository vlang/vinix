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

fn mask_entry(pattern int, lane int, count int) int {
 return match pattern { 0 { lane % count } 1 { count + lane % count } 2 { count * 2 - 1 - lane % (count * 2) } 3 { count * 2 - 1 } 4 { if lane % 3 == 0 { -1 } else { lane * 7 % (count * 2) } } 5, 6 { -1 } else { 0 } }
}
fn mask_literal(pattern int, count int, size int, safe bool) string {
 if !safe && pattern in [5, 6, 7] { return if pattern == 5 { 'poison' } else if pattern == 6 { 'undef' } else { 'zeroinitializer' } }
 mut lanes := []string{cap: size}
 for lane in 0 .. size { selected := mask_entry(pattern, lane, count); lanes << 'i32 ' + if selected >= 0 { selected.str() } else if safe { '0' } else if lane % 2 == 0 { 'poison' } else { 'undef' } }
 return '<' + lanes.join(', ') + '>'
}
fn arm(width int, count int, state int, right bool, safe bool) string {
 if state == 0 { return if safe { literal(width, count, if right { 5 } else { 0 }, true) } else if right { '%b' } else { '%a' } }
 return literal(width, count, if right { (state + 1) % 4 } else { state }, safe)
}
fn shuffle_source(width int, count int, size int, state int, pattern int, frozen bool, safe bool) string {
 input := '<${count} x i${width}>'; output := '<${size} x i${width}>'
 left := arm(width, count, state, false, safe); right := arm(width, count, state, true, safe)
 mut text := '%raw = shufflevector ${input} ${left}, ${input} ${right}, <${size} x i32> ${mask_literal(pattern, count, size, safe)}\n'
 if safe {
  mut valid := []string{cap: size}; for lane in 0 .. size { valid << 'i1 ' + if mask_entry(pattern, lane, count) >= 0 { 'true' } else { 'false' } }
  text += '%defined = select <${size} x i1> <' + valid.join(', ') + '>, ${output} %raw, ${output} zeroinitializer\n'
  text += '%s = freeze ${output} %defined\n'
 } else if frozen { text += '%s = freeze ${output} %raw\n' }
 return text
}
fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(65536); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] {
  for side in ['left', 'right', 'selector', 'freeze', 'nested'] {
   text.write_string('define void @depth_${side}_${over}${args} {\n')
   n := if side == 'nested' { 9 } else if over { 26 } else { 25 }
   if side in ['left', 'right'] {
    for i in 0 .. n { prev := if i == 0 { if side == 'left' { '%a' } else { '%b' } } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %a\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
   }
   if side == 'selector' { for i in 0 .. n { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
   if side == 'nested' {
    for i in 0 .. n { prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = shufflevector <3 x i32> ${prev}, <3 x i32> %b, <3 x i32> <i32 0, i32 4, i32 2>\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
    text.write_string('%wide = zext i32 %v${n - 1} to i64\n %pad0 = or i64 %wide, 0\n')
    if over { text.write_string('%pad1 = or i64 %pad0, 0\n') }
    text.write_string('%last = getelementptr i8, ptr %out, i64 ${if over { '%pad1' } else { '%pad0' }}\n ret void }\n'); continue
   }
   left := if side == 'left' { '%s' + (n - 1).str() } else { '%a' }; right := if side == 'right' { '%s' + (n - 1).str() } else { '%b' }
   text.write_string('%sh = shufflevector <3 x i32> ${left}, <3 x i32> ${right}, <3 x i32> <i32 0, i32 4, i32 2>\n')
   if side == 'freeze' { for i in 0 .. n { prev := if i == 0 { '%sh' } else { '%f' + (i - 1).str() }; text.write_string('%f${i} = freeze <3 x i32> ${prev}\n %v${i} = extractelement <3 x i32> %f${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   text.write_string('%v = extractelement <3 x i32> ${if side == 'freeze' { '%f' + (n - 1).str() } else { '%sh' }}, i32 ${if side == 'selector' { '%r' + (n - 1).str() } else { '%j' }}\n %wide = zext i32 %v to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  }
  text.write_string('define void @nodes_${over}${args} { %s = shufflevector <3 x i32> %a, <3 x i32> %b, <3 x i32> <i32 0, i32 4, i32 2>\n')
  for i in 0 .. if over { 251 } else { 250 } { text.write_string('%v${i} = extractelement <3 x i32> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['lazy_undef', 'chosen_undef', 'scalar_ignored_undef', 'scalar_freeze_undef', 'source_freeze', 'invalid_selector', 'outer_freeze', 'poison_mask', 'legacy_mask', 'frozen_mask', 'repaired_poison', 'source_insert', 'nested', 'select_discard', 'cache_selectors', 'root_before', 'root_after', 'cold_bad', 'cold_good', 'loaded_source', 'arithmetic_source', 'loaded_selector', 'phi_source', 'undef_selector', 'poison_selector', 'ignored_error', 'poison_condition']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_source' { text.write_string('%left = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'arithmetic_source' { text.write_string('%left = add <3 x i32> %a, zeroinitializer\n') }
  if kind == 'phi_source' { text.write_string('br label %join\n join: %left = phi <3 x i32> [%a, %entry]\n') }
  if kind == 'loaded_selector' { text.write_string('%index = load i32, ptr %out, align 1\n') }
  if kind == 'ignored_error' { text.write_string('%bad = udiv i32 1, 0\n %left = insertelement <3 x i32> %a, i32 %bad, i32 0\n') }
  if kind == 'source_insert' { text.write_string('%left = insertelement <3 x i32> undef, i32 5, i32 0\n') }
  if kind == 'poison_condition' { text.write_string('%left = select i1 poison, <3 x i32> undef, <3 x i32> %b\n') }
  if kind == 'nested' { text.write_string('%left = shufflevector <3 x i32> %a, <3 x i32> %b, <3 x i32> <i32 2, i32 0, i32 4>\n') }
  left := if kind in ['lazy_undef', 'chosen_undef', 'scalar_ignored_undef', 'scalar_freeze_undef', 'source_freeze', 'cold_bad', 'cold_good', 'poison_mask', 'legacy_mask'] { 'undef' } else if kind in ['loaded_source', 'arithmetic_source', 'phi_source', 'ignored_error', 'source_insert', 'nested', 'poison_condition'] { '%left' } else { '%a' }
  mask := if kind in ['lazy_undef', 'ignored_error'] { '<i32 3, i32 3, i32 3>' } else if kind == 'legacy_mask' { 'undef' } else if kind in ['poison_mask', 'frozen_mask', 'repaired_poison'] { 'poison' } else if kind == 'nested' { '<i32 2, i32 0, i32 4>' } else { '<i32 0, i32 4, i32 poison>' }
  text.write_string('%raw = shufflevector <3 x i32> ${left}, <3 x i32> %b, <3 x i32> ${mask}\n')
  if kind == 'root_before' { text.write_string('%bad = extractelement <3 x i32> %raw, i32 2\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  frozen := kind in ['source_freeze', 'frozen_mask', 'root_before', 'root_after', 'cold_good', 'poison_condition']
  if frozen { text.write_string('%f = freeze <3 x i32> %raw\n') }
  if kind == 'repaired_poison' { text.write_string('%fixed = insertelement <3 x i32> %raw, i32 5, i32 0\n') }
  if kind == 'select_discard' { text.write_string('%chosen = select i1 true, <3 x i32> %a, <3 x i32> %raw\n') }
  selector := if kind in ['invalid_selector', 'outer_freeze'] { '3' } else if kind == 'undef_selector' { 'undef' } else if kind == 'poison_selector' { 'poison' } else if kind == 'loaded_selector' { '%index' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${if kind == 'repaired_poison' { '%fixed' } else if kind == 'select_discard' { '%chosen' } else if frozen { '%f' } else { '%raw' }}, i32 ${selector}\n')
  if kind in ['outer_freeze', 'scalar_freeze_undef'] { text.write_string('%idx = freeze i32 %v\n') }
  else if kind == 'scalar_ignored_undef' { text.write_string('%idx = select i1 false, i32 %v, i32 0\n') }
  else if kind == 'cache_selectors' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i32> %raw, i32 %next\n %idx = add i32 %v, %other\n') }
  else { text.write_string('%idx = or i32 %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%bad = extractelement <3 x i32> %raw, i32 2\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['depth_left', 'depth_right', 'depth_selector', 'depth_freeze', 'depth_nested', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over, name; plan.free() } else { assert over, '${name}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_source', 'arithmetic_source', 'phi_source', 'loaded_selector', 'undef_selector'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported shuffle') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported shuffle ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['lazy_undef', 'source_freeze', 'outer_freeze', 'frozen_mask', 'repaired_poison', 'source_insert', 'nested', 'select_discard', 'cache_selectors', 'cold_good', 'poison_condition']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { expected[if kind == 'lazy_undef' { 4 } else if kind in ['repaired_poison', 'source_insert', 'nested'] { 5 } else if kind == 'select_discard' { 1 } else if kind == 'cache_selectors' { 6 } else { 0 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'cache_selectors'); scope := bodies.scopes[f + 1]; mut shuffle := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 8 { shuffle = i; break } }
 assert shuffle >= 0; saved := p.instructions[shuffle]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_count: 2}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[shuffle + 1].result_type}] {
  p.instructions[shuffle] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed shuffle') }; total++
 }
 p.instructions[shuffle] = saved
 saved_index := p.indices[saved.indices_start + 2]
 for changed in [u32(1), 6, 0xfffffffe] {
  p.indices[saved.indices_start + 2] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('changed unselected mask entry') }; total++
 }
 p.indices[saved.indices_start + 2] = saved_index
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-SHUFFLE-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0
 for width in 1 .. 65 {
  counts := if width == 32 { []int{len: 16, init: index + 1} } else { [1, 3, 16] }
  sizes := if width == 32 { []int{len: 16, init: index + 1} } else { [1, 2, 3, 16] }
  for selected_count in counts {
  active_counts := [selected_count]
  wide := if width == 64 { 'or i64 %value, 0' } else { 'zext i${width} %value to i64' }
  mut text := strings.new_builder(1048576); text.write_string('target datalayout = "e-p:64:64"\n')
  for count in active_counts { for size in sizes { for state in 0 .. 4 { for pattern in 0 .. 8 { for frozen in [false, true] {
   input := '<${count} x i${width}>'; output := '<${size} x i${width}>'; name := '${count}_${size}_${state}_${pattern}_${frozen}'
   text.write_string('define void @ref_${name}(ptr %in, ptr %unused, ptr %out) { %j = load i64, ptr %in, align 1\n')
   text.write_string(shuffle_source(width, count, size, state, pattern, frozen, true))
   text.write_string('%valid = icmp ult i64 %j, ${size}\n %bounded = select i1 %valid, i64 %j, i64 0\n %value = extractelement ${output} %s, i64 %bounded\n %wide = ${wide}\n %result = select i1 %valid, i64 %wide, i64 0\n store i64 %result, ptr %out, align 1\n ret void }\n')
   for selector_bits in [1, 32, 64] {
    text.write_string('define void @test_${name}_${selector_bits}(${input} %a, ${input} %b, i${selector_bits} %j, i1 %c, ptr %out) { store i8 17, ptr %out\n')
    text.write_string(shuffle_source(width, count, size, state, pattern, frozen, false))
    text.write_string('%value = extractelement ${output} ${if frozen { '%s' } else { '%raw' }}, i${selector_bits} %j\n %idx = ${wide}\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n')
   }
  } } } } }
  dir := root + '/i${width}-n${selected_count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  for count in active_counts { for size in sizes { for state in 0 .. 4 { for pattern in 0 .. 8 { for frozen in [false, true] {
   name := '${count}_${size}_${state}_${pattern}_${frozen}'; reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + name).str); assert reference != 0
   for selector_bits in [1, 32, 64] {
    f := fi(ir, 'test_${name}_${selector_bits}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
    sm := mask(selector_bits); mut candidates := []u64{cap: size + 4}; for j in 0 .. size + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
    mut av := []u64{len: count}; mut bv := []u64{len: count}; for lane in 0 .. count { av[lane] = lane_word(width, 0, lane) | ~mask(width); bv[lane] = lane_word(width, 5, lane) | ~mask(width) }
    for raw in candidates {
     j := raw & sm; selected := if j >= u64(size) { -1 } else { mask_entry(pattern, int(j), count) }
     source_state := if state == 0 { if selected >= count { 5 } else { 0 } } else if selected >= count { (state + 1) % 4 } else { state }
     kind := if selected < 0 { 1 } else { lane_state(source_state, selected % count) }
     word := if kind != 0 { u64(0) } else { lane_word(width, source_state, selected % count) }
     inputs := [j]!; mut result := [u64(0)]!
     unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
     assert result[0] == word, '${width}/${name}/${j}: ${result[0]} != ${word}'
     valid := j < u64(size) && (frozen || kind == 0) && word < 64
     mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(word)] = 42 }
     jv := [j | ~sm]; cv := [u64(1)]
     mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
     check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
     if valid { accepted++ } else { refused++ }; if j < u64(size) && !frozen && kind == 2 { undefined++ }
     rows.writeln('${width} ${name} ${selector_bits} ${j} ${selected} ${kind} ${word} ${valid} PASS')!
     unsafe { actual.free(); expected.free(); jv.free(); cv.free(); bindings.free() }
    }; unsafe { av.free(); bv.free(); candidates.free() }; plan.free()
   }
  } } } } }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
  }
 }
 assert accepted + refused == 1799040
 line := 'AIR-VECTOR-SHUFFLE-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} selected undef), all 64 lane widths, selector widths 1/32/64, input counts 1/3/16 and output counts 1/2/3/16 plus every count pair at i32, 4 source patterns, 8 mask patterns, frozen/unfrozen, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
