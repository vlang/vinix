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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-half-fma'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
// Reference bodies contain LLVM calls only; native_module removes AIR bodies.
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn canonical(word u16) u16 {return if word&0x7fff>0x7c00{u16(0x7e00)}else{word}}
fn word(bytes []u8,offset int) u16 {mut value:=u16(0);for i in 0..2{value|=u16(bytes[offset+i])<<u16(i*8)};return value}
fn check_scalar(r airbitcode.IRScalarRun,value u16,steps int) ! {
 if r.kind!=.binary16||r.bits!=16||r.poison||r.steps!=steps||r.value!=u64(value){return error('FMA result value/metadata')}
}
fn operations(mode int,native bool) string {
 name:=if native{'llvm.fma.f16'}else{'air.fma.f16'}
 if mode==0{return '%r = call half @${name}(half %x,half %y,half %z)\n'}
 second:=if native||mode==1{'llvm.fma.f16'}else{'air.fma.f16'}
 return '%a = call half @${name}(half %x,half %y,half %z)\n %r = call half @${second}(half %a,half %y,half %z)\n'
}
const load_inputs = '%x = load half,ptr %in,align 1\n %yp = getelementptr i8,ptr %in,i32 2\n %y = load half,ptr %yp,align 1\n %zp = getelementptr i8,ptr %in,i32 4\n %z = load half,ptr %zp,align 1\n'
const store_result = '%p = getelementptr i8,ptr %out,i32 5\n store half %r,ptr %p,align 1\n ret void }\n'
fn source() string {
 mut s:=strings.new_builder(32768);s.write_string('target datalayout = "e-p:64:64"\n declare half @air.fma.f16(half,half,half) #0\n declare half @llvm.fma.f16(half,half,half) #0\n declare half @alias(half,half,half)\n declare i32 @llvm.ctlz.i32(i32,i1 immarg)\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for mode in 0..3 {
  ops:=operations(mode,false);ref:=operations(mode,true)
  s.write_string('define half @eval_${mode}(half %x,half %y,half %z) {${ops}ret half %r }\n')
  s.write_string('define void @memory_${mode}(half %x,half %y,half %z,ptr %out) {store i8 17,ptr %out\n ${ops}${store_result}')
  s.write_string('define void @loaded_${mode}(ptr %in,ptr %out) {${load_inputs}store i8 17,ptr %out\n ${ops}${store_result}')
  s.write_string('define void @ref_memory_${mode}(ptr %in,ptr %unused,ptr %out) {${load_inputs}store i8 17,ptr %out\n ${ref}${store_result}')
 }
 s.write_string('define void @ref_unfused(ptr %in,ptr %unused,ptr %out) {${load_inputs}store i8 17,ptr %out\n %product = fmul half %x,%y\n %r = fadd half %product,%z\n ${store_result}')
 for side in 0..3 {
  for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef'] {
   bad:=if state.contains('undef'){'undef'}else{'poison'};input:=if state.starts_with('source_'){'%f'}else{bad}
   args:='half ${if side==0{input}else{'0.0'}},half ${if side==1{input}else{'0.0'}},half ${if side==2{input}else{'0.0'}}'
   prefix:=if state.starts_with('source_'){'%f = freeze half ${bad}\n'}else{''};suffix:=if state.starts_with('result_'){'%f = freeze half %r\n ret half %f'}else{'ret half %r'}
   s.write_string('define half @state_${side}_${state}() {${prefix}%r = call half @air.fma.f16(${args})\n ${suffix} }\n')
  }
  args:='half ${if side==0{'poison'}else{'0.0'}},half ${if side==1{'poison'}else{'0.0'}},half ${if side==2{'poison'}else{'0.0'}}'
  s.write_string('define void @discard_${side}() {%r = call half @air.fma.f16(${args})\n ret void }\n')
  for bad in ['poison','undef'] {
   bad_args:=args.replace('poison',bad)
   s.write_string('define void @guard_${side}_${bad}(ptr %out) {store i8 17,ptr %out\n %r = call half @air.fma.f16(${bad_args})\n ${store_result}')
  }
  for repair in ['freeze','select'] {
   choice:=if repair=='freeze'{'freeze half %bad'}else{'select i1 false,half %bad,half 1.0'}
   s.write_string('define void @repair_${side}_${repair}(ptr %out) {store i8 17,ptr %out\n %bad = call half @air.fma.f16(${args})\n %r = ${choice}\n ${store_result}')
  }
 }
 s.write_string('define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call half @air.fma.f16(half 1.0,half 1.0,half 1.0)\n %b = call half @alias(half 1.0,half 1.0,half 1.0)\n ret void }\n')
 for native in [false,true] {
  name:=if native{'llvm.fma.f16'}else{'air.fma.f16'}
  s.write_string(if native{'define void @ref_loop(ptr %in,ptr %counts,ptr %out) {${load_inputs}%limit = load i64,ptr %counts,align 1\n'}else{'define half @loop(half %x,half %y,half %z,i64 %limit) {\n'})
  s.write_string('br label %body\n body: %v = phi half [%x,%0],[%r,%body]\n %i = phi i64 [0,%0],[%next,%body]\n %r = call half @${name}(half %v,half %y,half %z)\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: ')
  s.write_string(if native{'store half %r,ptr %out,align 1\n ret void }\n'}else{'ret half %r }\n'})
 }
 s.write_string(coexist_source())
 return s.str()
}
fn native_word(pointer u64,triple [3]u16) u16 {
 mut input:=[16]u8{};mut output:=[16]u8{init:0xcc}
 for i in 0..3{for j in 0..2{input[1+i*2+j]=u8(triple[i]>>u16(j*8))}}
 unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&output[0])}
 assert output[0]==17;for i in 1..16{if i<5||i>=7{assert output[i]==0xcc}}
 mut value:=u16(0);for i in 0..2{value|=u16(output[5+i])<<u16(i*8)};return value
}
fn rejected_profile(assembler string,out string,body string) ! {
 data:=assemble(assembler,out,'target datalayout = "e-p:64:64"\n'+body)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[]u8{len:72,init:0xcc};defer{unsafe{output.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];defer{unsafe{bs.free()}};f:=fi(ir,'reject')
 if prepared:=p.prepare_memory_function(ir,stream,pools,bodies,f){prepared.free();panic('invalid prepared FMA profile')}
 if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,16){panic('invalid direct FMA profile')};unchanged(output)
}
fn rejected_profiles(assembler string,root string) !int {
 mut count:=0
 for typ in ['float','i16','<2 x half>'] {
  rejected_profile(assembler,root+'/format-${count}','declare ${typ} @air.fma.f16(${typ},${typ},${typ})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${typ} @air.fma.f16(${typ} zeroinitializer,${typ} zeroinitializer,${typ} zeroinitializer)\n ret void }\n')!;count++
 }
 for other in ['float','i16'] {
  rejected_profile(assembler,root+'/mixed-${count}','declare half @air.fma.f16(half,${other},half)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call half @air.fma.f16(half 1.0,${other} zeroinitializer,half 1.0)\n ret void }\n')!;count++
 }
 for arity in [2,4]! {
  types:=[]string{len:arity,init:'half'}.join(',');args:=[]string{len:arity,init:'half 1.0'}.join(',')
  rejected_profile(assembler,root+'/arity-${arity}','declare half @air.fma.f16(${types})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call half @air.fma.f16(${args})\n ret void }\n')!;count++
 }
 for name in ['air.fast_fma.f16','air.fma.f64','air.fma.v2f16','air.fma.f16.spoof'] {
  rejected_profile(assembler,root+'/name-${count}','declare half @${name}(half,half,half)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call half @${name}(half 1.0,half 1.0,half 1.0)\n ret void }\n')!;count++
 }
 rejected_profile(assembler,root+'/address','declare half @air.fma.f16(half,half,half)\n define void @reject(ptr %out) {%r = call half @air.fma.f16(half 1.0,half 1.0,half 1.0)\n %raw = bitcast half %r to i16\n %w = zext i16 %raw to i32\n %i = and i32 %w,63\n %p = getelementptr i8,ptr %out,i32 %i\n store i8 17,ptr %p\n ret void }\n')!;return count+1
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0&&C.fegetround()==C.FE_TONEAREST;defer{assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0}
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut native_checks:=0;mut scalar_checks:=0;mut nan_checks:=0;mut boundaries:=0;mut refusals:=0;mut budgets:=0
 edges:=[u16(0),0x8000,1,0x8001,0x03ff,0x0400,0x3800,0x3c00,0xbc00,0x3c01,0x3bfe,0x4000,0x7bff,0xfbff,0x7c00,0xfc00,0x7c01,0xfc01,0x7e45,0xfe45]!
 for mode in 0..3 {
  sf:=fi(ir,'eval_${mode}');mf:=fi(ir,'memory_${mode}');lf:=fi(ir,'loaded_${mode}');steps:=if mode==0{2}else{3}
  memory:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert memory.steps()==steps+3&&loaded.steps()==steps+8
  mut input:=[]u8{len:16};mut output:=[]u8{len:72,init:0xcc};mut reference:=output.clone();mut args:=[u64(0),0,0]
  mut bs:=[airbitcode.IRMemoryBinding{values:unsafe{args[..1]}},airbitcode.IRMemoryBinding{values:unsafe{args[1..2]}},airbitcode.IRMemoryBinding{values:unsafe{args[2..]}},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  mut lbs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${mode}').str);assert pointer!=0
  // Boundary triples plus each binary16 encoding in each operand position.
  for sample in 0..204608 {
   mut x:=u16(0);mut y:=u16(0);mut z:=u16(0)
   if sample<8000 {x=edges[sample/400];y=edges[(sample/20)%20];z=edges[sample%20];boundaries++}
   else {
    index:=sample-8000;side:=index/65536;raw:=u16(index%65536)
    x=u16(u32(raw)*4051+17);y=u16(u32(raw)*7919+31);z=u16(u32(raw)*6599+47)
    match side {0{x=raw} 1{y=raw} else{z=raw}}
    if sample%3==0 {y=0x3c01;z=x^u16(0x8000);if side==1{y=raw};if side==2{z=raw}}
   }
   for i,value in [x,y,z]!{args[i]=u64(value)|(u64(0xfedcba987654)+u64(i))<<16;for j in 0..2{input[1+i*2+j]=u8(value>>u16(j*8))}}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])}
   raw:=word(reference,8);value:=canonical(raw);if raw&0x7fff>0x7c00{nan_checks++};for i in 0..2{reference[8+i]=u8(value>>u16(i*8))}
   check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps)!,value,steps)!;scalar_checks++
   for is_loaded in [false,true] {for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc}
    if is_loaded{loaded.validate(lbs,loaded.steps())!}else{memory.validate(bs,memory.steps())!};unchanged(output)
    if is_loaded{if prepared{loaded.run(mut lbs,loaded.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,loaded.steps())!}}
    else{if prepared{memory.run(mut bs,memory.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps())!}}
    assert output==reference
   };native_checks++}
  }
  for i in 0..output.len{output[i]=0xcc}
  if _:=memory.run(mut bs,memory.steps()-1){panic('prepared budget')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps()-1){panic('direct budget')};unchanged(output);budgets+=2
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps-1){panic('scalar budget')};budgets++
  if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,steps){panic('integer-only call')};refusals++
  scope:=bodies.scopes[mf+1]
  for at in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   op:=p.instructions[at];if stream.records[bodies.instructions[at].record].code!=34{continue}
   for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:3},airbitcode.IRTypedInstruction{...op,operands_count:5},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
    p.instructions[at]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('call metadata')};unchanged(output);refusals++
   };p.instructions[at]=op
   for side in 0..3{slot:=op.operands_start+side+1;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1}
    if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('operand type')};unchanged(output);refusals++;p.operands[slot]=saved
   }
  }
  memory.free();loaded.free();unsafe{input.free();output.free();reference.free();args.free();bs.free();lbs.free()}
 }
 println('FMA all numeric/metadata modes PASS')
 mut states:=0;mut memory_states:=0;mut repairs:=0
 for side in 0..3{for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef']{
  undef:=state.contains('undef')&&!state.starts_with('source_');f:=fi(ir,'state_${side}_${state}')
  if result:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4){assert !undef&&result.poison==(state=='poison');if !result.poison{assert result.value==0}}else{assert undef};states++
 };assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_${side}'),[],2)!.steps==2;states++
  for state in ['poison','undef','freeze','select'] {
   bad:=state in ['poison','undef'];name:='${if bad{'guard'}else{'repair'}}_${side}_${state}';f:=fi(ir,name);prepared:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
   mut output:=[]u8{len:72,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
   for cached in [false,true] {
    for i in 0..output.len{output[i]=0xcc}
    if bad{if cached{if _:=prepared.run(mut bs,prepared.steps()){panic('prepared indeterminate store')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,prepared.steps()){panic('direct indeterminate store')}};assert output[3]==17;for i,b in output{if i!=3{assert b==0xcc}}}
    else{if cached{prepared.run(mut bs,prepared.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut bs,prepared.steps())!};wanted:=if state=='select'{u16(0x3c00)}else{u16(0)};assert output[3]==17&&word(output,8)==wanted;for i,b in output{if i!=3&&(i<8||i>=10){assert b==0xcc}}}
   }
   if bad{memory_states++}else{repairs++};prepared.free();unsafe{output.free();bs.free()}
  }
 }
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:'air.fma.f16'}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,4){panic('duplicate AIR identity')};unchanged(output);refusals++
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values};helper:=stream.records[ir.functions[fi(ir,'llvm.ctlz.i32')].record];attribute:=stream.values[helper.values_start+6];assert attribute!=0
 record:=stream.records[ir.functions[fi(ir,'air.fma.f16')].record];values[record.values_start+6]=attribute
 mut a:=[u64(0)];mut bytes:=[]u8{len:72,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 if _:=p.run_memory_function(ir,view_stream,pools,bodies,fi(ir,'memory_0'),mut bindings,16){panic('AIR declaration immarg')}else{assert err.msg().contains('attribute'),err.msg()};unchanged(bytes);refusals++;unsafe{a.free();bytes.free();bindings.free()}
 mut loops:=0;loop_pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_loop');assert loop_pointer!=0
 for limit in [u64(1),2,3,7,16,257]!{for triple in [[u16(0),0x3c00,0x3400]!,[u16(0xbc00),0x3c01,0x3c00]!,[u16(0x3c00),0xbc00,0x3800]!,[u16(0x3800),0x3800,1]!]!{
  mut reference:=u16(0);unsafe{NativeCast(voidptr(loop_pointer))(&triple[0],&limit,&reference)}
  steps:=int(limit*6+2);args:=[u64(triple[0])|u64(0xfedcba987654)<<16,u64(triple[1])|u64(0x123456789abc)<<16,u64(triple[2])|u64(0x9876543210ab)<<16,limit]
  check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),args,steps)!,canonical(reference),steps)!
  if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),args,steps-1){panic('executed loop budget')};loops++;unsafe{args.free()}
 }}
 // The first six finite triples distinguish a single rounding from fmul+fadd.
 specials:=[[u16(0x3c01),0x3bfe,0xbc00]!,[u16(0x3bfe),0x3c01,0xbc00]!,[u16(0xbc01),0x3bfe,0x3c00]!,[u16(0x7bff),0x4000,0xfbff]!,[u16(0xfbff),0x4000,0x7bff]!,[u16(1),0x3800,1]!,[u16(0x8000),0x3c00,0x8000]!,[u16(0x7c00),0,0x3c00]!,[u16(0x7c00),0x3c00,0xfc00]!,[u16(0x3e00),0x3c01,1]!,[u16(0x3e00),0x3c01,0x8001]!,[u16(0xbe00),0x3c01,1]!]!
 reference_pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_memory_0');unfused_pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_unfused');assert reference_pointer!=0&&unfused_pointer!=0
 mut expected:=[12]u16{};mut distinctions:=0;assert C.fegetround()==C.FE_TONEAREST
 for i,triple in specials{expected[i]=canonical(native_word(reference_pointer,triple));if i<6{assert expected[i]!=canonical(native_word(unfused_pointer,triple));distinctions++}}
 mut environments:=0
 for rounding in [C.FE_TONEAREST,C.FE_DOWNWARD,C.FE_UPWARD,C.FE_TOWARDZERO]!{assert C.fesetround(rounding)==0
  for i,triple in specials{args:=[u64(triple[0]),u64(triple[1]),u64(triple[2])];check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'eval_0'),args,2)!,expected[i],2)!;assert C.fegetround()==rounding;environments++;unsafe{args.free()}}
 };assert C.fesetround(C.FE_TONEAREST)==0
 baseline:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'eval_0'),[u64(0x3c01),0x3bfe,0xbc00],2)!;mut controls:=0
 for changed in [airbitcode.IRScalarRun{...baseline,value:baseline.value^1},airbitcode.IRScalarRun{...baseline,kind:.integer},airbitcode.IRScalarRun{...baseline,bits:32},airbitcode.IRScalarRun{...baseline,poison:true},airbitcode.IRScalarRun{...baseline,steps:1}] {check_scalar(changed,u16(baseline.value),2) or {controls++;continue};panic('corrupted scalar result')}
 coexist_pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_coexist');assert coexist_pointer!=0
 mut coexist:=0
 for sample in 0..1024 {
  triple:=[u16((sample*4051)%0x7bff),u16(0x3800+sample%1024),u16((sample*4051)%0x7bff)|u16(0x8000)]!
  mut reference:=u64(0);unsafe{NativeCast(voidptr(coexist_pointer))(&triple[0],nil,&reference)}
  args:=[u64(triple[0])|~u64(0xffff),u64(triple[1])|~u64(0xffff),u64(triple[2])|~u64(0xffff)]
  r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'coexist'),args,32)!
  assert !r.poison&&r.value==reference;coexist++;unsafe{args.free()}
 }
 assert coexist==1024
 os.write_file(root+'/coexist-result.txt','AIR-HALF-FMA-COEXIST: 1024 native mixed AIR/LLVM f16/f32 FMA and earlier half unary cache comparisons PASS\n')!
 guards:=rejected_profiles(os.args[1],root+'/guards')!
 assert native_checks==1227648&&scalar_checks==613824&&boundaries==24000&&nan_checks>0&&states==21&&memory_states==6&&repairs==6&&refusals==65&&budgets==9&&loops==24&&environments==48&&distinctions==6&&controls==5&&guards==12
 line:='AIR-NATIVE-HALF-FMA: ${native_checks} native typed/loaded memory cases (direct and prepared), ${scalar_checks} scalar checks (${nan_checks} canonical NaNs, ${boundaries} boundary triples), ${states} state/discard checks, ${memory_states} ordered poison/undef stores, ${repairs} memory freeze/lazy repairs, ${refusals} metadata/type/profile refusals, ${budgets} short budgets, ${loops} native loops with executed-budget refusals, ${environments} host-rounding checks, ${distinctions} fused/unfused distinctions, ${controls} result controls and ${guards} signature/overload/address guards PASS\n'
 os.write_file(root+'/result.txt',line)!;print(line);unsafe{output.free();bs.free()}
}

