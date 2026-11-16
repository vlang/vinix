// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references use defined replacement lanes. V independently models
// poison, undef and freeze, then checks both memory APIs' write ordering.
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

fn width(element int) int { return element + 1 }
fn typ(element int) string { return 'i'+width(element).str() }
fn word(element int, sample int, lane int) u64 {
 return [u64(0), 1, ~u64(0), u64(1) << u32(width(element) - 1), 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15, 0x0123456789abcdef, 0x80017c017f800001]![(sample + lane) % 8] & mask(width(element))
}
fn state(sample int, lane int, count int) int {
	if (sample == 2 && lane == count - 1) || sample == 7 { return 2 }
	if (sample == 3 && lane == count - 1) || sample == 6 { return 1 }
	return 0
}
fn scalar_literal(element int, value u64) string { return (value & mask(width(element))).str() }
fn literal(element int, count int, sample int, defined bool) string {
	mut lanes := []string{cap: count}
	for lane in 0 .. count {
		kind := if defined { 0 } else { state(sample, lane, count) }
		lanes << typ(element) + ' ' + if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { scalar_literal(element, word(element, sample, lane)) }
	}
	return '<' + lanes.join(', ') + '>'
}
fn expected_lane(words [16]u64, source_bits int, bits int, lane int) u64 {
	mut stream := [1024]u8{}
	for i in 0 .. 16 { for bit in 0 .. source_bits { stream[i * source_bits + bit] = u8(words[i] >> u32(bit) & 1) } }
	mut result := u64(0)
	for bit in 0 .. bits { if stream[lane * bits + bit] == 1 { result |= u64(1) << u32(bit) } }
	return result
}
fn scalar_to_bits(element int, input string, output string) string { return if element < 64 { '%${output} = or i${width(element)} ${input}, 0\n' } else { '%${output} = bitcast ${typ(element)} ${input} to i${width(element)}\n' } }
fn bits_to_scalar(element int, input string, output string) string { return if element < 64 { '%${output} = or i${width(element)} ${input}, 0\n' } else { '%${output} = bitcast i${width(element)} ${input} to ${typ(element)}\n' } }
fn widen(bits int, input string, output string) string { return '%${output} = ' + if bits == 64 { 'or i64 ${input}, 0\n' } else { 'zext i${bits} ${input} to i64\n' } }

// A failed address validation must leave even the preceding marker untouched.
fn memory_check(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, f int, plan &airbitcode.IRPreparedMemoryFunction, mut bindings []airbitcode.IRMemoryBinding, undefined bool, poison bool, index u64) ! {
 valid := !undefined && !poison && index < 64
 for prepared in [false, true] {
  for i in 0 .. bindings[2].data.len { bindings[2].data[i] = 0xcc }
  if _ := plan.validate(bindings, plan.steps()) { assert valid, ir.functions[f].name } else { assert !valid, ir.functions[f].name + ': ' + err.msg() }
  for b in bindings[2].data { assert b == 0xcc }
  if prepared { if r := plan.run(mut bindings, plan.steps()) { assert valid && r.steps == plan.steps() } else { assert !valid, ir.functions[f].name + ': ' + err.msg() } }
  else { if r := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, plan.steps()) { assert valid && r.steps == plan.steps() } else { assert !valid, ir.functions[f].name + ': ' + err.msg() } }
  for i, b in bindings[2].data { assert b == if valid && i == int(index) + 3 { u8(42) } else if valid && i == 3 { u8(17) } else { u8(0xcc) }, '${ir.functions[f].name} byte=${i}' }
 }
}

