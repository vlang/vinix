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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'canonicalize'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('ref_') || f.declaration { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
fn oracle(bits u32, signed bool, a u64, b u64) u64 {
	mask := width_mask(int(bits)); sign := u64(1) << (bits - 1)
	x := a & mask; y := b & mask
	nx := signed && x & sign != 0; ny := signed && y & sign != 0
	mx := if nx { (u64(0) - x) & mask } else { x }
	my := if ny { (u64(0) - y) & mask } else { y }
	mut columns := [128]u32{}
	for i in u32(0) .. bits { if mx & (u64(1) << i) != 0 { for j in u32(0) .. bits { columns[i + j] += u32((my >> j) & 1) } } }
	mut carry := u32(0)
	for i in u32(0) .. bits * 2 { sum := columns[i] + carry; columns[i] = sum & 1; carry = sum >> 1 }
	if nx != ny {
		carry = 1
		for i in u32(0) .. bits * 2 { sum := (columns[i] ^ 1) + carry; columns[i] = sum & 1; carry = sum >> 1 }
	}
	mut result := u64(0)
	for i in u32(0) .. bits { result |= u64(columns[bits + i]) << i }
	return result
}
fn width_mask(width int) u64 { return if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 } }
fn fi(ir airbitcode.IRModule, name string) int { for i,f in ir.functions { if f.name == name { return i } }; panic(name) }
fn untouched(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn word(width int, sample int, lane int, side int) u64 {
 sign := u64(1) << u32(width - 1)
 return [u64(0), 1, width_mask(width), sign, sign - 1, sign + 1, u64(sample + lane * 13 + side * 7) * u64(0x9e3779b97f4a7c15), u64(sample + lane * 31 + side * 17) * u64(0xd1b54a32d192ed03)]![(sample + lane + side * 3) % 8] & width_mask(width)
}
fn wide_ops(width int, count int, signed bool) string {
 t := '<${count} x i${width}>'; wide := '<${count} x i${width * 2}>'
 mut amounts := []string{}; for _ in 0 .. count { amounts << 'i${width * 2} ${width}' }
 return '%aa = ${if signed { 'sext' } else { 'zext' }} ${t} %a to ${wide}\n %bb = ${if signed { 'sext' } else { 'zext' }} ${t} %b to ${wide}\n %product = mul ${wide} %aa, %bb\n %high = lshr ${wide} %product, <${amounts.join(', ')}>\n %raw = trunc ${wide} %high to ${t}\n'
}
fn fixture(width int) string {
 mut s := strings.new_builder(1048576); s.write_string('target datalayout = "e-p:64:64"\n')
 for id in ['smulh','umulh'] {
  s.write_string('declare i${width} @llvm.${id}.i${width}(i${width}, i${width})\n define i${width} @q_${id}(i${width} %x, i${width} %y) { %r = call i${width} @llvm.${id}.i${width}(i${width} %x, i${width} %y)\n ret i${width} %r }\n')
  for count in 1 .. 17 {
   t := '<${count} x i${width}>'; name := 'llvm.${id}.v${count}i${width}'
   s.write_string('declare ${t} @${name}(${t}, ${t})\n')
   s.write_string('define void @ref_${id}_${count}(ptr %left, ptr %right, ptr %out) { %av = load <${count} x i64>, ptr %left, align 1\n %bv = load <${count} x i64>, ptr %right, align 1\n %a = ${if width == 64 { 'or ${t} %av, zeroinitializer' } else { 'trunc <${count} x i64> %av to ${t}' }}\n %b = ${if width == 64 { 'or ${t} %bv, zeroinitializer' } else { 'trunc <${count} x i64> %bv to ${t}' }}\n ${wide_ops(width,count,id=='smulh')}%result = ${if width == 64 { 'or ${t} %raw, zeroinitializer' } else { 'zext ${t} %raw to <${count} x i64>' }}\n store <${count} x i64> %result, ptr %out, align 1\n ret void }\n')
   ops := '%a = insertelement ${t} zeroinitializer, i${width} %x, i32 %j\n %b = insertelement ${t} zeroinitializer, i${width} %y, i32 %j\n %r = call ${t} @${name}(${t} %a, ${t} %b)\n %e = extractelement ${t} %r, i32 %j\n'
   s.write_string('define i${width} @s_${id}_${count}(i${width} %x, i${width} %y, i32 %j) { ${ops}ret i${width} %e }\n')
   s.write_string('define void @m_${id}_${count}(${t} %a, ${t} %b, ptr %out) { store i8 17, ptr %out\n %r = call ${t} @${name}(${t} %a, ${t} %b)\n')
   for lane in 0 .. count {
    s.write_string('%e${lane} = extractelement ${t} %r, i32 ${lane}\n %z${lane} = ${if width == 64 { 'or i64 %e${lane}, 0' } else { 'zext i${width} %e${lane} to i64' }}\n %p${lane} = getelementptr i64, ptr %out, i64 ${lane + 1}\n store i64 %z${lane}, ptr %p${lane}, align 1\n')
   }; s.write_string('ret void }\n')
   for vector in [false,true] {
    scalar_ops := '%e = call i${width} @llvm.${id}.i${width}(i${width} %x, i${width} %y)\n'
    s.write_string('define void @index_${id}_${count}_${vector}(i${width} %x, i${width} %y, i32 %j, ptr %out) { store i8 17, ptr %out\n ${if vector { ops } else { scalar_ops }}%idx = and i${width} %e, ${width_mask(width)&63}\n %offset = ${if width==64 { 'or i64 %idx, 0' } else { 'zext i${width} %idx to i64' }}\n %p = getelementptr i8, ptr %out, i64 %offset\n store i8 42, ptr %p\n ret void }\n')
   }
  }
 }
 return s.str()
}
fn run_width(assembler string, root string, width int) ! {
 data := assemble(assembler, root, fixture(width))!; verify(data)!
 stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream,pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream,pools,bodies)!; defer { p.free() }
 native := native_module(data,root,ir)!; defer { native.close() }
 mut native_lanes := 0; mut scalar_checks := 0; mut index_checks := 0; mut metadata := 0; mut budgets := 0
 mut rows := os.create(root+'/comparisons.tsv')!; defer { rows.close() }; rows.writeln('operation\tlanes\tsample\tlane\tleft\tright\thigh')!
 for id in ['smulh','umulh'] {
  single := C.LLVMGetFunctionAddress(native.engine,'ref_${id}_1'.str); assert single != 0
  for sample in 0 .. 512 {
   a := word(width,sample,0,0); b := word(width,sample,0,1); mut reference := u64(0)
   unsafe { NativeCast(voidptr(single))(&a,&b,&reference) }
   r := p.run_scalar_function(ir,stream,pools,bodies,fi(ir,'q_${id}'),[a|~width_mask(width),b|~width_mask(width)],2)!
   assert !r.poison && r.value == reference && reference == oracle(u32(width),id=='smulh',a,b); scalar_checks++
  }
  for count in 1 .. 17 {
   f := fi(ir,'m_${id}_${count}'); sf := fi(ir,'s_${id}_${count}'); plan := p.prepare_memory_function(ir,stream,pools,bodies,f)!
   assert plan.steps() == count*4+3
   address := C.LLVMGetFunctionAddress(native.engine,'ref_${id}_${count}'.str); assert address != 0
   mut left := []u64{len:count}; mut right := []u64{len:count}; mut expected := []u64{len:count}
   mut output := []u8{len:count*8+16,init:0xcc}; mut bs := [airbitcode.IRMemoryBinding{values:left},airbitcode.IRMemoryBinding{values:right},airbitcode.IRMemoryBinding{data:output,offset:3,writable:true}]
   for sample in 0 .. 16 {
    for lane in 0 .. count { left[lane] = word(width,sample,lane,0)|~width_mask(width); right[lane] = word(width,sample,lane,1)|~width_mask(width) }
    unsafe { NativeCast(voidptr(address))(left.data,right.data,expected.data) }
    for lane in 0 .. count { assert expected[lane] == oracle(u32(width),id=='smulh',left[lane],right[lane]); rows.writeln('${id}\t${count}\t${sample}\t${lane}\t${left[lane]}\t${right[lane]}\t${expected[lane]}')!; native_lanes++ }
    j := sample % count
    for integer in [false,true] {
     args := [left[j],right[j],u64(j)]
     r := if integer { v:=p.run_integer_function(ir,stream,pools,bodies,sf,args,5)!; airbitcode.IRScalarRun{value:v.value,poison:v.poison,steps:v.steps} } else { p.run_scalar_function(ir,stream,pools,bodies,sf,args,5)! }
     assert !r.poison && r.value == expected[j] && r.steps==5; scalar_checks++; unsafe { args.free() }
    }
    for prepared in [false,true] {
     for i in 0 .. output.len { output[i]=0xcc }; plan.validate(bs,plan.steps())!; untouched(output)
     if prepared { assert plan.run(mut bs,plan.steps())!.steps == plan.steps() } else { assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps())!.steps == plan.steps() }
     for i,b in output { assert b == if i==3 {u8(17)} else if i>=11 && i<11+count*8 {u8(expected[(i-11)/8] >> u32(((i-11)%8)*8))} else {u8(0xcc)}, '${id} ${width} ${count} ${sample} byte=${i}' }
    }
   }
   for i in 0 .. output.len { output[i]=0xcc }
   if _ := plan.run(mut bs,plan.steps()-1) { panic('prepared short budget') }; untouched(output)
   if _ := p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()-1) { panic('direct short budget') }; untouched(output); budgets+=2
   scope:=bodies.scopes[f+1]
   for index in scope.instructions_start .. scope.instructions_start+scope.instructions_count {
    op:=p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 34 {continue}
    for changed in [airbitcode.IRTypedInstruction{...op,flags:32769},airbitcode.IRTypedInstruction{...op,fast_math_flags:1},airbitcode.IRTypedInstruction{...op,calling_convention:8},airbitcode.IRTypedInstruction{...op,attribute_set:1},airbitcode.IRTypedInstruction{...op,call_signature:-1},airbitcode.IRTypedInstruction{...op,callee_function:-1},airbitcode.IRTypedInstruction{...op,operands_count:2},airbitcode.IRTypedInstruction{...op,result_type:-1}] {
     p.instructions[index]=changed; if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {panic('mulh metadata')}; untouched(output); metadata++
    };p.instructions[index]=op
   }
   for vector in [false,true] {
    ix:=fi(ir,'index_${id}_${count}_${vector}'); ip:=p.prepare_memory_function(ir,stream,pools,bodies,ix)!
    mut bytes:=[]u8{len:96,init:0xcc}; mut xvalues:=[u64(0)];mut yvalues:=[u64(0)];mut jvalues:=[u64(0)];mut bindings:=[airbitcode.IRMemoryBinding{values:xvalues},airbitcode.IRMemoryBinding{values:yvalues},airbitcode.IRMemoryBinding{values:jvalues},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
    for sample in 0 .. 16 {
     a:=word(width,sample,0,0); b:=word(width,sample,0,1); xvalues[0]=a|~width_mask(width);yvalues[0]=b|~width_mask(width);jvalues[0]=u64(sample%count)
     offset:=int(oracle(u32(width),id=='smulh',a,b)&63)
     for prepared in [false,true] {
      for i in 0 .. bytes.len {bytes[i]=0xcc};ip.validate(bindings,ip.steps())!;untouched(bytes)
      if prepared {ip.run(mut bindings,ip.steps())!} else {p.run_memory_function(ir,stream,pools,bodies,ix,mut bindings,ip.steps())!}
      for i,bv in bytes {assert bv==if i==3+offset {u8(42)} else if i==3 {u8(17)} else {u8(0xcc)}};index_checks++
     }
    }
    if vector {jvalues[0]=u64(count)
     for i in 0 .. bytes.len {bytes[i]=0xcc}
     if _:=ip.validate(bindings,ip.steps()) {panic('out-of-range projected mulh')};untouched(bytes)
     if _:=ip.run(mut bindings,ip.steps()) {panic('out-of-range prepared mulh')};untouched(bytes)
     if _:=p.run_memory_function(ir,stream,pools,bodies,ix,mut bindings,ip.steps()) {panic('out-of-range direct mulh')};untouched(bytes);index_checks+=3
    }
    ip.free();unsafe{bytes.free();for slot in 0..3 {bindings[slot].values.free()};bindings.free()}
   }
   plan.free();unsafe{left.free();right.free();expected.free();output.free();bs.free()}
  }
 }
 assert native_lanes==4352 && scalar_checks==2048 && index_checks==2144 && metadata==256 && budgets==64
 os.write_file(root+'/result.txt','AIR-MULH-WIDTH: i${width}, ${native_lanes} native vector lanes, ${scalar_checks} native-scalar/scalar/integer comparisons, ${index_checks} address checks, ${metadata} metadata refusals, ${budgets} prewrite budgets PASS\n')!
}
fn main() {
 assert os.args.len==3;root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 mut availability:=''
 for name in ['llvm.smulh','llvm.umulh'] {availability+='${name}: '+C.LLVMLookupIntrinsicID(name.str,usize(name.len)).str()+'\n'}
 os.write_file(root+'/intrinsic-availability.txt',availability+'Native references always use widened sext/zext, mul, lshr and trunc, including i128.\n')!
 controls(os.args[1],root+'/controls')!
 for width in 1 .. 65 {run_width(os.args[1],root+'/w${width}',width)!}
 result:='AIR-MULH: all i1-i64 and counts 1-16, both signednesses; 278528 native vector lanes, 131072 native-scalar/scalar/integer comparisons, 137216 address checks, 16384 metadata refusals, 4096 prewrite budgets PASS\n'
 os.write_file(root+'/result.txt',result)!;print(result)
}
fn controls(assembler string, root string) ! {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 modes:= ['defined','left_poison','right_poison','left_undef','right_undef','unused_poison','unused_undef','source_freeze','result_freeze','result_undef']
 for id in ['smulh','umulh'] {
  s.write_string('declare <2 x i32> @llvm.${id}.v2i32(<2 x i32>, <2 x i32>) #0\n')
  for mode in modes {
   left:=if mode in ['left_poison','result_freeze'] {'<i32 poison, i32 1>'} else if mode in ['left_undef','source_freeze','result_undef'] {'<i32 undef, i32 1>'} else if mode=='unused_poison' {'<i32 2147483648, i32 poison>'} else if mode=='unused_undef' {'<i32 2147483648, i32 undef>'} else {'<i32 2147483648, i32 1>'}
   right:=if mode=='right_poison' {'<i32 poison, i32 -1>'} else if mode=='right_undef' {'<i32 undef, i32 -1>'} else {'<i32 -1, i32 -1>'}
   ops:='${if mode=='source_freeze' {'%source = freeze <2 x i32> '+left+'\n'}else{''}}%r = call <2 x i32> @llvm.${id}.v2i32(<2 x i32> ${if mode=='source_freeze' {'%source'}else{left}}, <2 x i32> ${right})\n ${if mode in ['result_freeze','result_undef'] {'%f = freeze <2 x i32> %r\n'}else{''}}%v = extractelement <2 x i32> %${if mode in ['result_freeze','result_undef'] {'f'}else{'r'}}, i32 0\n'
   for address in [false,true] {
    s.write_string('define void @state_${id}_${mode}_${address}(ptr %out) {store i8 17, ptr %out\n ${ops}${if address {'%masked = and i32 %v, 63\n %wide = zext i32 %masked to i64\n %p = getelementptr i8, ptr %out, i64 %wide\n store i8 42, ptr %p\n'}else{'%p = getelementptr i8, ptr %out, i64 8\n store i32 %v, ptr %p, align 1\n'}}ret void }\n')
   }
  }
  s.write_string('define i32 @loop_${id}(i32 %count) { entry: br label %body\n body: %a = phi <2 x i32> [<i32 2147483648, i32 1>, %entry], [%r, %body]\n %i = phi i32 [0, %entry], [%next, %body]\n %r = call <2 x i32> @llvm.${id}.v2i32(<2 x i32> %a, <2 x i32> <i32 -1, i32 -1>)\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %count\n br i1 %c, label %body, label %done\n done: %v = extractelement <2 x i32> %r, i32 0\n ret i32 %v }\n')
 }
 s.write_string('declare <2 x i32> @alias(<2 x i32>, <2 x i32>) #0\n define void @duplicate(ptr %out) {store i8 17, ptr %out\n %a = call <2 x i32> @llvm.smulh.v2i32(<2 x i32> zeroinitializer, <2 x i32> zeroinitializer)\n %b = call <2 x i32> @alias(<2 x i32> zeroinitializer, <2 x i32> zeroinitializer)\n ret void }\n attributes #0 = { nounwind memory(none) }\n')
 data:=assemble(assembler,root,s.str())!;verify(data)!
 stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()}
 mut checks:=0
 for id in ['smulh','umulh'] { for mode in modes { for address in [false,true] {
  f:=fi(ir,'state_${id}_${mode}_${address}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
  bad:=mode in ['left_poison','right_poison','left_undef','right_undef','unused_undef','result_undef']
  value:=if mode in ['source_freeze','result_freeze'] {u64(0)} else {oracle(32,id=='smulh',0x80000000,0xffffffff)}
  for prepared in [false,true] {
   mut bytes:=[]u8{len:96,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
   if address&&bad {if _:=plan.validate(bs,plan.steps()) {panic('bad mulh index validate')};untouched(bytes)}else{plan.validate(bs,plan.steps())!;untouched(bytes)}
   if prepared {if _:=plan.run(mut bs,plan.steps()) {assert !bad}else{assert bad,err.msg()}}else{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert !bad}else{assert bad,err.msg()}}
   for i,b in bytes {assert b==if address&&bad {u8(0xcc)} else if !bad&&address&&i==3+int(value&63) {u8(42)} else if i==3 {u8(17)} else if !bad&&!address&&i>=11&&i<15 {u8(value>>u32((i-11)*8))}else{u8(0xcc)}, '${id} ${mode} address=${address} byte=${i}'}
   checks++;unsafe{bytes.free();bs.free()}
  };plan.free()
 } } }
 for id in ['smulh','umulh'] { for count in [u64(1),2,3,7,16,257,513,1024]! {
  mut expected:=u64(0x80000000);for _ in u64(0)..count {expected=oracle(32,id=='smulh',expected,0xffffffff)}
  for integer in [false,true] {
   f:=fi(ir,'loop_${id}');r:=if integer {v:=p.run_integer_function(ir,stream,pools,bodies,f,[count],int(count*6+3))!;airbitcode.IRScalarRun{value:v.value,poison:v.poison,steps:v.steps}}else{p.run_scalar_function(ir,stream,pools,bodies,f,[count],int(count*6+3))!}
   assert !r.poison&&r.value==expected&&r.steps==int(count*6+3)
   if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[count],int(count*6+2)) {panic('loop short budget')};checks+=2
  }
 } }
 mut functions:=ir.functions.clone();defer{unsafe{functions.free()}};view:=airbitcode.IRModule{...ir,functions:functions};alias:=fi(ir,'alias');functions[alias]=airbitcode.IRFunction{...functions[alias],name:'llvm.smulh.v2i32'}
 mut bytes:=[]u8{len:96,init:0xcc};defer{unsafe{bytes.free()}};mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}];defer{unsafe{bs.free()}}
 if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'duplicate'),mut bs,10) {panic('duplicate mulh')}else{assert err.msg()=='AIR vector intrinsic: duplicate reserved declaration',err.msg()};untouched(bytes);checks++
 callee:=fi(ir,'llvm.smulh.v2i32');old:=functions[callee]
 for name in ['llvm.smulh.v17i32','llvm.smulh.v2i31','llvm.smulh.v02i32','llvm.smulh.v2i32.spoof','llvm.umulh.v2f32'] {
  functions[callee]=airbitcode.IRFunction{...old,name:name};if _:=p.run_memory_function(view,stream,pools,bodies,fi(ir,'state_smulh_defined_false'),mut bs,20) {panic('bad declaration mulh')};untouched(bytes);checks++
 };functions[callee]=old
 mut values:=stream.values.clone();defer{unsafe{values.free()}};changed:=airbitcode.Stream{...stream,values:values};mut group:=-1
 for record in stream.records {if stream.blocks[record.block].id==10&&record.code==3&&record.values_count>=4&&values[record.values_start+1]==0xffffffff&&values[record.values_start+2]==0 {group=record.values_start;break}}
 assert group>=0;values[group+3]=54
 if _:=p.run_memory_function(ir,changed,pools,bodies,fi(ir,'state_smulh_defined_false'),mut bs,20) {panic('strictfp mulh')};untouched(bytes);checks++
 for storage in [false,true] {for over in [false,true] {for api in ['memory','void','scalar'] {limits(assembler,root+'/limit-${storage}-${over}-${api}',storage,over,api)!;checks++}}}
 assert checks==163
 os.write_file(root+'/result.txt','AIR-MULH-CONTROLS: ${checks} state/freeze/strict-undef/prewrite-address, simultaneous vector-PHI loop reuse/budget, duplicate/declaration/attribute and shared work/storage boundary checks PASS\n')!
}
fn limits(assembler string,out string,storage bool,over bool,name string) ! {
 count:=if storage{1}else{16};t:='<${count} x i16>';mut s:=strings.new_builder(16777216);s.write_string('declare ${t} @llvm.smulh.v${count}i16(${t}, ${t})\n define ${if name=='scalar'{'i64'}else{'void'}} @${name}(${if name=='memory'{'ptr %out'}else{''}}) {\n');if name=='memory'{s.write_string('store i8 17, ptr %out\n')}
 for i in 0..if storage&&over{4097}else{4096}{s.write_string('%n${i} = call ${t} @llvm.smulh.v${count}i16(${t} zeroinitializer, ${t} zeroinitializer)\n')};if !storage{for i in 0..if over{50213}else{50212}{s.write_string('%x${i} = extractelement ${t} %n4095, i32 0\n')}};s.write_string('ret ${if name=='scalar'{'i64 0'}else{'void'}} }\n')
 data:=assemble(assembler,out,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;defer{stream.free()};ir:=stream.ir_module(data)!;defer{ir.free()};pools:=ir.constant_pools(stream)!;defer{pools.free()};bodies:=ir.function_bodies(stream,pools)!;defer{bodies.free()};p:=ir.typed_operands(stream,pools,bodies)!;defer{p.free()};mut output:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:output,writable:true}];diagnostic:=if storage{'AIR vector: update result limit'}else{'AIR vector: constant lane work limit'};f:=fi(ir,name)
 if over{if name=='memory'{if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000){panic('memory limit')}else{assert err.msg()==diagnostic,err.msg()};untouched(output)}else if name=='void'{if _:=p.run_void_function(ir,stream,pools,bodies,f,[],70000){panic('void limit')}else{assert err.msg()==diagnostic,err.msg()}}else{if _:=p.run_scalar_function(ir,stream,pools,bodies,f,[],70000){panic('scalar limit')}else{assert err.msg()==diagnostic,err.msg()};if _:=p.run_integer_function(ir,stream,pools,bodies,f,[],70000){panic('integer limit')}else{assert err.msg()==diagnostic,err.msg()}}}
 else{steps:=if storage{4097}else{54309};if name=='memory'{assert p.run_memory_function(ir,stream,pools,bodies,f,mut bs,70000)!.steps==steps+1;assert output[0]==17}else if name=='void'{assert p.run_void_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}else{assert p.run_scalar_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps;assert p.run_integer_function(ir,stream,pools,bodies,f,[],70000)!.steps==steps}}
 unsafe{output.free();bs.free()};os.write_file(out+'/result.txt','AIR-MULH-LIMIT: ${name} storage=${storage} over=${over} PASS\n')!
}
