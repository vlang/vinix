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
fn operation(op int) string { return ['pext', 'pdep'][op] }
fn reference_value(op int, width int, a u64, b u64) u64 {
 mut rank:=0;mut result:=u64(0)
 for position in 0 .. width {
  if (b >> u32(position)) & 1 == 0 {continue}
  from:=if op==0 {position} else {rank};to:=if op==0 {rank} else {position}
  result |= ((a >> u32(from)) & 1) << u32(to);rank++
 };return result
}
fn permutation_controls(assembler string, root string) !int {
 mut text := strings.new_builder(131072)
 text.write_string('target datalayout = "e-p:64:64"\n')
 for id in ['pext', 'pdep'] { text.write_string('declare <3 x i32> @llvm.${id}.v3i32(<3 x i32>, <3 x i32>) #0\n') }
 text.write_string('attributes #0 = { nounwind memory(none) }\n')
 args := '(<3 x i32> %a, <3 x i32> %b, i32 %j, i1 %c, ptr %out)'
 for over in [false, true] { for side in ['left', 'right', 'selector', 'nodes'] {
  text.write_string('define void @depth_${side}_${over}${args} {\n')
  if side in ['left', 'right'] { for i in 0 .. 26 + int(over) {
   prev := if i == 0 { '%a' } else { '%s' + (i - 1).str() }
   text.write_string('%s${i} = select i1 %c, <3 x i32> ${prev}, <3 x i32> %b\n %v${i} = extractelement <3 x i32> %s${i}, i32 %j\n %p${i} = getelementptr i8, ptr %out, i32 %v${i}\n')
  } }
  if side == 'selector' { for i in 0 .. 28 + int(over) { prev := if i == 0 { '%j' } else { '%r' + (i - 1).str() }; text.write_string('%r${i} = or i32 ${prev}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n') } }
  text.write_string('%raw = call <3 x i32> @llvm.pext.v3i32(<3 x i32> ${if side == 'left' { '%s' + (25 + int(over)).str() } else { '%a' }}, <3 x i32> ${if side == 'right' { '%s' + (25 + int(over)).str() } else { '%b' }})\n')
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
  text.write_string('%raw = call <3 x i32> @llvm.pext.v3i32(<3 x i32> ${left}, <3 x i32> ${right})\n')
  mut source := '%raw'
  if kind in ['result_freeze_poison', 'result_freeze_undef'] { text.write_string('%f = freeze <3 x i32> %raw\n'); source = '%f' }
  if kind == 'unchosen_undef' { text.write_string('%chosen = select i1 true, <3 x i32> zeroinitializer, <3 x i32> %raw\n'); source = '%chosen' }
  if kind == 'composition' {
   text.write_string('%smax = call <3 x i32> @llvm.pdep.v3i32(<3 x i32> %raw, <3 x i32> zeroinitializer)\n %umin = call <3 x i32> @llvm.pext.v3i32(<3 x i32> %smax, <3 x i32> <i32 2, i32 2, i32 2>)\n %umax = call <3 x i32> @llvm.pdep.v3i32(<3 x i32> %umin, <3 x i32> <i32 2, i32 2, i32 2>)\n'); source = '%umax'
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
 data := assemble(assembler, root + '/permutation-controls', text.str())!; verify(data)!
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
  if valid { expected[0] = 17; if kind != 'cold_good' { index := if kind in ['result_freeze_poison', 'source_freeze_undef', 'right_freeze_undef'] { 0 } else if kind == 'mask_consumer' { 4 } else { 0 }; expected[index] = 42 } }
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
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed vector permutation') }; total++
 }
 p.instructions[call] = saved
 for side in 0 .. 2 {
  slot := saved.operands_start + side + 1; source := p.operands[slot]; p.operands[slot] = selector
  if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic('malformed permutation argument') }; total++
  p.operands[slot] = source
 }
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return total
}
fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};t:='<${count} x i16>';mut s:=strings.new_builder(16777216);s.write_string('declare ${t} @llvm.pext.v${count}i16(${t}, ${t})\n define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')}
 for i in 0..if storage&&over{4097}else{4096}{s.write_string('%n${i} = call ${t} @llvm.pext.v${count}i16(${t} zeroinitializer, ${t} zeroinitializer)\n')};if !storage{for i in 0..if over{50213}else{50212}{s.write_string('%x${i} = extractelement ${t} %n4095, i32 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage{'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'};f:=fi(ir,name)
 if over{if name=='memory'{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000){panic('memory limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output)}else if name=='void'{if _:=p.run_void_function(ir,stream,pools,bodies,f,[],70000){panic('void limit')}else{assert err.msg()==diagnostic,err.msg()}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],70000){panic('scalar limit')}else{assert err.msg()==diagnostic,err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],70000){panic('integer limit')}else{assert err.msg()==diagnostic,err.msg()}}}
 else{steps:=if storage{4097}else{54309};if name=='memory'{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000)!.steps==steps+1;assert output[0]==17}else if name=='void'{assert p.run_void_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}else{assert p.run_scalar_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps;assert p.run_integer_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}}
 unsafe{output.free();bs.free()};os.write_file(out+'/result.txt','AIR-VECTOR-BIT-PERMUTATION-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}
fn unchanged(data []u8) { for b in data { assert b == 0xcc } }
fn value_controls(assembler string, root string) !int {
 mut s:=strings.new_builder(131072);s.write_string('target datalayout = "e-p:64:64"\n')
 for width in [1,7,32,64] {
  t:='<1 x i${width}>';for op in ['pext','pdep'] {s.write_string('declare ${t} @llvm.${op}.v1i${width}(${t}, ${t}) #0\n')}
  for memory in [false,true] {for reverse in [false,true] {
   name:='chain_${width}_${memory}_${reverse}'
   s.write_string(if memory {'define void @${name}(i${width} %x, i${width} %m, ptr %out) { store i8 17, ptr %out\n'} else {'define i64 @${name}(i${width} %x, i${width} %m) {\n'})
   s.write_string('%a = insertelement ${t} zeroinitializer, i${width} %x, i32 0\n %b = insertelement ${t} zeroinitializer, i${width} %m, i32 0\n %first = call ${t} @llvm.${if reverse {'pdep'} else {'pext'}}.v1i${width}(${t} %a, ${t} %b)\n %back = call ${t} @llvm.${if reverse {'pext'} else {'pdep'}}.v1i${width}(${t} %first, ${t} %b)\n %r = extractelement ${t} %back, i32 0\n')
   s.write_string(if width==64 {'%wide = or i64 %r, 0\n'} else {'%wide = zext i${width} %r to i64\n'})
   s.write_string(if memory {'%p = getelementptr i8, ptr %out, i64 8\n store i64 %wide, ptr %p, align 1\n ret void }\n'} else {'ret i64 %wide }\n'})
  }}
  for op in ['pext','pdep'] {for side in [0,1] {for kind in ['poison','undef','source_freeze','result_freeze'] {
   name:='state_${width}_${op}_${side}_${kind}'
   s.write_string('define i64 @${name}() {\n')
   input:=if kind=='poison'||kind=='result_freeze' {'poison'} else {'undef'}
   if kind=='source_freeze' {s.write_string('%sf = freeze ${t} undef\n')}
   a:=if side==0 {if kind=='source_freeze' {'%sf'} else {input}} else {'zeroinitializer'}
   b:=if side==1 {if kind=='source_freeze' {'%sf'} else {input}} else {'zeroinitializer'}
   s.write_string('%v = call ${t} @llvm.${op}.v1i${width}(${t} ${a}, ${t} ${b})\n')
   if kind=='result_freeze' {s.write_string('%f = freeze ${t} %v\n')}
   s.write_string('%r = extractelement ${t} ${if kind=='result_freeze' {'%f'} else {'%v'}}, i32 0\n')
   s.write_string(if width==64 {'%wide = or i64 %r, 0\n'} else {'%wide = zext i${width} %r to i64\n'});s.write_string('ret i64 %wide }\n')
  }}}
 }
 for memory in [false,true] {s.write_string('define void @limit_${memory}(${if memory {'ptr %out'} else {''}}) {\n');if memory {s.write_string('store i8 17, ptr %out\n')};for i in 0..4097 {s.write_string('%v${i} = call <1 x i32> @llvm.pext.v1i32(<1 x i32> zeroinitializer, <1 x i32> zeroinitializer)\n')};s.write_string('ret void }\n')}
 s.write_string('attributes #0 = { nounwind memory(none) }\n')
 data:=assemble(assembler,root+'/value-controls',s.str())!;verify(data)!
 stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;mut p:=ir.typed_operands(stream,pools,bodies)!
 mut checks:=0
 for width in [1,7,32,64] {for reverse in [false,true] {
  f:=fi(ir,'chain_${width}_true_${reverse}');sf:=fi(ir,'chain_${width}_false_${reverse}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  for sample in 0..16 {
   args:=[sample_word(width,sample,0,0)|~mask(width),sample_word(width,sample,0,1)|~mask(width)]
   first:=reference_value(int(reverse),width,args[0],args[1]);value:=reference_value(1-int(reverse),width,first,args[1])
   a:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,100)!;b:=p.run_integer_function(ir,stream,pools,bodies,sf,args,100)!;assert !a.poison&&!b.poison&&a.value==value&&b.value==value;checks+=2
   for prepared in [false,true] {
    mut bytes:=[]u8{len:24,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:[args[0]]},airbitcode.IRMemoryBinding{values:[args[1]]},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
    if prepared {plan.run(mut bs,plan.steps())!} else {p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps())!}
    for i,v in bytes {assert v==if i==3 {u8(17)} else if i>=11&&i<19 {u8(value>>u32((i-11)*8))} else {u8(0xcc)}};checks++
    unsafe{bytes.free();bs[0].values.free();bs[1].values.free();bs.free()}
   };unsafe{args.free()}
  };plan.free()
 }}
 for width in [1,7,32,64] {for op in ['pext','pdep'] {for side in [0,1] {for kind in ['poison','undef','source_freeze','result_freeze'] {
  f:=fi(ir,'state_${width}_${op}_${side}_${kind}')
  if r:=p.run_scalar_function(ir,stream,pools,bodies,f,[],100) {assert kind!='undef'&&r.poison==(kind=='poison')&&(r.poison||r.value==0)} else {assert kind=='undef'}
  if r:=p.run_integer_function(ir,stream,pools,bodies,f,[],100) {assert kind!='undef'&&r.poison==(kind=='poison')&&(r.poison||r.value==0)} else {assert kind=='undef'};checks+=2
 }}}}
 for memory in [false,true] {f:=fi(ir,'limit_${memory}');mut bytes:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}];if memory {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,10000) {panic('slots')};assert bytes[0]==0xcc} else {if _:=p.run_void_function(ir,stream,pools,bodies,f,[],10000) {panic('slots')}};checks++;unsafe{bs.free()}}
 mut changed_functions:=ir.functions.clone();bad_ir:=airbitcode.IRModule{...ir,functions:changed_functions}
 mut declaration:=-1;for i,f in ir.functions {if f.name=='llvm.pdep.v1i32' {declaration=i;break}};assert declaration>=0
 for name in ['llvm.pext.v1i32','llvm.pdep.v1i31','llvm.pdep.v01i32','llvm.pdep.v1i32.spoof'] {
  changed_functions[declaration]=airbitcode.IRFunction{...ir.functions[declaration],name:name}
  mut bytes:=[]u8{len:24,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:[u64(1)]},airbitcode.IRMemoryBinding{values:[u64(1)]},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
  if _:=p.run_memory_function(bad_ir,stream,pools,bodies,fi(ir,'chain_32_true_false'),mut bs,100) {panic('duplicate or wrong overload')};unchanged(bytes)
  if _:=p.run_scalar_function(bad_ir,stream,pools,bodies,fi(ir,'chain_32_false_false'),[u64(1),1],100) {panic('scalar overload')};checks+=2
  unsafe{bytes.free();bs[0].values.free();bs[1].values.free();bs.free()}
 };unsafe{changed_functions.free()}
 for storage in [false,true] { for over in [false,true] { for name in ['memory','void'] { limits(assembler,root+'/limits-'+storage.str()+'-'+over.str()+'-'+name,storage,over,name)!;checks++ } } }
 p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()};return checks
}

fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; control_count := permutation_controls(os.args[1], root)! + value_controls(os.args[1], root)!
 if os.args.len == 4 { println('AIR-VECTOR-BIT-PERMUTATION-CONTROLS: ${control_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut accepted := 0; mut refused := 0; mut undefined := 0; mut lane_checks := 0
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
 assert accepted == 141781 && refused == 102827 && undefined == 45864 && lane_checks == 54848 && control_count == 696
 line := 'AIR-VECTOR-BIT-PERMUTATION: ${accepted} exact outputs, ${refused} prewrite refusals (${undefined} whole-vector undef), ${lane_checks} native/oracle lane checks, pext/pdep i1-i64, selector widths 1/32/64, count 3 plus all counts 1..16 for widths 1/8/16/32/64, eight operand pairs, four expression modes, ${control_count} controls and all three APIs PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