fn controls(assembler string, root string) !int {
 mut s := strings.new_builder(131072); s.write_string('target datalayout = "e-p:64:64"\n')
 names := ['pack', 'split', 'split_argument', 'pack_argument', 'source_freeze', 'result_freeze', 'roundtrip_poison', 'roundtrip_freeze', 'cold_undef', 'unchosen_undef', 'insert_repair', 'shuffle', 'binary', 'select', 'cache_selectors', 'root_before', 'root_after', 'loaded_scalar', 'loaded_vector', 'phi_scalar', 'phi_vector', 'floating_pack', 'floating_split', 'negative', 'out_of_bounds', 'freeze_scalar_undef', 'scalar_undef']
 for name in names {
  s.write_string('define void @${name}(i32 %seed, <4 x i8> %lanes, i32 %j, i1 %c, ptr %out) { entry: store i8 17, ptr %out\n')
  if name == 'cold_undef' { s.write_string('br i1 true, label %exit, label %cold\n cold:\n') }
  split := name in ['split', 'split_argument', 'loaded_scalar', 'phi_scalar', 'floating_split', 'freeze_scalar_undef', 'scalar_undef']
  if name == 'loaded_scalar' { s.write_string('%input = load i32, ptr %out, align 1\n') }
  if name == 'phi_scalar' { s.write_string('br label %join\n join: %input = phi i32 [1, %entry]\n') }
  if name == 'floating_split' { s.write_string('%fp = bitcast i32 %seed to float\n %input = bitcast float %fp to i32\n') }
  if name == 'freeze_scalar_undef' { s.write_string('%input = freeze i32 undef\n') }
  if split {
   input := if name == 'split_argument' { '%seed' } else if name == 'scalar_undef' { 'undef' } else if name in ['loaded_scalar','phi_scalar','floating_split','freeze_scalar_undef'] { '%input' } else { '67305985' }
   s.write_string('%v = bitcast i32 ${input} to <4 x i8>\n %e = extractelement <4 x i8> %v, i32 %j\n %raw = zext i8 %e to i32\n')
  } else {
   mut input := '<i8 1, i8 0, i8 0, i8 0>'
   if name in ['source_freeze', 'cold_undef', 'unchosen_undef'] { input = '<i8 1, i8 0, i8 undef, i8 0>' }
   if name in ['result_freeze','roundtrip_poison','roundtrip_freeze','root_before','root_after'] { input = '<i8 1, i8 0, i8 poison, i8 0>' }
   if name == 'negative' { input = '<i8 0, i8 0, i8 0, i8 128>' }
   if name == 'out_of_bounds' { input = '<i8 64, i8 0, i8 0, i8 0>' }
   if name == 'pack_argument' { input = '%lanes' }
   if name == 'source_freeze' { s.write_string('%sf = freeze <4 x i8> ${input}\n'); input = '%sf' }
   if name == 'insert_repair' { s.write_string('%sf = insertelement <4 x i8> <i8 1, i8 0, i8 undef, i8 0>, i8 0, i32 2\n'); input = '%sf' }
   if name == 'shuffle' { s.write_string('%sf = shufflevector <4 x i8> <i8 1, i8 0, i8 0, i8 0>, <4 x i8> undef, <4 x i32> <i32 0, i32 1, i32 2, i32 3>\n'); input = '%sf' }
   if name == 'binary' { s.write_string('%sf = add <4 x i8> <i8 1, i8 0, i8 0, i8 0>, zeroinitializer\n'); input = '%sf' }
   if name == 'select' { s.write_string('%sf = select i1 %c, <4 x i8> <i8 1, i8 0, i8 0, i8 0>, <4 x i8> undef\n'); input = '%sf' }
   if name == 'loaded_vector' { s.write_string('%sf = load <4 x i8>, ptr %out, align 1\n'); input = '%sf' }
   if name == 'phi_vector' { s.write_string('br label %join\n join: %sf = phi <4 x i8> [zeroinitializer, %entry]\n'); input = '%sf' }
   if name == 'floating_pack' { s.write_string('%sf = bitcast <2 x half> zeroinitializer to <4 x i8>\n'); input = '%sf' }
   s.write_string('%packed = bitcast <4 x i8> ${input} to i32\n')
   if name in ['root_before','root_after'] { s.write_string('%safe = freeze i32 %packed\n') }
   if name == 'root_before' { s.write_string('%bad = getelementptr i8, ptr %out, i32 %packed\n') }
   if name in ['result_freeze','roundtrip_freeze'] { s.write_string('%f = freeze i32 %packed\n') }
   if name == 'unchosen_undef' { s.write_string('%f = select i1 true, i32 1, i32 %packed\n') }
   if name.starts_with('roundtrip') || name == 'cache_selectors' {
    s.write_string('%v = bitcast i32 ${if name == 'roundtrip_freeze' { '%f' } else { '%packed' }} to <4 x i8>\n %e = extractelement <4 x i8> %v, i32 %j\n %raw = zext i8 %e to i32\n')
    if name == 'cache_selectors' { s.write_string('%e2 = extractelement <4 x i8> %v, i32 1\n %p2 = getelementptr i8, ptr %out, i8 %e2\n') }
   } else { s.write_string('%raw = or i32 ${if name in ['root_before','root_after'] { '%safe' } else if name in ['result_freeze','unchosen_undef'] { '%f' } else { '%packed' }}, 0\n') }
  }
  s.write_string('%p = getelementptr i8, ptr %out, i32 %raw\n store i8 42, ptr %p\n')
  if name == 'root_after' { s.write_string('%bad = getelementptr i8, ptr %out, i32 %packed\n') }
  if name == 'cold_undef' { s.write_string('br label %exit\n exit:\n') }
  s.write_string('ret void }\n')
 }
 data := assemble(assembler, root + '/controls', s.str())!; verify(data)!
 stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream,pools)!; mut p := ir.typed_operands(stream,pools,bodies)!
 mut checks := 0
 for name in names {
  f := fi(ir,name); mut bytes := []u8{len: 64, init: 0xcc}; mut expected := bytes.clone()
  mut bindings := [airbitcode.IRMemoryBinding{values: [u64(67305985)]}, airbitcode.IRMemoryBinding{values: [u64(1), 0, 0, 0]}, airbitcode.IRMemoryBinding{values: [u64(0)]}, airbitcode.IRMemoryBinding{values: [u64(1)]}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]
  static_bad := name in ['loaded_scalar','loaded_vector','phi_scalar','phi_vector','floating_pack','floating_split','scalar_undef']
  if static_bad { if _ := p.prepare_memory_function(ir,stream,pools,bodies,f) { panic(name) }; if _ := p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,100) { panic(name) }; for b in bytes { assert b == 0xcc }; checks++; unsafe { bytes.free(); expected.free(); for b in bindings { b.values.free() }; bindings.free() }; continue }
  plan := p.prepare_memory_function(ir,stream,pools,bodies,f)!
  valid := name !in ['roundtrip_poison','cold_undef','unchosen_undef','root_before','root_after','negative','out_of_bounds']
  index := if name in ['result_freeze','roundtrip_freeze','freeze_scalar_undef'] { 0 } else { 1 }
  if valid { expected[0]=17; expected[index]=42 }
  for prepared in [false,true] {
   for i in 0 .. bytes.len { bytes[i]=0xcc }
   if _ := plan.validate(bindings,plan.steps()) { assert valid,name } else { assert !valid,name + ': ' + err.msg() }; for b in bytes { assert b==0xcc }
   if prepared { if _ := plan.run(mut bindings,plan.steps()) { assert valid,name } else { assert !valid,name + ': ' + err.msg() } }
   else { if _ := p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,plan.steps()) { assert valid,name } else { assert !valid,name + ': ' + err.msg() } }
   assert bytes==expected,name; checks++
  }
  plan.free(); unsafe { bytes.free(); expected.free(); for b in bindings { b.values.free() }; bindings.free() }
 }
 for name in ['pack','split'] {
  f:=fi(ir,name); scope:=bodies.scopes[f+1]; mut cast := -1
  for i in scope.instructions_start .. scope.instructions_start + scope.instructions_count { if stream.records[bodies.instructions[i].record].code==3 { cast=i; break } }
  assert cast>=0; saved:=p.instructions[cast]
  for op in [airbitcode.IRTypedInstruction{...saved,flags:1}, airbitcode.IRTypedInstruction{...saved,indices_count:1}, airbitcode.IRTypedInstruction{...saved,targets_count:1}, airbitcode.IRTypedInstruction{...saved,operands_count:2}, airbitcode.IRTypedInstruction{...saved,is_volatile:true}] { p.instructions[cast]=op; if _ := p.prepare_memory_function(ir,stream,pools,bodies,f) { panic('metadata') }; checks++ }
  p.instructions[cast]=saved
  big:=airbitcode.IRModule{...ir,data_layout:'E-p:64:64'}; if _ := p.prepare_memory_function(big,stream,pools,bodies,f) { panic('big endian') }; checks++
 }
 p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
 return checks
}

