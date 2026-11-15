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
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
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
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn verify(data []u8) ! {
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}
struct NativeModule { context voidptr buffer voidptr engine voidptr }
fn native_module(data []u8, out string) !NativeModule {
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-integer-extrema-intrinsics'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }

 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures(); os.write_file(out + '/native-features.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
 mut f := C.LLVMGetFirstFunction(module_ptr); for f != unsafe { nil } { C.LLVMAddTargetDependentFunctionAttr(f, c'target-cpu', cpu); C.LLVMAddTargetDependentFunctionAttr(f, c'target-features', features); f = C.LLVMGetNextFunction(f) }; C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
 assert C.LLVMWriteBitcodeToFile(module_ptr, (out + '/native-input-features.bc').str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn mask(width int) u64 { return if width==64 {~u64(0)} else {(u64(1)<<u32(width))-1} }
fn signed_input(width int,value u64) i64 {
 x:=value&mask(width);return if x&(u64(1)<<(width-1))!=0 {-i64((~x)&mask(width))-1}else{i64(x)}
}
fn count_reference(id int,width int,a u64,b u64) u64 {
 x:=a&mask(width);y:=b&mask(width)
 less:=if id in [0,1]!{signed_input(width,x)<signed_input(width,y)}else{x<y}
 return if (id in [0,2]! && less)||(id in [1,3]! && !less){x}else{y}
}
fn word(width int,sample int) u64 {
 m:=mask(width);sign:=u64(1)<<u32(width-1)
 x:=if sample==0 {m} else if sample==1 {u64(0)} else if sample==2 {sign} else if sample==3 {sign-1} else if sample==4 {u64(1)} else if sample==5 {m^sign} else if sample==6 {u64(0x5555555555555555)} else if sample==7 {u64(0xaaaaaaaaaaaaaaaa)} else {(u64(sample)*u64(0x9e3779b97f4a7c15))^(u64(sample)<<47)}
 return x&m
}
fn fi(ir airbitcode.IRModule,name string) int {for i,f in ir.functions {if f.name==name {return i}};panic(name)}
fn unchanged(data []u8) {for b in data {assert b==0xcc}}
struct Counts {
mut:
 shapes int
 exact int
 choices int
 poison int
 undef int
 scalar int
 metadata int
 budgets int
}
fn (mut c Counts) add(x Counts) {c.shapes+=x.shapes;c.exact+=x.exact;c.choices+=x.choices;c.poison+=x.poison;c.undef+=x.undef;c.scalar+=x.scalar;c.metadata+=x.metadata;c.budgets+=x.budgets}
struct Case {name string width int count int form int mode int flag int}
fn vector(c Case) string {
 if c.form>=2 {return ['poison','undef','zeroinitializer'][c.form-2]}
 mut s:=strings.new_builder(2048);s.write_string('<');for lane in 0 .. c.count {if lane!=0 {s.write_string(', ')};v:=if c.form==1 && lane%4==1 {'poison'} else if c.form==1 && lane%4==2 {'undef'} else {word(c.width,lane).str()};s.write_string('i${c.width} '+v)};s.write_string('>');return s.str()
}
fn source_lane(c Case,j u64,lane int,x u64) (int,u64) {
 if c.mode!=0 {if j>=u64(c.count){return 1,0};if j==u64(lane){return 0,x}}
 if c.form==3 || (c.form==1 && lane%4==2){return 3,0};if c.form==2 || (c.form==1 && lane%4==1){return 1,0}
 return 0,if c.form==4 {u64(0)} else {word(c.width,lane)}
}
fn aux_lane(c Case,j u64,lane int,value u64) (int,u64) {
 if c.mode==0 {return source_lane(c,j,lane,value)}
 if j>=u64(c.count){return 1,0};return 0,if j==u64(lane){value}else{u64(0)}
}
fn expected(c Case,j u64,q u64,r u64,x u64,y u64) (int,u64) {
 for lane in 0..c.count{a,_:=source_lane(c,j,lane,x);b,_:=aux_lane(c,j,lane,y);if c.mode!=2&&(a==3||b==3){return 3,0}}
 if r>=u64(c.count){return 1,0};index:=if c.mode==4{c.count-1-int(r)}else{int(r)}
 if c.mode==4&&r%2==0{if q>=u64(c.count){return 1,0};if q==u64(index){return 0,1}}
 mut a,mut av:=source_lane(c,j,index,x);mut b,mut bv:=aux_lane(c,j,index,y);mut choice:=false
 if c.mode==2{if a!=0{a=0;av=0;choice=true};if b!=0{b=0;bv=0;choice=true}}
 if a==1||b==1{return if c.mode==4{2}else{1},0};first:=count_reference(c.flag,c.width,av,bv)
 return if choice{2}else{0},if c.mode==3{count_reference(c.flag,c.width,first,bv)}else{first}
}
fn matrix(assembler string,out string,first int,last int,flag int) !Counts {
 id:=['smin','smax','umin','umax'][flag]
 mut s:=strings.new_builder(8388608);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 for width in first .. last {for count in 1 .. 17 {s.write_string('declare <${count} x i${width}> @llvm.${id}.v${count}i${width}(<${count} x i${width}>, <${count} x i${width}>)\n')
 for form in 0 .. 5 {for mode in 0 .. 5 {
  c:=Case{'case_${cases.len}',width,count,form,mode,flag};cases<<c;mut lanes:=[]string{};for lane in 0 .. count {lanes<<'i32 ${count-1-lane+(lane%2)*count}'}
  mut ops:='%a = insertelement <${count} x i${width}> ${vector(c)}, i${width} %x, i64 %j\n %b0 = insertelement <${count} x i${width}> zeroinitializer, i${width} %y, i64 %j\n'
  if mode==2 {for name in ['a','b0']{ops+='%f${name} = freeze <${count} x i${width}> %${name}\n'}}
  left:=if mode==0{vector(c)}else if mode==2{'%fa'}else{'%a'};right:=if mode==0{vector(c)}else if mode==2{'%fb0'}else{'%b0'}
  ops+='%n = call <${count} x i${width}> @llvm.${id}.v${count}i${width}(<${count} x i${width}> ${left}, <${count} x i${width}> ${right})\n'
  if mode==3 {ops+='%again = call <${count} x i${width}> @llvm.${id}.v${count}i${width}(<${count} x i${width}> %n, <${count} x i${width}> ${right})\n'}
  if mode==4 {ops+='%f = freeze <${count} x i${width}> %n\n %b = insertelement <${count} x i${width}> %f, i${width} 1, i64 %q\n %t = shufflevector <${count} x i${width}> %b, <${count} x i${width}> %f, <${count} x i32> <${lanes.join(', ')}>\n'}
  ops+='%v = extractelement <${count} x i${width}> ${if mode==4 {'%t'}else if mode==3 {'%again'}else{'%n'}}, i64 %r\n';if width!=64{ops+='%wide = zext i${width} %v to i64\n'};result:=if width==64{'%v'}else{'%wide'}
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load i${width}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load i${width}, ptr %yp, align 1\n store i8 17, ptr %out\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i64 ${result}, ptr %d, align 1\n ret void }\n')
  s.write_string('define i64 @scalar_${c.name}(i64 %j, i64 %q, i64 %r, i${width} %x, i${width} %y) { ${ops}ret i64 ${result} }\n');unsafe{lanes.free()}
 }}}}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out)!;defer{native.close()};mut total:=Counts{shapes:cases.len}
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('width\tlanes\tform\tmode\tj\tq\tr\tx\tvalue')!
 for c in cases {
  f:=fi(ir,c.name);sf:=fi(ir,'scalar_'+c.name);steps:=bodies.scopes[f+1].instructions_count;scalar_steps:=bodies.scopes[sf+1].instructions_count
  profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!;assert profile.steps==steps && profile.arguments[0].minimum_size==24 && profile.arguments[1].minimum_size==8+(c.width+7)/8 && profile.arguments[2].minimum_size==16;profile.free()
  address:=C.LLVMGetFunctionAddress(native.engine,c.name.str);assert address!=0
  mut indices:=[]u8{len:32};mut input:=[]u8{len:32};mut actual:=[]u8{len:32,init:0xcc};mut reference:=actual.clone();mut bs:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}]
  edges:=[u64(0),u64(c.count-1),u64(c.count),~u64(0),1,2,3,u64(c.count+1)]!
  for sample in 0 .. c.count+2 {
   j:=edges[(sample*3)%8];q:=edges[(sample*5+1)%8];r:=u64(sample);x:=word(c.width,sample);y:=word(c.width,sample+3);state,value:=expected(c,j,q,r,x,y)
   for i in 0 .. 8 {indices[1+i]=u8(j>>u32(i*8));indices[9+i]=u8(q>>u32(i*8));indices[17+i]=u8(r>>u32(i*8));input[1+i]=u8((x|~mask(c.width))>>u32(i*8));input[9+i]=u8((y|~mask(c.width))>>u32(i*8))};for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc}
   args:=[j,q,r,x|~mask(c.width),y|~mask(c.width)]
   if state==3 {if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps){panic('undef scalar admitted')};if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps){panic('undef integer admitted')}}else{
    a:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps)!;assert a.kind==.integer && a.bits==64 && a.steps==scalar_steps && a.poison==(state==1) && (a.poison||a.value==value),'${c} ${sample} expected=${value} got=${a}'
    b:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps)!;assert b.bits==64 && b.steps==scalar_steps && b.poison==(state==1) && (b.poison||b.value==value),'${c} ${sample} expected=${value} got=${b}'
   };total.scalar+=2
   if state in [1,3] {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('indeterminate stored')}else{assert err.msg()==if state==3{'AIR vector intrinsic: undef source lane'}else{'AIR memory execution: poison store'}};if state==1{total.poison++}else{total.undef++}}else{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps;if state==0{total.exact++}else{total.choices++}}
   for i,b in actual {assert b==if i==3{u8(17)}else if state in [0,2]&&i>=11&&i<19{u8(value>>u32((i-11)*8))}else{u8(0xcc)},'${c} sample=${sample} byte=${i}'}
   // The VM receives noisy padding. Canonicalize native load padding: LLVM
   // may assume unused bits are zero when legalizing i1/odd-width vectors.
   if state==0 {for i in 0 .. 8 {input[1+i]=u8(x>>u32(i*8));input[9+i]=u8(y>>u32(i*8))};unsafe{NativeCast(voidptr(address))(&indices[1],&input[1],&reference[3])};assert actual==reference,'${c} sample=${sample}';rows.writeln('${c.width}\t${c.count}\t${c.form}\t${c.mode}\t${j}\t${q}\t${r}\t${x}\t${value}')!};unsafe{args.free()}
  }
  for i in 0 .. actual.len {actual[i]=0xcc};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps-1){panic('short memory budget')};unchanged(actual);if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0,0],scalar_steps-1){panic('short scalar budget')};if _:=p.run_integer_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0,0],scalar_steps-1){panic('short integer budget')};total.budgets+=3
  total.metadata+=metadata_checks(ir,stream,pools,bodies,mut p,f,mut bs,actual,steps)!
  unsafe{indices.free();input.free();actual.free();reference.free();bs.free()}
 }
 assert total.shapes==(last-first)*400 && total.scalar==(total.exact+total.choices+total.poison+total.undef)*2 && total.metadata*5==total.shapes*138 && total.budgets==total.shapes*3
 os.write_file(out+'/result.txt','AIR-VECTOR-INTEGER-EXTREMA-MATRIX: ${total}\n')!;return total
}
fn bulk(assembler string,out string,first int,last int,direction int) !int {
 id:=['smin','smax','umin','umax'][direction];mut s:=strings.new_builder(1048576);s.write_string('target datalayout = "e-p:64:64"\n')
 for width in first..last {t:='<16 x i${width}>';s.write_string('declare ${t} @llvm.${id}.v16i${width}(${t}, ${t})\n define void @bulk_${width}(ptr %unused, ptr %src, ptr %out) { store i8 17, ptr %out\n')
  for arg in 0..2{for lane in 0..16{s.write_string('%p${arg}_${lane} = getelementptr i8, ptr %src, i64 ${arg*128+lane*8}\n %x${arg}_${lane} = load i${width}, ptr %p${arg}_${lane}, align 1\n %a${arg}_${lane} = insertelement ${t} ${if lane==0{'poison'}else{'%a${arg}_${lane-1}'}}, i${width} %x${arg}_${lane}, i32 ${lane}\n')}}
  s.write_string('%n = call ${t} @llvm.${id}.v16i${width}(${t} %a0_15, ${t} %a1_15)\n')
  for lane in 0..16{s.write_string('%v${lane} = extractelement ${t} %n, i32 ${lane}\n');if width!=64{s.write_string('%z${lane} = zext i${width} %v${lane} to i64\n')};s.write_string('%d${lane} = getelementptr i8, ptr %out, i64 ${8+lane*8}\n store i64 %${if width==64{'v'}else{'z'}}${lane}, ptr %d${lane}, align 1\n')};s.write_string('ret void }\n')
 }
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out)!;defer{native.close()};mut checks:=0;mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('width\ta\tb\tvalue')!
 for width in first..last {f:=fi(ir,'bulk_${width}');steps:=bodies.scopes[f+1].instructions_count;profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!;assert profile.steps==steps&&profile.arguments[0].minimum_size==0&&profile.arguments[1].minimum_size==248+(width+7)/8&&profile.arguments[2].minimum_size==136;profile.free();address:=C.LLVMGetFunctionAddress(native.engine,('bulk_${width}').str);assert address!=0
  mut unused:=[u8(0)];mut input:=[]u8{len:257};mut actual:=[]u8{len:144,init:0xcc};mut reference:=actual.clone();mut bs:=[airbitcode.IRMemoryBinding{data:unused},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}];samples:=if width<=8{int(u64(1)<<u32(width*2))}else{4096}
  for chunk in 0..(samples+15)/16 {mut words:=[32]u64{}
   for lane in 0..16{k:=u64((chunk*16+lane)%samples);words[lane]=(if width<=8{k&mask(width)}else{k*u64(0x9e3779b97f4a7c15)})|~mask(width);words[16+lane]=(if width<=8{k>>u32(width)}else{(k*u64(0xd1b54a32d192ed03))^(k<<47)})|~mask(width)}
   for arg in 0..2{for lane in 0..16{for i in 0..8{input[1+arg*128+lane*8+i]=u8(words[arg*16+lane]>>u32(i*8))}}};for i in 0..actual.len{actual[i]=0xcc;reference[i]=0xcc};assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps
   for arg in 0..2{for lane in 0..16{for i in 0..8{input[1+arg*128+lane*8+i]=u8((words[arg*16+lane]&mask(width))>>u32(i*8))}}};unsafe{NativeCast(voidptr(address))(unused.data,&input[1],&reference[3])};assert actual==reference,'${id} ${width} ${chunk}'
   for i,b in actual{lane:=if i>=11&&i<139{(i-11)/8}else{0};value:=count_reference(direction,width,words[lane],words[16+lane]);assert b==if i==3{u8(17)}else if i>=11&&i<139{u8(value>>u32(((i-11)%8)*8))}else{u8(0xcc)}}
   for lane in 0..16{row:='${width}\t${words[lane]}\t${words[16+lane]}\t${count_reference(direction,width,words[lane],words[16+lane])}';rows.writeln(row)!;unsafe{row.free()};checks++}
  };unsafe{unused.free();input.free();actual.free();reference.free();bs.free()}
 };os.write_file(out+'/result.txt','AIR-VECTOR-INTEGER-EXTREMA-BULK: ${checks} exact native lane values, narrow pair exhaustion and wider patterns PASS\n')!;return checks
}
fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};t:='<${count} x i16>';mut s:=strings.new_builder(16777216);s.write_string('declare ${t} @llvm.smin.v${count}i16(${t}, ${t})\n define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')}
 for i in 0..if storage&&over{4097}else{4096}{s.write_string('%n${i} = call ${t} @llvm.smin.v${count}i16(${t} zeroinitializer, ${t} zeroinitializer)\n')};if !storage{for i in 0..if over{50213}else{50212}{s.write_string('%x${i} = extractelement ${t} %n4095, i32 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage{'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'};f:=fi(ir,name)
 if over{if name=='memory'{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000){panic('memory limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output)}else if name=='void'{if _:=p.run_void_function(ir,stream,pools,bodies,f,[],70000){panic('void limit')}else{assert err.msg()==diagnostic,err.msg()}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],70000){panic('scalar limit')}else{assert err.msg()==diagnostic,err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],70000){panic('integer limit')}else{assert err.msg()==diagnostic,err.msg()}}}
 else{steps:=if storage{4097}else{54309};if name=='memory'{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000)!.steps==steps+1;assert output[0]==17}else if name=='void'{assert p.run_void_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}else{assert p.run_scalar_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps;assert p.run_integer_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}}
 unsafe{output.free();bs.free()};os.write_file(out+'/result.txt','AIR-VECTOR-INTEGER-EXTREMA-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}
fn controls(assembler string,out string) ! {
 ids:=['smin','smax','umin','umax'];mut s:=strings.new_builder(8388608);s.write_string('target datalayout = "e-p:64:64"\n');mut checks:=0
 for width in 1..65{t:='<2 x i${width}>';sign:=u64(1)<<u32(width-1);a:='<i${width} ${sign}, i${width} ${sign}>';b:='<i${width} 1, i${width} 1>'
  for id in ids{s.write_string('declare ${t} @llvm.${id}.v2i${width}(${t}, ${t}) #0\n')}
  mut ops:='';for i,id in ids{ops+='%n${i} = call ${t} @llvm.${id}.v2i${width}(${t} ${a}, ${t} ${b})\n %x${i} = extractelement ${t} %n${i}, i32 0\n';if width!=64{ops+='%v${i} = zext i${width} %x${i} to i64\n'};ops+='%w${i} = shl i64 %${if width==64{'x'}else{'v'}}${i}, ${i}\n';if i>0{ops+='%sum${i} = add i64 %${if i==1{'w0'}else{'sum'+(i-1).str()}}, %w${i}\n'}}
  for kind in ['scalar','memory','void']{s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @cache_${width}_${kind}(${if kind=='memory'{'ptr %out'}else{''}}) { ${if kind=='memory'{'store i8 17, ptr %out\n'}else{''}}${ops}${if kind=='memory'{'%p = getelementptr i8, ptr %out, i64 8\n store i64 %sum3, ptr %p, align 1\n'}else{''}}ret ${if kind=='scalar'{'i64 %sum3'}else{'void'}} }\n')}
  for id in ids{for arg in 0..2{for state in ['poison','undef']{name:='state_${width}_${id}_${arg}_${state}';values:=[if arg==0{state}else{a},if arg==1{state}else{b}]
   for kind in ['scalar','memory','void']{value:=if width==64{'%v'}else{'%wide'};body:=if kind=='void'{''}else{'%v = extractelement ${t} %n, i32 0\n '+if width==64{''}else{'%wide = zext i${width} %v to i64\n'}};s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @${name}_${kind}(${if kind=='memory'{'ptr %out'}else{''}}) { ${if kind=='memory'{'store i8 17, ptr %out\n'}else{''}}%n = call ${t} @llvm.${id}.v2i${width}(${t} ${values[0]}, ${t} ${values[1]})\n ${body}${if kind=='memory'{'%p = getelementptr i8, ptr %out, i64 8\n store i64 '+value+', ptr %p, align 1\n'}else{''}}ret ${if kind=='scalar'{'i64 '+value}else{'void'}} }\n')}
  }}}
 }
 for id in ids{t:='<2 x i65>';s.write_string('declare ${t} @llvm.${id}.v2i65(${t}, ${t})\n define void @cold_${id}(ptr %out) { store i8 17, ptr %out\n br i1 true, label %done, label %bad\n done: ret void\n bad: %n = call ${t} @llvm.${id}.v2i65(${t} zeroinitializer, ${t} zeroinitializer)\n ret void }\n')};s.write_string('attributes #0 = { nounwind }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 for width in 1..65{mut expected:=u64(0);for i,_ in ids{expected+=count_reference(i,width,u64(1)<<u32(width-1),1)<<u32(i)}
  for kind in ['scalar','memory','void']{f:=fi(ir,'cache_${width}_${kind}');if kind=='scalar'{a:=p.run_scalar_function(ir,stream,pools,bodies,f,[],100)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,[],100)!;assert !a.poison&&!b.poison&&a.value==expected&&b.value==expected;checks+=2}else if kind=='void'{p.run_void_function(ir,stream,pools,bodies,f,[],100)!;checks++}else{mut output:=[]u8{len:16,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100)!;for i,b in output{assert b==if i==0{u8(17)}else if i>=8{u8(expected>>u32((i-8)*8))}else{u8(0xcc)}};unsafe{output.free();bs.free()};checks++}}
  for id in ids{for arg in 0..2{for state in ['poison','undef']{name:='state_${width}_${id}_${arg}_${state}';f:=fi(ir,name+'_scalar');if state=='poison'{assert p.run_scalar_function(ir,stream,pools,bodies,f,[],50)!.poison;assert p.run_integer_function(ir,stream,pools,bodies,f,[],50)!.poison;p.run_void_function(ir,stream,pools,bodies,fi(ir,name+'_void'),[],50)!}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],50){panic('scalar undef')};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],50){panic('integer undef')};if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,name+'_void'),[],50){panic('void undef')}}
   mut output:=[]u8{len:16,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,name+'_memory'),mut bs,50){panic('state store')}else{assert err.msg()==if state=='poison'{'AIR memory execution: poison store'}else{'AIR vector intrinsic: undef source lane'}};for i,b in output{assert b==if i==0{u8(17)}else{u8(0xcc)}};unsafe{output.free();bs.free()};checks+=4
  }}}
 }
 mut values:=stream.values.clone();defer{unsafe{values.free()}};mut records:=stream.records.clone();defer{unsafe{records.free()}};bad_stream:=airbitcode.Stream{...stream,values:values,records:records};mut group:=-1
 for i,r in stream.records{if stream.blocks[r.block].id==10&&r.code==3&&r.values_count>=4&&stream.values[r.values_start+1]==0xffffffff&&stream.values[r.values_start+2]==0{group=r.values_start;records[i]=airbitcode.Record{...r,values_count:4};break}};assert group>=0;before:=values[group+1];enum_before:=values[group+3]
 for width in [1,7,32,64]{mut expected:=u64(0);for i,_ in ids{expected+=count_reference(i,width,u64(1)<<u32(width-1),1)<<u32(i)};mut output:=[]u8{len:16,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];p.run_memory_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_memory'),mut bs,100)!;assert output[0]==17&&output[8]==u8(expected);p.run_void_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_void'),[],100)!;assert p.run_scalar_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_scalar'),[],100)!.value==expected;assert p.run_integer_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_scalar'),[],100)!.value==expected;checks+=4;unsafe{output.free();bs.free()}}
 for slot in u64(0)..3{values[group+1]=slot;values[group+3]=60;for width in [1,7,32,64]{mut output:=[]u8{len:16,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_memory'),mut bs,100){panic('attribute memory')};unchanged(output);if _:=p.run_void_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_void'),[],100){panic('attribute void')};if _:=p.run_scalar_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_scalar'),[],100){panic('attribute scalar')};if _:=p.run_integer_function(ir,bad_stream,pools,bodies,fi(ir,'cache_${width}_scalar'),[],100){panic('attribute integer')};checks+=4;unsafe{output.free();bs.free()}}};values[group+1]=before;values[group+3]=enum_before
 for id in ids{mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'cold_'+id),mut bs,50){panic('cold width')};unchanged(output);checks++;unsafe{output.free();bs.free()}}
 assert checks==4420;os.write_file(out+'/result.txt','AIR-VECTOR-INTEGER-EXTREMA-CONTROLS: ${checks} all-four cache chains, both poison/undef sources, four APIs, repaired attribute baselines, immarg refusal and cold widths PASS\n')!
}
fn main(){assert os.args.len==3;out:=os.abs_path(os.args[2]);assert !os.exists(out)&&!out.starts_with(os.getwd()+'/');os.mkdir_all(out)!;mut total:=Counts{};mut values:=0
 for direction in 0..4{for chunk in 0..16{total.add(matrix(os.args[1],out+'/matrix-${direction}-${chunk}',chunk*4+1,(chunk+1)*4+1,direction)!);values+=bulk(os.args[1],out+'/bulk-${direction}-${chunk}',chunk*4+1,(chunk+1)*4+1,direction)!}}
 assert total.shapes==102400&&total.scalar==2150400&&total.metadata==2826240&&total.budgets==307200&&values==1267072
 controls(os.args[1],out+'/controls')!;for storage in [false,true]{for over in [false,true]{for name in ['memory','void','scalar']{limits(os.args[1],out+'/${if storage{'storage'}else{'work'}}-${if over{'over'}else{'boundary'}}-${name}',storage,over,name)!}}}
 result:='AIR-VECTOR-INTEGER-EXTREMA-MATRIX: ${total}\nAIR-VECTOR-INTEGER-EXTREMA-BULK: ${values} exact native values; every i1-i8 pair, wide deterministic pairs PASS\n'+os.read_file(out+'/controls/result.txt')!+'AIR-VECTOR-INTEGER-EXTREMA: 16 shared storage/work boundary checks through four APIs PASS\n';os.write_file(out+'/result.txt',result)!;print(result)
}
fn metadata_checks(ir airbitcode.IRModule, stream airbitcode.Stream,pools airbitcode.IRConstantPools,bodies airbitcode.IRFunctionBodies,mut p airbitcode.IRTypedProgram,f int,mut bs []airbitcode.IRMemoryBinding,output []u8,steps int) !int {
 scope:=bodies.scopes[f+1]; mut checks:=0
 for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {
  op:=p.instructions[index]; if stream.records[bodies.instructions[index].record].code!=34 {continue}
  for changed in [airbitcode.IRTypedInstruction{...op,flags:0},airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,opcode:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,callee_function:ir.functions.len},airbitcode.IRTypedInstruction{...op,operands_count:0},airbitcode.IRTypedInstruction{...op,operands_count:1},airbitcode.IRTypedInstruction{...op,operands_count:5},airbitcode.IRTypedInstruction{...op,result_type:-1},airbitcode.IRTypedInstruction{...op,targets_count:1},airbitcode.IRTypedInstruction{...op,indices_count:1}] {p.instructions[index]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('metadata admitted')}; unchanged(output);checks++}; p.instructions[index]=op
  for operand in 0 .. op.operands_count { slot:=op.operands_start+operand; original:=p.operands[slot]; changes:=if operand==0 {[airbitcode.IRTypedOperand{...original,number:~u32(0)},airbitcode.IRTypedOperand{...original,type_index:-1}]} else {[airbitcode.IRTypedOperand{...original,number:~u32(0)},airbitcode.IRTypedOperand{...original,number:bodies.instructions[index].next_value},airbitcode.IRTypedOperand{...original,type_index:-1}]}; for changed in changes {p.operands[slot]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('source admitted')}; unchanged(output);checks++}; p.operands[slot]=original; unsafe{changes.free()} }
 }
 return checks
}
