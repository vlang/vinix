// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
import math.bits as bitops
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-vector-zero-count64'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn fi(ir airbitcode.IRModule, name string) int { for i,f in ir.functions { if f.name==name{return i} };panic(name) }
fn untouched(data []u8) {for b in data {assert b==0xcc}}
fn air_name(id string) string {return if id=='ctlz'{'air.clz'}else{'air.ctz'}}
fn oracle(id string,raw u64) u64 {
 x:=raw;return if id=='ctlz'{u64(bitops.leading_zeros_64(x))}else{u64(bitops.trailing_zeros_64(x))}
}
fn word(sample int,lane int) u64 {
 edges:=[u64(0),1,2,3,7,31,63,127,0xffffffff,0x100000000,0x7ffffffffffffffe,0x7fffffffffffffff,0x8000000000000000,0x8000000000000001,0xfffffffffffffffe,0xffffffffffffffff]!
 return if sample<16{edges[(sample+lane)%16]}else if sample<80{u64(1)<<u32((sample-16+lane)%64)}else if sample<144{~(u64(1)<<u32((sample-80+lane)%64))}else{u64(sample)*u64(0x9e3779b97f4a7c15)^u64(lane)*u64(0x85ebca6bc2b2ae35)}
}
fn fixture() string {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n attributes #0 = { nounwind memory(none) }\n')
 for id in ['ctlz','cttz'] {for count in 1..17 {
  t:='<${count} x i64>';wide:='<${count} x i64>';air:='${air_name(id)}.v${count}i64';llvm:='llvm.${id}.v${count}i64';name:='${id}_${count}'
  s.write_string('declare ${t} @${air}(${t},i1) #0\n declare ${t} @${llvm}(${t},i1 immarg)\n')
  for mode in ['typed','loaded','ref'] {
   header:=if mode=='typed'{'${t} %a,ptr %out'}else if mode=='loaded'{'ptr %in,ptr %out'}else{'ptr %in,ptr %unused,ptr %out'}
   load:=if mode=='typed'{''}else{'%wide = load ${wide},ptr %in,align 1\n %a = or ${wide} %wide,zeroinitializer\n'}
   callee:=if mode=='ref'{llvm}else{air}
   s.write_string('define void @${mode}_${name}(${header}) {${load}store i8 17,ptr %out\n %r = call ${t} @${callee}(${t} %a,i1 false)\n %z = or ${t} %r,zeroinitializer\n %p = getelementptr i8,ptr %out,i64 8\n store ${wide} %z,ptr %p,align 1\n ret void }\n')
  }
  s.write_string('define i64 @scalar_${name}(i64 %x,i64 %j) {%a = insertelement ${t} zeroinitializer,i64 %x,i64 %j\n %r = call ${t} @${air}(${t} %a,i1 false)\n %v = extractelement ${t} %r,i64 %j\n ret i64 %v }\n')
  s.write_string('define void @coexist_${name}(${t} %a,ptr %out) {store i8 17,ptr %out\n %ar = call ${t} @${air}(${t} %a,i1 false)\n %lr = call ${t} @${llvm}(${t} %a,i1 false)\n %r = xor ${t} %ar,%lr\n %p = getelementptr i8,ptr %out,i64 8\n store ${t} %r,ptr %p,align 1\n ret void }\n')
  s.write_string('define void @index_${name}(i64 %x,i64 %j,ptr %out) {store i8 17,ptr %out\n %a = insertelement ${t} zeroinitializer,i64 %x,i64 %j\n %r = call ${t} @${air}(${t} %a,i1 false)\n %v = extractelement ${t} %r,i64 %j\n %offset = and i64 %v,63\n %p = getelementptr i8,ptr %out,i64 %offset\n store i8 42,ptr %p\n ret void }\n')
 }}
 return s.str()
}
fn read_word(data []u8,offset int) u64 {mut x:=u64(0);for i in 0..8{x|=u64(data[offset+i])<<u32(i*8)};return x}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/')
 data:=assemble(os.args[1],root,fixture())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut lanes:=0;mut observed:=0;mut scalars:=0;mut indices:=0;mut metadata:=0;mut budgets:=0;mut coexist:=0;mut bounds:=0
 mut rows:=os.create(root+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('operation\tlanes\tsample\tlane\tsource\tresult')!
 for id in ['ctlz','cttz'] {for count in 1..17 {
  name:='${id}_${count}';tf:=fi(ir,'typed_'+name);lf:=fi(ir,'loaded_'+name);sf:=fi(ir,'scalar_'+name)
  typed:=p.prepare_memory_function(ir,stream,pools,bodies,tf)!;loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert typed.steps()==6&&loaded.steps()==8
  mut values:=[]u64{len:count};mut input:=[]u8{len:count*8+8};mut output:=[]u8{len:count*8+24,init:0xcc};mut expected:=output.clone()
  mut bs:=[airbitcode.IRMemoryBinding{values:values},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  mut lbs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_'+name).str);assert pointer!=0
  for sample in 0..512 {
   for lane in 0..count {values[lane]=word(sample,lane);for j in 0..8{input[1+lane*8+j]=u8(values[lane]>>u32(j*8))}}
   for i in 0..expected.len{expected[i]=0xcc};unsafe{NativeCast(voidptr(pointer))(&input[1],nil,&expected[3])}
   assert expected[3]==17
   for lane in 0..count{assert read_word(expected,11+lane*8)==oracle(id,values[lane]);rows.writeln('${id}\t${count}\t${sample}\t${lane}\t${values[lane]}\t${read_word(expected,11+lane*8)}')!;lanes++}
   for is_loaded in [false,true] {for prepared in [false,true] {
    for i in 0..output.len{output[i]=0xcc}
    if is_loaded{loaded.validate(lbs,8)!}else{typed.validate(bs,6)!};untouched(output)
    if is_loaded{if prepared{loaded.run(mut lbs,8)!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,8)!}}
    else{if prepared{typed.run(mut bs,6)!}else{p.run_memory_function(ir,stream,pools,bodies,tf,mut bs,6)!}}
    assert output==expected;observed+=count
   }}
   lane:=sample%count
   r:=p.run_scalar_function(ir,stream,pools,bodies,sf,[values[lane],u64(lane)],4)!;q:=p.run_integer_function(ir,stream,pools,bodies,sf,[values[lane],u64(lane)],4)!
   assert !r.poison&&!q.poison&&r.value==oracle(id,values[lane])&&q.value==r.value&&r.steps==4&&q.steps==4;scalars+=2
  }
  for is_loaded in [false,true] {for prepared in [false,true] {
   for i in 0..output.len{output[i]=0xcc}
   if is_loaded{if prepared{if _:=loaded.run(mut lbs,7){panic('short loaded budget')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,7){panic('short direct loaded budget')}}}
   else{if prepared{if _:=typed.run(mut bs,5){panic('short typed budget')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,tf,mut bs,5){panic('short direct typed budget')}}};untouched(output);budgets++
  }}
  scope:=bodies.scopes[tf+1]
  for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34{continue}
   for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:1},airbitcode.IRTypedInstruction{...op,operands_count:4},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
    for i in 0..output.len{output[i]=0xcc};p.instructions[index]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,tf,mut bs,6){panic('metadata')};untouched(output);metadata++
   };p.instructions[index]=op
   slot:=op.operands_start+1;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1};if _:=p.run_memory_function(ir,stream,pools,bodies,tf,mut bs,6){panic('source type')};untouched(output);metadata++;p.operands[slot]=saved
  }
  co:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'coexist_'+name))!;assert co.steps()==7
  for sample in 0..32 {
   for lane in 0..count{values[lane]=word(sample,lane)};for i in 0..output.len{output[i]=0xcc};co.run(mut bs,7)!
   for i,b in output{assert b==if i==3{u8(17)}else if i>=11&&i<11+count*8{u8(0)}else{u8(0xcc)}};coexist++
  };co.free()
  ix:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'index_'+name))!;assert ix.steps()==8
  mut bytes:=[]u8{len:96,init:0xcc};mut xvalues:=[u64(0)];mut jvalues:=[u64(0)];mut xs:=[airbitcode.IRMemoryBinding{values:xvalues},airbitcode.IRMemoryBinding{values:jvalues},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
  for sample in 0..32{xvalues[0]=word(sample,0);jvalues[0]=u64(sample%count)
   for prepared in [false,true]{for i in 0..bytes.len{bytes[i]=0xcc};ix.validate(xs,8)!;untouched(bytes);if prepared{ix.run(mut xs,8)!}else{p.run_memory_function(ir,stream,pools,bodies,fi(ir,'index_'+name),mut xs,8)!}
    for i,b in bytes{assert b==if i==3+int(oracle(id,xvalues[0])&63){u8(42)}else if i==3{u8(17)}else{u8(0xcc)}};indices++
   }
  }
  jvalues[0]=u64(count);for i in 0..bytes.len{bytes[i]=0xcc}
  if _:=ix.validate(xs,8){panic('invalid projected lane')};untouched(bytes);if _:=ix.run(mut xs,8){panic('invalid prepared lane')};untouched(bytes);if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'index_'+name),mut xs,8){panic('invalid direct lane')};untouched(bytes);indices+=3;ix.free()
  for short_input in [false,true] {for prepared in [false,true] {
   for i in 0..output.len{output[i]=0xcc};old:=lbs[if short_input{0}else{1}];lbs[if short_input{0}else{1}]=airbitcode.IRMemoryBinding{...old,data:unsafe{old.data[..int(old.offset)+if short_input{count*8-1}else{count*8+7}]}}
   if prepared{if _:=loaded.run(mut lbs,8){panic('short buffer')}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut lbs,8){panic('short direct buffer')}};untouched(output);bounds++;lbs[if short_input{0}else{1}]=old
  }}
  typed.free();loaded.free();unsafe{values.free();input.free();output.free();expected.free();bs.free();lbs.free();bytes.free();for binding in xs{binding.values.free()};xs.free()}
 }}
 controls(os.args[1],root+'/controls')!
 flag_checks(os.args[1],root+'/flags')!
 assert lanes==139264&&observed==557056&&scalars==32768&&indices==2144&&metadata==320&&budgets==128&&coexist==1024&&bounds==128
 result:='AIR-NATIVE-VECTOR-ZERO-COUNT64: 139264 native reference lanes, 557056 direct/prepared typed/loaded lane observations, 32768 scalar/integer checks, 2144 address checks, 320 metadata refusals, 128 budgets, 1024 AIR/LLVM coexistence cases and 128 bounds refusals PASS\n'
 os.write_file(root+'/result.txt',result)!;print(result)
}

