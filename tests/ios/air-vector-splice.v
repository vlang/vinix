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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(reference_data.data, usize(reference_data.len), c'vector-splice'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 options_ref := C.LLVMCreatePassBuilderOptions(); assert C.LLVMRunPasses(module_ptr, c'always-inline', unsafe { nil }, options_ref) == unsafe { nil }; C.LLVMDisposePassBuilderOptions(options_ref)
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Case {name string element int count int form int mode int right bool}
fn suffix(element int) string {return if element<64 {'i${element+1}'}else if element==64 {'f16'}else{'f32'}}
fn name(c Case) string {return 'llvm.vector.splice.${if c.right {'right'}else{'left'}}.v${c.count}${suffix(c.element)}'}
fn vector(c Case,second bool) string {
 if c.form>=2 {return ['poison','undef','zeroinitializer'][c.form-2]}
 mut s:=strings.new_builder(1024);s.write_string('<')
 for lane in 0..c.count {if lane>0 {s.write_string(', ')};state:=(lane+int(second))%4;v:=if c.form==1&&state==1 {'poison'}else if c.form==1&&state==2 {'undef'}else{literal(c.element,lane_word(c.element,(lane+int(second)*7)%16))};s.write_string(typ(c.element)+' '+v)};s.write_string('>');return s.str()
}
fn expected(c Case,j u64,offset u64,r u64,x u64,y u64) (int,u64) {
 if r>=u64(c.count) {return 1,0}
 if c.mode==4 {if j>=u64(c.count) {return 1,0};if j==r {return 0,y}}
 if offset>u64(c.count) {return if c.mode==3 {2}else{1},0}
 selected:=(if c.right {c.count-int(offset)}else{int(offset)})+int(r)
 second:=selected>=c.count;lane:=selected%c.count
 mut state:=0;mut value:=u64(0)
 if c.mode!=0&&j>=u64(c.count) {state=1}
 else if c.mode!=0&&j==u64(lane) {value=if second {y}else{x}}
 else if c.form==3||(c.form==1&&(lane+int(second))%4==2) {state=3}
 else if c.form==2||(c.form==1&&(lane+int(second))%4==1) {state=1}
 else{value=if c.form==4 {u64(0)}else{lane_word(c.element,(lane+int(second)*7)%16)}}
 if c.mode in [2,3]&&state!=0 {return 2,0}
 return state,value
}
fn batch(assembler string,out string,element int) ! {
 mut s:=strings.new_builder(2097152);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 t:=typ(element);width:=bits(element)
 for count in 1..17 {for right in [false,true] {c:=Case{count:count,element:element,right:right};vt:='<${count} x ${t}>';s.write_string('declare ${vt} @${name(c)}(${vt},${vt},i32)\n')}}
 for count in 1..17 {for right in [false,true] {for form in 0..5 {for mode in 0..5 {
  c:=Case{'case_${cases.len}',element,count,form,mode,right};cases<<c;vt:='<${count} x ${t}>'
  ops:='%a = insertelement ${vt} ${vector(c,false)},${t} %x,i64 %j\n %b = insertelement ${vt} ${vector(c,true)},${t} %y,i64 %j\n %fa = freeze ${vt} %a\n %fb = freeze ${vt} %b\n %splice = call ${vt} @${name(c)}(${vt} ${if mode==0 {vector(c,false)}else if mode==2 {'%fa'}else{'%a'}},${vt} ${if mode==0 {vector(c,true)}else if mode==2 {'%fb'}else{'%b'}},i32 %offset)\n %f = freeze ${vt} %splice\n %over = insertelement ${vt} %splice,${t} %y,i64 %j\n %v = extractelement ${vt} %${if mode==3 {'f'}else if mode==4 {'over'}else{'splice'}},i64 %r\n %raw = ${if element<64 {'or i${width} %v,0'}else{'bitcast ${t} %v to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n'
  s.write_string('define void @${c.name}(ptr %indices,ptr %src,ptr %out) {%j = load i64,ptr %indices,align 1\n %op = getelementptr i8,ptr %indices,i64 8\n %offset = load i32,ptr %op,align 1\n %rp = getelementptr i8,ptr %indices,i64 16\n %r = load i64,ptr %rp,align 1\n %x = load ${t},ptr %src,align 1\n %yp = getelementptr i8,ptr %src,i64 8\n %y = load ${t},ptr %yp,align 1\n store i8 17,ptr %out\n ${ops}%d = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %d,align 1\n ret void }\n')
  s.write_string('define i64 @scalar_${c.name}(i64 %j,i32 %offset,i64 %r,${t} %x,${t} %y) {${ops}ret i64 %wide }\n')
 }}}}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out,ir)!;defer{native.close()}
 mut exact:=0;mut frozen:=0;mut poison:=0;mut undef:=0;mut apis:=0;mut budgets:=0;mut metadata:=0
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('case\tj\toffset\tr\tx\ty\tstate\tvalue')!
 for c in cases {
  f:=fi(ir,c.name);sf:=fi(ir,'scalar_'+c.name);plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==22
  pointer:=C.LLVMGetFunctionAddress(native.engine,c.name.str);assert pointer!=0
  mut indices:=[]u8{len:32};mut input:=[]u8{len:24};mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bindings:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for sample in 0..c.count+5 {
   offset:=if sample<=c.count+1 {u64(sample)}else if sample==c.count+2 {u64(0xffffffff)}else{u64(c.count/2)}
   r:=if sample==c.count+3 {u64(c.count)}else if sample==c.count+4 {~u64(0)}else{u64(sample%c.count)}
   edges:=[u64(0),u64(c.count-1),u64(c.count),~u64(0),1,2,3,u64(c.count+1)]!
   j:=edges[(sample*3)%8];x:=lane_word(element,sample%16);y:=lane_word(element,(sample+5)%16)
   state,value:=expected(c,j,offset,r,x,y)
   for i in 0..8 {indices[1+i]=u8(j>>u32(i*8));indices[9+i]=u8(offset>>u32(i*8));indices[17+i]=u8(r>>u32(i*8));input[1+i]=u8(x>>u32(i*8));input[9+i]=u8(y>>u32(i*8))}
   args:=[j,offset|0xeeeeeeee00000000,r,x|~mask(width),y|~mask(width)]
   if state==3 {if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,11) {panic('selected undef scalar')}else{assert err.msg().contains('undef'),err.msg()}}else{v:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,11)!;assert v.poison==(state==1)&&v.steps==11&&v.bits==64&&(v.poison||v.value==value),'${c} sample=${sample} state=${state} expected=${value} actual=${v}'};apis++
   if element<64 {if state==3 {if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,11) {panic('selected undef integer')}}else{v:=p.run_integer_function(ir,stream,pools,bodies,sf,args,11)!;assert v.poison==(state==1)&&v.steps==11&&(v.poison||v.value==value)}}else{if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,11) {panic('floating integer API')}};apis++
   for prepared in [false,true] {
    for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc};plan.validate(bindings,22)!;unchanged(output)
    if prepared {if _:=plan.run(mut bindings,22) {assert state in [0,2]}else{assert state in [1,3]&&err.msg().contains(if state==3 {'undef'}else{'poison store'}),err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,22) {assert state in [0,2]}else{assert state in [1,3]&&err.msg().contains(if state==3 {'undef'}else{'poison store'}),err.msg()}}
    for i,b in output {assert b==if i==3 {u8(17)}else if state in [0,2]&&i>=11&&i<19 {u8(value>>u32((i-11)*8))}else{u8(0xcc)},'${c} sample=${sample} state=${state} byte=${i}'}
   }
   if state==0 {unsafe{NativeCast(voidptr(pointer))(&indices[1],&input[1],&reference[3])};assert output==reference,'native raw bits ${c} sample=${sample}';exact++}else if state==2 {frozen++}else if state==1 {poison++}else{undef++}
   rows.writeln('${c.name}\t${j}\t${offset}\t${r}\t${x}\t${y}\t${state}\t${value}')!;unsafe{args.free()}
  }
  for i in 0..output.len {output[i]=0xcc}
  if _:=plan.run(mut bindings,21) {panic('prepared short budget')};unchanged(output)
  if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,21) {panic('direct short budget')};unchanged(output);budgets+=2
  if c.form==0&&c.mode==0 {
   scope:=bodies.scopes[f+1]
   for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34 {continue}
    for change in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:3},airbitcode.IRTypedInstruction{...op,result_type:-1}] {p.instructions[index]=change;if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,22) {panic('splice metadata')};unchanged(output);metadata++};p.instructions[index]=op
   }
  }
  plan.free();unsafe{indices.free();input.free();output.free();reference.free();bindings.free()}
 }
 assert cases.len==800&&exact+frozen+poison+undef==10800&&apis==21600&&budgets==1600&&metadata==256
 line:='AIR-VECTOR-SPLICE-BATCH: ${element}, ${exact} native raw values, ${frozen} frozen choices, ${poison} poison, ${undef} selected undef, ${apis} scalar/integer checks, ${budgets} prewrite budgets, ${metadata} metadata refusals PASS\n'
 os.write_file(out+'/result.txt',line)!;print(line)
}
fn main() {
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 if os.args.len==4 {if os.args[3]=='controls' {controls(os.args[1],root+'/controls')!}else{element:=os.args[3].int();batch(os.args[1],root+'/e'+element.str(),element)!};return}
 mut result:='';for element in 0..66 {batch(os.args[1],root+'/e${element}',element)!;result+=os.read_file(root+'/e${element}/result.txt')!}
 controls(os.args[1],root+'/controls')!;loop_controls(os.args[1],root+'/loops')!;result+=os.read_file(root+'/controls/result.txt')!+os.read_file(root+'/loops/result.txt')!;os.write_file(root+'/result.txt',result)!;print(result)
}
fn controls(assembler string,root string) ! {
 mut s:=strings.new_builder(4194304);s.write_string('target datalayout = "e-p:64:64"\n')
 for element in 0..66 {for count in 1..17 {for right in [false,true] {c:=Case{element:element,count:count,right:right};vt:='<${count} x ${typ(element)}>';s.write_string('declare ${vt} @${name(c)}(${vt},${vt},i32)\n')}}}
 for width in 1..65 {for count in 1..17 {for right in [false,true] {
  c:=Case{element:width-1,count:count,right:right};t:='<${count} x i${width}>'
  ops:='store i8 17,ptr %out\n %r = call ${t} @${name(c)}(${t} %a,${t} %b,i32 %offset)\n %v = extractelement ${t} %r,i64 %j\n %idx = and i${width} %v,${mask(width)&63}\n %z = ${if width==64 {'or i64 %idx,0'}else{'zext i${width} %idx to i64'}}\n %p = getelementptr i8,ptr %out,i64 %z\n store i8 42,ptr %p\n ret void }\n'
  s.write_string('define void @addr_${width}_${count}_${right}(${t} %a,${t} %b,i32 %offset,i64 %j,ptr %out) {${ops}')
  s.write_string('define void @case_addr_${width}_${count}_${right}(ptr %src,ptr %selector,ptr %out) {%aw = load <${count} x i64>,ptr %src,align 1\n %bp = getelementptr i8,ptr %src,i64 128\n %bw = load <${count} x i64>,ptr %bp,align 1\n %a = ${if width==64 {'or ${t} %aw,zeroinitializer'}else{'trunc <${count} x i64> %aw to ${t}'}}\n %b = ${if width==64 {'or ${t} %bw,zeroinitializer'}else{'trunc <${count} x i64> %bw to ${t}'}}\n %offset = load i32,ptr %selector,align 1\n %jp = getelementptr i8,ptr %selector,i64 8\n %j = load i64,ptr %jp,align 1\n ${ops}')
 }}}
 for element in 0..66 {for count in [1,3,16] {for right in [false,true] {for loaded in [false,true] {
  c:=Case{element:element,count:count,right:right};vt:='<${count} x ${typ(element)}>';width:=bits(element);t:=typ(element)
  s.write_string('define void @copy_${element}_${count}_${right}_${loaded}(${if loaded {'ptr %src'}else{'${vt} %a,${vt} %b'}},i32 %offset,i64 %j,ptr %out) {store i8 17,ptr %out\n ${if loaded {'%a = load ${vt},ptr %src,align 1\n %bp = getelementptr i8,ptr %src,i64 128\n %b = load ${vt},ptr %bp,align 1\n'}else{''}}%r = call ${vt} @${name(c)}(${vt} %a,${vt} %b,i32 %offset)\n %v = extractelement ${vt} %r,i64 %j\n %raw = ${if element<64 {'or i${width} %v,0'}else{'bitcast ${t} %v to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n %p = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %p,align 1\n ret void }\n')
 }}}}
 for right in [false,true] {for freeze in [false,true] {for address in [false,true] {
  c:=Case{element:31,count:3,right:right}
  s.write_string('define void @state_${right}_${freeze}_${address}(i32 %offset,i64 %j,ptr %out) {store i8 17,ptr %out\n %r = call <3 x i32> @${name(c)}(<3 x i32> <i32 5,i32 poison,i32 undef>,<3 x i32> <i32 undef,i32 7,i32 poison>,i32 %offset)\n ${if freeze {'%f = freeze <3 x i32> %r\n'}else{''}}%v = extractelement <3 x i32> %${if freeze {'f'}else{'r'}},i64 %j\n ${if address {'%idx = and i32 %v,63\n %wide = zext i32 %idx to i64\n %p = getelementptr i8,ptr %out,i64 %wide\n store i8 42,ptr %p\n'}else{'%p = getelementptr i8,ptr %out,i64 8\n store i32 %v,ptr %p,align 1\n'}}ret void }\n')
 }}}
 for state in ['poison','undef'] {for frozen in [false,true] {
  s.write_string('define i32 @offset_${state}_${frozen}() {%offset = freeze i32 ${state}\n %v = call <3 x i32> @llvm.vector.splice.left.v3i32(<3 x i32> <i32 1,i32 2,i32 3>,<3 x i32> zeroinitializer,i32 ${if frozen {'%offset'}else{state}})\n %r = extractelement <3 x i32> %v,i32 0\n ret i32 %r }\n')
 }}
 for state in ['poison','undef'] {s.write_string('define void @discard_${state}() {%r = call <3 x i32> @llvm.vector.splice.left.v3i32(<3 x i32> ${state},<3 x i32> ${state},i32 1)\n ret void }\n')}
 s.write_string('declare <3 x i32> @alias(<3 x i32>,<3 x i32>,i32)\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <3 x i32> @llvm.vector.splice.left.v3i32(<3 x i32> zeroinitializer,<3 x i32> zeroinitializer,i32 1)\n %b = call <3 x i32> @alias(<3 x i32> zeroinitializer,<3 x i32> zeroinitializer,i32 1)\n ret void }\n')
 for amount in 1..17 {
  s.write_string('define void @depth_${amount}(<3 x i32> %a,i32 %offset,i64 %j,ptr %out) {store i8 17,ptr %out\n')
  for i in 0..amount {s.write_string('%r${i} = call <3 x i32> @llvm.vector.splice.left.v3i32(<3 x i32> %${if i==0 {'a'}else{'r'+(i-1).str()}},<3 x i32> zeroinitializer,i32 %offset)\n')}
  s.write_string('%v = extractelement <3 x i32> %r${amount-1},i64 %j\n %p = getelementptr i8,ptr %out,i32 %v\n ret void }\n')
 }
 for amount in 230..258 {
  s.write_string('define void @nodes_${amount}(<3 x i32> %a,i32 %offset,i64 %j,ptr %out) {store i8 17,ptr %out\n %r = call <3 x i32> @llvm.vector.splice.left.v3i32(<3 x i32> %a,<3 x i32> %a,i32 %offset)\n')
  for i in 0..amount {s.write_string('%v${i} = extractelement <3 x i32> %r,i64 %j\n %p${i} = getelementptr i8,ptr %out,i32 %v${i}\n')};s.write_string('ret void }\n')
 }
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut addresses:=0;mut exact:=0;mut copies:=0;mut states:=0;mut graph:=0
 for width in 1..65 {for count in 1..17 {for right in [false,true] {
  f:=fi(ir,'addr_${width}_${count}_${right}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  pointer:=C.LLVMGetFunctionAddress(native.engine,'case_addr_${width}_${count}_${right}'.str);assert pointer!=0
  mut words:=[]u64{len:32};mut a:=[]u64{len:count};mut b:=[]u64{len:count};mut offset:=[u64(0)];mut selector:=[u64(0)];mut native_args:=[u64(0),0];mut bytes:=[]u8{len:96,init:0xcc};mut reference:=bytes.clone()
  mut bs:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{values:b},airbitcode.IRMemoryBinding{values:offset},airbitcode.IRMemoryBinding{values:selector},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
  for amount in 0..count+3 {for j in 0..count+2 {
   for lane in 0..count {a[lane]=((u64(lane+amount*7)*u64(0x9e3779b97f4a7c15))&mask(width))|~mask(width);b[lane]=~a[lane];words[lane]=a[lane];words[16+lane]=b[lane]}
   offset[0]=if amount==count+2 {u64(0xffffffff)}else{u64(amount)};selector[0]=if j==count+1 {~u64(0)}else{u64(j)};native_args[0]=offset[0];native_args[1]=selector[0]
   valid:=amount<=count&&j<count;selected:=(if right {count-amount}else{amount})+j;index:=if valid {int((if selected<count {a[selected]}else{b[selected%count]})&mask(width)&63)}else{0}
   for prepared in [false,true] {
    for i in 0..bytes.len {bytes[i]=0xcc;reference[i]=0xcc}
    if _:=plan.validate(bs,plan.steps()) {assert valid}else{assert !valid};unchanged(bytes)
    if prepared {if _:=plan.run(mut bs,plan.steps()) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert valid}else{assert !valid}}
    for i,bv in bytes {assert bv==if !valid {u8(0xcc)}else if i==3+index {u8(42)}else if i==3 {u8(17)}else{u8(0xcc)}};addresses++
   }
   if valid {unsafe{NativeCast(voidptr(pointer))(words.data,native_args.data,&reference[3])};assert bytes==reference;exact++}
  }}
  plan.free();unsafe{words.free();a.free();b.free();offset.free();selector.free();native_args.free();bytes.free();reference.free();bs.free()}
 }}}
 for element in 0..66 {for count in [1,3,16] {for right in [false,true] {for loaded in [false,true] {
  width:=bits(element);if loaded&&element<64&&width%8!=0 {continue}
  f:=fi(ir,'copy_${element}_${count}_${right}_${loaded}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  mut input:=[]u8{len:260};mut a:=[]u64{len:count};mut b:=[]u64{len:count};mut offset:=[u64(0)];mut selector:=[u64(0)];mut output:=[]u8{len:32,init:0xcc}
  for lane in 0..count {a[lane]=lane_word(element,lane)|~mask(width);b[lane]=lane_word(element,(lane+7)%16)|~mask(width);for j in 0..(width+7)/8 {input[1+lane*((width+7)/8)+j]=u8(a[lane]>>u32(j*8));input[129+lane*((width+7)/8)+j]=u8(b[lane]>>u32(j*8))}}
  mut bindings:=[]airbitcode.IRMemoryBinding{}
  if loaded {bindings<<airbitcode.IRMemoryBinding{data:input,offset:1}}else{bindings<<airbitcode.IRMemoryBinding{values:a};bindings<<airbitcode.IRMemoryBinding{values:b}}
  bindings<<airbitcode.IRMemoryBinding{values:offset};bindings<<airbitcode.IRMemoryBinding{values:selector};bindings<<airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}
  for amount in [0,count/2,count] {for lane in 0..count {offset[0]=u64(amount);selector[0]=u64(lane);selected:=(if right {count-amount}else{amount})+lane;expected:=(if selected<count {a[selected]}else{b[selected%count]})&mask(width)
   for prepared in [false,true] {for i in 0..output.len {output[i]=0xcc};plan.validate(bindings,plan.steps())!;unchanged(output);if prepared {plan.run(mut bindings,plan.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,plan.steps())!};for i,bv in output {assert bv==if i==3 {u8(17)}else if i>=11&&i<19 {u8(expected>>u32((i-11)*8))}else{u8(0xcc)}};copies++}
  }};plan.free();unsafe{input.free();a.free();b.free();offset.free();selector.free();output.free();bindings.free()}
 }}}}
 for right in [false,true] {for freeze in [false,true] {for address in [false,true] {
  f:=fi(ir,'state_${right}_${freeze}_${address}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  for amount in 0..6 {for lane in 0..5 {
   selected:=(if right {3-amount}else{amount})+lane;in_range:=amount<=3&&lane<3;defined:=in_range&&selected in [0,4];valid:=in_range&&(defined||freeze);value:=if defined {if selected==0 {u64(5)}else{u64(7)}}else{u64(0)}
   for prepared in [false,true] {mut output:=[]u8{len:96,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:[u64(amount)]},airbitcode.IRMemoryBinding{values:[u64(lane)]},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
    // A result freeze repairs an invalid offset, but cannot repair extraction
    // with an invalid selector. Its value choice here is zero.
    repaired:=valid||(freeze&&lane<3&&amount>3)
    if _:=plan.validate(bs,plan.steps()) {assert !address||repaired}else{assert address&&!repaired};unchanged(output)
    if prepared {if _:=plan.run(mut bs,plan.steps()) {assert repaired}else{assert !repaired}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert repaired}else{assert !repaired}}
    for i,bv in output {assert bv==if address&&!repaired {u8(0xcc)}else if address&&i==3+int(value) {u8(42)}else if i==3 {u8(17)}else if !address&&repaired&&i>=11&&i<15 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}};states++;unsafe{output.free();bs[0].values.free();bs[1].values.free();bs.free()}
   }
  }};plan.free()
 }}}
 for state in ['poison','undef'] {for frozen in [false,true] {f:=fi(ir,'offset_${state}_${frozen}');if state=='undef'&&!frozen {if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4) {panic('undef scalar offset')}}else{v:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4)!;assert v.poison==(!frozen)&&(!frozen||v.value==1)};states++}}
 for state in ['poison','undef'] {assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard_${state}'),[],2)!.steps==2;states++}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.vector.splice.left.v3i32'}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10) {panic('duplicate splice')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration',err.msg()};unchanged(output);states++
 mut max_depth:=0;mut refused_depth:=false
 for amount in 1..17 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'depth_${amount}')) {assert !refused_depth;max_depth=amount;plan.free()}else{refused_depth=true};graph++};assert max_depth>0&&max_depth<16
 mut max_shared:=0;mut refused_nodes:=false
 for amount in 230..258 {if profile:=p.memory_function_profile(ir,stream,pools,bodies,fi(ir,'nodes_${amount}')) {assert !refused_nodes;max_shared=amount;profile.free()}else{refused_nodes=true};graph++};assert max_shared>=230&&max_shared<257
 for storage in [false,true] {for over in [false,true] {limits(assembler,root+'/limit-${storage}-${over}',storage,over)!;graph+=2}}
 unsafe{output.free();bs.free()}
 line:='AIR-VECTOR-SPLICE-CONTROLS: ${addresses} address API checks, ${exact} native address values, ${copies} typed/loaded lane copies, ${states} state/discard/duplicate controls, ${graph} graph/resource checks (max splice chain ${max_depth}, ${max_shared} shared extractions) PASS\n'
 os.write_file(root+'/result.txt',line)!;print(line)
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s:=strings.new_builder(10485760);count:=if storage {1}else{16}
 s.write_string('declare <${count} x half> @llvm.vector.splice.left.v${count}f16(<${count} x half>,<${count} x half>,i32)\n')
 for name in ['memory','scalar'] {
  s.write_string('define void @${name}(${if name=='memory' {'ptr %out'}else{''}}) {\n');if name=='memory' {s.write_string('store i8 17,ptr %out,align 1\n')}
  for i in 0..if storage&&over {4097}else{4096} {s.write_string('%v${i} = call <${count} x half> @llvm.vector.splice.left.v${count}f16(<${count} x half> zeroinitializer,<${count} x half> zeroinitializer,i32 0)\n')}
  if !storage {for i in 0..if over {50213}else{50212} {s.write_string('%x${i} = extractelement <16 x half> %v4095,i32 0\n')}};s.write_string('ret void }\n')
 }
 data:=assemble(assembler_path,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('memory splice limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('scalar splice limit')}else{assert err.msg()==diagnostic,err.msg()}}else{assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098}else{54310};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!.steps==if storage {4097}else{54309}}
 unsafe{output.free();bs.free()}
}
// LLVM's AArch64 backend cannot lower every legal splice shape. Keep the AIR
// input intact and expand only the independent native reference into scalar
// index arithmetic, extracts, selects and inserts. No interpreter helper is used.
fn native_source(source string) string {
 mut result:=strings.new_builder(source.len*2)
 for line in source.split_into_lines() {
  if line.starts_with('declare ')&&line.contains('@llvm.vector.splice.') {
   end:=line.index('>') or {panic('vector type')};vt:=line[8..end+1];parts:=vt[1..vt.len-1].split(' x ');count:=parts[0].int();t:=parts[1]
   at:=line.index('@') or {panic('name')};paren:=line.index('(') or {panic('signature')};callee:=line[at+1..paren];right:=callee.contains('.right.')
   result.write_string('define ${vt} @${callee}(${vt} %a,${vt} %b,i32 %offset) alwaysinline {\n %start = ${if right {'sub i32 ${count},%offset'}else{'add i32 %offset,0'}}\n')
   for lane in 0..count {
    result.write_string('%index${lane} = add i32 %start,${lane}\n %local${lane} = urem i32 %index${lane},${count}\n %choose${lane} = icmp ult i32 %index${lane},${count}\n %a${lane} = extractelement ${vt} %a,i32 %local${lane}\n %b${lane} = extractelement ${vt} %b,i32 %local${lane}\n %chosen${lane} = select i1 %choose${lane},${t} %a${lane},${t} %b${lane}\n %v${lane} = insertelement ${vt} ${if lane==0 {'poison'}else{'%v'+(lane-1).str()}},${t} %chosen${lane},i32 ${lane}\n')
   }
   result.write_string('%valid = icmp ule i32 %offset,${count}\n %result = select i1 %valid,${vt} %v${count-1},${vt} poison\n ret ${vt} %result }\n')
  }else{result.write_string(line+'\n')}
 }
 return result.str().replace('@llvm.vector.splice.left.','@reference_splice_left_').replace('@llvm.vector.splice.right.','@reference_splice_right_')
}
fn loop_controls(assembler string,root string) ! {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 for element in [0,6,63,64,65] {for count in [1,3,16] {
  t:=typ(element);width:=bits(element);vt:='<${count} x ${t}>';c:=Case{'',element,count,0,0,false};name:='llvm.vector.splice.left.v${count}${suffix(element)}'
  s.write_string('declare ${vt} @${name}(${vt},${vt},i32)\n')
  ops:='%start = insertelement ${vt} ${vector(c,false)},${t} %x,i32 0\n %seed = insertelement ${vt} %start,${t} %y,i32 ${count-1}\n br label %body\n body: %v = phi ${vt} [%seed,%entry],[%r,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %r = call ${vt} @${name}(${vt} %v,${vt} %v,i32 1)\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %chosen = extractelement ${vt} %r,i32 0\n %raw = ${if element<64 {'or i${width} %chosen,0'}else{'bitcast ${t} %chosen to i${width}'}}\n %wide = ${if width==64 {'or i64 %raw,0'}else{'zext i${width} %raw to i64'}}\n'
  s.write_string('define i64 @loop_${element}_${count}(${t} %x,${t} %y,i64 %limit) {entry: ${ops}ret i64 %wide }\n')
  s.write_string('define void @case_loop_${element}_${count}(ptr %src,ptr %counter,ptr %out) {entry: %x = load ${t},ptr %src,align 1\n %yp = getelementptr i8,ptr %src,i64 8\n %y = load ${t},ptr %yp,align 1\n %limit = load i64,ptr %counter,align 1\n ${ops}store i64 %wide,ptr %out,align 1\n ret void }\n')
 }}
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut exact:=0;mut apis:=0;mut budgets:=0
 for element in [0,6,63,64,65] {for count in [1,3,16] {
  width:=bits(element);x:=lane_word(element,4);y:=lane_word(element,13);mut input:=[16]u8{}
  for b in 0..8 {input[b]=u8(x>>u32(b*8));input[8+b]=u8(y>>u32(b*8))}
  f:=fi(ir,'loop_${element}_${count}');address:=C.LLVMGetFunctionAddress(native.engine,'case_loop_${element}_${count}'.str);assert address!=0
  for visits in [u64(1),2,3,7,16,257,513,1024]! {
   selected:=int(visits%u64(count));expected:=if count==1||selected==count-1 {y}else if selected==0 {x}else{lane_word(element,selected)};mut reference:=u64(0)
   unsafe{NativeCast(voidptr(address))(&input[0],&visits,&reference)};assert reference==expected;exact++
   args:=[x|~mask(width),y|~mask(width),visits];v:=p.run_scalar_function(ir,stream,pools,bodies,f,args,int(visits*6+7))!;assert !v.poison&&v.value==expected&&v.steps==int(visits*6+7);apis++
   if element<64 {r:=p.run_integer_function(ir,stream,pools,bodies,f,args,int(visits*6+7))!;assert !r.poison&&r.value==expected;apis++}
   if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,int(visits*6+6)) {panic('splice loop short budget')};budgets++;unsafe{args.free()}
  }
 }}
 assert exact==120&&apis==192&&budgets==120
 os.write_file(root+'/result.txt','AIR-VECTOR-SPLICE-LOOPS: ${exact} native raw vector-PHI loop results, ${apis} scalar/integer checks, ${budgets} executed-budget refusals, i1/i7/i64/half/float and counts 1/3/16, cyclic iterations and signaling NaN payloads PASS\n')!
}
