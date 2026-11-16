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

fn number_reduction_reference(maximum bool, bits u32, words [16]u64, count int) u64 {
 lane_mask:=if bits==16 {u64(0xffff)} else {u64(0xffffffff)};sign:=u64(1)<<(bits-1);infinity:=if bits==16 {u64(0x7c00)} else {u64(0x7f800000)}
 if count==1 {return words[0]&lane_mask}
 mut chosen:=if bits==16 {u64(0x7e00)} else {u64(0x7fc00000)};mut best:=u64(0);mut found:=false
 for i in 0..count {x:=words[i]&lane_mask;if x&(sign-1)>infinity {continue};key:=if x&sign!=0 {~x&lane_mask} else {x|sign};if !found||(maximum&&key>best)||(!maximum&&key<best) {chosen=x;best=key;found=true}}
 return chosen
}
fn typ(bits int)string{return if bits==16 {'half'} else {'float'}}
fn is_nan_bits(bits int,value u64)bool{return value&((u64(1)<<u32(bits-1))-1)>if bits==16 {u64(0x7c00)} else {u64(0x7f800000)}}
// Compare defined inputs after quieting sNaNs. LLVM fmin/fmax may choose
// a different reduction order or sNaN outcome; exact equality on raw sNaNs
// would reject legal native results. Raw interpreter inputs retain their bits.
fn quiet_native_reference(address u64, source [16]u64, bits int, count int) u64 {
 mut words:=source
 for lane in 0..count {if is_nan_bits(bits,words[lane]) {words[lane] |= if bits==16 {u64(0x200)} else {u64(0x400000)}}}
 mut result:=[u64(0)]!
 unsafe{NativeCast(voidptr(address))(&words[0],&words[0],&result[0])}
 return result[0]
}
fn word(bits int,sample int,lane int)u64 {
 edges:=if bits==16 {[u64(0),0x8000,1,0x8001,0x3ff,0x83ff,0x400,0x8400,0x3c00,0xbc00,0x7c00,0xfc00,0x7c01,0xfc01,0x7e55,0xfe55]!} else {[u64(0),0x80000000,1,0x80000001,0x7fffff,0x807fffff,0x800000,0x80800000,0x3f800000,0xbf800000,0x7f800000,0xff800000,0x7f800001,0xff800001,0x7fc12345,0xffc12345]!}
 return if sample<16 {edges[sample]} else {edges[(sample+lane)%16]}
}
fn state(sample int,lane int,count int)int{return if (sample%8==2&&lane==count-1)||sample%8==7 {2} else if (sample%8==3&&lane==count-1)||sample%8==6 {1} else {0}}
fn scalar_literal(bits int,value u64)string{return 'bitcast (i${bits} ${value&mask(bits)} to ${typ(bits)})'}
fn literal(bits int,count int,sample int,defined bool)string{mut lanes:=[]string{};for lane in 0..count {k:=if defined {0} else {state(sample,lane,count)};lanes<<typ(bits)+' '+if k==1 {'poison'} else if k==2 {'undef'} else {scalar_literal(bits,word(bits,sample,lane))}};return '<'+lanes.join(', ')+'>'}
fn output(bits int,from string)string{return '%bits = bitcast ${typ(bits)} ${from} to i${bits}\n %wide = zext i${bits} %bits to i64\n'}
fn checked(p airbitcode.IRTypedProgram,ir airbitcode.IRModule,stream airbitcode.Stream,pools airbitcode.IRConstantPools,bodies airbitcode.IRFunctionBodies,f int,plan &airbitcode.IRPreparedMemoryFunction,mut bs []airbitcode.IRMemoryBinding,undefined bool,poison bool,expected u64)!{
 for prepared in [false,true] {
  for i in 0..bs.last().data.len {bs[bs.len-1].data[i]=0xcc}
  plan.validate(bs,plan.steps())!;for b in bs.last().data {assert b==0xcc}
  if prepared {if _:=plan.run(mut bs,plan.steps()) {assert !undefined&&!poison} else {assert undefined||poison;assert err.msg().contains(if undefined {'undef'} else {'poison store'}),err.msg()}}
  else {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert !undefined&&!poison} else {assert undefined||poison;assert err.msg().contains(if undefined {'undef'} else {'poison store'}),err.msg()}}
  for i,b in bs.last().data {assert b==if i==3 {u8(17)} else if !undefined&&!poison&&i>=11&&i<19 {u8(expected>>u32((i-11)*8))} else {u8(0xcc)},ir.functions[f].name}
 }
}
fn controls(assembler string,root string)!int {
 mut s:=strings.new_builder(65536);s.write_string('target datalayout = "e-p:64:64"\n')
 kinds:=['argument','composition','loaded','cold','discard_poison','discard_undef','address','raw']
 for bits in [16,32] {t:=typ(bits);v:='<3 x ${t}>';for op in 0..2 {name:='llvm.vector.reduce.f${if op==0 {'min'} else {'max'}}.v3f${bits}';s.write_string('declare ${t} @${name}(${v}) #0\n')
  for kind in kinds {
   s.write_string('define ${if kind=='raw' {t} else {'void'}} @c_${bits}_${op}_${kind}(${v} %a, ptr %out) {entry:\n')
   if kind!='raw' {s.write_string('store i8 17, ptr %out\n')}
   if kind=='cold' {s.write_string('br i1 true, label %exit, label %cold\n cold:\n')}
   mut source:='%a'
   if kind in ['cold','discard_undef'] {source='undef'}
   if kind=='discard_poison' {source='poison'}
   if kind=='loaded' {s.write_string('%load = load ${v}, ptr %out, align 1\n');source='%load'}
   if kind=='composition' {s.write_string('%b = fneg ${v} %a\n %c = fneg ${v} %b\n %v = shufflevector ${v} %c, ${v} undef, <3 x i32> <i32 2, i32 1, i32 0>\n');source='%v'}
   s.write_string('%raw = call ${t} @${name}(${v} ${source})\n')
   if kind=='raw' {s.write_string('ret ${t} %raw }\n');continue}
   if kind in ['argument','composition','loaded'] {s.write_string(output(bits,'%raw')+'%p = getelementptr i8, ptr %out, i64 8\n store i64 %wide, ptr %p, align 1\n')}
   if kind=='address' {s.write_string('%b = bitcast ${t} %raw to i${bits}\n %p = getelementptr i8, ptr %out, i${bits} %b\n store i8 42, ptr %p\n')}
   if kind=='cold' {s.write_string('br label %exit\n exit:\n')}
   s.write_string('ret void }\n')
  }
 }}
 s.write_string('attributes #0 = { nounwind memory(none) }\n');data:=assemble(assembler,root+'/controls',s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;mut p:=ir.typed_operands(stream,pools,bodies)!;mut total:=0
 for bits in [16,32] {for op in 0..2 {for kind in kinds {
  f:=fi(ir,'c_${bits}_${op}_${kind}');a:=[u64(0),u64(1)<<u32(bits-1),if bits==16 {u64(0x3c00)} else {u64(0x3f800000)}];mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:a},airbitcode.IRMemoryBinding{data:bytes,writable:true}]
  mut words:=[16]u64{};for lane in 0..3 {words[lane]=a[lane]};if kind=='loaded' {for lane in 0..3 {mut w:=u64(0);for byte in 0..bits/8 {w |= u64(if lane==0&&byte==0 {u8(17)} else {u8(0xcc)})<<u32(byte*8)};words[lane]=w}}
  expected:=number_reduction_reference(op==1,u32(bits),words,3)
  if kind=='raw' {scalar_source:='target datalayout = "e-p:64:64"\n declare ${typ(bits)} @llvm.vector.reduce.f${if op==0 {'min'} else {'max'}}.v3f${bits}(<3 x ${typ(bits)}>)\n define ${typ(bits)} @raw() { %r = call ${typ(bits)} @llvm.vector.reduce.f${if op==0 {'min'} else {'max'}}.v3f${bits}(<3 x ${typ(bits)}> <${typ(bits)} ${scalar_literal(bits,a[0])}, ${typ(bits)} ${scalar_literal(bits,a[1])}, ${typ(bits)} ${scalar_literal(bits,a[2])}>)\n ret ${typ(bits)} %r }\n';raw_data:=assemble(assembler,root+'/raw-${bits}-${op}',scalar_source)!;raw_stream:=airbitcode.parse(raw_data)!;raw_ir:=raw_stream.ir_module(raw_data)!;raw_pools:=raw_ir.constant_pools(raw_stream)!;raw_bodies:=raw_ir.function_bodies(raw_stream,raw_pools)!;raw_p:=raw_ir.typed_operands(raw_stream,raw_pools,raw_bodies)!;r:=raw_p.run_scalar_function(raw_ir,raw_stream,raw_pools,raw_bodies,fi(raw_ir,'raw'),[],20)!;assert !r.poison&&r.value==expected&&r.kind==if bits==16 {airbitcode.IRScalarKind.binary16} else {airbitcode.IRScalarKind.binary32};raw_p.free();raw_bodies.free();raw_pools.free();raw_ir.free();raw_stream.free();unsafe{raw_data.free()};total++}
  else if kind=='address' {if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('floating address')};if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,100) {panic('floating address')};for b in bytes {assert b==0xcc};total++}
  else {plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;for prepared in [false,true] {for i in 0..bytes.len {bytes[i]=0xcc};plan.validate(bs,plan.steps())!;for b in bytes {assert b==0xcc}
   if prepared {if _:=plan.run(mut bs,plan.steps()) {assert kind!='discard_undef'} else {assert kind=='discard_undef'&&err.msg().contains('undef'),err.msg()}}
   else {if _:=p.run_memory_function(ir,stream,pools,bodies,f,mut bs,plan.steps()) {assert kind!='discard_undef'} else {assert kind=='discard_undef'&&err.msg().contains('undef'),err.msg()}}
   for i,b in bytes {assert b==if i==0 {u8(17)} else if kind in ['argument','composition','loaded']&&i>=8&&i<16 {u8(expected>>u32((i-8)*8))} else {u8(0xcc)}};total++
  };plan.free()};unsafe{a.free();bytes.free();bs.free()}
 }}}
 f:=fi(ir,'c_32_0_argument');scope:=bodies.scopes[f+1];mut call:=-1;for i in scope.instructions_start..scope.instructions_start+scope.instructions_count {if stream.records[bodies.instructions[i].record].code==34 {call=i;break}};assert call>=0;saved:=p.instructions[call]
 for op in [airbitcode.IRTypedInstruction{...saved,flags:0},airbitcode.IRTypedInstruction{...saved,opcode:1},airbitcode.IRTypedInstruction{...saved,is_volatile:true},airbitcode.IRTypedInstruction{...saved,fast_math_flags:1},airbitcode.IRTypedInstruction{...saved,calling_convention:8},airbitcode.IRTypedInstruction{...saved,attribute_set:1},airbitcode.IRTypedInstruction{...saved,operands_count:1},airbitcode.IRTypedInstruction{...saved,indices_count:1},airbitcode.IRTypedInstruction{...saved,targets_count:1},airbitcode.IRTypedInstruction{...saved,call_signature:-1},airbitcode.IRTypedInstruction{...saved,callee_function:-1},airbitcode.IRTypedInstruction{...saved,result_type:-1}] {p.instructions[call]=op;if _:=p.prepare_memory_function(ir,stream,pools,bodies,f) {panic('metadata')};total++};p.instructions[call]=saved
 mut functions:=ir.functions.clone();bad_ir:=airbitcode.IRModule{...ir,functions:functions}
 for name in ['llvm.vector.reduce.fmin.v03f32','llvm.vector.reduce.fmin.v2f32','llvm.vector.reduce.fmin.v3f16','llvm.vector.reduce.fmin.v3i32','llvm.vector.reduce.fmaxnum.v3f32','llvm.vector.reduce.fmin.v3f64'] {functions[saved.callee_function]=airbitcode.IRFunction{...ir.functions[saved.callee_function],name:name};if _:=p.prepare_memory_function(bad_ir,stream,pools,bodies,f) {panic('name/type')};total++}
 unsafe{functions.free()};p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
 for storage in [false,true] {for over in [false,true] {limits(assembler,root+'/limit-${storage}-${over}',storage,over)!;total+=2}}
 return total
}
fn limits(assembler string,root string,storage bool,over bool) ! {
 mut s:=strings.new_builder(8388608);s.write_string('target datalayout = "e-p:64:64"\n declare half @llvm.vector.reduce.fmin.v16f16(<16 x half>)\n')
 for memory in [false,true] {
  s.write_string('define void @${if memory {'memory'} else {'scalar'}}(${if memory {'ptr %out'} else {''}}) {\n');if memory {s.write_string('store i8 17, ptr %out\n')}
  for i in 0..if storage&&over {4097} else {4096} {s.write_string('%v${i} = insertelement <16 x half> zeroinitializer, half 1.0, i32 0\n')}
  for i in 0..if storage {4096} else {54968} {s.write_string('%r${i} = call half @llvm.vector.reduce.fmin.v16f16(<16 x half> %v4095)\n')}
  if !storage {s.write_string('%e = extractelement <8 x i1> zeroinitializer, i32 0\n');if over {s.write_string('%over = extractelement <1 x i1> zeroinitializer, i32 0\n')}};s.write_string('ret void }\n')
 }
 data:=assemble(assembler,root,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!
 mut bytes:=[u8(0xcc)];mut bs:=[airbitcode.IRMemoryBinding{data:bytes,writable:true}]
 if over {expected:=if storage {'AIR vector: update result limit'} else {'AIR vector: constant lane work limit'};if _:=p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000) {panic('limit')} else {assert err.msg()==expected,err.msg()};assert bytes[0]==0xcc;if _:=p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000) {panic('void limit')} else {assert err.msg()==expected,err.msg()}}
 else {p.run_memory_function(ir,stream,pools,bodies,fi(ir,'memory'),mut bs,70000)!;assert bytes[0]==17;p.run_void_function(ir,stream,pools,bodies,fi(ir,'scalar'),[],70000)!}
 p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free();bs.free()}
}

