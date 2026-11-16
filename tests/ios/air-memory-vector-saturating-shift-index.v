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

fn sample_word(width int, sample int, lane int, side int) u64 {
 if side == 1 { return [u64(0), 1, u64(width - 1), u64(width), u64(width + 1), 2, 63, ~u64(0)]![(sample + lane) % 8] & mask(width) }
 sign := u64(1) << u32(width - 1)
 return [u64(0), 1, mask(width), sign, sign - 1, sign + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]![(sample + lane + side * 3) % 8] & mask(width)
}
fn input_kind(sample int, lane int, count int, side int) int {
 if (sample == 2 && side == 0 && lane == count - 1) || (sample == 5 && side == 1 && lane == count - 1) || (sample == 7 && side == 1) { return 2 }
 if (sample == 3 && side == 0 && lane == count - 1) || (sample == 4 && side == 1 && lane == count - 1) || (sample == 6 && side == 0) { return 1 }
 return 0
}
fn input_literal(width int, count int, sample int, side int) string {
 mut lanes := []string{cap: count}
 for lane in 0 .. count { kind := input_kind(sample, lane, count, side); value := if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { sample_word(width, sample, lane, side).str() }; lanes << 'i${width} ${value}' }
 return '<' + lanes.join(', ') + '>'
}
fn operation(op int) string { return ['sshl.sat', 'ushl.sat'][op] }
// Native references use defined amounts. This oracle doubles with checked
// margins instead of the production magnitude/shift-bound calculation.
fn reference_value(op int, width int, a u64, b u64) u64 {
 limit := mask(width); x := a & limit; amount := b & limit
 assert amount < u64(width)
 if op == 1 {
  mut value := x
  for _ in u64(0) .. amount { if value > limit - value { return limit }; value += value }
  return value
 }
 assert op == 0
 maximum := i64((u64(1) << u32(width - 1)) - 1); minimum := -maximum - 1
 mut value := if x >> u32(width - 1) == 0 { i64(x) } else { -i64((~x) & limit) - 1 }
 for _ in u64(0) .. amount {
  if value > maximum / 2 { return u64(maximum) }
  if value < minimum / 2 { return u64(minimum) & limit }
  value += value
 }
 return u64(value) & limit
}
fn bit_controls(assembler string, root string) !int {
 mut text := strings.new_builder(131072)
 text.write_string('target datalayout = "e-p:64:64"\n declare <3 x i32> @llvm.ctpop.v3i32(<3 x i32>) #0\n declare <1 x i32> @llvm.ctpop.v1i32(<1 x i32>)\n declare <3 x i32> @llvm.bitreverse.v3i32(<3 x i32>)\n declare <3 x i32> @llvm.bswap.v3i32(<3 x i32>)\n declare <3 x i32> @llvm.fptosi.sat.v3i32.v3f32(<3 x float>)\n attributes #0 = { nounwind memory(none) }\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] {
  for side in ['source', 'selector', 'freeze', 'nested'] {
   text.write_string('define void @depth_${side}_${over}${args} {\n')
   n := if side == 'nested' { 14 } else if side == 'selector' { 28 + int(over) } else { 26 + int(over) }
   if side == 'source' { for i in 0 .. n { prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %b\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   if side == 'selector' { for i in 0 .. n { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
   if side == 'nested' {
    for i in 0 .. n { prev := if i == 0 { 'zeroinitializer' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = call <1 x i32> @llvm.ctpop.v1i32(<1 x i32> ${prev})\n %v${i} = extractelement <1 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
    text.write_string('%wide = zext i32 %v${n - 1} to i64\n')
    if over { text.write_string('%extra = or i64 %wide, 0\n') }
    text.write_string('%last = getelementptr i8, ptr %out, i64 ${if over { '%extra' } else { '%wide' }}\n ret void }\n'); continue
   }
   text.write_string('%raw = call <3 x i32> @llvm.ctpop.v3i32(<3 x i32> ${if side == 'source' { '%s' + (n - 1).str() } else { '%a' }})\n')
   if side == 'freeze' { for i in 0 .. n { prev := if i == 0 { '%raw' } else { '%f' + (i - 1).str() }; text.write_string('%f${i} = freeze <3 x i32> ${prev}\n %v${i} = extractelement <3 x i32> %f${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   text.write_string('%v = extractelement <3 x i32> ${if side == 'freeze' { '%f' + (n - 1).str() } else { '%raw' }}, i32 ${if side == 'selector' { '%r' + (n - 1).str() } else { '%j' }}\n %wide = zext i32 %v to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  }
  text.write_string('define void @nodes_${over}${args} { %s = call <3 x i32> @llvm.ctpop.v3i32(<3 x i32> %a)\n')
  for i in 0 .. 244 + int(over) { text.write_string('%v${i} = extractelement <3 x i32> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['defined', 'ignored_undef', 'invalid_undef', 'scalar_freeze_undef', 'result_freeze_undef', 'source_freeze_undef', 'select_ignored_undef', 'poison_neighbor', 'selected_poison', 'result_freeze_poison', 'old_after_freeze', 'root_before', 'root_after', 'cache_selectors', 'cold_bad', 'cold_good', 'loaded_source', 'unsupported_call', 'loaded_scalar', 'phi_source', 'undef_selector', 'invalid_selector', 'outer_freeze', 'insert_repair', 'shuffle_source', 'binary_source', 'cast_source', 'compare_source', 'mask_source', 'binary_error', 'select_source', 'chain']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_source' { text.write_string('%left = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'unsupported_call' { text.write_string('%left = call <3 x i32> @llvm.fptosi.sat.v3i32.v3f32(<3 x float> zeroinitializer)\n') }
  if kind == 'loaded_scalar' { text.write_string('%loaded = load i32, ptr %out, align 1\n %left = insertelement <3 x i32> %a, i32 %loaded, i32 2\n') }
  if kind == 'phi_source' { text.write_string('br label %join\n join: %left = phi <3 x i32> [%a, %entry]\n') }
  if kind == 'insert_repair' { text.write_string('%left = insertelement <3 x i32> <i32 1, i32 undef, i32 3>, i32 2, i32 1\n') }
  if kind == 'shuffle_source' { text.write_string('%left = shufflevector <3 x i32> %a, <3 x i32> %b, <3 x i32> <i32 4, i32 0, i32 2>\n') }
  if kind == 'binary_source' { text.write_string('%left = add <3 x i32> %a, zeroinitializer\n') }
  if kind == 'cast_source' { text.write_string('%small = trunc <3 x i32> %a to <3 x i8>\n %left = zext <3 x i8> %small to <3 x i32>\n') }
  if kind == 'compare_source' { text.write_string('%mask = icmp ult <3 x i32> %a, %b\n %left = zext <3 x i1> %mask to <3 x i32>\n') }
  if kind == 'mask_source' { text.write_string('%left = select <3 x i1> <i1 true, i1 false, i1 true>, <3 x i32> %a, <3 x i32> %b\n') }
  if kind == 'binary_error' { text.write_string('%left = udiv <3 x i32> %a, <i32 1, i32 0, i32 1>\n') }
  if kind == 'select_source' { text.write_string('%left = select i1 %c, <3 x i32> %a, <3 x i32> undef\n') }
  if kind == 'chain' { text.write_string('%swap = call <3 x i32> @llvm.bswap.v3i32(<3 x i32> %a)\n %back = call <3 x i32> @llvm.bswap.v3i32(<3 x i32> %swap)\n %reverse = call <3 x i32> @llvm.bitreverse.v3i32(<3 x i32> %back)\n %left = call <3 x i32> @llvm.bitreverse.v3i32(<3 x i32> %reverse)\n') }
  undef := kind in ['ignored_undef', 'invalid_undef', 'scalar_freeze_undef', 'result_freeze_undef', 'source_freeze_undef', 'select_ignored_undef', 'cold_bad']
  poison := kind in ['poison_neighbor', 'selected_poison', 'result_freeze_poison', 'old_after_freeze', 'root_before', 'root_after']
  mut left := if undef { '<i32 1, i32 undef, i32 3>' } else if poison { '<i32 1, i32 poison, i32 3>' } else if kind in ['loaded_source', 'unsupported_call', 'loaded_scalar', 'phi_source', 'insert_repair', 'shuffle_source', 'binary_source', 'cast_source', 'compare_source', 'mask_source', 'binary_error', 'select_source', 'chain'] { '%left' } else { '%a' }
  if kind == 'source_freeze_undef' { text.write_string('%sf = freeze <3 x i32> ${left}\n'); left = '%sf' }
  text.write_string('%raw = call <3 x i32> @llvm.ctpop.v3i32(<3 x i32> ${left})\n')
  if kind == 'root_before' { text.write_string('%bad = extractelement <3 x i32> %raw, i32 1\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  frozen := kind in ['result_freeze_undef', 'result_freeze_poison', 'old_after_freeze', 'root_before', 'root_after']
  if frozen { text.write_string('%f = freeze <3 x i32> %raw\n') }
  if kind == 'select_ignored_undef' { text.write_string('%chosen = select i1 true, <3 x i32> zeroinitializer, <3 x i32> %raw\n') }
  selector := if kind in ['selected_poison', 'result_freeze_poison', 'old_after_freeze'] { '1' } else if kind in ['invalid_selector', 'invalid_undef', 'outer_freeze'] { '3' } else if kind == 'undef_selector' { 'undef' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${if kind == 'select_ignored_undef' { '%chosen' } else if frozen && kind != 'old_after_freeze' { '%f' } else { '%raw' }}, i32 ${selector}\n')
  if kind in ['outer_freeze', 'scalar_freeze_undef'] { text.write_string('%idx = freeze i32 %v\n') }
  else if kind == 'cache_selectors' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i32> %raw, i32 %next\n %idx = add i32 %v, %other\n') }
  else { text.write_string('%idx = or i32 %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%bad = extractelement <3 x i32> %raw, i32 1\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
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
  if kind in ['loaded_source', 'unsupported_call', 'loaded_scalar', 'phi_source', 'undef_selector'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported vector intrinsic') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported vector intrinsic ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['defined', 'source_freeze_undef', 'poison_neighbor', 'result_freeze_poison', 'cache_selectors', 'cold_good', 'outer_freeze', 'insert_repair', 'shuffle_source', 'binary_source', 'cast_source', 'compare_source', 'mask_source', 'select_source', 'chain']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { expected[if kind in ['result_freeze_poison', 'outer_freeze'] { 0 } else if kind == 'cache_selectors' { 2 } else if kind == 'shuffle_source' { 2 } else { 1 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut call := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 34 { call = i; break } }
 assert call >= 0; saved := p.instructions[call]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[call + 1].result_type}] {
  p.instructions[call] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed vector intrinsic') }; total++
 }
 p.instructions[call] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn extrema_controls(assembler string, root string) !int {
 mut text := strings.new_builder(131072)
 text.write_string('target datalayout = "e-p:64:64"\n')
 for id in ['smin', 'smax', 'umin', 'umax'] { text.write_string('declare <3 x i32> @llvm.${id}.v3i32(<3 x i32>, <3 x i32>) #0\n') }
 text.write_string('attributes #0 = { nounwind memory(none) }\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] { for side in ['left', 'right', 'selector', 'nodes'] {
  text.write_string('define void @depth_${side}_${over}${args} {\n')
  if side in ['left', 'right'] { for i in 0 .. 26 + int(over) {
   prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }
   text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %b\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n')
  } }
  if side == 'selector' { for i in 0 .. 28 + int(over) { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
  text.write_string('%raw = call <3 x i32> @llvm.smin.v3i32(<3 x i32> ${if side == 'left' { '%s' + (25 + int(over)).str() } else { '%a' }}, <3 x i32> ${if side == 'right' { '%s' + (25 + int(over)).str() } else { '%b' }})\n')
  if side == 'nodes' {
   // 15 shared selector/table/projection nodes plus one scalar extraction
   // for each independently checked GEP: 241 reaches the 256-node boundary.
   for i in 0 .. 241 + int(over) { text.write_string('%v${i} = extractelement <3 x i32> %raw, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  } else {
   text.write_string('%v = extractelement <3 x i32> %raw, i32 ${if side == 'selector' { '%r' + (27 + int(over)).str() } else { '%j' }}\n %wide = zext i32 %v to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n')
  }
  text.write_string('ret void }\n')
 } }
 kinds := ['defined', 'left_undef', 'right_undef', 'both_undef', 'left_poison', 'right_poison', 'poison_ignored', 'result_freeze_poison', 'source_freeze_undef', 'right_freeze_undef', 'result_freeze_undef', 'invalid_undef', 'unchosen_undef', 'cold_undef', 'cold_good', 'composition', 'mask_consumer', 'shared', 'winning_left_poison', 'winning_right_poison']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  mut left := if kind in ['left_undef', 'both_undef', 'source_freeze_undef'] { '<i32 1, i32 undef, i32 3>' } else if kind in ['left_poison', 'poison_ignored', 'result_freeze_poison'] { '<i32 1, i32 poison, i32 3>' } else if kind == 'winning_left_poison' { '<i32 poison, i32 2, i32 3>' } else { '%a' }
  mut right := if kind in ['right_undef', 'both_undef', 'right_freeze_undef', 'result_freeze_undef', 'invalid_undef', 'unchosen_undef', 'cold_undef'] { '<i32 4, i32 undef, i32 6>' } else if kind == 'right_poison' { '<i32 4, i32 poison, i32 6>' } else if kind == 'winning_right_poison' { '<i32 poison, i32 5, i32 6>' } else if kind == 'winning_left_poison' { 'zeroinitializer' } else { '%b' }
  if kind == 'winning_right_poison' { left = 'zeroinitializer' }
  if kind == 'source_freeze_undef' { text.write_string('%sf = freeze <3 x i32> ${left}\n'); left = '%sf' }
  if kind == 'right_freeze_undef' { text.write_string('%sf = freeze <3 x i32> ${right}\n'); right = '%sf' }
  text.write_string('%raw = call <3 x i32> @llvm.smin.v3i32(<3 x i32> ${left}, <3 x i32> ${right})\n')
  mut source := '%raw'
  if kind in ['result_freeze_poison', 'result_freeze_undef'] { text.write_string('%f = freeze <3 x i32> %raw\n'); source = '%f' }
  if kind == 'unchosen_undef' { text.write_string('%chosen = select i1 true, <3 x i32> zeroinitializer, <3 x i32> %raw\n'); source = '%chosen' }
  if kind == 'composition' {
   text.write_string('%smax = call <3 x i32> @llvm.smax.v3i32(<3 x i32> %raw, <3 x i32> zeroinitializer)\n %umin = call <3 x i32> @llvm.umin.v3i32(<3 x i32> %smax, <3 x i32> <i32 2, i32 2, i32 2>)\n %umax = call <3 x i32> @llvm.umax.v3i32(<3 x i32> %umin, <3 x i32> <i32 2, i32 2, i32 2>)\n'); source = '%umax'
  }
  if kind == 'mask_consumer' { text.write_string('%mask = trunc <3 x i32> %raw to <3 x i1>\n %chosen = select <3 x i1> %mask, <3 x i32> %a, <3 x i32> %b\n'); source = '%chosen' }
  selector := if kind in ['left_poison', 'right_poison', 'result_freeze_poison', 'source_freeze_undef', 'right_freeze_undef', 'result_freeze_undef'] { '1' } else if kind == 'invalid_undef' { '3' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${source}, i32 ${selector}\n')
  if kind == 'shared' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i32> %raw, i32 %next\n %idx = add i32 %v, %other\n') }
  else { text.write_string('%idx = or i32 %v, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/extrema-controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for side in ['left', 'right', 'selector', 'nodes'] {
  f := fi(ir, 'depth_${side}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over, side; plan.free() } else { assert over, '${side}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
  valid := kind in ['defined', 'poison_ignored', 'result_freeze_poison', 'source_freeze_undef', 'right_freeze_undef', 'cold_good', 'composition', 'mask_consumer', 'shared']
  mut expected := actual.clone()
  if valid { expected[0] = 17; if kind != 'cold_good' { index := if kind in ['result_freeze_poison', 'source_freeze_undef', 'right_freeze_undef'] { 0 } else if kind == 'composition' { 2 } else if kind == 'shared' { 3 } else { 1 }; expected[index] = 42 } }
  check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); total++
  unsafe { actual.free(); expected.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut call := -1; mut selector := airbitcode.IRTypedOperand{}
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
  op := p.instructions[i]; code := stream.records[bodies.instructions[i].record].code
  if code == 34 { call = i }
  if code == 6 { selector = p.operands[op.operands_start + 1] }
 }
 assert call >= 0; saved := p.instructions[call]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 2}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, result_type: selector.type_index}] {
  p.instructions[call] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed vector extrema') }; total++
 }
 p.instructions[call] = saved
 for side in 0 .. 2 {
  slot := saved.operands_start + side + 1; source := p.operands[slot]; p.operands[slot] = selector
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed extrema argument') }; total++
  p.operands[slot] = source
 }
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn shift_controls(assembler string, root string) !int {
 mut text := strings.new_builder(65536)
 text.write_string('target datalayout = "e-p:64:64"\n declare <3 x i32> @llvm.sshl.sat.v3i32(<3 x i32>, <3 x i32>)\n declare <3 x i32> @llvm.ushl.sat.v3i32(<3 x i32>, <3 x i32>)\n')
 kinds := ['signed_defined', 'unsigned_defined', 'signed_positive_clamp', 'signed_negative_clamp', 'unsigned_clamp', 'zero_overshift', 'selected_overshift', 'ignored_overshift', 'result_freeze_overshift', 'scalar_freeze_overshift', 'source_freeze_overshift', 'right_freeze_undef', 'result_freeze_undef', 'right_undef', 'ignored_left_undef', 'invalid_selector', 'invalid_after_freeze', 'right_freeze_poison', 'shared_counts', 'mask_consumer']
 for kind in kinds {
  text.write_string('define void @${kind}(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out) { store i8 17, ptr %out\n')
  mut left := if kind == 'signed_positive_clamp' { '<i32 2147483647, i32 2, i32 3>' } else if kind == 'signed_negative_clamp' { '<i32 2147483648, i32 2, i32 3>' } else if kind == 'unsigned_clamp' { '<i32 4294967295, i32 2, i32 3>' } else if kind == 'zero_overshift' { 'zeroinitializer' } else if kind == 'ignored_left_undef' { '<i32 1, i32 undef, i32 3>' } else { '%a' }
  mut right := if kind == 'zero_overshift' { '<i32 32, i32 1, i32 1>' } else if kind.ends_with('overshift') || kind == 'invalid_after_freeze' { '<i32 1, i32 32, i32 0>' } else if kind in ['right_freeze_undef', 'result_freeze_undef', 'right_undef'] { '<i32 1, i32 undef, i32 0>' } else if kind == 'right_freeze_poison' { '<i32 1, i32 poison, i32 0>' } else { '<i32 1, i32 1, i32 1>' }
  if kind == 'source_freeze_overshift' { text.write_string('%left = freeze <3 x i32> ${left}\n'); left = '%left' }
  if kind in ['source_freeze_overshift', 'right_freeze_undef', 'right_freeze_poison'] { text.write_string('%right = freeze <3 x i32> ${right}\n'); right = '%right' }
  id := if kind.starts_with('unsigned') || kind == 'zero_overshift' { 'ushl' } else { 'sshl' }
  text.write_string('%raw = call <3 x i32> @llvm.${id}.sat.v3i32(<3 x i32> ${left}, <3 x i32> ${right})\n')
  mut source := '%raw'
  if kind in ['result_freeze_overshift', 'result_freeze_undef', 'invalid_after_freeze'] { text.write_string('%f = freeze <3 x i32> %raw\n'); source = '%f' }
  if kind == 'mask_consumer' { text.write_string('%mask = trunc <3 x i32> %raw to <3 x i1>\n %choice = select <3 x i1> %mask, <3 x i32> %a, <3 x i32> %b\n'); source = '%choice' }
  selector := if kind in ['selected_overshift', 'result_freeze_overshift', 'scalar_freeze_overshift', 'source_freeze_overshift', 'right_freeze_undef', 'right_freeze_poison'] { '1' } else if kind in ['invalid_selector', 'invalid_after_freeze'] { '3' } else { '%j' }
  text.write_string('%v = extractelement <3 x i32> ${source}, i32 ${selector}\n')
  mut value := '%v'
  if kind == 'scalar_freeze_overshift' { text.write_string('%sf = freeze i32 %v\n'); value = '%sf' }
  if kind == 'shared_counts' { text.write_string('%next = add i32 %j, 1\n %other = extractelement <3 x i32> %raw, i32 %next\n %sum = add i32 %v, %other\n'); value = '%sum' }
  text.write_string('%hi = lshr i32 ${value}, 26\n %lo = and i32 ${value}, 31\n %idx = xor i32 %hi, %lo\n %p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n ret void }\n')
 }
 data := assemble(assembler, root + '/shift-controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!
 for kind in kinds {
  f := fi(ir, kind); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
  valid := kind !in ['zero_overshift', 'selected_overshift', 'source_freeze_overshift', 'result_freeze_undef', 'right_undef', 'ignored_left_undef', 'invalid_selector', 'invalid_after_freeze']
  mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone()
  if valid { expected[0] = 17; index := if kind in ['result_freeze_overshift', 'scalar_freeze_overshift', 'signed_positive_clamp'] { 0 } else if kind in ['signed_negative_clamp', 'unsigned_clamp'] { 32 } else if kind == 'shared_counts' { 6 } else if kind == 'mask_consumer' { 4 } else { 2 }; expected[index] = 42 }
  av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free()
  unsafe { actual.free(); expected.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return kinds.len
}
fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := bit_controls(os.args[1], root)! + extrema_controls(os.args[1], root)! + shift_controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-SAT-SHIFT-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0; mut lane_checks := 0; mut substituted := 0
 for width in 1 .. 65 {
  counts := if width in [1, 8, 16, 32, 64] { []int{len: 16, init: index + 1} } else { [3] }
  for count in counts {
   typ := '<${count} x i${width}>'; mut text := strings.new_builder(262144); text.write_string('target datalayout = "e-p:64:64"\n')
   for op in 0 .. 2 {
    intrinsic := 'llvm.${operation(op)}.v${count}i${width}'
    text.write_string('declare ${typ} @${intrinsic}(${typ}, ${typ})\n define void @ref_${op}(ptr %in, ptr %other, ptr %out) {\n')
    for side in 0 .. 2 { for lane in 0 .. count {
     text.write_string('%p${side}_${lane} = getelementptr i64, ptr ${if side == 0 { '%in' } else { '%other' }}, i64 ${lane}\n %w${side}_${lane} = load i64, ptr %p${side}_${lane}, align 1\n %b${side}_${lane} = ${if width == 64 { 'or i64 %w' + side.str() + '_' + lane.str() + ', 0' } else { 'trunc i64 %w' + side.str() + '_' + lane.str() + ' to i' + width.str() }}\n %v${side}_${lane} = insertelement ${typ} ${if lane == 0 { 'zeroinitializer' } else { '%v' + side.str() + '_' + (lane - 1).str() }}, i${width} %b${side}_${lane}, i32 ${lane}\n')
    } }
    text.write_string('%raw = call ${typ} @${intrinsic}(${typ} %v0_${count - 1}, ${typ} %v1_${count - 1})\n')
    for lane in 0 .. count { text.write_string('%e${lane} = extractelement ${typ} %raw, i32 ${lane}\n %z${lane} = ${if width == 64 { 'or i64 %e' + lane.str() + ', 0' } else { 'zext i' + width.str() + ' %e' + lane.str() + ' to i64' }}\n %o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n') }
    text.write_string('ret void }\n')
    for sample in 0 .. 8 { for mode in 0 .. 4 { for selector_bits in [1, 32, 64] {
     text.write_string('define void @test_${op}_${sample}_${mode}_${selector_bits}(${typ} %a, ${typ} %b, i${selector_bits} %j, i1 %c, ptr %out) { store i8 17, ptr %out\n')
     if mode == 2 { for side in 0 .. 2 { text.write_string('%arg${side} = freeze ${typ} ${input_literal(width, count, sample, side)}\n') } }
     left := if mode == 0 { '%a' } else if mode == 2 { '%arg0' } else { input_literal(width, count, sample, 0) }
     right := if mode == 0 { '%b' } else if mode == 2 { '%arg1' } else { input_literal(width, count, sample, 1) }
     text.write_string('%raw = call ${typ} @${intrinsic}(${typ} ${left}, ${typ} ${right})\n')
     if mode == 3 { text.write_string('%f = freeze ${typ} %raw\n') }
     text.write_string('%r = extractelement ${typ} ${if mode == 3 { '%f' } else { '%raw' }}, i${selector_bits} %j\n')
     if mode == 2 && width > 1 { text.write_string('%high = lshr i${width} %r, ${width / 2}\n %fold = xor i${width} %r, %high\n') }
     text.write_string('%value = ${if mode == 3 { 'or i' + width.str() + ' %r, 0' } else { 'and i' + width.str() + if mode == 2 && width > 1 { ' %fold, ' } else { ' %r, ' } + (mask(width) & 63).str() }}\n %idx = ${if width == 64 { 'or i64 %value, 0' } else { 'zext i' + width.str() + ' %value to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n')
    } } }
   }
   dir := root + '/w${width}-n${count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
   stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
   for op in 0 .. 2 {
    reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + op.str()).str); assert reference != 0
    for sample in 0 .. 8 { for mode in 0 .. 4 {
     mut inputs := [16]u64{}; mut others := [16]u64{}; mut result := [16]u64{}; mut poisoned := [16]bool{}; mut hard_undef := false
     mut av := []u64{len: count}; mut bv := []u64{len: count}
     for lane in 0 .. count {
      mut a := sample_word(width, sample, lane, 0); mut b := sample_word(width, sample, lane, 1)
      av[lane] = a | ~mask(width); bv[lane] = b | ~mask(width)
      ka := if mode == 0 { 0 } else { input_kind(sample, lane, count, 0) }; kb := if mode == 0 { 0 } else { input_kind(sample, lane, count, 1) }
      if mode in [1, 3] && (ka == 2 || kb == 2) { hard_undef = true }
      if ka != 0 { a = 0 }; if kb != 0 { b = 0 }
      poisoned[lane] = mode in [1, 3] && (ka != 0 || kb != 0)
      if b >= u64(width) { poisoned[lane] = true; b = 0; substituted++ }
      inputs[lane] = a; others[lane] = b
     }
     unsafe { NativeCast(voidptr(reference))(&inputs[0], &others[0], &result[0]) }
     for lane in 0 .. count { assert result[lane] == reference_value(op, width, inputs[lane], others[lane]); lane_checks++ }
     for selector_bits in [1, 32, 64] {
      f := fi(ir, 'test_${op}_${sample}_${mode}_${selector_bits}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
      sm := mask(selector_bits); mut candidates := []u64{cap: count + 4}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
      for raw in candidates {
       j := raw & sm; poison := j >= u64(count) || (mode != 3 && poisoned[int(j)])
       word := if j >= u64(count) || poisoned[int(j)] { u64(0) } else { result[int(j)] }
       index := if mode == 3 { word } else if mode == 2 && width > 1 { (word ^ (word >> u32(width / 2))) & 63 } else { word & 63 }; valid := !hard_undef && !poison && index < 64
       mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
       jv := [j | ~sm]; cv := [u64(1)]
       mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
       check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
       if valid { accepted++ } else { refused++ }; if hard_undef { undefined++ }
       rows.writeln('${width} ${count} ${op} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${poison} ${index} ${valid} PASS')!
       unsafe { actual.free(); expected.free(); jv.free(); cv.free(); bindings.free() }
      }; unsafe { candidates.free() }; plan.free()
     }; unsafe { av.free(); bv.free() }
    } }
   }
   native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
  }
 }
 assert accepted + refused == 244608 && lane_checks == 54848
 line := 'AIR-VECTOR-SAT-SHIFT-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} whole-vector undef), ${lane_checks} native/oracle lane checks (${substituted} overshift substitutions), sshl/ushl.sat i1-i64, selector widths 1/32/64, count 3 plus all counts 1..16 for widths 1/8/16/32/64, eight operand pairs, four expression modes, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
