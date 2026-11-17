// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
import math.bits as bitops
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'canonicalize'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
const air_names = ['air.clz.i64', 'air.ctz.i64']
const llvm_names = ['llvm.ctlz.i64', 'llvm.cttz.i64']
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn operations(mode int,native bool) string {
 op:=mode%2;name:=if native{llvm_names[op]}else{air_names[op]}
 return if mode<2 {'%r = call i64 @${name}(i64 %x,i1 false)\n'}else{'%a = call i64 @${name}(i64 %x,i1 false)\n %b = call i64 @${llvm_names[op]}(i64 %x,i1 false)\n %r = xor i64 %a,%b\n'}
}
fn source() string {
 mut s:=strings.new_builder(32768);s.write_string('target datalayout = "e-p:64:64"\n')
 for name in air_names{s.write_string('declare i64 @${name}(i64,i1) #0\n')}
 for name in llvm_names{s.write_string('declare i64 @${name}(i64,i1 immarg) #0\n')}
 s.write_string('declare i64 @alias(i64,i1)\n declare i64 @flag_width(i64,i8) #0\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for mode in 0..4 {
  ops:=operations(mode,false);ref:=operations(mode,true)
  s.write_string('define i64 @eval_${mode}(i64 %x) {${ops}ret i64 %r }\n')
  for index in [false,true] {
   name:=if index{'index'}else{'memory'}
   tail:=if index{'%p = getelementptr i8,ptr %out,i64 %r\n store i8 42,ptr %p\n'}else{'%p = getelementptr i8,ptr %out,i64 5\n store i64 %r,ptr %p,align 1\n'}
   s.write_string('define void @${name}_${mode}(i64 %x,ptr %out) {store i8 17,ptr %out\n ${ops}${tail}ret void }\n')
   s.write_string('define void @ref_${name}_${mode}(ptr %in,ptr %unused,ptr %out) {%x = load i64,ptr %in,align 1\n store i8 17,ptr %out\n ${ref}${tail}ret void }\n')
  }
 }
 s.write_string('define void @width(ptr %out) {store i8 17,ptr %out\n %r = call i64 @flag_width(i64 7,i8 0)\n ret void }\n define i64 @canonical_good() {%r = call i64 @llvm.ctlz.i64(i64 8,i1 false)\n ret i64 %r }\n')
 for op,name in air_names {
  for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef'] {
   bad:=if state.contains('undef'){'undef'}else{'poison'};input:=if state.starts_with('source_'){'%f'}else{bad}
   prefix:=if state.starts_with('source_'){'%f = freeze i64 ${bad}\n'}else{''}
   suffix:=if state.starts_with('result_'){'%f = freeze i64 %r\n ret i64 %f'}else{'ret i64 %r'}
   s.write_string('define i64 @state_${op}_${state}() {${prefix}%r = call i64 @${name}(i64 ${input},i1 false)\n ${suffix} }\n')
  }
  for flag in ['false','true']{s.write_string('define i64 @llvm_zero_${op}_${flag}() {%r = call i64 @${llvm_names[op]}(i64 0,i1 ${flag})\n ret i64 %r }\n')}
  s.write_string('define void @discard_${op}() {%r = call i64 @${name}(i64 poison,i1 false)\n ret void }\n define void @duplicate_${op}(ptr %out) {store i8 17,ptr %out\n %a = call i64 @${name}(i64 3,i1 false)\n %b = call i64 @alias(i64 7,i1 false)\n ret void }\n')
  for flag in ['true','argument','undef','poison','computed','cached'] {
   value:=if flag in ['argument','computed']{'%flag'}else if flag=='cached'{'true'}else{flag}
   argument:=if flag=='argument'{',i1 %flag'}else{''}
   prefix:=if flag=='computed'{'%flag = icmp eq i64 0,0\n'}else if flag=='cached'{'%before = call i64 @'+name+'(i64 7,i1 false)\n'}else{''}
   s.write_string('define void @bad_${op}_${flag}(ptr %out${argument}) {store i8 17,ptr %out\n ${prefix}%r = call i64 @${name}(i64 7,i1 ${value})\n ret void }\n')
  }
  for native in [false,true] {
   callee:=if native{llvm_names[op]}else{name}
   s.write_string(if native{'define void @ref_loop_${op}(ptr %in,ptr %counts,ptr %out) {%x = load i64,ptr %in,align 1\n %limit = load i64,ptr %counts,align 1\n'}else{'define i64 @loop_${op}(i64 %x,i64 %limit) {\n'})
   s.write_string('br label %body\n body: %v = phi i64 [%x,%0],[%sum,%body]\n %i = phi i64 [0,%0],[%next,%body]\n %t = xor i64 %v,9223372036854775808\n %r = call i64 @${callee}(i64 %t,i1 false)\n %sum = add i64 %r,17\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: ')
   s.write_string(if native{'store i64 %sum,ptr %out,align 1\n ret void }\n'}else{'ret i64 %sum }\n'})
  }
 }
 s.write_string('declare i32 @air.clz.i32(i32,i1) #0
 declare i32 @air.ctz.i32(i32,i1) #0
 declare i64 @air.popcount.i64(i64) #0
 declare i64 @air.min.s.i64(i64,i64) #0
 declare float @air.fabs.f32(float) #0
 define i64 @widths(i64 %x) {
 %n = trunc i64 %x to i32
 %a = call i64 @air.clz.i64(i64 %x,i1 false)
 %b = call i64 @air.ctz.i64(i64 %x,i1 false)
 %c = call i32 @air.clz.i32(i32 %n,i1 false)
 %d = call i32 @air.ctz.i32(i32 %n,i1 false)
 %cz = zext i32 %c to i64
 %dz = zext i32 %d to i64
 %bs = shl i64 %b,7
 %cs = shl i64 %cz,14
 %ds = shl i64 %dz,20
 %ab = or i64 %a,%bs
 %cd = or i64 %cs,%ds
 %both = or i64 %ab,%cd
 %pop = call i64 @air.popcount.i64(i64 %x)
 %cap = call i64 @air.min.s.i64(i64 %pop,i64 64)
 %ps = shl i64 %cap,26
 %counts = or i64 %both,%ps
 %f = call float @air.fabs.f32(float bitcast (i32 3212836864 to float))
 %fb = bitcast float %f to i32
 %fw = zext i32 %fb to i64
 %fp = xor i64 %fw,1065353216
 %r = xor i64 %counts,%fp
 ret i64 %r }
')
 return s.str()
}
fn sample_value(sample int) u64 {
 return if sample<64{u64(1)<<u32(sample)}else if sample<128{~(u64(1)<<u32(sample-64))}else if sample==128{u64(0)}else if sample==129{~u64(0)}else{u64(sample)*u64(0x9e3779b97f4a7c15)^u64(sample>>3)*u64(0x1f123bb585ebca6b)}
}
fn oracle(op int,x u64,width u32) u64 {
 value:=if width==64{x}else{x&0xffffffff}
 return if value==0{u64(width)}else if op==0{u64(bitops.leading_zeros_64(value)-int(64-width))}else{u64(bitops.trailing_zeros_64(value))}
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut native_checks:=0;mut scalar_checks:=0;mut budgets:=0;mut refusals:=0
 for mode in 0..4 {
  sf:=fi(ir,'eval_${mode}');mf:=fi(ir,'memory_${mode}');ix:=fi(ir,'index_${mode}');steps:=if mode<2{2}else{4}
  memory:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;index:=p.prepare_memory_function(ir,stream,pools,bodies,ix)!;assert memory.steps()==steps+3&&index.steps()==steps+3
  mut input:=[]u8{len:16};mut output:=[]u8{len:72,init:0xcc};mut reference:=output.clone();mut args:=[u64(0)]
  mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  ref_memory:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${mode}').str);ref_index:=C.LLVMGetFunctionAddress(native.engine,('ref_index_${mode}').str);assert ref_memory!=0&&ref_index!=0
  for sample in 0..16384 {
   x:=sample_value(sample)
   args[0]=x;for i in 0..8{input[1+i]=u8(x>>u64(i*8))}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(ref_memory))(&input[1],unsafe{nil},&reference[3])}
   mut value:=u64(0);for i in 0..8{value|=u64(reference[8+i])<<u64(i*8)}
   result:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps)!;assert !result.poison&&result.value==value&&value==if mode<2{oracle(mode,x,64)}else{u64(0)}&&result.steps==steps;scalar_checks++
   for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc};memory.validate(bs,memory.steps())!;unchanged(output)
    if prepared{memory.run(mut bs,memory.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps())!};assert output==reference
   };native_checks++
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(ref_index))(&input[1],unsafe{nil},&reference[3])}
   for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc};index.validate(bs,index.steps())!;unchanged(output)
    if prepared{index.run(mut bs,index.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,ix,mut bs,index.steps())!};assert output==reference
   };native_checks++
  }
  for i in 0..output.len{output[i]=0xcc}
  if _:=memory.run(mut bs,memory.steps()-1){panic('short prepared budget')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps()-1){panic('short memory budget')};unchanged(output);budgets+=2
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps-1){panic('short scalar budget')};budgets++
  if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,steps){panic('integer-only scalar call')};refusals++
  if mode<2 {
   scope:=bodies.scopes[mf+1]
   for at in scope.instructions_start..scope.instructions_start+scope.instructions_count {
    op:=p.instructions[at];if stream.records[bodies.instructions[at].record].code!=34{continue}
    for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,operands_count:4},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
     p.instructions[at]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('bad call metadata')};unchanged(output);refusals++
    };p.instructions[at]=op
   }
  }
  memory.free();index.free();unsafe{input.free();output.free();reference.free();args.free();bs.free()}
 }
 mut states:=0
 for op in 0..2{for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef']{
  f:=fi(ir,'state_${op}_${state}');undef:=state.contains('undef')&&!state.starts_with('source_')
  if result:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4){assert !undef;assert result.poison==(state=='poison');if !result.poison{assert result.value==if state.starts_with('source_'){u64(64)}else{u64(0)}}}else{assert undef};states++
 };assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_${op}'),[],2)!.steps==2;states++
  for flag in ['false','true']{r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'llvm_zero_${op}_${flag}'),[],2)!;assert r.poison==(flag=='true');if !r.poison{assert r.value==64};states++}
 }
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');width:=fi(ir,'flag_width');canonical:=fi(ir,'llvm.ctlz.i64')
 mut output:=[u8(0xcc)];mut flags:=[u64(0)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];mut flagged:=[airbitcode.IRMemoryBinding{data:output,writable:true},airbitcode.IRMemoryBinding{values:flags}];mut declarations:=0
 for op,name in air_names{
  functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:name};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate_${op}'),mut bs,4){panic('duplicate AIR identity')};unchanged(output);refusals++;functions[alias]=ir.functions[alias]
  for flag in ['true','argument','undef','poison','computed','cached']{
   expected:=match flag{'true','cached'{'AIR intrinsic: AIR zero count requires a constant false flag'}'argument'{'AIR intrinsic: constant immediate required'}'computed'{'AIR constants: local value ID out of range (instruction values are not indexed)'}else{'AIR intrinsic: invalid immediate constant'}}
   mut bindings:=if flag=='argument'{flagged}else{bs};if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'bad_${op}_${flag}'),mut bindings,8){panic('AIR zero flag accepted')}else{assert err.msg()==expected,err.msg()};unchanged(output);refusals++
  }
  functions[width]=airbitcode.IRFunction{...ir.functions[width],name:name};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'width'),mut bs,4){panic('flag width')}else{assert err.msg().contains('immediate type'),err.msg()};unchanged(output);refusals++;functions[width]=ir.functions[width]
  functions[canonical]=airbitcode.IRFunction{...ir.functions[canonical],name:name};r:=p.run_scalar_function(view,stream,pools,bodies,fi(ir,'canonical_good'),[],2)!;assert !r.poison&&r.value==if op==0{u64(60)}else{u64(3)};declarations++;functions[canonical]=ir.functions[canonical]
 }
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values};mut group:=-1
 for record in stream.records{if stream.blocks[record.block].id==10&&record.code==3&&record.values_count==4&&values[record.values_start+1]==2&&values[record.values_start+3]==60{group=record.values_start;break}};assert group>=0
 helper:=stream.records[ir.functions[canonical].record];attribute:=stream.values[helper.values_start+6];assert attribute!=0
 mut a:=[u64(0)];mut bytes:=[]u8{len:72,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 for op,name in air_names{
  record:=stream.records[ir.functions[fi(ir,name)].record];saved:=values[record.values_start+6];values[record.values_start+6]=attribute
  for wrong_slot in [true,false]{values[group+1]=if wrong_slot{u64(1)}else{u64(2)};values[group+3]=if wrong_slot{u64(60)}else{u64(18)}
   if _:=p.run_memory_function(ir,view_stream,pools,bodies,fi(ir,'memory_${op}'),mut bindings,16){panic('AIR declaration attribute')}else{assert err.msg().contains('attribute'),err.msg()};unchanged(bytes);refusals++
  };values[record.values_start+6]=saved
 };values[group+1]=2;values[group+3]=60
 unsafe{a.free();bytes.free();bindings.free()}
 mut loops:=0
 for op in 0..2{pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_loop_${op}').str);assert pointer!=0
  for limit in [u64(1),2,3,7,16,257]!{for x in [u64(0),1,0x8000000000000000,0xffffffffffffffff]!{
   mut reference:=u64(0);unsafe{NativeCast(voidptr(pointer))(&x,&limit,&reference)}
   steps:=int(limit*8+2);args:=[x,limit];r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${op}'),args,steps)!;assert !r.poison&&r.value==reference&&r.steps==steps
   if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${op}'),args,steps-1){panic('executed loop budget')};loops++;unsafe{args.free()}
  }}
 }
 for sample in 0..512 {
  x:=sample_value(sample);expected:=oracle(0,x,64)|(oracle(1,x,64)<<7)|(oracle(0,x,32)<<14)|(oracle(1,x,32)<<20)|(u64(bitops.ones_count_64(x))<<26)
  r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'widths'),[x],23)!;assert !r.poison&&r.value==expected&&r.steps==23
 }
 os.write_file(root+'/widths-result.txt','AIR-SCALAR-ZERO-COUNT64-WIDTHS: 512 i32/i64/float/bit/extrema coexistence checks PASS\n')!
 assert native_checks==131072&&scalar_checks==65536&&states==18&&loops==48&&refusals==42&&budgets==12&&declarations==2
 line:='AIR-NATIVE-SCALAR-ZERO-COUNT64: ${native_checks} native value/address comparisons, ${scalar_checks} scalar checks, ${states} state/discard/LLVM-zero checks, ${refusals} profile/metadata/flag/duplicate refusals, ${budgets} short budgets, ${declarations} immarg declarations and ${loops} native loop comparisons with executed-budget refusals PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
 unsafe{output.free();flags.free();bs.free();flagged.free()}
}