fn main(){
 assert os.args.len in [3,4];root:=os.abs_path(os.args[2]);assert !os.exists(root)&&!root.starts_with(os.getwd()+'/');os.mkdir_all(root)!
 control_count:=controls(os.args[1],root)!
 assert control_count==82
 if os.args.len==4 {println('AIR-NUMBER-REDUCTION-CONTROLS: ${control_count} PASS');return}
 mut rows:=os.create(root+'/comparisons.txt')!;defer{rows.close()}
 mut exact:=0;mut poison_checks:=0;mut undefined:=0;mut native_checks:=0;mut nan_checks:=0;mut sweeps:=0;mut shapes:=0;mut integer_guards:=0;mut budgets:=0
 for bits in [16,32] {for count in 1..17 {
  t:=typ(bits);v:='<${count} x ${t}>';mut s:=strings.new_builder(262144);s.write_string('target datalayout = "e-p:64:64"\n')
  for op in 0..2 {shapes++;name:='llvm.vector.reduce.f${if op==0 {'min'} else {'max'}}.v${count}f${bits}';s.write_string('declare ${t} @${name}(${v})\n define void @ref_${op}(ptr %in, ptr %unused, ptr %out) {\n')
   for lane in 0..count {s.write_string('%p${lane} = getelementptr i64, ptr %in, i64 ${lane}\n %w${lane} = load i64, ptr %p${lane}, align 1\n %b${lane} = trunc i64 %w${lane} to i${bits}\n %a${lane} = bitcast i${bits} %b${lane} to ${t}\n %v${lane} = insertelement ${v} ${if lane==0 {'zeroinitializer'} else {'%v'+(lane-1).str()}}, ${t} %a${lane}, i32 ${lane}\n')}
   s.write_string('%r = call ${t} @${name}(${v} %v${count-1})\n'+output(bits,'%r')+'store i64 %wide, ptr %out, align 1\n ret void }\n')
   for sample in 0..32 {for mode in 0..5 {for memory in [false,true] {
    s.write_string(if memory {'define void @m_${op}_${sample}_${mode}(${t} %seed, ptr %out) { store i8 17, ptr %out\n'} else {'define i64 @s_${op}_${sample}_${mode}(${t} %seed) {\n'})
    input:=literal(bits,count,sample,mode in [0,4])
    if mode==2 {s.write_string('%sf = freeze ${v} ${input}\n')}
    if mode==4 {s.write_string('%v = insertelement ${v} ${input}, ${t} %seed, i32 ${sample%count}\n')}
    s.write_string('%raw = call ${t} @${name}(${v} ${if mode==2 {'%sf'} else if mode==4 {'%v'} else {input}})\n')
    if mode==3 {s.write_string('%r = freeze ${t} %raw\n')}
    s.write_string(output(bits,if mode==3 {'%r'} else {'%raw'}))
    s.write_string(if memory {'%p = getelementptr i8, ptr %out, i64 8\n store i64 %wide, ptr %p, align 1\n ret void }\n'} else {'ret i64 %wide }\n'})
   }}}
   if count==3 {for memory in [false,true] {s.write_string(if memory {'define void @sweep_m_${op}(${t} %seed, ptr %out) {store i8 17, ptr %out\n'} else {'define i64 @sweep_s_${op}(${t} %seed) {\n'});s.write_string('%v = insertelement ${v} zeroinitializer, ${t} %seed, i32 0\n %raw = call ${t} @${name}(${v} %v)\n'+output(bits,'%raw'));s.write_string(if memory {'%p = getelementptr i8, ptr %out, i64 8\n store i64 %wide, ptr %p, align 1\n ret void }\n'} else {'ret i64 %wide }\n'})}}
  }
  dir:=root+'/w${bits}-n${count}';data:=assemble(os.args[1],dir,s.str())!;verify(data)!;stream:=airbitcode.parse(data)!;ir:=stream.ir_module(data)!;pools:=ir.constant_pools(stream)!;bodies:=ir.function_bodies(stream,pools)!;p:=ir.typed_operands(stream,pools,bodies)!;native:=native_module(data,dir)!
  for op in 0..2 {address:=C.LLVMGetFunctionAddress(native.engine,('ref_'+op.str()).str);assert address!=0
   for sample in 0..32 {for mode in 0..5 {
    seed:=word(bits,(sample+9)%32,0);mut words:=[16]u64{};mut hard_undef:=false;mut poison:=false
    for lane in 0..count {k:=if mode in [0,4] {0} else {state(sample,lane,count)};words[lane]=if k!=0 {u64(0)} else if mode==4&&lane==sample%count {seed} else {word(bits,sample,lane)};if mode!=2&&k==2 {hard_undef=true};if mode!=2&&k==1 {poison=true}}
    expected:=number_reduction_reference(op==1,u32(bits),words,count);mut result:=[u64(0)]!;result[0]=quiet_native_reference(address,words,bits,count);assert if is_nan_bits(bits,expected) {is_nan_bits(bits,result[0])} else {result[0]==expected};native_checks++;if is_nan_bits(bits,expected) {nan_checks++}
    value:=if mode==3&&poison {u64(0)} else {expected};selected_poison:=mode!=3&&poison
    f:=fi(ir,'m_${op}_${sample}_${mode}');sf:=fi(ir,'s_${op}_${sample}_${mode}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!;args:=[seed|~mask(bits)]
    if r:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,100) {assert !hard_undef&&r.poison==selected_poison&&(r.poison||r.value==value)} else {assert hard_undef&&err.msg().contains('undef'),err.msg()}
    if sample==0&&mode==0 {if _:=p.run_integer_function(ir,stream,pools,bodies,sf,args,100) {panic('integer floating reduction')};integer_guards++}
    mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
    checked(p,ir,stream,pools,bodies,f,plan,mut bs,hard_undef,selected_poison,value)!
    for i in 0..bytes.len {bytes[i]=0xcc};if _:=plan.run(mut bs,plan.steps()-1) {panic('short budget')} else {assert err.msg().contains('budget')};for b in bytes {assert b==0xcc};budgets++
    if hard_undef {undefined++} else if selected_poison {poison_checks++} else {exact++}
    rows.writeln('${op} ${bits} ${count} ${sample} ${mode} ${hard_undef} ${selected_poison} ${value} ${result[0]} PASS')!;plan.free();unsafe{args.free();bytes.free();bs.free()}
   }}
   if count==3 {
    f:=fi(ir,'sweep_m_${op}');sf:=fi(ir,'sweep_s_${op}');plan:=p.prepare_memory_function(ir,stream,pools,bodies,f)!
    mut args:=[u64(0)];mut bytes:=[]u8{len:32,init:0xcc};mut bs:=[airbitcode.IRMemoryBinding{values:args},airbitcode.IRMemoryBinding{data:bytes,offset:3,writable:true}]
    for sample in 0..65536 {
     seed:=if bits==16 {u64(sample)} else {u64(u32(sample)*u32(0x9e3779b9))};args[0]=seed|~mask(bits);mut words:=[16]u64{};words[0]=seed;value:=number_reduction_reference(op==1,u32(bits),words,3);mut result:=[u64(0)]!;result[0]=quiet_native_reference(address,words,bits,count);assert if is_nan_bits(bits,value) {is_nan_bits(bits,result[0])} else {result[0]==value};native_checks++;if is_nan_bits(bits,value) {nan_checks++}
     r:=p.run_scalar_function(ir,stream,pools,bodies,sf,args,100)!;assert !r.poison&&r.value==value;checked(p,ir,stream,pools,bodies,f,plan,mut bs,false,false,value)!;sweeps++
     rows.writeln('sweep ${op} ${bits} ${sample} ${value} ${result[0]} PASS')!
    };plan.free();unsafe{args.free();bytes.free();bs.free()}
   }
  };native.close();p.free();bodies.free();pools.free();ir.free();stream.free();unsafe{data.free()}
 }}
 assert shapes==64&&native_checks==272384&&sweeps==262144&&exact==8704&&poison_checks==512&&undefined==1024&&integer_guards==64&&budgets==10240
 line:='AIR-NUMBER-REDUCTION: ${shapes} shapes, ${exact} exact/frozen values, ${poison_checks} poison stores, ${undefined} strict undef failures, ${native_checks} quieted native/oracle values (${nan_checks} NaN-class comparisons), ${sweeps} sweep samples, ${budgets} short budgets, ${integer_guards} integer exclusions, ${control_count} controls PASS\n';os.write_file(root+'/result.txt',line)!;print(line)
}
