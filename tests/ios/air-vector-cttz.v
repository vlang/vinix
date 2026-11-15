// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import math.bits as bitops
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-cttz-intrinsics'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
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
fn count_reference(width int,value u64) u64 {x:=value&mask(width);return if x==0{u64(width)}else{u64(bitops.trailing_zeros_64(x))}}
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
fn expected(c Case,j u64,q u64,r u64,x u64) (int,u64) {
 for lane in 0 .. c.count {state,_:=source_lane(c,j,lane,x);if state==3&&c.mode!=2{return 3,0}}
 if r>=u64(c.count){return 1,0};index:=if c.mode==4{c.count-1-int(r)}else{int(r)}
 if c.mode==4&&r%2==0 {if q>=u64(c.count){return 1,0};if q==u64(index){return 0,1}}
 mut state,mut value:=source_lane(c,j,index,x)
 if c.mode==2&&state!=0 {state=2;value=0}
 if state==1||(value&mask(c.width)==0&&c.flag==1) {return if c.mode==4{2}else{1},0}
 result:=count_reference(c.width,value)
 return state,if c.mode==3&&result!=0{count_reference(c.width,result)}else{result}
}
fn matrix(assembler string,out string,first int,last int,flag int) !Counts {
 mut s:=strings.new_builder(8388608);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 for width in first .. last {for count in 1 .. 17 {s.write_string('declare <${count} x i${width}> @llvm.cttz.v${count}i${width}(<${count} x i${width}>, i1 immarg)\n')
 for form in 0 .. 5 {for mode in 0 .. 5 {
  c:=Case{'case_${cases.len}',width,count,form,mode,flag};cases<<c;mut lanes:=[]string{};for lane in 0 .. count {lanes<<'i32 ${count-1-lane+(lane%2)*count}'}
  mut ops:='%a = insertelement <${count} x i${width}> ${vector(c)}, i${width} %x, i64 %j\n'
  if mode==2 {ops+='%fs = freeze <${count} x i${width}> %a\n'}
  ops+='%n = call <${count} x i${width}> @llvm.cttz.v${count}i${width}(<${count} x i${width}> ${if mode==0 {vector(c)}else if mode==2{'%fs'}else{'%a'}}, i1 ${flag})\n'
  if mode==3 {ops+='%again = call <${count} x i${width}> @llvm.cttz.v${count}i${width}(<${count} x i${width}> %n, i1 ${flag})\n %cmp = icmp ne <${count} x i${width}> %n, zeroinitializer\n %sel = select <${count} x i1> %cmp, <${count} x i${width}> %again, <${count} x i${width}> %n\n'}
  if mode==4 {ops+='%f = freeze <${count} x i${width}> %n\n %b = insertelement <${count} x i${width}> %f, i${width} 1, i64 %q\n %t = shufflevector <${count} x i${width}> %b, <${count} x i${width}> %f, <${count} x i32> <${lanes.join(', ')}>\n'}
  ops+='%v = extractelement <${count} x i${width}> ${if mode==4 {'%t'}else if mode==3 {'%sel'}else{'%n'}}, i64 %r\n';if width!=64{ops+='%wide = zext i${width} %v to i64\n'};result:=if width==64{'%v'}else{'%wide'}
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load i${width}, ptr %src, align 1\n store i8 17, ptr %out\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i64 ${result}, ptr %d, align 1\n ret void }\n')
  s.write_string('define i64 @scalar_${c.name}(i64 %j, i64 %q, i64 %r, i${width} %x) { ${ops}ret i64 ${result} }\n');unsafe{lanes.free()}
 }}}}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out)!;defer{native.close()};mut total:=Counts{shapes:cases.len}
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('width\tlanes\tform\tmode\tj\tq\tr\tx\tvalue')!
 for c in cases {
  f:=fi(ir,c.name);sf:=fi(ir,'scalar_'+c.name);steps:=bodies.scopes[f+1].instructions_count;scalar_steps:=bodies.scopes[sf+1].instructions_count
  profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!;assert profile.steps==steps && profile.arguments[0].minimum_size==24 && profile.arguments[1].minimum_size==(c.width+7)/8 && profile.arguments[2].minimum_size==16;profile.free()
  address:=C.LLVMGetFunctionAddress(native.engine,c.name.str);assert address!=0
  mut indices:=[]u8{len:32};mut input:=[]u8{len:16};mut actual:=[]u8{len:32,init:0xcc};mut reference:=actual.clone();mut bs:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}]
  edges:=[u64(0),u64(c.count-1),u64(c.count),~u64(0),1,2,3,u64(c.count+1)]!
  for sample in 0 .. c.count+2 {
   j:=edges[(sample*3)%8];q:=edges[(sample*5+1)%8];r:=u64(sample);x:=word(c.width,sample);state,value:=expected(c,j,q,r,x)
   for i in 0 .. 8 {indices[1+i]=u8(j>>u32(i*8));indices[9+i]=u8(q>>u32(i*8));indices[17+i]=u8(r>>u32(i*8));input[1+i]=u8((x|~mask(c.width))>>u32(i*8))};for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc}
   args:=[j,q,r,x|~mask(c.width)]
   if state==3 {if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps){panic('undef scalar admitted')};if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps){panic('undef integer admitted')}}else{
    a:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps)!;assert a.kind==.integer && a.bits==64 && a.steps==scalar_steps && a.poison==(state==1) && (a.poison||a.value==value),'${c} ${sample} expected=${value} got=${a}'
    b:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps)!;assert b.bits==64 && b.steps==scalar_steps && b.poison==(state==1) && (b.poison||b.value==value),'${c} ${sample} expected=${value} got=${b}'
   };total.scalar+=2
   if state in [1,3] {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('indeterminate stored')}else{assert err.msg()==if state==3{'AIR vector intrinsic: undef source lane'}else{'AIR memory execution: poison store'}};if state==1{total.poison++}else{total.undef++}}else{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps;if state==0{total.exact++}else{total.choices++}}
   for i,b in actual {assert b==if i==3{u8(17)}else if state in [0,2]&&i>=11&&i<19{u8(value>>u32((i-11)*8))}else{u8(0xcc)},'${c} sample=${sample} byte=${i}'}
   // The VM receives noisy padding. Canonicalize native load padding: LLVM
   // may assume unused bits are zero when legalizing i1/odd-width vectors.
   if state==0 {for i in 0 .. 8 {input[1+i]=u8(x>>u32(i*8))};unsafe{NativeCast(voidptr(address))(&indices[1],&input[1],&reference[3])};assert actual==reference,'${c} sample=${sample}';rows.writeln('${c.width}\t${c.count}\t${c.form}\t${c.mode}\t${j}\t${q}\t${r}\t${x}\t${value}')!};unsafe{args.free()}
  }
  for i in 0 .. actual.len {actual[i]=0xcc};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps-1){panic('short memory budget')};unchanged(actual);if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0],scalar_steps-1){panic('short scalar budget')};if _:=p.run_integer_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0],scalar_steps-1){panic('short integer budget')};total.budgets+=3
  total.metadata+=metadata_checks(ir,stream,pools,bodies,mut p,f,mut bs,actual,steps)!
  unsafe{indices.free();input.free();actual.free();reference.free();bs.free()}
 }
 assert total.shapes==(last-first)*400 && total.scalar==(total.exact+total.choices+total.poison+total.undef)*2 && total.metadata*5==total.shapes*138 && total.budgets==total.shapes*3
 os.write_file(out+'/result.txt','AIR-VECTOR-CTTZ-MATRIX: ${total}\n')!;return total
}
fn bulk_function(width int,flag int) string {
 mut s:=strings.new_builder(16384);s.write_string('define void @bulk_${width}(ptr %unused, ptr %src, ptr %out) { store i8 17, ptr %out\n')
 for lane in 0 .. 16 {s.write_string('%p${lane} = getelementptr i8, ptr %src, i64 ${lane*8}\n %x${lane} = load i${width}, ptr %p${lane}, align 1\n %a${lane} = insertelement <16 x i${width}> ${if lane==0{'poison'}else{'%a'+(lane-1).str()}}, i${width} %x${lane}, i32 ${lane}\n')}
 s.write_string('%n = call <16 x i${width}> @llvm.cttz.v16i${width}(<16 x i${width}> %a15, i1 ${flag})\n')
 for lane in 0 .. 16 {s.write_string('%v${lane} = extractelement <16 x i${width}> %n, i32 ${lane}\n');if width!=64{s.write_string('%z${lane} = zext i${width} %v${lane} to i64\n')};s.write_string('%d${lane} = getelementptr i8, ptr %out, i64 ${8+lane*8}\n store i64 %${if width==64{'v'}else{'z'}}${lane}, ptr %d${lane}, align 1\n')};s.write_string('ret void }\n');return s.str()
}
fn bulk(assembler string,out string,first int,last int,flag int) !int {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n');for width in first .. last {s.write_string('declare <16 x i${width}> @llvm.cttz.v16i${width}(<16 x i${width}>, i1 immarg)\n');s.write_string(bulk_function(width,flag))}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out)!;defer{native.close()};mut checks:=0
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('width\tpattern\ttrailing_zeros')!
 for width in first .. last {
  f:=fi(ir,'bulk_${width}');steps:=bodies.scopes[f+1].instructions_count;profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!;assert profile.steps==steps && profile.arguments[0].minimum_size==0 && profile.arguments[1].minimum_size==120+(width+7)/8 && profile.arguments[2].minimum_size==136;profile.free();address:=C.LLVMGetFunctionAddress(native.engine,('bulk_${width}').str);assert address!=0
  mut unused:=[u8(0)];mut input:=[]u8{len:129};mut actual:=[]u8{len:144,init:0xcc};mut reference:=actual.clone();mut bs:=[airbitcode.IRMemoryBinding{data:unused},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}]
  samples:=if width<=16{int(u64(1)<<u32(width))}else{4096}
  for chunk in 0 .. (samples+15)/16 {
   mut words:=[16]u64{};for lane in 0 .. 16 {k:=(chunk*16+lane)%samples;x:=if width<=16{u64(k)}else{(u64(k)*u64(0x9e3779b97f4a7c15))^(u64(k)<<47)};words[lane]=(if flag==1&&x&mask(width)==0{u64(1)}else{x})|~mask(width);for i in 0 .. 8 {input[1+lane*8+i]=u8(words[lane]>>u32(i*8))}}
   for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc};assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps;for lane in 0 .. 16 {for i in 0 .. 8 {input[1+lane*8+i]=u8((words[lane]&mask(width))>>u32(i*8))}};unsafe{NativeCast(voidptr(address))(unused.data,&input[1],&reference[3])};assert actual==reference,'bulk ${width} chunk=${chunk}'
   for i,b in actual {value:=if i>=11&&i<139{count_reference(width,words[(i-11)/8])}else{u64(0)};assert b==if i==3{u8(17)}else if i>=11&&i<139{u8(value>>u32(((i-11)%8)*8))}else{u8(0xcc)}}
   for x in words {row:='${width}\t${x}\t${count_reference(width,x)}';rows.writeln(row)!;unsafe{row.free()};checks++}
  };unsafe{unused.free();input.free();actual.free();reference.free();bs.free()}
 }
 os.write_file(out+'/result.txt','AIR-VECTOR-CTTZ-BULK: ${checks} exact native lane values, narrow exhaustion/wide deterministic patterns and upper-bit noise PASS\n')!;return checks
}
fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};mut s:=strings.new_builder(16777216);s.write_string('declare <${count} x i16> @llvm.cttz.v${count}i16(<${count} x i16>, i1 immarg)\n')
 {s.write_string('define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')};for i in 0 .. if storage&&over{4097}else{4096}{s.write_string('%n${i} = call <${count} x i16> @llvm.cttz.v${count}i16(<${count} x i16> zeroinitializer, i1 false)\n')};if !storage{for i in 0 .. if over{54309}else{54308}{s.write_string('%x${i} = extractelement <16 x i16> %n4095, i32 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage{'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'}
 if over {
  if name=='memory' {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,name),mut bs,70000){panic('memory limit')}else{assert err.msg()==diagnostic,err.msg()};unchanged(output)}
  else if name=='void' {if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,name),[],70000){panic('void limit')}else{assert err.msg()==diagnostic,err.msg()}}
  else {if _:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,name),[],70000){panic('scalar limit')}else{assert err.msg()==diagnostic,err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,fi(ir,name),[],70000){panic('integer limit')}else{assert err.msg()==diagnostic,err.msg()}}
 } else {
  steps:=if storage{4097}else{58405}
  if name=='memory' {assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,name),mut bs,70000)!.steps==steps+1;assert output[0]==17}
  else if name=='void' {assert p.run_void_function(ir,stream,pools,bodies,fi(ir,name),[],70000)!.steps==steps}
  else {assert p.run_scalar_function(ir,stream,pools,bodies,fi(ir,name),[],70000)!.steps==steps;assert p.run_integer_function(ir,stream,pools,bodies,fi(ir,name),[],70000)!.steps==steps}
 };unsafe{output.free();bs.free()}
 os.write_file(out+'/result.txt','AIR-VECTOR-CTTZ-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}
fn main() {
 assert os.args.len==3;out:=os.abs_path(os.args[2]);assert !os.exists(out)&&!out.starts_with(os.getwd()+'/');os.mkdir_all(out)!;mut total:=Counts{};mut values:=0
 for flag in 0 .. 2 {for chunk in 0 .. 16 {total.add(matrix(os.args[1],out+'/matrix-${flag}-${chunk}',chunk*4+1,(chunk+1)*4+1,flag)!);values+=bulk(os.args[1],out+'/bulk-${flag}-${chunk}',chunk*4+1,(chunk+1)*4+1,flag)!}}
 assert total.shapes==51200&&total.scalar==1075200&&total.metadata==1413120&&total.budgets==153600&&values==655424
 controls(os.args[1],out+'/controls')!
 for storage in [false,true]{for over in [false,true]{for name in ['memory','void','scalar']{limits(os.args[1],out+'/${if storage{'storage'}else{'work'}}-${if over{'over'}else{'boundary'}}-${name}',storage,over,name)!}}}
 result:='AIR-VECTOR-CTTZ-MATRIX: ${total}\nAIR-VECTOR-CTTZ-BULK: ${values} exact defined native lane values PASS; true-flag zero patterns use one; independent poison checks remain in matrix/units\n'+os.read_file(out+'/controls/result.txt')!+'AIR-VECTOR-CTTZ: 16 exact shared work/storage boundary checks through four APIs PASS\n';os.write_file(out+'/result.txt',result)!;print(result)
}
fn metadata_checks(ir airbitcode.IRModule, stream airbitcode.Stream,pools airbitcode.IRConstantPools,bodies airbitcode.IRFunctionBodies,mut p airbitcode.IRTypedProgram,f int,mut bs []airbitcode.IRMemoryBinding,output []u8,steps int) !int {
 scope:=bodies.scopes[f+1]; mut checks:=0
 for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {
  op:=p.instructions[index]; if stream.records[bodies.instructions[index].record].code!=34 {continue}
  for changed in [airbitcode.IRTypedInstruction{...op,flags:0},airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,opcode:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,callee_function:ir.functions.len},airbitcode.IRTypedInstruction{...op,operands_count:0},airbitcode.IRTypedInstruction{...op,operands_count:1},airbitcode.IRTypedInstruction{...op,operands_count:4},airbitcode.IRTypedInstruction{...op,result_type:-1},airbitcode.IRTypedInstruction{...op,targets_count:1},airbitcode.IRTypedInstruction{...op,indices_count:1}] {p.instructions[index]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('metadata admitted')}; unchanged(output);checks++}; p.instructions[index]=op
  for operand in 0 .. op.operands_count { slot:=op.operands_start+operand; original:=p.operands[slot]; changes:=if operand==0 {[airbitcode.IRTypedOperand{...original,number:~u32(0)},airbitcode.IRTypedOperand{...original,type_index:-1}]} else {[airbitcode.IRTypedOperand{...original,number:~u32(0)},airbitcode.IRTypedOperand{...original,number:bodies.instructions[index].next_value},airbitcode.IRTypedOperand{...original,type_index:-1}]}; for changed in changes {p.operands[slot]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('source admitted')}; unchanged(output);checks++}; p.operands[slot]=original; unsafe{changes.free()} }
 }
 return checks
}
fn controls(assembler string,out string) ! {
 mut s:=strings.new_builder(2097152);s.write_string('target datalayout = "e-p:64:64"\n');tags:=['arg','result','poison','undef'];mut checks:=0
 for width in 1 .. 65 {t:='<2 x i${width}>';name:='llvm.cttz.v2i${width}';s.write_string('declare ${t} @${name}(${t}, i1 immarg)\n declare ${t} @reserved_${width}(${t}, i1)\n')
  for kind in ['memory','void','scalar'] {ret:=if kind=='scalar'{'i64 0'}else{'void'};signature:=if kind=='memory'{'ptr %out'}else{''};marker:=if kind=='memory'{'store i8 17, ptr %out\n'}else{''}
   s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @raw_${width}_${kind}(${signature}) { ${marker}%a = call ${t} @${name}(${t} zeroinitializer, i1 false)\n %b = call ${t} @${name}(${t} zeroinitializer, i1 true)\n ret ${ret} }\n')
   for tag in tags {sig:=if kind=='memory'{'ptr %src, ptr %out'}else{'i1 %flag'};pre:=if kind=='memory'{'%flag = load i1, ptr %src, align 1\n '+marker}else{''};v:=if tag=='arg'{'%flag'}else if tag=='result'{'%changed'}else{tag};s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @bad_${width}_${tag}_${kind}(${sig}) { ${pre}%a = call ${t} @reserved_${width}(${t} zeroinitializer, i1 false)\n %changed = xor i1 %flag, false\n %b = call ${t} @reserved_${width}(${t} zeroinitializer, i1 ${v})\n ret ${ret} }\n')}
  }
  s.write_string('define i64 @flags_${width}() { %a = call ${t} @${name}(${t} zeroinitializer, i1 false)\n %b = call ${t} @${name}(${t} <i${width} 1, i${width} 1>, i1 true)\n %x = extractelement ${t} %a, i32 0\n %y = extractelement ${t} %b, i32 0\n '+if width==64{''}else{'%xx = zext i${width} %x to i64\n %yy = zext i${width} %y to i64\n'}+'%sum = add i64 %${if width==64{'x'}else{'xx'}}, %${if width==64{'y'}else{'yy'}}\n ret i64 %sum }\n')
 }
 s.write_string('declare <2 x i65> @llvm.cttz.v2i65(<2 x i65>, i1 immarg)\n define void @cold(ptr %out) { store i8 17, ptr %out\n br i1 true, label %done, label %bad\n done: ret void\n bad: %n = call <2 x i65> @llvm.cttz.v2i65(<2 x i65> zeroinitializer, i1 false)\n ret void }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut funcs:=ir.functions.clone();defer{unsafe{funcs.free()}};view:=airbitcode.IRModule{...ir,functions:funcs};mut words:=pools.words.clone();defer{unsafe{words.free()}};bad_pools:=airbitcode.IRConstantPools{...pools,words:words}
 for width in 1 .. 65 {
  f:=fi(ir,'flags_${width}');a:=p.run_scalar_function(ir,stream,pools,bodies,f,[],20)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,[],20)!;assert !a.poison&&!b.poison&&a.value==u64(width)&&b.value==a.value;checks+=2
  alias:=fi(ir,'reserved_${width}');original:=funcs[alias];funcs[alias]=airbitcode.IRFunction{...original,name:'llvm.cttz.v2i${width}'}
  for tag in tags {for kind in ['memory','void','scalar'] {
   f2:=fi(ir,'bad_${width}_${tag}_${kind}');scope:=bodies.scopes[f2+1];mut first:=-1;mut second:=-1
   for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34{continue};if first<0{first=op.operands_start+2}else{assert second<0;second=op.operands_start+2}}
   assert first>=0&&second>=0;before:=p.operands[second];p.operands[second]=airbitcode.IRTypedOperand{...before,number:p.operands[first].number}
   mut input:=[u8(1)];mut output:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:input},airbitcode.IRMemoryBinding{data:output,writable:true}]
   if kind=='memory'{p.run_memory_function(view,stream,pools,bodies,f2,mut bs,50)!;assert output[0]==17;output[0]=0xcc}else if kind=='void'{p.run_void_function(view,stream,pools,bodies,f2,[u64(1)],50)!}else{assert p.run_scalar_function(view,stream,pools,bodies,f2,[u64(1)],50)!.value==0;assert p.run_integer_function(view,stream,pools,bodies,f2,[u64(1)],50)!.value==0};checks+=if kind=='scalar'{2}else{1};p.operands[second]=before
   if kind=='memory'{if _:=p.run_memory_function(view,stream,pools,bodies,f2,mut bs,50){panic('cached flag memory admitted')};unchanged(output)}else if kind=='void'{if _:=p.run_void_function(view,stream,pools,bodies,f2,[u64(1)],50){panic('cached flag void admitted')}}else{if _:=p.run_scalar_function(view,stream,pools,bodies,f2,[u64(1)],50){panic('cached flag scalar admitted')};if _:=p.run_integer_function(view,stream,pools,bodies,f2,[u64(1)],50){panic('cached flag integer admitted')}};checks+=if kind=='scalar'{2}else{1};unsafe{input.free();output.free();bs.free()}
  }};funcs[alias]=original
  for kind in ['memory','void','scalar'] {f2:=fi(ir,'raw_${width}_${kind}');scope:=bodies.scopes[f2+1];mut constant:=-1
   for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count{op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code==34{v:=pools.lookup(f2+1,p.operands[op.operands_start+2].number)!;if pools.scalar_bits(v.constant_index)! == 1{constant=v.constant_index}}};assert constant>=0;slot:=pools.constants[constant].words_start;before:=words[slot]
   mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
   if kind=='memory'{p.run_memory_function(ir,stream,pools,bodies,f2,mut bs,50)!;assert output[0]==17;output[0]=0xcc}else if kind=='void'{p.run_void_function(ir,stream,pools,bodies,f2,[],50)!}else{p.run_scalar_function(ir,stream,pools,bodies,f2,[],50)!;p.run_integer_function(ir,stream,pools,bodies,f2,[],50)!};checks+=if kind=='scalar'{2}else{1};words[slot]=2
   if kind=='memory'{if _:=p.run_memory_function(ir,stream,bad_pools,bodies,f2,mut bs,50){panic('raw flag memory')};unchanged(output)}else if kind=='void'{if _:=p.run_void_function(ir,stream,bad_pools,bodies,f2,[],50){panic('raw flag void')}}else{if _:=p.run_scalar_function(ir,stream,bad_pools,bodies,f2,[],50){panic('raw flag scalar')};if _:=p.run_integer_function(ir,stream,bad_pools,bodies,f2,[],50){panic('raw flag integer')}};checks+=if kind=='scalar'{2}else{1};words[slot]=before;unsafe{output.free();bs.free()}
  }
 }
 mut values:=stream.values.clone();defer{unsafe{values.free()}};bad_stream:=airbitcode.Stream{...stream,values:values};mut group:=-1;for r in stream.records{if stream.blocks[r.block].id==10&&r.code==3&&r.values_count==4&&stream.values[r.values_start+1]==2&&stream.values[r.values_start+3]==60{group=r.values_start;break}};assert group>=0
 for change in 0 .. 5{values[group+1]=2;values[group+2]=0;values[group+3]=60;if change<3{values[group+1]=[u64(0),1,3][change]}else if change==3{values[group+3]=54}else{values[group+2]=1}
  for awidth in [1,7,32,64] {mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,bad_stream,pools,bodies,fi(ir,'raw_${awidth}_memory'),mut bs,50){panic('attribute memory')};unchanged(output);if _:=p.run_void_function(ir,bad_stream,pools,bodies,fi(ir,'raw_${awidth}_void'),[],50){panic('attribute void')};if _:=p.run_scalar_function(ir,bad_stream,pools,bodies,fi(ir,'raw_${awidth}_scalar'),[],50){panic('attribute scalar')};if _:=p.run_integer_function(ir,bad_stream,pools,bodies,fi(ir,'raw_${awidth}_scalar'),[],50){panic('attribute integer')};checks+=4;unsafe{output.free();bs.free()}}
 }
 mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'cold'),mut bs,50){panic('cold width')};unchanged(output);checks++
 assert checks==2769;os.write_file(out+'/result.txt','AIR-VECTOR-CTTZ-CONTROLS: ${checks} both-flag cache results, repaired positive baselines, cached nonconstant/SSA/poison/undef flags, raw flag corruptions, immarg slot/enum/encoding and cold-width checks PASS\n')!
}
