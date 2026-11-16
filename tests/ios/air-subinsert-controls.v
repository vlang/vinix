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
 mut s:=strings.new_builder(1048576);s.write_string('target datalayout = "e-p:64:64"\n declare <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8>,<2 x i8>,i64 immarg)\n declare <4 x i8> @alias(<4 x i8>,<2 x i8>,i64)\n')
 for selected in [false,true] {for frozen in [false,true] {
  base:=if selected {'<i8 7,i8 9,i8 poison,i8 undef>'}else{'<i8 poison,i8 undef,i8 7,i8 9>'};input:=if selected {'<i8 poison,i8 undef>'}else{'<i8 11,i8 13>'}
  s.write_string('define i8 @state_${selected}_${frozen}(i64 %r) {%v = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> ${base},<2 x i8> ${input},i64 0)\n %f = freeze <4 x i8> %v\n %e = extractelement <4 x i8> %${if frozen {'f'}else{'v'}},i64 %r\n ret i8 %e }\n')
 }}
 s.write_string('define void @discard() {%v = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> undef,<2 x i8> undef,i64 2)\n ret void }\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> zeroinitializer,<2 x i8> zeroinitializer,i64 0)\n %b = call <4 x i8> @alias(<4 x i8> zeroinitializer,<2 x i8> zeroinitializer,i64 2)\n ret void }\n')
 s.write_string('define void @cached(i64 %offset,ptr %out) {store i8 17,ptr %out\n %one = add i64 1,4\n %negative = freeze i64 -1\n %poison = freeze i64 poison\n %undef = freeze i64 undef\n %a = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> zeroinitializer,<2 x i8> zeroinitializer,i64 0)\n %b = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> zeroinitializer,<2 x i8> zeroinitializer,i64 2)\n ret void }\n')
 for amount in 0..36 {s.write_string('define void @depth_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %v = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> zeroinitializer,<2 x i8> zeroinitializer,i64 2)\n');for i in 0..amount {s.write_string('%f${i} = freeze <4 x i8> %${if i==0 {'v'}else{'f'+(i-1).str()}}\n')};s.write_string('%e = extractelement <4 x i8> %${if amount==0 {'v'}else{'f'+(amount-1).str()}},i64 %r\n %w = zext i8 %e to i64\n %p = getelementptr i8,ptr %out,i64 %w\n ret void }\n')}
 for amount in 90..141 {s.write_string('define void @nodes_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %v = call <4 x i8> @llvm.vector.insert.v4i8.v2i8(<4 x i8> zeroinitializer,<2 x i8> zeroinitializer,i64 2)\n');for i in 0..amount {s.write_string('%e${i} = extractelement <4 x i8> %v,i64 %r\n %w${i} = zext i8 %e${i} to i64\n %p${i} = getelementptr i8,ptr %out,i64 %w${i}\n')};s.write_string('ret void }\n')}
 data:=assemble(os.args[1],root+'/basic',s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut checks:=0
 for selected in [false,true] {for frozen in [false,true] {for r in [u64(0),1,2,3,4,~u64(0)]! {for integer in [false,true] {
  f:=fi(ir,'state_${selected}_${frozen}');args:=[r];undef:=selected&&!frozen&&r<4&&r%2==1;poison:=r>=4||(selected&&!frozen&&r%2==0);value:=if selected||r>=4 {u64(0)}else{[u64(11),13,7,9]![int(r)]}
  if integer {if v:=p.run_integer_function(ir,stream,pools,bodies,f,args,4) {assert !undef&&v.poison==poison&&(poison||v.value==value)}else{assert undef}}else{if v:=p.run_scalar_function(ir,stream,pools,bodies,f,args,4) {assert !undef&&v.poison==poison&&(poison||v.value==value)}else{assert undef}};checks++;unsafe{args.free()}
 }}}}
 assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard'),[],2)!.steps==2;checks++
 mut output:=[u8(0xcc)];mut offset:=[u64(0)];mut bs:=[airbitcode.IRMemoryBinding{values:offset},airbitcode.IRMemoryBinding{data:output,writable:true}]
 cached:=fi(ir,'cached');scope:=bodies.scopes[cached+1];mut calls:=[]int{};mut invalid:=[]airbitcode.IRTypedOperand{}
 for index in scope.instructions_start..scope.instructions_start+scope.instructions_count {
  op:=p.instructions[index];code:=stream.records[bodies.instructions[index].record].code
  if code==34 {calls<<index}else if code==2 {invalid<<p.operands[op.operands_start];invalid<<p.operands[op.operands_start+1]}else if code==58 {invalid<<p.operands[op.operands_start]}
 }
 assert calls.len==2&&invalid.len==5;original:=p.operands[p.instructions[calls[1]].operands_start+3];invalid<<airbitcode.IRTypedOperand{...original,number:pools.module_values};assert pools.lookup(cached+1,pools.module_values)!.kind==.argument
 assert p.run_memory_function(ir,stream,pools,bodies,cached,mut bs,8)!.steps==8;assert output[0]==17
 for replacement in invalid {p.operands[p.instructions[calls[1]].operands_start+3]=replacement;output[0]=0xcc
  if _:=p.run_memory_function(ir,stream,pools,bodies,cached,mut bs,8) {panic('cached immediate accepted')}else{assert err.msg().contains('offset'),err.msg()};unchanged(output)
  if _:=p.prepare_memory_function(ir,stream,pools,bodies,cached) {panic('prepared cached immediate accepted')}else{assert err.msg().contains('offset'),err.msg()};checks+=2
 };p.operands[p.instructions[calls[1]].operands_start+3]=original
 mut values:=stream.values.clone();defer{unsafe{values.free()}};view_stream:=airbitcode.Stream{...stream,values:values};mut attribute_group:=-1
 for record in stream.records {if stream.blocks[record.block].id==10&&record.code==3&&record.values_count==4&&stream.values[record.values_start+1]==3&&stream.values[record.values_start+3]==60 {attribute_group=record.values_start;break}};assert attribute_group>=0
 for slot in [u64(0),1,2,4,0xffffffff]! {values[attribute_group+1]=slot;output[0]=0xcc
  if _:=p.run_memory_function(ir,view_stream,pools,bodies,cached,mut bs,8) {panic('wrong third immarg slot')};unchanged(output)
  if _:=p.run_void_function(ir,view_stream,pools,bodies,fi(ir,'discard'),[],2) {panic('void wrong third immarg slot')};checks+=2
 };values[attribute_group+1]=3
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.vector.insert.v4i8.v2i8'}
 output[0]=0xcc;mut one_binding:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut one_binding,10) {panic('duplicate overload')};unchanged(output);checks++
 declaration:=fi(ir,'llvm.vector.insert.v4i8.v2i8');saved:=functions[declaration]
 for name in ['llvm.vector.insert.v3i8.v2i8','llvm.vector.insert.v4i8.v1i8','llvm.vector.insert.v4i9.v2i9'] {functions[declaration]=airbitcode.IRFunction{...saved,name:name};if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'discard'),[],2) {panic('name/type mismatch')};checks++};functions[declaration]=saved
 mut depth_max:=0;mut depth_failed:=false
 for amount in 0..36 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'depth_${amount}')) {assert !depth_failed;depth_max=amount;plan.free()}else{depth_failed=true};checks++};assert depth_max>0&&depth_max<35
 mut nodes_max:=0;mut nodes_failed:=false
 for amount in 90..141 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'nodes_${amount}')) {assert !nodes_failed;nodes_max=amount;plan.free()}else{nodes_failed=true};checks++};assert nodes_max>=90&&nodes_max<140
 for storage in [false,true] {for over in [false,true] {limits(os.args[1],root+'/limit-${storage}-${over}',storage,over)!;checks+=2}}
 loop_checks(os.args[1],root+'/loops')!
 line:='AIR-SUBINSERT-CONTROLS: ${checks} state/discard/cached-offset/immarg/name/duplicate/resource checks, max ${depth_max} freezes and ${nodes_max} shared extractions PASS\n';os.write_file(root+'/result.txt',line+os.read_file(root+'/loops/result.txt')!)!;print(line)
 unsafe{output.free();offset.free();bs.free();one_binding.free();calls.free();invalid.free()}
}
fn limits(assembler string,root string,storage bool,over bool) ! {
 n:=if storage {1}else{16};mut s:=strings.new_builder(10485760);s.write_string('declare <${n} x i8> @llvm.vector.insert.v${n}i8.v${n}i8(<${n} x i8>,<${n} x i8>,i64 immarg)\n')
 for name in ['memory','scalar'] {s.write_string('define void @${name}(${if name=='memory' {'ptr %out'}else{''}}) {\n');if name=='memory' {s.write_string('store i8 17,ptr %out\n')};for i in 0..if storage&&over {4097}else{4096} {s.write_string('%s${i} = call <${n} x i8> @llvm.vector.insert.v${n}i8.v${n}i8(<${n} x i8> zeroinitializer,<${n} x i8> zeroinitializer,i64 0)\n')};if !storage {for i in 0..if over {50213}else{50212} {s.write_string('%e${i} = extractelement <16 x i8> %s4095,i32 0\n')}};s.write_string('ret void }\n')}
 data:=assemble(assembler,root,s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('memory resource limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('void resource limit')}else{assert err.msg()==diagnostic,err.msg()}}else{assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098}else{54310};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!.steps==if storage {4097}else{54309}}
 unsafe{output.free();bs.free()}
}
fn loop_checks(assembler string,root string) ! {
 mut s:=strings.new_builder(65536)
 for width in [1,8,9,32,64] {for shape in [[1,1,0]!,[3,1,2]!,[16,3,12]!,[16,16,0]!] {
  size:=shape[0];count:=shape[1];offset:=shape[2];bt:='<${size} x i${width}>';st:='<${count} x i${width}>';name:='llvm.vector.insert.v${size}i${width}.v${count}i${width}'
  s.write_string('declare ${bt} @${name}(${bt},${st},i64 immarg)\n define i64 @loop_${width}_${size}_${count}(i${width} %x,i64 %limit,i64 %r) {entry: br label %body\n body: %full = phi ${bt} [zeroinitializer,%entry],[%v,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %old = extractelement ${bt} %full,i32 ${offset}\n %sum = add i${width} %old,%x\n %small = insertelement ${st} zeroinitializer,i${width} %sum,i32 0\n %v = call ${bt} @${name}(${bt} %full,${st} %small,i64 ${offset})\n %chosen = extractelement ${bt} %v,i64 %r\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%limit\n br i1 %again,label %body,label %done\n done: %wide = ${if width==64 {'or i64 %chosen,0'}else{'zext i${width} %chosen to i64'}}\n ret i64 %wide }\n')
 }}
 data:=assemble(assembler,root,s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut checks:=0
 for width in [1,8,9,32,64] {for shape in [[1,1,0]!,[3,1,2]!,[16,3,12]!,[16,16,0]!] {for visits in [u64(1),2,3,7,16,257,1024]! {for lane in [u64(shape[2]),u64(shape[2]+shape[1]-1)]! {
  mask:=if width==64 {~u64(0)}else{(u64(1)<<u32(width))-1};x:=u64(0x9e3779b97f4a7c15)&mask;value:=if lane==u64(shape[2]) {(x*visits)&mask}else{u64(0)};args:=[x|~mask,visits,lane];steps:=int(visits*10+3);f:=fi(ir,'loop_${width}_${shape[0]}_${shape[1]}')
  a:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,args,steps)!;assert !a.poison&&!b.poison&&a.value==value&&b.value==value&&a.steps==steps&&b.steps==steps;if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps-1) {panic('executed loop budget')};checks++;unsafe{args.free()}
 }}}}
 assert checks==280;line:='AIR-SUBINSERT-LOOPS: 280 vector-PHI properties, 560 scalar/integer checks and 280 executed-budget refusals PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