// Cache shallow roots first, then reuse their full heights under a cast.
// Separate star-shaped copy/extract graphs exercise exactly 256 nodes.
fn graph_limits(assembler string, root string) !int {
 mut s := strings.new_builder(131072); s.write_string('target datalayout = "e-p:64:64"\n')
 for side in ['split', 'pack'] { for nodes in [false,true] { for over in [false,true] {
  s.write_string('define void @${side}_${nodes}_${over}(i32 %seed, <4 x i8> %lanes, i32 %j, i1 %cond, ptr %out) { store i8 17, ptr %out\n')
  if nodes {
   if side=='split' {
    s.write_string('%v = bitcast i32 %seed to <4 x i8>\n')
    for i in 0 .. if over {249} else {248} { s.write_string('%e${i} = extractelement <4 x i8> %v, i32 %j\n %p${i} = getelementptr i8, ptr %out, i8 %e${i}\n') }
   } else {
    s.write_string('%p = bitcast <4 x i8> %lanes to i32\n')
    for i in 0 .. if over {243} else {242} { s.write_string('%c${i} = or i32 %p, 0\n %q${i} = getelementptr i8, ptr %out, i32 %c${i}\n') }
   }
  } else {
   n:=if over {29} else {28}
   for i in 0 .. n {
    prev:=if i==0 {if side=='split' {'%seed'} else {'%lanes'}} else {'%s'+(i-1).str()}
    if side=='split' { s.write_string('%s${i} = select i1 %cond, i32 ${prev}, i32 0\n %q${i} = getelementptr i8, ptr %out, i32 %s${i}\n') }
    else {s.write_string('%s${i} = select i1 %cond, <4 x i8> ${prev}, <4 x i8> zeroinitializer\n %e${i} = extractelement <4 x i8> %s${i}, i32 %j\n %q${i} = getelementptr i8, ptr %out, i8 %e${i}\n')}
   }
   if side=='split' {s.write_string('%v = bitcast i32 %s${n-1} to <4 x i8>\n %e = extractelement <4 x i8> %v, i32 %j\n %p = getelementptr i8, ptr %out, i8 %e\n')}
   else {s.write_string('%v = bitcast <4 x i8> %s${n-1} to i32\n %p = getelementptr i8, ptr %out, i32 %v\n')}
  }
  s.write_string('ret void }\n')
 } } }
 data:=assemble(assembler,root+'/graph-limits',s.str())!; verify(data)!
 stream:=airbitcode.parse(data)!; ir:=stream.ir_module(data)!; pools:=ir.constant_pools(stream)!; bodies:=ir.function_bodies(stream,pools)!; p:=ir.typed_operands(stream,pools,bodies)!
 mut checks:=0
 for side in ['split','pack'] {for nodes in [false,true] {for over in [false,true] {
  name:='${side}_${nodes}_${over}'; f:=fi(ir,name)
  mut bytes:=[]u8{len:64,init:0xcc}; mut bindings:=[airbitcode.IRMemoryBinding{values:[u64(0)]},airbitcode.IRMemoryBinding{values:[u64(0),0,0,0]},airbitcode.IRMemoryBinding{values:[u64(0)]},airbitcode.IRMemoryBinding{values:[u64(1)]},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
  if plan:=p.prepare_memory_function(ir,stream,pools,bodies,f) {
   assert !over,name
   plan.validate(bindings,plan.steps())!; for b in bytes {assert b==0xcc}
   plan.run(mut bindings,plan.steps())!; assert bytes[0]==17
   for b in bytes[1..] {assert b==0xcc}; plan.free()
  } else {assert over,name+': '+err.msg(); assert err.msg().contains(if nodes {'limit'} else {'depth'}),err.msg(); if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,1000) {panic('graph limit')}; for b in bytes {assert b==0xcc}}
  checks++; unsafe {bytes.free();for b in bindings {b.values.free()};bindings.free()}
 }}}
 p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
 return checks
}

