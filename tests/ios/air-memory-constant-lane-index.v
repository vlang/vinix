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
 untouched(bindings[2].data)
 for prepared in [false, true] {
  for j in 0 .. bindings[2].data.len { bindings[2].data[j] = 0xcc }
  if prepared { if _ := plan.run(mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid } else { assert !valid } }
  assert bindings[2].data == expected
 }
}

fn controls(assembler string, root string) !int {
 mut text := strings.new_builder(65536); text.write_string('target datalayout = "e-p:64:64"\n')
 args := '(i32 %s, i1 %c, ptr %out)'; vector := '<16 x i32>'; table := literal(32, 16, 0, false)
 for over in [false, true] {
  text.write_string('define void @nodes_${over}${args} {\n')
  for i in 0 .. if over { 240 } else { 239 } { text.write_string('%v${i} = extractelement ${vector} ${table}, i32 %s\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n') }
  text.write_string('ret void }\n define void @depth_${over}${args} {\n')
  n := if over { 30 } else { 29 }
  for i in 0 .. n { previous := if i == 0 { '%s' } else { '%s' + (i - 1).str() }; text.write_string('%s${i} = or i32 ${previous}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %s${i}\n') }
  text.write_string('%v = extractelement ${vector} ${table}, i32 %s${n - 1}\n %wide = zext i32 %v to i64\n %p = getelementptr i8, ptr %out, i64 %wide\n ret void }\n')
 }
 kinds := ['root_before', 'root_after', 'cold_undef', 'cold_defined', 'ignored_undef', 'frozen_undef', 'invalid_undef', 'poison_undef', 'shared', 'scalar_cache', 'loaded_selector', 'loaded_vector', 'constructed_vector']
 for kind in kinds {
  text.write_string('define void @${kind}${args} { entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') { text.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  if kind == 'loaded_selector' { text.write_string('%loaded = load i32, ptr %out, align 1\n') }
  if kind == 'loaded_vector' { text.write_string('%vec = load <3 x i32>, ptr %out, align 1\n') }
  if kind == 'constructed_vector' { text.write_string('%vec = insertelement <3 x i32> zeroinitializer, i32 0, i32 1\n') }
  value := if kind in ['root_before', 'root_after'] { '<i32 poison, i32 undef, i32 3>' } else if kind in ['invalid_undef', 'poison_undef'] { 'undef' } else if kind in ['loaded_vector', 'constructed_vector'] { '%vec' } else { '<i32 2, i32 undef, i32 1>' }
  selector := if kind in ['root_before', 'root_after'] { '0' } else if kind in ['cold_undef', 'ignored_undef', 'frozen_undef'] { '1' } else if kind == 'invalid_undef' { '3' } else if kind == 'poison_undef' { 'poison' } else if kind == 'loaded_selector' { '%loaded' } else { '%s' }
  text.write_string('%v = extractelement <3 x i32> ${value}, i32 ${selector}\n')
  if kind == 'root_before' { text.write_string('%bad = getelementptr i8, ptr %out, i32 %v\n') }
  if kind == 'ignored_undef' { text.write_string('%fixed = select i1 false, i32 %v, i32 0\n') }
  else { text.write_string('%fixed = freeze i32 %v\n') }
  if kind == 'shared' { text.write_string('%neighbor = extractelement <3 x i32> <i32 2, i32 undef, i32 1>, i32 2\n %idx = add i32 %fixed, %neighbor\n') }
  else if kind == 'scalar_cache' { text.write_string('%idx = add i32 %fixed, 2\n') }
  else { text.write_string('%idx = or i32 %fixed, 0\n') }
  text.write_string('%p = getelementptr i8, ptr %out, i32 %idx\n store i8 42, ptr %p\n')
  if kind == 'root_after' { text.write_string('%bad = getelementptr i8, ptr %out, i32 %v\n') }
  if kind.starts_with('cold') { text.write_string('br label %exit\n exit:\n') }
  text.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', text.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; mut p := ir.typed_operands(stream, pools, bodies)!
 mut total := 0
 for over in [false, true] { for name in ['nodes', 'depth'] {
  f := fi(ir, '${name}_${over}')
  if plan := p.prepare_memory_function(ir, stream, pools, bodies, f) { assert !over; plan.free() } else { assert over, '${name}: ${err}' }
  total++
 } }
 for kind in kinds {
  f := fi(ir, kind); mut actual := []u8{len: 64, init: 0xcc}; sv := [u64(0)]; cv := [u64(1)]
  mut bindings := [airbitcode.IRMemoryBinding{values: sv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if kind in ['loaded_selector', 'loaded_vector', 'constructed_vector'] {
   if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('unsupported literal address dependency') }
   if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 4096) { panic('unsupported literal address ran') }; untouched(actual)
  } else {
   plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
   valid := kind in ['cold_defined', 'invalid_undef', 'poison_undef', 'shared', 'scalar_cache']
   mut expected := actual.clone()
   if valid { expected[0] = 17; if kind != 'cold_defined' { expected[if kind == 'shared' { 3 } else if kind == 'scalar_cache' { 4 } else { 0 }] = 42 } }
   check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!; plan.free(); unsafe { expected.free() }
  }
  total++; unsafe { actual.free(); sv.free(); cv.free(); bindings.free() }
 }
 // Corrupt constant-source identity and element type in a decoded extraction.
 f := fi(ir, 'shared'); scope := bodies.scopes[f + 1]
 mut extract := -1
 for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code == 6 { extract = i; break } }
 assert extract >= 0
 start := p.instructions[extract].operands_start; saved := p.operands[start]
 for changed in [airbitcode.IRTypedOperand{number: saved.number, type_index: p.operands[start + 1].type_index}, airbitcode.IRTypedOperand{number: p.operands[start + 1].number, type_index: saved.type_index}] {
  p.operands[start] = changed
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed constant vector type') }; total++
 }
 p.operands[start] = saved
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}

fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!
 control_count := controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-CONSTANT-LANE-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0
 for width in 1 .. 65 {
  counts := if width == 32 { []int{len: 16, init: index + 1} } else { [1, 2, 3, 16] }
  wide := if width == 64 { 'or i64 %value, 0' } else { 'zext i${width} %value to i64' }
  mut text := strings.new_builder(524288); text.write_string('target datalayout = "e-p:64:64"\n')
  for count in counts { for state in 0 .. 8 {
   vector := '<${count} x i${width}>'; actual := literal(width, count, state, false); safe := literal(width, count, state, true)
   text.write_string('define void @ref_${count}_${state}(ptr %unused, ptr %selector, ptr %out) { %s = load i64, ptr %selector, align 1\n %value = extractelement ${vector} ${safe}, i64 %s\n %wide = ${wide}\n store i64 %wide, ptr %out, align 1\n ret void }\n')
   for selector_bits in [1, 32, 64] { for mode in 0 .. 7 {
    typ := 'i${selector_bits}'
    text.write_string('define void @test_${count}_${state}_${selector_bits}_${mode}(${typ} %s, i1 %c, ptr %out) { store i8 17, ptr %out\n')
    if mode == 4 { text.write_string('%j = select i1 %c, ${typ} %s, ${typ} poison\n') }
    if mode == 5 { text.write_string('%j = add ${typ} %s, 1\n') }
    selector := if mode in [4, 5] { '%j' } else if mode == 6 { '0' } else { '%s' }
    text.write_string('%r = extractelement ${vector} ${actual}, ${typ} ${selector}\n')
    if mode in [2, 4, 6] { text.write_string('%value = freeze i${width} %r\n') }
    else if mode in [3, 5] { text.write_string('%value = select i1 %c, i${width} %r, i${width} 0\n') }
    else { text.write_string('%value = or i${width} %r, 0\n') }
    if mode == 0 { text.write_string('%p = getelementptr i8, ptr %out, i${width} %value\n') }
    else if mode == 2 { text.write_string('%limited = and i${width} %value, ${mask(width) & 63}\n %idx = ${if width == 64 { 'or i64 %limited, 0' } else { 'zext i${width} %limited to i64' }}\n %p = getelementptr i8, ptr %out, i64 %idx\n') }
    else { text.write_string('%idx = ${wide}\n %p = getelementptr i8, ptr %out, i64 %idx\n') }
    text.write_string('store i8 42, ptr %p\n ret void }\n')
   } }
  } }
  dir := root + '/i${width}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
  stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
  for count in counts { for state in 0 .. 8 {
   reference := C.LLVMGetFunctionAddress(native.engine, ('ref_${count}_${state}').str); assert reference != 0
   for selector_bits in [1, 32, 64] { for mode in 0 .. 7 {
    f := fi(ir, 'test_${count}_${state}_${selector_bits}_${mode}'); plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
    sm := mask(selector_bits); mut candidates := []u64{cap: 21}; for j in 0 .. 18 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1), ~u64(0)]
    for condition in [false, true] { for raw in candidates {
     s := raw & sm; selector := if mode == 5 { (s + 1) & sm } else if mode == 6 { u64(0) } else { s }
     index_poison := selector >= u64(count) || (mode == 4 && !condition)
     safe := [if index_poison { u64(0) } else { selector }]!; mut result := [u64(0)]!
     unsafe { NativeCast(voidptr(reference))(&safe[0], &safe[0], &result[0]) }
     native_kind := lane_state(state, int(safe[0])); assert result[0] == if native_kind == 0 { lane_word(width, state, int(safe[0])) } else { u64(0) }
     kind := if index_poison { 1 } else { lane_state(state, int(selector)) }
     undef := kind == 2; mut poison := kind == 1; mut value := result[0]
     if mode in [2, 4, 6] && poison { value = 0; poison = false }
     if mode in [3, 5] && !condition { value = 0; poison = false }
     index := if mode == 2 { value & 63 } else { value }
     valid := !undef && !poison && index < 64 && (mode != 0 || index & (u64(1) << u32(width - 1)) == 0)
     mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone(); if valid { expected[0] = 17; expected[int(index)] = 42 }
     sv := [s | ~sm]; cv := [u64(condition) | ~u64(1)]
     mut bindings := [airbitcode.IRMemoryBinding{values: sv}, airbitcode.IRMemoryBinding{values: cv}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
     check(p, ir, stream, pools, bodies, f, plan, mut bindings, expected, valid)!
     if valid { accepted++ } else { refused++ }; if undef { undefined++ }
     rows.writeln('${width} ${count} ${state} ${selector_bits} ${mode} ${condition} ${s} ${selector} ${kind} ${index} ${valid} PASS')!
     unsafe { actual.free(); expected.free(); sv.free(); cv.free(); bindings.free() }
    } }; unsafe { candidates.free() }; plan.free()
   } }
  } }
  native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 }
 assert accepted + refused == 1891008
 line := 'AIR-CONSTANT-LANE-INDEX: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} selected undef), all 64 lane widths, selector widths 1/32/64, lengths 1/2/3/16 plus all lengths at i32, 8 lane patterns, 7 expression patterns, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
