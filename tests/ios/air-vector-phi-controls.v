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

fn mask(bits int) u64 { return if bits==64 {~u64(0)} else {(u64(1)<<u32(bits))-1} }
fn bits(e int) int { return if e<64 {e+1} else if e==64 {16} else {32} }
fn typ(e int) string {return if e<64 {'i${e+1}'} else if e==64 {'half'} else {'float'}}
fn word(e int,lane int,side int) u64 {
 if e<64 {return (u64(lane+1+side*19)*u64(0x9e3779b97f4a7c15))&mask(bits(e))}
 return if e==64 {[u64(0),0x8000,0x7c01,0x7e55,0xfc00,0x7c00,1,0x3ff,0x3c00,0xbc00,0x7bff,0x400,0xfc01,0xfe55,0x8001,0x3555]![(lane+side*7)%16]} else {[u64(0),0x80000000,0x7f800001,0x7fc12345,0xff800000,0x7f800000,1,0x7fffff,0x3f800000,0xbf800000,0x7f7fffff,0x800000,0xff800001,0xffc12345,0x80000001,0x3eaaaaab]![(lane+side*7)%16]}
}
fn literal(e int,x u64) string {return if e<64 {x.str()} else {'bitcast (i${bits(e)} ${x} to ${typ(e)})'}}
fn vector(e int,n int,side int,form int) string {
 if form==1 {return 'poison'};if form==2 {return 'undef'}
 mut lanes:=[]string{}
 for lane in 0..n {lanes<<typ(e)+' '+if form==3&&lane%4==1 {'poison'} else if form==3&&lane%4==2 {'undef'} else {literal(e,word(e,lane,side))}}
 return '<'+lanes.join(', ')+'>'
}
fn unpack(e int,name string,raw string) string {
 if e==63 {return '%${name} = or i64 ${raw}, 0\n'}
 return '%${name}_bits = trunc i64 ${raw} to i${bits(e)}\n'+if e<64 {'%${name} = or i${bits(e)} %${name}_bits, 0\n'} else {'%${name} = bitcast i${bits(e)} %${name}_bits to ${typ(e)}\n'}
}
fn widen(e int,source string) string {
 if e==63 {return '%wide = or i64 ${source}, 0\n'}
 return (if e>=64 {'%rawbits = bitcast ${typ(e)} ${source} to i${bits(e)}\n'} else {''})+'%wide = zext i${bits(e)} ${if e>=64 {'%rawbits'} else {source}} to i64\n'
}
fn join_body(e int,n int,form int,mode int,memory bool) string {
 t:=typ(e);v:='<${n} x ${t}>'
 return 'entry:\n'+(if memory {'store i8 17, ptr %out\n'} else {''})+unpack(e,'x','%xraw')+unpack(e,'y','%yraw')+'%cond = trunc i64 %which to i1\n br i1 %cond, label %left, label %right\n left:\n %a = insertelement ${v} ${vector(e,n,0,form)}, ${t} %x, i32 0\n br label %join\n right:\n %b = insertelement ${v} ${vector(e,n,1,form)}, ${t} %y, i32 0\n br label %join\n join:\n %tag = phi i64 [5, %left], [9, %right]\n %p = phi ${v} [%a, %left], [%b, %right]\n'+(if mode==1 {'%f = freeze ${v} %p\n'} else {''})+'%val = extractelement ${v} ${if mode==1 {'%f'} else {'%p'}}, i64 %lane\n'+(if mode==2 {'%fval = freeze ${t} %val\n'} else {''})+widen(e,if mode==2 {'%fval'} else {'%val'})+'%answer = xor i64 %wide, %tag\n'+(if memory {'%dest = getelementptr i8, ptr %out, i64 8\n store i64 %answer, ptr %dest, align 1\n ret void }\n'} else {'ret i64 %answer }\n'})
}
fn loop_body(e int,n int,reverse bool,memory bool) string {
 v:='<${n} x ${typ(e)}>';mut lanes:=[]string{};for i in 0..n {lanes<<'i32 ${n-1-i}'}
 return 'entry:\n'+(if memory {'store i8 17, ptr %out\n'} else {''})+'br label %head\n head:\n %a = phi ${v} [${vector(e,n,0,0)}, %entry], [${if reverse {'%nexta'} else {'%b'}}, %latch]\n %k = phi i64 [0, %entry], [%next, %latch]\n %b = phi ${v} [${vector(e,n,1,0)}, %entry], [%c, %latch]\n %tag = phi i64 [17, %entry], [%tag, %latch]\n %c = phi ${v} [${vector(e,n,2,0)}, %entry], [%a, %latch]\n %more = icmp ult i64 %k, %trip\n br i1 %more, label %latch, label %exit\n latch:\n'+(if reverse {'%nexta = shufflevector ${v} %b, ${v} %b, <${n} x i32> <${lanes.join(', ')}>\n'} else {''})+'%next = add i64 %k, 1\n br label %head\n exit:\n %val = extractelement ${v} %a, i64 %lane\n'+widen(e,'%val')+'%answer = xor i64 %wide, %tag\n'+(if memory {'%dest = getelementptr i8, ptr %out, i64 8\n store i64 %answer, ptr %dest, align 1\n ret void }\n'} else {'ret i64 %answer }\n'})
}
fn reference(name string,target string,looping bool) string {
 mut s:=strings.new_builder(2048);s.write_string('define void @${name}(ptr %in, ptr %unused, ptr %out) {\n')
 for i in 0..if looping {2} else {4} {s.write_string('%p${i} = getelementptr i64, ptr %in, i64 ${i}\n %a${i} = load i64, ptr %p${i}, align 1\n')}
 args:=if looping {'i64 %a0, i64 %a1'} else {'i64 %a0, i64 %a1, i64 %a2, i64 %a3'}
 s.write_string('%r = call i64 @${target}(${args})\n store i64 %r, ptr %out, align 1\n ret void }\n');return s.str()
}
fn expect(e int,n int,form int,mode int,which int,lane int,x u64,y u64) (int,u64) {
 tag:=u64(if which&1!=0 {5} else {9});side:=if which&1!=0 {0} else {1}
 mut state:=if lane>=n {1} else if lane==0 {0} else if form in [1,2] {form} else if form==3&&lane%4 in [1,2] {lane%4} else {0}
 mut value:=if lane==0 {if side==0 {x} else {y}} else if lane<n {word(e,lane,side)} else {u64(0)}
 if (mode==1&&lane<n&&state!=0)||(mode==2&&state==1) {state=0;value=0}
 return state,(value&mask(bits(e)))^tag
}
fn bytes_match(actual []u8,state int,value u64) {
 for i,b in actual {assert b==if i==3 {u8(17)} else if state==0&&i>=11&&i<19 {u8(value>>u32((i-11)*8))} else {u8(0xcc)},'${i} ${b} ${state} ${value}'}
}
fn limits(assembler string,root string,storage bool,over bool) ! {
 mut source:=strings.new_builder(8388608);source.write_string('target datalayout = "e-p:64:64"\n')
 for memory in [false,true] {source.write_string('define void @${if memory {'m'} else {'v'}}(${if memory {'ptr %out'} else {''}}) {entry:\n'+if memory {'store i8 17, ptr %out\n'} else {''})
  if storage {source.write_string('br label %join\n join:\n');for i in 0..if over {4097} else {4096} {source.write_string('%p${i} = phi <1 x i1> [zeroinitializer, %entry]\n')}}
  else {source.write_string('br i1 true, label %left, label %right\n left: br label %join\n right: br label %join\n join:\n %p = phi <16 x i1> [zeroinitializer, %left], [zeroinitializer, %right]\n');for i in 0..62497 {source.write_string('%e${i} = extractelement <16 x i1> %p, i32 0\n')};if over {source.write_string('%over = extractelement <1 x i1> zeroinitializer, i32 0\n')}}
  source.write_string('ret void }\n')
 }
 data:=assemble(assembler,root,source.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!
 defer {p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}}
 mut bytes:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 if over {diagnostic:=if storage {'AIR vector: update result limit'} else {'AIR vector: constant lane work limit'};if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'m'),mut bs,70000) {panic('memory limit')} else {assert err.msg()==diagnostic,err.msg()};assert bytes[0]==0xcc;if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'v'),[],70000) {panic('void limit')} else {assert err.msg()==diagnostic,err.msg()}}
 else {p.run_memory_function(ir,stream,pools,bodies,fi(ir,'m'),mut bs,70000)!;assert bytes[0]==17;p.run_void_function(ir,stream,pools,bodies,fi(ir,'v'),[],70000)!};unsafe{bs.free()}
}
fn main(){assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!;assembler:=os.args[1]
 mut source:=strings.new_builder(1048576);source.write_string('target datalayout = "e-p:64:64"\n')
 for e in 0..66 {for n in [1,3,16] {for form in 0..4 {for mode in 0..3 {source.write_string('define void @v_${e}_${n}_${form}_${mode}(i64 %which, i64 %xraw, i64 %yraw, i64 %lane) {\n'+join_body(e,n,form,mode,false).replace('ret i64 %answer','ret void'))}}}}
 for e in [7,15,31,63,64,65] {for n in [1,3,16] {v:='<${n} x ${typ(e)}>';for loaded in [false,true] {sig:=if loaded {'i64 %which, ptr %src, ptr %out'} else {'i64 %which, ${v} %a, ${v} %b, ptr %out'};source.write_string('define void @m_${e}_${n}_${loaded}(${sig}) {entry:\n store i8 17, ptr %out\n %cond = trunc i64 %which to i1\n br i1 %cond, label %left, label %right\n left:\n'+(if loaded {'%la = load ${v}, ptr %src, align 1\n'} else {''})+'br label %join\n right:\n'+(if loaded {'%rp = getelementptr i8, ptr %src, i64 128\n %lb = load ${v}, ptr %rp, align 1\n'} else {''})+'br label %join\n join:\n %q = phi ptr [%out, %left], [%out, %right]\n %p = phi ${v} [${if loaded {'%la'} else {'%a'}}, %left], [${if loaded {'%lb'} else {'%b'}}, %right]\n %tag = phi i8 [11, %left], [13, %right]\n %dest = getelementptr i8, ptr %q, i64 8\n store ${v} %p, ptr %dest, align 1\n %tp = getelementptr i8, ptr %q, i64 144\n store i8 %tag, ptr %tp\n ret void }\n')}}}
 source.write_string('define void @address(i64 %which, ptr %out) {entry: store i8 17, ptr %out\n %c = trunc i64 %which to i1\n br i1 %c, label %left, label %right\n left: br label %join\n right: br label %join\n join: %v = phi <2 x i32> [zeroinitializer, %left], [zeroinitializer, %right]\n %i = extractelement <2 x i32> %v, i32 0\n %p = getelementptr i8, ptr %out, i32 %i\n store i8 42, ptr %p\n ret void }\n')
 data:=assemble(assembler,root+'/cases',source.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;mut p:=ir.typed_operands(stream,pools,bodies)!
 defer {p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}}
 mut void_checks:=0;mut copies:=0;mut guards:=0
 for e in 0..66 {for n in [1,3,16] {for form in 0..4 {for mode in 0..3 {f:=fi(ir,'v_${e}_${n}_${form}_${mode}');for which in 0..2 {for lane in 0..n+1 {args:=[u64(which),u64(31),u64(47),u64(lane)];state,_:=expect(e,n,form,mode,which,lane,31,47);if _:=p.run_void_function(ir,stream,pools,bodies,f,args,100) {assert state!=2} else {assert state==2&&err.msg().contains('undef'),err.msg()};void_checks++;unsafe{args.free()}}}}}}}
 for e in [7,15,31,63,64,65] {for n in [1,3,16] {for loaded in [false,true] {f:=fi(ir,'m_${e}_${n}_${loaded}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;stride:=bits(e)/8;mut input:=[]u8{len:272};mut a:=[]u64{len:n};mut b:=[]u64{len:n};mut output:=[]u8{len:192,init:0xcc};mut cond:=[u64(0)]
  for side in 0..2 {for lane in 0..n {w:=word(e,lane,side);if side==0 {a[lane]=w|~mask(bits(e))} else {b[lane]=w|~mask(bits(e))};for byte in 0..stride {input[3+side*128+lane*stride+byte]=u8(w>>u32(byte*8))}}}
  mut bs:=if loaded {[airbitcode.IRMemoryBinding{values:cond},airbitcode.IRMemoryBinding{data:input,offset:3},airbitcode.IRMemoryBinding{data:output,offset:5,writable:true}]} else {[airbitcode.IRMemoryBinding{values:cond},airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:b},airbitcode.IRMemoryBinding{data:output,offset:5,writable:true}]}
  for which in 0..2 {cond[0]=u64(which);for prepared in [false,true] {for i in 0..output.len {output[i]=0xcc};plan.validate(bs,plan.steps())!;for x in output {assert x==0xcc};if prepared {plan.run(mut bs,plan.steps())!} else {p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps())!};for i,x in output {assert x==if i==5 {u8(17)} else if i==149 {u8(if which!=0 {11} else {13})} else if i>=13&&i<13+n*stride {input[3+if which!=0 {0} else {128}+i-13]} else {u8(0xcc)},'${e} ${n} ${loaded} ${which} ${i} ${x}'};copies++}}
  plan.free();unsafe{input.free();a.free();b.free();output.free();cond.free();bs.free()}
 }}}
 f:=fi(ir,'m_7_3_false');s:=bodies.scopes[f+1];mut pi:=-1;for i in s.instructions_start..s.instructions_start+s.instructions_count {if stream.records[bodies.instructions[i].record].code==16&&p.types[p.instructions[i].result_type].kind==.vector_t {pi=i;break}};assert pi>=0;saved:=p.instructions[pi]
 mut output:=[]u8{len:192,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:[u64(1)]},airbitcode.IRMemoryBinding{values:[u64(1),2,3]},airbitcode.IRMemoryBinding{values:[u64(4),5,6]},airbitcode.IRMemoryBinding{data:output,writable:true}]
 for bad in [airbitcode.IRTypedInstruction{...saved,flags:1},airbitcode.IRTypedInstruction{...saved,opcode:1},airbitcode.IRTypedInstruction{...saved,is_volatile:true},airbitcode.IRTypedInstruction{...saved,fast_math_flags:1},airbitcode.IRTypedInstruction{...saved,operands_count:0},airbitcode.IRTypedInstruction{...saved,targets_count:1},airbitcode.IRTypedInstruction{...saved,targets_start:-1},airbitcode.IRTypedInstruction{...saved,targets_start:p.targets.len},airbitcode.IRTypedInstruction{...saved,operands_start:-1},airbitcode.IRTypedInstruction{...saved,operands_start:p.operands.len},airbitcode.IRTypedInstruction{...saved,indices_count:1},airbitcode.IRTypedInstruction{...saved,result_type:-1}] {p.instructions[pi]=bad;if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('metadata')};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100) {panic('metadata')};for x in output {assert x==0xcc};guards++};p.instructions[pi]=saved
 operand:=p.operands[saved.operands_start];for bad in [airbitcode.IRTypedOperand{...operand,type_index:0},airbitcode.IRTypedOperand{...operand,number:bodies.instructions[pi].next_value}] {p.operands[saved.operands_start]=bad;if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('source')};guards++};p.operands[saved.operands_start]=operand
 target:=p.targets[saved.targets_start];for bad in [-1,bodies.blocks.len] {p.targets[saved.targets_start]=bad;if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('target')};guards++};p.targets[saved.targets_start]=target
 af:=fi(ir,'address');mut abs:=[airbitcode.IRMemoryBinding{values:[u64(0)]},airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.prepare_memory_function(ir,stream,pools,bodies,af) {panic('PHI address')};if _:=p.run_memory_function(ir,stream,pools,bodies,af,mut abs,100) {panic('PHI address')};for x in output {assert x==0xcc};guards++
 unsafe{output.free();for b in bs {b.values.free()};bs.free();abs[0].values.free();abs.free()}
 for storage in [false,true] {for over in [false,true] {limits(assembler,root+'/limit-${storage}-${over}',storage,over)!}}
 line:='AIR-VECTOR-PHI-CONTROLS: ${void_checks} void observations, ${copies} typed-argument/loaded vector copies with interleaved pointer/scalar PHIs, ${guards} metadata/source/address refusals, 8 exact storage/work boundaries PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
