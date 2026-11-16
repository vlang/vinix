// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references reduce only defined lanes. Separate interpreter checks
// cover poison, strict undef errors, freezing and the pre-write boundary.
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

fn reduction_reference(op int, words [16]u64, bits u32, count int) u64 {
	lane_mask := mask(int(bits))
	mut result := if op == 1 { u64(1) } else if op == 2 { lane_mask } else { u64(0) }
	if op >= 5 {
		mut chosen := 0
		for i in 1 .. count {
			key := (words[i] & lane_mask) ^ if op < 7 { u64(1) << (bits - 1) } else { u64(0) }
			best := (words[chosen] & lane_mask) ^ if op < 7 { u64(1) << (bits - 1) } else { u64(0) }
			if (op in [5,7] && key < best) || (op in [6,8] && key > best) { chosen = i }
		}
		return words[chosen] & lane_mask
	}
	for i in 0 .. count { v := words[i] & lane_mask; match op { 0 { result += v } 1 { result *= v } 2 { result &= v } 3 { result |= v } else { result ^= v } } }
	return result & lane_mask
}
fn opname(op int) string { return ['add','mul','and','or','xor','smin','smax','umin','umax'][op] }
fn word(bits int,sample int,lane int) u64 { return [u64(0),1,~u64(0),u64(1)<<u32(bits-1),(u64(1)<<u32(bits-1))-1,0xaaaaaaaaaaaaaaaa,0x9e3779b97f4a7c15,0x0123456789abcdef]![(sample+lane)%8]&mask(bits) }
fn state(sample int,lane int,count int) int { return if (sample==2&&lane==count-1)||sample==7 {2} else if (sample==3&&lane==count-1)||sample==6 {1} else {0} }
fn literal(bits int,count int,sample int,defined bool) string {
 mut lanes:=[]string{cap:count};for lane in 0..count {k:=if defined {0} else {state(sample,lane,count)};lanes<<'i${bits} '+if k==1 {'poison'} else if k==2 {'undef'} else {word(bits,sample,lane).str()}}
 return '<'+lanes.join(', ')+'>'
}
fn widen(bits int,from string,to string) string { return '%${to} = '+if bits==64 {'or i64 ${from}, 0\n'} else {'zext i${bits} ${from} to i64\n'} }
fn memory_check(p airbitcode.IRTypedProgram,ir airbitcode.IRModule,stream airbitcode.Stream,pools airbitcode.IRConstantPools,bodies airbitcode.IRFunctionBodies,f int,plan &airbitcode.IRPreparedMemoryFunction,mut bs []airbitcode.IRMemoryBinding,undefined bool,poison bool,value u64) ! {
 for prepared in [false,true] {
  for i in 0..bs[1].data.len {bs[1].data[i]=0xcc}
  plan.validate(bs,plan.steps())!;for b in bs[1].data {assert b==0xcc}
  if prepared {if _:=plan.run(mut bs,plan.steps()) {assert !undefined&&!poison} else {assert undefined||poison,err.msg();assert if undefined {err.msg().contains('undef')} else {err.msg()=='AIR memory execution: poison store'},err.msg()}}
  else {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert !undefined&&!poison} else {assert undefined||poison,err.msg();assert if undefined {err.msg().contains('undef')} else {err.msg()=='AIR memory execution: poison store'},err.msg()}}
  for i,b in bs[1].data {assert b==if i==3 {u8(17)} else if !undefined&&!poison&&i>=11&&i<19 {u8(value>>u32((i-11)*8))} else {u8(0xcc)},ir.functions[f].name}
 }
}

