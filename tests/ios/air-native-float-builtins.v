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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-float-builtins'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
const air_names = ['air.fabs.f32', 'air.floor.f32', 'air.ceil.f32', 'air.trunc.f32']
const llvm_names = ['llvm.fabs.f32', 'llvm.floor.f32', 'llvm.ceil.f32', 'llvm.trunc.f32']
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn result_is_nan(bits u32) bool {return bits&0x7fffffff>0x7f800000}
fn operations(mode int,native bool) string {
 op:=mode%4;name:=if native{llvm_names[op]}else{air_names[op]}
 return if mode<4{'%r = call float @${name}(float %x)\n'}else{'%a = call float @${name}(float %x)\n %r = call float @${llvm_names[op]}(float %a)\n'}
}
fn source() string {
 mut s:=strings.new_builder(32768);s.write_string('target datalayout = "e-p:64:64"\n')
 for name in air_names{s.write_string('declare float @${name}(float) #0\n')}
 for name in llvm_names{s.write_string('declare float @${name}(float) #0\n')}
 s.write_string('declare float @alias(float)\n declare i32 @llvm.ctlz.i32(i32,i1 immarg)\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for mode in 0..8 {
  ops:=operations(mode,false);ref:=operations(mode,true)
  s.write_string('define float @eval_${mode}(float %x) {${ops}ret float %r }\n')
  tail:='%p = getelementptr i8,ptr %out,i32 5\n store float %r,ptr %p,align 1\n ret void }\n'
  s.write_string('define void @memory_${mode}(float %x,ptr %out) {store i8 17,ptr %out\n ${ops}${tail}')
  s.write_string('define void @loaded_${mode}(ptr %in,ptr %out) {%x = load float,ptr %in,align 1\n store i8 17,ptr %out\n ${ops}${tail}')
  s.write_string('define void @ref_memory_${mode}(ptr %in,ptr %unused,ptr %out) {%x = load float,ptr %in,align 1\n store i8 17,ptr %out\n ${ref}${tail}')
 }
 for op,name in air_names {
  for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef'] {
   bad:=if state.contains('undef'){'undef'}else{'poison'};input:=if state.starts_with('source_'){'%f'}else{bad}
   prefix:=if state.starts_with('source_'){'%f = freeze float ${bad}\n'}else{''}
   suffix:=if state.starts_with('result_'){'%f = freeze float %r\n ret float %f'}else{'ret float %r'}
   s.write_string('define float @state_${op}_${state}() {${prefix}%r = call float @${name}(float ${input})\n ${suffix} }\n')
  }
  s.write_string('define void @discard_${op}() {%r = call float @${name}(float poison)\n ret void }\n define void @duplicate_${op}(ptr %out) {store i8 17,ptr %out\n %a = call float @${name}(float 1.0)\n %b = call float @alias(float 1.0)\n ret void }\n')
  for native in [false,true] {
   callee:=if native{llvm_names[op]}else{name}
   s.write_string(if native{'define void @ref_loop_${op}(ptr %in,ptr %counts,ptr %out) {%x = load float,ptr %in,align 1\n %limit = load i64,ptr %counts,align 1\n'}else{'define float @loop_${op}(float %x,i64 %limit) {\n'})
   s.write_string('br label %body\n body: %v = phi float [%x,%0],[%sum,%body]\n %i = phi i64 [0,%0],[%next,%body]\n %r = call float @${callee}(float %v)\n %sum = fadd float %r,0.25\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: ')
   s.write_string(if native{'store float %sum,ptr %out,align 1\n ret void }\n'}else{'ret float %sum }\n'})
  }
 }
 return s.str()
}
fn rejected_profiles(assembler string,root string) !int {
 mut checks:=0
 for op,name in air_names {
  for typ in ['half','i32','<2 x float>'] {
   source:='target datalayout = "e-p:64:64"\n declare ${typ} @${name}(${typ})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${typ} @${name}(${typ} zeroinitializer)\n ret void }\n'
   rejected_profile(assembler,root+'/signature-${op}-${checks}',source)!;checks++
  }
  source:='target datalayout = "e-p:64:64"\n declare float @${name}(float)\n define void @reject(ptr %out) {%r = call float @${name}(float 1.0)\n %bits = bitcast float %r to i32\n %index = and i32 %bits,63\n %p = getelementptr i8,ptr %out,i32 %index\n store i8 17,ptr %p\n ret void }\n'
  rejected_profile(assembler,root+'/address-${op}',source)!;checks++
 }
 for i,name in ['air.fast_floor.f32','air.sqrt.f32','air.floor.f64','air.floor.v2f32'] {
  typ:=if i==2{'double'}else if i==3{'<2 x float>'}else{'float'}
  source:='target datalayout = "e-p:64:64"\n declare ${typ} @${name}(${typ})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${typ} @${name}(${typ} zeroinitializer)\n ret void }\n'
  rejected_profile(assembler,root+'/overload-${i}',source)!;checks++
 }
 return checks
}
fn rejected_profile(assembler string,out string,source string) ! {
 data:=assemble(assembler,out,source)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[]u8{len:72,init:0xcc};defer{unsafe{output.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];defer{unsafe{bs.free()}};f:=fi(ir,'reject')
 if prepared:=p.prepare_memory_function(ir,stream,pools,bodies,f){prepared.free();panic('invalid prepared float profile')}
 if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,16){panic('invalid direct float profile')};unchanged(output)
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0&&C.fegetround()==C.FE_TONEAREST
 defer{assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0}
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut native_checks:=0;mut scalar_checks:=0;mut budgets:=0;mut refusals:=0;mut nan_checks:=0
 edges:=[u32(0),1,0x007fffff,0x00800000,0x3effffff,0x3f000000,0x3f000001,0x3f7fffff,0x3f800000,0x3f800001,0x3fbfffff,0x3fc00000,0x3fc00001,0x3fffffff,0x40000000,0x40000001,0x401fffff,0x40200000,0x40200001,0x405fffff,0x40600000,0x40600001,0x4affffff,0x4b000000,0x4b000001,0x4b7fffff,0x7f7fffff,0x7f800000,0x7f800001,0x7fc00000,0x7fc12345,0x7fffffff]!
 for mode in 0..8 {
  sf:=fi(ir,'eval_${mode}');mf:=fi(ir,'memory_${mode}');lf:=fi(ir,'loaded_${mode}');steps:=if mode<4{2}else{3}
  memory:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert memory.steps()==steps+3&&loaded.steps()==steps+4
  mut input:=[]u8{len:8};mut output:=[]u8{len:72,init:0xcc};mut reference:=output.clone();mut args:=[u64(0)]
  mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  mut lbs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${mode}').str);assert pointer!=0
  for sample in 0..8192 {
   x:=if sample<64{edges[sample/2]|u32(sample%2)<<31}else{u32(sample)*u32(0x9e3779b9)^u32(sample>>3)*u32(0x1f123bb5)}
   args[0]=u64(x)|u64(0xfedcba98)<<32;for i in 0..4{input[1+i]=u8(x>>u32(i*8))}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(pointer))(&input[1],unsafe{nil},&reference[3])}
   mut value:=u32(0);for i in 0..4{value|=u32(reference[8+i])<<u32(i*8)}
   // Rounding uses the established positive canonical NaN policy. fabs is exact.
   if mode%4!=0&&result_is_nan(value){value=0x7fc00000;for i in 0..4{reference[8+i]=u8(value>>u32(i*8))};nan_checks++}
   result:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps)!;assert !result.poison&&result.value==value&&result.steps==steps;scalar_checks++
   for is_loaded in [false,true] {
    for prepared in [false,true] {
     for i in 0..output.len{output[i]=0xcc}
     if is_loaded{loaded.validate(lbs,loaded.steps())!}else{memory.validate(bs,memory.steps())!};unchanged(output)
     if is_loaded{if prepared{loaded.run(mut lbs,loaded.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,loaded.steps())!}}
     else{if prepared{memory.run(mut bs,memory.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps())!}}
     assert output==reference
    };native_checks++
   }
  }
  for i in 0..output.len{output[i]=0xcc}
  if _:=memory.run(mut bs,memory.steps()-1){panic('short prepared budget')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps()-1){panic('short memory budget')};unchanged(output);budgets+=2
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps-1){panic('short scalar budget')};budgets++
  if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,steps){panic('integer-only scalar call')};refusals++
  if mode<4 {
   scope:=bodies.scopes[mf+1]
   for at in scope.instructions_start..scope.instructions_start+scope.instructions_count {
    op:=p.instructions[at];if stream.records[bodies.instructions[at].record].code!=34{continue}
    for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:1},airbitcode.IRTypedInstruction{...op,operands_count:3},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
     p.instructions[at]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('bad call metadata')};unchanged(output);refusals++
    };p.instructions[at]=op
   }
  }
  memory.free();loaded.free();unsafe{input.free();output.free();reference.free();args.free();bs.free();lbs.free()}
 }
 mut states:=0
 for op in 0..4{for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef']{
  f:=fi(ir,'state_${op}_${state}');undef:=state.contains('undef')&&!state.starts_with('source_')
  if result:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4){assert !undef;poison:=state=='poison';assert result.poison==poison;if !poison{assert result.value==u64(0)}}else{assert undef};states++
 };assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_${op}'),[],2)!.steps==2;states++}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias')
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 for op,name in air_names{functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:name};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate_${op}'),mut bs,4){panic('duplicate AIR identity')};unchanged(output);refusals++}
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values}
 helper:=stream.records[ir.functions[fi(ir,'llvm.ctlz.i32')].record];attribute:=stream.values[helper.values_start+6];assert attribute!=0
 mut a:=[u64(0)];mut bytes:=[]u8{len:72,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 for mode,name in air_names {
  record:=stream.records[ir.functions[fi(ir,name)].record];saved:=values[record.values_start+6];values[record.values_start+6]=attribute
  if _:=p.run_memory_function(ir,view_stream,pools,bodies,fi(ir,'memory_${mode}'),mut bindings,16){panic('AIR declaration immarg')}else{assert err.msg().contains('attribute'),err.msg()};unchanged(bytes);refusals++
  values[record.values_start+6]=saved
 }
 unsafe{a.free();bytes.free();bindings.free()}
 mut loops:=0
 for op in 0..4{pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_loop_${op}').str);assert pointer!=0
  for limit in [u64(1),2,3,7,16,257]!{for seed in [u32(0),0x3fc00000,0xbf400000,0xc0200000]!{
   mut reference:=u32(0);unsafe{NativeCast(voidptr(pointer))(&seed,&limit,&reference)}
   steps:=int(limit*7+2);args:=[u64(seed)|u64(0xfedcba98)<<32,limit];r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${op}'),args,steps)!;assert !r.poison&&r.value==reference&&r.steps==steps
   if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${op}'),args,steps-1){panic('executed loop budget')};loops++;unsafe{args.free()}
  }}
 }
 mut environments:=0
 for rounding in [C.FE_TONEAREST,C.FE_DOWNWARD,C.FE_UPWARD,C.FE_TOWARDZERO]! {
  assert C.fesetround(rounding)==0
  for op in 0..4{for edge in edges{for sign in [u32(0),0x80000000]!{
   x:=edge|sign;pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${op}').str);mut reference:=[u8(0xcc)].repeat(16);unsafe{NativeCast(voidptr(pointer))(&x,unsafe{nil},reference.data)}
   mut expected:=u32(0);for i in 0..4{expected|=u32(reference[5+i])<<u32(i*8)};if op!=0&&result_is_nan(expected){expected=0x7fc00000}
   r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'eval_${op}'),[u64(x)],2)!;assert !r.poison&&r.value==expected&&C.fegetround()==rounding;environments++;unsafe{reference.free()}
  }}}
 }
 guards:=rejected_profiles(os.args[1],root+'/guards')!
 assert native_checks==131072&&scalar_checks==65536&&states==28&&loops==96&&refusals==52&&budgets==24&&environments==1024&&nan_checks>0&&guards==20
 line:='AIR-NATIVE-FLOAT-BUILTINS: ${native_checks} native typed/loaded memory cases (direct and prepared), ${scalar_checks} scalar checks (${nan_checks} canonical rounding NaNs), ${states} state/discard checks, ${refusals} profile/metadata/duplicate refusals, ${budgets} short budgets, ${loops} native loop comparisons with executed-budget refusals, ${environments} native rounding-environment checks and ${guards} signature/overload/address guards PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
 unsafe{output.free();bs.free()}
}
