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
type NativeExtract = fn (voidptr, voidptr)
struct Case { name string element int count int index_bits int form int }
struct Counts { shapes int defined int poison int undef int scalar int metadata int controls int budgets int }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn bits(element int) int { return if element < 64 { element + 1 } else if element == 64 { 16 } else { 32 } }
fn typ(element int) string { return if element < 64 { 'i${element + 1}' } else if element == 64 { 'half' } else { 'float' } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn lane_word(element int, lane int) u64 {
 if element < 64 { return (u64(lane + 1) * u64(0x9e3779b97f4a7c15)) & mask(bits(element)) }
 if element == 64 { return [u64(0x3e00), 0x8000, 0x7c00, 0xfc00, 0x7c01, 0x7e55, 1, 0x3ff, 0x400, 0x7bff, 0xbc00, 0, 0xfc01, 0xfe55, 0x8001, 0x3555]![lane] }
 return [u64(0x3fc00000), 0x80000000, 0x7f800000, 0xff800000, 0x7f800001, 0x7fc12345, 1, 0x7fffff, 0x800000, 0x7f7fffff, 0xbf800000, 0, 0xff800001, 0xffc12345, 0x80000001, 0x3eaaaaab]![lane]
}
fn literal(element int, word u64) string {
 return if element < 64 { word.str() } else if element == 64 { 'bitcast (i16 ${word} to half)' } else { 'bitcast (i32 ${word} to float)' }
}
fn vector(c Case) string {
 if c.form == 1 { return 'zeroinitializer' }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count {
  if lane != 0 { s.write_string(', ') }
  v := if c.form == 3 && lane % 4 == 1 { 'poison' } else if c.form == 3 && lane % 4 == 2 { 'undef' } else { literal(c.element, lane_word(c.element, if c.form == 2 { 0 } else { lane })) }
  s.write_string(typ(c.element) + ' ' + v)
 }
 s.write_string('>'); return s.str()
}
fn index_word(c Case, sample int) u64 {
 if sample < 20 { return u64(sample) & mask(c.index_bits) }
 return [u64(c.count), u64(c.count - 1), u64(c.count + 1), mask(c.index_bits), u64(1) << u32(c.index_bits - 1), (u64(1) << u32(c.index_bits - 1)) - 1, (u64(1) << u32(c.index_bits - 1)) + 1, u64(0x9e3779b97f4a7c15), u64(0x5555555555555555), u64(0xaaaaaaaaaaaaaaaa), u64(0), u64(1)]![sample - 20] & mask(c.index_bits)
}
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn run_batch(assembler_path string, out string, first int, last int) !Counts {
 mut s := strings.new_builder(2097152); mut cases := []Case{}
 s.write_string('target datalayout = "e-p:64:64"\n')
 for element in first .. last { for count in [1, 2, 3, 4, 8, 16] { for index_bits in [1, 8, 32, 64] { for form in 0 .. 4 {
  c := Case{'case_${cases.len}', element, count, index_bits, form}; cases << c; t := typ(element); v := vector(c)
  s.write_string('define void @${c.name}(ptr %src, ptr %out) { %index = load i${index_bits}, ptr %src, align 1\n store i8 17, ptr %out, align 1\n %v = extractelement <${count} x ${t}> ${v}, i${index_bits} %index\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i${index_bits} %index) { %v = extractelement <${count} x ${t}> ${v}, i${index_bits} %index\n ret ${t} %v }\n')
 } } } }
 for element in first .. last {
  c := Case{'discard_${element}', element, 4, 64, 3}; t := typ(element)
  s.write_string('define void @${c.name}(i64 %index) { %v = extractelement <4 x ${t}> ${vector(c)}, i64 %index\n ret void }\n')
 }
 for element in first .. last { for mode in ['vector_poison', 'vector_undef', 'index_poison', 'index_undef', 'oob_undef', 'frozen', 'selected'] {
  t := typ(element); v := if mode in ['vector_undef', 'index_poison', 'oob_undef'] { 'undef' } else { 'poison' }; index := if mode == 'index_poison' { 'poison' } else if mode == 'index_undef' { 'undef' } else if mode == 'oob_undef' { '4' } else { '0' }
  choice := if mode == 'frozen' { '%w = freeze ${t} %v' } else if mode == 'selected' { '%w = select i1 false, ${t} %v, ${t} zeroinitializer' } else { '' }; value := if mode in ['frozen', 'selected'] { '%w' } else { '%v' }
  s.write_string('define void @${mode}_${element}(ptr %out) { store i8 17, ptr %out, align 1\n %v = extractelement <4 x ${t}> ${v}, i64 ${index}\n ${choice}\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} ${value}, ptr %d, align 1\n ret void }\n')
 } }
 for spec in ['<17 x i8>', '<vscale x 4 x i8>', '<4 x double>', '<4 x bfloat>', '<4 x ptr>'] {
  t := if spec.contains('i8') { 'i8' } else if spec.contains('double') { 'double' } else if spec.contains('bfloat') { 'bfloat' } else { 'ptr' }
  s.write_string('define void @guard_type_${spec.len}_${t}(ptr %out) { store i8 17, ptr %out, align 1\n %v = extractelement ${spec} zeroinitializer, i32 0\n ret void }\n')
 }
 s.write_string('define void @guard_argument(<4 x i8> %v, ptr %out) { store i8 17, ptr %out, align 1\n %x = extractelement <4 x i8> %v, i32 0\n ret void }\ndefine void @guard_load(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %v = load <4 x i8>, ptr %src, align 1\n %x = extractelement <4 x i8> %v, i32 0\n ret void }\ndefine void @guard_vector_freeze(ptr %out) { store i8 17, ptr %out, align 1\n %v = freeze <4 x i8> poison\n %x = extractelement <4 x i8> %v, i32 0\n ret void }\ndefine void @guard_opaque(ptr %out) { store i8 17, ptr %out, align 1\n %x = extractelement <2 x i64> <i64 7, i64 ptrtoint (ptr @case_0 to i64)>, i32 0\n ret void }\n')
 s.write_string('define void @guard_cold(ptr %out) { entry: store i8 17, ptr %out, align 1\n br i1 true, label %good, label %cold\n good: ret void\n cold: %v = extractelement <17 x i8> zeroinitializer, i32 0\n ret void }\n')
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'constant-extract'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 // Unsupported profiles and indeterminate cases are never compiled/invoked
 // as native oracles. Verify the complete module before this projection.
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple)
 native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut defined := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); width := bits(c.element)
  name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 6 && profile.arguments[0].minimum_size == (c.index_bits + 7) / 8 && profile.arguments[1].minimum_size == 8 + (width + 7) / 8; profile.free()
  mut input := []u8{len: 16, init: 0xcc}; mut actual := []u8{len: 24, init: 0xcc}; mut expected := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  for sample in 0 .. 32 {
   index := index_word(c, sample); invalid := index >= u64(c.count) || (c.form == 3 && index % 4 == 1); unknown := !invalid && c.form == 3 && index % 4 == 2
   for i in 0 .. (c.index_bits + 7) / 8 { input[1 + i] = u8(index >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; expected[i] = 0xcc }
   args := [index | ~mask(c.index_bits)]
   if unknown {
    if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 2) { panic('selected undef returned') }
   } else {
    run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 2)!; assert run.bits == width && run.steps == 2 && run.poison == invalid && run.kind == if c.element < 64 { airbitcode.IRScalarKind.integer } else if c.element == 64 { airbitcode.IRScalarKind.binary16 } else { airbitcode.IRScalarKind.binary32 }
    if !invalid { assert run.value == if c.form == 1 { u64(0) } else { lane_word(c.element, if c.form == 2 { 0 } else { int(index) }) } }
   }
   if c.element < 64 { if unknown { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 2) { panic('integer undef returned') } } else { run := p.run_integer_function(ir, stream, pools, bodies, sf, args, 2)!; assert run.poison == invalid && run.bits == width && run.steps == 2; if !invalid { assert run.value == if c.form == 1 { u64(0) } else { lane_word(c.element, if c.form == 2 { 0 } else { int(index) }) } } } } else { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 2) { panic('floating lane entered integer API') } }; scalar += 2
   if invalid || unknown {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6) { panic('indeterminate lane stored') } else { assert err.msg() == if invalid { 'AIR memory execution: poison store' } else { 'AIR vector: selected undef lane' }, err.msg() }
    for i, byte in actual { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } }; if invalid { poison++ } else { undef++ }
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6)!.steps == 6
    unsafe { NativeExtract(voidptr(address))(&input[1], &expected[3]) }
    for i in 0 .. actual.len { assert actual[i] == if i == 11 + (width + 7) / 8 - 1 && width % 8 != 0 { expected[i] & u8((1 << (width % 8)) - 1) } else { expected[i] }, '${c.name} index=${index}' }; defined++
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 5) { panic('short memory budget') }; unchanged(actual)
  if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0)], 1) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 6 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 3}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6) { panic('extract metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
  }
  unsafe { input.free(); actual.free(); expected.free(); bs.free() }
 }
 for element in first .. last { for index in u64(0) .. 5 {
  function := fi(ir, 'discard_${element}')
  if index == 2 { if _ := p.run_void_function(ir, stream, pools, bodies, function, [index], 2) { panic('discarded undef lane accepted') } } else { assert p.run_void_function(ir, stream, pools, bodies, function, [index], 2)!.steps == 2 }; controls++
 } }
 for element in first .. last { for mode in ['vector_poison', 'vector_undef', 'index_poison', 'index_undef', 'oob_undef', 'frozen', 'selected'] {
  mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]; function := fi(ir, '${mode}_${element}')
  if mode in ['frozen', 'selected'] { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6)!.steps == 6; for i, byte in output { assert byte == if i == 3 { u8(17) } else if i >= 11 && i < 11 + (bits(element) + 7) / 8 { u8(0) } else { u8(0xcc) } } } else {
   if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 5) { panic('indeterminate control accepted') }; for i, byte in output { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } }
  }; controls++; unsafe { output.free(); bs.free() }
 } }
 for i, f in ir.functions { if !f.name.starts_with('guard_') { continue }; mut output := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if f.name in ['guard_argument', 'guard_load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }; if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 100) { panic('unsupported vector profile: ' + f.name) }; unchanged(output); controls++; unsafe { output.free(); bs.free() } }
 assert cases.len == 576 && defined + poison + undef == cases.len * 32 && scalar == cases.len * 64 && metadata == cases.len * 5 && budgets == cases.len * 2 && controls == 82
 return Counts{cases.len, defined, poison, undef, scalar, metadata, controls, budgets}
}
fn work_limits(assembler_path string, out string) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n')
  if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. 62501 { s.write_string('%v${i} = extractelement <16 x i32> zeroinitializer, i32 0\n') }
  s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'work-limit'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]
 if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 62503) { panic('memory lane work limit') } else { assert err.msg() == 'AIR vector: constant lane work limit', err.msg() }; unchanged(output)
 if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 62502) { panic('scalar lane work limit') } else { assert err.msg() == 'AIR vector: constant lane work limit', err.msg() }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut defined := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for batch in 0 .. 11 { n := run_batch(os.args[1], out + '/batch-${batch}', batch * 6, batch * 6 + 6)!; shapes += n.shapes; defined += n.defined; poison += n.poison; undef += n.undef; scalar += n.scalar; metadata += n.metadata; controls += n.controls; budgets += n.budgets }
 work_limits(os.args[1], out + '/work-limits')!
 assert shapes == 6336 && defined + poison + undef == 202752 && scalar == 405504 && metadata == 31680 && controls == 902 && budgets == 12672
 os.write_file(out + '/result.txt', 'AIR-CONSTANT-EXTRACT: ${shapes} i1-i64/half/float, 1/2/3/4/8/16-lane, i1/i8/i32/i64-index, value/zero/splat/mixed shapes; ${defined} defined native LLVM comparisons, ${poison} poison and ${undef} undef-store failures preserving earlier writes, ${scalar} scalar/integer checks, ${metadata} metadata, ${controls} indeterminate/profile, ${budgets} budget and two whole-function lane-work controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
