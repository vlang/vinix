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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(reference_data.data, usize(reference_data.len), c'vector-step'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 options_ref := C.LLVMCreatePassBuilderOptions(); assert C.LLVMRunPasses(module_ptr, c'always-inline', unsafe { nil }, options_ref) == unsafe { nil }; C.LLVMDisposePassBuilderOptions(options_ref)
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn native_source(source string) string {
 mut result:=strings.new_builder(source.len*2)
 for line in source.split_into_lines() {
  if line.starts_with('declare ')&&line.contains('@llvm.stepvector.') {
   end:=line.index('>') or {panic('type')};vt:=line[8..end+1];parts:=vt[1..vt.len-1].split(' x ');count:=parts[0].int();t:=parts[1];at:=line.index('@') or {panic('name')};paren:=line.index('(') or {panic('signature')};name:=line[at+1..paren]
   lanes:=[]string{len:count,init:t+' '+index.str()};result.write_string('define ${vt} @${name}() alwaysinline {ret ${vt} <${lanes.join(',')}>}\n')
  }else{result.write_string(line+'\n')}
 }
 return result.str().replace('@llvm.stepvector.','@reference_stepvector_')
}
fn outcome(count int,mode int,j u64,r u64,x u64) (int,u64) {
 if r>=u64(count) {return 1,0}
 if mode==2 {if j>=u64(count) {return 1,0};if j==r {return 0,x}}
 if mode==3&&j!=0 {return 1,0};if mode==4&&j!=0 {return 3,0}
 return 0,if mode==5 {u64(count-1)-r}else{r}
}
fn batch(assembler string,out string,width int) ! {
 mut s:=strings.new_builder(2097152);s.write_string('target datalayout = "e-p:64:64"\n')
 for n in 1..17 {vt:='<${n} x i${width}>';s.write_string('declare ${vt} @llvm.stepvector.v${n}i${width}()\n declare ${vt} @llvm.vector.reverse.v${n}i${width}(${vt})\n')
  for mode in 0..6 {
   chosen:=['s','f','over','sp','su','rev'][mode]
   ops:='%s = call ${vt} @llvm.stepvector.v${n}i${width}()\n %f = freeze ${vt} %s\n %over = insertelement ${vt} %s,i${width} %x,i64 %j\n %choose = icmp eq i64 %j,0\n %sp = select i1 %choose,${vt} %s,${vt} poison\n %su = select i1 %choose,${vt} %s,${vt} undef\n %rev = call ${vt} @llvm.vector.reverse.v${n}i${width}(${vt} %s)\n %v = extractelement ${vt} %${chosen},i64 %r\n %wide = ${if width==64 {'or i64 %v,0'}else{'zext i${width} %v to i64'}}\n'
   s.write_string('define i64 @scalar_${n}_${mode}(i64 %j,i64 %r,i${width} %x) {${ops}ret i64 %wide }\n')
   s.write_string('define void @case_${n}_${mode}(ptr %indices,ptr %src,ptr %out) {%j = load i64,ptr %indices,align 1\n %rp = getelementptr i8,ptr %indices,i64 8\n %r = load i64,ptr %rp,align 1\n %x = load i${width},ptr %src,align 1\n store i8 17,ptr %out\n ${ops}%d = getelementptr i8,ptr %out,i64 8\n store i64 %wide,ptr %d,align 1\n ret void }\n')
  }
  for sb in [1,32,64] {for mode in 0..4 {
   chosen:=['s','f','rev','su'][mode]
   ops:='store i8 17,ptr %out\n %s = call ${vt} @llvm.stepvector.v${n}i${width}()\n %f = freeze ${vt} %s\n %rev = call ${vt} @llvm.vector.reverse.v${n}i${width}(${vt} %s)\n %choose = icmp eq i64 %j,0\n %su = select i1 %choose,${vt} %s,${vt} undef\n %v = extractelement ${vt} %${chosen},i${sb} %r\n %index = ${if width==64 {'or i64 %v,0'}else{'zext i${width} %v to i64'}}\n %p = getelementptr i8,ptr %out,i64 %index\n store i8 42,ptr %p\n ret void }\n'
   s.write_string('define void @address_${n}_${sb}_${mode}(i64 %j,i${sb} %r,ptr %out) {${ops}')
   s.write_string('define void @case_address_${n}_${sb}_${mode}(ptr %indices,ptr %unused,ptr %out) {%j = load i64,ptr %indices,align 1\n %rp = getelementptr i8,ptr %indices,i64 8\n %rawindex = load i64,ptr %rp,align 1\n %r = ${if sb==64 {'or i64 %rawindex,0'}else{'trunc i64 %rawindex to i${sb}'}}\n ${ops}')
  }}
 }
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out,ir)!;defer{native.close()}
 mut exact:=0;mut poison:=0;mut undef:=0;mut apis:=0;mut budgets:=0;mut metadata:=0;mut addresses:=0;mut address_native:=0
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('n\tmode\tj\tr\tx\tstate\tvalue')!
 for n in 1..17 {for mode in 0..6 {
  f:=fi(ir,'case_${n}_${mode}');sf:=fi(ir,'scalar_${n}_${mode}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;assert plan.steps()==17
  pointer:=C.LLVMGetFunctionAddress(native.engine,'case_${n}_${mode}'.str);assert pointer!=0
  mut indices:=[]u8{len:24};mut input:=[]u8{len:16};mut output:=[]u8{len:32,init:0xcc};mut reference:=output.clone();mut bindings:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for sample in 0..n+2 {
   edges:=[u64(0),u64(n-1),u64(n),~u64(0),1,2,3,u64(n+1)]!;j:=edges[(sample*3)%8];r:=if sample==n+1 {~u64(0)}else{u64(sample)};x:=(u64(sample)*u64(0x9e3779b97f4a7c15))&mask(width);state,value:=outcome(n,mode,j,r,x)
   for i in 0..8 {indices[1+i]=u8(j>>u32(i*8));indices[9+i]=u8(r>>u32(i*8));input[1+i]=u8(x>>u32(i*8))};args:=[j,r,x|~mask(width)]
   if state==3 {if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,10) {panic('undef scalar')}else{assert err.msg().contains('undef'),err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,10) {panic('undef integer')}}else{a:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,10)!;b:=p.run_integer_function(ir,stream,pools,bodies,sf,args,10)!;assert a.poison==(state==1)&&b.poison==a.poison&&a.steps==10&&b.steps==10&&(a.poison||(a.value==value&&b.value==value))};apis+=2
   for prepared in [false,true] {
    for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc};plan.validate(bindings,17)!;unchanged(output)
    if prepared {if _:=plan.run(mut bindings,17) {assert state==0}else{assert state in [1,3]&&err.msg().contains(if state==3 {'undef'}else{'poison store'}),err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,17) {assert state==0}else{assert state in [1,3]&&err.msg().contains(if state==3 {'undef'}else{'poison store'}),err.msg()}}
    for i,b in output {assert b==if i==3 {u8(17)}else if state==0&&i>=11&&i<19 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}}
   }
   if state==0 {unsafe{NativeCast(voidptr(pointer))(&indices[1],&input[1],&reference[3])};assert output==reference;exact++}else if state==1 {poison++}else{undef++};rows.writeln('${n}\t${mode}\t${j}\t${r}\t${x}\t${state}\t${value}')!;unsafe{args.free()}
  }
  for i in 0..output.len {output[i]=0xcc};if _:=plan.run(mut bindings,16) {panic('short prepared')};unchanged(output);if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,16) {panic('short direct')};unchanged(output);budgets+=2
  if mode==0 {scope:=bodies.scopes[f+1];for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34 {continue}
   if ir.functions[op.callee_function].name.starts_with('llvm.stepvector.') {
    for change in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:0},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,result_type:-1}] {p.instructions[index]=change;if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,17) {panic('zero-arity metadata')};unchanged(output);metadata++}
   }else{p.instructions[index]=airbitcode.IRTypedInstruction{...op,operands_count:1};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,17) {panic('nonzero-arity missing source')};unchanged(output);metadata++};p.instructions[index]=op
  }}
  plan.free();unsafe{indices.free();input.free();output.free();reference.free();bindings.free()}
 }}
 for n in 1..17 {for sb in [1,32,64] {for mode in 0..4 {
  f:=fi(ir,'address_${n}_${sb}_${mode}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;pointer:=C.LLVMGetFunctionAddress(native.engine,'case_address_${n}_${sb}_${mode}'.str);assert pointer!=0
  mut j:=[u64(0)];mut selector:=[u64(0)];mut indices:=[u64(0),0];mut output:=[]u8{len:64,init:0xcc};mut reference:=output.clone();mut bs:=[airbitcode.IRMemoryBinding{values:j},airbitcode.IRMemoryBinding{values:selector},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
  for choose in [u64(0),1]! {for sample in 0..n+2 {j[0]=choose;selector[0]=if sample==n+1 {~u64(0)}else{u64(sample)};r:=selector[0]&mask(sb);indices[0]=choose;indices[1]=selector[0];valid:=r<u64(n)&&!(mode==3&&choose!=0);value:=if valid {if mode==2 {u64(n-1)-r}else{r}}else{u64(0)}
   for prepared in [false,true] {for i in 0..output.len {output[i]=0xcc;reference[i]=0xcc};if _:=plan.validate(bs,plan.steps()) {assert valid}else{assert !valid};unchanged(output)
    if prepared {if _:=plan.run(mut bs,plan.steps()) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert valid}else{assert !valid}}
    for i,b in output {assert b==if !valid {u8(0xcc)}else if i==3+int(value) {u8(42)}else if i==3 {u8(17)}else{u8(0xcc)}};addresses++
   }
   if valid {unsafe{NativeCast(voidptr(pointer))(&indices[0],unsafe{nil},&reference[3])};assert output==reference,'width=${width} n=${n} sb=${sb} mode=${mode} choose=${choose} sample=${sample} r=${r}';address_native++}
  }}
  plan.free();unsafe{j.free();selector.free();indices.free();output.free();reference.free();bs.free()}
 }}}
 assert exact+poison+undef==1008&&apis==2016&&budgets==192&&metadata==160&&addresses==8064&&address_native==3066
 line:='AIR-STEPVECTOR-BATCH: ${width}, ${exact} native values, ${poison} poison, ${undef} selected undef, ${apis} scalar/integer checks, ${addresses} address API checks, ${address_native} native addresses, ${budgets} budgets, ${metadata} metadata/arity refusals PASS\n';os.write_file(out+'/result.txt',line)!;print(line)
}
fn main() {
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 if os.args.len==4 {batch(os.args[1],root+'/w8',8)!;return}
 mut result:='';for width in 8..65 {batch(os.args[1],root+'/w${width}',width)!;result+=os.read_file(root+'/w${width}/result.txt')!};controls(os.args[1],root+'/controls')!;result+=os.read_file(root+'/controls/result.txt')!;os.write_file(root+'/result.txt',result)!;print(result)
}
fn controls(assembler string,root string) ! {
 mut s:=strings.new_builder(1048576);s.write_string('target datalayout = "e-p:64:64"\n declare <3 x i32> @llvm.stepvector.v3i32()\n')
 for state in ['poison','undef'] {for freeze in [false,true] {s.write_string('define i32 @index_${state}_${freeze}() {%i = freeze i64 ${state}\n %s = call <3 x i32> @llvm.stepvector.v3i32()\n %v = extractelement <3 x i32> %s,i64 ${if freeze {'%i'}else{state}}\n ret i32 %v }\n')}}
 s.write_string('define void @discard() {%s = call <3 x i32> @llvm.stepvector.v3i32()\n ret void }\n declare <3 x i32> @alias()\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <3 x i32> @llvm.stepvector.v3i32()\n %b = call <3 x i32> @alias()\n ret void }\n')
 for amount in 0..36 {s.write_string('define void @depth_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %s = call <3 x i32> @llvm.stepvector.v3i32()\n');for i in 0..amount {s.write_string('%f${i} = freeze <3 x i32> %${if i==0 {'s'}else{'f'+(i-1).str()}}\n')};s.write_string('%v = extractelement <3 x i32> %${if amount==0 {'s'}else{'f'+(amount-1).str()}},i64 %r\n %p = getelementptr i8,ptr %out,i32 %v\n ret void }\n')}
 for amount in 240..258 {s.write_string('define void @nodes_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %s = call <3 x i32> @llvm.stepvector.v3i32()\n');for i in 0..amount {s.write_string('%v${i} = extractelement <3 x i32> %s,i64 %r\n %p${i} = getelementptr i8,ptr %out,i32 %v${i}\n')};s.write_string('ret void }\n')}
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut states:=0
 for state in ['poison','undef'] {for freeze in [false,true] {f:=fi(ir,'index_${state}_${freeze}');for integer in [false,true] {
  if state=='undef'&&!freeze {if integer {if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],4) {panic('undef index')}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4) {panic('undef index')}}}else{if integer {v:=p.run_integer_function(ir,stream,pools,bodies,f,[],4)!;assert v.poison==!freeze&&(v.poison||v.value==0)}else{v:=p.run_scalar_function(ir,stream,pools,bodies,f,[],4)!;assert v.poison==!freeze&&(v.poison||v.value==0)}};states++
 }}}
 assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard'),[],2)!.steps==2;states++
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.stepvector.v3i32'}
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10) {panic('duplicate stepvector')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration',err.msg()};unchanged(output);states++
 mut max_depth:=0;mut refused:=false;mut graph:=0
 for amount in 0..36 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'depth_${amount}')) {assert !refused;max_depth=amount;plan.free()}else{refused=true};graph++};assert max_depth>0&&max_depth<35
 mut max_shared:=0;mut refused_nodes:=false
 for amount in 240..258 {if profile:=p.memory_function_profile(ir,stream,pools,bodies,fi(ir,'nodes_${amount}')) {assert !refused_nodes;max_shared=amount;profile.free()}else{refused_nodes=true};graph++};assert max_shared>=240&&max_shared<257
 for storage in [false,true] {for over in [false,true] {limits(assembler,root+'/limit-${storage}-${over}',storage,over)!;graph+=2}}
 assert states==10&&graph==62;unsafe{output.free();bs.free()}
 loop_controls(assembler,root+'/loops')!
 line:='AIR-STEPVECTOR-CONTROLS: ${states} state/discard/duplicate checks, ${graph} graph/resource checks (max freezes ${max_depth}, ${max_shared} shared extractions) PASS\n';os.write_file(root+'/result.txt',line+os.read_file(root+'/loops/result.txt')!)!;print(line)
}
fn limits(assembler string,root string,storage bool,over bool) ! {
 n:=if storage {1}else{16};mut s:=strings.new_builder(10485760);s.write_string('declare <${n} x i8> @llvm.stepvector.v${n}i8()\n')
 for name in ['memory','scalar'] {s.write_string('define void @${name}(${if name=='memory' {'ptr %out'}else{''}}) {\n');if name=='memory' {s.write_string('store i8 17,ptr %out\n')};for i in 0..if storage&&over {4097}else{4096} {s.write_string('%s${i} = call <${n} x i8> @llvm.stepvector.v${n}i8()\n')};if !storage {for i in 0..if over {58405}else{58404} {s.write_string('%v${i} = extractelement <16 x i8> %s4095,i32 0\n')}};s.write_string('ret void }\n')}
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('memory step limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('void step limit')}else{assert err.msg()==diagnostic,err.msg()}}else{assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098}else{62502};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!.steps==if storage {4097}else{62501}}
 unsafe{output.free();bs.free()}
}
fn loop_controls(assembler string,root string) ! {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 for width in [8,9,32,64] {for n in [1,3,16] {vt:='<${n} x i${width}>';s.write_string('declare ${vt} @llvm.stepvector.v${n}i${width}()\n')
  ops:='br label %body\n body: %v = phi ${vt} [zeroinitializer,%entry],[%over,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %s = call ${vt} @llvm.stepvector.v${n}i${width}()\n %old = extractelement ${vt} %v,i32 0\n %sum = add i${width} %old,%x\n %over = insertelement ${vt} %s,i${width} %sum,i32 0\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %chosen = extractelement ${vt} %over,i64 %r\n %wide = ${if width==64 {'or i64 %chosen,0'}else{'zext i${width} %chosen to i64'}}\n'
  s.write_string('define i64 @loop_${width}_${n}(i${width} %x,i64 %limit,i64 %r) {entry: ${ops}ret i64 %wide }\n define void @case_loop_${width}_${n}(ptr %src,ptr %counter,ptr %out) {entry: %x = load i${width},ptr %src,align 1\n %limit = load i64,ptr %counter,align 1\n %rp = getelementptr i8,ptr %counter,i64 8\n %r = load i64,ptr %rp,align 1\n ${ops}store i64 %wide,ptr %out,align 1\n ret void }\n')
 }}
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,root,ir)!;defer{native.close()}
 mut exact:=0;mut apis:=0;mut budgets:=0
 for width in [8,9,32,64] {for n in [1,3,16] {f:=fi(ir,'loop_${width}_${n}');address:=C.LLVMGetFunctionAddress(native.engine,'case_loop_${width}_${n}'.str);assert address!=0
  for visits in [u64(1),2,3,7,16,257,513,1024]! {for r in [u64(0),u64(n-1)]! {x:=u64(0x9e3779b97f4a7c15)&mask(width);value:=if r==0 {(x*visits)&mask(width)}else{r};mut counters:=[visits,r];mut reference:=u64(0);unsafe{NativeCast(voidptr(address))(&x,&counters[0],&reference)};assert reference==value;exact++
   args:=[x|~mask(width),visits,r];steps:=int(visits*9+4);a:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,args,steps)!;assert !a.poison&&!b.poison&&a.value==value&&b.value==value&&a.steps==steps&&b.steps==steps;apis+=2;if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps-1) {panic('loop budget')};budgets++;unsafe{args.free();counters.free()}
  }}
 }}
 assert exact==192&&apis==384&&budgets==192;line:='AIR-STEPVECTOR-LOOPS: ${exact} native vector-PHI results, ${apis} scalar/integer checks, ${budgets} executed-budget refusals, fresh lane sequences after insertions and 1 through 1024 visits PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