fn coexist_source() string {
 mut s:=strings.new_builder(8192)
 for namespace in ['air','llvm'] {
  s.write_string('declare float @${namespace}.fma.f32(float,float,float) #0\n declare half @${namespace}.fabs.f16(half) #0\n declare half @${namespace}.rint.f16(half) #0\n')
 }
 for native in [false,true] {
  namespace:=if native {'llvm'}else{'air'}
  if native {s.write_string('define void @ref_coexist(ptr %in,ptr %unused,ptr %out) {${load_inputs}')}
  else {s.write_string('define i64 @coexist(half %x,half %y,half %z) {\n')}
  s.write_string(' %h = call half @${namespace}.fma.f16(half %x,half %y,half %z)\n %xf = fpext half %x to float\n %yf = fpext half %y to float\n %zf = fpext half %z to float\n %f = call float @${namespace}.fma.f32(float %xf,float %yf,float %zf)\n %abs = call half @${namespace}.fabs.f16(half %h)\n %rounded = call half @${namespace}.rint.f16(half %h)\n %hr = bitcast half %h to i16\n %fr = bitcast float %f to i32\n %ar = bitcast half %abs to i16\n %rr = bitcast half %rounded to i16\n %hw = zext i16 %hr to i64\n %fw = zext i32 %fr to i64\n %aw = zext i16 %ar to i64\n %rw = zext i16 %rr to i64\n %hs = shl i64 %hw,32\n %as = shl i64 %aw,48\n %rs = shl i64 %rw,16\n %a = xor i64 %hs,%fw\n %b = xor i64 %as,%rs\n %r = xor i64 %a,%b\n')
  s.write_string(if native {'store i64 %r,ptr %out,align 1\n ret void }\n'}else{'ret i64 %r }\n'})
 }
 return s.str()
}
