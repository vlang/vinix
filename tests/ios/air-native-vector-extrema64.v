// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fegetround() int
fn C.fesetround(int) int
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
fn C.LLVMLookupIntrinsicID(&char, usize) u32
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn verify(data []u8) ! {
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}
struct NativeModule { context voidptr buffer voidptr engine voidptr }
fn native_module(data []u8, out string, ir airbitcode.IRModule) !NativeModule {
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'air-vector-extrema64'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn width_mask(width int) u64 { return if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 } }
fn fi(ir airbitcode.IRModule, name string) int { for i,f in ir.functions { if f.name == name { return i } }; panic(name) }
fn untouched(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn air_name(id string) string {
 return match id { 'smin' { 'air.min.s' } 'smax' { 'air.max.s' } 'umin' { 'air.min.u' } 'umax' { 'air.max.u' } else { panic(id) } }
}
fn oracle(bits u32,id string,a u64,b u64) u64 {
 assert bits==64
 minimum:=id.ends_with('min')
 less:=if id.starts_with('s'){i64(a)<i64(b)}else{a<b}
 return if less==minimum{a}else{b}
}
fn wide_ops(width int,count int,id string) string {
 assert width==64
 t:='<${count} x i64>';minimum:=id.ends_with('min');signed:=id.starts_with('s')
 predicate:=if signed{if minimum{'slt'}else{'sgt'}}else{if minimum{'ult'}else{'ugt'}}
 return '%order = icmp ${predicate} ${t} %a,%b\n %raw = select <${count} x i1> %order,${t} %a,${t} %b\n'
}
fn word(width int,sample int,lane int,side int) u64 {
 assert width==64
 edges:=[u64(0),1,2,7,31,63,127,255,0xffffffff,0x100000000,0x7ffffffffffffffe,0x7fffffffffffffff,0x8000000000000000,0x8000000000000001,0xfffffffffffffffe,0xffffffffffffffff]!
 if sample<256{return edges[if side==0{(sample/16+lane)%16}else{(sample%16+lane*7)%16}]}
 x:=u64(sample)*u64(0x9e3779b97f4a7c15)^u64(lane)*u64(0x1f123bb585ebca6b)
 return if side==0||sample%4==0{x}else if sample%4==1{~x}else{u64(sample)*u64(0x85ebca6bc2b2ae35)^u64(lane)*u64(0xc2b2ae351f123bb5)}
}
fn fixture(width int) string {
 mut s := strings.new_builder(1048576); s.write_string('target datalayout = "e-p:64:64"\n')
 for id in ['smin','smax','umin','umax'] {
  s.write_string('declare i${width} @llvm.${id.replace('_','.')}.i${width}(i${width}, i${width})\n define i${width} @q_${id}(i${width} %x, i${width} %y) { %r = call i${width} @llvm.${id.replace('_','.')}.i${width}(i${width} %x, i${width} %y)\n ret i${width} %r }\n')
  for count in 1 .. 17 {
   t := '<${count} x i${width}>'; name := '${air_name(id)}.v${count}i${width}'
   s.write_string('declare ${t} @${name}(${t}, ${t})\n')
   s.write_string('declare ${t} @llvm.${id.replace('_','.')}.v${count}i${width}(${t}, ${t})\n define void @coexist_${id}_${count}(${t} %a, ${t} %b, ptr %out) {store i8 17, ptr %out\n %ar = call ${t} @${name}(${t} %a, ${t} %b)\n %lr = call ${t} @llvm.${id.replace('_','.')}.v${count}i${width}(${t} %a, ${t} %b)\n %r = xor ${t} %ar, %lr\n %p = getelementptr i8, ptr %out, i64 8\n store ${t} %r, ptr %p, align 1\n ret void }\n')
   s.write_string('define void @ref_${id}_${count}(ptr %left, ptr %right, ptr %out) { %av = load <${count} x i64>, ptr %left, align 1\n %bv = load <${count} x i64>, ptr %right, align 1\n %a = ${if width == 64 { 'or ${t} %av, zeroinitializer' } else { 'trunc <${count} x i64> %av to ${t}' }}\n %b = ${if width == 64 { 'or ${t} %bv, zeroinitializer' } else { 'trunc <${count} x i64> %bv to ${t}' }}\n ${wide_ops(width,count,id)}%result = ${if width == 64 { 'or ${t} %raw, zeroinitializer' } else { 'zext ${t} %raw to <${count} x i64>' }}\n store <${count} x i64> %result, ptr %out, align 1\n ret void }\n')
   ops := '%a = insertelement ${t} zeroinitializer, i${width} %x, i64 %j\n %b = insertelement ${t} zeroinitializer, i${width} %y, i64 %j\n %r = call ${t} @${name}(${t} %a, ${t} %b)\n %e = extractelement ${t} %r, i64 %j\n'
   s.write_string('define i${width} @s_${id}_${count}(i${width} %x, i${width} %y, i64 %j) { ${ops}ret i${width} %e }\n')
   s.write_string('define void @m_${id}_${count}(${t} %a, ${t} %b, ptr %out) { store i8 17, ptr %out\n %r = call ${t} @${name}(${t} %a, ${t} %b)\n')
   for lane in 0 .. count {
    s.write_string('%e${lane} = extractelement ${t} %r, i64 ${lane}\n %z${lane} = ${if width == 64 { 'or i64 %e${lane}, 0' } else { 'zext i${width} %e${lane} to i64' }}\n %p${lane} = getelementptr i64, ptr %out, i64 ${lane + 1}\n store i64 %z${lane}, ptr %p${lane}, align 1\n')
   }; s.write_string('ret void }\n')
   for vector in [false,true] {
    scalar_ops := '%e = call i${width} @llvm.${id.replace('_','.')}.i${width}(i${width} %x, i${width} %y)\n'
    s.write_string('define void @index_${id}_${count}_${vector}(i${width} %x, i${width} %y, i64 %j, ptr %out) { store i8 17, ptr %out\n ${if vector { ops } else { scalar_ops }}%idx = and i${width} %e, ${width_mask(width)&63}\n %offset = ${if width==64 { 'or i64 %idx, 0' } else { 'zext i${width} %idx to i64' }}\n %p = getelementptr i8, ptr %out, i64 %offset\n store i8 42, ptr %p\n ret void }\n')
   }
  }
 }
 return s.str()
}
fn loaded_source(source string,width int) string {
 mut added:=''
 for id in ['smin','smax','umin','umax'] {for count in 1..17 {
  t:='<${count} x i${width}>';header:='define void @m_${id}_${count}(${t} %a, ${t} %b, ptr %out) {'
  assert source.count(header)==1;body:=source.all_after(header).all_before('ret void }\n')
  added+='define void @loaded_${id}_${count}(ptr %in, ptr %out) {%av = load <${count} x i64>, ptr %in, align 1\n %bp = getelementptr i8, ptr %in, i64 128\n %bv = load <${count} x i64>, ptr %bp, align 1\n %a = or ${t} %av,zeroinitializer\n %b = or ${t} %bv,zeroinitializer\n '+body+'ret void }\n'
 }}
 return source+added
}
fn run_width(assembler string, root string, width int) ! {
 data := assemble(assembler, root, loaded_source(fixture(width),width))!; verify(data)!
 stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream,pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream,pools,bodies)!; defer { p.free() }
 native := native_module(data,root,ir)!; defer { native.close() }
 mut native_lanes := 0; mut scalar_checks := 0; mut index_checks := 0; mut metadata := 0; mut budgets := 0; mut coexist := 0; mut bounds := 0
 mut rows := os.create(root+'/comparisons.tsv')!; defer { rows.close() }; rows.writeln('operation\tlanes\tsample\tlane\tleft\tright\tresult')!
 for id in ['smin','smax','umin','umax'] {
  single := C.LLVMGetFunctionAddress(native.engine,'ref_${id}_1'.str); assert single != 0
  for sample in 0 .. 512 {
   a := word(width,sample,0,0); b := word(width,sample,0,1); mut reference := u64(0)
   unsafe { NativeCast(voidptr(single))(&a,&b,&reference) }
   r := p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'q_${id}'),[a|~width_mask(width),b|~width_mask(width)],2)!
   assert !r.poison && r.value == reference && reference == oracle(u32(width),id,a,b); scalar_checks++
  }
  for count in 1 .. 17 {
   f := fi(ir,'m_${id}_${count}'); sf := fi(ir,'s_${id}_${count}'); plan := p.prepare_memory_function(ir,stream,pools,bodies,f)!
   assert plan.steps() == count*4+3
   lf:=fi(ir,'loaded_${id}_${count}');loaded:=p.prepare_memory_function(ir,stream,pools,bodies,lf)!;assert loaded.steps()==plan.steps()+5
   cf:=fi(ir,'coexist_${id}_${count}');coexisting:=p.prepare_memory_function(ir,stream,pools,bodies,cf)!;assert coexisting.steps()==7
   mut input:=[]u8{len:264};mut input_bindings:=[airbitcode.IRMemoryBinding{data:input,offset:1},airbitcode.IRMemoryBinding{}]
   address := C.LLVMGetFunctionAddress(native.engine,'ref_${id}_${count}'.str); assert address != 0
   mut left := []u64{len:count}; mut right := []u64{len:count}; mut expected := []u64{len:count}
   mut output := []u8{len:count*8+16,init:0xcc}; mut bs := [airbitcode.IRMemoryBinding{values:left},airbitcode.IRMemoryBinding{values:right},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
   for sample in 0 .. 1024 {
    for lane in 0 .. count { left[lane] = word(width,sample,lane,0)|~width_mask(width); right[lane] = word(width,sample,lane,1)|~width_mask(width) }
    unsafe { NativeCast(voidptr(address))(left.data,right.data,expected.data) }
    for lane in 0 .. count { assert expected[lane] == oracle(u32(width),id,left[lane],right[lane]); rows.writeln('${id}\t${count}\t${sample}\t${lane}\t${left[lane]}\t${right[lane]}\t${expected[lane]}')!; native_lanes++ }
    j := sample % count
    for integer in [false,true] {
     args := [left[j],right[j],u64(j)]
     r := if integer { v:=p.run_integer_function(ir,stream,pools,bodies,sf,args,5)!; airbitcode.IRScalarRun{value:v.value,poison:v.poison,steps:v.steps} } else { p.run_scalar_function(ir,stream,pools,bodies,sf,args,5)! }
     assert !r.poison && r.value == expected[j] && r.steps==5; scalar_checks++; unsafe { args.free() }
    }
    for lane in 0..count {for side in 0..2 {value:=if side==0{left[lane]}else{right[lane]};for byte_index in 0..8{input[1+side*128+lane*8+byte_index]=u8(value>>u32(byte_index*8))}}}
    input_bindings[1]=airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}
    for cached in [false,true] {
     for i in 0..output.len{output[i]=0xcc};loaded.validate(input_bindings,loaded.steps())!;untouched(output)
     if cached{loaded.run(mut input_bindings,loaded.steps())!}else{p.run_memory_function(ir,stream,pools,bodies,lf,mut input_bindings,loaded.steps())!}
     for i,b in output{assert b==if i==3{u8(17)}else if i>=11&&i<11+count*8{u8(expected[(i-11)/8]>>u32(((i-11)%8)*8))}else{u8(0xcc)}}
    }
    for prepared in [false,true] {
     for i in 0 .. output.len { output[i]=0xcc }; plan.validate(bs,plan.steps())!; untouched(output)
     if prepared { assert plan.run(mut bs,plan.steps())!.steps == plan.steps() } else { assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps())!.steps == plan.steps() }
     for i,b in output { assert b == if i==3 {u8(17)} else if i>=11 && i<11+count*8 {u8(expected[(i-11)/8] >> u32(((i-11)%8)*8))} else {u8(0xcc)}, '${id} ${width} ${count} ${sample} byte=${i}' }
    }
    if sample % 32 == 0 {for cached in [false,true] {
     for i in 0..output.len {output[i]=0xcc};coexisting.validate(bs,7)!;untouched(output)
     if cached {coexisting.run(mut bs,7)!} else {p.run_memory_function(ir,stream,pools,bodies,cf,mut bs,7)!}
     for i,b in output {assert b==if i==3{u8(17)}else if i>=11&&i<11+count*8{u8(0)}else{u8(0xcc)}};coexist++
    }}
   }
   for i in 0 .. output.len { output[i]=0xcc }
   if _ := plan.run(mut bs,plan.steps()-1) { panic('prepared short budget') }; untouched(output)
   if _ := p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()-1) { panic('direct short budget') }; untouched(output); budgets+=2
   if _:=loaded.run(mut input_bindings,loaded.steps()-1){panic('loaded short budget')};untouched(output)
   if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut input_bindings,loaded.steps()-1){panic('direct loaded short budget')};untouched(output);budgets+=2
   for slot in 0..2 {
    mut bad_bindings:=input_bindings.clone()
    bad_bindings[slot]=if slot==0{airbitcode.IRMemoryBinding{...bad_bindings[0],data:unsafe{input[..128+count*8]}}}else{airbitcode.IRMemoryBinding{...bad_bindings[1],data:unsafe{output[..10+count*8]}}}
    if _:=loaded.validate(bad_bindings,loaded.steps()){panic('short loaded buffer validation')};untouched(output);bounds++
    if _:=loaded.run(mut bad_bindings,loaded.steps()){panic('short loaded buffer')};untouched(output);bounds++
    if _:=p.run_memory_function(ir,stream,pools,bodies,lf,mut bad_bindings,loaded.steps()){panic('direct short loaded buffer')};untouched(output);bounds++
    unsafe{bad_bindings.free()}
   }
   scope:=bodies.scopes[f+1]
   for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {
    op:=p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 34 {continue}
    for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,operands_count:4},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
     p.instructions[index]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {panic('integer-extrema metadata')}; untouched(output); metadata++
    };p.instructions[index]=op
    for side in 0..2 {slot:=op.operands_start+side+1;saved:=p.operands[slot];p.operands[slot]=airbitcode.IRTypedOperand{...saved,type_index:-1};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()){panic('operand type')};untouched(output);metadata++;p.operands[slot]=saved}
   }
   for vector in [false,true] {
    ix:=fi(ir,'index_${id}_${count}_${vector}'); ip:=p.prepare_memory_function(ir,stream,pools,bodies,ix)!
    mut bytes:=[]u8{len:96,init:0xcc}; mut xvalues:=[u64(0)];mut yvalues:=[u64(0)];mut jvalues:=[u64(0)];mut bindings:=[airbitcode.IRMemoryBinding{values:xvalues},airbitcode.IRMemoryBinding{values:yvalues},airbitcode.IRMemoryBinding{values:jvalues},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
    for sample in 0 .. 16 {
     a:=word(width,sample,0,0); b:=word(width,sample,0,1); xvalues[0]=a|~width_mask(width);yvalues[0]=b|~width_mask(width);jvalues[0]=u64(sample%count)
     offset:=int(oracle(u32(width),id,a,b)&63)
     for prepared in [false,true] {
      for i in 0 .. bytes.len {bytes[i]=0xcc};ip.validate(bindings,ip.steps())!;untouched(bytes)
      if prepared {ip.run(mut bindings,ip.steps())!} else {p.run_memory_function(ir,stream,pools,bodies,ix,mut bindings,ip.steps())!}
      for i,bv in bytes {assert bv==if i==3+offset {u8(42)} else if i==3 {u8(17)} else {u8(0xcc)}};index_checks++
     }
    }
    if vector {jvalues[0]=u64(count)
     for i in 0 .. bytes.len {bytes[i]=0xcc}
     if _:=ip.validate(bindings,ip.steps()) {panic('out-of-range projected integer-extrema')};untouched(bytes)
     if _:=ip.run(mut bindings,ip.steps()) {panic('out-of-range prepared integer-extrema')};untouched(bytes)
     if _:=p.run_memory_function(ir,stream,pools,bodies,ix,mut bindings,ip.steps()) {panic('out-of-range direct integer-extrema')};untouched(bytes);index_checks+=3
    }
    ip.free();unsafe{bytes.free();for slot in 0..3 {bindings[slot].values.free()};bindings.free()}
   }
   plan.free();loaded.free();coexisting.free();unsafe{input.free();input_bindings.free();left.free();right.free();expected.free();output.free();bs.free()}
  }
 }
 assert native_lanes==557056 && scalar_checks==133120 && index_checks==4288 && metadata==704 && budgets==256 && coexist==4096 && bounds==384
 os.write_file(root+'/result.txt','AIR-EXTREMA64-WIDTH: i${width}, ${native_lanes} native vector lanes (typed/loaded, each direct/prepared), ${scalar_checks} native-scalar/scalar/integer comparisons, ${index_checks} address checks, ${metadata} metadata refusals, ${budgets} prewrite budgets, ${coexist} AIR/LLVM coexistence cases, ${bounds} buffer bounds refusals PASS\n')!
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 mut availability:=''
 for name in ['llvm.smin','llvm.smax','llvm.umin','llvm.umax'] {availability+='${name}: '+C.LLVMLookupIntrinsicID(name.str,usize(name.len)).str()+'\n'}
 os.write_file(root+'/intrinsic-availability.txt',availability+'Native references compare/select signed or unsigned i64 vectors without AIR calls. Scalar LLVM and vector AIR declarations coexist.\n')!
 controls(os.args[1],root+'/controls')!
 negative_profiles(os.args[1],root+'/guards')!
 for width in [64] {run_width(os.args[1],root+'/w${width}',width)!}
 result:='AIR-NATIVE-VECTOR-EXTREMA64: i64 and counts 1-16, signed/unsigned min/max; 557056 native vector lanes (typed/loaded, each direct/prepared), 133120 native-scalar/scalar/integer comparisons, 4288 address checks, 704 metadata refusals, 256 prewrite budgets, 4096 AIR/LLVM coexistence cases, 384 buffer bounds refusals, 60 negative profiles and 307 state/loop/limit controls PASS\n'
 os.write_file(root+'/result.txt',result)!;print(result)
}
fn controls(assembler string, root string) ! {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 modes:= ['defined','left_poison','right_poison','left_undef','right_undef','unused_poison','unused_undef','source_freeze','result_freeze','result_undef']
 for id in ['smin','smax','umin','umax'] {
  s.write_string('declare <2 x i64> @${air_name(id)}.v2i64(<2 x i64>, <2 x i64>) #0\n')
  for mode in modes {
   left:=if mode in ['left_poison','result_freeze'] {'<i64 poison, i64 1>'} else if mode in ['left_undef','source_freeze','result_undef'] {'<i64 undef, i64 1>'} else if mode=='unused_poison' {'<i64 9223372036854775808, i64 poison>'} else if mode=='unused_undef' {'<i64 9223372036854775808, i64 undef>'} else {'<i64 9223372036854775808, i64 1>'}
   right:=if mode=='right_poison' {'<i64 poison, i64 -1>'} else if mode=='right_undef' {'<i64 undef, i64 -1>'} else {'<i64 -1, i64 -1>'}
   ops:='${if mode=='source_freeze' {'%source = freeze <2 x i64> '+left+'\n'}else{''}}%r = call <2 x i64> @${air_name(id)}.v2i64(<2 x i64> ${if mode=='source_freeze' {'%source'}else{left}}, <2 x i64> ${right})\n ${if mode in ['result_freeze','result_undef'] {'%f = freeze <2 x i64> %r\n'}else{''}}%v = extractelement <2 x i64> %${if mode in ['result_freeze','result_undef'] {'f'}else{'r'}}, i64 0\n'
   for address in [false,true] {
    s.write_string('define void @state_${id}_${mode}_${address}(ptr %out) {store i8 17, ptr %out\n ${ops}${if address {'%masked = and i64 %v, 63\n %wide = or i64 %masked,0\n %p = getelementptr i8, ptr %out, i64 %wide\n store i8 42, ptr %p\n'}else{'%p = getelementptr i8, ptr %out, i64 8\n store i64 %v, ptr %p, align 1\n'}}ret void }\n')
   }
  }
  s.write_string('define i64 @loop_${id}(i64 %count) { entry: br label %body\n body: %a = phi <2 x i64> [<i64 9223372036854775808, i64 1>, %entry], [%r, %body]\n %i = phi i64 [0, %entry], [%next, %body]\n %t = xor <2 x i64> %a, <i64 -9223372036854775808, i64 -9223372036854775808>\n %r = call <2 x i64> @${air_name(id)}.v2i64(<2 x i64> %t, <2 x i64> <i64 -1, i64 -1>)\n %next = add i64 %i, 1\n %c = icmp ult i64 %next, %count\n br i1 %c, label %body, label %done\n done: %v = extractelement <2 x i64> %r, i64 0\n ret i64 %v }\n')
 }
 s.write_string('declare <2 x i64> @alias(<2 x i64>, <2 x i64>) #0\n define void @duplicate(ptr %out) {store i8 17, ptr %out\n %a = call <2 x i64> @air.min.s.v2i64(<2 x i64> zeroinitializer, <2 x i64> zeroinitializer)\n %b = call <2 x i64> @alias(<2 x i64> zeroinitializer, <2 x i64> zeroinitializer)\n ret void }\n attributes #0 = { nounwind memory(none) }\n')
 data:=assemble(assembler,root,s.str())!;verify(data)!
 stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut checks:=0
 for id in ['smin','smax','umin','umax'] { for mode in modes { for address in [false,true] {
  f:=fi(ir,'state_${id}_${mode}_${address}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  bad:=mode in ['left_poison','right_poison','left_undef','right_undef','unused_undef','result_undef']
  value:=if mode=='source_freeze' {oracle(64,id,0,0xffffffffffffffff)} else if mode=='result_freeze' {u64(0)} else {oracle(64,id,0x8000000000000000,0xffffffffffffffff)}
  for prepared in [false,true] {
   mut bytes:=[]u8{len:96,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
   if address&&bad {if _:=plan.validate(bs,plan.steps()) {panic('bad integer-extrema index validate')};untouched(bytes)}else{plan.validate(bs,plan.steps())!;untouched(bytes)}
   if prepared {if _:=plan.run(mut bs,plan.steps()) {assert !bad}else{assert bad,err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert !bad}else{assert bad,err.msg()}}
   for i,b in bytes {assert b==if address&&bad {u8(0xcc)} else if !bad&&address&&i==3+int(value&63) {u8(42)} else if i==3 {u8(17)} else if !bad&&!address&&i>=11&&i<19 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}, '${id} ${mode} address=${address} byte=${i}'}
   checks++;unsafe{bytes.free();bs.free()}
  };plan.free()
 } } }
 for id in ['smin','smax','umin','umax'] { for count in [u64(1),2,3,7,16,257,513,1024]! {
  mut expected:=u64(0x8000000000000000);for _ in u64(0)..count {expected=oracle(64,id,expected^u64(0x8000000000000000),0xffffffffffffffff)}
  for integer in [false,true] {
   f:=fi(ir,'loop_${id}');r:=if integer {v:=p.run_integer_function(ir,stream,pools,bodies,f,[count],int(count*7+3))!;airbitcode.IRScalarRun{value:v.value,poison:v.poison,steps:v.steps}}else{p.run_scalar_function(ir,stream,pools,bodies,f,[count],int(count*7+3))!}
   assert !r.poison&&r.value==expected&&r.steps==int(count*7+3)
   if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[count],int(count*7+2)) {panic('loop short budget')};checks+=2
  }
 } }
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'air.min.s.v2i64'}
 mut bytes:=[]u8{len:96,init:0xcc};defer{unsafe{bytes.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}];defer{unsafe{bs.free()}}
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10) {panic('duplicate integer-extrema')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration',err.msg()};untouched(bytes);checks++
 callee:=fi(ir,'air.min.s.v2i64');old:=functions[callee]
 for name in ['air.min.s.v17i64','air.min.s.v2i31','air.min.s.v02i64','air.min.s.v2i64.spoof','air.min.u.v2f32'] {
  functions[callee]=airbitcode.IRFunction{...old,name:name};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'state_smin_defined_false'),mut bs,20) {panic('bad declaration integer-extrema')};untouched(bytes);checks++
 };functions[callee]=old
 mut values:=stream.values.clone();defer{unsafe{values.free()}};changed:=airbitcode.Stream{...stream,values:values};mut group:=-1
 for record in stream.records {if stream.blocks[record.block].id==10&&record.code==3&&record.values_count>=4&&values[record.values_start+1]==0xffffffff&&values[record.values_start+2]==0 {group=record.values_start;break}}
 assert group>=0;values[group+3]=54
 if _:=p.run_memory_function(ir,changed,pools,bodies,fi(ir,'state_smin_defined_false'),mut bs,20) {panic('strictfp integer-extrema')};untouched(bytes);checks++
 for storage in [false,true] {for over in [false,true] {for api in ['memory','void','scalar'] {limits(assembler,root+'/limit-${storage}-${over}-${api}',storage,over,api)!;checks++}}}
 assert checks==307
 os.write_file(root+'/result.txt','AIR-EXTREMA64-CONTROLS: ${checks} state/freeze/strict-undef/prewrite-address, simultaneous vector-PHI loop reuse/budget, duplicate/declaration/attribute and shared work/storage boundary checks PASS\n')!
}
fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};t:='<${count} x i64>';mut s:=strings.new_builder(16777216);s.write_string('declare ${t} @air.min.s.v${count}i64(${t}, ${t})\n define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')}
 for i in 0..if storage&&over{4097}else{4096}{s.write_string('%n${i} = call ${t} @air.min.s.v${count}i64(${t} zeroinitializer, ${t} zeroinitializer)\n')};if !storage{for i in 0..if over{50213}else{50212}{s.write_string('%x${i} = extractelement ${t} %n4095, i64 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage{'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'};f:=fi(ir,name)
 if over{if name=='memory'{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000){panic('memory limit')}else{assert err.msg()==diagnostic,err.msg()};untouched(output)}else if name=='void'{if _:=p.run_void_function(ir,stream,pools,bodies,f,[],70000){panic('void limit')}else{assert err.msg()==diagnostic,err.msg()}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],70000){panic('scalar limit')}else{assert err.msg()==diagnostic,err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],70000){panic('integer limit')}else{assert err.msg()==diagnostic,err.msg()}}}
 else{steps:=if storage{4097}else{54309};if name=='memory'{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000)!.steps==steps+1;assert output[0]==17}else if name=='void'{assert p.run_void_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}else{assert p.run_scalar_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps;assert p.run_integer_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}}
 unsafe{output.free();bs.free()};os.write_file(out+'/result.txt','AIR-EXTREMA64-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}

fn rejected_profile(assembler string,out string,body string) ! {
 data:=assemble(assembler,out,'target datalayout = "e-p:64:64"\n'+body)!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut output:=[]u8{len:96,init:0xcc};defer{unsafe{output.free()}};mut bindings:=[airbitcode.IRMemoryBinding{data:output,writable:true}];defer{unsafe{bindings.free()}}
 f:=fi(ir,'reject')
 if plan:=p.prepare_memory_function(ir,stream,pools,bodies,f){plan.free();panic('invalid AIR vector integer-extrema profile')}
 if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bindings,16){panic('invalid direct AIR vector integer-extrema profile')};untouched(output)
}

