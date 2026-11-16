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
#include <llvm-c/Transforms/PassBuilder.h>
fn C.LLVMCreatePassBuilderOptions() voidptr
fn C.LLVMDisposePassBuilderOptions(voidptr)
fn C.LLVMRunPasses(voidptr, &char, voidptr, voidptr) voidptr
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
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name {return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn verify(data []u8) ! {
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}
struct NativeModule { context voidptr buffer voidptr engine voidptr }
fn native_module(_data []u8, out string, ir airbitcode.IRModule) !NativeModule {
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 reference_data := assemble('/opt/homebrew/opt/llvm/bin/llvm-as', out+'/native-reference', native_source(os.read_file(out+'/input.ll')!))!; defer { unsafe { reference_data.free() } }
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(reference_data.data, usize(reference_data.len), c'active-mask'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 options_ref := C.LLVMCreatePassBuilderOptions(); assert C.LLVMRunPasses(module_ptr, c'always-inline', unsafe { nil }, options_ref) == unsafe { nil }; C.LLVMDisposePassBuilderOptions(options_ref)
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
// Independent mathematical-add reference. Five extra bits can represent
// every admitted base plus lane, including i64 max + 15, without wrapping.
fn native_source(source string) string {
 mut result := strings.new_builder(source.len * 2)
 for line in source.split_into_lines() {
  if line.starts_with('declare ') && line.contains('@llvm.get.active.lane.mask.') {
   end := line.index('>') or { panic('type') }; vt := line[8..end+1]
   count := vt[1..end-8].split(' x ')[0].int()
   at := line.index('@') or { panic('name') }; paren := line.index('(') or { panic('signature') }; name := line[at+1..paren]
   width := name.all_after_last('.i').int(); wide := width + 5
   result.write_string('define ${vt} @${name}(i${width} %a,i${width} %b) alwaysinline {\n %aw = zext i${width} %a to i${wide}\n %bw = zext i${width} %b to i${wide}\n')
   for lane in 0 .. count {
    result.write_string('%s${lane} = add i${wide} %aw,${lane}\n %c${lane} = icmp ult i${wide} %s${lane},%bw\n %v${lane} = insertelement ${vt} ${if lane==0 {'poison'} else {'%v'+(lane-1).str()}},i1 %c${lane},i32 ${lane}\n')
   }
   result.write_string('ret ${vt} %v${count-1} }\n')
  } else { result.write_string(line+'\n') }
 }
 return result.str().replace('@llvm.get.active.lane.mask.','@reference_active_mask_')
}
fn expected(a u64,b u64,lane u64) u64 {
 sum := a + lane
 return u64(sum >= a && sum < b)
}
fn batch(assembler string,out string,width int) ! {
 mut s := strings.new_builder(1048576); s.write_string('target datalayout = "e-p:64:64"\n')
 for n in 1 .. 17 {
  vt := '<${n} x i1>'; name := 'llvm.get.active.lane.mask.v${n}i1.i${width}'
  s.write_string('declare ${vt} @${name}(i${width},i${width})\n declare ${vt} @llvm.vector.reverse.v${n}i1(${vt})\n')
  for mode in 0 .. 3 {
   chosen := ['f','rev','selected'][mode]
   ops := '%m = call ${vt} @${name}(i${width} %a,i${width} %b)\n %f = freeze ${vt} %m\n %rev = call ${vt} @llvm.vector.reverse.v${n}i1(${vt} %m)\n %choose = icmp eq i${width} %a,0\n %selected = select i1 %choose,${vt} %m,${vt} undef\n %e = extractelement ${vt} %${chosen},i64 %r\n %wide = zext i1 %e to i64\n'
   s.write_string('define i64 @scalar_${n}_${mode}(i${width} %a,i${width} %b,i64 %r) {${ops}ret i64 %wide }\n')
   loads := '%rawa = load i64,ptr %src,align 1\n %bp = getelementptr i8,ptr %src,i64 8\n %rawb = load i64,ptr %bp,align 1\n %a = ${if width==64 {'or i64 %rawa,0'}else{'trunc i64 %rawa to i${width}'}}\n %b = ${if width==64 {'or i64 %rawb,0'}else{'trunc i64 %rawb to i${width}'}}\n %r = load i64,ptr %indices,align 1\n'
   s.write_string('define void @case_${n}_${mode}(ptr %src,ptr %indices,ptr %out) {${loads}store i8 17,ptr %out\n ${ops}%dest = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %dest,align 1\n ret void }\n')
  }
  for sb in [1,32,64] {
   ops := 'store i8 17,ptr %out\n %m = call ${vt} @${name}(i${width} %a,i${width} %b)\n %f = freeze ${vt} %m\n %e = extractelement ${vt} %f,i${sb} %r\n %index = zext i1 %e to i64\n %p = getelementptr i8,ptr %out,i64 %index\n store i8 42,ptr %p\n ret void }\n'
   s.write_string('define void @address_${n}_${sb}(i${width} %a,i${width} %b,i${sb} %r,ptr %out) {${ops}')
   s.write_string('define void @case_address_${n}_${sb}(ptr %src,ptr %indices,ptr %out) {%rawa = load i64,ptr %src,align 1\n %bp = getelementptr i8,ptr %src,i64 8\n %rawb = load i64,ptr %bp,align 1\n %a = ${if width==64 {'or i64 %rawa,0'}else{'trunc i64 %rawa to i${width}'}}\n %b = ${if width==64 {'or i64 %rawb,0'}else{'trunc i64 %rawb to i${width}'}}\n %rawr = load i64,ptr %indices,align 1\n %r = ${if sb==64 {'or i64 %rawr,0'}else{'trunc i64 %rawr to i${sb}'}}\n ${ops}')
  }
 }
 data := assemble(assembler,out,s.str())!; verify(data)!
 stream := airbitcode.parse(data)!; defer {stream.free()}; ir := stream.ir_module(data)!; defer {ir.free()}; pools := ir.constant_pools(stream)!; defer {pools.free()}; bodies := ir.function_bodies(stream,pools)!; defer {bodies.free()}; mut p := ir.typed_operands(stream,pools,bodies)!; defer {p.free()}; native := native_module(data,out,ir)!; defer {native.close()}
 mut exact:=0;mut poison:=0;mut undef:=0;mut apis:=0;mut addresses:=0;mut address_native:=0;mut refusals:=0
 maximum := mask(width); edges := [u64(0),1,maximum/2,maximum-1,maximum]!
 for n in 1 .. 17 {for mode in 0 .. 3 {
  f:=fi(ir,'case_${n}_${mode}');sf:=fi(ir,'scalar_${n}_${mode}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==17
  pointer:=C.LLVMGetFunctionAddress(native.engine,'case_${n}_${mode}'.str);assert pointer!=0
  mut input:=[]u8{len:24};mut selector:=[]u8{len:16};mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bs:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:selector,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for raw_a in edges {for raw_b in edges {for sample in 0 .. n+2 {
   a:=raw_a&maximum;b:=raw_b&maximum;r:=if sample==n+1 {~u64(0)}else{u64(sample)}
   state:=if r>=u64(n) {1}else if mode==2&&a!=0 {2}else{0}
   value:=if r<u64(n) {expected(a,b,if mode==1 {u64(n-1)-r}else{r})}else{u64(0)}
   for i in 0..8 {input[1+i]=u8((a|~maximum)>>u32(i*8));input[9+i]=u8((b|~maximum)>>u32(i*8));selector[1+i]=u8(r>>u32(i*8))}
   args:=[a|~maximum,b|~maximum,r]
   for integer in [false,true] {
    if integer {if v:=p.run_integer_function(ir,stream,pools,bodies,sf,args,8) {assert state!=2&&v.poison==(state==1)&&(v.poison||v.value==value)&&v.steps==8}else{assert state==2&&err.msg().contains('undef'),err.msg()}}
    else {if v:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,8) {assert state!=2&&v.poison==(state==1)&&(v.poison||v.value==value)&&v.steps==8}else{assert state==2&&err.msg().contains('undef'),err.msg()}};apis++
   }
   for prepared in [false,true] {
    for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc};plan.validate(bs,17)!;unchanged(output)
    if prepared {if _:=plan.run(mut bs,17) {assert state==0}else{assert state!=0,err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,17) {assert state==0}else{assert state!=0,err.msg()}}
    for i,byte in output {assert byte==if i==3 {u8(17)}else if state==0&&i>=11&&i<19 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}}
   }
   if state==0 {unsafe{NativeCast(voidptr(pointer))(&input[1],&selector[1],&reference[3])};assert output==reference;exact++}else if state==1 {poison++}else{undef++}
   unsafe{args.free()}
  }}}
  for i in 0..output.len {output[i]=0xcc};if _:=plan.run(mut bs,16) {panic('short budget')};unchanged(output);refusals++
  if mode==0 {scope:=bodies.scopes[f+1];for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34||!ir.functions[op.callee_function].name.starts_with('llvm.get.active.lane.mask.') {continue}
   for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,operands_count:4},airbitcode.IRTypedInstruction{...op,result_type:-1}] {p.instructions[index]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,17) {panic('mask metadata')};unchanged(output);refusals++};p.instructions[index]=op
  }}
  plan.free();unsafe{input.free();selector.free();output.free();reference.free();bs.free()}
 }}
 for n in 1..17 {for sb in [1,32,64] {
  f:=fi(ir,'address_${n}_${sb}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==8
  pointer:=C.LLVMGetFunctionAddress(native.engine,'case_address_${n}_${sb}'.str);assert pointer!=0
  mut a:=[u64(0)];mut b:=[u64(0)];mut r:=[u64(0)];mut native_input:=[u64(0),0];mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bs:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:b},airbitcode.IRMemoryBinding{values:r},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for raw_a in edges {for raw_b in edges {for sample in 0..n+2 {
   a[0]=raw_a|~maximum;b[0]=raw_b|~maximum;r[0]=if sample==n+1 {~u64(0)}else{u64(sample)|~mask(sb)};lane:=r[0]&mask(sb);valid:=lane<u64(n);value:=if valid {expected(a[0]&maximum,b[0]&maximum,lane)}else{u64(0)}
   for prepared in [false,true] {
    for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc}
    if _:=plan.validate(bs,8) {assert valid}else{assert !valid};unchanged(output)
    if prepared {if _:=plan.run(mut bs,8) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,8) {assert valid}else{assert !valid}}
    for i,byte in output {assert byte==if !valid {u8(0xcc)}else if i==3+int(value) {u8(42)}else if i==3 {u8(17)}else{u8(0xcc)}};addresses++
   }
   if valid {native_input[0]=a[0];native_input[1]=b[0];unsafe{NativeCast(voidptr(pointer))(&native_input[0],&r[0],&reference[3])};assert output==reference;address_native++}
  }}}
  plan.free();unsafe{a.free();b.free();r.free();native_input.free();output.free();reference.free();bs.free()}
 }}
 assert exact+poison+undef==12600&&apis==25200&&addresses==25200&&refusals==192
 line:='AIR-ACTIVE-MASK-BATCH: i${width}, ${exact} native values, ${poison} poison, ${undef} selected undef, ${apis} scalar/integer checks, ${addresses} address API checks, ${address_native} native addresses, ${refusals} budget/metadata refusals PASS\n';os.write_file(out+'/result.txt',line)!;print(line)
}
fn main() {
 assert os.args.len in [3,4]; root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 if os.args.len==4 {batch(os.args[1],root+'/w1',1)!;return}
 mut result:='';for width in 1..65 {batch(os.args[1],root+'/w${width}',width)!;result+=os.read_file(root+'/w${width}/result.txt')!};os.write_file(root+'/result.txt',result)!
}
