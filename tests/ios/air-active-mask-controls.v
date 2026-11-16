// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings

fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name {return i}};panic(name)}
fn unchanged(bytes []u8) {for b in bytes {assert b==0xcc}}
fn assemble(assembler string,root string,source string) ![]u8 {
 assert !os.exists(root);os.mkdir_all(root)!;os.write_file(root+'/input.ll',source)!
 result:=os.exec([assembler,root+'/input.ll','-o',root+'/input.bc']);os.write_file(root+'/assemble.log',result.output)!;assert result.exit_code==0,result.output
 return os.read_bytes(root+'/input.bc')!
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 mut s:=strings.new_builder(1048576)
 s.write_string('target datalayout = "e-p:64:64"\n')
 s.write_string('declare <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8,i8)\n declare <3 x i1> @alias(i8,i8)\n')
 for state in ['poison','undef'] {for operand in 0..2 {for input_freeze in [false,true] {for output_freeze in [false,true] {
  name:='state_${state}_${operand}_${input_freeze}_${output_freeze}'
  s.write_string('define i1 @${name}() {%input = freeze i8 ${state}\n %m = call <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8 ${if operand==0 {if input_freeze {'%input'}else{state}}else{'0'}},i8 ${if operand==1 {if input_freeze {'%input'}else{state}}else{'255'}})\n %f = freeze <3 x i1> %m\n %v = extractelement <3 x i1> %${if output_freeze {'f'}else{'m'}},i64 0\n ret i1 %v }\n')
 }}}}
 s.write_string('define void @discard() {%m = call <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8 0,i8 1)\n ret void }\n define void @duplicate(ptr %out) {store i8 17,ptr %out\n %a = call <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8 0,i8 1)\n %b = call <3 x i1> @alias(i8 0,i8 1)\n ret void }\n')
 for state in ['poison','undef'] {for frozen in [false,true] {for bad_index in [false,true] {
  s.write_string('define void @address_${state}_${frozen}_${bad_index}(ptr %out) {store i8 17,ptr %out\n %m = call <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8 ${state},i8 255)\n %f = freeze <3 x i1> %m\n %e = extractelement <3 x i1> %${if frozen {'f'}else{'m'}},i64 ${if bad_index {'3'}else{'0'}}\n %v = zext i1 %e to i64\n %p = getelementptr i8,ptr %out,i64 %v\n store i8 42,ptr %p\n ret void }\n')
 }}}
 for amount in 0..36 {s.write_string('define void @depth_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %m = call <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8 0,i8 2)\n');for i in 0..amount {s.write_string('%f${i} = freeze <3 x i1> %${if i==0 {'m'}else{'f'+(i-1).str()}}\n')};s.write_string('%e = extractelement <3 x i1> %${if amount==0 {'m'}else{'f'+(amount-1).str()}},i64 %r\n %v = zext i1 %e to i64\n %p = getelementptr i8,ptr %out,i64 %v\n ret void }\n')}
 for amount in 100..140 {s.write_string('define void @nodes_${amount}(i64 %r,ptr %out) {store i8 17,ptr %out\n %m = call <3 x i1> @llvm.get.active.lane.mask.v3i1.i8(i8 0,i8 2)\n');for i in 0..amount {s.write_string('%e${i} = extractelement <3 x i1> %m,i64 %r\n %v${i} = zext i1 %e${i} to i64\n %p${i} = getelementptr i8,ptr %out,i64 %v${i}\n')};s.write_string('ret void }\n')}
 for width in [1,8,9,32,64] {for n in [1,3,16] {
  if width!=8||n!=3 {s.write_string('declare <${n} x i1> @llvm.get.active.lane.mask.v${n}i1.i${width}(i${width},i${width})\n')}
  s.write_string('define i64 @loop_${width}_${n}(i${width} %base,i${width} %limit,i64 %visits,i64 %r) {entry: br label %body\n body: %old = phi <${n} x i1> [zeroinitializer,%entry],[%m,%body]\n %i = phi i64 [0,%entry],[%next,%body]\n %total = phi i64 [0,%entry],[%sum,%body]\n %low = trunc i64 %i to i${width}\n %a = add i${width} %base,%low\n %m = call <${n} x i1> @llvm.get.active.lane.mask.v${n}i1.i${width}(i${width} %a,i${width} %limit)\n %v = extractelement <${n} x i1> %old,i64 %r\n %wide = zext i1 %v to i64\n %sum = add i64 %total,%wide\n %next = add i64 %i,1\n %again = icmp ult i64 %next,%visits\n br i1 %again,label %body,label %done\n done: ret i64 %sum }\n')
 }}
 // The i64 loop already has the correct type: avoid an invalid identity trunc.
 source:=s.str().replace('trunc i64 %i to i64','or i64 %i,0')
 os.write_file(root+'/input.ll',source)!
 r:=os.exec([os.args[1],root+'/input.ll','-o',root+'/input.bc']);os.write_file(root+'/assemble.log',r.output)!;assert r.exit_code==0,r.output
 data:=os.read_bytes(root+'/input.bc')!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut checks:=0
 for state in ['poison','undef'] {for operand in 0..2 {for input_freeze in [false,true] {for output_freeze in [false,true] {for integer in [false,true] {
  f:=fi(ir,'state_${state}_${operand}_${input_freeze}_${output_freeze}')
  if state=='undef'&&!input_freeze {if integer {if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],5) {panic('undef argument')}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],5) {panic('undef argument')}}}
  else {
   expected_poison:=state=='poison'&&!input_freeze&&!output_freeze
   expected_value:=if !input_freeze {u64(0)}else{u64(operand==0)}
   if integer {v:=p.run_integer_function(ir,stream,pools,bodies,f,[],5)!;assert v.poison==expected_poison&&(v.poison||v.value==expected_value)}else{v:=p.run_scalar_function(ir,stream,pools,bodies,f,[],5)!;assert v.poison==expected_poison&&(v.poison||v.value==expected_value)}
  };checks++
 }}}}}
 assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'discard'),[],2)!.steps==2;checks++
 mut output:=[]u8{len:16,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
 for state in ['poison','undef'] {for frozen in [false,true] {for bad_index in [false,true] {f:=fi(ir,'address_${state}_${frozen}_${bad_index}');for prepared in [false,true] {
  for i in 0..output.len {output[i]=0xcc};valid:=state=='poison'&&frozen&&!bad_index
  if plan:=p.prepare_memory_function(ir,stream,pools,bodies,f) {
   if _:=plan.validate(bs,8) {assert valid}else{assert !valid};for byte in output {assert byte==0xcc}
   if prepared {if _:=plan.run(mut bs,8) {assert valid}else{assert !valid}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,8) {assert valid}else{assert !valid}};plan.free()
  }else{assert !valid,err.msg()}
  for i,byte in output {assert byte==if valid&&i==0 {u8(42)}else{u8(0xcc)}};checks++
 }}}}
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.get.active.lane.mask.v3i1.i8'}
 for i in 0..output.len {output[i]=0xcc};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10) {panic('duplicate mask')};for byte in output {assert byte==0xcc};checks++
 original:=fi(ir,'llvm.get.active.lane.mask.v3i1.i8');saved:=functions[original]
 for name in ['llvm.get.active.lane.mask.v3i1.i9','llvm.get.active.lane.mask.v2i1.i8','llvm.get.active.lane.mask.v3i1.i08'] {functions[original]=airbitcode.IRFunction{...saved,name:name};if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'discard'),[],2) {panic('mask name/type')};checks++};functions[original]=saved
 mut max_depth:=0;mut refused:=false
 for amount in 0..36 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'depth_${amount}')) {assert !refused;max_depth=amount;plan.free()}else{refused=true};checks++};assert max_depth>0&&max_depth<35
 mut max_nodes:=0;mut node_refused:=false
 for amount in 100..140 {if plan:=p.prepare_memory_function(ir,stream,pools,bodies,fi(ir,'nodes_${amount}')) {assert !node_refused;max_nodes=amount;plan.free()}else{node_refused=true};checks++};assert max_nodes>=100&&max_nodes<139
 mut loops:=0
 for width in [1,8,9,32,64] {for n in [1,3,16] {for visits in [u64(1),2,3,7,16,257,1024]! {for lane in [u64(0),u64(n-1)]! {
  maximum:=if width==64 {~u64(0)}else{(u64(1)<<u32(width))-1};base:=maximum-1;limit:=maximum;mut total:=u64(0)
  for i in u64(0)..visits-1 {a:=(base+i)&maximum;sum:=a+lane;if sum>=a&&sum<limit {total++}}
  f:=fi(ir,'loop_${width}_${n}');args:=[base,limit,visits,lane];steps:=int(visits*12+2)
  a:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,args,steps)!;assert !a.poison&&!b.poison&&a.value==total&&b.value==total&&a.steps==steps&&b.steps==steps
  if _:=p.run_scalar_function(ir,stream,pools,bodies,f,args,steps-1) {panic('executed mask budget')};loops++;unsafe{args.free()}
 }}}}
 for storage in [false,true] {for over in [false,true] {limits(os.args[1],root+'/limit-${storage}-${over}',storage,over)!;checks+=2}}
 unsafe{output.free();bs.free()}
 line:='AIR-ACTIVE-MASK-CONTROLS: ${checks} state/arity/name/duplicate/graph checks (max freezes ${max_depth}, ${max_nodes} shared extractions); ${loops} vector-PHI loop results, 420 scalar/integer checks and 210 executed-budget refusals PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}

fn limits(assembler string,root string,storage bool,over bool) ! {
 n:=if storage {1}else{16};mut s:=strings.new_builder(10485760);s.write_string('declare <${n} x i1> @llvm.get.active.lane.mask.v${n}i1.i8(i8,i8)\n')
 for name in ['memory','scalar'] {s.write_string('define void @${name}(${if name=='memory' {'ptr %out'}else{''}}) {\n');if name=='memory' {s.write_string('store i8 17,ptr %out\n')};for i in 0..if storage&&over {4097}else{4096} {s.write_string('%s${i} = call <${n} x i1> @llvm.get.active.lane.mask.v${n}i1.i8(i8 0,i8 1)\n')};if !storage {for i in 0..if over {58405}else{58404} {s.write_string('%v${i} = extractelement <16 x i1> %s4095,i32 0\n')}};s.write_string('ret void }\n')}
 data:=assemble(assembler,root,s.str())!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('memory step limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('void step limit')}else{assert err.msg()==diagnostic,err.msg()}}else{assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098}else{62502};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!.steps==if storage {4097}else{62501}}
 unsafe{output.free();bs.free()}
}
