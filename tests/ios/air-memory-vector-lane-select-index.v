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

fn word(width int, state int, lane int, side int) u64 {
 words := [u64(0), 1, mask(width), u64(1) << u32(width - 1), 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 17, 63]!
 return words[(state + lane * 3 + side) % 8] & mask(width)
}
fn arm_kind(state int, lane int, count int, side int) int {
 if (state == 2 && lane == count - 1 && side == 0) || (state == 7 && side == 1) { return 2 }
 if (state == 3 && lane == 0 && side == 1) || (state == 6 && side == 0) { return 1 }
 return 0
}
fn condition_kind(state int, lane int, count int) int {
 if (state == 4 && lane == count - 1) || state == 7 { return 2 }
 if (state == 3 && lane == count - 1) || state == 6 { return 1 }
 return 0
}
fn condition_word(state int, lane int) u64 {
 return match state { 0 { 0 } 1 { 1 } 2 { u64(lane % 2) } 5 { u64(lane % 3 == 0) } else { 0 } }
}
fn condition_literal(state int, count int, safe bool) string {
 mut lanes := []string{cap: count}
 for lane in 0 .. count { kind := condition_kind(state, lane, count); value := if safe || kind == 0 { condition_word(state, lane).str() } else if kind == 1 { 'poison' } else { 'undef' }; lanes << 'i1 ${value}' }
 return '<' + lanes.join(', ') + '>'
}
fn arm_literal(width int, state int, count int, side int) string {
 mut lanes := []string{cap: count}
 for lane in 0 .. count { kind := arm_kind(state, lane, count, side); value := if kind == 0 { word(width, state, lane, side).str() } else if kind == 1 { 'poison' } else { 'undef' }; lanes << 'i${width} ${value}' }
 return '<' + lanes.join(', ') + '>'
}
fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, <3 x i1> %c, ptr %out)'
 for over in [false, true] {
  for side in ['left', 'right', 'condition', 'selector', 'freeze'] {
   text.write_string('define void @depth_${side}_${over}${args} {\n')
   base := if side in ['condition', 'freeze'] { 25 } else { 27 }; n := base + int(over)
   if side in ['left', 'right', 'condition'] {
    typ := if side == 'condition' { '<3 x i1>' } else { '<3 x i32>' }
    first := if side == 'condition' { '%c' } else { '%a' }
    for i in 0 .. n { prev := if i == 0 { first } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = select i1 true, ${typ} ${prev}, ${typ} zeroinitializer\n %v${i} = extractelement ${typ} %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, ${if side == 'condition' { 'i1' } else { 'i32' }} %v${i}\n') }
   }
   if side == 'selector' { for i in 0 .. n { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
   source := '%s' + (n - 1).str()
   text.write_string('%raw = select <3 x i1> ${if side == 'condition' { source } else { '%c' }}, <3 x i32> ${if side == 'left' { source } else { '%a' }}, <3 x i32> ${if side == 'right' { source } else { '%b' }}\n')
   if side == 'freeze' { for i in 0 .. n { prev := if i == 0 { '%raw' } else { '%f' + (i - 1).str() }; text.write_string('%f${i} = freeze <3 x i32> ${prev}\n %v${i} = extractelement <3 x i32> %f${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   text.write_string('%v = extractelement <3 x i32> ${if side == 'freeze' { '%f' + (n - 1).str() } else { '%raw' }}, i32 ${if side == 'selector' { '%r' + (n - 1).str() } else { '%j' }}\n %wide = zext i32 %v to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  }
  text.write_string('define void @nodes_${over}${args} { %s = select <3 x i1> %c, <3 x i32> %a, <3 x i32> %b\n')
  for i in 0 .. 241 + int(over) { text.write_string('%v${i} = extractelement <3 x i32> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['defined', 'unchosen_undef', 'chosen_undef', 'chosen_result_freeze', 'chosen_source_freeze', 'condition_undef', 'condition_undef_result_freeze', 'condition_undef_scalar_freeze', 'condition_undef_invalid_selector', 'condition_undef_discard', 'condition_source_freeze', 'poison_neighbor', 'selected_poison', 'result_freeze_poison', 'source_freeze_poison', 'all_poison', 'all_poison_frozen', 'cache_selectors', 'shared_masks', 'root_before', 'root_after', 'cold_bad', 'cold_good', 'loaded_condition', 'floating_condition', 'loaded_arm', 'phi_condition', 'undef_selector', 'invalid_selector', 'outer_freeze', 'insert_condition', 'shuffle_condition', 'compare_condition', 'binary_condition', 'cast_condition', 'nested_condition', 'binary_error']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_condition' { text.write_string('%mask = load <3 x i1>, ptr %out, align 1\n') }
  if kind == 'floating_condition' { text.write_string('%mask = fcmp oeq <3 x float> zeroinitializer, zeroinitializer\n') }
  if kind == 'loaded_arm' { text.write_string('%arm = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'phi_condition' { text.write_string('br label %join\n join: %mask = phi <3 x i1> [%c, %entry]\n') }
  if kind == 'insert_condition' { text.write_string('%mask = insertelement <3 x i1> <i1 true, i1 undef, i1 true>, i1 false, i32 1\n') }
  if kind == 'shuffle_condition' { text.write_string('%mask = shufflevector <3 x i1> %c, <3 x i1> zeroinitializer, <3 x i32> <i32 1, i32 0, i32 2>\n') }
  if kind == 'compare_condition' { text.write_string('%mask = icmp ult <3 x i32> %a, %b\n') }
  if kind == 'binary_condition' { text.write_string('%mask = xor <3 x i1> %c, <i1 true, i1 true, i1 true>\n') }
  if kind == 'cast_condition' { text.write_string('%mask = trunc <3 x i32> %a to <3 x i1>\n') }
  if kind == 'nested_condition' { text.write_string('%mask = select <3 x i1> %c, <3 x i1> <i1 false, i1 true, i1 false>, <3 x i1> <i1 true, i1 false, i1 true>\n') }
  if kind == 'binary_error' { text.write_string('%bad = udiv <3 x i1> %c, zeroinitializer\n') }
  undef := kind.starts_with('condition_undef') || kind in ['condition_source_freeze', 'root_before', 'root_after', 'cold_bad']
  poison := kind in ['poison_neighbor', 'selected_poison', 'result_freeze_poison', 'source_freeze_poison']
  mut condition := if undef { '<i1 true, i1 undef, i1 true>' } else if poison { '<i1 true, i1 poison, i1 true>' } else if kind.starts_with('all_poison') { 'poison' } else if kind in ['loaded_condition', 'floating_condition', 'phi_condition', 'insert_condition', 'shuffle_condition', 'compare_condition', 'binary_condition', 'cast_condition', 'nested_condition'] { '%mask' } else if kind == 'binary_error' { '%bad' } else { '%c' }
  if kind in ['condition_source_freeze', 'source_freeze_poison', 'root_before', 'root_after'] { text.write_string('%fixed = freeze <3 x i1> ${condition}\n') }
  if kind in ['condition_source_freeze', 'source_freeze_poison'] { condition = '%fixed' }
  if kind == 'root_before' { text.write_string('%old = select <3 x i1> ${condition}, <3 x i32> %a, <3 x i32> %b\n %oldv = extractelement <3 x i32> %old, i32 0\n %oldp = getelementptr i8, ptr %out, i32 %oldv\n') }
  mut left := if kind in ['unchosen_undef', 'chosen_undef', 'chosen_result_freeze', 'chosen_source_freeze'] { if kind == 'unchosen_undef' { '<i32 1, i32 undef, i32 3>' } else { '<i32 undef, i32 2, i32 3>' } } else if kind.starts_with('all_poison') { 'undef' } else if kind == 'loaded_arm' { '%arm' } else { '%a' }
  right := if kind == 'unchosen_undef' { '<i32 undef, i32 5, i32 undef>' } else if kind.starts_with('all_poison') { 'undef' } else { '%b' }
  if kind == 'chosen_source_freeze' { text.write_string('%fixedarm = freeze <3 x i32> ${left}\n'); left = '%fixedarm' }
  text.write_string('%raw = select <3 x i1> ${if kind in ['root_before', 'root_after'] { '%fixed' } else { condition }}, <3 x i32> ${left}, <3 x i32> ${right}\n')
  frozen := kind in ['chosen_result_freeze', 'condition_undef_result_freeze', 'result_freeze_poison', 'all_poison_frozen']
  if frozen { text.write_string('%f = freeze <3 x i32> %raw\n') }
  if kind == 'condition_undef_discard' { text.write_string('%discard = select i1 true, <3 x i32> zeroinitializer, <3 x i32> %raw\n') }
  if kind == 'shared_masks' { text.write_string('%other = select <3 x i1> %c, <3 x i32> %b, <3 x i32> %a\n %ov = extractelement <3 x i32> %other, i32 0\n %op = getelementptr i8, ptr %out, i32 %ov\n') }
  selector := if kind in ['selected_poison', 'result_freeze_poison', 'source_freeze_poison'] { '1' } else if kind in ['condition_undef_invalid_selector', 'invalid_selector', 'outer_freeze'] { '3' } else if kind == 'undef_selector' { 'undef' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${if kind == 'condition_undef_discard' { '%discard' } else if frozen { '%f' } else { '%raw' }}, i32 ${selector}\n')
  if kind in ['outer_freeze', 'condition_undef_scalar_freeze'] { text.write_string('%idx = freeze i32 %v\n') }
  else if kind == 'cache_selectors' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i32> %raw, i32 %next\n %idx = add i32 %v, %other\n') }
  else { text.write_string('%idx = or i32 %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%old = select <3 x i1> ${condition}, <3 x i32> %a, <3 x i32> %b\n %oldv = extractelement <3 x i32> %old, i32 0\n %oldp = getelementptr i8, ptr %out, i32 %oldv\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['depth_left', 'depth_right', 'depth_condition', 'depth_selector', 'depth_freeze', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over, name; plan.free() } else { assert over, '${name}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1), 0, 1]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_condition', 'floating_condition', 'loaded_arm', 'phi_condition', 'undef_selector'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported lane select') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported lane select ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['defined', 'unchosen_undef', 'chosen_result_freeze', 'chosen_source_freeze', 'condition_source_freeze', 'poison_neighbor', 'result_freeze_poison', 'source_freeze_poison', 'all_poison_frozen', 'cache_selectors', 'shared_masks', 'cold_good', 'outer_freeze', 'insert_condition', 'shuffle_condition', 'compare_condition', 'binary_condition', 'cast_condition', 'nested_condition']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { index := if kind in ['chosen_result_freeze', 'chosen_source_freeze', 'result_freeze_poison', 'all_poison_frozen', 'outer_freeze'] { 0 } else if kind == 'source_freeze_poison' { 5 } else if kind == 'cache_selectors' { 6 } else if kind in ['shuffle_condition', 'binary_condition', 'nested_condition'] { 4 } else { 1 }; expected[index] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut selection := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code in [u64(5), 29] { selection = i; break } }
 assert selection >= 0; saved := p.instructions[selection]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[selection + 1].result_type}] {
  p.instructions[selection] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed lane select') }; total++
 }
 p.instructions[selection] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-LANE-SELECT-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0; mut lane_checks := 0
 for width in 1 .. 65 {
  counts := if width in [1, 8, 16, 32, 64] { []int{len: 16, init: index + 1} } else { [3] }
  for count in counts {
   typ := '<${count} x i${width}>'; ct := '<${count} x i1>'
   mut text := strings.new_builder(262144); text.write_string('target datalayout = "e-p:64:64"\n')
   for cs in 0 .. 8 {
    text.write_string('define void @ref_${cs}(ptr %in, ptr %other, ptr %out) {\n')
    for side in 0 .. 2 { for lane in 0 .. count { text.write_string('%p${side}_${lane} = getelementptr i64, ptr ${if side == 0 { '%in' } else { '%other' }}, i64 ${lane}\n %w${side}_${lane} = load i64, ptr %p${side}_${lane}, align 1\n %b${side}_${lane} = ${if width == 64 { 'or i64 %w' + side.str() + '_' + lane.str() + ', 0' } else { 'trunc i64 %w' + side.str() + '_' + lane.str() + ' to i' + width.str() }}\n %v${side}_${lane} = insertelement ${typ} ${if lane == 0 { 'zeroinitializer' } else { '%v' + side.str() + '_' + (lane - 1).str() }}, i${width} %b${side}_${lane}, i32 ${lane}\n') } }
    text.write_string('%raw = select ${ct} ${condition_literal(cs, count, true)}, ${typ} %v0_${count - 1}, ${typ} %v1_${count - 1}\n')
    for lane in 0 .. count { text.write_string('%e${lane} = extractelement ${typ} %raw, i32 ${lane}\n %z${lane} = ${if width == 64 { 'or i64 %e' + lane.str() + ', 0' } else { 'zext i' + width.str() + ' %e' + lane.str() + ' to i64' }}\n %o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n') }
    text.write_string('ret void }\n')
    for state in 0 .. 8 { for mode in 0 .. 4 { for selector_bits in [1, 32, 64] {
     name := '${cs}_${state}_${mode}_${selector_bits}'
     text.write_string('define void @test_${name}(${typ} %a, ${typ} %b, i${selector_bits} %j, ${ct} %c, ptr %out) { store i8 17, ptr %out\n')
     if mode == 2 { text.write_string('%aa = freeze ${typ} ${arm_literal(width, state, count, 0)}\n %bb = freeze ${typ} ${arm_literal(width, state, count, 1)}\n %cc = freeze ${ct} ${condition_literal(cs, count, false)}\n') }
     text.write_string('%raw = select ${ct} ${if mode == 0 { '%c' } else if mode == 2 { '%cc' } else { condition_literal(cs, count, false) }}, ${typ} ${if mode == 0 { '%a' } else if mode == 2 { '%aa' } else { arm_literal(width, state, count, 0) }}, ${typ} ${if mode == 0 { '%b' } else if mode == 2 { '%bb' } else { arm_literal(width, state, count, 1) }}\n')
     if mode == 1 { text.write_string('%f = freeze ${typ} %raw\n') }
     text.write_string('%r = extractelement ${typ} ${if mode == 1 { '%f' } else { '%raw' }}, i${selector_bits} %j\n %high = ${if width == 1 { 'and i1 %r, false' } else { 'lshr i' + width.str() + ' %r, ' + (width / 2).str() }}\n %fold = xor i${width} %r, %high\n %masked = and i${width} %fold, ${mask(width) & 63}\n %idx = ${if width == 64 { 'or i64 %masked, 0' } else { 'zext i' + width.str() + ' %masked to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n')
    } } }
   }
   dir := root + '/w${width}-n${count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
   stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
   for cs in 0 .. 8 {
    reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + cs.str()).str); assert reference != 0
    for state in 0 .. 8 { for mode in 0 .. 4 {
     mut inputs := [16]u64{}; mut others := [16]u64{}; mut result := [16]u64{}; mut expected_words := [16]u64{}; mut hard_undef := false
     mut av := []u64{len: count}; mut bv := []u64{len: count}; mut cv := []u64{len: count}
     for lane in 0 .. count {
      a := word(width, state, lane, 0); b := word(width, state, lane, 1); c := condition_word(cs, lane)
      av[lane] = a | ~mask(width); bv[lane] = b | ~mask(width); cv[lane] = c | ~u64(1)
      ka := if mode == 0 { 0 } else { arm_kind(state, lane, count, 0) }; kb := if mode == 0 { 0 } else { arm_kind(state, lane, count, 1) }; kc := if mode == 0 { 0 } else { condition_kind(cs, lane, count) }
      if mode in [1, 3] && kc == 2 { hard_undef = true }
      inputs[lane] = if ka == 0 { a } else { 0 }; others[lane] = if kb == 0 { b } else { 0 }
      expected_words[lane] = if mode == 1 && kc != 0 { 0 } else if c != 0 { inputs[lane] } else { others[lane] }
     }
     unsafe { NativeCast(voidptr(reference))(&inputs[0], &others[0], &result[0]) }
     for lane in 0 .. count { assert result[lane] == if condition_word(cs, lane) != 0 { inputs[lane] } else { others[lane] }; lane_checks++ }
     for selector_bits in [1, 32, 64] {
      f := fi(ir, 'test_${cs}_${state}_${mode}_${selector_bits}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
      sm := mask(selector_bits); mut candidates := []u64{cap: count + 4}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
      for raw in candidates {
       j := raw & sm; poison := j >= u64(count); v := if poison { u64(0) } else { expected_words[int(j)] }; index := (if width == 1 { v } else { v ^ (v >> u32(width / 2)) }) & 63; bad_lane := mode == 3 && !poison && (condition_kind(cs, int(j), count) != 0 || arm_kind(state, int(j), count, if condition_word(cs, int(j)) != 0 { 0 } else { 1 }) != 0); valid := !hard_undef && !poison && !bad_lane
       mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
       jv := [j | ~sm]
       mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
       check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
       if valid { accepted++ } else { refused++ }; if hard_undef { undefined++ }
       rows.writeln('${width} ${count} ${cs} ${state} ${mode} ${selector_bits} ${j} ${hard_undef} ${index} ${valid} PASS')!
       unsafe { actual.free(); expected.free(); jv.free(); bindings.free() }
      }; unsafe { candidates.free() }; plan.free()
     }; unsafe { av.free(); bv.free(); cv.free() }
    } }
   }
   native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
  }
 }
 assert accepted + refused == 978432 && lane_checks == 219392
 line := 'AIR-VECTOR-LANE-SELECT-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} whole-condition undef), ${lane_checks} native/oracle lane checks, all i1-i64 widths, selector widths 1/32/64, count 3 plus all counts 1..16 for widths 1/8/16/32/64, eight mask patterns, eight arm patterns, four expression modes, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