fn main() {
 assert os.args.len in [3, 4]
 root := os.abs_path(os.args[2]); assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
 os.mkdir_all(root)!; controls_count := controls(os.args[1], root + '/controls')! + graph_limits(os.args[1], root)!
 if os.args.len == 4 { println('AIR-SCALAR-VECTOR-BITCAST-INDEX-CONTROLS: ${controls_count} PASS'); return }
 mut rows := os.create(root + '/comparisons.txt')!; defer { rows.close() }
 mut shapes := 0; mut values := 0; mut poison := 0; mut undefined := 0; mut native_checks := 0; mut scalar_checks := 0; mut budgets := 0; mut bounds := 0; mut static_refusals := 0
 for scalar in 0 .. 64 { for vector in 0 .. 64 {
  total := width(scalar); lane_bits := width(vector)
  if total % lane_bits != 0 || total / lane_bits > 16 { continue }
  count := total / lane_bits
  for split in [false, true] {
   source := if split { scalar } else { vector }; dest := if split { vector } else { scalar }
   source_count := if split { 1 } else { count }; result_count := if split { count } else { 1 }
   source_bits := width(source); bits := width(dest)
   input_type := if split { typ(source) } else { '<${count} x ${typ(source)}>' }; output_type := if split { '<${count} x ${typ(dest)}>' } else { typ(dest) }
   shapes++
   mut text := strings.new_builder(131072); text.write_string('target datalayout = "e-p:64:64"\n define void @reference(ptr %in, ptr %unused, ptr %out) {\n')
   for lane in 0 .. source_count {
    text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = ${if source_bits == 64 { 'or i64 %w' + lane.str() + ', 0' } else { 'trunc i64 %w' + lane.str() + ' to i' + source_bits.str() }}\n' + bits_to_scalar(source, '%b' + lane.str(), 's' + lane.str()))
    if !split { text.write_string('%v${lane} = insertelement ${input_type} ${if lane == 0 { 'zeroinitializer' } else { '%v' + (lane - 1).str() }}, ${typ(source)} %s${lane}, i32 ${lane}\n') }
   }
   text.write_string('%raw = bitcast ${input_type} ${if split { '%s0' } else { '%v' + (source_count - 1).str() }} to ${output_type}\n')
   for lane in 0 .. result_count {
    if split { text.write_string('%e${lane} = extractelement ${output_type} %raw, i32 ${lane}\n') }
    text.write_string(scalar_to_bits(dest, if split { '%e' + lane.str() } else { '%raw' }, 'b_out' + lane.str()) + widen(bits, '%b_out' + lane.str(), 'z' + lane.str()) + '%o${lane} = getelementptr i64, ptr %out, i64 ${lane}\n store i64 %z${lane}, ptr %o${lane}, align 1\n')
   }
   text.write_string('ret void }\n')
   for sample in 0 .. 8 { for mode in 0 .. 4 { for selector_bits in [1, 32, 64] { for memory in [false, true] {
    name := '${sample}_${mode}_${selector_bits}'
    text.write_string(if memory { 'define void @memory_${name}(i64 %seed, i${selector_bits} %j, ptr %out) { store i8 17, ptr %out\n' } else { 'define i64 @scalar_${name}(i64 %seed, i${selector_bits} %j) {\n' })
    kind := if mode == 0 { 0 } else { state(sample, 0, 1) }
    input := if split { if kind == 1 { 'poison' } else if kind == 2 { 'undef' } else { scalar_literal(source, word(source, sample, 0)) } } else { literal(source, source_count, sample, mode == 0) }
    if mode == 0 {
     text.write_string('%seed_bits = ${if source_bits == 64 { 'or i64 %seed, 0' } else { 'trunc i64 %seed to i' + source_bits.str() }}\n' + bits_to_scalar(source, '%seed_bits', 'seed_value'))
     if !split { text.write_string('%inserted = insertelement ${input_type} ${input}, ${typ(source)} %seed_value, i32 ${sample % source_count}\n') }
    }
    if mode == 2 { text.write_string('%sf = freeze ${input_type} ${input}\n') }
    text.write_string('%raw = bitcast ${input_type} ${if mode == 0 { if split { '%seed_value' } else { '%inserted' } } else if mode == 2 { '%sf' } else { input }} to ${output_type}\n')
    if mode == 3 { text.write_string('%rf = freeze ${output_type} %raw\n') }
    if split { text.write_string('%e = extractelement ${output_type} ${if mode == 3 { '%rf' } else { '%raw' }}, i${selector_bits} %j\n') }
    text.write_string(scalar_to_bits(dest, if split { '%e' } else if mode == 3 { '%rf' } else { '%raw' }, 'bits') + widen(bits, '%bits', 'result'))
    text.write_string(if memory { '%idx = ' + if mode == 3 { 'or i64 %result, 0' } else { 'and i64 %result, 63' } + '\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p, align 1\n ret void }\n' } else { 'ret i64 %result }\n' })
   } } } }
   dir := root + '/s${scalar}-v${vector}-${split}'; data := assemble(os.args[1], dir, text.str())!; verify(data)!
   stream := airbitcode.parse(data)!; ir := stream.ir_module(data)!; pools := ir.constant_pools(stream)!; bodies := ir.function_bodies(stream, pools)!; p := ir.typed_operands(stream, pools, bodies)!; native := native_module(data, dir)!
   reference := C.LLVMGetFunctionAddress(native.engine, c'reference'); assert reference != 0
   for sample in 0 .. 8 { for mode in 0 .. 4 {
    seed := word(source, sample + 5, 0)
    mut inputs := [16]u64{}; mut result := [16]u64{}; mut source_poison := false; mut hard_undef := false
    for lane in 0 .. source_count {
     kind := if mode == 0 { 0 } else { state(sample, lane, source_count) }
     inputs[lane] = if kind != 0 { u64(0) } else if mode == 0 && lane == sample % source_count { seed } else { word(source, sample, lane) }
     if mode != 2 && kind == 2 { hard_undef = true }
     if kind == 1 && mode in [1, 3] { source_poison = true }
    }
    unsafe { NativeCast(voidptr(reference))(&inputs[0], &inputs[0], &result[0]) }
    for lane in 0 .. result_count { assert result[lane] == expected_lane(inputs, source_bits, bits, lane), dir; native_checks++ }
    for selector_bits in [1, 32, 64] {
     name := '${sample}_${mode}_${selector_bits}'; f := fi(ir, 'memory_' + name); sf := fi(ir, 'scalar_' + name); mut planned := true
     plan := p.prepare_memory_function(ir, stream, pools, bodies, f) or { assert split && hard_undef, dir + name + ': ' + err.msg(); static_refusals++; planned = false; airbitcode.IRPreparedMemoryFunction{} }
     sm := mask(selector_bits); mut candidates := []u64{cap: result_count + 3}; for j in 0 .. result_count + 1 { candidates << u64(j) }; candidates << [sm, u64(1) << u32(selector_bits - 1)]
     for raw in candidates {
      j := raw & sm; selected_poison := (split && j >= u64(result_count)) || (mode != 3 && source_poison)
      expected := if (split && j >= u64(result_count)) || source_poison { u64(0) } else { result[if split { int(j) } else { 0 }] }
      index := if mode == 3 { expected } else { expected & 63 }
      if !hard_undef && !selected_poison && index >= 64 { bounds++ }
      args := [seed | ~mask(source_bits), j | ~sm]
      if r := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 100) { assert !hard_undef && r.poison == selected_poison && (selected_poison || r.value == expected), dir + name } else { assert hard_undef, dir + name + ': ' + err.msg(); assert err.msg().contains('undef'), err.msg() }

       if r := p.run_integer_function(ir, stream, pools, bodies, sf, args, 100) { assert !hard_undef && r.poison == selected_poison && (selected_poison || r.value == expected), name } else { assert hard_undef && err.msg().contains('undef'), err.msg() }; scalar_checks += 2
      mut bytes := []u8{len: 67, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{values: [args[0]]}, airbitcode.IRMemoryBinding{values: [args[1]]}, airbitcode.IRMemoryBinding{data: bytes, offset: 3, writable: true}]
      if planned { memory_check(p, ir, stream, pools, bodies, f, plan, mut bindings, hard_undef, selected_poison, index)! } else { if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bindings, 100) { panic('static undef address') }; for b in bytes { assert b == 0xcc } }
      if hard_undef { undefined++ } else if selected_poison { poison++ } else { values++ }
      rows.writeln('${scalar} ${vector} ${split} ${sample} ${mode} ${selector_bits} ${j} ${hard_undef} ${selected_poison} ${expected} ${index} PASS')!
      unsafe { args.free(); bytes.free(); bindings[0].values.free(); bindings[1].values.free(); bindings.free() }
     }
     if planned {
     mut bytes := [u8(0xcc), 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc]!
     mut bindings := [airbitcode.IRMemoryBinding{values: [seed]}, airbitcode.IRMemoryBinding{values: [u64(0)]}, airbitcode.IRMemoryBinding{data: bytes, offset: 3, writable: true}]
     if _ := plan.run(mut bindings, plan.steps() - 1) { panic('short prepared budget') }; for b in bytes { assert b == 0xcc }; budgets++
     unsafe { bindings[0].values.free(); bindings[1].values.free(); bindings.free();  }; plan.free()
     }; unsafe { candidates.free() }
    }
   } }
   native.close(); p.free(); bodies.free(); pools.free(); ir.free(); stream.free(); unsafe { data.free() }
  }
 } }
 assert shapes == 422 && values == 153114 && poison == 52602 && undefined == 29388 && native_checks == 37856 && scalar_checks == 470208 && budgets == 37980 && bounds == 9872 && static_refusals == 2532 && controls_count == 67
 line := 'AIR-SCALAR-VECTOR-BITCAST-INDEX: ${shapes} shapes, ${values - bounds} exact address outputs, ${poison + undefined + bounds} prewrite refusals (${undefined} undef, ${bounds} bounds), ${native_checks} defined LLVM/oracle lanes, ${scalar_checks} scalar/integer checks, ${budgets} short budgets, ${static_refusals} scalar undef profile refusals, ${controls_count} controls PASS\n'
 os.write_file(root + '/result.txt', line)!; print(line)
}