fn negative_profiles(assembler string,root string) ! {
 mut guards:=0
 for family in ['min','max'] { for sign in ['s','u'] {
  name:='air.${family}.${sign}.v2i64'
  for t in ['<2 x float>','<2 x i16>','<1 x i64>'] {
   rejected_profile(assembler,root+'/type-${guards}','declare ${t} @${name}(${t},${t})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call ${t} @${name}(${t} zeroinitializer,${t} zeroinitializer)\n ret void }\n')!;guards++
  }
  for side in 0..2 {mut types:=[]string{len:2,init:'<2 x i64>'};types[side]='<2 x i16>';args:=types.map(it+' zeroinitializer').join(',')
   rejected_profile(assembler,root+'/mixed-${guards}','declare <2 x i64> @${name}(${types.join(',')})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${name}(${args})\n ret void }\n')!;guards++
  }
  for arity in [1,3]! {types:=[]string{len:arity,init:'<2 x i64>'}.join(',');args:=[]string{len:arity,init:'<2 x i64> zeroinitializer'}.join(',')
   rejected_profile(assembler,root+'/arity-${guards}','declare <2 x i64> @${name}(${types})\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${name}(${args})\n ret void }\n')!;guards++
  }
  for suffix in ['v0i64','v02i64','v17i64','v2i16','v2i63','v2i64.spoof','v2f32'] {
   rejected_profile(assembler,root+'/name-${guards}','declare <2 x i64> @air.${family}.${sign}.${suffix}(<2 x i64>,<2 x i64>)\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @air.${family}.${sign}.${suffix}(<2 x i64> zeroinitializer,<2 x i64> zeroinitializer)\n ret void }\n')!;guards++
  }
  rejected_profile(assembler,root+'/definition-${guards}','define <2 x i64> @${name}(<2 x i64> %a,<2 x i64> %b) {ret <2 x i64> zeroinitializer}\n define void @reject(ptr %out) {store i8 17,ptr %out\n %r = call <2 x i64> @${name}(<2 x i64> zeroinitializer,<2 x i64> zeroinitializer)\n ret void }\n')!;guards++
 }
 }
 assert guards==60
 os.write_file(root+'/result.txt','AIR-VECTOR-EXTREMA64-GUARDS: ${guards} name/type/arity/definition profiles reject in preparation and direct execution before marker writes PASS\n')!
}
