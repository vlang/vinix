// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native references reduce only defined lanes. Separate interpreter checks
// cover poison, strict undef errors, freezing and the pre-write boundary.
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
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
fn C.LLVMWriteBitcodeToFile(voidptr, &char) int

struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel           u32
	CodeModel          int
	NoFramePointerElim int
	EnableFastISel     int
	MCJMM              voidptr
}

fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)

type NativeCast = fn (voidptr, voidptr, voidptr)

fn assemble(assembler_path string, out string, source string) ![]u8 {
	assert !os.exists(out)
	os.mkdir_all(out)!
	os.write_file(out + '/input.ll', source)!
	mut a := os.new_process(assembler_path)
	a.set_args([out + '/input.ll', '-o', out + '/input.bc'])
	a.set_redirect_stdio_merged()
	a.run()
	log := a.stdout_slurp()
	a.wait()
	code := a.code
	a.close()
	os.write_file(out + '/assemble.log', log)!
	assert code == 0, log
	return os.read_bytes(out + '/input.bc')!
}

fn verify(data []u8) ! {
	context := C.LLVMContextCreate()
	defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify')
	defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }
	assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	defer { C.LLVMDisposeModule(module_ptr) }
	mut message := &char(unsafe { nil })
	assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}

struct NativeModule {
	context voidptr
	buffer  voidptr
	engine  voidptr
}

fn native_module(data []u8, out string) !NativeModule {
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0
	C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate()
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'indexed-memory')
	mut module_ptr := unsafe { nil }
	assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil })
	assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
	message = unsafe { nil }

	C.LLVMSetDataLayout(module_ptr, c'')
	triple := C.LLVMGetDefaultTargetTriple()
	C.LLVMSetTarget(module_ptr, triple)
	os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!
	C.LLVMDisposeMessage(triple)
	path := out + '/native-input.bc'
	assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
	cpu := C.LLVMGetHostCPUName()
	features := C.LLVMGetHostCPUFeatures()
	os.write_file(out + '/native-features.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut f := C.LLVMGetFirstFunction(module_ptr)
	for f != unsafe { nil } {
		C.LLVMAddTargetDependentFunctionAttr(f, c'target-cpu', cpu)
		C.LLVMAddTargetDependentFunctionAttr(f, c'target-features', features)
		f = C.LLVMGetNextFunction(f)
	}
	C.LLVMDisposeMessage(cpu)
	C.LLVMDisposeMessage(features)
	assert C.LLVMWriteBitcodeToFile(module_ptr, (out + '/native-input-features.bc').str) == 0
	mut options := C.LLVMMCJITCompilerOptions{}
	C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions))
	options.OptLevel = 2
	options.EnableFastISel = 0
	mut engine := unsafe { nil }
	assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
	os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	return NativeModule{context, buffer, engine}
}

fn (n NativeModule) close() {
	C.LLVMDisposeExecutionEngine(n.engine)
	C.LLVMDisposeMemoryBuffer(n.buffer)
	C.LLVMContextDispose(n.context)
}

fn fi(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }
	panic(name)
}

fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }

