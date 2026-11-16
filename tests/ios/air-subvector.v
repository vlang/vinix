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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(reference_data.data, usize(reference_data.len), c'subvector'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 options_ref := C.LLVMCreatePassBuilderOptions(); assert C.LLVMRunPasses(module_ptr, c'always-inline', unsafe { nil }, options_ref) == unsafe { nil }; C.LLVMDisposePassBuilderOptions(options_ref)
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn bits(element int) int {return if element<64 {element+1}else if element==64 {16}else{32}}
fn typ(element int) string {return if element<64 {'i${element+1}'}else if element==64 {'half'}else{'float'}}
fn suffix(element int) string {return if element<64 {'i${element+1}'}else if element==64 {'f16'}else{'f32'}}
fn vt(element int,count int) string {return '<${count} x ${typ(element)}>'}
fn lane_word(element int,lane int) u64 {
 if element<64 {return (u64(lane+1)*u64(0x9e3779b97f4a7c15))&mask(bits(element))}
 if element==64 {return [u64(0x3e00),0x8000,0x7c00,0xfc00,0x7c01,0x7e55,1,0x3ff,0x400,0x7bff,0xbc00,0,0xfc01,0xfe55,0x8001,0x3555]![lane]}
 return [u64(0x3fc00000),0x80000000,0x7f800000,0xff800000,0x7f800001,0x7fc12345,1,0x7fffff,0x800000,0x7f7fffff,0xbf800000,0,0xff800001,0xffc12345,0x80000001,0x3eaaaaab]![lane]
}
fn literal(element int,word u64) string {return if element<64 {word.str()}else if element==64 {'bitcast (i16 ${word} to half)'}else{'bitcast (i32 ${word} to float)'}}
fn vector(element int,count int,mixed bool) string {
 mut lanes:=[]string{}
 for lane in 0..count {lanes<<typ(element)+' '+if mixed&&lane%4==1 {'poison'}else if mixed&&lane%4==2 {'undef'}else{literal(element,lane_word(element,lane))}}
 return '<'+lanes.join(',')+'>'
}
// Native reference uses explicit scalar extraction/insertion and is inlined
// before JIT, avoiding vector ABI differences for odd lane counts and widths.
fn native_source(source string) string {
 mut result:=strings.new_builder(source.len*2)
 for line in source.split_into_lines() {
  if line.starts_with('declare ')&&line.contains('@llvm.vector.extract.') {
   end:=line.index('>') or {panic('type')};output_type:=line[8..end+1];count:=output_type[1..output_type.len-1].split(' x ')[0].int();t:=output_type[1..output_type.len-1].split(' x ')[1]
   at:=line.index('@') or {panic('name')};paren:=line.index('(') or {panic('args')};name:=line[at+1..paren];input_type:=line[paren+1..].all_before(',')
   result.write_string('define ${output_type} @${name}(${input_type} %src,i64 %offset) alwaysinline {\n')
   for lane in 0..count {result.write_string('%i${lane} = add i64 %offset,${lane}\n %e${lane} = extractelement ${input_type} %src,i64 %i${lane}\n %v${lane} = insertelement ${output_type} ${if lane==0 {'poison'}else{'%v'+(lane-1).str()}},${t} %e${lane},i32 ${lane}\n')}
   result.write_string('ret ${output_type} %v${count-1} }\n')
  }else{result.write_string(line+'\n')}
 }
 return result.str().replace('@llvm.vector.extract.','@reference_subvector_')
}
struct Case {name string source int count int offset int mode int}
fn expected(c Case,element int,j u64,r u64,x u64) (int,u64) {
 if r>=u64(c.count) {return 1,0}
 selected:=u64(c.offset)+r
 if c.mode==4 {if j>=u64(c.source) {return 1,0};if j==selected {return 0,x}}
 if c.mode in [1,2,3]&&selected%4 in [1,2] {return if c.mode!=1 {2}else if selected%4==1 {1}else{3},0}
 return 0,lane_word(element,int(selected))
}
fn batch(assembler string,out string,element int) ! {
 t:=typ(element);width:=bits(element);mut s:=strings.new_builder(4194304);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 for source_count in 1..17 {for count in 1..source_count+1 {
  st:=vt(element,source_count);ot:=vt(element,count);name:='llvm.vector.extract.v${count}${suffix(element)}.v${source_count}${suffix(element)}'
  s.write_string('declare ${ot} @${name}(${st},i64 immarg)\n')
  for offset in 0..source_count-count+1 {if offset%count!=0 {continue}
   for mode in 0..5 {
    c:=Case{'case_${cases.len}',source_count,count,offset,mode};cases<<c
    input:=if mode in [1,3] {vector(element,source_count,true)}else if mode==2 {'%fs'}else if mode==4 {'%insert'}else{vector(element,source_count,false)}
    ops:='%fs = freeze ${st} ${vector(element,source_count,true)}\n %insert = insertelement ${st} ${vector(element,source_count,false)},${t} %x,i64 %j\n %v = call ${ot} @${name}(${st} ${input},i64 ${offset})\n %f = freeze ${ot} %v\n %chosen = extractelement ${ot} %${if mode==3 {'f'}else{'v'}},i64 %r\n %raw = ${if element<64 {'or i${width} %chosen,0'}else{'bitcast ${t} %chosen to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n'
    s.write_string('define i64 @scalar_${c.name}(i64 %j,i64 %r,${t} %x) {${ops}ret i64 %wide }\n')
    s.write_string('define void @${c.name}(ptr %indices,ptr %src,ptr %out) {%j = load i64,ptr %indices,align 1\n %rp = getelementptr i8,ptr %indices,i64 8\n %r = load i64,ptr %rp,align 1\n %x = load ${t},ptr %src,align 1\n store i8 17,ptr %out\n ${ops}%dest = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %dest,align 1\n ret void }\n')
   }
  }
 }}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out,ir)!;defer{native.close()}
 mut exact:=0;mut frozen:=0;mut poison:=0;mut undef:=0;mut apis:=0;mut budgets:=0;mut metadata:=0
 for c in cases {
  f:=fi(ir,c.name);sf:=fi(ir,'scalar_'+c.name);plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==15
  pointer:=C.LLVMGetFunctionAddress(native.engine,c.name.str);assert pointer!=0
  mut indices:=[]u8{len:24};mut input:=[]u8{len:16};mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bs:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for sample in 0..c.count+2 {
   j:=[u64(0),u64(c.source-1),u64(c.source),~u64(0),u64(c.offset),1,2,3]![sample%8];r:=if sample==c.count+1 {~u64(0)}else{u64(sample)};x:=lane_word(element,(sample+5)%16);state,value:=expected(c,element,j,r,x)
   for i in 0..8 {indices[1+i]=u8(j>>u32(i*8));indices[9+i]=u8(r>>u32(i*8));input[1+i]=u8(x>>u32(i*8))}
   args:=[j,r,x|~mask(width)]
   for integer in [false,true] {
    if integer {if v:=p.run_integer_function(ir,stream,pools,bodies,sf,args,8) {assert element<64&&state!=3&&v.poison==(state==1)&&(v.poison||v.value==value)&&v.steps==8}else{assert element>=64||state==3}}
    else {if v:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,8) {assert state!=3&&v.poison==(state==1)&&(v.poison||v.value==value)&&v.steps==8}else{assert state==3,err.msg()}};apis++
   }
   for prepared in [false,true] {
    for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc};plan.validate(bs,15)!;unchanged(output)
    if prepared {if _:=plan.run(mut bs,15) {assert state in [0,2]}else{assert state in [1,3],err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,15) {assert state in [0,2]}else{assert state in [1,3],err.msg()}}
    for i,b in output {assert b==if i==3 {u8(17)}else if state in [0,2]&&i>=11&&i<19 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}}
   }
   if state==0 {unsafe{NativeCast(voidptr(pointer))(&indices[1],&input[1],&reference[3])};assert output==reference;exact++}else if state==1 {poison++}else if state==2 {frozen++}else{undef++};unsafe{args.free()}
  }
  for i in 0..output.len {output[i]=0xcc};if _:=plan.run(mut bs,14) {panic('short prepared')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,14) {panic('short direct')};unchanged(output);budgets+=2
  if c.mode==0 {scope:=bodies.scopes[f+1];for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {
   op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34 {continue}
   for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,operands_count:4},airbitcode.IRTypedInstruction{...op,result_type:-1}] {p.instructions[index]=changed;if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,15) {panic('subvector metadata')};unchanged(output);metadata++};p.instructions[index]=op
  }}
  plan.free();unsafe{indices.free();input.free();output.free();reference.free();bs.free()}
 }
 assert cases.len==1820&&exact+frozen+poison+undef==10020&&apis==20040&&budgets==3640&&metadata==3276
 line:='AIR-SUBVECTOR-BATCH: ${element}, ${exact} native values, ${frozen} frozen choices, ${poison} poison, ${undef} selected undef, ${apis} scalar/integer checks, ${budgets} budgets, ${metadata} metadata refusals PASS\n';os.write_file(out+'/result.txt',line)!;print(line)
}
fn main() {
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 if os.args.len==4 {
  if os.args[3]=='address' {for width in 1..65 {address_batch(os.args[1],root+'/w${width}',width)!}}
  else {batch(os.args[1],root+'/e0',0)!}
  return
 }
 mut result:='';for element in 0..66 {batch(os.args[1],root+'/e${element}',element)!;result+=os.read_file(root+'/e${element}/result.txt')!};os.write_file(root+'/result.txt',result)!
}
fn address_batch(assembler string,out string,width int) ! {
 mut s:=strings.new_builder(4194304);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 for source_count in 1..17 {for count in 1..source_count+1 {
  st:='<${source_count} x i${width}>';ot:='<${count} x i${width}>';name:='llvm.vector.extract.v${count}i${width}.v${source_count}i${width}'
  s.write_string('declare ${ot} @${name}(${st},i64 immarg)\n')
  for offset in 0..source_count-count+1 {if offset%count!=0 {continue}
   for sb in [1,32,64] {for mode in 0..3 {
    c:=Case{'case_address_${cases.len}',source_count,count,offset,mode};cases<<c;mut lanes:=[]string{}
    for lane in 0..source_count {lanes<<'i${width} '+if mode>0&&lane%4==1 {'poison'}else if mode>0&&lane%4==2 {'undef'}else{(u64(lane)&mask(width)).str()}}
    ops:='store i8 17,ptr %out\n %v = call ${ot} @${name}(${st} <${lanes.join(',')}>,i64 ${offset})\n %f = freeze ${ot} %v\n %e = extractelement ${ot} %${if mode==2 {'f'}else{'v'}},i${sb} %r\n %index = ${if width==64 {'or i64 %e,0'}else{'zext i${width} %e to i64'}}\n %p = getelementptr i8,ptr %out,i64 %index\n store i8 42,ptr %p\n ret void }\n'
    s.write_string('define void @address_${cases.len-1}(i${sb} %r,ptr %out) {${ops}')
    s.write_string('define void @${c.name}(ptr %indices,ptr %unused,ptr %out) {%raw = load i64,ptr %indices,align 1\n %r = ${if sb==64 {'or i64 %raw,0'}else{'trunc i64 %raw to i${sb}'}}\n ${ops}')
   }}
  }
 }}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out,ir)!;defer{native.close()}
 mut checks:=0;mut exact:=0;mut frozen:=0;mut refusals:=0
 for i,c in cases {
  sb:=[1,32,64]![(i/3)%3];f:=fi(ir,'address_${i}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==8
  pointer:=C.LLVMGetFunctionAddress(native.engine,c.name.str);assert pointer!=0
  mut selector:=[u64(0)];mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bs:=[airbitcode.IRMemoryBinding{values:selector},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for sample in 0..c.count+2 {
   selector[0]=if sample==c.count+1 {~u64(0)}else{u64(sample)|~mask(sb)};r:=selector[0]&mask(sb);selected:=u64(c.offset)+r;bad_lane:=c.mode>0&&selected%4 in [1,2];valid:=r<u64(c.count)&&(!bad_lane||c.mode==2);value:=if bad_lane {u64(0)}else{selected&mask(width)}
   for prepared in [false,true] {
    for j in 0..output.len {output[j]=0xcc;reference[j]=0xcc};if _:=plan.validate(bs,8) {assert valid}else{assert !valid};unchanged(output)
    if prepared {if _:=plan.run(mut bs,8) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,8) {assert valid}else{assert !valid}}
    for j,b in output {assert b==if !valid {u8(0xcc)}else if j==3+int(value) {u8(42)}else if j==3 {u8(17)}else{u8(0xcc)}};checks++
   }
   if valid&&!bad_lane {unsafe{NativeCast(voidptr(pointer))(&selector[0],unsafe{nil},&reference[3])};assert output==reference;exact++}else if valid {frozen++}else{refusals++}
  }
  plan.free();unsafe{selector.free();output.free();reference.free();bs.free()}
 }
 assert cases.len==3276&&checks==36072&&exact+frozen+refusals==18036
 line:='AIR-SUBVECTOR-ADDRESS: i${width}, ${checks} API checks, ${exact} native addresses, ${frozen} frozen choices, ${refusals} prewrite refusals PASS\n';os.write_file(out+'/result.txt',line)!;print(line)
}