fn controls(assembler string,root string) !int {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 for op in 0..9 {s.write_string('declare i32 @llvm.vector.reduce.${opname(op)}.v3i32(<3 x i32>) #0\n')}
 s.write_string('declare i16 @llvm.vector.reduce.add.v3i16(<3 x i16>)\n declare float @llvm.vector.reduce.fadd.v3f32(float, <3 x float>)\n attributes #0 = { nounwind memory(none) }\n')
 for memory in [false,true] {
  s.write_string(if memory {'define void @cache_memory(i32 %seed, ptr %out) { store i8 17, ptr %out\n'} else {'define i64 @cache_scalar(i32 %seed) {\n'})
  s.write_string('%a = insertelement <3 x i32> <i32 0, i32 2147483648, i32 4294967295>, i32 %seed, i32 0\n %b = add <3 x i32> %a, zeroinitializer\n %c = shufflevector <3 x i32> %b, <3 x i32> undef, <3 x i32> <i32 2, i32 1, i32 0>\n %v = select i1 true, <3 x i32> %c, <3 x i32> undef\n')
  for op in 0..9 {s.write_string('%r${op} = call i32 @llvm.vector.reduce.${opname(op)}.v3i32(<3 x i32> %v)\n %z${op} = zext i32 %r${op} to i64\n %s${op} = shl i64 %z${op}, ${op}\n %x${op} = xor i64 ${if op==0 {'0'} else {'%x'+(op-1).str()}}, %s${op}\n')}
  s.write_string(if memory {'%p = getelementptr i8, ptr %out, i64 8\n store i64 %x8, ptr %p, align 1\n ret void }\n'} else {'ret i64 %x8 }\n'})
 }
 for name in ['cold','discard_poison','discard_undef','address','floating','loaded'] {
  s.write_string('define void @${name}(ptr %out) { entry: store i8 17, ptr %out\n')
  if name=='cold' {s.write_string('br i1 true, label %exit, label %cold\n cold:\n')}
  if name=='floating' {s.write_string('%r = call float @llvm.vector.reduce.fadd.v3f32(float 0.0, <3 x float> zeroinitializer)\n')}
  else if name=='loaded' {s.write_string('%v = load <3 x i16>, ptr %out, align 1\n %r = call i16 @llvm.vector.reduce.add.v3i16(<3 x i16> %v)\n %p = getelementptr i8, ptr %out, i64 8\n store i16 %r, ptr %p, align 1\n')}
  else {s.write_string('%r = call i32 @llvm.vector.reduce.add.v3i32(<3 x i32> ${if name=='address' {'<i32 1, i32 0, i32 0>'} else if name=='discard_poison' {'poison'} else {'undef'}})\n')}
  if name=='address' {s.write_string('%p = getelementptr i8, ptr %out, i32 %r\n store i8 42, ptr %p\n')}
  if name=='cold' {s.write_string('br label %exit\n exit:\n')}
  s.write_string('ret void }\n')
 }
 s.write_string('define i64 @loop(i64 %limit) { entry: br label %body\n body: %i = phi i64 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%r, %body]\n %v = insertelement <3 x i32> <i32 0, i32 1, i32 2>, i32 %sum, i32 0\n %r = call i32 @llvm.vector.reduce.add.v3i32(<3 x i32> %v)\n %next = add i64 %i, 1\n %more = icmp ult i64 %next, %limit\n br i1 %more, label %body, label %exit\n exit: %wide = zext i32 %r to i64\n ret i64 %wide }\n')
 data:=assemble(assembler,root+'/controls',s.str())!;verify(data)!
 stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;mut p:=ir.typed_operands(stream,pools,bodies)!;mut checks:=0
 f:=fi(ir,'cache_memory');sf:=fi(ir,'cache_scalar');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
 for sample in 0..16 {
  seed:=word(32,sample,0);words:=[u64(0xffffffff),0x80000000,seed,u64(0),0,0,0,0,0,0,0,0,0,0,0,0]!
  mut expected:=u64(0);for op in 0..9 {expected ^= reduction_reference(op,words,32,3)<<u32(op)}
  args:=[seed|~mask(32)];a:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,100)!;b:=p.run_integer_function(ir,stream,pools,bodies,sf,args,100)!;assert !a.poison&&!b.poison&&a.value==expected&&b.value==expected;checks+=2
  mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
  memory_check(p,ir,stream,pools,bodies,f,plan,mut bs,false,false,expected)!;checks+=2;unsafe{args.free();bytes.free();bs.free()}
 };plan.free()
 for name in ['cold','discard_poison','discard_undef','address','floating','loaded'] {
  f2:=fi(ir,name);mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}]
  if name=='floating' {if _:=p.prepare_memory_function(ir,stream,pools,bodies,f2) {panic(name)};if _:=p.run_memory_function(ir,stream,pools,bodies,f2,mut bs,100) {panic(name)};for b in bytes {assert b==0xcc};checks++}
  else {pl:=p.prepare_memory_function(ir,stream,pools,bodies,f2)!;for prepared in [false,true] {
   for i in 0..bytes.len {bytes[i]=0xcc};pl.validate(bs,pl.steps())!;for b in bytes {assert b==0xcc}
   if prepared {if _:=pl.run(mut bs,pl.steps()) {assert name!='discard_undef'} else {assert name=='discard_undef',err.msg()}} else {if _:=p.run_memory_function(ir,stream,pools,bodies,f2,mut bs,pl.steps()) {assert name!='discard_undef'} else {assert name=='discard_undef',err.msg()}}
   // Loaded lanes observe the preceding marker: 0xcc11 + 0xcccc + 0xcccc.
   value:=u64(0x65a9);for i,b in bytes {assert b==if i==0 {u8(17)} else if name=='address'&&i==1 {u8(42)} else if name=='loaded'&&i in [8,9] {u8(value>>u32((i-8)*8))} else {u8(0xcc)},name};checks++
  };pl.free()};unsafe{bytes.free();bs.free()}
 }
 for count in [u64(1),2,3,7,16,257,513,1024]! {a:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),[count],20000)!;b:=p.run_integer_function(ir,stream,pools,bodies,fi(ir,'loop'),[count],20000)!;assert !a.poison&&!b.poison&&a.value==count*3&&b.value==count*3;checks+=2}
 scope:=bodies.scopes[f+1];mut call:=-1;for i in scope.instructions_start..scope.instructions_start+scope.instructions_count {if stream.records[bodies.instructions[i].record].code==34 {call=i;break}};assert call>=0;saved:=p.instructions[call]
 mut blank:=[]u8{len:32,init:0xcc};args:=[u64(1)];mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:blank,writable:true}]
 for op in [airbitcode.IRTypedInstruction{...saved,flags:0},airbitcode.IRTypedInstruction{...saved,opcode:1},airbitcode.IRTypedInstruction{...saved,is_volatile:true},airbitcode.IRTypedInstruction{...saved,calling_convention:8},airbitcode.IRTypedInstruction{...saved,fast_math_flags:1},airbitcode.IRTypedInstruction{...saved,attribute_set:1},airbitcode.IRTypedInstruction{...saved,targets_count:1},airbitcode.IRTypedInstruction{...saved,indices_count:1},airbitcode.IRTypedInstruction{...saved,operands_count:1},airbitcode.IRTypedInstruction{...saved,operands_count:3},airbitcode.IRTypedInstruction{...saved,call_signature:-1},airbitcode.IRTypedInstruction{...saved,callee_function:-1},airbitcode.IRTypedInstruction{...saved,result_type:-1}] {
  p.instructions[call]=op;if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('metadata')};checks++
 };p.instructions[call]=saved
 slot:=saved.operands_start+1;operand:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...operand,type_index:saved.result_type};if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('source type')};checks++;p.operands[slot]=operand
 mut functions:=ir.functions.clone();bad_ir:=airbitcode.IRModule{...ir,functions:functions}
 for name in ['llvm.vector.reduce.add.v2i32','llvm.vector.reduce.add.v3i31','llvm.vector.reduce.add.v03i32','llvm.vector.reduce.fadd.v3f32'] {functions[saved.callee_function]=airbitcode.IRFunction{...ir.functions[saved.callee_function],name:name};if _:=p.run_memory_function(bad_ir,stream,pools,bodies,f,mut bs,100) {panic('name/type')};for b in blank {assert b==0xcc};checks++};functions[saved.callee_function]=ir.functions[saved.callee_function]
 mut duplicate:=-1;for i,fun in functions {if fun.name=='llvm.vector.reduce.mul.v3i32' {duplicate=i}};assert duplicate>=0;functions[duplicate]=airbitcode.IRFunction{...functions[duplicate],name:'llvm.vector.reduce.add.v3i32'};if _:=p.run_memory_function(bad_ir,stream,pools,bodies,f,mut bs,100) {panic('duplicate identity')};for b in blank {assert b==0xcc};checks++
 unsafe{functions.free();blank.free();args.free();bs.free()};p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
 for storage in [false,true] {for over in [false,true] {limits(assembler,root+'/limit-'+storage.str()+'-'+over.str(),storage,over)!;checks+=2}}
 return checks
}
fn limits(assembler string,root string,storage bool,over bool) ! {
 mut s:=strings.new_builder(8388608);s.write_string('target datalayout = "e-p:64:64"\n declare i4 @llvm.vector.reduce.add.v16i4(<16 x i4>)\n')
 for memory in [false,true] {
  s.write_string('define void @${if memory {'memory'} else {'scalar'}}(${if memory {'ptr %out'} else {''}}) {\n');if memory {s.write_string('store i8 17, ptr %out\n')}
  for i in 0..if storage&&over {4097} else {4096} {s.write_string('%v${i} = insertelement <16 x i4> zeroinitializer, i4 1, i32 0\n')}
  for i in 0..if storage {4096} else {54968} {s.write_string('%r${i} = call i4 @llvm.vector.reduce.add.v16i4(<16 x i4> %v4095)\n')}
  if !storage {s.write_string('%e = extractelement <8 x i1> zeroinitializer, i32 0\n');if over {s.write_string('%over = extractelement <1 x i1> zeroinitializer, i32 0\n')}};s.write_string('ret void }\n')
 }
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!
 mut bytes:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 if over {expected:=if storage {'AIR vector: update result limit'} else {'AIR vector: constant lane work limit'};if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('limit')} else {assert err.msg()==expected,err.msg()};assert bytes[0]==0xcc;if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('void limit')} else {assert err.msg()==expected,err.msg()}}
 else {p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!;assert bytes[0]==17;p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!}
 p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free();bs.free()}
}