fn reduction_reference(op int, words [16]u64, bits u32, count int) u64 {
	lane_mask := mask(int(bits))
	mut result := if op == 1 { u64(1) } else if op == 2 { lane_mask } else { u64(0) }
	if op >= 5 {
		mut chosen := 0
		for i in 1 .. count {
			key := (words[i] & lane_mask) ^ if op < 7 { u64(1) << (bits - 1) } else { u64(0) }
			best := (words[chosen] & lane_mask) ^ if op < 7 { u64(1) << (bits - 1) } else { u64(0) }
			if (op in [5,7] && key < best) || (op in [6,8] && key > best) { chosen = i }
		}
		return words[chosen] & lane_mask
	}
	for i in 0 .. count { v := words[i] & lane_mask; match op { 0 { result += v } 1 { result *= v } 2 { result &= v } 3 { result |= v } else { result ^= v } } }
	return result & lane_mask
}
fn opname(op int) string { return ['add','mul','and','or','xor','smin','smax','umin','umax'][op] }
fn word(bits int,sample int,lane int) u64 { return [u64(0),1,~u64(0),u64(1)<<u32(bits-1),(u64(1)<<u32(bits-1))-1,0xaaaaaaaaaaaaaaaa,0x9e3779b97f4a7c15,0x0123456789abcdef]![(sample+lane)%8]&mask(bits) }
fn state(sample int,lane int,count int) int { return if (sample==2&&lane==count-1)||sample==7 {2} else if (sample==3&&lane==count-1)||sample==6 {1} else {0} }
fn literal(bits int,count int,sample int,defined bool) string {
 mut lanes:=[]string{cap:count};for lane in 0..count {k:=if defined {0} else {state(sample,lane,count)};lanes<<'i${bits} '+if k==1 {'poison'} else if k==2 {'undef'} else {word(bits,sample,lane).str()}}
 return '<'+lanes.join(', ')+'>'
}
fn widen(bits int,from string,to string) string { return '%${to} = '+if bits==64 {'or i64 ${from}, 0\n'} else {'zext i${bits} ${from} to i64\n'} }
fn untouched(data []u8){for b in data {assert b==0xcc}}
fn checked(p airbitcode.IRTypedProgram,ir airbitcode.IRModule,stream airbitcode.Stream,pools airbitcode.IRConstantPools,bodies airbitcode.IRFunctionBodies,f int,plan &airbitcode.IRPreparedMemoryFunction,mut bs []airbitcode.IRMemoryBinding,valid bool,index u64,reason string,write bool)!{
 for i in 0..bs.last().data.len {bs[bs.len-1].data[i]=0xcc}
 if _:=plan.validate(bs,plan.steps()) {assert valid} else {assert !valid;assert err.msg().contains(reason),err.msg()}
 untouched(bs.last().data)
 for prepared in [false,true] {
  if prepared {if _:=plan.run(mut bs,plan.steps()) {assert valid} else {assert !valid;assert err.msg().contains(reason),err.msg()}}
  else {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert valid} else {assert !valid;assert err.msg().contains(reason),err.msg()}}
  for i,b in bs.last().data {expected:=if valid&&write&&i==int(bs.last().offset+index) {u8(42)} else if valid&&i==int(bs.last().offset) {u8(17)} else {u8(0xcc)};assert b==expected,ir.functions[f].name}
  for i in 0..bs.last().data.len {bs[bs.len-1].data[i]=0xcc}
 }
}
fn mixed_literal(bits int,count int,sample int)string {mut lanes:=[]string{};for lane in 0..count {lanes<<'i${bits} '+if lane==count-1 {'undef'} else if lane==0 {'poison'} else {word(bits,sample,lane).str()}};return '<'+lanes.join(', ')+'>'}
fn controls(assembler string,root string)!int{
 mut s:=strings.new_builder(131072);s.write_string('target datalayout = "e-p:64:64"\n')
 for op in 0..9 {s.write_string('declare i32 @llvm.vector.reduce.${opname(op)}.v3i32(<3 x i32>) #0\n')}
 s.write_string('declare i32 @llvm.vector.reduce.add.v1i32(<1 x i32>)\n declare i8 @llvm.vector.reduce.add.v4i8(<4 x i8>)\n attributes #0 = { nounwind memory(none) }\n')
 kinds:=['defined','source_undef','source_poison','frozen_undef','frozen_poison','ignored_undef','ignored_poison','mixed','cold_bad','cold_good','composition','loaded','signed','large','shared','nested']
 for op in 0..9 {for kind in kinds {
  s.write_string('define void @c_${op}_${kind}(<3 x i32> %a, ptr %out) {entry: store i8 17, ptr %out\n')
  if kind.starts_with('cold') {s.write_string('br i1 true, label %exit, label %cold\n cold:\n')}
  mut source:=if kind in ['source_undef','frozen_undef','ignored_undef','cold_bad'] {'<i32 1, i32 undef, i32 3>'} else if kind in ['source_poison','frozen_poison','ignored_poison'] {'<i32 1, i32 poison, i32 3>'} else if kind=='mixed' {'<i32 poison, i32 0, i32 undef>'} else {'%a'}
  if kind.starts_with('source') {s.write_string('%sf = freeze <3 x i32> ${source}\n');source='%sf'}
  if kind=='loaded' {s.write_string('%load = load <3 x i32>, ptr %out, align 1\n');source='%load'}
  if kind=='signed' {source='<i32 2147483648, i32 2147483648, i32 2147483648>'}
  if kind=='large' {source='<i32 1073741824, i32 1073741824, i32 1073741824>'}
  if kind=='composition' {s.write_string('%b = add <3 x i32> %a, zeroinitializer\n %c = shufflevector <3 x i32> %b, <3 x i32> undef, <3 x i32> <i32 2, i32 1, i32 0>\n %v = select i1 true, <3 x i32> %c, <3 x i32> undef\n');source='%v'}
  s.write_string('%raw = call i32 @llvm.vector.reduce.${opname(op)}.v3i32(<3 x i32> ${source})\n')
  mut value:='%raw'
  if kind in ['frozen_undef','frozen_poison','mixed'] {s.write_string('%f = freeze i32 %raw\n');value='%f'}
  if kind.starts_with('ignored') {s.write_string('%sel = select i1 false, i32 %raw, i32 0\n');value='%sel'}
  if kind=='nested' {s.write_string('%split = bitcast i32 %raw to <4 x i8>\n %r8 = call i8 @llvm.vector.reduce.add.v4i8(<4 x i8> %split)\n %r32 = zext i8 %r8 to i32\n');value='%r32'}
  if kind=='shared' {s.write_string('%first = getelementptr i8, ptr %out, i32 %raw\n %sum = add i32 %raw, %raw\n');value='%sum'}
  s.write_string('%p = getelementptr i8, ptr %out, i32 ${value}\n store i8 42, ptr %p\n')
  if kind.starts_with('cold') {s.write_string('br label %exit\n exit:\n')};s.write_string('ret void }\n')
 }}
 for over in [false,true] {for kind in ['nodes','scalar_depth','source_depth'] {
  s.write_string('define void @limit_${kind}_${over}(<1 x i32> %a, ptr %out) {\n')
  if kind=='source_depth' {for i in 0..28+int(over) {s.write_string('%v${i} = freeze <1 x i32> ${if i==0 {'%a'} else {'%v'+(i-1).str()}}\n')}}
  s.write_string('%raw = call i32 @llvm.vector.reduce.add.v1i32(<1 x i32> ${if kind=='source_depth' {'%v'+(27+int(over)).str()} else {'%a'}})\n %base = getelementptr i8, ptr %out, i32 %raw\n')
  if kind!='source_depth' {for i in 0..(if kind=='nodes' {251} else {28})+int(over) {s.write_string('%r${i} = or i32 ${if kind=='nodes'||i==0 {'%raw'} else {'%r'+(i-1).str()}}, 0\n %p${i} = getelementptr i8, ptr %out, i32 %r${i}\n')}}
  s.write_string('ret void }\n')
 }}
 data:=assemble(assembler,root+'/controls',s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!;mut total:=0
 for over in [false,true] {for kind in ['nodes','scalar_depth','source_depth'] {f:=fi(ir,'limit_${kind}_${over}');if plan:=p.prepare_memory_function(ir,stream,pools,bodies,f) {assert !over,kind;plan.free()} else {assert over,kind+err.msg();assert if kind=='nodes' {err.msg().contains('node limit')} else {err.msg().contains('depth')},err.msg()};total++}}
 words:=[u64(1),2,3,u64(0),0,0,0,0,0,0,0,0,0,0,0,0]!
 for op in 0..9 {for kind in kinds {f:=fi(ir,'c_${op}_${kind}');mut a:=[u64(1),2,3];mut bytes:=[]u8{len:64,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
  if kind=='loaded' {if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('load dependency')};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100) {panic('load dependency')};untouched(bytes);total++}
  else {
   plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
   mut w:=words;if kind.starts_with('source') {w[1]=0};if kind=='signed' {for i in 0..3 {w[i]=2147483648}};if kind=='large' {for i in 0..3 {w[i]=1073741824}}
   mut index:=reduction_reference(op,w,32,3)
   if kind=='frozen_poison'||kind.starts_with('ignored') {index=0}
   if kind=='shared' {index=(index*2)&mask(32)}
   if kind=='nested' {index=((index&255)+((index>>8)&255)+((index>>16)&255)+((index>>24)&255))&255}
   undef:=kind in ['frozen_undef','ignored_undef','mixed','cold_bad'];bad:=undef||index>=64
   checked(p,ir,stream,pools,bodies,f,plan,mut bs,!bad,index,if undef {'undef'} else if index&0x80000000!=0 {'negative'} else if index>67108864 {'extent limit'} else {'bounds'},kind!='cold_good')!;total++
   plan.free()
  };unsafe{a.free();bytes.free();bs.free()}
 }}
 p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
 return total
}
fn main(){
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 control_count:=controls(os.args[1],root)!
 assert control_count==150
 if os.args.len==4 {println('AIR-VECTOR-REDUCTION-INDEX-CONTROLS: ${control_count} PASS');return}
 mut rows:=os.create(root+'/comparisons.txt')!;defer{rows.close()}
 mut shapes:=0;mut exact:=0;mut rejected:=0;mut undefs:=0;mut native_checks:=0;mut budgets:=0
 for bits in 1..65 {counts:=if bits in [1,8,16,32,64] {[]int{len:16,init:index+1}} else {[3]};for count in counts {
  t:='<${count} x i${bits}>';mut text:=strings.new_builder(262144);text.write_string('target datalayout = "e-p:64:64"\n')
  for op in 0..9 {shapes++;name:='llvm.vector.reduce.${opname(op)}.v${count}i${bits}';text.write_string('declare i${bits} @${name}(${t})\n define void @ref_${op}(ptr %in, ptr %unused, ptr %out) {\n')
   for lane in 0..count {text.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = '+if bits==64 {'or i64 %w${lane}, 0\n'} else {'trunc i64 %w${lane} to i${bits}\n'});text.write_string('%v${lane} = insertelement ${t} ${if lane==0 {'zeroinitializer'} else {'%v'+(lane-1).str()}}, i${bits} %b${lane}, i32 ${lane}\n')}
   text.write_string('%r = call i${bits} @${name}(${t} %v${count-1})\n'+widen(bits,'%r','wide')+'store i64 %wide, ptr %out, align 1\n ret void }\n')
   for sample in 0..8 {for mode in 0..8 {
    text.write_string('define void @f_${op}_${sample}_${mode}(${t} %a, i${bits} %seed, ptr %out) {store i8 17, ptr %out\n')
    input:=if mode==7 {mixed_literal(bits,count,sample)} else {literal(bits,count,sample,mode==4)}
    if mode==2 {text.write_string('%sf = freeze ${t} ${input}\n')}
    if mode==4 {text.write_string('%v = insertelement ${t} ${input}, i${bits} %seed, i32 ${sample%count}\n')}
    if mode==6 {text.write_string('%v = select i1 true, ${t} %a, ${t} undef\n')}
    text.write_string('%raw = call i${bits} @${name}(${t} ${if mode==0 {'%a'} else if mode==2 {'%sf'} else if mode in [4,6] {'%v'} else {input}})\n')
    if mode in [3,7] {text.write_string('%r = freeze i${bits} %raw\n')}
    if mode==5 {text.write_string('%r = select i1 false, i${bits} %raw, i${bits} 0\n')}
    text.write_string(widen(bits,if mode in [3,5,7] {'%r'} else {'%raw'},'wide')+'%index = and i64 %wide, 63\n %p = getelementptr i8, ptr %out, i64 %index\n store i8 42, ptr %p\n ret void }\n')
   }}
  }
  dir:=root+'/w${bits}-n${count}';data:=assemble(os.args[1],dir,text.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!;native:=native_module(data,dir)!
  for op in 0..9 {address:=C.LLVMGetFunctionAddress(native.engine,('ref_'+op.str()).str);assert address!=0
   for sample in 0..8 {for mode in 0..8 {
    seed:=word(bits,sample+5,0);mut input:=[]u64{len:count};mut words:=[16]u64{};mut hard_undef:=false;mut poison:=false
    for lane in 0..count {input[lane]=word(bits,sample,lane)|~mask(bits);k:=if mode in [0,4,6] {0} else if mode==7 {if lane==count-1 {2} else if lane==0 {1} else {0}} else {state(sample,lane,count)};words[lane]=if k!=0 {u64(0)} else if mode==4&&lane==sample%count {seed} else {word(bits,sample,lane)};if mode!=2&&k==2 {hard_undef=true};if mode!=2&&k==1 {poison=true}}
    mut result:=[u64(0)]!;unsafe{NativeCast(voidptr(address))(&words[0],&words[0],&result[0])};assert result[0]==reduction_reference(op,words,u32(bits),count);native_checks++
    value:=if mode==5||(mode in [3,7]&&poison) {u64(0)} else {result[0]};selected_poison:=poison&&mode !in [3,5,7];index:=value&63
    f:=fi(ir,'f_${op}_${sample}_${mode}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;args:=[seed|~mask(bits)]
    for extent in [16,64,80] {
     mut bytes:=[]u8{len:extent+3,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:input},airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
     valid:=!hard_undef&&!selected_poison&&index<u64(extent);reason:=if hard_undef {'undef'} else if selected_poison {'poison'} else {'bounds'}
     checked(p,ir,stream,pools,bodies,f,plan,mut bs,valid,index,reason,true)!
     if _:=plan.run(mut bs,plan.steps()-1) {panic('short budget')} else {assert err.msg().contains('budget'),err.msg()};untouched(bytes);budgets++
     if valid {exact++} else {rejected++};if hard_undef {undefs++}
     rows.writeln('${op} ${bits} ${count} ${sample} ${mode} ${extent} ${index} ${valid} ${reason} PASS')!;unsafe{bytes.free();bs.free()}
    };plan.free();unsafe{input.free();args.free()}
   }}
  };native.close();p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
 }}
 assert shapes==1251&&native_checks==80064&&exact+rejected==240192&&undefs==52542&&budgets==240192
 line:='AIR-VECTOR-REDUCTION-INDEX: ${shapes} shapes, ${exact} exact outputs, ${rejected} prewrite refusals (${undefs} whole-source undef), ${native_checks} native/oracle values, ${budgets} short budgets, ${control_count} controls; validation/ordinary/prepared PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