fn rejected(assembler string,out string,source string) ! {
 data:=assemble(assembler,out,'target datalayout = "e-p:64:64"\n'+source)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut bytes:=[]u8{len:96,init:0xcc};defer{unsafe{bytes.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}];defer{unsafe{bs.free()}}
 f:=fi(ir,'reject');if plan:=p.prepare_memory_function(ir,stream,pools,bodies,f){plan.free();panic('invalid profile')};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,20){panic('invalid direct profile')};untouched(bytes)
}
fn controls(assembler string,root string) ! {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 modes:= ['defined','poison','undef','unused_poison','unused_undef','source_freeze','result_freeze','result_undef']
 for id in ['ctlz','cttz'] {
  air:=air_name(id)+'.v2i64';s.write_string('declare <2 x i64> @${air}(<2 x i64>,i1) #0\n')
  for mode in modes {for address in [false,true] {
   raw:=if mode in ['poison','result_freeze']{'<i64 poison,i64 1>'}else if mode in ['undef','source_freeze','result_undef']{'<i64 undef,i64 1>'}else if mode=='unused_poison'{'<i64 9223372036854775809,i64 poison>'}else if mode=='unused_undef'{'<i64 9223372036854775809,i64 undef>'}else{'<i64 9223372036854775809,i64 1>'}
   pre:=if mode=='source_freeze'{'%s = freeze <2 x i64> '+raw+'\n'}else{''};input:=if mode=='source_freeze'{'%s'}else{raw}
   post:=if mode in ['result_freeze','result_undef']{'%f = freeze <2 x i64> %r\n'}else{''};value:=if mode in ['result_freeze','result_undef']{'%f'}else{'%r'}
   tail:=if address{'%offset = and i64 %v,63\n %p = getelementptr i8,ptr %out,i64 %offset\n store i8 42,ptr %p\n'}else{'%p = getelementptr i8,ptr %out,i64 8\n store i64 %v,ptr %p,align 1\n'}
   s.write_string('define void @state_${id}_${mode}_${address}(ptr %out) {store i8 17,ptr %out\n ${pre}%r = call <2 x i64> @${air}(<2 x i64> ${input},i1 false)\n ${post}%v = extractelement <2 x i64> ${value},i64 0\n ${tail}ret void }\n')
  }}
  s.write_string('define i64 @loop_${id}(i64 %count) {entry: br label %body\n body: %a = phi <2 x i64> [<i64 9223372036854775809,i64 1>,%entry],[%r,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %t = xor <2 x i64> %a,<i64 -9223372036854775808,i64 1>\n %r = call <2 x i64> @${air}(<2 x i64> %t,i1 false)\n %next = add i64 %i,1\n %c = icmp ult i64 %next,%count\n br i1 %c,label %body,label %done\n done: %v = extractelement <2 x i64> %r,i64 0\n ret i64 %v }\n')
 }
 s.write_string('declare <2 x i64> @alias(<2 x i64>,i1) #0\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <2 x i64> @air.clz.v2i64(<2 x i64> zeroinitializer,i1 false)\n %b = call <2 x i64> @alias(<2 x i64> zeroinitializer,i1 false)\n ret void }\n attributes #0 = {nounwind memory(none)}\n')
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut checks:=0
 for id in ['ctlz','cttz'] {for mode in modes {for address in [false,true] {
  f:=fi(ir,'state_${id}_${mode}_${address}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;bad:=mode in ['poison','undef','unused_undef','result_undef'];value:=if mode=='source_freeze'{u64(64)}else if mode=='result_freeze'{u64(0)}else{oracle(id,0x8000000000000001)}
  for prepared in [false,true] {
   mut bytes:=[]u8{len:96,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
   if address&&bad{if _:=plan.validate(bs,plan.steps()){panic('invalid index validation')}}else{plan.validate(bs,plan.steps())!};untouched(bytes)
   if prepared{if _:=plan.run(mut bs,plan.steps()){assert !bad}else{assert bad,err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()){assert !bad}else{assert bad,err.msg()}}
   for i,b in bytes{assert b==if address&&bad{u8(0xcc)}else if !bad&&address&&i==3+int(value&63){u8(42)}else if i==3{u8(17)}else if !bad&&!address&&i>=11&&i<19{u8(value>>u32((i-11)*8))}else{u8(0xcc)},'${id} ${mode} ${address} ${i}'}
   checks++;unsafe{bytes.free();bs.free()}
  };plan.free()
 }}}
 for id in ['ctlz','cttz'] {for count in [u64(1),2,3,7,16,257,513,1024]! {
  mut expected:=u64(0x8000000000000001);for _ in u64(0)..count{expected=oracle(id,expected^u64(0x8000000000000000))};f:=fi(ir,'loop_'+id)
  r:=p.run_scalar_function(ir,stream,pools,bodies,f,[count],int(count*7+3))!;q:=p.run_integer_function(ir,stream,pools,bodies,f,[count],int(count*7+3))!
  assert !r.poison&&!q.poison&&r.value==expected&&q.value==expected&&r.steps==int(count*7+3)&&q.steps==r.steps
  if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[count],int(count*7+2)){panic('short scalar loop')};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[count],int(count*7+2)){panic('short integer loop')};checks+=4
 }}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'air.clz.v2i64'}
 mut bytes:=[]u8{len:96,init:0xcc};defer{unsafe{bytes.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}];defer{unsafe{bs.free()}}
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10){panic('duplicate')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration'};untouched(bytes);checks++
 mut values:=stream.values.clone();defer{unsafe{values.free()}};changed:=airbitcode.Stream{...stream,values:values};mut group:=-1
 for record in stream.records{if stream.blocks[record.block].id==10&&record.code==3&&record.values_count>=4&&values[record.values_start+1]==0xffffffff&&values[record.values_start+2]==0{group=record.values_start;break}};assert group>=0;values[group+3]=54
 if _:=p.run_memory_function(ir,changed,pools,bodies,fi(ir,'state_ctlz_defined_false'),mut bs,20){panic('strictfp')};untouched(bytes);checks++
 mut guards:=0
 for family in ['clz','ctz'] {
  name:='air.${family}.v2i64'
  for t in ['<2 x float>','<2 x i16>','<1 x i64>']{rejected(assembler,root+'/type-${guards}','declare ${t} @${name}(${t},i1)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${t} @${name}(${t} zeroinitializer,i1 false)\n ret void }\n')!;guards++}
  rejected(assembler,root+'/mixed-${guards}','declare <2 x i64> @${name}(<2 x i16>,i1)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${name}(<2 x i16> zeroinitializer,i1 false)\n ret void }\n')!;guards++
  for arity in [1,3]!{types:=[]string{len:arity,init:'<2 x i64>'}.join(',');args:=[]string{len:arity,init:'<2 x i64> zeroinitializer'}.join(',');rejected(assembler,root+'/arity-${guards}','declare <2 x i64> @${name}(${types})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${name}(${args})\n ret void }\n')!;guards++}
  for suffix in ['v0i64','v02i64','v17i64','v2i16','v2i32','v2i64.spoof','v2f32','s.v2i64','u.v2i64']{callee:='air.${family}.${suffix}';rejected(assembler,root+'/name-${guards}','declare <2 x i64> @${callee}(<2 x i64>,i1)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${callee}(<2 x i64> zeroinitializer,i1 false)\n ret void }\n')!;guards++}
  rejected(assembler,root+'/definition-${guards}','define <2 x i64> @${name}(<2 x i64> %a,i1 %flag) {ret <2 x i64> zeroinitializer}\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${name}(<2 x i64> zeroinitializer,i1 false)\n ret void }\n')!;guards++
 }
 for storage in [false,true]{for over in [false,true]{for api in ['memory','void','scalar']{limits(assembler,root+'/limit-${storage}-${over}-${api}',storage,over,api)!;checks++}}}
 assert checks==142&&guards==32
 os.write_file(root+'/result.txt','AIR-VECTOR-ZERO-COUNT64-CONTROLS: 142 state/freeze/loop/budget/duplicate/strictfp/shared-limit controls and 32 negative profiles PASS\n')!
}

fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};t:='<${count} x i64>';mut s:=strings.new_builder(16777216);s.write_string('declare ${t} @air.clz.v${count}i64(${t},i1)\n define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')}
 for i in 0..if storage&&over{4097}else{4096}{s.write_string('%n${i} = call ${t} @air.clz.v${count}i64(${t} zeroinitializer,i1 false)\n')};if !storage{for i in 0..if over{54309}else{54308}{s.write_string('%x${i} = extractelement ${t} %n4095, i64 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage{'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'};f:=fi(ir,name)
 if over{if name=='memory'{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000){panic('memory limit')}else{assert err.msg()==diagnostic,err.msg()};untouched(output)}else if name=='void'{if _:=p.run_void_function(ir,stream,pools,bodies,f,[],70000){panic('void limit')}else{assert err.msg()==diagnostic,err.msg()}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],70000){panic('scalar limit')}else{assert err.msg()==diagnostic,err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],70000){panic('integer limit')}else{assert err.msg()==diagnostic,err.msg()}}}
 else{steps:=if storage{4097}else{58405};if name=='memory'{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000)!.steps==steps+1;assert output[0]==17}else if name=='void'{assert p.run_void_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}else{assert p.run_scalar_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps;assert p.run_integer_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}}
 unsafe{output.free();bs.free()};os.write_file(out+'/result.txt','AIR-VECTOR-ZERO-COUNT64-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}

fn flag_checks(assembler string,root string) ! {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n')
 for id in ['ctlz','cttz']{for count in 1..17{
  name:='${id}_${count}';t:='<${count} x i64>';wide:='<${count} x i64>';air:='${air_name(id)}.v${count}i64'
  s.write_string('declare ${t} @${air}(${t},i1)\n declare ${t} @llvm.${id}.v${count}i64(${t},i1 immarg)\n')
  s.write_string('define void @both_${name}(${t} %a,ptr %out) {store i8 17,ptr %out\n %off = call ${t} @${air}(${t} %a,i1 false)\n %on = call ${t} @${air}(${t} %a,i1 true)\n %f = freeze ${t} %on\n %z0 = or ${t} %off,zeroinitializer\n %z1 = or ${t} %f,zeroinitializer\n %p0 = getelementptr i8,ptr %out,i64 8\n %p1 = getelementptr i8,ptr %out,i64 ${8+count*8}\n store ${wide} %z0,ptr %p0,align 1\n store ${wide} %z1,ptr %p1,align 1\n ret void }\n')
  s.write_string('define void @ref_true_${name}(ptr %in,ptr %unused,ptr %out) {%wide = load ${wide},ptr %in,align 1\n %a = or ${wide} %wide,zeroinitializer\n %r = call ${t} @llvm.${id}.v${count}i64(${t} %a,i1 true)\n %z = or ${t} %r,zeroinitializer\n store ${wide} %z,ptr %out,align 1\n ret void }\n')
  s.write_string('define i64 @scalar_true_${name}(i64 %x,i64 %j) {%a = insertelement ${t} zeroinitializer,i64 %x,i64 %j\n %r = call ${t} @${air}(${t} %a,i1 true)\n %v = extractelement ${t} %r,i64 %j\n ret i64 %v }\n')
  for flag in ['false','true']{s.write_string('define void @index_${flag}_${name}(i64 %x,ptr %out) {store i8 17,ptr %out\n %a = insertelement ${t} zeroinitializer,i64 %x,i64 0\n %r = call ${t} @${air}(${t} %a,i1 ${flag})\n %v = extractelement ${t} %r,i64 0\n %p = getelementptr i8,ptr %out,i64 %v\n store i8 42,ptr %p\n ret void }\n')}
  for flag in ['undef','poison','%flag']{label:=if flag=='%flag'{'dynamic'}else{flag};s.write_string('define void @bad_${label}_${name}(${t} %a,i1 %flag,ptr %out) {store i8 17,ptr %out\n %prime = call ${t} @${air}(${t} %a,i1 false)\n %bad = call ${t} @${air}(${t} %a,i1 ${flag})\n ret void }\n')}
 }}
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut lanes:=0;mut observed:=0;mut scalars:=0;mut addresses:=0;mut guards:=0
 for id in ['ctlz','cttz']{for count in 1..17{
  name:='${id}_${count}';f:=fi(ir,'both_'+name);plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==11
  mut values:=[]u64{len:count};mut input:=[]u64{len:count};mut reference:=[]u64{len:count};mut bytes:=[]u8{len:count*16+80,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:values},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
  pointer:=C.LLVMGetFunctionAddress(native.engine,('ref_true_'+name).str);assert pointer!=0
  for sample in 0..128{
   for lane in 0..count{values[lane]=word(sample,lane);input[lane]=values[lane]|1}
   // OR 1 defines every native true-flag input; native poison never runs.
   unsafe{NativeCast(voidptr(pointer))(input.data,nil,reference.data)}
   for lane in 0..count{assert reference[lane]==oracle(id,input[lane]);lanes++}
   for prepared in [false,true]{for i in 0..bytes.len{bytes[i]=0xcc};plan.validate(bs,11)!;untouched(bytes);if prepared{plan.run(mut bs,11)!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut bs,11)!}
    for i,b in bytes{first:=i>=11&&i<11+count*8;second:=i>=11+count*8&&i<11+count*16;lane:=if first{(i-11)/8}else if second{(i-11-count*8)/8}else{0};value:=if second&&values[lane]==0{u64(0)}else{oracle(id,values[lane])};assert b==if i==3{u8(17)}else if first||second{u8(value>>u32(((i-11)%8)*8))}else{u8(0xcc)}}
   }
   lane:=sample%count;args:=[values[lane],u64(lane)];r:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'scalar_true_'+name),args,4)!;q:=p.run_integer_function(ir,stream,pools,bodies,fi(ir,'scalar_true_'+name),args,4)!
   assert r.poison==(values[lane]==0)&&q.poison==r.poison&&(r.poison||(r.value==oracle(id,values[lane])&&q.value==r.value));scalars+=2
   unsafe{args.free()}
   // Compare both AIR flags directly with native true-flag results on defined inputs.
   for observed_lane in 0..count{values[observed_lane]=input[observed_lane]}
   for prepared in [false,true]{for i in 0..bytes.len{bytes[i]=0xcc};plan.validate(bs,11)!;untouched(bytes);if prepared{plan.run(mut bs,11)!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut bs,11)!}
    for observed_lane in 0..count{assert read_word(bytes,11+observed_lane*8)==reference[observed_lane]&&read_word(bytes,11+count*8+observed_lane*8)==reference[observed_lane];observed+=2}
    for i,b in bytes{if i<11||i>=11+count*16{assert b==if i==3{u8(17)}else{u8(0xcc)}}}
   }
  }
  for label in ['undef','poison','dynamic']{
   bad:=fi(ir,'bad_${label}_${name}');if prepared:=p.prepare_memory_function(ir,stream,pools,bodies,bad){prepared.free();panic('bad cached flag')}
   mut badbs:=[airbitcode.IRMemoryBinding{values:values},airbitcode.IRMemoryBinding{values:[u64(0)]},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}];for i in 0..bytes.len{bytes[i]=0xcc}
   if _:=p.run_memory_function(ir,stream,pools,bodies,bad,mut badbs,5){panic('direct bad cached flag')};untouched(bytes);guards+=2;unsafe{badbs[1].values.free();badbs.free()}
  }
  // A valid first call primes the declaration cache before mutating the second flag.
  scope:=bodies.scopes[f+1];mut calls:=0
  for index in scope.instructions_start..scope.instructions_start+scope.instructions_count{op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34{continue};calls++;if calls!=2{continue};slot:=op.operands_start+2;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1};for i in 0..bytes.len{bytes[i]=0xcc};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,11){panic('cached flag type')};untouched(bytes);guards++;p.operands[slot]=saved}
  assert calls==2
  mut xvalues:=[u64(0)];mut ibs:=[airbitcode.IRMemoryBinding{values:xvalues},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
  for flag in ['false','true']{index:=fi(ir,'index_${flag}_${name}');ip:=p.prepare_memory_function(ir,stream,pools,bodies,index)!;assert ip.steps()==7
   for x in [u64(0),1,0x8000000000000000,0xffffffffffffffff]!{xvalues[0]=x
    for prepared in [false,true]{for i in 0..bytes.len{bytes[i]=0xcc};bad:=flag=='true'&&x==0
     if bad{if _:=ip.validate(ibs,7){panic('zero poison index')}}else{ip.validate(ibs,7)!};untouched(bytes)
     if prepared{if _:=ip.run(mut ibs,7){assert !bad}else{assert bad}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,index,mut ibs,7){assert !bad}else{assert bad}}
     for i,b in bytes{assert b==if bad{u8(0xcc)}else if i==3+int(oracle(id,x)){u8(42)}else if i==3{u8(17)}else{u8(0xcc)}};addresses++
    }
   };ip.free()
  }
  plan.free();unsafe{values.free();input.free();reference.free();bytes.free();bs.free();xvalues.free();ibs.free()}
 }}
 assert lanes==34816&&observed==139264&&scalars==8192&&addresses==512&&guards==224
 os.write_file(root+'/result.txt','AIR-VECTOR-ZERO-COUNT64-FLAGS: 34816 defined native true-flag lanes, 139264 direct/prepared false/true lane observations, 8192 scalar/integer value/poison checks, 512 address controls and 224 cached flag refusals; false/true/frozen mixed zero vectors PASS\n')!
}
