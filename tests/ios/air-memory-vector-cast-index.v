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

fn cast_expected(opcode u32, flags u64, source_bits u32, dest_bits u32, word u64) (bool, u64) {
	negative := word >> (source_bits - 1) & 1
	mut poison := opcode == 1 && flags == 1 && negative != 0
	if opcode == 0 { for bit in dest_bits .. source_bits {
		value := word >> bit & 1
		if flags & 1 != 0 && value != 0 { poison = true }
		if flags & 2 != 0 && value != word >> (dest_bits - 1) & 1 { poison = true }
	} }
	mut result := u64(0)
	for bit in u32(0) .. dest_bits {
		value := if bit < source_bits { word >> bit & 1 } else if opcode == 2 { negative } else { u64(0) }
		result |= value << bit
	}
	return poison, result
}
fn cast_text(op int, flags int) string {
 return ['trunc', 'zext', 'sext'][op] + if flags == 0 { '' } else if op == 1 { ' nneg' } else if flags == 1 { ' nuw' } else if flags == 2 { ' nsw' } else { ' nuw nsw' }
}
fn sample_word(width int, sample int, lane int) u64 {
 sign := u64(1) << u32(width - 1)
 return [u64(0), 1, mask(width), sign, sign - 1, sign + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]![(sample + lane) % 8] & mask(width)
}
fn input_kind(sample int, lane int, count int) int {
 if (sample == 2 && lane == count - 1) || sample == 7 { return 2 }
 if (sample == 3 && lane == count - 1) || sample == 6 { return 1 }
 return 0
}
fn input_literal(width int, count int, sample int) string {
 mut lanes := []string{cap: count}
 for lane in 0 .. count { kind := input_kind(sample, lane, count); value := if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { sample_word(width, sample, lane).str() }; lanes << 'i${width} ${value}' }
 return '<' + lanes.join(', ') + '>'
}
fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] {
  for side in ['source', 'selector', 'freeze', 'nested'] {
   text.write_string('define void @depth_${side}_${over}${args} {\n')
   n := if side == 'nested' { 14 } else if side == 'selector' { if over { 29 } else { 28 } } else if over { 27 } else { 26 }
   if side == 'source' { for i in 0 .. n { prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %b\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   if side == 'selector' { for i in 0 .. n { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
   if side == 'nested' {
    for i in 0 .. n {
     src := if i % 2 == 0 { 32 } else { 64 }; dst := if i % 2 == 0 { 64 } else { 32 }
     prev := if i == 0 { 'zeroinitializer' } else { '%s' + (i - 1).str() }
     text.write_string('%s${i} = ${if i % 2 == 0 { 'zext' } else { 'trunc' }} <1 x i${src}> ${prev} to <1 x i${dst}>\n %v${i} = extractelement <1 x i${dst}> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i${dst} %v${i}\n')
    }
    text.write_string('%wide = zext i32 %v${n - 1} to i64\n')
    if over { text.write_string('%extra = or i64 %wide, 0\n') }
    text.write_string('%last = getelementptr i8, ptr %out, i64 ${if over { '%extra' } else { '%wide' }}\n ret void }\n'); continue
   }
   text.write_string('%raw = zext <3 x i32> ${if side == 'source' { '%s' + (n - 1).str() } else { '%a' }} to <3 x i64>\n')
   if side == 'freeze' { for i in 0 .. n { prev := if i == 0 { '%raw' } else { '%f' + (i - 1).str() }; text.write_string('%f${i} = freeze <3 x i64> ${prev}\n %v${i} = extractelement <3 x i64> %f${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i64 %v${i}\n') } }
   text.write_string('%v = extractelement <3 x i64> ${if side == 'freeze' { '%f' + (n - 1).str() } else { '%raw' }}, i32 ${if side == 'selector' { '%r' + (n - 1).str() } else { '%j' }}\n %wide = or i64 %v, 0\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  }
  text.write_string('define void @nodes_${over}${args} { %s = zext <3 x i32> %a to <3 x i64>\n')
  for i in 0 .. if over { 245 } else { 244 } { text.write_string('%v${i} = extractelement <3 x i64> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i64 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['defined', 'ignored_undef', 'invalid_undef', 'scalar_freeze_undef', 'result_freeze_undef', 'source_freeze_undef', 'select_ignored_undef', 'poison_neighbor', 'selected_poison', 'result_freeze_poison', 'negative_neighbor', 'selected_negative', 'frozen_negative', 'trunc_neighbor', 'trunc_selected', 'trunc_result_freeze', 'trunc_nsw', 'sign_extension', 'old_after_freeze', 'root_before', 'root_after', 'cache_selectors', 'cold_bad', 'cold_good', 'loaded_source', 'comparison_source', 'loaded_scalar', 'phi_source', 'undef_selector', 'invalid_selector', 'outer_freeze', 'insert_repair', 'shuffle_source', 'binary_source', 'binary_error', 'select_source']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_source' { text.write_string('%left = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'comparison_source' { text.write_string('%cmp = icmp eq <3 x i32> %a, zeroinitializer\n %left = sext <3 x i1> %cmp to <3 x i32>\n') }
  if kind == 'loaded_scalar' { text.write_string('%loaded = load i32, ptr %out, align 1\n %left = insertelement <3 x i32> %a, i32 %loaded, i32 2\n') }
  if kind == 'phi_source' { text.write_string('br label %join\n join: %left = phi <3 x i32> [%a, %entry]\n') }
  if kind == 'insert_repair' { text.write_string('%left = insertelement <3 x i32> <i32 1, i32 undef, i32 3>, i32 2, i32 1\n') }
  if kind == 'shuffle_source' { text.write_string('%left = shufflevector <3 x i32> %a, <3 x i32> %b, <3 x i32> <i32 4, i32 0, i32 2>\n') }
  if kind == 'binary_source' { text.write_string('%left = add <3 x i32> %a, zeroinitializer\n') }
  if kind == 'binary_error' { text.write_string('%left = udiv <3 x i32> %a, <i32 1, i32 0, i32 1>\n') }
  if kind == 'select_source' { text.write_string('%left = select i1 %c, <3 x i32> %a, <3 x i32> undef\n') }
  if kind == 'sign_extension' { text.write_string('%left = trunc <3 x i32> %a to <3 x i1>\n') }
  undef := kind in ['ignored_undef', 'invalid_undef', 'scalar_freeze_undef', 'result_freeze_undef', 'source_freeze_undef', 'select_ignored_undef', 'cold_bad']
  poison := kind in ['poison_neighbor', 'selected_poison', 'result_freeze_poison', 'old_after_freeze', 'root_before', 'root_after']
  truncating := kind.starts_with('trunc_')
  negative := kind in ['negative_neighbor', 'selected_negative', 'frozen_negative']
  mut left := if undef { '<i32 1, i32 undef, i32 3>' } else if poison { '<i32 1, i32 poison, i32 3>' } else if negative { '<i32 1, i32 2147483648, i32 3>' } else if truncating { if kind == 'trunc_nsw' { '<i64 1, i64 2147483648, i64 3>' } else { '<i64 1, i64 4294967297, i64 3>' } } else if kind in ['loaded_source', 'comparison_source', 'loaded_scalar', 'phi_source', 'insert_repair', 'shuffle_source', 'binary_source', 'binary_error', 'select_source', 'sign_extension'] { '%left' } else { '%a' }
  if kind == 'source_freeze_undef' { text.write_string('%sf = freeze <3 x i32> ${left}\n'); left = '%sf' }
  source_bits := if truncating { 64 } else if kind == 'sign_extension' { 1 } else { 32 }; dest_bits := if truncating || kind == 'sign_extension' { 32 } else { 64 }
  operation := if truncating { if kind == 'trunc_nsw' { 'trunc nsw' } else { 'trunc nuw' } } else if negative { 'zext nneg' } else if kind == 'sign_extension' { 'sext' } else { 'zext' }
  text.write_string('%raw = ${operation} <3 x i${source_bits}> ${left} to <3 x i${dest_bits}>\n')
  if kind == 'root_before' { text.write_string('%bad = extractelement <3 x i64> %raw, i32 1\n %bp = getelementptr i8, ptr %out, i64 %bad\n') }
  frozen := kind in ['result_freeze_undef', 'result_freeze_poison', 'old_after_freeze', 'root_before', 'root_after', 'frozen_negative', 'trunc_result_freeze']
  if frozen { text.write_string('%f = freeze <3 x i${dest_bits}> %raw\n') }
  if kind == 'select_ignored_undef' { text.write_string('%chosen = select i1 true, <3 x i64> zeroinitializer, <3 x i64> %raw\n') }
  selector := if kind in ['selected_poison', 'result_freeze_poison', 'selected_negative', 'frozen_negative', 'trunc_selected', 'trunc_result_freeze', 'trunc_nsw', 'old_after_freeze'] { '1' } else if kind in ['invalid_selector', 'invalid_undef', 'outer_freeze'] { '3' } else if kind == 'undef_selector' { 'undef' } else { '%j' }
  text.write_string('%v = extractelement <3 x i${dest_bits}> ${if kind == 'select_ignored_undef' { '%chosen' } else if frozen && kind != 'old_after_freeze' { '%f' } else { '%raw' }}, i32 ${selector}\n')
  if kind in ['outer_freeze', 'scalar_freeze_undef'] { text.write_string('%idx = freeze i${dest_bits} %v\n') }
  else if kind == 'cache_selectors' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i64> %raw, i32 %next\n %idx = add i64 %v, %other\n') }
  else if kind == 'sign_extension' { text.write_string('%idx = and i32 %v, 63\n') }
  else { text.write_string('%idx = or i${dest_bits} %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i${dest_bits} %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%bad = extractelement <3 x i64> %raw, i32 1\n %bp = getelementptr i8, ptr %out, i64 %bad\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['depth_source', 'depth_selector', 'depth_freeze', 'depth_nested', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over, name; plan.free() } else { assert over, '${name}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_source', 'comparison_source', 'loaded_scalar', 'phi_source', 'undef_selector'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported vector cast') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported vector cast ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['defined', 'source_freeze_undef', 'poison_neighbor', 'result_freeze_poison', 'negative_neighbor', 'frozen_negative', 'trunc_neighbor', 'trunc_result_freeze', 'sign_extension', 'cache_selectors', 'cold_good', 'outer_freeze', 'insert_repair', 'shuffle_source', 'binary_source', 'select_source']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { expected[if kind in ['result_freeze_poison', 'outer_freeze', 'frozen_negative', 'trunc_result_freeze'] { 0 } else if kind == 'sign_extension' { 63 } else if kind == 'cache_selectors' { 3 } else if kind == 'shuffle_source' { 5 } else { 1 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut cast := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 3 { cast = i; break } }
 assert cast >= 0; saved := p.instructions[cast]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 4}, airbitcode.IRTypedInstruction{...saved, opcode: 11}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[cast + 1].result_type}, airbitcode.IRTypedInstruction{...saved, result_type: p.operands[saved.operands_start].type_index}] {
  p.instructions[cast] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed vector cast') }; total++
 }
 p.instructions[cast] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-CAST-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0; mut lane_checks := 0
 for source_bits in 1 .. 65 { for dest_bits in 1 .. 65 {
  if source_bits == dest_bits { continue }
  counts := if source_bits in [1, 8, 16, 32, 64] && dest_bits in [1, 8, 16, 32, 64] { []int{len: 16, init: index + 1} } else { [3] }
  for count in counts {
   input_type := '<${count} x i${source_bits}>'; output_type := '<${count} x i${dest_bits}>'
   mut text := strings.new_builder(262144); text.write_string('target datalayout = "e-p:64:64"\n')
   for op in 0 .. 3 {
    if (op == 0) != (dest_bits < source_bits) { continue }
    text.write_string('define void @ref_${op}(ptr %in, ptr %unused, ptr %out) {\n')
    for lane in 0 .. count { text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = ${if source_bits == 64 { 'or i64 %w' + lane.str() + ', 0' } else { 'trunc i64 %w' + lane.str() + ' to i' + source_bits.str() }}\n %v${lane} = insertelement ${input_type} ${if lane == 0 { 'zeroinitializer' } else { '%v' + (lane - 1).str() }}, i${source_bits} %b${lane}, i32 ${lane}\n') }
    text.write_string('%raw = ${cast_text(op, 0)} ${input_type} %v${count - 1} to ${output_type}\n')
    for lane in 0 .. count { text.write_string('%e${lane} = extractelement ${output_type} %raw, i32 ${lane}\n %z${lane} = ${if dest_bits == 64 { 'or i64 %e' + lane.str() + ', 0' } else { 'zext i' + dest_bits.str() + ' %e' + lane.str() + ' to i64' }}\n %o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n') }
    text.write_string('ret void }\n')
    for flags in 0 .. if op == 0 { 4 } else if op == 1 { 2 } else { 1 } { for sample in 0 .. 8 { for mode in 0 .. 3 { for selector_bits in [1, 32, 64] {
     name := '${op}_${flags}_${sample}_${mode}_${selector_bits}'
     text.write_string('define void @test_${name}(${input_type} %a, ${input_type} %b, i${selector_bits} %j, i1 %c, ptr %out) { store i8 17, ptr %out\n')
     constant := input_literal(source_bits, count, sample)
     if mode == 2 { text.write_string('%aa = freeze ${input_type} ${constant}\n') }
     text.write_string('%raw = ${cast_text(op, flags)} ${input_type} ${if mode == 0 { '%a' } else if mode == 2 { '%aa' } else { constant }} to ${output_type}\n')
     if mode == 1 { text.write_string('%f = freeze ${output_type} %raw\n') }
     text.write_string('%r = extractelement ${output_type} ${if mode == 1 { '%f' } else { '%raw' }}, i${selector_bits} %j\n')
     if mode == 2 { text.write_string('%high = lshr i${dest_bits} %r, ${dest_bits / 2}\n %fold = xor i${dest_bits} %r, %high\n') }
     text.write_string('%value = ${if mode == 1 { 'or i' + dest_bits.str() + ' %r, 0' } else { 'and i' + dest_bits.str() + ' ' + if mode == 2 { '%fold, ' } else { '%r, ' } + (mask(dest_bits) & 63).str() }}\n %idx = ${if dest_bits == 64 { 'or i64 %value, 0' } else { 'zext i' + dest_bits.str() + ' %value to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n')
    } } } }
   }
   dir := root + '/s${source_bits}-d${dest_bits}-n${count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
   stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
   for op in 0 .. 3 {
    if (op == 0) != (dest_bits < source_bits) { continue }
    reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + op.str()).str); assert reference != 0
    for flags in 0 .. if op == 0 { 4 } else if op == 1 { 2 } else { 1 } { for sample in 0 .. 8 { for mode in 0 .. 3 {
     mut inputs := [16]u64{}; mut result := [16]u64{}; mut expected_bits := [16]u64{}; mut poisoned := [16]bool{}; mut hard_undef := false
     mut av := []u64{len: count}
     for lane in 0 .. count {
      mut word := sample_word(source_bits, sample, lane); av[lane] = word | ~mask(source_bits)
      kind := if mode == 0 { 0 } else { input_kind(sample, lane, count) }
      if mode == 1 && kind == 2 { hard_undef = true }
      if kind != 0 { word = 0 }
      bad, value := cast_expected(u32(op), u64(flags), u32(source_bits), u32(dest_bits), word)
      poisoned[lane] = bad || (mode == 1 && kind != 0)
      expected_bits[lane] = value; inputs[lane] = word
     }
     unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
     for lane in 0 .. count { assert result[lane] == expected_bits[lane], '${source_bits}->${dest_bits}: op=${op} flags=${flags} sample=${sample} lane=${lane}'; lane_checks++ }
     for selector_bits in [1, 32, 64] {
      f := fi(ir, 'test_${op}_${flags}_${sample}_${mode}_${selector_bits}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
      sm := mask(selector_bits); mut candidates := []u64{cap: count + 4}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
      for raw in candidates {
       j := raw & sm; poison := j >= u64(count) || (mode != 1 && poisoned[int(j)])
       word := if j >= u64(count) || poisoned[int(j)] { u64(0) } else { result[int(j)] }
       index := if mode == 0 { word & 63 } else if mode == 2 { (word ^ (word >> u32(dest_bits / 2))) & 63 } else { word }
       valid := !hard_undef && !poison && index < 64
       mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
       jv := [j | ~sm]; cv := [u64(1)]
       mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
       check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
       if valid { accepted++ } else { refused++ }; if hard_undef { undefined++ }
       rows.writeln('${source_bits} ${dest_bits} ${count} ${op} ${flags} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${poison} ${index} ${valid} PASS')!
       unsafe { actual.free(); expected.free(); jv.free(); cv.free(); bindings.free() }
      }; unsafe { candidates.free() }; plan.free()
     }; unsafe { av.free() }
    } } }
   }
   native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
  }
 } }
 assert accepted + refused == 6993504
 line := 'AIR-VECTOR-CAST-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} whole-vector undef), ${lane_checks} native/per-bit lane checks, all 4032 distinct i1-i64 width pairs, selector widths 1/32/64, count 3 plus every count for width pairs in 1/8/16/32/64, 7 opcode/flag variants, 8 operand patterns, 3 expression modes, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
