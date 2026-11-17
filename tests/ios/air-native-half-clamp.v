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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-half-clamp'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
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
fn check_scalar(r airbitcode.IRScalarRun,value u16,poison bool,steps int) ! {
 if r.kind!=.binary16||r.bits!=16||r.poison!=poison||r.steps!=steps||(!poison&&r.value!=u64(value)){return error('CLAMP result value/metadata')}
}
// Defined native number operations with explicit AIR first-zero selection.
fn number_operation(minimum bool,left string,right string,prefix string,result string) string {
 name:=if minimum{'llvm.minimumnum.f16'}else{'llvm.maximumnum.f16'}
 return '%${prefix}v = call half @${name}(half ${left},half ${right})\n %${prefix}x = bitcast half ${left} to i16\n %${prefix}y = bitcast half ${right} to i16\n %${prefix}xy = or i16 %${prefix}x,%${prefix}y\n %${prefix}abs = and i16 %${prefix}xy,32767\n %${prefix}zero = icmp eq i16 %${prefix}abs,0\n %${result} = select i1 %${prefix}zero,half ${left},half %${prefix}v\n'
}
fn native_clamp(left string,low string,high string,prefix string,result string) string {
 return number_operation(false,left,low,prefix+'l',prefix+'lower')+number_operation(true,'%'+prefix+'lower',high,prefix+'h',result)
}
fn operations(mode int,native bool) string {
 if native {
  // Classify invalid bounds before the defined number composition. The flag
  // represents our poison policy; no undefined native clamp is executed.
  prefix:='%invalid = fcmp ogt half %y,%z\n br i1 %invalid,label %invalid_bounds,label %valid_bounds\n invalid_bounds: store i8 1,ptr %out\n ret void\n valid_bounds:\n'
  return prefix+if mode==0{native_clamp('%x','%y','%z','p','r')}else{native_clamp('%x','%y','%z','p','a')+native_clamp('%a','%y','%z','q','r')}
 }
 call:='%r = call half @air.clamp.f16(half %x,half %y,half %z)\n'
 if mode==0{return call}
 if mode==1{return '%a = call half @air.clamp.f16(half %x,half %y,half %z)\n %r = call half @air.clamp.f16(half %a,half %y,half %z)\n'}
 return '%a = call half @air.fmax.f16(half %x,half %y)\n %b = call half @air.fmin.f16(half %a,half %z)\n %r = call half @air.clamp.f16(half %b,half %y,half %z)\n'
}
const load_inputs = '%x = load half,ptr %in,align 1\n %yp = getelementptr i8,ptr %in,i32 2\n %y = load half,ptr %yp,align 1\n %zp = getelementptr i8,ptr %in,i32 4\n %z = load half,ptr %zp,align 1\n'
const store_result = '%p = getelementptr i8,ptr %out,i32 5\n store half %r,ptr %p,align 1\n ret void }\n'
fn source() string {
 mut s:=strings.new_builder(32768);s.write_string('target datalayout = "e-p:64:64"\n declare half @air.clamp.f16(half,half,half) #0\n declare half @air.fmin.f16(half,half) #0\n declare half @air.fmax.f16(half,half) #0\n declare half @llvm.minimumnum.f16(half,half) #0\n declare half @llvm.maximumnum.f16(half,half) #0\n declare half @alias(half,half,half)\n declare i32 @llvm.ctlz.i32(i32,i1 immarg)\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for mode in 0..3 {
  ops:=operations(mode,false);ref:=operations(mode,true)
  s.write_string('define half @eval_${mode}(half %x,half %y,half %z) {${ops}ret half %r }\n')
  s.write_string('define void @memory_${mode}(half %x,half %y,half %z,ptr %out) {store i8 17,ptr %out\n ${ops}${store_result}')
  s.write_string('define void @loaded_${mode}(ptr %in,ptr %out) {${load_inputs}store i8 17,ptr %out\n ${ops}${store_result}')
  s.write_string('define void @ref_memory_${mode}(ptr %in,ptr %unused,ptr %out) {${load_inputs}store i8 17,ptr %out\n ${ref}${store_result}')
 }
 for side in 0..3 {
  for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef'] {
   bad:=if state.contains('undef'){'undef'}else{'poison'};input:=if state.starts_with('source_'){'%f'}else{bad}
   args:='half ${if side==0{input}else{'0.0'}},half ${if side==1{input}else{'0.0'}},half ${if side==2{input}else{'0.0'}}'
   prefix:=if state.starts_with('source_'){'%f = freeze half ${bad}\n'}else{''};suffix:=if state.starts_with('result_'){'%f = freeze half %r\n ret half %f'}else{'ret half %r'}
   s.write_string('define half @state_${side}_${state}() {${prefix}%r = call half @air.clamp.f16(${args})\n ${suffix} }\n')
  }
  args:='half ${if side==0{'poison'}else{'0.0'}},half ${if side==1{'poison'}else{'0.0'}},half ${if side==2{'poison'}else{'0.0'}}'
  s.write_string('define void @discard_${side}() {%r = call half @air.clamp.f16(${args})\n ret void }\n')
  for bad in ['poison','undef'] {s.write_string('define void @guard_${side}_${bad}(ptr %out) {store i8 17,ptr %out\n %r = call half @air.clamp.f16(${args.replace('poison',bad)})\n ${store_result}')}
  for repair in ['freeze','select'] {
   choice:=if repair=='freeze'{'freeze half %bad'}else{'select i1 false,half %bad,half 1.0'}
   s.write_string('define void @repair_${side}_${repair}(ptr %out) {store i8 17,ptr %out\n %bad = call half @air.clamp.f16(${args})\n %r = ${choice}\n ${store_result}')
  }
 }
 s.write_string('define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call half @air.clamp.f16(half 1.0,half 1.0,half 1.0)\n %b = call half @alias(half 1.0,half 1.0,half 1.0)\n ret void }\n')
 for native in [false,true] {
  s.write_string(if native{'define void @ref_loop(ptr %in,ptr %counts,ptr %out) {${load_inputs}%limit = load i64,ptr %counts,align 1\n'}else{'define half @loop(half %x,half %y,half %z,i64 %limit) {\n'})
  ops:=if native{native_clamp('%v','%y','%z','p','r')}else{'%r = call half @air.clamp.f16(half %v,half %y,half %z)\n'}
  s.write_string('br label %body\n body: %v = phi half [%x,%0],[%sum,%body]\n %i = phi i64 [0,%0],[%next,%body]\n ${ops}%sum = fadd half %r,0.25\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: ')
  s.write_string(if native{'store half %sum,ptr %out,align 1\n ret void }\n'}else{'ret half %sum }\n'})
 }
 bad_call:='%bad = call half @air.clamp.f16(half 0.0,half 1.0,half -1.0)\n'
 s.write_string('define half @invalid_plain() {${bad_call}ret half %bad }\n define void @invalid_discard() {${bad_call}ret void }\n')
 for repair in ['store','freeze','select'] {
  choice:=if repair=='freeze'{'%r = freeze half %bad\n'}else if repair=='select'{'%r = select i1 false,half %bad,half 1.0\n'}else{'%r = fadd half %bad,0.0\n'}
  if repair!='store'{s.write_string('define half @invalid_${repair}() {${bad_call}${choice}ret half %r }\n')}
  s.write_string('define void @invalid_${repair}_memory(ptr %out) {store i8 17,ptr %out\n ${bad_call}${choice}${store_result}')
 }
 return s.str()
}
struct ClampReference {value u16 poison bool}
fn native_reference(pointer u64,triple [3]u16) ClampReference {
 mut input:=[16]u8{};mut output:=[16]u8{init:0xcc}
 for i in 0..3{for j in 0..2{input[1+i*2+j]=u8(triple[i]>>u16(j*8))}}
 unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&output[0])};assert output[0] in [u8(1),17]!
 if output[0]==1 {for i in 1..16{assert output[i]==0xcc};return ClampReference{poison:true}}
 for i in 1..16{if i<5||i>=7{assert output[i]==0xcc}}
 mut value:=u16(0);for i in 0..2{value|=u16(output[5+i])<<u16(i*8)};return ClampReference{value:canonical(value)}
}
fn rejected_profile(assembler string,out string,body string) ! {
 data:=assemble(assembler,out,'target datalayout = "e-p:64:64"\n'+body)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[]u8{len:72,init:0xcc};defer{unsafe{output.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];defer{unsafe{bs.free()}};f:=fi(ir,'reject')
 if prepared:=p.prepare_memory_function(ir,stream,pools,bodies,f){prepared.free();panic('invalid prepared CLAMP profile')}
 if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,16){panic('invalid direct CLAMP profile')};unchanged(output)
}
fn rejected_profiles(assembler string,root string) !int {
 mut count:=0
 for typ in ['float','i16','<2 x half>'] {
  rejected_profile(assembler,root+'/format-${count}','declare ${typ} @air.clamp.f16(${typ},${typ},${typ})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${typ} @air.clamp.f16(${typ} zeroinitializer,${typ} zeroinitializer,${typ} zeroinitializer)\n ret void }\n')!;count++
 }
 for other in ['float','i16'] {
  rejected_profile(assembler,root+'/mixed-${count}','declare half @air.clamp.f16(half,${other},half)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call half @air.clamp.f16(half 1.0,${other} zeroinitializer,half 1.0)\n ret void }\n')!;count++
 }
 for arity in [2,4]! {
  types:=[]string{len:arity,init:'half'}.join(',');args:=[]string{len:arity,init:'half 1.0'}.join(',')
  rejected_profile(assembler,root+'/arity-${arity}','declare half @air.clamp.f16(${types})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call half @air.clamp.f16(${args})\n ret void }\n')!;count++
 }
 for name in ['air.fast_clamp.f16','air.clamp.f64','air.clamp.v2f16','air.clamp.f16.spoof'] {
  rejected_profile(assembler,root+'/name-${count}','declare half @${name}(half,half,half)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call half @${name}(half 1.0,half 1.0,half 1.0)\n ret void }\n')!;count++
 }
 rejected_profile(assembler,root+'/address','declare half @air.clamp.f16(half,half,half)\n define void @reject(ptr %out) {%r = call half @air.clamp.f16(half 1.0,half 1.0,half 1.0)\n %w = bitcast half %r to i16\n %i16 = and i16 %w,63\n %i = zext i16 %i16 to i32\n %p = getelementptr i8,ptr %out,i32 %i\n store i8 17,ptr %p\n ret void }\n')!;return count+1
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0&&C.fegetround()==C.FE_TONEAREST;defer{assert C.fesetenv(unsafe{voidptr(C.FE_DFL_ENV)})==0}
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut native_checks:=0;mut scalar_checks:=0;mut nan_checks:=0;mut defined:=0;mut domain_poisons:=0;mut boundaries:=0;mut refusals:=0;mut budgets:=0
 edges:=[u16(0),0x8000,1,0x8001,0x03ff,0x0400,0x3800,0x3c00,0xbc00,0x3c01,0x3bfe,0x4000,0x7bff,0xfbff,0x7c00,0xfc00,0x7c01,0xfc01,0x7e45,0xfe45]!
 for mode in 0..3 {
  sf:=fi(ir,'eval_${mode}');mf:=fi(ir,'memory_${mode}');lf:=fi(ir,'loaded_${mode}');steps:=mode+2
  memory:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert memory.steps()==steps+3&&loaded.steps()==steps+8
  mut input:=[]u8{len:16};mut output:=[]u8{len:72,init:0xcc};mut reference:=output.clone();mut args:=[u64(0),0,0]
  mut bs:=[airbitcode.IRMemoryBinding{values:unsafe{args[..1]}},airbitcode.IRMemoryBinding{values:unsafe{args[1..2]}},airbitcode.IRMemoryBinding{values:unsafe{args[2..]}},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  mut lbs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${mode}').str);assert pointer!=0
  // All encodings in each operand position, plus twenty boundary values cubed.
  for sample in 0..204608 {
   mut x:=u16(0);mut y:=u16(0);mut z:=u16(0)
   if sample<8000 {x=edges[sample/400];y=edges[(sample/20)%20];z=edges[sample%20];boundaries++}
   else {
    index:=sample-8000;raw:=u16(index%65536);a:=u16(u32(raw)*4051+17);b:=if index%4==0{a}else{u16(u32(raw)*7919+31)}
    match index/65536 {0{x=raw;y=a;z=b}1{x=a;y=raw;z=b}else{x=a;y=b;z=raw}}
   }
   for i,value in [x,y,z]!{args[i]=u64(value)|(u64(0xfedcba98)+u64(i))<<16;for j in 0..2{input[1+i*2+j]=u8(value>>u16(j*8))}}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&reference[3])}
   poison:=reference[3]==1;assert poison||reference[3]==17
   raw:=if poison{u16(0)}else{word(reference,8)};value:=canonical(raw)
   if poison{domain_poisons++}else{defined++;if raw&0x7fff>0x7c00{nan_checks++};for i in 0..2{reference[8+i]=u8(value>>u16(i*8))}}
   check_scalar(p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps)!,value,poison,steps)!;scalar_checks++
   for is_loaded in [false,true] {for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc};if is_loaded{loaded.validate(lbs,loaded.steps())!}else{memory.validate(bs,memory.steps())!};unchanged(output)
    if poison {
     if is_loaded{if prepared{if _:=loaded.run(mut lbs,loaded.steps()){panic('loaded poison store')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,loaded.steps()){panic('direct loaded poison store')}}}
     else{if prepared{if _:=memory.run(mut bs,memory.steps()){panic('typed poison store')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps()){panic('direct typed poison store')}}}
     assert output[3]==17;for i,b in output{if i!=3{assert b==0xcc}}
    }else{
     if is_loaded{if prepared{loaded.run(mut lbs,loaded.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,loaded.steps())!}}
     else{if prepared{memory.run(mut bs,memory.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps())!}}
     assert output==reference
    }
   };native_checks++}
  }
  for i in 0..output.len{output[i]=0xcc}
  if _:=memory.run(mut bs,memory.steps()-1){panic('prepared budget')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,memory.steps()-1){panic('direct budget')};unchanged(output);budgets+=2
  if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps-1){panic('scalar budget')};budgets++
  if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,steps){panic('integer-only call')};refusals++
  scope:=bodies.scopes[mf+1]
  for at in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   op:=p.instructions[at];if stream.records[bodies.instructions[at].record].code!=34{continue}
   for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:op.operands_count-1},airbitcode.IRTypedInstruction{...op,operands_count:op.operands_count+1},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
    p.instructions[at]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('call metadata')};unchanged(output);refusals++
   };p.instructions[at]=op
   for side in 0..op.operands_count-1{slot:=op.operands_start+side+1;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1}
    if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('operand type')};unchanged(output);refusals++;p.operands[slot]=saved
   }
  }
  memory.free();loaded.free();unsafe{input.free();output.free();reference.free();args.free();bs.free();lbs.free()}
 }
 println('CLAMP all numeric/metadata modes PASS')
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
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...ir.functions[alias],name:'air.clamp.f16'}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,4){panic('duplicate AIR identity')};unchanged(output);refusals++
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values};helper:=stream.records[ir.functions[fi(ir,'llvm.ctlz.i32')].record];attribute:=stream.values[helper.values_start+6];assert attribute!=0
 record:=stream.records[ir.functions[fi(ir,'air.clamp.f16')].record];values[record.values_start+6]=attribute
 mut a:=[u64(0)];mut bytes:=[]u8{len:72,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 if _:=p.run_memory_function(ir,view_stream,pools,bodies,fi(ir,'memory_0'),mut bindings,16){panic('AIR declaration immarg')}else{assert err.msg().contains('attribute'),err.msg()};unchanged(bytes);refusals++;unsafe{a.free();bytes.free();bindings.free()}
 mut loops:=0;loop_pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_loop');assert loop_pointer!=0
 for limit in [u64(1),2,3,7,16,257]!{for triple in [[u16(0),0xbc00,0x3c00]!,[u16(0x3e00),0xbc00,0x3c00]!,[u16(0xba00),0,0x3c00]!,[u16(0x4100),0xc000,0x4000]!]!{
  mut reference:=u16(0);unsafe{NativeCast(voidptr(loop_pointer))(&triple[0],&limit,&reference)}
  steps:=int(limit*7+2);args:=[u64(triple[0])|u64(0xfedcba98)<<16,u64(triple[1])|u64(0x12345678)<<16,u64(triple[2])|u64(0x98765432)<<16,limit]
  check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),args,steps)!,canonical(reference),false,steps)!
  if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),args,steps-1){panic('executed loop budget')};loops++;unsafe{args.free()}
 }}
 // Capture native results/classifications before changing the host environment.
 specials:=[[u16(0xb800),0xbc00,0x3c00]!,[u16(0x4000),0xbc00,0x3c00]!,[u16(0),0x3c00,0xbc00]!,[u16(0x7e45),0x3c00,0x4000]!,[u16(0x3c00),0x7e45,0x4000]!,[u16(0x3c00),0xbc00,0x7e45]!,[u16(0x7e45),0x7e45,0x7e45]!,[u16(0x8000),0,0x8000]!,[u16(0),0x8000,0]!,[u16(1),0,0x0400]!,[u16(0x7c00),0xfc00,0x7c00]!,[u16(0xfc00),0xfc00,0x7c00]!]!
 pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_memory_0');assert pointer!=0
 mut expected:=[12]ClampReference{};for i,triple in specials{expected[i]=native_reference(pointer,triple)}
 mut environments:=0
 for rounding in [C.FE_TONEAREST,C.FE_DOWNWARD,C.FE_UPWARD,C.FE_TOWARDZERO]!{assert C.fesetround(rounding)==0
  for i,triple in specials{args:=[u64(triple[0]),u64(triple[1]),u64(triple[2])];check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'eval_0'),args,2)!,expected[i].value,expected[i].poison,2)!;assert C.fegetround()==rounding;environments++;unsafe{args.free()}}
 };assert C.fesetround(C.FE_TONEAREST)==0
 baseline:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'eval_0'),[u64(0),0xbc00,0x3c00],2)!;mut controls:=0
 for changed in [airbitcode.IRScalarRun{...baseline,value:baseline.value^1},airbitcode.IRScalarRun{...baseline,kind:.integer},airbitcode.IRScalarRun{...baseline,bits:32},airbitcode.IRScalarRun{...baseline,poison:true},airbitcode.IRScalarRun{...baseline,steps:1}] {check_scalar(changed,u16(baseline.value),false,2) or {controls++;continue};panic('corrupted scalar result')}
 mut domain_controls:=0
 bad:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'invalid_plain'),[],2)!;check_scalar(bad,0,true,2)!;domain_controls++
 check_scalar(airbitcode.IRScalarRun{...bad,poison:false},0,true,2) or {controls++}
 assert controls==6
 for repair in ['freeze','select'] {check_scalar(p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'invalid_${repair}'),[],3)!,if repair=='select'{u16(0x3c00)}else{u16(0)},false,3)!;domain_controls++}
 assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'invalid_discard'),[],2)!.steps==2;domain_controls++
 for repair in ['store','freeze','select'] {
  f:=fi(ir,'invalid_${repair}_memory');prepared:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  mut domain_bytes:=[]u8{len:72,init:0xcc};mut domain_bindings:=[airbitcode.IRMemoryBinding{data:domain_bytes,offset:3,writable:true}]
  for cached in [false,true] {for i in 0..domain_bytes.len{domain_bytes[i]=0xcc}
   if repair=='store'{if cached{if _:=prepared.run(mut domain_bindings,prepared.steps()){panic('invalid bounds store')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut domain_bindings,prepared.steps()){panic('direct invalid bounds store')}};assert domain_bytes[3]==17;for i,b in domain_bytes{if i!=3{assert b==0xcc}}}
   else{if cached{prepared.run(mut domain_bindings,prepared.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut domain_bindings,prepared.steps())!};assert domain_bytes[3]==17&&word(domain_bytes,8)==if repair=='select'{u16(0x3c00)}else{u16(0)};for i,b in domain_bytes{if i!=3&&(i<8||i>=10){assert b==0xcc}}}
  };prepared.free();domain_controls++;unsafe{domain_bytes.free();domain_bindings.free()}
 }
 guards:=rejected_profiles(os.args[1],root+'/guards')!
 assert native_checks==1227648&&scalar_checks==613824&&defined+domain_poisons==scalar_checks&&defined>0&&domain_poisons>0&&boundaries==24000&&nan_checks>0&&states==21&&memory_states==6&&repairs==6&&refusals==75&&budgets==9&&loops==24&&environments==48&&controls==6&&guards==12&&domain_controls==7
 line:='AIR-NATIVE-HALF-CLAMP: ${native_checks} typed/loaded memory cases (direct and prepared), ${scalar_checks} scalar cases (${defined} native values, ${domain_poisons} domain poison, ${nan_checks} canonical NaNs, ${boundaries} boundary triples), ${states} state/discard checks, ${memory_states} ordered poison/undef stores, ${repairs} memory repairs, ${refusals} metadata/type/profile refusals, ${budgets} short budgets, ${loops} native loops with executed-budget refusals, ${environments} host-rounding checks, ${controls} result controls, ${guards} signature/overload/address guards and ${domain_controls} invalid-bounds freeze/lazy/discard/store cases PASS\n'
 os.write_file(root+'/result.txt',line)!;print(line);unsafe{output.free();bs.free()}
}
