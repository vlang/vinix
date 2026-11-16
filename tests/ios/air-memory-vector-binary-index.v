// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references extract only defined in-range lanes. V models invalid
// selectors, poison and address bounds before running either memory API.
import airbitcode
import os
import strings
import math.bits as mbits

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

fn flag_mask(op int) int { return match op { 0, 1, 2, 7 { 3 } 3, 4, 8, 9, 11 { 1 } else { 0 } } }
fn binary_text(op int, flags int) string {
 name := ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor'][op]
 suffix := if flags == 0 { '' } else if op in [0, 1, 2, 7] { if flags == 1 { ' nuw' } else if flags == 2 { ' nsw' } else { ' nuw nsw' } } else if op == 11 { ' disjoint' } else { ' exact' }
 return name + suffix
}
fn bad_flags(op int, flags u64, width int, a u64, b u64) bool {
 limit := mask(width); sign := u64(1) << u32(width - 1); x := a & limit; y := b & limit
 if op in [7, 8, 9] && y >= u64(width) { return true }
 if flags == 0 { return false }
 nx := x >= sign; ny := y >= sign
 mut unsigned := false; mut signed := false
 match op {
  0 { sum := x + y; unsigned = sum < x || sum > limit; signed = nx == ny && nx != ((sum & limit) >= sign) }
  1 { unsigned = x < y; signed = nx != ny && nx != (((x - y) & limit) >= sign) }
  2, 7 {
   high, low := mbits.mul_64(x, if op == 7 { u64(1) << y } else { y }); unsigned = high != 0 || low > limit
   mag_x := if nx { (~x & limit) + 1 } else { x }; mag_y := if op == 7 { u64(1) << y } else if ny { (~y & limit) + 1 } else { y }
   hi, lo := mbits.mul_64(mag_x, mag_y); negative := if op == 7 { nx } else { nx != ny }; signed = hi != 0 || lo > if negative { sign } else { sign - 1 }
  }
  3 { return (x / y) * y != x }
  4 { mx := if nx { (~x & limit) + 1 } else { x }; my := if ny { (~y & limit) + 1 } else { y }; return (mx / my) * my != mx }
  8, 9 { return x % (u64(1) << y) != 0 }
  11 { return ((x + y) & limit) != x | y }
  else {}
 }
 return (flags & 1 != 0 && unsigned) || (flags & 2 != 0 && signed)
}
fn sample_word(width int, sample int, side int, lane int, op int) u64 {
 sign := u64(1) << u32(width - 1)
 edges := [u64(0), 1, mask(width), sign, sign - 1, sign + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]!
 if side == 1 && op in [7, 8, 9] { shifts := [u64(0), 1, u64(width - 1), u64(width), u64(width + 1), 2, 63, ~u64(0)]!; return shifts[(sample + lane) % 8] & mask(width) }
 return edges[(sample + lane + side * 3) % 8] & mask(width)
}
fn input_kind(sample int, side int, lane int, count int) int {
 if (sample == 2 && side == 0 && lane == count - 1) || (sample == 5 && side == 1 && lane == count - 1) || (sample == 7 && side == 1) { return 2 }
 if (sample == 3 && side == 0 && lane == count - 1) || (sample == 4 && side == 1 && lane == count - 1) || (sample == 6 && side == 0) { return 1 }
 return 0
}
fn input_literal(width int, count int, sample int, side int, op int) string {
 mut lanes := []string{cap: count}
 for lane in 0 .. count { kind := input_kind(sample, side, lane, count); value := if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { sample_word(width, sample, side, lane, op).str() }; lanes << 'i${width} ${value}' }
 return '<' + lanes.join(', ') + '>'
}
fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] {
  for side in ['left', 'right', 'selector', 'freeze', 'nested'] {
   text.write_string('define void @depth_${side}_${over}${args} {\n')
   n := if side == 'nested' { 14 } else if side == 'selector' { if over { 29 } else { 28 } } else if over { 27 } else { 26 }
   if side in ['left', 'right'] { for i in 0 .. n { prev := if i == 0 { if side == 'left' { '%a' } else { '%b' } } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %a\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   if side == 'selector' { for i in 0 .. n { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
   if side == 'nested' {
    for i in 0 .. n { prev := if i == 0 { 'zeroinitializer' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = add <1 x i32> ${prev}, zeroinitializer\n %v${i} = extractelement <1 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
    text.write_string('%wide = zext i32 %v${n - 1} to i64\n')
    if over { text.write_string('%extra = or i64 %wide, 0\n') }
    text.write_string('%last = getelementptr i8, ptr %out, i64 ${if over { '%extra' } else { '%wide' }}\n ret void }\n'); continue
   }
   left := if side == 'left' { '%s' + (n - 1).str() } else { '%a' }; right := if side == 'right' { '%s' + (n - 1).str() } else { '%b' }
   text.write_string('%raw = add <3 x i32> ${left}, ${right}\n')
   if side == 'freeze' { for i in 0 .. n { prev := if i == 0 { '%raw' } else { '%f' + (i - 1).str() }; text.write_string('%f${i} = freeze <3 x i32> ${prev}\n %v${i} = extractelement <3 x i32> %f${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') } }
   text.write_string('%v = extractelement <3 x i32> ${if side == 'freeze' { '%f' + (n - 1).str() } else { '%raw' }}, i32 ${if side == 'selector' { '%r' + (n - 1).str() } else { '%j' }}\n %wide = zext i32 %v to i64\n %last = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
  }
  text.write_string('define void @nodes_${over}${args} { %s = add <3 x i32> %a, %b\n')
  for i in 0 .. if over { 242 } else { 241 } { text.write_string('%v${i} = extractelement <3 x i32> %s, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n')
 }
 kinds := ['defined', 'ignored_undef', 'invalid_undef', 'scalar_freeze_undef', 'result_freeze_undef', 'source_freeze_undef', 'select_ignored_undef', 'poison_neighbor', 'selected_poison', 'result_freeze_poison', 'division_zero', 'division_poison', 'signed_overflow', 'ignored_shift', 'selected_shift', 'old_after_freeze', 'root_before', 'root_after', 'cache_selectors', 'cold_bad', 'cold_good', 'loaded_source', 'comparison_source', 'loaded_scalar', 'phi_source', 'undef_selector', 'invalid_selector', 'outer_freeze', 'insert_repair', 'shuffle_source']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_source' { text.write_string('%left = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'comparison_source' { text.write_string('%unsupported_compare = icmp eq <3 x i32> %a, zeroinitializer\n %left = sext <3 x i1> %unsupported_compare to <3 x i32>\n') }
  if kind == 'loaded_scalar' { text.write_string('%loaded = load i32, ptr %out, align 1\n %left = insertelement <3 x i32> %a, i32 %loaded, i32 2\n') }
  if kind == 'phi_source' { text.write_string('br label %join\n join: %left = phi <3 x i32> [%a, %entry]\n') }
  if kind == 'insert_repair' { text.write_string('%left = insertelement <3 x i32> <i32 1, i32 undef, i32 3>, i32 2, i32 1\n') }
  if kind == 'shuffle_source' { text.write_string('%left = shufflevector <3 x i32> %a, <3 x i32> %b, <3 x i32> <i32 4, i32 0, i32 2>\n') }
  undef := kind in ['ignored_undef', 'invalid_undef', 'scalar_freeze_undef', 'result_freeze_undef', 'source_freeze_undef', 'select_ignored_undef', 'cold_bad']
  poison := kind in ['poison_neighbor', 'selected_poison', 'result_freeze_poison', 'division_poison', 'old_after_freeze', 'root_before', 'root_after']
  mut left := if undef { '<i32 1, i32 undef, i32 3>' } else if poison { '<i32 1, i32 poison, i32 3>' } else if kind == 'signed_overflow' { '<i32 1, i32 2147483648, i32 3>' } else if kind in ['loaded_source', 'comparison_source', 'loaded_scalar', 'phi_source', 'insert_repair', 'shuffle_source'] { '%left' } else { '%a' }
  if kind == 'source_freeze_undef' { text.write_string('%sf = freeze <3 x i32> ${left}\n'); left = '%sf' }
  right := if kind == 'division_zero' { '<i32 1, i32 0, i32 1>' } else if kind == 'signed_overflow' { '<i32 1, i32 4294967295, i32 1>' } else if kind in ['ignored_shift', 'selected_shift'] { '<i32 0, i32 32, i32 0>' } else { '<i32 1, i32 1, i32 1>' }
  op := if kind in ['division_zero', 'division_poison'] { 'udiv' } else if kind == 'signed_overflow' { 'srem' } else if kind in ['ignored_shift', 'selected_shift'] { 'shl' } else { 'add' }
  text.write_string('%raw = ${op} <3 x i32> ${left}, ${right}\n')
  if kind == 'root_before' { text.write_string('%bad = extractelement <3 x i32> %raw, i32 1\n %bp = getelementptr i8, ptr %out, i32 %bad\n') }
  frozen := kind in ['result_freeze_undef', 'result_freeze_poison', 'old_after_freeze', 'root_before', 'root_after']
  if frozen { text.write_string('%f = freeze <3 x i32> %raw\n') }
  if kind == 'select_ignored_undef' { text.write_string('%chosen = select i1 true, <3 x i32> %a, <3 x i32> %raw\n') }
  selector := if kind in ['selected_poison', 'result_freeze_poison', 'selected_shift', 'old_after_freeze'] { '1' } else if kind in ['invalid_selector', 'invalid_undef', 'outer_freeze'] { '3' } else if kind == 'undef_selector' { 'undef' } else { '%j' }
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
 for over in [false, true] { for name in ['depth_left', 'depth_right', 'depth_selector', 'depth_freeze', 'depth_nested', 'nodes'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over, name; plan.free() } else { assert over, '${name}: ${err}' }; total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; av := [u64(1), 2, 3]; bv := [u64(4), 5, 6]; jv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_source', 'comparison_source', 'loaded_scalar', 'phi_source', 'undef_selector'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported vector binary') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported vector binary ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['defined', 'source_freeze_undef', 'poison_neighbor', 'result_freeze_poison', 'ignored_shift', 'cache_selectors', 'cold_good', 'outer_freeze', 'insert_repair', 'shuffle_source']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_good' { expected[if kind in ['result_freeze_poison', 'outer_freeze'] { 0 } else if kind == 'cache_selectors' { 5 } else if kind == 'ignored_shift' { 1 } else if kind == 'shuffle_source' { 6 } else { 2 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }; total++; unsafe { actual.free(); av.free(); bv.free(); jv.free(); cv.free(); bindings.free() }
 }
 f := fi(ir, 'defined'); scope := bodies.scopes[f + 1]; mut binary := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 2 { binary = i; break } }
 assert binary >= 0; saved := p.instructions[binary]
 for changed in [airbitcode.IRTypedInstruction{...saved, flags: 4}, airbitcode.IRTypedInstruction{...saved, opcode: 99}, airbitcode.IRTypedInstruction{...saved, operands_count: 1}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, result_type: p.instructions[binary + 1].result_type}] {
  p.instructions[binary] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed vector binary') }; total++
 }
 p.instructions[binary] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-BINARY-INDEX-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0; mut division := 0
 for width in 1 .. 65 {
  counts := if width == 32 { []int{len: 16, init: index + 1} } else { [1, 2, 3, 16] }
  for count in counts {
   t := '<${count} x i${width}>'; mut text := strings.new_builder(1048576); text.write_string('target datalayout = "e-p:64:64"\n')
   for op in 0 .. 13 {
    text.write_string('define void @ref_${op}(ptr %in, ptr %unused, ptr %out) {\n')
    for side in 0 .. 2 { for lane in 0 .. count {
     text.write_string('%p${side}_${lane} = getelementptr i64, ptr %in, i64 ${side * 16 + lane}\n %w${side}_${lane} = load i64, ptr %p${side}_${lane}, align 1\n %b${side}_${lane} = ${if width == 64 { 'or i64 %w' + side.str() + '_' + lane.str() + ', 0' } else { 'trunc i64 %w' + side.str() + '_' + lane.str() + ' to i' + width.str() }}\n %v${side}_${lane} = insertelement ${t} ${if lane == 0 { 'zeroinitializer' } else { '%v' + side.str() + '_' + (lane - 1).str() }}, i${width} %b${side}_${lane}, i32 ${lane}\n')
    } }
    text.write_string('%raw = ${binary_text(op, 0)} ${t} %v0_${count - 1}, %v1_${count - 1}\n')
    for lane in 0 .. count { text.write_string('%e${lane} = extractelement ${t} %raw, i32 ${lane}\n %z${lane} = ${if width == 64 { 'or i64 %e' + lane.str() + ', 0' } else { 'zext i' + width.str() + ' %e' + lane.str() + ' to i64' }}\n %o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n') }
    text.write_string('ret void }\n')
    for flags in 0 .. flag_mask(op) + 1 { for sample in 0 .. 8 { for mode in 0 .. 3 { for selector_bits in [1, 32, 64] {
     name := '${op}_${flags}_${sample}_${mode}_${selector_bits}'
     text.write_string('define void @test_${name}(${t} %a, ${t} %b, i${selector_bits} %j, i1 %c, ptr %out) { store i8 17, ptr %out\n')
     left := input_literal(width, count, sample, 0, op); right := input_literal(width, count, sample, 1, op)
     if mode == 2 { text.write_string('%aa = freeze ${t} ${left}\n %bb = freeze ${t} ${right}\n') }
     text.write_string('%raw = ${binary_text(op, flags)} ${t} ${if mode == 0 { '%a, %b' } else if mode == 2 { '%aa, %bb' } else { left + ', ' + right }}\n')
     if mode == 1 { text.write_string('%f = freeze ${t} %raw\n') }
     text.write_string('%r = extractelement ${t} ${if mode == 1 { '%f' } else { '%raw' }}, i${selector_bits} %j\n')
     if mode == 2 { text.write_string('%high = lshr i${width} %r, ${width / 2}\n %fold = xor i${width} %r, %high\n') }
     text.write_string('%value = ${if mode == 1 { 'or i' + width.str() + ' %r, 0' } else { 'and i' + width.str() + ' ' + if mode == 2 { '%fold, ' } else { '%r, ' } + (mask(width) & 63).str() }}\n %idx = ${if width == 64 { 'or i64 %value, 0' } else { 'zext i' + width.str() + ' %value to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\n')
    } } } }
   }
   dir := root + '/i${width}-n${count}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
   stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
   for op in 0 .. 13 { reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + op.str()).str); assert reference != 0
    for flags in 0 .. flag_mask(op) + 1 { for sample in 0 .. 8 { for mode in 0 .. 3 {
     mut inputs := [32]u64{}; mut result := [16]u64{}; mut poisoned := [16]bool{}; mut hard_undef := false; mut hard_div := false
     mut av := []u64{len: count}; mut bv := []u64{len: count}
     for lane in 0 .. count {
      mut a := sample_word(width, sample, 0, lane, op); mut b := sample_word(width, sample, 1, lane, op)
      ak := if mode == 0 { 0 } else { input_kind(sample, 0, lane, count) }; bk := if mode == 0 { 0 } else { input_kind(sample, 1, lane, count) }
      av[lane] = a | ~mask(width); bv[lane] = b | ~mask(width)
      if mode == 2 { if ak != 0 { a = 0 }; if bk != 0 { b = 0 } }
      undef := mode == 1 && (ak == 2 || bk == 2); poison := mode == 1 && (ak == 1 || bk == 1)
      if undef { hard_undef = true }
      bad_div := op in [3, 4, 5, 6] && (undef || poison || b == 0 || (op in [4, 6] && a == u64(1) << u32(width - 1) && b == mask(width)))
      if bad_div { hard_div = true }
      poisoned[lane] = poison || undef || if bad_div { false } else { bad_flags(op, u64(flags), width, a, b) }
      if undef || poison { a = 0; b = if op in [3, 4, 5, 6] { 1 } else { 0 } }
      if bad_div { b = 1 }
      if op in [7, 8, 9] && b >= u64(width) { b = 0 }
      inputs[lane] = a; inputs[16 + lane] = b
     }
     unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
     for selector_bits in [1, 32, 64] {
      f := fi(ir, 'test_${op}_${flags}_${sample}_${mode}_${selector_bits}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
      sm := mask(selector_bits); mut candidates := []u64{cap: count + 4}; for j in 0 .. count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
      for raw in candidates {
       j := raw & sm; poison := j >= u64(count) || (mode != 1 && poisoned[int(j)])
       word := if j >= u64(count) || poisoned[int(j)] { u64(0) } else { result[int(j)] }
       index := if mode == 0 { word & 63 } else if mode == 2 { (word ^ (word >> u32(width / 2))) & 63 } else { word }
       valid := !hard_undef && !hard_div && !poison && index < 64
       mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
       jv := [j | ~sm]; cv := [u64(1)]
       mut bindings := [airbitcode.IRMemoryBinding{values: av}, airbitcode.IRMemoryBinding{values: bv}, airbitcode.IRMemoryBinding{values: jv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
       check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
       if valid { accepted++ } else { refused++ }; if hard_undef { undefined++ }; if hard_div { division++ }
       rows.writeln('${width} ${count} ${op} ${flags} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${hard_div} ${poison} ${index} ${valid} PASS')!
       unsafe { actual.free(); expected.free(); jv.free(); cv.free(); bindings.free() }
      }; unsafe { candidates.free() }; plan.free()
     }; unsafe { av.free(); bv.free() }
    } } }
   }
   native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
  }
 }
 assert accepted + refused == 5024160
 line := 'AIR-VECTOR-BINARY-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} whole-vector undef, ${division} division/remainder), all 64 lane widths, selector widths 1/32/64, counts 1/2/3/16 plus every count at i32, 13 opcodes, 30 flag variants, 8 operand patterns, 3 expression modes, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
