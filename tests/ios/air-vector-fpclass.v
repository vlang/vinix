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
#include <fenv.h>
fn C.fegetround() int
fn C.fesetround(int) int
fn C.feclearexcept(int) int
fn C.fetestexcept(int) int
fn C.feraiseexcept(int) int
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-ldexp-intrinsics'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }

 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures(); os.write_file(out + '/native-features.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
 mut f := C.LLVMGetFirstFunction(module_ptr); for f != unsafe { nil } { C.LLVMAddTargetDependentFunctionAttr(f, c'target-cpu', cpu); C.LLVMAddTargetDependentFunctionAttr(f, c'target-features', features); f = C.LLVMGetNextFunction(f) }; C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
 assert C.LLVMWriteBitcodeToFile(module_ptr, (out + '/native-input-features.bc').str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn typ(bits int) string { return if bits == 16 { 'half' } else { 'float' } }
fn mask(bits int) u64 { return (u64(1) << u32(bits)) - 1 }
fn fi(ir airbitcode.IRModule, name string) int { for i,f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn word(bits int, i int) u64 {
 return if bits == 16 { [u64(0x7c01), 0xfcff, 0x7e00, 0xffff, 0xfc00, 0xfc00, 0x8400, 0xfbff, 0x8001, 0x83ff, 0x8000, 0x8000, 0, 0, 1, 0x3ff, 0x400, 0x7bff, 0x7c00, 0x7c00]![i % 20] } else { [u64(0x7f800001), 0xffbfffff, 0x7fc00000, 0xffffffff, 0xff800000, 0xff800000, 0x80800000, 0xff7fffff, 0x80000001, 0x807fffff, 0x80000000, 0x80000000, 0, 0, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0x7f800000, 0x7f800000]![i % 20] }
}
// Independent field decoding, used alongside exact native vector predicates.
fn class_reference(bits int, value u64, test int) u64 {
 fraction_bits := if bits == 16 { 10 } else { 23 }; exponent_bits := if bits == 16 { 5 } else { 8 }
 exponent := (value >> u32(fraction_bits)) & ((u64(1) << u32(exponent_bits)) - 1)
 fraction := value & ((u64(1) << u32(fraction_bits)) - 1); negative := value >> u32(bits - 1) & 1 != 0
 index := if exponent == (u64(1) << u32(exponent_bits)) - 1 { if fraction != 0 { if fraction >> u32(fraction_bits - 1) != 0 { 1 } else { 0 } } else if negative { 2 } else { 9 } } else if exponent == 0 { if fraction == 0 { if negative { 5 } else { 6 } } else if negative { 4 } else { 7 } } else if negative { 3 } else { 8 }
 return u64(test & (1 << index) != 0)
}
fn literal(bits int, value u64) string { return 'bitcast (i${bits} ${value} to ${typ(bits)})' }
struct Case { name string bits int count int form int mode int test int }
fn vector(c Case) string {
 if c.form >= 2 { return ['poison', 'undef', 'zeroinitializer'][c.form - 2] }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; state := if c.form == 1 && lane % 4 == 1 { 'poison' } else if c.form == 1 && lane % 4 == 2 { 'undef' } else { literal(c.bits, word(c.bits, lane)) }; s.write_string(typ(c.bits)+' '+state) }; s.write_string('>'); return s.str()
}
fn source_lane(c Case, j u64, lane int, x u64) (int,u64) {
 if c.mode != 0 { if j >= u64(c.count) { return 1,0 }; if j == u64(lane) { return 0,x } }
 if c.form == 3 || (c.form == 1 && lane % 4 == 2) { return 3,0 }
 if c.form == 2 || (c.form == 1 && lane % 4 == 1) { return 1,0 }
 return 0, if c.form == 4 { u64(0) } else { word(c.bits,lane) }
}
fn expected(c Case,j u64,q u64,r u64,x u64) (int,u64) {
 for lane in 0 .. c.count { state,_ := source_lane(c,j,lane,x); if state==3 && c.mode!=2 { return 3,0 } }
 if r>=u64(c.count) { return 1,0 }
 index := if c.mode==4 { c.count-1-int(r) } else { int(r) }
 if c.mode==4 && r%2==0 { if q>=u64(c.count) { return 1,0 }; if q==u64(index) { return 0,1 } }
 mut state,mut value := source_lane(c,j,index,x)
 if c.mode==4 && state!=0 { return 2,0 }
 if c.mode==2 && state!=0 { state=2; value=0 }
 predicate:=class_reference(c.bits,value,c.test)
 return state, if c.mode==3 && predicate!=0 { value } else if c.mode==3 { u64(0) } else { predicate }
}
fn matrix(assembler string,out string) ! {
 mut s:=strings.new_builder(2097152); s.write_string('target datalayout = "e-p:64:64"\n'); mut cases:=[]Case{}
 masks:=[0,1023,1,2,4,8,16,32,64,128,256,512,3,96,144,264,516,504]!
 for bits in [16,32] { for count in 1 .. 17 { t:=typ(bits); s.write_string('declare <${count} x i1> @llvm.is.fpclass.v${count}f${bits}(<${count} x ${t}>, i32 immarg)\n')
 for form in 0 .. 5 { for mode in 0 .. 5 {
  c:=Case{'case_${cases.len}',bits,count,form,mode,masks[(count+form*3+mode*7)%18]}; cases<<c
  mut lanes:=[]string{}; for lane in 0 .. count { lanes << 'i32 ${count-1-lane+(lane%2)*count}' }
  mut ops:='%a = insertelement <${count} x ${t}> ${vector(c)}, ${t} %x, i64 %j\n'
  if mode==2 { ops += '%fs = freeze <${count} x ${t}> %a\n' }
  ops += '%n = call <${count} x i1> @llvm.is.fpclass.v${count}f${bits}(<${count} x ${t}> ${if mode==0 {vector(c)} else if mode==2 {'%fs'} else {'%a'}}, i32 ${c.test})\n'
  if mode==4 { ops += '%f = freeze <${count} x i1> %n\n %b = insertelement <${count} x i1> %f, i1 true, i64 %q\n %t = shufflevector <${count} x i1> %b, <${count} x i1> %f, <${count} x i32> <${lanes.join(', ')}>\n' }
  if mode==3 { ops += '%sel = select <${count} x i1> %n, <${count} x ${t}> %a, <${count} x ${t}> zeroinitializer\n %v = extractelement <${count} x ${t}> %sel, i64 %r\n %raw = bitcast ${t} %v to i${bits}\n'; if bits==16 {ops += '%wide = zext i16 %raw to i32\n'} } else { ops += '%v = extractelement <${count} x i1> ${if mode==4 {'%t'} else {'%n'}}, i64 %r\n %wide = zext i1 %v to i32\n' }
  result:=if mode==3 && bits==32 {'%raw'} else {'%wide'}
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${t}, ptr %src, align 1\n store i8 17, ptr %out\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i32 ${result}, ptr %d, align 1\n ret void }\n')
  s.write_string('define i32 @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${t} %x) { ${ops}ret i32 ${result} }\n'); unsafe {lanes.free()}
 } } } }
 data:=assemble(assembler,out,s.str())!; verify(data)!; stream:=airbitcode.parse(data)!; defer{stream.free()}; ir:=stream.ir_module(data)!; defer{ir.free()}; pools:=ir.constant_pools(stream)!; defer{pools.free()}; bodies:=ir.function_bodies(stream,pools)!; defer{bodies.free()}; mut p:=ir.typed_operands(stream,pools,bodies)!; defer{p.free()}; native:=native_module(data,out)!; defer{native.close()}
 mut exact:=0; mut choices:=0; mut poison:=0; mut undef:=0; mut scalar:=0; mut metadata:=0; mut budgets:=0
 mut rows:=os.create(out+'/comparisons.tsv')!; defer{rows.close()}; rows.writeln('bits\tlanes\tform\tmode\tmask\tj\tq\tr\tx\tvalue')!
 for c in cases {
  f:=fi(ir,c.name); sf:=fi(ir,'scalar_'+c.name); steps:=bodies.scopes[f+1].instructions_count; scalar_steps:=bodies.scopes[sf+1].instructions_count
  profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!; assert profile.steps==steps && profile.arguments[0].minimum_size==24 && profile.arguments[1].minimum_size==c.bits/8 && profile.arguments[2].minimum_size==12; profile.free()
  address:=C.LLVMGetFunctionAddress(native.engine,c.name.str); assert address!=0
  mut indices:=[]u8{len:32}; mut input:=[]u8{len:8}; mut actual:=[]u8{len:24,init:0xcc}; mut reference:=actual.clone(); mut bs:=[airbitcode.IRMemoryBinding{data:indices,offset:1},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}]
  edges:=[u64(0),u64(c.count-1),u64(c.count),~u64(0),1,2,3,u64(c.count+1)]!
  for sample in 0 .. c.count+2 {
   j:=edges[(sample*3)%8]; q:=edges[(sample*5+1)%8]; r:=u64(sample); x:=word(c.bits,sample)
   state,value:=expected(c,j,q,r,x)
   for i in 0 .. 8 {indices[1+i]=u8(j>>u32(i*8)); indices[9+i]=u8(q>>u32(i*8)); indices[17+i]=u8(r>>u32(i*8))}; for i in 0 .. c.bits/8 {input[1+i]=u8(x>>u32(i*8))}; for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc}
   args:=[j,q,r,x|~mask(c.bits)]
   if state==3 { if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps) {panic('undef scalar classification')} else {assert err.msg()=='AIR vector intrinsic: undef source lane'} } else {run:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,scalar_steps)!; assert run.bits==32 && run.steps==scalar_steps && run.poison==(state==1) && (run.poison || run.value==value), '${c} sample=${sample} state=${state} expected=${value} got=${run}'}
   if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,scalar_steps) {panic('classification entered integer-only API')}; scalar+=2
   if state in [1,3] { if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps) {panic('indeterminate classification stored')} else {assert err.msg()==if state==3 {'AIR vector intrinsic: undef source lane'} else {'AIR memory execution: poison store'}}; if state==1 {poison++} else {undef++} } else {assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps; if state==0 {exact++} else {choices++}}
   for i,b in actual {assert b==if i==3 {u8(17)} else if state in [0,2] && i>=11 && i<15 {u8(value>>u32((i-11)*8))} else {u8(0xcc)}, '${c} ${sample} byte=${i}'}
   if state==0 {unsafe{NativeCast(voidptr(address))(&indices[1],&input[1],&reference[3])}; assert actual==reference,'${c} sample=${sample}'; rows.writeln('${c.bits}\t${c.count}\t${c.form}\t${c.mode}\t${c.test}\t${j}\t${q}\t${r}\t${x}\t${value}')!}
   unsafe{args.free()}
  }
  for i in 0 .. actual.len {actual[i]=0xcc}; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps-1) {panic('short memory budget')}; unchanged(actual); if _:=p.run_scalar_function(ir,stream,pools,bodies,sf,[u64(0),0,0,0],scalar_steps-1) {panic('short scalar budget')}; budgets+=2
  metadata+=metadata_checks(ir,stream,pools,bodies,mut p,f,mut bs,actual,steps)!
  unsafe{indices.free();input.free();actual.free();reference.free();bs.free()}
 }
 assert cases.len==800 && scalar==(exact+choices+poison+undef)*2 && metadata==18400 && budgets==1600
 os.write_file(out+'/result.txt','AIR-VECTOR-FPCLASS-MATRIX: ${cases.len} shapes, ${exact} bit-exact LLVM values, ${choices} fixed choices, ${poison} poison stores, ${undef} strict undef, ${scalar} scalar/integer checks, ${metadata} metadata and ${budgets} budget refusals PASS\n')!
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
fn bulk_function(bits int,test int) string {
 t:=typ(bits); mut s:=strings.new_builder(8192); s.write_string('define void @bulk_${bits}_${test}(ptr %unused, ptr %src, ptr %out) { store i8 17, ptr %out\n')
 for lane in 0 .. 16 {s.write_string('%p${lane} = getelementptr i8, ptr %src, i64 ${lane*(bits/8)}\n %x${lane} = load ${t}, ptr %p${lane}, align 1\n %a${lane} = insertelement <16 x ${t}> ${if lane==0 {'poison'} else {'%a'+(lane-1).str()}}, ${t} %x${lane}, i32 ${lane}\n')}
 s.write_string('%n = call <16 x i1> @llvm.is.fpclass.v16f${bits}(<16 x ${t}> %a15, i32 ${test})\n')
 for lane in 0 .. 16 {s.write_string('%v${lane} = extractelement <16 x i1> %n, i32 ${lane}\n %b${lane} = zext i1 %v${lane} to i8\n %d${lane} = getelementptr i8, ptr %out, i64 ${8+lane}\n store i8 %b${lane}, ptr %d${lane}\n')}; s.write_string('ret void }\n');return s.str()
}
fn bulk(assembler string,out string, first int, last int) ! {
 mut s:=strings.new_builder(16777216); s.write_string('target datalayout = "e-p:64:64"\n')
 for bits in [16,32] {s.write_string('declare <16 x i1> @llvm.is.fpclass.v16f${bits}(<16 x ${typ(bits)}>, i32 immarg)\n');for test in first .. last {s.write_string(bulk_function(bits,test))}}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};native:=native_module(data,out)!;defer{native.close()}
 mut rows:=os.create(out+'/comparisons.tsv')!;defer{rows.close()};rows.writeln('bits\tmask\tpattern\tvalue')!
 sweeps:=[0,1023,1,2,4,8,16,32,64,128,256,512,3,96,144,264,516,504]!
 mut values:=0;mut edge:=0;mut environment:=0;mut native_invalid:=0
 mut env_rows:=os.create(out+'/environment.tsv')!;defer{env_rows.close()};env_rows.writeln('bits\tmask\trounding\tVM-exceptions\tnative-exceptions')!
 for bits in [16,32] {
  mut input:=[]u8{len:65};mut actual:=[]u8{len:32,init:0xcc};mut reference:=actual.clone();mut indices:=[u8(0)];mut bs:=[airbitcode.IRMemoryBinding{data:indices},airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{data:actual,offset:3,writable:true}]
  for test in first .. last {
   f:=fi(ir,'bulk_${bits}_${test}');steps:=bodies.scopes[f+1].instructions_count;address:=C.LLVMGetFunctionAddress(native.engine,('bulk_${bits}_${test}').str);assert address!=0
   profile:=p.memory_function_profile(ir,stream,pools,bodies,f)!;assert profile.arguments[0].minimum_size==0 && profile.arguments[1].minimum_size==16*(bits/8) && profile.arguments[2].minimum_size==24 && profile.steps==steps;profile.free()
   for sample in 0 .. 2+if test in sweeps {4096} else {0} {
    mut words:=[16]u64{}
    for lane in 0 .. 16 {k:=(sample-2)*16+lane; x:=if sample<2 {word(bits,sample*16+lane)} else if bits==16 {u64(k)} else {u64(u32(k)*u32(0x9e3779b9))};words[lane]=x;for i in 0 .. bits/8 {input[1+lane*(bits/8)+i]=u8(x>>u32(i*8))}}
    for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc}
    assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,steps)!.steps==steps
    unsafe{NativeCast(voidptr(address))(indices.data,&input[1],&reference[3])};assert actual==reference,'bulk ${bits} ${test} ${sample}'
    for i,b in actual {expected:=if i==3 {u8(17)} else if i>=11 && i<27 {u8(class_reference(bits,words[i-11],test))} else {u8(0xcc)};assert b==expected}
    for lane,x in words {rows.writeln('${bits}\t${test}\t${x}\t${actual[11+lane]}')!;if sample<2 {edge++} else {values++}}
   }
  }
  // Vinix must leave flags clear, including for sNaNs, in all four modes.
  // The captured native lowering raises FE_INVALID for masks 3/96. Keep its
  // exact values as the oracle and retain flags as deviations, not conformance.
  for rounding in [C.FE_TONEAREST,C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO] { assert C.fesetround(rounding)==0
   for test in [1,3,96,144] {if test<first || test>=last {continue};for lane in 0 .. 16 {x:=word(bits,lane);for i in 0 .. bits/8 {input[1+lane*(bits/8)+i]=u8(x>>u32(i*8))}};for i in 0 .. actual.len {actual[i]=0xcc;reference[i]=0xcc}
    f:=fi(ir,'bulk_${bits}_${test}');address:=C.LLVMGetFunctionAddress(native.engine,('bulk_${bits}_${test}').str);assert C.feclearexcept(C.FE_ALL_EXCEPT)==0;p.run_memory_function(ir,stream,pools,bodies,f,mut bs,200)!;assert C.fetestexcept(C.FE_ALL_EXCEPT)==0;unsafe{NativeCast(voidptr(address))(indices.data,&input[1],&reference[3])};native_flags:=C.fetestexcept(C.FE_ALL_EXCEPT);assert actual==reference;assert native_flags & ~C.FE_INVALID==0;env_rows.writeln('${bits}\t${test}\t${rounding}\t0\t${native_flags}')!;if native_flags!=0 {native_invalid++}
    for lane in 0 .. 16 {assert actual[11+lane]==u8(class_reference(bits,word(bits,lane),test))};environment++
   }
  };assert C.fesetround(C.FE_TONEAREST)==0
  unsafe{input.free();actual.free();reference.free();indices.free();bs.free()}
 }
 assert values==sweeps.filter(it>=first && it<last).len*131072 && edge==(last-first)*64 && environment==[1,3,96,144].filter(it>=first && it<last).len*8
 os.write_file(out+'/result.txt','AIR-VECTOR-FPCLASS-BULK: ${values} exhaustive half/deterministic float singleton/composite-mask lane comparisons, ${edge} all-1024-mask boundary lane comparisons and ${environment} VM rounding/exception checks PASS; ${native_invalid} native FE_INVALID deviations recorded\n')!
}
fn controls(assembler string,out string) ! {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n');modes:=['raw','source','result','discard','old','chain'];guards:=['tail','attribute','argument','load','phi','wide','scalable','double','alias'];bad_masks:=['arg','result','wide','negative','poison','undef'];types:=['mask16','mask64','maskvec','source_double','source_int','return8','return_count','return_scalar']
 for bits in [16,32] {t:=typ(bits);nan:=if bits==16 {u64(0x7c01)} else {u64(0x7f800001)}
  for n in [2,17] {s.write_string('declare <${n} x i1> @llvm.is.fpclass.v${n}f${bits}(<${n} x ${t}>, i32 immarg)\n')}
  s.write_string('declare <vscale x 2 x i1> @llvm.is.fpclass.nxv2f${bits}(<vscale x 2 x ${t}>, i32 immarg)\n declare <2 x i1> @air.is.fpclass.v2f${bits}(<2 x ${t}>, i32)\n declare <2 x i1> @reserved_${bits}(<2 x ${t}>, i32)\n declare <2 x i1> @duplicate_${bits}(<2 x ${t}>, i32)\n')
  for state in ['defined','poison','undef'] {for mode in modes {
   source:=if state=='defined' {'<${t} ${literal(bits,nan)}, ${t} zeroinitializer>'} else {state}
   pre:=if mode=='source' {'%s = freeze <2 x ${t}> ${source}\n'} else {''}
   post:=if mode=='result' {'%f = freeze <2 x i1> %n\n'} else if mode=='old' {'%changed = insertelement <2 x i1> %n, i1 false, i32 0\n'} else if mode=='chain' {'%chain = select <2 x i1> %n, <2 x i32> <i32 11, i32 11>, <2 x i32> <i32 7, i32 7>\n'} else {''}
   store:=if mode=='discard' {''} else {'%v = extractelement <2 x ${if mode=='chain' {'i32'} else {'i1'}}> ${if mode=='chain' {'%chain'} else if mode=='result' {'%f'} else {'%n'}}, i32 0\n '+if mode=='chain' {''} else {'%z = zext i1 %v to i32\n '}+'%d = getelementptr i8, ptr %out, i64 8\n store i32 %${if mode=='chain' {'v'} else {'z'}}, ptr %d, align 1\n'}
   old:=if mode=='old' {'%v2 = extractelement <2 x i1> %changed, i32 0\n %z2 = zext i1 %v2 to i32\n %d2 = getelementptr i8, ptr %out, i64 16\n store i32 %z2, ptr %d2, align 1\n'} else {''}
   s.write_string('define void @state_${bits}_${state}_${mode}(ptr %out) { store i8 17, ptr %out\n ${pre}%n = call <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}> ${if mode=='source' {'%s'} else {source}}, i32 3)\n ${post}${store}${old}ret void }\n')
  }}
  for guard in guards {n:=if guard=='wide' {17} else {2};src:=if guard=='scalable' {'<vscale x 2 x ${t}>'} else if guard=='double' {'<2 x double>'} else {'<${n} x ${t}>'};dst:=if guard=='scalable' {'<vscale x 2 x i1>'} else {'<${n} x i1>'};callee:=if guard=='scalable' {'llvm.is.fpclass.nxv2f${bits}'} else if guard=='double' {'llvm.is.fpclass.v2f64'} else if guard=='alias' {'air.is.fpclass.v2f${bits}'} else {'llvm.is.fpclass.v${n}f${bits}'}
   sig:=if guard=='argument' {'<2 x ${t}> %a, ptr %out'} else if guard=='load' {'ptr %src, ptr %out'} else {'ptr %out'};pre:=if guard=='load' {'%a = load <2 x ${t}>, ptr %src, align 1\n'} else if guard=='phi' {'br label %body\n body: %a = phi <2 x ${t}> [zeroinitializer, %entry]\n'} else if guard=='wide' {'br i1 true, label %done, label %cold\n done: ret void\n cold:'} else {''}
   s.write_string('define void @guard_${bits}_${guard}(${sig}) { entry: store i8 17, ptr %out\n ${pre}%n = ${if guard=='tail' {'tail '} else {''}}call ${if guard=='fmf' {'nnan '} else {''}}${dst} @${callee}(${src} ${if guard in ['argument','load','phi'] {'%a'} else {'zeroinitializer'}}, i32 3)${if guard=='attribute' {' #1'} else {''}}\n ret void }\n')
  }
  for tag in types {src:=if tag=='source_double' {'<2 x double>'} else if tag=='source_int' {'<2 x i32>'} else {'<2 x ${t}>'};dst:=if tag=='return8' {'<2 x i8>'} else if tag=='return_count' {'<3 x i1>'} else if tag=='return_scalar' {'i1'} else {'<2 x i1>'};mt:=if tag=='mask16' {'i16'} else if tag=='mask64' {'i64'} else if tag=='maskvec' {'<2 x i32>'} else {'i32'}
   s.write_string('declare ${dst} @typed_${bits}_${tag}(${src}, ${mt})\n');for kind in ['memory','void'] {s.write_string('define void @typed_${bits}_${tag}_${kind}(${if kind=='memory' {'ptr %out'} else {''}}) { ${if kind=='memory' {'store i8 17, ptr %out\n'} else {''}}%n = call ${dst} @typed_${bits}_${tag}(${src} zeroinitializer, ${mt} zeroinitializer)\n ret void }\n')}
  }
  for tag in bad_masks {for kind in ['memory','void'] {
   second:=if tag=='arg' {'%mask'} else if tag=='result' {'%changed'} else if tag=='wide' {'1024'} else if tag=='negative' {'-1'} else {tag}
   s.write_string('define void @mask_${bits}_${tag}_${kind}(${if kind=='memory' {'ptr %src, ptr %out'} else {'i32 %mask'}}) { ${if kind=='memory' {'%mask = load i32, ptr %src, align 1\n store i8 17, ptr %out\n'} else {''}}%a = call <2 x i1> @reserved_${bits}(<2 x ${t}> zeroinitializer, i32 3)\n %changed = and i32 %mask, 1023\n %b = call <2 x i1> @reserved_${bits}(<2 x ${t}> zeroinitializer, i32 ${second})\n ret void }\n')
  }}
  for kind in ['memory','void'] {s.write_string('define void @duplicate_${bits}_${kind}(${if kind=='memory' {'ptr %out'} else {''}}) { ${if kind=='memory' {'store i8 17, ptr %out\n'} else {''}}%a = call <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}> zeroinitializer, i32 3)\n %b = call <2 x i1> @duplicate_${bits}(<2 x ${t}> zeroinitializer, i32 96)\n ret void }\n')}
  s.write_string('define void @masks_${bits}(ptr %out) { %a = call <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}> <${t} ${literal(bits,nan)}, ${t} zeroinitializer>, i32 3)\n %b = call <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}> <${t} ${literal(bits,nan)}, ${t} zeroinitializer>, i32 96)\n')
  for i in 0 .. 4 {s.write_string('%v${i} = extractelement <2 x i1> %${if i<2 {'a'} else {'b'}}, i32 ${i%2}\n %z${i} = zext i1 %v${i} to i8\n %p${i} = getelementptr i8, ptr %out, i64 ${i}\n store i8 %z${i}, ptr %p${i}\n')};s.write_string('ret void }\n')
  s.write_string('define i32 @literal_${bits}() { %n = call <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}> zeroinitializer, i32 96)\n %v = extractelement <2 x i1> %n, i32 0\n %z = zext i1 %v to i32\n ret i32 %z }\n')
  s.write_string('define i32 @loop_${bits}(i32 %limit) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %short = trunc i32 %i to i16\n %x = bitcast i${bits} %${if bits==16 {'short'} else {'i'}} to ${t}\n %a = insertelement <2 x ${t}> poison, ${t} %x, i32 0\n %n = call <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}> %a, i32 128)\n %v = extractelement <2 x i1> %n, i32 0\n %z = zext i1 %v to i32\n %added = add i32 %sum, %z\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i32 %added }\n')
 }
 s.write_string('declare <2 x i1> @llvm.is.fpclass.v2f64(<2 x double>, i32 immarg)\n attributes #1 = { nounwind }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};mut p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};mut checks:=0
 for bits in [16,32] {
  for state in ['defined','poison','undef'] {for mode in modes {
   mut output:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}];f:=fi(ir,'state_${bits}_${state}_${mode}');bad:=(state=='undef' && mode!='source') || (state=='poison' && mode !in ['source','result','discard'])
   if bad {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100){panic('state admitted')}} else {p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100)!}
   value:=if state!='defined' && mode in ['source','result'] {0} else {1};result:=if mode=='chain' {if value==1 {11} else {7}} else {value}
   for i,b in output {assert b==if i==3 {u8(17)} else if !bad && mode!='discard' && i>=11 && i<15 {u8(u32(result)>>u32((i-11)*8))} else if !bad && mode=='old' && i>=19 && i<23 {u8(0)} else {u8(0xcc)},'${bits} ${state} ${mode} byte=${i}'};checks++;unsafe{output.free();bs.free()}
  }}
  for guard in guards {mut output:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if guard in ['argument','load'] {bs<<airbitcode.IRMemoryBinding{data:output}};if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'guard_${bits}_${guard}'),mut bs,100){panic('guard admitted')};unchanged(output);checks++;unsafe{output.free();bs.free()}}
  for tag in types {callee:=fi(ir,'typed_${bits}_${tag}');old:=functions[callee];functions[callee]=airbitcode.IRFunction{...old,name:'llvm.is.fpclass.v2f${bits}'};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'typed_${bits}_${tag}_memory'),mut bs,100){panic('typed memory accepted')};unchanged(output);if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'typed_${bits}_${tag}_void'),[],100){panic('typed void accepted')};functions[callee]=old;checks+=2;unsafe{output.free();bs.free()}}
  callee:=fi(ir,'reserved_${bits}');old:=functions[callee];functions[callee]=airbitcode.IRFunction{...old,name:'llvm.is.fpclass.v2f${bits}'}
  for tag in bad_masks {mut output:=[u8(0xcc)];mut input:=[u8(3),0,0,0];mut bs:=[airbitcode.IRMemoryBinding{data:input},airbitcode.IRMemoryBinding{data:output,writable:true}];for kind in ['memory','void'] {
   function:=fi(ir,'mask_${bits}_${tag}_${kind}');scope:=bodies.scopes[function+1];mut first_mask:=-1;mut second_mask:=-1
   for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {op:=p.instructions[index];if stream.records[bodies.instructions[index].record].code!=34 {continue};if first_mask<0 {first_mask=op.operands_start+2} else {assert second_mask<0;second_mask=op.operands_start+2}}
   assert first_mask>=0 && second_mask>=0
   original:=p.operands[second_mask];p.operands[second_mask]=airbitcode.IRTypedOperand{...original,number:p.operands[first_mask].number}
   if kind=='memory' {p.run_memory_function(view,stream,pools,bodies,function,mut bs,100)!;assert output[0]==17;output[0]=0xcc} else {p.run_void_function(view,stream,pools,bodies,function,[u64(3)],100)!}
   p.operands[second_mask]=original;checks++
  };if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'mask_${bits}_${tag}_memory'),mut bs,100){panic('cached invalid mask accepted')};unchanged(output);if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'mask_${bits}_${tag}_void'),[u64(3)],100){panic('cached void invalid mask accepted')};checks+=2;unsafe{input.free();output.free();bs.free()}};functions[callee]=old
  duplicate:=fi(ir,'duplicate_${bits}');before:=functions[duplicate];functions[duplicate]=airbitcode.IRFunction{...before,name:'llvm.is.fpclass.v2f${bits}'};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate_${bits}_memory'),mut bs,100){panic('duplicate accepted')} else {assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration'};unchanged(output);if _:=p.run_void_function(view,stream,pools,bodies,fi(ir,'duplicate_${bits}_void'),[],100){panic('duplicate void accepted')} else {assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration'};functions[duplicate]=before;checks+=2;unsafe{output.free();bs.free()}
  mut values:=[]u8{len:8,init:0xcc};mut bindings:=[airbitcode.IRMemoryBinding{data:values,offset:2,writable:true}];p.run_memory_function(ir,stream,pools,bodies,fi(ir,'masks_${bits}'),mut bindings,100)!;assert values==[u8(0xcc),0xcc,1,0,0,1,0xcc,0xcc];checks++;unsafe{values.free();bindings.free()}
  literal_function:=fi(ir,'literal_${bits}');literal_run:=p.run_scalar_function(ir,stream,pools,bodies,literal_function,[],4)!;assert literal_run.value==1 && !literal_run.poison && literal_run.bits==32 && literal_run.steps==4
  if _:=p.run_integer_function(ir,stream,pools,bodies,literal_function,[],4) {panic('direct floating classification entered integer-only API')};checks++
  for n in [u64(1),2,3,16,257,513]! {run:=p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'loop_${bits}'),[n],10000)!;assert !run.poison && run.value==n-1;checks++}
 }
 assert checks==154
 os.write_file(out+'/result.txt','AIR-VECTOR-FPCLASS-CONTROLS: ${checks} source/state/freeze/discard/snapshot/composition, cached masks, mixed signatures, changing-source loops, unsupported profiles and duplicate checks PASS\n')!
}
fn attributes(assembler string,out string) ! {
 mut s:=strings.new_builder(4096)
 for bits in [16,32] {t:=typ(bits);s.write_string('declare <2 x i1> @llvm.is.fpclass.v2f${bits}(<2 x ${t}>, i32 immarg)\n declare <2 x ${t}> @llvm.fabs.v2f${bits}(<2 x ${t}>)\n')
 for kind in ['memory','void'] {for family in ['class','fabs'] {s.write_string('define void @${family}_${bits}_${kind}(${if kind=='memory' {'ptr %out'} else {''}}) { ${if kind=='memory' {'store i8 17, ptr %out\n'} else {''}}%n = call <2 x ${if family=='class' {'i1'} else {t}}> @llvm.${if family=='class' {'is.fpclass'} else {'fabs'}}.v2f${bits}(<2 x ${t}> zeroinitializer${if family=='class' {', i32 3'} else {''}})\n ret void }\n') }} }
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 for bits in [16,32] {for family in ['class','fabs'] {profile:=p.memory_function_profile(ir,stream,pools,bodies,fi(ir,'${family}_${bits}_memory'))!;profile.free();p.run_void_function(ir,stream,pools,bodies,fi(ir,'${family}_${bits}_void'),[],2)!}}
 mut values:=stream.values.clone();defer{unsafe{values.free()}};mutated:=airbitcode.Stream{...stream,values:values};mut group:=-1
 for record in stream.records {if stream.blocks[record.block].id==10 && record.code==3 && record.values_count==4 && stream.values[record.values_start+1]==2 && stream.values[record.values_start+3]==60 {group=record.values_start;break}};assert group>=0
 for change in 0 .. 4 {values[group+1]=stream.values[group+1];values[group+2]=stream.values[group+2];values[group+3]=stream.values[group+3];if change==0 {values[group+1]=1} else if change==1 {values[group+1]=0} else if change==2 {values[group+3]=54} else {values[group+2]=1}
  for bits in [16,32] {mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,mutated,pools,bodies,fi(ir,'class_${bits}_memory'),mut bs,100){panic('bad immarg admitted')};unchanged(output);if _:=p.run_void_function(ir,mutated,pools,bodies,fi(ir,'class_${bits}_void'),[],100){panic('bad void immarg admitted')};unsafe{output.free();bs.free()}}
 };values[group+1]=stream.values[group+1];values[group+2]=stream.values[group+2];values[group+3]=stream.values[group+3]
 for bits in [16,32] {class_record:=stream.records[ir.functions[fi(ir,'llvm.is.fpclass.v2f${bits}')].record];fabs_record:=stream.records[ir.functions[fi(ir,'llvm.fabs.v2f${bits}')].record];slot:=fabs_record.values_start+6;original:=values[slot];values[slot]=stream.values[class_record.values_start+6];mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];if _:=p.run_memory_function(ir,mutated,pools,bodies,fi(ir,'fabs_${bits}_memory'),mut bs,100){panic('immarg leaked to fabs')};unchanged(output);if _:=p.run_void_function(ir,mutated,pools,bodies,fi(ir,'fabs_${bits}_void'),[],100){panic('void immarg leaked to fabs')};values[slot]=original;unsafe{output.free();bs.free()}}
 os.write_file(out+'/result.txt','AIR-VECTOR-FPCLASS-ATTRIBUTES: canonical class/fabs acceptance, 16 exact immarg slot/enum/encoding refusals and four other-family immarg refusals PASS\n')!
}
fn limits(assembler string,out string,storage bool,over bool) ! {
 count:=if storage {1} else {16};mut s:=strings.new_builder(10485760);s.write_string('declare <${count} x i1> @llvm.is.fpclass.v${count}f16(<${count} x half>, i32 immarg)\n')
 for name in ['memory','void'] {s.write_string('define void @${name}(${if name=='memory' {'ptr %out'} else {''}}) {\n');if name=='memory' {s.write_string('store i8 17, ptr %out\n')};for i in 0 .. if storage && over {4097} else {4096} {s.write_string('%n${i} = call <${count} x i1> @llvm.is.fpclass.v${count}f16(<${count} x half> zeroinitializer, i32 ${i%1024})\n')};if !storage {for i in 0 .. if over {54309} else {54308} {s.write_string('%x${i} = extractelement <16 x i1> %n4095, i32 0\n')}};s.write_string('ret void }\n')}
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage {'AIR vector: update result limit'} else {'AIR vector: constant lane work limit'}
 if over {if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000){panic('memory limit')} else {assert err.msg()==diagnostic,err.msg()};unchanged(output);if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'void'),[],70000){panic('void limit')} else {assert err.msg()==diagnostic,err.msg()}} else {assert p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!.steps==if storage {4098} else {58406};assert output[0]==17;assert p.run_void_function(ir,stream,pools,bodies,fi(ir,'void'),[],70000)!.steps==if storage {4097} else {58405}};unsafe{output.free();bs.free()}
}
fn main() {
 assert os.args.len==3;out:=os.abs_path(os.args[2]);assert !os.exists(out) && !out.starts_with(os.getwd()+'/');os.mkdir_all(out)!
 saved:=C.fegetround();assert saved>=0;defer{assert C.fesetround(saved)==0};assert C.fesetround(C.FE_TONEAREST)==0
 assert C.feclearexcept(C.FE_ALL_EXCEPT)==0;assert C.feraiseexcept(C.FE_INVALID)==0;assert C.fetestexcept(C.FE_INVALID)!=0;assert C.feclearexcept(C.FE_ALL_EXCEPT)==0
 matrix(os.args[1],out+'/matrix')!;for chunk in 0 .. 8 {bulk(os.args[1],out+'/bulk-${chunk}',chunk*128,(chunk+1)*128)!};controls(os.args[1],out+'/controls')!;attributes(os.args[1],out+'/attributes')!
 for storage in [false,true] {for over in [false,true] {limits(os.args[1],out+'/${if storage {'storage'} else {'work'}}-${if over {'over'} else {'boundary'}}',storage,over)!}}
 result:=os.read_file(out+'/matrix/result.txt')!+'AIR-VECTOR-FPCLASS-BULK: eight bounded modules; 2359296 sweep and 65536 all-mask boundary lane comparisons, 32 VM rounding/exception checks PASS; native exceptions retained separately\n'+os.read_file(out+'/controls/result.txt')!+os.read_file(out+'/attributes/result.txt')!+'AIR-VECTOR-FPCLASS: exception-flag positive control and eight exact shared storage/work boundaries PASS\n';os.write_file(out+'/result.txt',result)!;print(result)
}
