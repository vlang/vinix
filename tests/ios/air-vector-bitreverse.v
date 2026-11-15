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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-bitreverse-intrinsics'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
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
fn reverse_reference(width int,value u64) u64 {return bitops.reverse_64(value&mask(width))>>u32(64-width)}
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
struct Case {name string width int count int form int mode int}
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
 for lane in 0 .. c.count {state,_:=source_lane(c,j,lane,x);if state==3 && c.mode!=2{return 3,0}}
 if r>=u64(c.count){return 1,0};index:=if c.mode==4{c.count-1-int(r)}else{int(r)}
 if c.mode==4 && r%2==0 {if q>=u64(c.count){return 1,0};if q==u64(index){return 0,1}}
 mut state,mut value:=source_lane(c,j,index,x)
 if c.mode==4 && state!=0{return 2,0};if c.mode==2 && state!=0{state=2;value=0}
 result:=reverse_reference(c.width,value);return state,if c.mode==3 {reverse_reference(c.width,result)}else{result}
}
fn matrix(assembler string,out string,first int,last int) !Counts {
 mut s:=strings.new_builder(8388608);s.write_string('target datalayout = "e-p:64:64"\n');mut cases:=[]Case{}
 for width in first .. last {for count in 1 .. 17 {s.write_string('declare <${count} x i${width}> @llvm.bitreverse.v${count}i${width}(<${count} x i${width}>)\n')
 for form in 0 .. 5 {for mode in 0 .. 5 {
  c:=Case{'case_${cases.len}',width,count,form,mode};cases<<c;mut lanes:=[]string{};for lane in 0 .. count {lanes<<'i32 ${count-1-lane+(lane%2)*count}'}
  mut ops:='%a = insertelement <${count} x i${width}> ${vector(c)}, i${width} %x, i64 %j\n'
  if mode==2 {ops+='%fs = freeze <${count} x i${width}> %a\n'}
  ops+='%n = call <${count} x i${width}> @llvm.bitreverse.v${count}i${width}(<${count} x i${width}> ${if mode==0 {vector(c)}else if mode==2{'%fs'}else{'%a'}})\n'
  if mode==3 {ops+='%again = call <${count} x i${width}> @llvm.bitreverse.v${count}i${width}(<${count} x i${width}> %n)\n %cmp = icmp ne <${count} x i${width}> %n, zeroinitializer\n %sel = select <${count} x i1> %cmp, <${count} x i${width}> %again, <${count} x i${width}> %n\n'}
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
 assert total.shapes==(last-first)*400 && total.scalar==(total.exact+total.choices+total.poison+total.undef)*2 && total.metadata==total.shapes*24 && total.budgets==total.shapes*3
 os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-MATRIX: ${total}\n')!;return total
}
fn bulk_function(width int) string {
 mut s:=strings.new_builder(16384);s.write_string('define void @bulk_${width}(ptr %unused, ptr %src, ptr %out) { store i8 17, ptr %out\n')
 for lane in 0 .. 16 {s.write_string('%p${lane} = getelementptr i8, ptr %src, i64 ${lane*8}\n %x${lane} = load i${width}, ptr %p${lane}, align 1\n %a${lane} = insertelement <16 x i${width}> ${if lane==0{'poison'}else{'%a'+(lane-1).str()}}, i${width} %x${lane}, i32 ${lane}\n')}
 s.write_string('%n = call <16 x i${width}> @llvm.bitreverse.v16i${width}(<16 x i${width}> %a15)\n')
 for lane in 0 .. 16 {s.write_string('%v${lane} = extractelement <16 x i${width}> %n, i32 ${lane}\n');if width!=64{s.write_string('%z${lane} = zext i${width} %v${lane} to i64\n')};s.write_string('%d${lane} = getelementptr i8, ptr %out, i64 ${8+lane*8}\n store i64 %${if width==64{'v'}else{'z'}}${lane}, ptr %d${lane}, align 1\n')};s.write_string('ret void }\n');return s.str()
}
fn bulk(assembler string,out string,first int,last int) !int {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n');for width in first .. last {s.write_string('declare <16 x i${width}> @llvm.bitreverse.v16i${width}(<16 x i${width}>)\n');s.write_string(bulk_function(width))}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out)!;defer{native.close()};mut checks:=0
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('width\tpattern\treversed')!
 for width in first .. last {
  f:=fi(ir,'bulk_${width}');steps:=bodies.scopes[f+1].instructions_count;profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!;assert profile.steps==steps && profile.arguments[0].minimum_size==0 && profile.arguments[1].minimum_size==120+(width+7)/8 && profile.arguments[2].minimum_size==136;profile.free();address:=C.LLVMGetFunctionAddress(native.engine,('bulk_${width}').str);assert address!=0
  mut unused:=[u8(0)];mut input:=[]u8{len:129};mut actual:=[]u8{len:144,init:0xcc};mut reference:=actual.clone();mut bs:=[airbitcode.IRMemoryBinding{data:unused},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}]
  samples:=if width<=16{int(u64(1)<<u32(width))}else{65536}
  for chunk in 0 .. (samples+15)/16 {
   mut words:=[16]u64{};for lane in 0 .. 16 {k:=(chunk*16+lane)%samples;x:=if width<=16{u64(k)}else{(u64(k)*u64(0x9e3779b97f4a7c15))^(u64(k)<<47)};words[lane]=x|~mask(width);for i in 0 .. 8 {input[1+lane*8+i]=u8(words[lane]>>u32(i*8))}}
   for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc};assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps;for lane in 0 .. 16 {for i in 0 .. 8 {input[1+lane*8+i]=u8((words[lane]&mask(width))>>u32(i*8))}};unsafe{NativeCast(voidptr(address))(unused.data,&input[1],&reference[3])};assert actual==reference,'bulk ${width} chunk=${chunk}'
   for i,b in actual {value:=if i>=11&&i<139{reverse_reference(width,words[(i-11)/8])}else{u64(0)};assert b==if i==3{u8(17)}else if i>=11&&i<139{u8(value>>u32(((i-11)%8)*8))}else{u8(0xcc)}}
   for x in words {row:='${width}\t${x}\t${reverse_reference(width,x)}';rows.writeln(row)!;unsafe{row.free()};checks++}
  };unsafe{unused.free();input.free();actual.free();reference.free();bs.free()}
 }
 os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-BULK: ${checks} exact native lane values, narrow exhaustion/wide deterministic patterns and upper-bit noise PASS\n')!;return checks
}
fn controls(assembler string,out string) ! {
 mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n');modes:=['raw','source','result','discard','old','chain'];guards:=['tail','attribute','argument','load','phi','count','width','scalable','alias'];types:=['good','source_width','source_count','source_float','return_width','return_count','return_scalar']
 for width in [1,7,32,64] {
  t:='<2 x i${width}>';name:='llvm.bitreverse.v2i${width}';s.write_string('declare ${t} @${name}(${t})\n declare ${t} @duplicate_${width}(${t})\n')
  for state in ['defined','poison','undef'] {for mode in modes {
   source:=if state=='defined'{'<i${width} ${mask(width)}, i${width} 0>'}else{state};pre:=if mode=='source'{'%s = freeze ${t} ${source}\n'}else{''};post:=if mode=='result'{'%f = freeze ${t} %n\n'}else if mode=='old'{'%changed = insertelement ${t} %n, i${width} 0, i32 0\n'}else if mode=='chain'{'%again = call ${t} @${name}(${t} %n)\n'}else{''}
   extract:=if mode=='discard'{''}else{'%v = extractelement ${t} ${if mode=='result'{'%f'}else if mode=='chain'{'%again'}else{'%n'}}, i32 0\n '+if width==64{''}else{'%z = zext i${width} %v to i64\n'}+'%d = getelementptr i8, ptr %out, i64 8\n store i64 %${if width==64{'v'}else{'z'}}, ptr %d, align 1\n'}
   old:=if mode=='old'{'%v2 = extractelement ${t} %changed, i32 0\n '+if width==64{''}else{'%z2 = zext i${width} %v2 to i64\n'}+'%d2 = getelementptr i8, ptr %out, i64 16\n store i64 %${if width==64{'v2'}else{'z2'}}, ptr %d2, align 1\n'}else{''}
   s.write_string('define void @state_${width}_${state}_${mode}(ptr %out) { store i8 17, ptr %out\n ${pre}%n = call ${t} @${name}(${t} ${if mode=='source'{'%s'}else{source}})\n ${post}${extract}${old}ret void }\n')
  }}
  for guard in guards {
   vt:=if guard=='count'{'<17 x i${width}>'}else if guard=='width'{'<2 x i65>'}else if guard=='scalable'{'<vscale x 2 x i${width}>'}else{t};callee:=if guard=='count'{'llvm.bitreverse.v17i${width}'}else if guard=='width'{'llvm.bitreverse.v2i65'}else if guard=='scalable'{'llvm.bitreverse.nxv2i${width}'}else if guard=='alias'{'air.bitreverse.v2i${width}'}else{name}
   if guard in ['count','scalable','alias'] {s.write_string('declare ${vt} @${callee}(${vt})\n')}
   sig:=if guard=='argument'{'${t} %a, ptr %out'}else if guard=='load'{'ptr %src, ptr %out'}else{'ptr %out'};pre:=if guard=='load'{'%a = load ${t}, ptr %src, align 1\n'}else if guard=='phi'{'br label %body\n body: %a = phi ${t} [zeroinitializer, %entry]\n'}else if guard=='width'{'br i1 true, label %done, label %cold\n done: ret void\n cold:'}else{''}
   s.write_string('define void @guard_${width}_${guard}(${sig}) { entry: store i8 17, ptr %out\n ${pre}%n = ${if guard=='tail'{'tail '}else{''}}call ${vt} @${callee}(${vt} ${if guard in ['argument','load','phi']{'%a'}else{'zeroinitializer'}})${if guard=='attribute'{' #1'}else{''}}\n ret void }\n')
  }
  for tag in types {src:=if tag=='source_width'{'<2 x i${width+1}>'}else if tag=='source_count'{'<3 x i${width}>'}else if tag=='source_float'{'<2 x float>'}else{t};dst:=if tag=='return_width'{'<2 x i${width+1}>'}else if tag=='return_count'{'<3 x i${width}>'}else if tag=='return_scalar'{'i${width}'}else{t};s.write_string('declare ${dst} @typed_${width}_${tag}(${src})\n')
   for kind in ['memory','void','scalar'] {s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @typed_${width}_${tag}_${kind}(${if kind=='memory'{'ptr %out'}else{''}}) { ${if kind=='memory'{'store i8 17, ptr %out\n'}else{''}}%n = call ${dst} @typed_${width}_${tag}(${src} zeroinitializer)\n ret ${if kind=='scalar'{'i64 0'}else{'void'}} }\n')}
  }
  for kind in ['memory','void','scalar'] {s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @duplicate_${width}_${kind}(${if kind=='memory'{'ptr %out'}else{''}}) { ${if kind=='memory'{'store i8 17, ptr %out\n'}else{''}}%a = call ${t} @${name}(${t} zeroinitializer)\n %b = call ${t} @duplicate_${width}(${t} zeroinitializer)\n ret ${if kind=='scalar'{'i64 0'}else{'void'}} }\n')}
  s.write_string('define i64 @loop_${width}(i64 %limit) { entry: br label %body\n body: %i = phi i64 [0, %entry], [%next, %body]\n %sum = phi i64 [0, %entry], [%added, %body]\n '+if width==64{''}else{'%short = trunc i64 %i to i${width}\n'}+'%a = insertelement ${t} poison, i${width} %${if width==64{'i'}else{'short'}}, i32 0\n %n = call ${t} @${name}(${t} %a)\n %v = extractelement ${t} %n, i32 0\n '+if width==64{''}else{'%z = zext i${width} %v to i64\n'}+'%added = add i64 %sum, %${if width==64{'v'}else{'z'}}\n %next = add i64 %i, 1\n %c = icmp ult i64 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i64 %added }\n')
 }
 for width in [1,7,32,64] {
  t:='<2 x i${width}>';s.write_string('declare ${t} @llvm.ctpop.v2i${width}(${t})\n')
  for order in 0 .. 2 {
   calls:=if order==0{'%r = call '+t+' @llvm.bitreverse.v2i${width}('+t+' %a)\n %p = call '+t+' @llvm.ctpop.v2i${width}('+t+' %r)\n %q = call '+t+' @llvm.ctpop.v2i${width}('+t+' %a)\n'}else{'%q = call '+t+' @llvm.ctpop.v2i${width}('+t+' %a)\n %r = call '+t+' @llvm.bitreverse.v2i${width}('+t+' %a)\n %p = call '+t+' @llvm.ctpop.v2i${width}('+t+' %r)\n'}
   s.write_string('define i64 @families_${width}_${order}(i${width} %x) { %a = insertelement ${t} zeroinitializer, i${width} %x, i32 0\n ${calls}%again = call ${t} @llvm.bitreverse.v2i${width}(${t} %r)\n %equal = icmp eq ${t} %again, %a\n %counts = icmp eq ${t} %p, %q\n %both = and <2 x i1> %equal, %counts\n %v = extractelement <2 x i1> %both, i32 0\n %z = zext i1 %v to i64\n ret i64 %z }\n')
  }
 }
 s.write_string('declare <2 x i65> @llvm.bitreverse.v2i65(<2 x i65>)\n attributes #1 = { nounwind }\n declare <2 x i1> @llvm.is.fpclass.v2f32(<2 x float>, i32 immarg)\n define i64 @mixed() { %a = call <2 x i1> @llvm.is.fpclass.v2f32(<2 x float> zeroinitializer, i32 96)\n %b = call <2 x i1> @llvm.bitreverse.v2i1(<2 x i1> %a)\n %v = extractelement <2 x i1> %b, i32 0\n %z = zext i1 %v to i64\n ret i64 %z }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};mut checks:=0
 for width in [1,7,32,64] {
  for state in ['defined','poison','undef'] {for mode in modes {
   mut output:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}];f:=fi(ir,'state_${width}_${state}_${mode}');bad:=(state=='undef'&&mode!='source')||(state=='poison'&&mode !in ['source','result','discard'])
   if bad {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100){panic('state admitted')}}else{p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100)!}
   value:=if state=='defined'{mask(width)}else{u64(0)};result:=if mode=='chain'{reverse_reference(width,value)}else{value}
   for i,b in output {assert b==if i==3{u8(17)}else if !bad&&mode!='discard'&&i>=11&&i<19{u8(result>>u32((i-11)*8))}else if !bad&&mode=='old'&&i>=19&&i<27{u8(0)}else{u8(0xcc)},'${width} ${state} ${mode} byte=${i}'};checks++;unsafe{output.free();bs.free()}
  }}
  for guard in guards {mut output:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if guard in ['argument','load']{bs<<airbitcode.IRMemoryBinding{data:output}};if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'guard_${width}_${guard}'),mut bs,100){panic('guard admitted')};unchanged(output);checks++;unsafe{output.free();bs.free()}}
  for tag in types {callee:=fi(ir,'typed_${width}_${tag}');original:=functions[callee];functions[callee]=airbitcode.IRFunction{...original,name:'llvm.bitreverse.v2i${width}'};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
   if tag=='good' {p.run_memory_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_memory'),mut bs,100)!;assert output[0]==17;p.run_void_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_void'),[],100)!;assert p.run_scalar_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_scalar'),[],100)!.value==0;assert p.run_integer_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_scalar'),[],100)!.value==0}else{
    if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_memory'),mut bs,100){panic('typed memory admitted')};unchanged(output);if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_void'),[],100){panic('typed void admitted')};if _:=p.run_scalar_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_scalar'),[],100){panic('typed scalar admitted')};if _:=p.run_integer_function(view,stream,pools,bodies,fi(ir,'typed_${width}_${tag}_scalar'),[],100){panic('typed integer admitted')}
   };functions[callee]=original;checks+=4;unsafe{output.free();bs.free()}
  }
  duplicate:=fi(ir,'duplicate_${width}');original:=functions[duplicate];functions[duplicate]=airbitcode.IRFunction{...original,name:'llvm.bitreverse.v2i${width}'};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}]
  if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate_${width}_memory'),mut bs,100){panic('duplicate memory')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration'};unchanged(output);if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'duplicate_${width}_void'),[],100){panic('duplicate void')};if _:=p.run_scalar_function(view,stream,pools,bodies,fi(ir,'duplicate_${width}_scalar'),[],100){panic('duplicate scalar')};if _:=p.run_integer_function(view,stream,pools,bodies,fi(ir,'duplicate_${width}_scalar'),[],100){panic('duplicate integer')};functions[duplicate]=original;checks+=4;unsafe{output.free();bs.free()}
  for n in [u64(1),2,3,16,257,513]! {mut expected:=u64(0);for i in 0 .. int(n){expected+=reverse_reference(width,u64(i))};a:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${width}'),[n],10000)!;assert !a.poison&&a.value==expected;b:=p.run_integer_function(ir,stream,pools,bodies,fi(ir,'loop_${width}'),[n],10000)!;assert !b.poison&&b.value==expected;checks+=2}
 }
 for width in [1,7,32,64] {for order in 0 .. 2 {f:=fi(ir,'families_${width}_${order}');steps:=bodies.scopes[f+1].instructions_count;for sample in 0 .. 20 {x:=word(width,sample)|~mask(width);a:=p.run_scalar_function(ir,stream,pools,bodies,f,[x],steps)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,[x],steps)!;assert !a.poison&&!b.poison&&a.value==1&&b.value==1&&a.steps==steps&&b.steps==steps;checks+=2}}}
 mixed:=fi(ir,'mixed');assert p.run_scalar_function(ir,stream,pools,bodies,mixed,[],5)!.value==1;if _:=p.run_integer_function(ir,stream,pools,bodies,mixed,[],5){panic('floating classification entered integer-only API')};checks+=2
 assert checks==606;os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-CONTROLS: ${checks} state/freeze/discard/snapshot/chain, signature, unsupported profile, duplicate, changing-source loop cross-family cache and mixed/integer isolation checks PASS\n')!
}
fn all_shapes(assembler string,out string, first int, last int) ! {
 mut s:=strings.new_builder(1048576)
 for width in first .. last {for count in 1 .. 17 {s.write_string('declare <${count} x i${width}> @llvm.bitreverse.v${count}i${width}(<${count} x i${width}>)\n')}};s.write_string('define i64 @all_shapes() {\n');mut index:=0
 for width in first .. last {for count in 1 .. 17 {mut lanes:=[]string{};for _ in 0 .. count{lanes<<'i${width} ${mask(width)}'};s.write_string('%n${index} = call <${count} x i${width}> @llvm.bitreverse.v${count}i${width}(<${count} x i${width}> <${lanes.join(', ')}>)\n %v${index} = extractelement <${count} x i${width}> %n${index}, i32 0\n');if width!=64{s.write_string('%z${index} = zext i${width} %v${index} to i64\n')};s.write_string('%s${index} = add i64 ${if index==0{'0'}else{'%s'+(index-1).str()}}, %${if width==64{'v'}else{'z'}}${index}\n');index++;unsafe{lanes.free()}}};s.write_string('ret i64 %s${index-1} }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};f:=fi(ir,'all_shapes');steps:=bodies.scopes[f+1].instructions_count;if first==1&&last==65 {if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],steps){panic('unbounded attribute scan')}else{assert err.msg()=='AIR intrinsic: attribute work limit'};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],steps){panic('unbounded integer attribute scan')}else{assert err.msg()=='AIR intrinsic: attribute work limit'};os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-CACHE: full1024 overload module rejects shared attribute work limit through both APIs PASS\n')!;return};mut sum:=u64(0);for width in first .. last{sum+=mask(width)*16};a:=p.run_scalar_function(ir,stream,pools,bodies,f,[],steps)!;b:=p.run_integer_function(ir,stream,pools,bodies,f,[],steps)!;assert !a.poison&&!b.poison&&a.value==sum&&b.value==sum&&a.steps==steps&&b.steps==steps;os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-CACHE: ${index} declarations together, widths ${first}..${last-1}, mixed and integer APIs, exact sum ${sum} PASS\n')!
}
fn attributes(assembler string,out string) ! {
 mut s:=strings.new_builder(8192);s.write_string('declare <2 x i1> @llvm.is.fpclass.v2f16(<2 x half>, i32 immarg)\n')
 for width in [1,7,32,64] {s.write_string('declare <2 x i${width}> @llvm.bitreverse.v2i${width}(<2 x i${width}>)\n');for kind in ['memory','void','scalar']{s.write_string('define ${if kind=='scalar'{'i64'}else{'void'}} @check_${width}_${kind}(${if kind=='memory'{'ptr %out'}else{''}}) { ${if kind=='memory'{'store i8 17, ptr %out\n'}else{''}}%n = call <2 x i${width}> @llvm.bitreverse.v2i${width}(<2 x i${width}> zeroinitializer)\n ret ${if kind=='scalar'{'i64 0'}else{'void'}} }\n')}}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 for width in [1,7,32,64] {profile:=p.memory_function_profile(ir,stream,pools,bodies,fi(ir,'check_${width}_memory'))!;profile.free();p.run_void_function(ir,stream,pools,bodies,fi(ir,'check_${width}_void'),[],2)!;assert p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'check_${width}_scalar'),[],2)!.value==0;assert p.run_integer_function(ir,stream,pools,bodies,fi(ir,'check_${width}_scalar'),[],2)!.value==0}
 mut values:=stream.values.clone();defer{unsafe{values.free()}};mutated:=airbitcode.Stream{...stream,values:values};mut group:=-1;for record in stream.records{if stream.blocks[record.block].id==10&&record.code==3&&record.values_count==4&&stream.values[record.values_start+1]==2&&stream.values[record.values_start+3]==60{group=record.values_start;break}};assert group>=0
 class_record:=stream.records[ir.functions[fi(ir,'llvm.is.fpclass.v2f16')].record]
 for width in [1,7,32,64] {record:=stream.records[ir.functions[fi(ir,'llvm.bitreverse.v2i${width}')].record];slot:=record.values_start+6;original:=values[slot];values[slot]=stream.values[class_record.values_start+6]
  for position in 0 .. 3 {values[group+1]=u64(position);mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,mutated,pools,bodies,fi(ir,'check_${width}_memory'),mut bs,100){panic('bitreverse immarg memory')};unchanged(output);if _:=p.run_void_function(ir,mutated,pools,bodies,fi(ir,'check_${width}_void'),[],100){panic('bitreverse immarg void')};if _:=p.run_scalar_function(ir,mutated,pools,bodies,fi(ir,'check_${width}_scalar'),[],100){panic('bitreverse immarg scalar')};if _:=p.run_integer_function(ir,mutated,pools,bodies,fi(ir,'check_${width}_scalar'),[],100){panic('bitreverse immarg integer')};unsafe{output.free();bs.free()}}
  values[group+1]=stream.values[group+1];values[slot]=original
 };os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-ATTRIBUTES: canonical acceptance through four APIs and 48 parameter/return immarg refusals before writes PASS\n')!
}
fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};mut s:=strings.new_builder(16777216);s.write_string('declare <${count} x i16> @llvm.bitreverse.v${count}i16(<${count} x i16>)\n')
 {s.write_string('define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')};for i in 0 .. if storage&&over{4097}else{4096}{s.write_string('%n${i} = call <${count} x i16> @llvm.bitreverse.v${count}i16(<${count} x i16> zeroinitializer)\n')};if !storage{for i in 0 .. if over{54309}else{54308}{s.write_string('%x${i} = extractelement <16 x i16> %n4095, i32 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')}
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
 os.write_file(out+'/result.txt','AIR-VECTOR-BITREVERSE-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}
fn main() {
 assert os.args.len==3;out:=os.abs_path(os.args[2]);assert !os.exists(out)&&!out.starts_with(os.getwd()+'/');os.mkdir_all(out)!;mut total:=Counts{};mut values:=0
 for chunk in 0 .. 16 {total.add(matrix(os.args[1],out+'/matrix-${chunk}',chunk*4+1,(chunk+1)*4+1)!);values+=bulk(os.args[1],out+'/bulk-${chunk}',chunk*4+1,(chunk+1)*4+1)!}
 assert total.shapes==25600&&total.scalar==537600&&total.metadata==614400&&total.budgets==76800&&values==3276832
 controls(os.args[1],out+'/controls')!;all_shapes(os.args[1],out+'/all-shapes',1,65)!;for chunk in 0 .. 8{all_shapes(os.args[1],out+'/cache-${chunk}',chunk*8+1,(chunk+1)*8+1)!};attributes(os.args[1],out+'/attributes')!;for storage in [false,true]{for over in [false,true]{for name in ['memory','void','scalar']{limits(os.args[1],out+'/${if storage{'storage'}else{'work'}}-${if over{'over'}else{'boundary'}}-${name}',storage,over,name)!}}}
 result:='AIR-VECTOR-BITREVERSE-MATRIX: ${total}\nAIR-VECTOR-BITREVERSE-BULK: ${values} exact native lane values PASS\n'+os.read_file(out+'/controls/result.txt')!+'AIR-VECTOR-BITREVERSE-CACHE: all 1024 overloads in eight bounded128-identity modules through both APIs, wrapped all-one sum18446744073709550560 PASS; full module shared attribute-work refusals PASS\n'+os.read_file(out+'/attributes/result.txt')!+'AIR-VECTOR-BITREVERSE: 16 exact shared work/storage boundary checks through four APIs PASS\n';os.write_file(out+'/result.txt',result)!;print(result)
}
fn metadata_checks(ir airbitcode.IRModule, stream airbitcode.Stream,pools airbitcode.IRConstantPools,bodies airbitcode.IRFunctionBodies,mut p airbitcode.IRTypedProgram,f int,mut bs []airbitcode.IRMemoryBinding,output []u8,steps int) !int {
 scope:=bodies.scopes[f+1]; mut checks:=0
 for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {
  op:=p.instructions[index]; if stream.records[bodies.instructions[index].record].code!=34 {continue}
  for changed in [airbitcode.IRTypedInstruction{...op,flags:0},airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,opcode:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,callee_function:ir.functions.len},airbitcode.IRTypedInstruction{...op,operands_count:0},airbitcode.IRTypedInstruction{...op,operands_count:1},airbitcode.IRTypedInstruction{...op,operands_count:3},airbitcode.IRTypedInstruction{...op,result_type:-1},airbitcode.IRTypedInstruction{...op,targets_count:1},airbitcode.IRTypedInstruction{...op,indices_count:1}] {p.instructions[index]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('metadata admitted')}; unchanged(output);checks++}; p.instructions[index]=op
  for operand in 0 .. op.operands_count { slot:=op.operands_start+operand; original:=p.operands[slot]; changes:=if operand==0 {[airbitcode.IRTypedOperand{...original,number:~u32(0)},airbitcode.IRTypedOperand{...original,type_index:-1}]} else {[airbitcode.IRTypedOperand{...original,number:~u32(0)},airbitcode.IRTypedOperand{...original,number:bodies.instructions[index].next_value},airbitcode.IRTypedOperand{...original,type_index:-1}]}; for changed in changes {p.operands[slot]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps){panic('source admitted')}; unchanged(output);checks++}; p.operands[slot]=original; unsafe{changes.free()} }
 }
 return checks
}
