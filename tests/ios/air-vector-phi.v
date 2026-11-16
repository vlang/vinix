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
fn run_batch(assembler string,root string,e int) ! {
 mut source:=strings.new_builder(1048576);source.write_string('target datalayout = "e-p:64:64"\n')
 for n in 1..17 {for form in 0..4 {for mode in 0..3 {suffix:='${n}_${form}_${mode}';source.write_string('define i64 @s_${suffix}(i64 %which, i64 %xraw, i64 %yraw, i64 %lane) {\n'+join_body(e,n,form,mode,false));source.write_string('define void @m_${suffix}(i64 %which, i64 %xraw, i64 %yraw, i64 %lane, ptr %out) {\n'+join_body(e,n,form,mode,true));if form==0 {source.write_string(reference('ref_'+suffix,'s_'+suffix,false))}}}}
 for n in [1,2,3,8,16] {for reverse in [false,true] {suffix:='${n}_${reverse}';source.write_string('define i64 @l_${suffix}(i64 %trip, i64 %lane) {\n'+loop_body(e,n,reverse,false));source.write_string(reference('lr_'+suffix,'l_'+suffix,true));source.write_string('define void @lm_${suffix}(i64 %trip, i64 %lane, ptr %out) {\n'+loop_body(e,n,reverse,true))}}
 data:=assemble(assembler,root,source.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;mut p:=ir.typed_operands(stream,pools,bodies)!;native:=native_module(data,root)!
 defer {native.close();p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}}
 mut rows:=os.create(root+'/comparisons.txt')!;defer{rows.close()}
 mut cases:=0;mut native_checks:=0;mut scalar_checks:=0;mut valid:=0;mut poison:=0;mut undefined:=0;mut budgets:=0;mut guards:=0
 for n in 1..17 {for form in 0..4 {for mode in 0..3 {
  suffix:='${n}_${form}_${mode}';sf:=fi(ir,'s_'+suffix);mf:=fi(ir,'m_'+suffix);plan:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;address:=if form==0 {C.LLVMGetFunctionAddress(native.engine,('ref_'+suffix).str)} else {u64(0)}
  for sample in 0..if form==0 {4} else {1} {for which in 0..2 {for lane in 0..n+1 {
   x:=(u64(sample+1)*u64(0x9e3779b97f4a7c15))&mask(bits(e));y:=(~x)&mask(bits(e));state,value:=expect(e,n,form,mode,which,lane,x,y)
   mut args:=[u64(which),x,y,u64(lane)];mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:args[..1]},airbitcode.IRMemoryBinding{values:args[1..2]},airbitcode.IRMemoryBinding{values:args[2..3]},airbitcode.IRMemoryBinding{values:args[3..4]},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
   if r:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,100) {assert state!=2&&r.poison==(state==1)&&(r.poison||r.value==value)} else {assert state==2&&err.msg().contains('undef'),err.msg()};scalar_checks++
   if e<64 {if r:=p.run_integer_function(ir,stream,pools,bodies,sf,args,100) {assert state!=2&&r.poison==(state==1)&&(r.poison||r.value==value)} else {assert state==2&&err.msg().contains('undef'),err.msg()};scalar_checks++}
   else if sample==0&&which==0&&lane==0 {if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,100) {panic('integer float PHI')};guards++}
   for prepared in [false,true] {for i in 0..bytes.len {bytes[i]=0xcc};plan.validate(bs,plan.steps())!;for b in bytes {assert b==0xcc}
    if prepared {if _:=plan.run(mut bs,plan.steps()) {assert state==0} else {assert state!=0&&err.msg().contains(if state==2 {'undef'} else {'poison store'}),err.msg()}}
    else {if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,plan.steps()) {assert state==0} else {assert state!=0&&err.msg().contains(if state==2 {'undef'} else {'poison store'}),err.msg()}}
    bytes_match(bytes,state,value)
   }
   for i in 0..bytes.len {bytes[i]=0xcc};if _:=plan.run(mut bs,plan.steps()-1) {panic('short budget')} else {assert err.msg().contains('budget')};for b in bytes {assert b==0xcc};budgets++
   if form==0&&lane<n {assert address!=0;mut result:=[u64(0)]!;unsafe{NativeCast(voidptr(address))(args.data,args.data,&result[0])};assert result[0]==value;native_checks++}
   rows.writeln('join ${n} ${form} ${mode} ${sample} ${which} ${lane} ${state} ${value} PASS')!
   if state==0 {valid++} else if state==1 {poison++} else {undefined++};cases++
   unsafe{args.free();bytes.free();bs.free()}
  }}};plan.free()
 }}}
 mut loops:=0;mut loop_budgets:=0
 for n in [1,2,3,8,16] {for reverse in [false,true] {suffix:='${n}_${reverse}';f:=fi(ir,'l_'+suffix);address:=C.LLVMGetFunctionAddress(native.engine,('lr_'+suffix).str);assert address!=0
  for trip in [0,1,2,3,7,16,1024] {mut words:=[3][16]u64{};for side in 0..3 {for lane in 0..n {words[side][lane]=word(e,lane,side)}};for _ in 0..trip {before:=words;for lane in 0..n {words[0][lane]=before[1][if reverse {n-1-lane} else {lane}];words[1][lane]=before[2][lane];words[2][lane]=before[0][lane]}}
   for lane in 0..n {args:=[u64(trip),u64(lane)];expected:=words[0][lane]^17;r:=p.run_scalar_function(ir,stream,pools,bodies,f,args,20000)!;assert !r.poison&&r.value==expected
    if e<64 {assert p.run_integer_function(ir,stream,pools,bodies,f,args,20000)!.value==expected}
    mut result:=[u64(0)]!;unsafe{NativeCast(voidptr(address))(args.data,args.data,&result[0])};assert result[0]==expected;loops++
    if lane==0 {if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,r.steps-1) {panic('loop budget')} else {assert err.msg().contains('budget')};loop_budgets++}
    rows.writeln('loop ${n} ${reverse} ${trip} ${lane} ${expected} ${r.steps} PASS')!;unsafe{args.free()}
   }
  }
  mf:=fi(ir,'lm_'+suffix);mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:[u64(2)]},airbitcode.IRMemoryBinding{values:[u64(0)]},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
  if _:=p.prepare_memory_function(ir,stream,pools,bodies,mf) {panic('memory loop')};if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,20000) {panic('memory loop')};for b in bytes {assert b==0xcc};guards++;unsafe{bytes.free();bs[0].values.free();bs[1].values.free();bs.free()}
 }}
 line:='AIR-VECTOR-PHI-BATCH: ${e} ${cases} joins (${valid} defined, ${poison} poison, ${undefined} undef), ${native_checks} native, ${scalar_checks} scalar/integer, ${budgets} prewrite budgets, ${loops} native loop values, ${loop_budgets} loop budgets, ${guards} exclusions PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
fn main(){assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!;for e in 0..if os.args.len==4 {1} else {66} {run_batch(os.args[1],root+'/e${e}',e)!};os.write_file(root+'/result.txt','AIR-VECTOR-PHI: '+if os.args.len==4 {'probe PASS\n'} else {'66 formats, i1..i64/half/float, counts 1..16, branch states, simultaneous vector/scalar PHIs, raw native comparisons, 0..1024 loop visits and exclusions PASS\n'})!}
