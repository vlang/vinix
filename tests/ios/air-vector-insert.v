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
type NativeInsert = fn (voidptr, voidptr, voidptr)
struct Case { name string element int count int index_bits int form int old bool }
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
fn literal(element int, word u64) string { return if element < 64 { word.str() } else if element == 64 { 'bitcast (i16 ${word} to half)' } else { 'bitcast (i32 ${word} to float)' } }
fn vector(c Case) string {
 if c.form in [1, 2, 3] { return ['zeroinitializer', 'poison', 'undef'][c.form - 1] }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count {
  if lane != 0 { s.write_string(', ') }
  v := if c.form == 4 && lane % 4 == 1 { 'poison' } else if c.form == 4 && lane % 4 == 2 { 'undef' } else { literal(c.element, lane_word(c.element, lane)) }
  s.write_string(typ(c.element) + ' ' + v)
 }; s.write_string('>'); return s.str()
}
fn indexes(c Case, sample int) (u64, u64, u64) {
 edges := [u64(0), 1, u64(c.count - 1), u64(c.count), u64(c.count + 1), mask(c.index_bits), u64(1) << u32(c.index_bits - 1), (u64(1) << u32(c.index_bits - 1)) - 1]!
 j := edges[sample / 8] & mask(c.index_bits); q := edges[sample % 8] & mask(c.index_bits)
 r := match sample % 4 { 0 { j } 1 { q } 2 { u64(2) & mask(c.index_bits) } else { (j + 1) & mask(c.index_bits) } }
 return j, q, r
}
// Resolve which write, if any, determines the selected lane. Earlier snapshots
// ignore later writes; an invalid second index poisons only the new snapshot.
fn expected(c Case, j u64, q u64, r u64, value u64) (int, u64) {
 if r >= u64(c.count) { return 1, 0 }
 if !c.old {
  if q >= u64(c.count) { return 1, 0 }
  if r == q { return 0, lane_word(c.element, 14) }
 }
 if j >= u64(c.count) { return 1, 0 }
 if r == j { return 0, value }
 if c.form == 2 || (c.form == 4 && r % 4 == 1) { return 1, 0 }
 if c.form == 3 || (c.form == 4 && r % 4 == 2) { return 2, 0 }
 return 0, if c.form == 1 { u64(0) } else { lane_word(c.element, int(r)) }
}
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn verify(data []u8) ! {
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}
fn run_batch(assembler_path string, out string, element int) !Counts {
 mut s := strings.new_builder(1048576); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for index_bits in [1, 8, 32, 64] { for form in 0 .. 5 { for old in [false, true] {
  c := Case{'case_${cases.len}', element, count, index_bits, form, old}; cases << c
  operations := '%a = insertelement <${count} x ${t}> ${vector(c)}, ${t} %x, i${index_bits} %j\n %b = insertelement <${count} x ${t}> %a, ${t} ${literal(element, lane_word(element, 14))}, i${index_bits} %q\n %v = extractelement <${count} x ${t}> ${if old { '%a' } else { '%b' }}, i${index_bits} %r\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i${index_bits}, ptr %indices, align 1\n %qptr = getelementptr i8, ptr %indices, i64 8\n %q = load i${index_bits}, ptr %qptr, align 1\n %rptr = getelementptr i8, ptr %indices, i64 16\n %r = load i${index_bits}, ptr %rptr, align 1\n %x = load ${t}, ptr %src, align 1\n store i8 17, ptr %out, align 1\n ${operations} %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i${index_bits} %j, i${index_bits} %q, i${index_bits} %r, ${t} %x) { ${operations} ret ${t} %v }\n')
 } } } }
 for mode in ['lane_poison_hit', 'lane_poison_miss', 'lane_undef_hit', 'lane_undef_miss', 'index_poison', 'index_undef', 'repair_poison', 'repair_undef', 'frozen', 'selected'] {
  lane := if mode.contains('undef') { 'undef' } else { 'poison' }; idx := if mode == 'index_poison' { 'poison' } else if mode == 'index_undef' { 'undef' } else { '0' }
  source := if mode.starts_with('repair_') { if mode.ends_with('undef') { 'undef' } else { 'poison' } } else { 'zeroinitializer' }
  value := if mode.starts_with('repair_') { literal(element, lane_word(element, 0)) } else { lane }
  selected := if mode.ends_with('_miss') { 1 } else { 0 }; choice := if mode == 'frozen' { '%w = freeze ${t} %v' } else if mode == 'selected' { '%w = select i1 false, ${t} %v, ${t} zeroinitializer' } else { '' }; result := if mode in ['frozen', 'selected'] { '%w' } else { '%v' }
  s.write_string('define void @${mode}(ptr %out) { store i8 17, ptr %out, align 1\n %a = insertelement <2 x ${t}> ${source}, ${t} ${value}, i64 ${idx}\n %v = extractelement <2 x ${t}> %a, i64 ${selected}\n ${choice}\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} ${result}, ptr %d, align 1\n ret void }\n')
 }
 s.write_string('define i32 @loop(i32 %n) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %a = insertelement <2 x i32> zeroinitializer, i32 %i, i32 0\n %b = insertelement <2 x i32> %a, i32 7, i32 1\n %x = extractelement <2 x i32> %a, i32 0\n %y = extractelement <2 x i32> %b, i32 1\n %v = add i32 %x, %y\n %added = add i32 %sum, %v\n %next = add i32 %i, 1\n %cond = icmp ult i32 %next, %n\n br i1 %cond, label %body, label %done\n done: ret i32 %added }\n')
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-insert'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut defined := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 13 && profile.arguments[0].minimum_size == 16 + (c.index_bits + 7) / 8 && profile.arguments[1].minimum_size == (bits(element) + 7) / 8 && profile.arguments[2].minimum_size == 8 + (bits(element) + 7) / 8; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 16}; mut actual := []u8{len: 24, init: 0xcc}; mut native := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  for sample in 0 .. 64 {
   j, q, r := indexes(c, sample); value := lane_word(element, sample % 16); state, word := expected(c, j, q, r, value)
   for i in 0 .. (c.index_bits + 7) / 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. (bits(element) + 7) / 8 { input[1 + i] = u8(value >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   args := [j | ~mask(c.index_bits), q | ~mask(c.index_bits), r | ~mask(c.index_bits), value | ~mask(bits(element))]
   if state == 2 { if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 4) { panic('selected undef returned') } } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 4)!; assert run.poison == (state == 1) && run.bits == bits(element) && run.steps == 4 && (run.poison || run.value == word) }
   if element < 64 { if state == 2 { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 4) { panic('integer undef returned') } } else { run := p.run_integer_function(ir, stream, pools, bodies, sf, args, 4)!; assert run.poison == (state == 1) && run.steps == 4 && (run.poison || run.value == word) } } else { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 4) { panic('FP vector entered integer API') } }; scalar += 2
   if state != 0 {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 13) { panic('indeterminate lane stored') } else { assert err.msg() == if state == 1 { 'AIR memory execution: poison store' } else { 'AIR vector: selected undef lane' }, err.msg() }; for i, b in actual { assert b == if i == 3 { u8(17) } else { u8(0xcc) } }; if state == 1 { poison++ } else { undef++ }
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 13)!.steps == 13; unsafe { NativeInsert(voidptr(address))(&indices[1], &input[1], &native[3]) }
    mut actual_word := u64(0); for i in 0 .. (bits(element) + 7) / 8 { actual_word |= u64(actual[11 + i]) << u32(i * 8) }; assert actual_word == word
    for i in 0 .. actual.len { assert actual[i] == if i == 11 + (bits(element) + 7) / 8 - 1 && bits(element) % 8 != 0 { native[i] & u8((1 << (bits(element) % 8)) - 1) } else { native[i] }, '${c.name} j=${j} q=${q} r=${r}' }; defined++
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 12) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0], 3) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 7 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, operands_count: 4}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 13) { panic('insertion metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
   operand := p.operands[op.operands_start]; p.operands[op.operands_start] = airbitcode.IRTypedOperand{...operand, number: p.operands[op.operands_start + 1].number}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 13) { panic('nonvector producer admitted') }; unchanged(actual); metadata++; p.operands[op.operands_start] = operand
  }
  unsafe { indices.free(); input.free(); actual.free(); native.free(); bs.free() }
 }
 for mode in ['lane_poison_hit', 'lane_poison_miss', 'lane_undef_hit', 'lane_undef_miss', 'index_poison', 'index_undef', 'repair_poison', 'repair_undef', 'frozen', 'selected'] {
  mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]; function := fi(ir, mode)
  bad := mode in ['lane_poison_hit', 'lane_undef_hit', 'index_poison', 'index_undef']
  if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6) { panic('control accepted: ' + mode) }; for i, b in output { assert b == if i == 3 { u8(17) } else { u8(0xcc) } } } else {
   bound := if mode in ['frozen', 'selected'] { 7 } else { 6 }; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == bound
   mut word := u64(0); for i in 0 .. (bits(element) + 7) / 8 { word |= u64(output[11 + i]) << u32(i * 8) }; assert word == if mode.starts_with('repair_') { lane_word(element, 0) } else { u64(0) }
  }; controls++; unsafe { output.free(); bs.free() }
 }
 for count in [u64(1), 2, 3, 16, 257]! { run := p.run_integer_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], int(11 * count + 2))!; assert !run.poison && run.value == count * (count - 1) / 2 + count * 7 && run.steps == int(11 * count + 2); controls++ }
 assert cases.len == 240 && defined + poison + undef == 15360 && scalar == 30720 && metadata == 2880 && budgets == 480 && controls == 15
 return Counts{cases.len, defined, poison, undef, scalar, metadata, controls, budgets}
}
fn limits(assembler_path string, out string, storage bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage { 4097 } else { 4096 } { s.write_string('%v${i} = insertelement <${if storage { 1 } else { 16 }} x i32> zeroinitializer, i32 7, i32 0\n') }
  if !storage { for i in 0 .. 58405 { s.write_string('%x${i} = extractelement <16 x i32> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; expected := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory vector limit') } else { assert err.msg() == expected, err.msg() }; unchanged(output)
 if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('scalar vector limit') } else { assert err.msg() == expected, err.msg() }; unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut defined := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for element in 0 .. 66 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; shapes += n.shapes; defined += n.defined; poison += n.poison; undef += n.undef; scalar += n.scalar; metadata += n.metadata; controls += n.controls; budgets += n.budgets }
 limits(os.args[1], out + '/storage-limits', true)!; limits(os.args[1], out + '/work-limits', false)!
 assert shapes == 15840 && defined + poison + undef == 1013760 && scalar == 2027520 && metadata == 190080 && controls == 990 && budgets == 31680
 os.write_file(out + '/result.txt', 'AIR-VECTOR-INSERT: ${shapes} i1-i64/half/float, 1/2/3/4/8/16-lane, i1/i8/i32/i64-index, two-update old/new-snapshot shapes; ${defined} defined native LLVM comparisons, ${poison} poison and ${undef} undef-store failures preserving earlier writes, ${scalar} scalar/integer checks, ${metadata} metadata, ${controls} indeterminate/repair/freeze/select/loop, ${budgets} budget and four whole-function storage/work controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