fn main() {
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 control_count:=controls(os.args[1],root)!
 assert control_count==118
 if os.args.len==4 {println('AIR-VECTOR-REDUCTION-CONTROLS: ${control_count} PASS');return}
 mut rows:=os.create(root+'/comparisons.txt')!;defer{rows.close()}
 mut shapes:=0;mut exact:=0;mut poisoned:=0;mut undefined:=0;mut native_checks:=0;mut scalar_checks:=0;mut budgets:=0
 for bits in 1..65 {
  counts:=if bits in [1,8,16,32,64] {[]int{len:16,init:index+1}} else {[3]}
  for count in counts {
   t:='<${count} x i${bits}>';mut text:=strings.new_builder(262144);text.write_string('target datalayout = "e-p:64:64"\n')
   for op in 0..9 {
    shapes++;name:='llvm.vector.reduce.${opname(op)}.v${count}i${bits}';text.write_string('declare i${bits} @${name}(${t})\n define void @ref_${op}(ptr %in, ptr %unused, ptr %out) {\n')
    for lane in 0..count {text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = '+if bits==64 {'or i64 %w${lane}, 0\n'} else {'trunc i64 %w${lane} to i${bits}\n'});text.write_string('%v${lane} = insertelement ${t} ${if lane==0 {'zeroinitializer'} else {'%v'+(lane-1).str()}}, i${bits} %b${lane}, i32 ${lane}\n')}
    text.write_string('%r = call i${bits} @${name}(${t} %v${count-1})\n'+widen(bits,'%r','wide')+'store i64 %wide, ptr %out, align 1\n ret void }\n')
    for sample in 0..8 {for mode in 0..4 {for memory in [false,true] {
     label:='${op}_${sample}_${mode}';text.write_string(if memory {'define void @memory_${label}(i${bits} %seed, ptr %out) { store i8 17, ptr %out\n'} else {'define i64 @scalar_${label}(i${bits} %seed) {\n'})
     input:=literal(bits,count,sample,mode==0)
     if mode==0 {text.write_string('%inserted = insertelement ${t} ${input}, i${bits} %seed, i32 ${sample%count}\n')}
     if mode==2 {text.write_string('%sf = freeze ${t} ${input}\n')}
     text.write_string('%r = call i${bits} @${name}(${t} ${if mode==0 {'%inserted'} else if mode==2 {'%sf'} else {input}})\n')
     if mode==3 {text.write_string('%rf = freeze i${bits} %r\n')}
     text.write_string(widen(bits,if mode==3 {'%rf'} else {'%r'},'wide'))
     text.write_string(if memory {'%p = getelementptr i8, ptr %out, i64 8\n store i64 %wide, ptr %p, align 1\n ret void }\n'} else {'ret i64 %wide }\n'})
    }}}
   }
   dir:=root+'/w${bits}-n${count}';data:=assemble(os.args[1],dir,text.str())!;verify(data)!
   stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!;native:=native_module(data,dir)!
   for op in 0..9 {
    address:=C.LLVMGetFunctionAddress(native.engine,('ref_'+op.str()).str);assert address!=0
    for sample in 0..8 {for mode in 0..4 {
     seed:=word(bits,sample+5,0);mut words:=[16]u64{};mut result:=[u64(0)]!;mut hard_undef:=false;mut poison:=false
     for lane in 0..count {k:=if mode==0 {0} else {state(sample,lane,count)};words[lane]=if k!=0 {u64(0)} else if mode==0&&lane==sample%count {seed} else {word(bits,sample,lane)};if mode!=2&&k==2 {hard_undef=true};if mode!=2&&k==1 {poison=true}}
     unsafe{NativeCast(voidptr(address))(&words[0],&words[0],&result[0])};assert result[0]==reduction_reference(op,words,u32(bits),count);native_checks++
     expected:=if mode==3&&poison {u64(0)} else {result[0]};selected_poison:=mode!=3&&poison
     label:='${op}_${sample}_${mode}';f:=fi(ir,'memory_'+label);sf:=fi(ir,'scalar_'+label);plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
     args:=[seed|~mask(bits)]
     if r:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,100) {assert !hard_undef&&r.poison==selected_poison&&(r.poison||r.value==expected),dir+label} else {assert hard_undef&&err.msg().contains('undef'),err.msg()}
     if r:=p.run_integer_function(ir,stream,pools,bodies,sf,args,100) {assert !hard_undef&&r.poison==selected_poison&&(r.poison||r.value==expected),dir+label} else {assert hard_undef&&err.msg().contains('undef'),err.msg()};scalar_checks+=2
     mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
     memory_check(p,ir,stream,pools,bodies,f,plan,mut bs,hard_undef,selected_poison,expected)!
     for i in 0..bytes.len {bytes[i]=0xcc};if _:=plan.run(mut bs,plan.steps()-1) {panic('short budget')};for b in bytes {assert b==0xcc};budgets++
     if hard_undef {undefined++} else if selected_poison {poisoned++} else {exact++}
     rows.writeln('${op} ${bits} ${count} ${sample} ${mode} ${hard_undef} ${selected_poison} ${expected} PASS')!
     plan.free();unsafe{args.free();bytes.free();bs.free()}
    }}
   }
   native.close();p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
  }
 }
 assert shapes==1251&&exact==32526&&poisoned==2502&&undefined==5004&&native_checks==40032&&scalar_checks==80064&&budgets==40032&&control_count==118
 line:='AIR-VECTOR-REDUCTION: ${shapes} shapes, ${exact} exact/frozen values, ${poisoned} poison stores, ${undefined} strict undef failures, ${native_checks} native/oracle values, ${scalar_checks} scalar/integer checks, ${budgets} short budgets, ${control_count} controls PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
