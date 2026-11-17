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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-saturating'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
const air_names = ['air.add_sat.s.i64', 'air.sub_sat.s.i64', 'air.add_sat.u.i64', 'air.sub_sat.u.i64']
const llvm_names = ['llvm.sadd.sat.i64', 'llvm.ssub.sat.i64', 'llvm.uadd.sat.i64', 'llvm.usub.sat.i64']
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn operations(mode int,native bool) string {
 op:=mode%4;name:=if native{llvm_names[op]}else{air_names[op]}
 return if mode<4 {'%r = call i64 @${name}(i64 %x,i64 %y)\n'}else{'%a = call i64 @${name}(i64 %x,i64 %y)\n %b = call i64 @${llvm_names[op]}(i64 %x,i64 %y)\n %r = xor i64 %a,%b\n'}
}
fn source() string {
 mut s:=strings.new_builder(32768);s.write_string('target datalayout = "e-p:64:64"\n')
 for name in air_names{s.write_string('declare i64 @${name}(i64,i64) #0\n')}
 for name in llvm_names{s.write_string('declare i64 @${name}(i64,i64) #0\n')}
 s.write_string('declare i64 @alias(i64,i64)\n declare i64 @llvm.cttz.i64(i64,i1 immarg)\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for mode in 0..8 {
  ops:=operations(mode,false);ref:=operations(mode,true)
  s.write_string('define i64 @eval_${mode}(i64 %x,i64 %y) {${ops}ret i64 %r }\n')
  for index in [false,true] {
   name:=if index{'index'}else{'memory'}
   tail:=if index{'%i = and i64 %r,63\n %p = getelementptr i8,ptr %out,i64 %i\n store i8 42,ptr %p\n'}else{'%p = getelementptr i8,ptr %out,i64 7\n store i64 %r,ptr %p,align 1\n'}
   s.write_string('define void @${name}_${mode}(i64 %x,i64 %y,ptr %out) {store i8 17,ptr %out\n ${ops}${tail}ret void }\n')
   s.write_string('define void @ref_${name}_${mode}(ptr %in,ptr %unused,ptr %out) {%x = load i64,ptr %in,align 1\n %yp = getelementptr i8,ptr %in,i64 8\n %y = load i64,ptr %yp,align 1\n store i8 17,ptr %out\n ${ref}${tail}ret void }\n')
  }
 }
 for op,name in air_names {
  for state in ['poison_left','poison_right','undef_left','undef_right','source_poison_left','source_undef_left','source_poison_right','source_undef_right','result_poison_left','result_poison_right','result_undef_left','result_undef_right'] {
   undef:=state.contains('undef');bad:=if undef{'undef'}else{'poison'};input:=if state.starts_with('source_'){'%f'}else{bad}
   prefix:=if state.starts_with('source_'){'%f = freeze i64 ${bad}\n'}else{''}
   args:=if state.ends_with('left'){'i64 ${input},i64 7'}else{'i64 7,i64 ${input}'}
   suffix:=if state.starts_with('result_'){'%f = freeze i64 %r\n ret i64 %f'}else{'ret i64 %r'}
   s.write_string('define i64 @state_${op}_${state}() {${prefix}%r = call i64 @${name}(${args})\n ${suffix} }\n')
  }
  s.write_string('define void @discard_${op}() {%r = call i64 @${name}(i64 poison,i64 7)\n ret void }\n define void @duplicate_${op}(ptr %out) {store i8 17,ptr %out\n %a = call i64 @${name}(i64 3,i64 7)\n %b = call i64 @alias(i64 7,i64 3)\n ret void }\n')
  for native in [false,true] {
   callee:=if native{llvm_names[op]}else{name}
   s.write_string(if native{'define void @ref_loop_${op}(ptr %in,ptr %counts,ptr %out) {%x = load i64,ptr %in,align 1\n %yp = getelementptr i8,ptr %in,i64 8\n %y = load i64,ptr %yp,align 1\n %limit = load i64,ptr %counts,align 1\n'}else{'define i64 @loop_${op}(i64 %x,i64 %y,i64 %limit) {\n'})
   s.write_string('br label %body\n body: %v = phi i64 [%x,%0],[%sum,%body]\n %i = phi i64 [0,%0],[%next,%body]\n %t = xor i64 %v,9223372036854775808\n %r = call i64 @${callee}(i64 %t,i64 %y)\n %sum = add i64 %r,17\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: ')
   s.write_string(if native{'store i64 %sum,ptr %out,align 1\n ret void }\n'}else{'ret i64 %sum }\n'})
  }
 }
 for op,name in air_names {
  old:=['air.add_sat.s.i32','air.sub_sat.s.i32','air.add_sat.u.i32','air.sub_sat.u.i32'][op]
  s.write_string('declare i32 @${old}(i32,i32) #0\n define i64 @widths_${op}(i64 %x,i64 %y) {\n %nx = trunc i64 %x to i32\n %ny = trunc i64 %y to i32\n %wide = call i64 @${name}(i64 %x,i64 %y)\n %narrow = call i32 @${old}(i32 %nx,i32 %ny)\n %z = zext i32 %narrow to i64\n %r = xor i64 %wide,%z\n %pop = call i64 @air.popcount.i64(i64 %x)\n %clz = call i64 @air.clz.i64(i64 %x,i1 false)\n %f = call float @air.fabs.f32(float bitcast (i32 3212836864 to float))\n %fb = bitcast float %f to i32\n %fw = zext i32 %fb to i64\n %fp = xor i64 %fw,1065353216\n %aux = xor i64 %pop,%clz\n %comb = xor i64 %aux,%fp\n %out = xor i64 %r,%comb\n ret i64 %out }\n')
 }
 s.write_string('declare i64 @air.popcount.i64(i64) #0\n declare i64 @air.clz.i64(i64,i1) #0\n declare float @air.fabs.f32(float) #0\n')
 return s.str()
}
fn source_freeze_value(op int,state string) u64 {
 if !state.starts_with('source_'){return 0}
 if op==0||op==2||state.ends_with('right'){return 7}
 return if op==1{u64(18446744073709551609)}else{u64(0)}
}
fn sat_mask(width u32) u64 {return if width==64{~u64(0)}else{(u64(1)<<width)-1}}

