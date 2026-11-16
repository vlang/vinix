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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-vector-unary'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
// The native references contain only LLVM calls; AIR bodies are removed before JIT.
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
const operations = ['fabs','floor','ceil','trunc','sqrt','round','rint']
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions{if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes{assert b==0xcc}}
fn canonical(value u32,operation int) u32 {return if operation!=0&&value&0x7fffffff>0x7f800000{u32(0x7fc00000)}else{value}}
fn word(bytes []u8,at int) u32 {mut r:=u32(0);for j in 0..4{r|=u32(bytes[at+j])<<u32(j*8)};return r}
fn check_scalar(result airbitcode.IRScalarRun,value u32,steps int) ! {
 if result.kind!=.binary32||result.bits!=32||result.poison||result.value!=u64(value)||result.steps!=steps{return error('AIR vector unary: scalar value/metadata')}
}
fn literal(count int,state string) string {
 mut lanes:=[]string{cap:count};for i in 0..count{lanes<<'float '+if i==count-1{state}else{'0.0'}};return '<'+lanes.join(',')+'>'
}
fn source() string {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for operation in operations {for count in 1..17 {
  t:='<${count} x float>';name:='${operation}_${count}';air:='air.${operation}.v${count}f32';llvm:='llvm.${operation}.v${count}f32'
  s.write_string('declare ${t} @${air}(${t}) #0\n declare ${t} @${llvm}(${t}) #0\n')
  for mode in ['typed','loaded','ref_memory'] {
   header:=if mode=='typed'{'${t} %x,ptr %out'}else if mode=='loaded'{'ptr %in,ptr %out'}else{'ptr %in,ptr %unused,ptr %out'}
   load:=if mode=='typed'{''}else{'%x = load ${t},ptr %in,align 1\n'}
   first:=if mode=='ref_memory'{llvm}else{air}
   s.write_string('define void @${mode}_${name}(${header}) {${load}store i8 17,ptr %out\n %a = call ${t} @${first}(${t} %x)\n %r = call ${t} @${llvm}(${t} %a)\n %p = getelementptr i8,ptr %out,i32 5\n store ${t} %r,ptr %p,align 1\n ret void }\n')
  }
  s.write_string('define float @scalar_${name}(float %x,i32 %lane) {%v = insertelement ${t} zeroinitializer,float %x,i32 %lane\n %a = call ${t} @${air}(${t} %v)\n %r = call ${t} @${llvm}(${t} %a)\n %e = extractelement ${t} %r,i32 %lane\n ret float %e }\n')
  for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef','isolate'] {
   value:=literal(count,if state.contains('undef'){'undef'}else{'poison'})
   pre:=if state.starts_with('source_'){'%f = freeze ${t} ${value}\n'}else{''}
   input:=if state.starts_with('source_'){'%f'}else{value}
   post:=if state.starts_with('result_'){'%f = freeze ${t} %r\n'}else{''}
   target:=if state=='isolate'&&count>1{0}else{count-1};selected:=if state.starts_with('result_'){'%f'}else{'%r'}
   s.write_string('define float @state_${state}_${name}() {${pre}%r = call ${t} @${air}(${t} ${input})\n ${post}%e = extractelement ${t} ${selected},i32 ${target}\n ret float %e }\n')
  }
  for state in ['poison','undef']{s.write_string('define void @discard_${state}_${name}() {%r = call ${t} @${air}(${t} ${literal(count,state)})\n ret void }\n')}
  for state in ['poison','undef','freeze','source_freeze'] {
   pre:=if state=='source_freeze'{'%s = freeze ${t} ${literal(count,'undef')}\n'}else{''}
   input:=if state=='source_freeze'{'%s'}else{literal(count,if state=='undef'{'undef'}else{'poison'})}
   post:=if state=='freeze'{'%r = freeze ${t} %a\n'}else{''};selected:=if state=='freeze'{'%r'}else{'%a'}
   s.write_string('define void @guard_${state}_${name}(ptr %out) {store i8 17,ptr %out\n ${pre}%a = call ${t} @${air}(${t} ${input})\n ${post}%p = getelementptr i8,ptr %out,i32 5\n store ${t} ${selected},ptr %p,align 1\n ret void }\n')
  }
  if count in [2,16] {
   initial:=literal(count,'4.0').replace('float 0.0','float 4.0')
   for native in [false,true] {
    header:=if native{'define void @ref_loop_${name}(ptr %unused,ptr %counts,ptr %out) {%limit = load i64,ptr %counts,align 1\n'}else{'define float @loop_${name}(i64 %limit) {\n'}
    call:=if native{llvm}else{air};tail:=if native{'store float %e,ptr %out,align 1\n ret void'}else{'ret float %e'}
    s.write_string('${header}br label %body\n body: %v = phi ${t} [${initial},%0],[%r,%body]\n %i = phi i64 [0,%0],[%next,%body]\n %r = call ${t} @${call}(${t} %v)\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %e = extractelement ${t} %r,i32 ${count-1}\n ${tail} }\n')
   }
  }
 }}
 s.write_string('declare <2 x float> @alias(<2 x float>)\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <2 x float> @air.fabs.v2f32(<2 x float> zeroinitializer)\n %b = call <2 x float> @alias(<2 x float> zeroinitializer)\n ret void }\n')
 return s.str()
}
fn rejected_profile(assembler string,out string,body string) ! {
 data:=assemble(assembler,out,'target datalayout = "e-p:64:64"\n'+body)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[]u8{len:96,init:0xcc};defer{unsafe{output.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];defer{unsafe{bs.free()}}
 if prepared:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'reject')){prepared.free();panic('invalid vector profile')}
 if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'reject'),mut bs,16){panic('invalid direct vector profile')};unchanged(output)
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0&&C.fegetround()==C.FE_TONEAREST;defer{assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0}
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 edges:=[u32(0),0x80000000,1,0x80000001,0x007fffff,0x00800000,0x3f000000,0xbf000000,0x3fc00000,0xbfc00000,0x40200000,0xc0200000,0x3f800000,0xbf800000,0x40000000,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7f800001,0xff800001,0x7fc12345,0xffc12345,0x3f000001,0x3effffff,0x4affffff,0x4b000000,0xcaffffff,0xcb000000,0x00800001,0x41100000,0x40800000]!
 mut vectors:=0;mut lanes:=0;mut scalars:=0;mut states:=0;mut stores:=0;mut refusals:=0;mut budgets:=0;mut loops:=0;mut environments:=0;mut controls:=0
 for operation,op in operations {for count in 1..17 {
  name:='${op}_${count}';mf:=fi(ir,'typed_'+name);lf:=fi(ir,'loaded_'+name);sf:=fi(ir,'scalar_'+name)
  prepared:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert prepared.steps()==6&&loaded.steps()==7
  mut input:=[]u8{len:72};mut output:=[]u8{len:96,init:0xcc};mut reference:=output.clone();mut args:=[]u64{len:count}
  mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}];mut lbs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_'+name).str);assert pointer!=0
  for sample in 0..512 {
   for lane in 0..count {
    raw:=if sample<32{edges[(sample+lane)%32]}else{u32(sample)*u32(0x9e3779b9)+u32(lane)*u32(0x85ebca6b)}
    args[lane]=u64(raw)|u64(0xfedcba98)<<32;for j in 0..4{input[1+lane*4+j]=u8(raw>>u32(j*8))}
   }
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])};assert reference[3]==17
   for lane in 0..count{value:=canonical(word(reference,8+lane*4),operation);for j in 0..4{reference[8+lane*4+j]=u8(value>>u32(j*8))}}
   for is_loaded in [false,true] {for cached in [false,true] {
    for i in 0..output.len{output[i]=0xcc}
    if is_loaded{loaded.validate(lbs,7)!}else{prepared.validate(bs,6)!};unchanged(output)
    if is_loaded{if cached{loaded.run(mut lbs,7)!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,7)!}}
    else{if cached{prepared.run(mut bs,6)!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,6)!}}
    assert output==reference
   };vectors++;lanes+=count}
   lane:=sample%count;check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,[args[lane],u64(lane)],5)!,word(reference,8+lane*4),5)!;scalars++
  }
  for is_loaded in [false,true]{for cached in [false,true]{for i in 0..output.len{output[i]=0xcc}
   if is_loaded{if cached{if _:=loaded.run(mut lbs,6){panic('loaded short budget')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,6){panic('direct loaded short budget')}}}
   else{if cached{if _:=prepared.run(mut bs,5){panic('typed short budget')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,5){panic('direct typed short budget')}}};unchanged(output);budgets++
  }}
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0],4){panic('scalar short budget')};budgets++
  scope:=bodies.scopes[mf+1]
  for at in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   instruction:=p.instructions[at];if stream.records[bodies.instructions[at].record].code!=34{continue}
   for changed in [airbitcode.IRTypedInstruction{...instruction,flags:32769},airbitcode.IRTypedInstruction{...instruction,calling_convention:8},airbitcode.IRTypedInstruction{...instruction,fast_math_flags:1},airbitcode.IRTypedInstruction{...instruction,attribute_set:1},airbitcode.IRTypedInstruction{...instruction,call_signature:-1},airbitcode.IRTypedInstruction{...instruction,callee_function:-1},airbitcode.IRTypedInstruction{...instruction,operands_count:1},airbitcode.IRTypedInstruction{...instruction,operands_count:3},airbitcode.IRTypedInstruction{...instruction,result_type:-1}] {
    p.instructions[at]=changed;for i in 0..output.len{output[i]=0xcc};if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('call metadata')};unchanged(output);refusals++
   };p.instructions[at]=instruction
   slot:=instruction.operands_start+1;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1};if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('operand type')};unchanged(output);refusals++;p.operands[slot]=saved
  }
  for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef','isolate'] {
   rejects:=state in ['undef','result_undef'];poison:=state=='poison'||(state=='isolate'&&count==1)
   if r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'state_${state}_'+name),[],4){assert !rejects&&r.kind==.binary32&&r.bits==32&&r.poison==poison;if !poison{assert r.value==0}}else{assert rejects};states++
  }
  assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_poison_'+name),[],2)!.steps==2
  if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_undef_'+name),[],2){panic('discarded undef')};states+=2
  for state in ['poison','undef','freeze','source_freeze'] {
   f:=fi(ir,'guard_${state}_'+name);guard:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;bad:=state in ['poison','undef']
   mut gb:=[airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
   for cached in [false,true]{for i in 0..output.len{output[i]=0xcc}
    if bad{if cached{if _:=guard.run(mut gb,guard.steps()){panic('poison/undef store')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut gb,guard.steps()){panic('direct poison/undef store')}}}
    else{if cached{guard.run(mut gb,guard.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut gb,guard.steps())!}}
    for i,b in output{assert b==if i==3{u8(17)}else if !bad&&i>=8&&i<8+count*4{u8(0)}else{u8(0xcc)}}
   };guard.free();stores++;unsafe{gb.free()}
  }
  if count in [2,16] {
   lp:=C.LLVMGetFunctionAddress(native.engine,('ref_loop_'+name).str);assert lp!=0
   for limit in [u64(1),2,3,7,16,257]!{mut reference_word:=u32(0);unsafe{NativeCast(voidptr(lp))(nil,&limit,&reference_word)};steps:=int(limit*6+3)
    check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_'+name),[limit],steps)!,canonical(reference_word,operation),steps)!
    if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_'+name),[limit],steps-1){panic('executed loop budget')};loops++
   }
  }
  if count==2 {
   mut saved:=[32]u32{}
   for sample,raw in edges {for lane in 0..count{for j in 0..4{input[1+lane*4+j]=u8(raw>>u32(j*8))}};unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])};saved[sample]=canonical(word(reference,8),operation)}
   for mode in [C.FE_TONEAREST,C.FE_DOWNWARD,C.FE_UPWARD,C.FE_TOWARDZERO]!{assert C.fesetround(mode)==0
    for sample,raw in edges{check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(raw),0],5)!,saved[sample],5)!;assert C.fegetround()==mode;environments++}
   };assert C.fesetround(C.FE_TONEAREST)==0
  }
  baseline:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0],5)!
  for changed in [airbitcode.IRScalarRun{...baseline,value:1},airbitcode.IRScalarRun{...baseline,kind:.integer},airbitcode.IRScalarRun{...baseline,bits:16},airbitcode.IRScalarRun{...baseline,poison:true},airbitcode.IRScalarRun{...baseline,steps:4}]{check_scalar(changed,0,5) or{controls++;continue};panic('corrupt scalar checker')}
  prepared.free();loaded.free();unsafe{input.free();output.free();reference.free();args.free();bs.free();lbs.free()}
 }}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:'air.fabs.v2f32'}
 mut duplicate_output:=[u8(0xcc)];mut duplicate_bindings:=[airbitcode.IRMemoryBinding{data:duplicate_output,writable:true}]
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut duplicate_bindings,4){panic('duplicate AIR key')};unchanged(duplicate_output);unsafe{duplicate_output.free();duplicate_bindings.free()}
 mut guards:=0
 for operation in operations {
  for t in ['<2 x half>','<2 x i32>','<1 x float>'] {rejected_profile(os.args[1],root+'/guards/type-${guards}','declare ${t} @air.${operation}.v2f32(${t})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${t} @air.${operation}.v2f32(${t} zeroinitializer)\n ret void }\n')!;guards++}
  for arity in [0,2]! {
   types:=[]string{len:arity,init:'<2 x float>'}.join(',');args:=[]string{len:arity,init:'<2 x float> zeroinitializer'}.join(',')
   rejected_profile(os.args[1],root+'/guards/arity-${guards}','declare <2 x float> @air.${operation}.v2f32(${types})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @air.${operation}.v2f32(${args})\n ret void }\n')!;guards++
  }
  rejected_profile(os.args[1],root+'/guards/address-${guards}','declare <2 x float> @air.${operation}.v2f32(<2 x float>)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @air.${operation}.v2f32(<2 x float> zeroinitializer)\n %v = bitcast <2 x float> %r to <2 x i32>\n %w = extractelement <2 x i32> %v,i32 0\n %i = and i32 %w,63\n %p = getelementptr i8,ptr %out,i32 %i\n store i8 17,ptr %p\n ret void }\n')!;guards++
 }
 for name in ['air.sqrt.v0f32','air.sqrt.v01f32','air.sqrt.v17f32','air.sqrt.v2f16','air.fast_sqrt.v2f32','air.sqrt.v2f32.spoof','air.roundeven.v2f32'] {
  rejected_profile(os.args[1],root+'/guards/name-${guards}','declare <2 x float> @${name}(<2 x float>)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x float> @${name}(<2 x float> zeroinitializer)\n ret void }\n')!;guards++
 }
 assert vectors==114688&&lanes==974848&&scalars==57344&&states==1008&&stores==448&&refusals==2240&&budgets==560&&loops==84&&environments==896&&controls==560&&guards==49
 line:='AIR-NATIVE-VECTOR-UNARY: 112 AIR/LLVM shapes, ${vectors} typed/loaded vector cases (each direct and prepared), ${lanes} native lane comparisons, ${scalars} scalar extractions, ${states} state/discard/isolation cases, ${stores} ordered store/repair cases, ${refusals} metadata/type refusals, ${budgets} short budgets, ${loops} native loops with executed-budget refusals, ${environments} host-rounding checks, ${controls} result controls, ${guards} overload/type/arity/address guards and duplicate AIR refusal PASS\n'
 os.write_file(root+'/result.txt',line)!;print(line)
}
