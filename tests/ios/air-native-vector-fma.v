// SPDX-License-Identifier: GPL-2.0-or-later
module main
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
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
fn C.LLVMGetNamedFunction(voidptr, &char) voidptr
fn C.LLVMDeleteFunction(voidptr)
fn C.LLVMWriteBitcodeToFile(voidptr, &char) int
struct C.LLVMMCJITCompilerOptions {
mut:
 OptLevel u32
 CodeModel int
 NoFramePointerElim int
 EnableFastISel int
 MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeCast = fn (voidptr, voidptr, voidptr)
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn verify(data []u8) ! {
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}
struct NativeModule { context voidptr buffer voidptr engine voidptr }
fn native_module(data []u8, out string, ir airbitcode.IRModule) !NativeModule {
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-vector-fma'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
// LLVM-only reference functions remain after all software bodies are removed.
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
const modes = ['single','mixed','repeat']
const specials = [[u32(0x3f800001),0x3f7ffffe,0xbf800000]!,[u32(0x3f7ffffe),0x3f800001,0xbf800000]!,[u32(0xbf800001),0x3f7ffffe,0x3f800000]!,[u32(0x7f7fffff),0x40000000,0xff7fffff]!,[u32(0xff7fffff),0x40000000,0x7f7fffff]!,[u32(1),0x3f000000,1]!,[u32(0x80000000),0x3f800000,0x80000000]!,[u32(0x7f800000),0,0x3f800000]!,[u32(0x7f800000),0x3f800000,0xff800000]!,[u32(0x3fc00000),0x3f800001,1]!,[u32(0x3fc00000),0x3f800001,0x80000001]!,[u32(0xbfc00000),0x3f800001,1]!]!
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions{if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes{assert b==0xcc}}
fn canonical(value u32) u32 {return if value&0x7fffffff>0x7f800000{u32(0x7fc00000)}else{value}}
fn word(bytes []u8,at int) u32 {mut r:=u32(0);for j in 0..4{r|=u32(bytes[at+j])<<u32(j*8)};return r}
fn check_scalar(r airbitcode.IRScalarRun,value u32,steps int) ! {if r.kind!=.binary32||r.bits!=32||r.poison||r.value!=u64(value)||r.steps!=steps{return error('AIR vector FMA: scalar value/metadata')}}
fn literal(count int,last string,other string) string {mut v:=[]string{cap:count};for i in 0..count{v<<'float '+if i==count-1{last}else{other}};return '<'+v.join(',')+'>'}
fn ops(mode int,count int,native bool,x string,y string,z string) string {
 t:='<${count} x float>';first:=if native{'llvm'}else{'air'};second:=if native||mode==1{'llvm'}else{'air'}
 if mode==0{return '%r = call ${t} @${first}.fma.v${count}f32(${t} ${x},${t} ${y},${t} ${z})\n'}
 return '%a = call ${t} @${first}.fma.v${count}f32(${t} ${x},${t} ${y},${t} ${z})\n %r = call ${t} @${second}.fma.v${count}f32(${t} %a,${t} ${y},${t} ${z})\n'
}
fn loads(count int) string {t:='<${count} x float>';return '%x = load ${t},ptr %in,align 1\n %yp = getelementptr i8,ptr %in,i32 64\n %y = load ${t},ptr %yp,align 1\n %zp = getelementptr i8,ptr %in,i32 128\n %z = load ${t},ptr %zp,align 1\n'}
fn store(count int) string {return '%p = getelementptr i8,ptr %out,i32 5\n store <${count} x float> %r,ptr %p,align 1\n ret void }\n'}
fn source() string {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for count in 1..17 {
  t:='<${count} x float>';air:='air.fma.v${count}f32';llvm:='llvm.fma.v${count}f32'
  s.write_string('declare ${t} @${air}(${t},${t},${t}) #0\n declare ${t} @${llvm}(${t},${t},${t}) #0\n')
  s.write_string('define void @ref_unfused_${count}(ptr %in,ptr %unused,ptr %out) {${loads(count)}store i8 17,ptr %out\n %product = fmul ${t} %x,%y\n %r = fadd ${t} %product,%z\n ${store(count)}')
  for mode,label in modes {name:='${label}_${count}'
   for form in ['typed','loaded','ref_memory'] {
    header:=if form=='typed'{'${t} %x,${t} %y,${t} %z,ptr %out'}else if form=='loaded'{'ptr %in,ptr %out'}else{'ptr %in,ptr %unused,ptr %out'}
    load:=if form=='typed'{''}else{loads(count)}
    s.write_string('define void @${form}_${name}(${header}) {${load}store i8 17,ptr %out\n ${ops(mode,count,form=='ref_memory','%x','%y','%z')}${store(count)}')
   }
   s.write_string('define float @scalar_${name}(float %sx,float %sy,float %sz,i32 %lane) {%x = insertelement ${t} zeroinitializer,float %sx,i32 %lane\n %y = insertelement ${t} zeroinitializer,float %sy,i32 %lane\n %z = insertelement ${t} zeroinitializer,float %sz,i32 %lane\n ${ops(mode,count,false,'%x','%y','%z')}%e = extractelement ${t} %r,i32 %lane\n ret float %e }\n')
   for side in 0..3 {
    for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef','isolate'] {
     value:=literal(count,if state.contains('undef'){'undef'}else{'poison'},'0.0');pre:=if state.starts_with('source_'){'%f = freeze ${t} ${value}\n'}else{''}
     input:=if state.starts_with('source_'){'%f'}else{value};x:=if side==0{input}else{'zeroinitializer'};y:=if side==1{input}else{'zeroinitializer'};z:=if side==2{input}else{'zeroinitializer'}
     post:=if state.starts_with('result_'){'%f = freeze ${t} %r\n'}else{''};target:=if state=='isolate'&&count>1{0}else{count-1};chosen:=if state.starts_with('result_'){'%f'}else{'%r'}
     s.write_string('define float @state_${side}_${state}_${name}() {${pre}${ops(mode,count,false,x,y,z)}${post}%e = extractelement ${t} ${chosen},i32 ${target}\n ret float %e }\n')
    }
    for state in ['poison','undef','freeze','source_freeze','discard_poison','discard_undef'] {
     value:=literal(count,if state.contains('undef')||state=='source_freeze'{'undef'}else{'poison'},'0.0');pre:=if state=='source_freeze'{'%s = freeze ${t} ${value}\n'}else{''}
     input:=if state=='source_freeze'{'%s'}else{value};x:=if side==0{input}else{'zeroinitializer'};y:=if side==1{input}else{'zeroinitializer'};z:=if side==2{input}else{'zeroinitializer'}
     post:=if state=='freeze'{'%f = freeze ${t} %r\n'}else{''};chosen:=if state=='freeze'{'%f'}else{'%r'}
     if state.starts_with('discard_'){s.write_string('define void @case_${side}_${state}_${name}() {${ops(mode,count,false,x,y,z)}ret void }\n')}
     else{s.write_string('define void @guard_${side}_${state}_${name}(ptr %out) {store i8 17,ptr %out\n ${pre}${ops(mode,count,false,x,y,z)}${post}%p = getelementptr i8,ptr %out,i32 5\n store ${t} ${chosen},ptr %p,align 1\n ret void }\n')}
    }
   }
   if count in [2,16] {for native in [false,true] {
    header:=if native{'define void @ref_loop_${name}(ptr %unused,ptr %counts,ptr %out) {%limit = load i64,ptr %counts,align 1\n'}else{'define float @loop_${name}(i64 %limit) {\n'}
    tail:=if native{'store float %e,ptr %out,align 1\n ret void'}else{'ret float %e'}
    s.write_string('${header}br label %body\n body: %v = phi ${t} [${literal(count,'4.0','4.0')},%0],[%r,%body]\n %i = phi i64 [0,%0],[%next,%body]\n ${ops(mode,count,native,'%v',literal(count,'1.0','1.0'),literal(count,'0.25','0.25'))}%next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %e = extractelement ${t} %r,i32 ${count-1}\n ${tail} }\n')
   }}
  }
 }
 s.write_string('declare <2 x float> @alias(<2 x float>,<2 x float>,<2 x float>)\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <2 x float> @air.fma.v2f32(<2 x float> zeroinitializer,<2 x float> zeroinitializer,<2 x float> zeroinitializer)\n %b = call <2 x float> @alias(<2 x float> zeroinitializer,<2 x float> zeroinitializer,<2 x float> zeroinitializer)\n ret void }\n')
 return s.str()
}
fn triple(sample int,lane int) [3]u32 {
 edges:=[u32(0),0x80000000,1,0x3f800000,0x7f7fffff,0x7f800000,0x7fc12345,0xff800000]!
 if sample<512{return [edges[(sample/64+lane)%8],edges[(sample/8+lane)%8],edges[(sample+lane)%8]]!}
 if sample%4==0{return specials[(sample/4+lane)%12]}
 return [u32(sample)*u32(0x9e3779b9)+u32(lane)*u32(0x85ebca6b),u32(sample)*u32(0x85ebca6b)^u32(lane)*u32(0xc2b2ae35),u32(sample)*u32(0xc2b2ae35)^u32(lane)*u32(0x1f123bb5)]!
}
fn set_input(mut input []u8,count int,values [3]u32) {for side in 0..3{for lane in 0..count{for j in 0..4{input[1+side*64+lane*4+j]=u8(values[side]>>u32(j*8))}}}}
fn rejected_profile(assembler string,out string,body string) ! {
 data:=assemble(assembler,out,'target datalayout = "e-p:64:64"\n'+body)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[]u8{len:96,init:0xcc};defer{unsafe{output.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];defer{unsafe{bs.free()}}
 if prepared:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'reject')){prepared.free();panic('invalid vector FMA profile')}
 if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'reject'),mut bs,16){panic('invalid direct vector FMA profile')};unchanged(output)
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0&&C.fegetround()==C.FE_TONEAREST;defer{assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0}
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut vectors:=0;mut lanes:=0;mut scalars:=0;mut states:=0;mut stores:=0;mut refusals:=0;mut budgets:=0;mut loops:=0;mut environments:=0;mut controls:=0;mut distinctions:=0
 for mode,label in modes {for count in 1..17 {
  name:='${label}_${count}';mf:=fi(ir,'typed_'+name);lf:=fi(ir,'loaded_'+name);sf:=fi(ir,'scalar_'+name);steps:=5+int(mode!=0);lsteps:=steps+5;ssteps:=steps+1
  prepared:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert prepared.steps()==steps&&loaded.steps()==lsteps
  mut input:=[]u8{len:200};mut output:=[]u8{len:96,init:0xcc};mut reference:=output.clone();mut args:=[]u64{len:count*3}
  mut bs:=[airbitcode.IRMemoryBinding{values:unsafe{args[..count]}},airbitcode.IRMemoryBinding{values:unsafe{args[count..2*count]}},airbitcode.IRMemoryBinding{values:unsafe{args[2*count..]}},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}];mut lbs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_'+name).str);assert pointer!=0
  for sample in 0..2048 {
   for lane in 0..count{values:=triple(sample,lane);for side in 0..3{args[side*count+lane]=u64(values[side])|u64(0xfedcba98+u32(side))<<32;for j in 0..4{input[1+side*64+lane*4+j]=u8(values[side]>>u32(j*8))}}}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])};assert reference[3]==17
   for lane in 0..count{value:=canonical(word(reference,8+lane*4));for j in 0..4{reference[8+lane*4+j]=u8(value>>u32(j*8))}}
   for is_loaded in [false,true]{for cached in [false,true]{for i in 0..output.len{output[i]=0xcc}
    if is_loaded{loaded.validate(lbs,lsteps)!}else{prepared.validate(bs,steps)!};unchanged(output)
    if is_loaded{if cached{loaded.run(mut lbs,lsteps)!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,lsteps)!}}
    else{if cached{prepared.run(mut bs,steps)!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,steps)!}};assert output==reference
   };vectors++;lanes+=count}
   lane:=sample%count;check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,[args[lane],args[count+lane],args[2*count+lane],u64(lane)],ssteps)!,word(reference,8+lane*4),ssteps)!;scalars++
  }
  for is_loaded in [false,true]{for cached in [false,true]{for i in 0..output.len{output[i]=0xcc}
   if is_loaded{if cached{if _:=loaded.run(mut lbs,lsteps-1){panic('loaded budget')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,lsteps-1){panic('direct loaded budget')}}}
   else{if cached{if _:=prepared.run(mut bs,steps-1){panic('typed budget')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,steps-1){panic('direct typed budget')}}};unchanged(output);budgets++
  }}
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0],ssteps-1){panic('scalar budget')};budgets++
  scope:=bodies.scopes[mf+1]
  for at in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   instruction:=p.instructions[at];if stream.records[bodies.instructions[at].record].code!=34{continue}
   for changed in [airbitcode.IRTypedInstruction{...instruction,flags:32769},airbitcode.IRTypedInstruction{...instruction,calling_convention:8},airbitcode.IRTypedInstruction{...instruction,fast_math_flags:1},airbitcode.IRTypedInstruction{...instruction,attribute_set:1},airbitcode.IRTypedInstruction{...instruction,call_signature:-1},airbitcode.IRTypedInstruction{...instruction,callee_function:-1},airbitcode.IRTypedInstruction{...instruction,operands_count:3},airbitcode.IRTypedInstruction{...instruction,operands_count:5},airbitcode.IRTypedInstruction{...instruction,result_type:-1}] {
    p.instructions[at]=changed;for i in 0..output.len{output[i]=0xcc};if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('call metadata')};unchanged(output);refusals++
   };p.instructions[at]=instruction
   for side in 0..3{slot:=instruction.operands_start+side+1;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1};if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('operand type')};unchanged(output);refusals++;p.operands[slot]=saved}
  }
  for side in 0..3 {
   for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef','isolate'] {
    rejects:=state in ['undef','result_undef'];poison:=state=='poison'||(state=='isolate'&&count==1)
    if r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'state_${side}_${state}_'+name),[],5){assert !rejects&&r.kind==.binary32&&r.bits==32&&r.poison==poison;if !poison{assert r.value==0}}else{assert rejects};states++
   }
   assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'case_${side}_discard_poison_'+name),[],3)!.steps==2+int(mode!=0)
   if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'case_${side}_discard_undef_'+name),[],3){panic('discarded undef')};states+=2
   for state in ['poison','undef','freeze','source_freeze'] {
    f:=fi(ir,'guard_${side}_${state}_'+name);guard:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;bad:=state in ['poison','undef'];mut gb:=[airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
    for cached in [false,true]{for i in 0..output.len{output[i]=0xcc}
     if bad{if cached{if _:=guard.run(mut gb,guard.steps()){panic('poison/undef store')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut gb,guard.steps()){panic('direct poison/undef store')}}}
     else{if cached{guard.run(mut gb,guard.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut gb,guard.steps())!}}
     for i,b in output{assert b==if i==3{u8(17)}else if !bad&&i>=8&&i<8+count*4{u8(0)}else{u8(0xcc)}}
    };guard.free();stores++;unsafe{gb.free()}
   }
  }
  if count in [2,16] {lp:=C.LLVMGetFunctionAddress(native.engine,('ref_loop_'+name).str);assert lp!=0
   for limit in [u64(1),2,3,7,16,257]!{mut raw:=u32(0);unsafe{NativeCast(voidptr(lp))(nil,&limit,&raw)};loop_steps:=int(limit*u64(6+int(mode!=0))+3)
    check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_'+name),[limit],loop_steps)!,canonical(raw),loop_steps)!
    if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_'+name),[limit],loop_steps-1){panic('executed loop budget')};loops++
   }
  }
  if mode==0 {
   unfused:=C.LLVMGetFunctionAddress(native.engine,('ref_unfused_${count}').str);assert unfused!=0
   for i,values in specials{set_input(mut input,count,values);unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])};wanted:=canonical(word(reference,8))
    if i<6{unsafe{NativeCast(voidptr(unfused))(&input[1],nil,&output[3])};for lane in 0..count{assert canonical(word(output,8+lane*4))!=canonical(word(reference,8+lane*4));distinctions++}}
    check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(values[0]),u64(values[1]),u64(values[2]),u64(count-1)],ssteps)!,wanted,ssteps)!
   }
  }
  if count==2 {
   mut expected:=[12]u32{};for i,values in specials{set_input(mut input,count,values);unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])};expected[i]=canonical(word(reference,8))}
   for rounding in [C.FE_TONEAREST,C.FE_DOWNWARD,C.FE_UPWARD,C.FE_TOWARDZERO]!{assert C.fesetround(rounding)==0
    for i,values in specials{check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(values[0]),u64(values[1]),u64(values[2]),0],ssteps)!,expected[i],ssteps)!;assert C.fegetround()==rounding;environments++}
   };assert C.fesetround(C.FE_TONEAREST)==0
  }
  baseline:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0],ssteps)!
  for changed in [airbitcode.IRScalarRun{...baseline,value:1},airbitcode.IRScalarRun{...baseline,kind:.integer},airbitcode.IRScalarRun{...baseline,bits:16},airbitcode.IRScalarRun{...baseline,poison:true},airbitcode.IRScalarRun{...baseline,steps:1}]{check_scalar(changed,0,ssteps) or{controls++;continue};panic('corrupt scalar checker')}
  prepared.free();loaded.free();unsafe{input.free();output.free();reference.free();args.free();bs.free();lbs.free()}
 }}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:'air.fma.v2f32'}
 mut duplicate_output:=[u8(0xcc)];mut duplicate_bindings:=[airbitcode.IRMemoryBinding{data:duplicate_output,writable:true}]
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut duplicate_bindings,4){panic('duplicate AIR key')};unchanged(duplicate_output);unsafe{duplicate_output.free();duplicate_bindings.free()}
 mut guards:=0
 for t in ['<2 x half>','<2 x i32>','<1 x float>']{rejected_profile(os.args[1],root+'/guards/type-${guards}','declare ${t} @air.fma.v2f32(${t},${t},${t})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${t} @air.fma.v2f32(${t} zeroinitializer,${t} zeroinitializer,${t} zeroinitializer)\n ret void }\n')!;guards++}
 for side in 0..3{mut types:=[]string{len:3,init:'<2 x float>'};types[side]='<2 x half>';args:=types.map(it+' zeroinitializer').join(',');rejected_profile(os.args[1],root+'/guards/mixed-${guards}','declare <2 x float> @air.fma.v2f32(${types.join(',')})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @air.fma.v2f32(${args})\n ret void }\n')!;guards++}
 for arity in [2,4]!{types:=[]string{len:arity,init:'<2 x float>'}.join(',');args:=[]string{len:arity,init:'<2 x float> zeroinitializer'}.join(',');rejected_profile(os.args[1],root+'/guards/arity-${guards}','declare <2 x float> @air.fma.v2f32(${types})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @air.fma.v2f32(${args})\n ret void }\n')!;guards++}
 for name in ['air.fma.v0f32','air.fma.v01f32','air.fma.v17f32','air.fma.v2f16','air.fast_fma.v2f32','air.fma.v2f32.spoof','air.fmuladd.v2f32']{rejected_profile(os.args[1],root+'/guards/name-${guards}','declare <2 x float> @${name}(<2 x float>,<2 x float>,<2 x float>)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @${name}(<2 x float> zeroinitializer,<2 x float> zeroinitializer,<2 x float> zeroinitializer)\n ret void }\n')!;guards++}
 rejected_profile(os.args[1],root+'/guards/address','declare <2 x float> @air.fma.v2f32(<2 x float>,<2 x float>,<2 x float>)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @air.fma.v2f32(<2 x float> zeroinitializer,<2 x float> zeroinitializer,<2 x float> zeroinitializer)\n %v = bitcast <2 x float> %r to <2 x i32>\n %w = extractelement <2 x i32> %v,i32 0\n %i = and i32 %w,63\n %p = getelementptr i8,ptr %out,i32 %i\n store i8 17,ptr %p\n ret void }\n')!;guards++
 assert vectors==196608&&lanes==1671168&&scalars==98304&&states==1296&&stores==576&&refusals==960&&budgets==240&&loops==36&&environments==144&&controls==240&&distinctions==816&&guards==16
 line:='AIR-NATIVE-VECTOR-FMA: 16 shapes in three modes, ${vectors} typed/loaded vector cases (each direct and prepared), ${lanes} native lane comparisons, ${scalars} scalar extractions, ${states} three-source state/discard/isolation cases, ${stores} ordered store/repair cases, ${refusals} metadata/type refusals, ${budgets} short budgets, ${loops} native loops with executed-budget refusals, ${environments} host-rounding checks, ${distinctions} fused/unfused lane distinctions, ${controls} result controls, ${guards} overload/type/arity/address guards and duplicate AIR refusal PASS\n'
 os.write_file(root+'/result.txt',line)!;print(line)
}