fn saturating_signed(value u64, width u32) i64 {
	x := value & sat_mask(width)
	return if x & (u64(1) << (width - 1)) == 0 { i64(x) } else { -i64((~x) & sat_mask(width)) - 1 }
}
// Independent oracle: signed arithmetic uses checked margins before computing
// any result. Unsigned addition uses two 32-bit limbs and an explicit carry.
fn saturating_reference(id int, width u32, a u64, b u64) u64 {
	mask := sat_mask(width); x := a & mask; y := b & mask
	if id == 2 {
		low := (x & 0xffffffff) + (y & 0xffffffff)
		high := (x >> 32) + (y >> 32) + (low >> 32)
		result := ((high & 0xffffffff) << 32) | (low & 0xffffffff)
		return if high >> 32 != 0 || result & ~mask != 0 { mask } else { result }
	}
	if id == 3 { return if x >= y { x - y } else { u64(0) } }
	left := saturating_signed(x, width); right := saturating_signed(y, width)
	maximum := i64((u64(1) << (width - 1)) - 1); minimum := -maximum - 1
	if id == 0 {
		if right > 0 && left > maximum - right { return u64(maximum) }
		if right < 0 && left < minimum - right { return u64(minimum) & mask }
		return u64(left + right) & mask
	}
	if right < 0 && left > maximum + right { return u64(maximum) }
	if right > 0 && left < minimum + right { return u64(minimum) & mask }
	return u64(left - right) & mask
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut native_checks:=0;mut scalar_checks:=0;mut budgets:=0;mut refusals:=0
 edges:=[u64(0),1,2,3,7,31,63,255,0xffffffff,0x100000000,0x7ffffffffffffffe,0x7fffffffffffffff,0x8000000000000000,0x8000000000000001,0xfffffffffffffffe,0xffffffffffffffff]!
 for mode in 0..8 {
  sf:=fi(ir,'eval_${mode}');mf:=fi(ir,'memory_${mode}');ix:=fi(ir,'index_${mode}');steps:=if mode<4{2}else{4}
  memory:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;index:=p.prepare_memory_function(ir,stream,pools,bodies,ix)!;assert memory.steps()==steps+3&&index.steps()==steps+4
  mut input:=[]u8{len:24};mut output:=[]u8{len:96,init:0xcc};mut reference:=output.clone();mut args:=[u64(0),0]
  mut bs:=[airbitcode.IRMemoryBinding{values:unsafe{args[..1]}},airbitcode.IRMemoryBinding{values:unsafe{args[1..]}},airbitcode.IRMemoryBinding{data:output,offset:5,writable:true}]
  ref_memory:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${mode}').str);ref_index:=C.LLVMGetFunctionAddress(native.engine,('ref_index_${mode}').str);assert ref_memory!=0&&ref_index!=0
  for sample in 0..8192 {
   x:=if sample<256{edges[sample/16]}else{u64(sample)*u64(0x9e3779b97f4a7c15)^u64(sample>>3)*u64(0x1f123bb585ebca6b)}
   y:=if sample<256{edges[sample%16]}else if sample%8==0{x}else if sample%8==1{~x}else{u64(sample)*u64(0x7f4a7c159e3779b9)^u64(sample<<17)}
   args[0]=x;args[1]=y
   for i in 0..8{input[1+i]=u8(x>>u64(i*8));input[9+i]=u8(y>>u64(i*8))}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(ref_memory))(&input[1],unsafe{nil},&reference[5])}
   mut value:=u64(0);for i in 0..8{value|=u64(reference[12+i])<<u64(i*8)}
   result:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps)!;assert !result.poison&&result.value==value&&value==if mode<4{saturating_reference(mode,64,x,y)}else{u64(0)}&&result.steps==steps;scalar_checks++
   for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc};memory.validate(bs,memory.steps())!;unchanged(output)
    if prepared{memory.run(mut bs,memory.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps())!};assert output==reference
   };native_checks++
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(ref_index))(&input[1],unsafe{nil},&reference[5])}
   for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc};index.validate(bs,index.steps())!;unchanged(output)
    if prepared{index.run(mut bs,index.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,ix,mut bs,index.steps())!};assert output==reference
   };native_checks++
  }
  for i in 0..output.len{output[i]=0xcc}
  if _:=memory.run(mut bs,memory.steps()-1){panic('short prepared budget')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps()-1){panic('short memory budget')};unchanged(output);budgets+=2
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps-1){panic('short scalar budget')};budgets++
  if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,steps){panic('integer-only scalar call')};refusals++
  if mode<4 {
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
 for op in 0..4{for state in ['poison_left','poison_right','undef_left','undef_right','source_poison_left','source_undef_left','source_poison_right','source_undef_right','result_poison_left','result_poison_right','result_undef_left','result_undef_right']{
  f:=fi(ir,'state_${op}_${state}');undef:=state.contains('undef')&&!state.starts_with('source_')
  if result:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4){assert !undef;poison:=state.starts_with('poison');assert result.poison==poison;if !poison{assert result.value==source_freeze_value(op,state)}}else{assert undef};states++
 };assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_${op}'),[],2)!.steps==2;states++}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias')
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 for op,name in air_names{functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:name};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate_${op}'),mut bs,4){panic('duplicate AIR identity')};unchanged(output);refusals++}
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values}
 helper:=stream.records[ir.functions[fi(ir,'llvm.cttz.i64')].record];attribute:=stream.values[helper.values_start+6];assert attribute!=0
 mut a:=[u64(0)];mut bytes:=[]u8{len:96,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 for mode,name in air_names {
  record:=stream.records[ir.functions[fi(ir,name)].record];saved:=values[record.values_start+6];values[record.values_start+6]=attribute
  if _:=p.run_memory_function(ir,view_stream,pools,bodies,fi(ir,'memory_${mode}'),mut bindings,16){panic('AIR declaration immarg')}else{assert err.msg().contains('attribute'),err.msg()};unchanged(bytes);refusals++
  values[record.values_start+6]=saved
 }
 unsafe{a.free();bytes.free();bindings.free()}
 mut loops:=0
 for op in 0..4{pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_loop_${op}').str);assert pointer!=0
  for limit in [u64(1),2,3,7,16,257]!{for pair in [[u64(0),0xffffffffffffffff]!,[u64(0x8000000000000000),0x7fffffffffffffff]!,[u64(0xffffffffffffffff),1]!,[u64(0x7fffffffffffffff),0x8000000000000000]!]!{
   mut reference:=u64(0);unsafe{NativeCast(voidptr(pointer))(&pair[0],&limit,&reference)}
   steps:=int(limit*8+2);args:=[pair[0],pair[1],limit];r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${op}'),args,steps)!;assert !r.poison&&r.value==reference&&r.steps==steps
   if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${op}'),args,steps-1){panic('executed loop budget')};loops++;unsafe{args.free()}
  }}
 }
 for op in 0..4 {for sample in 0..256 {
  x:=edges[sample/16];y:=edges[sample%16];expected:=saturating_reference(op,64,x,y)^saturating_reference(op,32,x,y)^u64(bitops.ones_count_64(x))^u64(bitops.leading_zeros_64(x))
  r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'widths_${op}'),[x,y],16)!;assert !r.poison&&r.value==expected&&r.steps==16
 }}
 os.write_file(root+'/widths-result.txt','AIR-SCALAR-SATURATING64-WIDTHS: 1024 i32/i64/float/bit/zero-count coexistence checks PASS\n')!
 assert native_checks==131072&&scalar_checks==65536&&states==52&&loops==96&&refusals==52&&budgets==24
 line:='AIR-NATIVE-SCALAR-SATURATING64: ${native_checks} native value/address comparisons, ${scalar_checks} scalar checks, ${states} state/discard checks, ${refusals} profile/metadata/duplicate refusals, ${budgets} short budgets and ${loops} native loop comparisons with executed-budget refusals PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
 unsafe{output.free();bs.free()}
}
