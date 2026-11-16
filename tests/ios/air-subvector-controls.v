// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings

fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name {return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn assemble(assembler string,root string,source string) ![]u8 {
 assert !os.exists(root);os.mkdir_all(root)!;os.write_file(root+'/input.ll',source)!
 r:=os.exec([assembler,root+'/input.ll','-o',root+'/input.bc']);os.write_file(root+'/assemble.log',r.output)!;assert r.exit_code==0,r.output;return os.read_bytes(root+'/input.bc')!
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 mut s:=strings.new_builder(1048576);s.write_string('target datalayout = "e-p:64:64"\n declare <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8>,i64 immarg)\n declare <2 x i8> @alias(<4 x i8>,i64)\n')
 for selected in [false,true] {for frozen in [false,true] {
  value:=if selected {'<i8 7,i8 9,i8 poison,i8 undef>'}else{'<i8 poison,i8 undef,i8 7,i8 9>'}
  s.write_string('define i8 @state_${selected}_${frozen}(i64 %r) {%v = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> ${value},i64 2)\n %f = freeze <2 x i8> %v\n %e = extractelement <2 x i8> %${if frozen {'f'}else{'v'}},i64 %r\n ret i8 %e }\n')
 }}
 s.write_string('define void @discard() {%v = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> undef,i64 2)\n ret void }\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> zeroinitializer,i64 0)\n %b = call <2 x i8> @alias(<4 x i8> zeroinitializer,i64 2)\n ret void }\n')
 s.write_string('define void @cached(i64 %offset,ptr %out) {store i8 17,ptr %out\n %one = add i64 1,4\n %negative = freeze i64 -1\n %poison = freeze i64 poison\n %undef = freeze i64 undef\n %a = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> zeroinitializer,i64 0)\n %b = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> zeroinitializer,i64 2)\n ret void }\n')
 for amount in 0..36 {s.write_string('define void @depth_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %v = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> zeroinitializer,i64 2)\n');for i in 0..amount {s.write_string('%f${i} = freeze <2 x i8> %${if i==0 {'v'}else{'f'+(i-1).str()}}\n')};s.write_string('%e = extractelement <2 x i8> %${if amount==0 {'v'}else{'f'+(amount-1).str()}},i64 %r\n %w = zext i8 %e to i64\n %p = getelementptr i8,ptr %out,i64 %w\n ret void }\n')}
 for amount in 90..141 {s.write_string('define void @nodes_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %v = call <2 x i8> @llvm.vector.extract.v2i8.v4i8(<4 x i8> zeroinitializer,i64 2)\n');for i in 0..amount {s.write_string('%e${i} = extractelement <2 x i8> %v,i64 %r\n %w${i} = zext i8 %e${i} to i64\n %p${i} = getelementptr i8,ptr %out,i64 %w${i}\n')};s.write_string('ret void }\n')}
 data:=assemble(os.args[1],root+'/basic',s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut checks:=0
 for selected in [false,true] {for frozen in [false,true] {for r in [u64(0),1,2,~u64(0)]! {for integer in [false,true] {
  f:=fi(ir,'state_${selected}_${frozen}');args:=[r];undef:=selected&&!frozen&&r==1;poison:=r>=2||(selected&&!frozen&&r==0);value:=if selected {u64(0)}else if r==0 {u64(7)}else{u64(9)}
  if integer {if v:=p.run_integer_function(ir,stream,pools,bodies,f,args,4) {assert !undef&&v.poison==poison&&(poison||v.value==value)}else{assert undef}}else{if v:=p.run_scalar_function(ir,stream,pools,bodies,f,args,4) {assert !undef&&v.poison==poison&&(poison||v.value==value)}else{assert undef}};checks++;unsafe{args.free()}
 }}}}
 assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard'),[],2)!.steps==2;checks++
 mut output:=[u8(0xcc)];mut offset:=[u64(0)];mut bs:=[airbitcode.IRMemoryBinding{values:offset},airbitcode.IRMemoryBinding{data:output,writable:true}]
 cached:=fi(ir,'cached');scope:=bodies.scopes[cached+1];mut calls:=[]int{};mut invalid:=[]airbitcode.IRTypedOperand{}
 for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {
  op:=p.instructions[index];code:=stream.records[bodies.instructions[index].record].code
  if code==34 {calls<<index}else if code==2 {invalid<<p.operands[op.operands_start];invalid<<p.operands[op.operands_start+1]}else if code==58 {invalid<<p.operands[op.operands_start]}
 }
 assert calls.len==2&&invalid.len==5
 original:=p.operands[p.instructions[calls[1]].operands_start+2]
 invalid<<airbitcode.IRTypedOperand{...original,number:pools.module_values}
 assert pools.lookup(cached+1,pools.module_values)!.kind==.argument
 assert p.run_memory_function(ir,stream,pools,bodies,cached,mut bs,8)!.steps==8;assert output[0]==17
 for replacement in invalid {
  p.operands[p.instructions[calls[1]].operands_start+2]=replacement;output[0]=0xcc
  if _:=p.run_memory_function(ir,stream,pools,bodies,cached,mut bs,8) {panic('cached immediate accepted')}else{assert err.msg().contains('offset'),err.msg()};unchanged(output)
  if _:=p.prepare_memory_function(ir,stream,pools,bodies,cached) {panic('prepared cached immediate accepted')}else{assert err.msg().contains('offset'),err.msg()};checks+=2
 };p.operands[p.instructions[calls[1]].operands_start+2]=original
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.vector.extract.v2i8.v4i8'}
 output[0]=0xcc;mut one_binding:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut one_binding,10) {panic('duplicate overload')};unchanged(output);checks++
 declaration:=fi(ir,'llvm.vector.extract.v2i8.v4i8');saved:=functions[declaration]
 for name in ['llvm.vector.extract.v1i8.v4i8','llvm.vector.extract.v2i8.v3i8','llvm.vector.extract.v2i9.v4i9'] {functions[declaration]=airbitcode.IRFunction{...saved,name:name};if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'discard'),[],2) {panic('name/type mismatch')};checks++};functions[declaration]=saved
 mut depth_max:=0;mut depth_failed:=false
 for amount in 0..36 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'depth_${amount}')) {assert !depth_failed;depth_max=amount;plan.free()}else{depth_failed=true};checks++};assert depth_max>0&&depth_max<35
 mut nodes_max:=0;mut nodes_failed:=false
 for amount in 90..141 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'nodes_${amount}')) {assert !nodes_failed;nodes_max=amount;plan.free()}else{nodes_failed=true};checks++};assert nodes_max>=90&&nodes_max<140
 for storage in [false,true] {for over in [false,true] {limits(os.args[1],root+'/limit-${storage}-${over}',storage,over)!;checks+=2}}
 loop_checks(os.args[1],root+'/loops')!
 line:='AIR-SUBVECTOR-CONTROLS: ${checks} state/discard/cached-offset/name/duplicate/resource checks, max ${depth_max} freezes and ${nodes_max} shared extractions PASS\n';os.write_file(root+'/result.txt',line+os.read_file(root+'/loops/result.txt')!)!;print(line)
 unsafe{output.free();offset.free();bs.free();one_binding.free();calls.free();invalid.free()}
}
fn limits(assembler string,root string,storage bool,over bool) ! {
 n:=if storage {1}else{16};mut s:=strings.new_builder(10485760);s.write_string('declare <${n} x i8> @llvm.vector.extract.v${n}i8.v${n}i8(<${n} x i8>,i64 immarg)\n')
 for name in ['memory','scalar'] {s.write_string('define void @${name}(${if name=='memory' {'ptr %out'}else{''}}) {\n');if name=='memory' {s.write_string('store i8 17,ptr %out\n')};for i in 0..if storage&&over {4097}else{4096} {s.write_string('%s${i} = call <${n} x i8> @llvm.vector.extract.v${n}i8.v${n}i8(<${n} x i8> zeroinitializer,i64 0)\n')};if !storage {for i in 0..if over {54309}else{54308} {s.write_string('%e${i} = extractelement <16 x i8> %s4095,i32 0\n')}};s.write_string('ret void }\n')}
 data:=assemble(assembler,root,s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('memory resource limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('void resource limit')}else{assert err.msg()==diagnostic,err.msg()}}else{assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098}else{58406};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!.steps==if storage {4097}else{58405}}
 unsafe{output.free();bs.free()}
}
fn loop_checks(assembler string,root string) ! {
 mut s:=strings.new_builder(65536)
 for width in [1,8,9,32,64] {for shape in [[1,1,0]!,[3,1,2]!,[16,3,12]!,[16,16,0]!] {
  source_count:=shape[0];count:=shape[1];offset:=shape[2];st:='<${source_count} x i${width}>';ot:='<${count} x i${width}>';name:='llvm.vector.extract.v${count}i${width}.v${source_count}i${width}'
  s.write_string('declare ${ot} @${name}(${st},i64 immarg)\n define i64 @loop_${width}_${source_count}_${count}(i${width} %x,i64 %limit,i64 %r) {entry: br label %body\n body: %full = phi ${st} [zeroinitializer,%entry],[%insert,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %old = extractelement ${st} %full,i32 ${offset}\n %sum = add i${width} %old,%x\n %insert = insertelement ${st} %full,i${width} %sum,i32 ${offset}\n %part = call ${ot} @${name}(${st} %insert,i64 ${offset})\n %v = extractelement ${ot} %part,i64 %r\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %wide = ${if width==64 {'or i64 %v,0'}else{'zext i${width} %v to i64'}}\n ret i64 %wide }\n')
 }}
 data:=assemble(assembler,root,s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut checks:=0
 for width in [1,8,9,32,64] {for shape in [[1,1,0]!,[3,1,2]!,[16,3,12]!,[16,16,0]!] {for visits in [u64(1),2,3,7,16,257,1024]! {for lane in [u64(0),u64(shape[1]-1)]! {
  mask:=if width==64 {~u64(0)}else{(u64(1)<<u32(width))-1};x:=u64(0x9e3779b97f4a7c15)&mask;value:=if lane==0 {(x*visits)&mask}else{u64(0)};args:=[x|~mask,visits,lane];steps:=int(visits*10+3);f:=fi(ir,'loop_${width}_${shape[0]}_${shape[1]}')
  a:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,args,steps)!;assert !a.poison&&!b.poison&&a.value==value&&b.value==value&&a.steps==steps&&b.steps==steps;if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps-1) {panic('executed loop budget')};checks++;unsafe{args.free()}
 }}}}
 assert checks==280;line:='AIR-SUBVECTOR-LOOPS: 280 vector-PHI properties, 560 scalar/integer checks and 280 executed-budget refusals PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
