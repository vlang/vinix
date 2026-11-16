// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
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
fn C.LLVMLookupIntrinsicID(&char, usize) u32
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
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name{return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn operations(mode int, native bool) string {
 pop:=if native{'llvm.ctpop.i32'}else{'air.popcount.i32'};rev:=if native{'llvm.bitreverse.i32'}else{'air.reverse_bits.i32'}
 return match mode {
  0 {'%r = call i32 @${pop}(i32 %x)\n'}
  1 {'%r = call i32 @${rev}(i32 %x)\n'}
  2 {'%t = call i32 @${rev}(i32 %x)\n %r = call i32 @${pop}(i32 %t)\n'}
  else {'%a = call i32 @${pop}(i32 %x)\n %b = call i32 @llvm.ctpop.i32(i32 %x)\n %c = call i32 @${rev}(i32 %x)\n %d = call i32 @llvm.bitreverse.i32(i32 %x)\n %e = xor i32 %a,%b\n %f = xor i32 %c,%d\n %r = or i32 %e,%f\n'}
 }
}
fn source() string {
 mut s:=strings.new_builder(32768)
 s.write_string('target datalayout = "e-p:64:64"\n declare i32 @air.popcount.i32(i32) #0\n declare i32 @air.reverse_bits.i32(i32) #0\n declare i32 @llvm.ctpop.i32(i32) #0\n declare i32 @llvm.bitreverse.i32(i32) #0\n declare i32 @alias(i32)\n declare i32 @llvm.ctlz.i32(i32,i1 immarg)\n attributes #0 = { mustprogress nofree nosync nounwind readnone willreturn }\n')
 for mode in 0..4 {
  ops:=operations(mode,false);ref:=operations(mode,true)
  s.write_string('define i32 @eval_${mode}(i32 %x) {${ops}ret i32 %r }\n')
  for index in [false,true] {
   name:=if index{'index'}else{'memory'}
   tail:=if index{'%i = and i32 %r,63\n %p = getelementptr i8,ptr %out,i32 %i\n store i8 42,ptr %p\n'}else{'%p = getelementptr i8,ptr %out,i32 5\n store i32 %r,ptr %p,align 1\n'}
   s.write_string('define void @${name}_${mode}(i32 %x,ptr %out) {store i8 17,ptr %out\n ${ops}${tail}ret void }\n')
   s.write_string('define void @ref_${name}_${mode}(ptr %in,ptr %unused,ptr %out) {%x = load i32,ptr %in,align 1\n store i8 17,ptr %out\n ${ref}${tail}ret void }\n')
  }
 }
 for op in ['air.popcount.i32','air.reverse_bits.i32'] {for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef'] {
  input:=if state in ['source_poison','source_undef']{'%f'}else if state.ends_with('undef'){'undef'}else{'poison'}
  prefix:=if state.starts_with('source_'){'%f = freeze i32 '+state.all_after('_')+'\n'}else{''}
  suffix:=if state.starts_with('result_'){'%f = freeze i32 %r\n ret i32 %f'}else{'ret i32 %r'}
  s.write_string('define i32 @state_${op}_${state}() {${prefix}%r = call i32 @${op}(i32 ${input})\n ${suffix} }\n')
 }}
 s.write_string('define void @discard() {%r = call i32 @air.popcount.i32(i32 poison)\n ret void }\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call i32 @air.popcount.i32(i32 3)\n %b = call i32 @alias(i32 7)\n ret void }\n')
 for native in [false,true] {
  pop:=if native{'llvm.ctpop.i32'}else{'air.popcount.i32'};rev:=if native{'llvm.bitreverse.i32'}else{'air.reverse_bits.i32'}
  s.write_string(if native{'define void @ref_loop(ptr %in,ptr %counts,ptr %out) {%x = load i32,ptr %in,align 1\n %limit = load i64,ptr %counts,align 1\n'}else{'define i32 @loop(i32 %x,i64 %limit) {\n'})
  s.write_string('br label %body\n body: %v = phi i32 [%x,%0],[%sum,%body]\n %i = phi i64 [0,%0],[%next,%body]\n %t = call i32 @${rev}(i32 %v)\n %r = call i32 @${pop}(i32 %t)\n %sum = add i32 %v,%r\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: ')
  s.write_string(if native{'store i32 %sum,ptr %out,align 1\n ret void }\n'}else{'ret i32 %sum }\n'})
 }
 return s.str()
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 data:=assemble(os.args[1],root,source())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut native_checks:=0;mut scalar_checks:=0;mut budgets:=0;mut refusals:=0
 for mode in 0..4 {
  sf:=fi(ir,'eval_${mode}');mf:=fi(ir,'memory_${mode}');ix:=fi(ir,'index_${mode}');steps:=[2,2,3,8]![mode]
  memory:=p.prepare_memory_function(ir,stream,pools,bodies,mf)!;index:=p.prepare_memory_function(ir,stream,pools,bodies,ix)!;assert memory.steps()==steps+3&&index.steps()==steps+4
  mut input:=[]u8{len:8};mut output:=[]u8{len:72,init:0xcc};mut reference:=output.clone();mut args:=[u64(0)]
  mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  ref_memory:=C.LLVMGetFunctionAddress(native.engine,('ref_memory_${mode}').str);ref_index:=C.LLVMGetFunctionAddress(native.engine,('ref_index_${mode}').str);assert ref_memory!=0&&ref_index!=0
  for sample in 0..16384 {
   word:=if sample<32{u32(1)<<u32(sample)}else if sample<64{~(u32(1)<<u32(sample-32))}else if sample==64{u32(0)}else if sample==65{~u32(0)}else{u32(sample)*u32(0x9e3779b9)^u32(sample>>3)*u32(0x1f123bb5)}
   args[0]=u64(word)|u64(0xfedcba98)<<32;for i in 0..4{input[1+i]=u8(word>>u32(i*8))}
   for i in 0..reference.len{reference[i]=0xcc};unsafe{NativeCast(voidptr(ref_memory))(&input[1],unsafe{nil},&reference[3])}
   mut value:=u64(0);for i in 0..4{value|=u64(reference[8+i])<<u32(i*8)}
   result:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,steps)!;assert !result.poison&&result.value==value&&result.steps==steps;scalar_checks++
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
    for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:1},airbitcode.IRTypedInstruction{...op,operands_count:3},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
     p.instructions[at]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,mf,mut bs,16){panic('bad call metadata')};unchanged(output);refusals++
    };p.instructions[at]=op
   }
  }
  memory.free();index.free();unsafe{input.free();output.free();reference.free();args.free();bs.free()}
 }
 mut states:=0
 for op in ['air.popcount.i32','air.reverse_bits.i32']{for state in ['poison','undef','source_poison','source_undef','result_poison','result_undef']{
  f:=fi(ir,'state_${op}_${state}')
  if result:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4){assert !state.ends_with('undef')||state=='source_undef';assert result.poison==(state=='poison');if !result.poison{assert result.value==0}}else{assert state in ['undef','result_undef']};states++
 }}
 assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard'),[],2)!.steps==2;states++
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'air.popcount.i32'}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,4){panic('duplicate AIR identity')};unchanged(output);refusals++
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values}
 helper:=stream.records[ir.functions[fi(ir,'llvm.ctlz.i32')].record];attribute:=stream.values[helper.values_start+6];assert attribute!=0
 mut a:=[u64(0)];mut bytes:=[]u8{len:32,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 for mode,name in ['air.popcount.i32','air.reverse_bits.i32'] {
  record:=stream.records[ir.functions[fi(ir,name)].record];saved:=values[record.values_start+6];values[record.values_start+6]=attribute
  if _:=p.run_memory_function(ir,view_stream,pools,bodies,fi(ir,'memory_${mode}'),mut bindings,16){panic('AIR declaration immarg')}else{assert err.msg().contains('attribute'),err.msg()};unchanged(bytes);refusals++
  values[record.values_start+6]=saved
 }
 unsafe{a.free();bytes.free();bindings.free()}
 pointer:=C.LLVMGetFunctionAddress(native.engine,c'ref_loop');assert pointer!=0;mut loops:=0
 for limit in [u64(1),2,3,7,16,257]!{for x in [u32(0),1,0x80000000,0xffffffff]!{
  mut reference:=u32(0);unsafe{NativeCast(voidptr(pointer))(&x,&limit,&reference)}
  steps:=int(limit*8+2);args:=[u64(x)|u64(0xfedcba98)<<32,limit];r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),args,steps)!;assert !r.poison&&r.value==reference&&r.steps==steps
  if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop'),args,steps-1){panic('executed loop budget')};loops++;unsafe{args.free()}
 }}
 assert native_checks==131072&&scalar_checks==65536&&states==13&&loops==24
 line:='AIR-NATIVE-INTEGER: ${native_checks} native value/address comparisons, ${scalar_checks} scalar checks, ${states} state/discard checks, ${refusals} profile/metadata/duplicate refusals, ${budgets} short budgets and ${loops} native loop comparisons with executed-budget refusals PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
 unsafe{output.free();bs.free()}
}
