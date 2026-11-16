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
fn bits(element int) int { return if element < 64 { element + 1 } else if element == 64 { 16 } else { 32 } }
fn typ(element int) string { return if element < 64 { 'i${element + 1}' } else if element == 64 { 'half' } else { 'float' } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn lane_word(element int, lane int) u64 {
 if element < 64 { return (u64(lane + 1) * u64(0x9e3779b97f4a7c15)) & mask(bits(element)) }
 if element == 64 { return [u64(0x3e00), 0x8000, 0x7c00, 0xfc00, 0x7c01, 0x7e55, 1, 0x3ff, 0x400, 0x7bff, 0xbc00, 0, 0xfc01, 0xfe55, 0x8001, 0x3555]![lane] }
 return [u64(0x3fc00000), 0x80000000, 0x7f800000, 0xff800000, 0x7f800001, 0x7fc12345, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0xbf800000, 0, 0xff800001, 0xffc12345, 0x80000001, 0x3eaaaaab]![lane]
}
fn literal(element int, word u64) string { return if element < 64 { word.str() } else if element == 64 { 'bitcast (i16 ${word} to half)' } else { 'bitcast (i32 ${word} to float)' } }
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(reference_data.data, usize(reference_data.len), c'vector-interleave'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 options_ref := C.LLVMCreatePassBuilderOptions(); assert C.LLVMRunPasses(module_ptr, c'always-inline', unsafe { nil }, options_ref) == unsafe { nil }; C.LLVMDisposePassBuilderOptions(options_ref)
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Case {name string element int factor int input int form int mode int}
fn suffix(element int) string {return if element<64 {'i${element+1}'}else if element==64 {'f16'}else{'f32'}}
fn intrinsic(c Case) string {return 'llvm.vector.interleave${c.factor}.v${c.factor*c.input}${suffix(c.element)}'}
fn vt(element int,count int) string {return '<${count} x ${typ(element)}>'}
fn vector(c Case,input int) string {
 if c.form>=2 {return ['poison','undef','zeroinitializer'][c.form-2]}
 mut s:=strings.new_builder(1024);s.write_string('<')
 for lane in 0..c.input {if lane>0 {s.write_string(', ')};state:=(lane+input)%4;value:=if c.form==1&&state==1 {'poison'}else if c.form==1&&state==2 {'undef'}else{literal(c.element,lane_word(c.element,(lane+input*3)%16))};s.write_string(typ(c.element)+' '+value)};s.write_string('>');return s.str()
}
fn expected(c Case,j u64,r u64,x u64,y u64) (int,u64) {
 count:=c.factor*c.input
 if r>=u64(count) {return 1,0}
 if c.mode==4 {if j>=u64(count) {return 1,0};if j==r {return 0,y}}
 input:=int(r)%c.factor;lane:=int(r)/c.factor
 mut state:=0;mut value:=u64(0)
 if c.mode!=0&&j>=u64(c.input) {state=1}
 else if c.mode!=0&&j==u64(lane) {value=if input%2==0 {x}else{y}}
 else if c.form==3||(c.form==1&&(lane+input)%4==2) {state=3}
 else if c.form==2||(c.form==1&&(lane+input)%4==1) {state=1}
 else{value=if c.form==4 {u64(0)}else{lane_word(c.element,(lane+input*3)%16)}}
 if c.mode in [2,3]&&state!=0 {return 2,0}
 return state,value
}
fn batch(assembler string,out string,element int) ! {
 mut s:=strings.new_builder(2097152);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 t:=typ(element);width:=bits(element)
 for factor in 2..9 {for input in 1..16/factor+1 {c:=Case{element:element,factor:factor,input:input};input_type:=vt(element,input);args:=[]string{len:factor,init:input_type};s.write_string('declare ${vt(element,factor*input)} @${intrinsic(c)}(${args.join(',')})\n')}}
 for factor in 2..9 {for input in 1..16/factor+1 {for form in 0..5 {for mode in 0..5 {
  c:=Case{'case_${cases.len}',element,factor,input,form,mode};cases<<c;input_type:=vt(element,input);ot:=vt(element,input*factor);mut args:=[]string{};mut ops:=''
  for i in 0..factor {ops+='%a${i} = insertelement ${input_type} ${vector(c,i)},${t} %${if i%2==0 {'x'}else{'y'}},i64 %j\n %f${i} = freeze ${input_type} %a${i}\n';args<<'${input_type} ${if mode==0 {vector(c,i)}else{'%'+if mode==2 {'f'}else{'a'}+i.str()}}'}
  ops+='%v = call ${ot} @${intrinsic(c)}(${args.join(',')})\n %f = freeze ${ot} %v\n %over = insertelement ${ot} %v,${t} %y,i64 %j\n %chosen = extractelement ${ot} %${if mode==3 {'f'}else if mode==4 {'over'}else{'v'}},i64 %r\n %raw = ${if element<64 {'or i${width} %chosen,0'}else{'bitcast ${t} %chosen to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n'
  s.write_string('define void @${c.name}(ptr %indices,ptr %src,ptr %out) {%j = load i64,ptr %indices,align 1\n %rp = getelementptr i8,ptr %indices,i64 8\n %r = load i64,ptr %rp,align 1\n %x = load ${t},ptr %src,align 1\n %yp = getelementptr i8,ptr %src,i64 8\n %y = load ${t},ptr %yp,align 1\n store i8 17,ptr %out\n ${ops}%d = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %d,align 1\n ret void }\n')
  s.write_string('define i64 @scalar_${c.name}(i64 %j,i64 %r,${t} %x,${t} %y) {${ops}ret i64 %wide }\n')
 }}}}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out,ir)!;defer{native.close()}
 mut exact:=0;mut frozen:=0;mut poison:=0;mut undef:=0;mut apis:=0;mut budgets:=0;mut metadata:=0
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('case\tj\tr\tx\ty\tstate\tvalue')!
 for c in cases {
  f:=fi(ir,c.name);sf:=fi(ir,'scalar_'+c.name);plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;steps:=c.factor*2+16;scalar_steps:=c.factor*2+7;assert plan.steps()==steps
  pointer:=C.LLVMGetFunctionAddress(native.engine,c.name.str);assert pointer!=0
  mut indices:=[]u8{len:24};mut input:=[]u8{len:24};mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bindings:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for sample in 0..c.factor*c.input+2 {
   edges:=[u64(0),u64(c.input-1),u64(c.input),~u64(0),1,2,3,u64(c.input+1)]!;j:=edges[(sample*3)%8];r:=if sample==c.factor*c.input+1 {~u64(0)}else{u64(sample)};x:=lane_word(element,sample%16);y:=lane_word(element,(sample+5)%16)
   state,value:=expected(c,j,r,x,y)
   for i in 0..8 {indices[1+i]=u8(j>>u32(i*8));indices[9+i]=u8(r>>u32(i*8));input[1+i]=u8(x>>u32(i*8));input[9+i]=u8(y>>u32(i*8))}
   args:=[j,r,x|~mask(width),y|~mask(width)]
   if state==3 {if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps) {panic('selected undef scalar')}else{assert err.msg().contains('undef'),err.msg()}}else{v:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps)!;assert v.poison==(state==1)&&v.steps==scalar_steps&&v.bits==64&&(v.poison||v.value==value),'${c} sample=${sample} state=${state} expected=${value} actual=${v}'};apis++
   if element<64 {if state==3 {if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps) {panic('selected undef integer')}}else{v:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps)!;assert v.poison==(state==1)&&v.steps==scalar_steps&&(v.poison||v.value==value)}}else{if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps) {panic('floating integer API')}};apis++
   for prepared in [false,true] {
    for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc};plan.validate(bindings,steps)!;unchanged(output)
    if prepared {if _:=plan.run(mut bindings,steps) {assert state in [0,2]}else{assert state in [1,3]&&err.msg().contains(if state==3 {'undef'}else{'poison store'}),err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,steps) {assert state in [0,2]}else{assert state in [1,3]&&err.msg().contains(if state==3 {'undef'}else{'poison store'}),err.msg()}}
    for i,b in output {assert b==if i==3 {u8(17)}else if state in [0,2]&&i>=11&&i<19 {u8(value>>u32((i-11)*8))}else{u8(0xcc)},'${c} sample=${sample} state=${state} byte=${i}'}
   }
   if state==0 {unsafe{NativeCast(voidptr(pointer))(&indices[1],&input[1],&reference[3])};assert output==reference,'native raw bits ${c} sample=${sample}';exact++}else if state==2 {frozen++}else if state==1 {poison++}else{undef++}
   rows.writeln('${c.name}\t${j}\t${r}\t${x}\t${y}\t${state}\t${value}')!;unsafe{args.free()}
  }
  for i in 0..output.len {output[i]=0xcc}
  if _:=plan.run(mut bindings,steps-1) {panic('prepared short budget')};unchanged(output)
  if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,steps-1) {panic('direct short budget')};unchanged(output);budgets+=2
  if c.form==0&&c.mode==0 {
   scope:=bodies.scopes[f+1]
   for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34 {continue}
    for change in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,result_type:-1}] {p.instructions[index]=change;if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,steps) {panic('interleave metadata')};unchanged(output);metadata++};p.instructions[index]=op
   }
  }
  plan.free();unsafe{indices.free();input.free();output.free();reference.free();bindings.free()}
 }
 assert cases.len==650&&exact+frozen+poison+undef==7550&&apis==15100&&budgets==1300&&metadata==208
 line:='AIR-VECTOR-INTERLEAVE-BATCH: ${element}, ${exact} native raw values, ${frozen} frozen choices, ${poison} poison, ${undef} selected undef, ${apis} scalar/integer checks, ${budgets} prewrite budgets, ${metadata} metadata refusals PASS\n'
 os.write_file(out+'/result.txt',line)!;print(line)
}
// Expand fixed interleaves to constant-lane copies in the independent native
// reference. Inlining avoids unusual fixed-vector argument/return ABI paths.
fn native_source(source string) string {
 mut result:=strings.new_builder(source.len*2)
 for line in source.split_into_lines() {
  if line.starts_with('declare ')&&line.contains('@llvm.vector.interleave') {
   end:=line.index('>') or {panic('vector type')};ot:=line[8..end+1];parts:=ot[1..ot.len-1].split(' x ');count:=parts[0].int();t:=parts[1]
   at:=line.index('@') or {panic('name')};paren:=line.index('(') or {panic('signature')};callee:=line[at+1..paren];factor:=int(callee[22]-`0`);input_type:='<${count/factor} x ${t}>';mut args:=[]string{}
   for i in 0..factor {args<<'${input_type} %a${i}'}
   result.write_string('define ${ot} @${callee}(${args.join(',')}) alwaysinline {\n')
   for lane in 0..count {result.write_string('%x${lane} = extractelement ${input_type} %a${lane%factor},i32 ${lane/factor}\n %v${lane} = insertelement ${ot} ${if lane==0 {'poison'}else{'%v'+(lane-1).str()}},${t} %x${lane},i32 ${lane}\n')}
   result.write_string('ret ${ot} %v${count-1} }\n')
  }else{result.write_string(line+'\n')}
 }
 return result.str().replace('@llvm.vector.interleave','@reference_interleave')
}
fn main() {
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 if os.args.len==4 {if os.args[3]=='controls' {controls(os.args[1],root+'/controls')!}else if os.args[3]=='loops' {loop_controls(os.args[1],root+'/loops')!}else{element:=os.args[3].int();batch(os.args[1],root+'/e'+element.str(),element)!};return}
 mut result:='';for element in 0..66 {batch(os.args[1],root+'/e${element}',element)!;result+=os.read_file(root+'/e${element}/result.txt')!}
 controls(os.args[1],root+'/controls')!;loop_controls(os.args[1],root+'/loops')!;result+=os.read_file(root+'/controls/result.txt')!+os.read_file(root+'/loops/result.txt')!;os.write_file(root+'/result.txt',result)!;print(result)
}
struct ControlResult {addresses int exact int copies int states int graph int depths string shared int}
fn control_batch(assembler string,root string,group int) !ControlResult {
 mut s:=strings.new_builder(4194304);s.write_string('target datalayout = "e-p:64:64"\n')
 for element in 0..66 {for factor in 2..9 {for input in 1..16/factor+1 {c:=Case{element:element,factor:factor,input:input};args:=[]string{len:factor,init:vt(element,input)};s.write_string('declare ${vt(element,input*factor)} @${intrinsic(c)}(${args.join(',')})\n')}}}
 for width in 1..65 {if (width-1)/8!=group {continue};for factor in 2..9 {for input in 1..16/factor+1 {
  c:=Case{element:width-1,factor:factor,input:input};input_type:=vt(width-1,input);ot:=vt(width-1,input*factor);mut args:=[]string{};mut signature:=[]string{};mut loads:=''
  for i in 0..factor {args<<'${input_type} %a${i}';signature<<'${input_type} %a${i}';loads+='%p${i} = getelementptr i8,ptr %src,i64 ${i*64}\n %w${i} = load <${input} x i64>,ptr %p${i},align 1\n %a${i} = ${if width==64 {'or ${input_type} %w${i},zeroinitializer'}else{'trunc <${input} x i64> %w${i} to ${input_type}'}}\n'}
  ops:='store i8 17,ptr %out\n %r = call ${ot} @${intrinsic(c)}(${args.join(',')})\n %v = extractelement ${ot} %r,i64 %j\n %idx = and i${width} %v,${mask(width)&63}\n %z = ${if width==64 {'or i64 %idx,0'}else{'zext i${width} %idx to i64'}}\n %p = getelementptr i8,ptr %out,i64 %z\n store i8 42,ptr %p\n ret void }\n'
  s.write_string('define void @addr_${width}_${factor}_${input}(${signature.join(',')},i64 %j,ptr %out) {${ops}')
  s.write_string('define void @case_addr_${width}_${factor}_${input}(ptr %src,ptr %selector,ptr %out) {${loads}%j = load i64,ptr %selector,align 1\n ${ops}')
 }}}
 for element in 0..66 {if element/8!=group {continue};for factor in 2..9 {for input in 1..16/factor+1 {for loaded in [false,true] {
  c:=Case{element:element,factor:factor,input:input};input_type:=vt(element,input);ot:=vt(element,input*factor);width:=bits(element);t:=typ(element);mut args:=[]string{};mut signature:=[]string{};mut loads:=''
  for i in 0..factor {args<<'${input_type} %a${i}';signature<<'${input_type} %a${i}';loads+='%p${i} = getelementptr i8,ptr %src,i64 ${i*64}\n %a${i} = load ${input_type},ptr %p${i},align 1\n'}
  s.write_string('define void @copy_${element}_${factor}_${input}_${loaded}(${if loaded {'ptr %src'}else{signature.join(',')}},i64 %j,ptr %out) {store i8 17,ptr %out\n ${if loaded {loads}else{''}}%r = call ${ot} @${intrinsic(c)}(${args.join(',')})\n %v = extractelement ${ot} %r,i64 %j\n %raw = ${if element<64 {'or i${width} %v,0'}else{'bitcast ${t} %v to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n %p = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %p,align 1\n ret void }\n')
 }}}}
 if group==0 {
 for factor in 2..9 {for freeze in [false,true] {for address in [false,true] {
  c:=Case{element:31,factor:factor,input:2,form:1};ot:=vt(31,factor*2);args:=[]string{len:factor,init:vt(31,2)+' '+vector(c,index)}
  s.write_string('define void @state_${factor}_${freeze}_${address}(i64 %j,ptr %out) {store i8 17,ptr %out\n %r = call ${ot} @${intrinsic(c)}(${args.join(',')})\n ${if freeze {'%f = freeze ${ot} %r\n'}else{''}}%v = extractelement ${ot} %${if freeze {'f'}else{'r'}},i64 %j\n ${if address {'%idx = and i32 %v,63\n %wide = zext i32 %idx to i64\n %p = getelementptr i8,ptr %out,i64 %wide\n store i8 42,ptr %p\n'}else{'%p = getelementptr i8,ptr %out,i64 8\n store i32 %v,ptr %p,align 1\n'}}ret void }\n')
 }}}
 for factor in 2..9 {for state in ['poison','undef'] {c:=Case{element:31,factor:factor,input:1};args:=[]string{len:factor,init:'<1 x i32> '+state};s.write_string('define void @discard_${factor}_${state}() {%r = call ${vt(31,factor)} @${intrinsic(c)}(${args.join(',')})\n ret void }\n')}}
 s.write_string('declare <4 x i32> @alias(<2 x i32>,<2 x i32>)\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <4 x i32> @llvm.vector.interleave2.v4i32(<2 x i32> zeroinitializer,<2 x i32> zeroinitializer)\n %b = call <4 x i32> @alias(<2 x i32> zeroinitializer,<2 x i32> zeroinitializer)\n ret void }\n')
 for factor in [2,8] {for amount in 1..13 {
  c:=Case{element:31,factor:factor,input:2};ot:=vt(31,factor*2)
  s.write_string('define void @depth_${factor}_${amount}(<2 x i32> %a,i64 %j,ptr %out) {store i8 17,ptr %out\n')
  for i in 0..amount {input:='%'+if i==0 {'a'}else{'v'+(i-1).str()};args:=[]string{len:factor,init:'<2 x i32> '+input};s.write_string('%r${i} = call ${ot} @${intrinsic(c)}(${args.join(',')})\n %v${i} = shufflevector ${ot} %r${i},${ot} poison,<2 x i32> <i32 0,i32 ${factor}>\n')}
  s.write_string('%v = extractelement <2 x i32> %v${amount-1},i64 %j\n %p = getelementptr i8,ptr %out,i32 %v\n ret void }\n')
 }}
 for amount in 220..258 {
  args:=[]string{len:8,init:'<2 x i32> %a'};s.write_string('define void @nodes_${amount}(<2 x i32> %a,i64 %j,ptr %out) {store i8 17,ptr %out\n %r = call <16 x i32> @llvm.vector.interleave8.v16i32(${args.join(',')})\n')
  for i in 0..amount {s.write_string('%v${i} = extractelement <16 x i32> %r,i64 %j\n %p${i} = getelementptr i8,ptr %out,i32 %v${i}\n')};s.write_string('ret void }\n')
 }
 }
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut addresses:=0;mut exact:=0;mut copies:=0;mut states:=0;mut graph:=0
 for width in 1..65 {if (width-1)/8!=group {continue};for factor in 2..9 {for input in 1..16/factor+1 {
  f:=fi(ir,'addr_${width}_${factor}_${input}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;pointer:=C.LLVMGetFunctionAddress(native.engine,'case_addr_${width}_${factor}_${input}'.str);assert pointer!=0
  mut words:=[]u64{len:64};mut inputs:=[][]u64{len:factor,init:[]u64{len:input}};mut selector:=[u64(0)];mut bytes:=[]u8{len:96,init:0xcc};mut reference:=bytes.clone();mut bs:=[]airbitcode.IRMemoryBinding{}
  for values in inputs {bs<<airbitcode.IRMemoryBinding{values:values}};bs<<airbitcode.IRMemoryBinding{values:selector};bs<<airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}
  for sample in 0..factor*input+2 {
   for i in 0..factor {for lane in 0..input {value:=((u64(lane+i*23+sample*7)*u64(0x9e3779b97f4a7c15))&mask(width))|~mask(width);inputs[i][lane]=value;words[i*8+lane]=value}}
   selector[0]=if sample==factor*input+1 {~u64(0)}else{u64(sample)};valid:=sample<factor*input;index:=if valid {int(inputs[sample%factor][sample/factor]&mask(width)&63)}else{0}
   for prepared in [false,true] {
    for i in 0..bytes.len {bytes[i]=0xcc;reference[i]=0xcc}
    if _:=plan.validate(bs,plan.steps()) {assert valid}else{assert !valid};unchanged(bytes)
    if prepared {if _:=plan.run(mut bs,plan.steps()) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert valid}else{assert !valid}}
    for i,b in bytes {assert b==if !valid {u8(0xcc)}else if i==3+index {u8(42)}else if i==3 {u8(17)}else{u8(0xcc)}};addresses++
   }
   if valid {unsafe{NativeCast(voidptr(pointer))(words.data,selector.data,&reference[3])};assert bytes==reference;exact++}
  }
  plan.free();unsafe{for values in inputs {values.free()};inputs.free();words.free();selector.free();bytes.free();reference.free();bs.free()}
 }}}
 for element in 0..66 {if element/8!=group {continue};for factor in 2..9 {for input in 1..16/factor+1 {for loaded in [false,true] {
  width:=bits(element);if loaded&&element<64&&width%8!=0 {continue}
  f:=fi(ir,'copy_${element}_${factor}_${input}_${loaded}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  mut bytes:=[]u8{len:516};mut inputs:=[][]u64{len:factor,init:[]u64{len:input}};mut selector:=[u64(0)];mut output:=[]u8{len:32,init:0xcc};mut bs:=[]airbitcode.IRMemoryBinding{}
  for i in 0..factor {for lane in 0..input {value:=lane_word(element,(lane+i*3)%16)|~mask(width);inputs[i][lane]=value;for j in 0..(width+7)/8 {bytes[1+i*64+lane*((width+7)/8)+j]=u8(value>>u32(j*8))}}}
  if loaded {bs<<airbitcode.IRMemoryBinding{data:bytes,offset:1}}else{for values in inputs {bs<<airbitcode.IRMemoryBinding{values:values}}};bs<<airbitcode.IRMemoryBinding{values:selector};bs<<airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}
  for lane in 0..factor*input {selector[0]=u64(lane);expected_word:=inputs[lane%factor][lane/factor]&mask(width)
   for prepared in [false,true] {for i in 0..output.len {output[i]=0xcc};plan.validate(bs,plan.steps())!;unchanged(output);if prepared {plan.run(mut bs,plan.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps())!};for i,b in output {assert b==if i==3 {u8(17)}else if i>=11&&i<19 {u8(expected_word>>u32((i-11)*8))}else{u8(0xcc)}};copies++}
  };plan.free();unsafe{for values in inputs {values.free()};inputs.free();bytes.free();selector.free();output.free();bs.free()}
 }}}}
 mut depths:='';mut max_shared:=0
 if group==0 {
 for factor in 2..9 {for freeze in [false,true] {for address in [false,true] {
  f:=fi(ir,'state_${factor}_${freeze}_${address}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;c:=Case{element:31,factor:factor,input:2,form:1}
  for lane in 0..factor*2+2 {
   state,word:=expected(c,0,u64(lane),0,0);valid:=state==0||(freeze&&lane<factor*2);value:=if state==0 {word}else{u64(0)};index:=value&63
   for prepared in [false,true] {mut output:=[]u8{len:96,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:[u64(lane)]},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
    if _:=plan.validate(bs,plan.steps()) {assert !address||valid}else{assert address&&!valid};unchanged(output)
    if prepared {if _:=plan.run(mut bs,plan.steps()) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert valid}else{assert !valid}}
    for i,b in output {assert b==if address&&!valid {u8(0xcc)}else if address&&i==3+int(index) {u8(42)}else if i==3 {u8(17)}else if !address&&valid&&i>=11&&i<15 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}};states++;unsafe{output.free();bs[0].values.free();bs.free()}
   }
  };plan.free()
 }}}
 for factor in 2..9 {for state in ['poison','undef'] {assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_${factor}_${state}'),[],2)!.steps==2;states++}}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.vector.interleave2.v4i32'}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10) {panic('duplicate interleave')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration',err.msg()};unchanged(output);states++

 for factor in [2,8] {mut maximum:=0;mut refused:=false;for amount in 1..13 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'depth_${factor}_${amount}')) {assert !refused;maximum=amount;plan.free()}else{refused=true};graph++};assert maximum>0&&maximum<12;depths+=' factor${factor}=${maximum}'}
 mut refused_nodes:=false
 for amount in 220..258 {if profile:=p.memory_function_profile(ir,stream,pools,bodies,fi(ir,'nodes_${amount}')) {assert !refused_nodes;max_shared=amount;profile.free()}else{refused_nodes=true};graph++};assert max_shared>=220&&max_shared<257
 for storage in [false,true] {for over in [false,true] {limits(assembler,root+'/limit-${storage}-${over}',storage,over)!;graph+=2}}
 unsafe{output.free();bs.free()}
 }
 line:='AIR-VECTOR-INTERLEAVE-GROUP: ${addresses} address API checks, ${exact} native address values, ${copies} typed/loaded lane copies, ${states} state/discard/duplicate controls, ${graph} graph/resource checks (max cycles${depths}, ${max_shared} shared extractions) PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
 return ControlResult{addresses,exact,copies,states,graph,depths,max_shared}
}
fn limits(assembler_path string,out string,storage bool,over bool) ! {
 mut s:=strings.new_builder(10485760);count:=if storage {2}else{16};factor:=if storage {2}else{8};input:=count/factor;input_type:='<${input} x half>';ot:='<${count} x half>';args:=[]string{len:factor,init:input_type+' zeroinitializer'}
 s.write_string('declare ${ot} @llvm.vector.interleave${factor}.v${count}f16(${[]string{len:factor,init:input_type}.join(',')})\n')
 for name in ['memory','scalar'] {
  s.write_string('define void @${name}(${if name=='memory' {'ptr %out'}else{''}}) {\n');if name=='memory' {s.write_string('store i8 17,ptr %out,align 1\n')}
  for i in 0..if storage&&over {4097}else{4096} {s.write_string('%v${i} = call ${ot} @llvm.vector.interleave${factor}.v${count}f16(${args.join(',')})\n')}
  if !storage {for i in 0..if over {54309}else{54308} {s.write_string('%x${i} = extractelement <16 x half> %v4095,i32 0\n')}};s.write_string('ret void }\n')
 }
 data:=assemble(assembler_path,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('memory interleave limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('scalar interleave limit')}else{assert err.msg()==diagnostic,err.msg()}}else{assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098}else{58406};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!.steps==if storage {4097}else{58405}}
 unsafe{output.free();bs.free()}
}
fn loop_controls(assembler string,root string) ! {
 mut s:=strings.new_builder(1048576);s.write_string('target datalayout = "e-p:64:64"\n')
 for element in [0,6,63,64,65] {for factor in 2..9 {for input in 1..16/factor+1 {
  c:=Case{element:element,factor:factor,input:input};input_type:=vt(element,input);ot:=vt(element,input*factor);t:=typ(element);width:=bits(element);signature:=[]string{len:factor,init:input_type};mut args:=[]string{}
  for i in 0..factor {args<<input_type+' %'+if i==0 {'a'}else{'v'}}
  s.write_string('declare ${ot} @${intrinsic(c)}(${signature.join(',')})\n')
  lanes:=[]string{len:input,init:'i32 '+(index*factor).str()}
  ops:='br label %body\n body: %v = phi ${input_type} [${vector(c,0)},%entry],[%u,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %first = icmp eq i64 %i,0\n %pick = select i1 %first,${t} %x,${t} %y\n %a = insertelement ${input_type} %v,${t} %pick,i32 0\n %r = call ${ot} @${intrinsic(c)}(${args.join(',')})\n %u = shufflevector ${ot} %r,${ot} poison,<${input} x i32> <${lanes.join(',')}>\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %chosen = extractelement ${ot} %r,i32 0\n %raw = ${if element<64 {'or i${width} %chosen,0'}else{'bitcast ${t} %chosen to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n'
  s.write_string('define i64 @loop_${element}_${factor}_${input}(${t} %x,${t} %y,i64 %limit) {entry: ${ops}ret i64 %wide }\n')
  s.write_string('define void @case_loop_${element}_${factor}_${input}(ptr %src,ptr %counter,ptr %out) {entry: %x = load ${t},ptr %src,align 1\n %yp = getelementptr i8,ptr %src,i64 8\n %y = load ${t},ptr %yp,align 1\n %limit = load i64,ptr %counter,align 1\n ${ops}store i64 %wide,ptr %out,align 1\n ret void }\n')
 }}}
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut exact:=0;mut apis:=0;mut budgets:=0
 for element in [0,6,63,64,65] {for factor in 2..9 {for input in 1..16/factor+1 {
  width:=bits(element);x:=lane_word(element,4);y:=lane_word(element,13);mut bytes:=[16]u8{}
  for b in 0..8 {bytes[b]=u8(x>>u32(b*8));bytes[8+b]=u8(y>>u32(b*8))}
  f:=fi(ir,'loop_${element}_${factor}_${input}');address:=C.LLVMGetFunctionAddress(native.engine,'case_loop_${element}_${factor}_${input}'.str);assert address!=0
  for visits in [u64(1),2,3,7,16,257,513,1024]! {
   expected_word:=if visits==1 {x}else{y};mut reference:=u64(0)
   unsafe{NativeCast(voidptr(address))(&bytes[0],&visits,&reference)};assert reference==expected_word;exact++
   args:=[x|~mask(width),y|~mask(width),visits];steps:=int(visits*10+5);v:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps)!;assert !v.poison&&v.value==expected_word&&v.steps==steps;apis++
   if element<64 {r:=p.run_integer_function(ir,stream,pools,bodies,f,args,steps)!;assert !r.poison&&r.value==expected_word;apis++}
   if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps-1) {panic('interleave loop short budget')};budgets++;unsafe{args.free()}
  }
 }}}
 assert exact==1040&&apis==1664&&budgets==1040
 line:='AIR-VECTOR-INTERLEAVE-LOOPS: ${exact} native raw vector-PHI loop results, ${apis} scalar/integer checks, ${budgets} executed-budget refusals, every factor/count and i1/i7/i64/half/float, 1 through 1024 iterations PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
// Keep each serialized module below the production record limit while retaining
// every width, shape, typed/loaded input, state and resource case.
fn controls(assembler string,root string) ! {
 assert !os.exists(root);os.mkdir_all(root)!
 mut addresses:=0;mut exact:=0;mut copies:=0;mut states:=0;mut graph:=0;mut depths:='';mut shared:=0
 for group in 0..9 {r:=control_batch(assembler,root+'/g${group}',group)!;addresses+=r.addresses;exact+=r.exact;copies+=r.copies;states+=r.states;graph+=r.graph;if group==0 {depths=r.depths;shared=r.shared}}
 assert addresses==38656&&exact==16000&&copies==38000&&states==687&&graph==70
 line:='AIR-VECTOR-INTERLEAVE-CONTROLS: ${addresses} address API checks, ${exact} native address values, ${copies} typed/loaded lane copies, ${states} state/discard/duplicate controls, ${graph} graph/resource checks (max cycles${depths}, ${shared} shared extractions) PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
