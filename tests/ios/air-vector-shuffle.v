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

struct Case { name string element int count int size int form int mode int old bool }
struct Counts { shapes int defined int poison int undef int scalar int metadata int controls int budgets int }
fn source_vector(c Case, side int) string {
 if c.form == 2 { return if side == 0 { 'undef' } else { 'poison' } }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; state := (lane + side) % 4
  v := if c.form == 1 && state == 1 { 'poison' } else if c.form == 1 && state == 2 { 'undef' } else { literal(c.element, lane_word(c.element, (lane + side * 7) % 16)) }
  s.write_string(typ(c.element) + ' ' + v)
 }; s.write_string('>'); return s.str()
}
fn selection(c Case, lane int) int {
 return match c.mode { 0 { c.count * 2 - 1 - lane % (c.count * 2) } 1 { (lane / 2) % c.count + (lane % 2) * c.count } 2 { (c.form % 2) * c.count + c.count - 1 } else { if lane % 5 >= 3 { -1 } else { (lane * 3 + 1) % (c.count * 2) } } }
}
fn shuffle_mask(c Case, second bool) string {
 mut s := strings.new_builder(512); s.write_string('<')
 for lane in 0 .. c.size { if lane != 0 { s.write_string(', ') }; v := if second { (c.size - 1 - lane) + (lane % 2) * c.size } else { selection(c, lane) }; s.write_string('i32 ' + if v >= 0 { v.str() } else if lane % 5 == 3 { 'poison' } else { 'undef' }) }
 s.write_string('>'); return s.str()
}
fn expected(c Case, j u64, q u64, r u64, x u64, y u64) (int, u64) {
 if r >= u64(c.size) { return 1, 0 }
 if !c.old { if j >= u64(c.size) { return 1, 0 }; if j == r { return 0, x } }
 lane := if c.old { int(r) } else { c.size - 1 - int(r) }; selected := selection(c, lane)
 if selected < 0 { return 1, 0 }
 side := selected / c.count; i := selected % c.count; update := if side == 0 { j } else { q }
 if update >= u64(c.count) { return 1, 0 }; if update == u64(i) { return 0, if side == 0 { x } else { y } }
 if c.form == 2 { return if side == 0 { 2 } else { 1 }, 0 }
 state := (i + side) % 4
 if c.form == 1 && state in [1, 2] { return state, 0 }
 return 0, lane_word(c.element, (i + side * 7) % 16)
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
 mut s := strings.new_builder(4194304); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for size in [1, 3, 8, 16] { for form in 0 .. 3 { for mode in 0 .. 4 { for old in [false, true] {
  c := Case{'case_${cases.len}', element, count, size, form, mode, old}; cases << c
  operations := '%a = insertelement <${count} x ${t}> ${source_vector(c, 0)}, ${t} %x, i64 %j\n %b = insertelement <${count} x ${t}> ${source_vector(c, 1)}, ${t} %y, i64 %q\n %v = shufflevector <${count} x ${t}> %a, <${count} x ${t}> %b, <${size} x i32> ${shuffle_mask(c, false)}\n %w = shufflevector <${size} x ${t}> %v, <${size} x ${t}> %v, <${size} x i32> ${shuffle_mask(c, true)}\n %u = insertelement <${size} x ${t}> %w, ${t} %x, i64 %j\n %chosen = extractelement <${size} x ${t}> ${if old { '%v' } else { '%u' }}, i64 %r\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${operations} %d = getelementptr i8, ptr %out, i64 8\n store ${t} %chosen, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${t} %x, ${t} %y) { ${operations} ret ${t} %chosen }\n')
 } } } } }
 modes := ['mask_zero', 'mask_poison', 'mask_undef', 'mask_mixed', 'source_undef_hit', 'source_undef_miss', 'source_poison_hit', 'source_poison_miss', 'frozen', 'selected', 'discard_poison', 'discard_undef']
 for mode in modes {
  left := if mode.contains('source_undef') || mode == 'discard_undef' { 'undef' } else if mode.contains('source_poison') { 'poison' } else { 'zeroinitializer' }
  mask_text := if mode in ['mask_poison', 'frozen', 'selected', 'discard_poison'] { 'poison' } else if mode == 'mask_undef' { 'undef' } else if mode == 'mask_mixed' { '<i32 0, i32 poison, i32 undef>' } else if mode.ends_with('_miss') { '<i32 2, i32 0, i32 3>' } else { 'zeroinitializer' }
  choice := if mode == 'frozen' { '%w = freeze ${t} %v' } else if mode == 'selected' { '%w = select i1 false, ${t} %v, ${t} zeroinitializer' } else { '' }; value := if mode in ['frozen', 'selected'] { '%w' } else { '%v' }
  stores := if mode.starts_with('discard_') { '' } else { '${choice}\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} ${value}, ptr %d, align 1\n' }
  s.write_string('define void @${mode}(ptr %out) { store i8 17, ptr %out, align 1\n %a = shufflevector <2 x ${t}> ${left}, <2 x ${t}> zeroinitializer, <3 x i32> ${mask_text}\n %v = extractelement <3 x ${t}> %a, i32 0\n ${stores} ret void }\n')
 }
 s.write_string('define i32 @loop(i32 %n) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %a = insertelement <2 x i32> zeroinitializer, i32 %i, i32 0\n %v = shufflevector <2 x i32> %a, <2 x i32> poison, <2 x i32> zeroinitializer\n %w = shufflevector <2 x i32> %v, <2 x i32> %v, <3 x i32> <i32 1, i32 2, i32 0>\n %x = extractelement <3 x i32> %w, i32 2\n %added = add i32 %sum, %x\n %next = add i32 %i, 1\n %cond = icmp ult i32 %next, %n\n br i1 %cond, label %body, label %done\n done: ret i32 %added }\n')
 guards := ['argument', 'load', 'freeze', 'select', 'phi', 'inputwide', 'outputwide', 'coldwide', 'opaque']
 for guard in guards {
  signature := if guard == 'argument' { '<2 x ${t}> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
  body := match guard {
   'argument' { '%z = shufflevector <2 x ${t}> %v, <2 x ${t}> poison, <1 x i32> zeroinitializer' }
   'load' { '%v = load <2 x ${t}>, ptr %src, align 1\n %z = shufflevector <2 x ${t}> %v, <2 x ${t}> poison, <1 x i32> zeroinitializer' }
   'freeze' { '%v = freeze <2 x ${t}> poison\n %z = shufflevector <2 x ${t}> %v, <2 x ${t}> poison, <1 x i32> zeroinitializer' }
   'select' { '%v = select i1 true, <2 x ${t}> zeroinitializer, <2 x ${t}> poison\n %z = shufflevector <2 x ${t}> %v, <2 x ${t}> poison, <1 x i32> zeroinitializer' }
   'phi' { 'br label %body\n body: %v = phi <2 x ${t}> [zeroinitializer, %entry]\n %z = shufflevector <2 x ${t}> %v, <2 x ${t}> poison, <1 x i32> zeroinitializer' }
   'inputwide' { '%z = shufflevector <17 x ${t}> zeroinitializer, <17 x ${t}> poison, <1 x i32> zeroinitializer' }
   'outputwide', 'coldwide' { '${if guard == 'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold:' } else { '' }} %z = shufflevector <2 x ${t}> zeroinitializer, <2 x ${t}> poison, <17 x i32> zeroinitializer' }
   else { '%z = shufflevector <2 x i64> zeroinitializer, <2 x i64> <i64 ptrtoint (ptr @case_0 to i64), i64 0>, <1 x i32> zeroinitializer' }
  }
  s.write_string('define void @guard_${guard}(${signature}) { entry: store i8 17, ptr %out, align 1\n ${body}\n ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-shuffle'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut defined := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 18 && profile.arguments[0].minimum_size == 24 && profile.arguments[1].minimum_size == 8 + (bits(element) + 7) / 8 && profile.arguments[2].minimum_size == 8 + (bits(element) + 7) / 8; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut native := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), u64(c.count), u64(c.count + 1), ~u64(0), 1, u64(c.size - 1), u64(c.size)]!
  for sample in 0 .. c.size + 2 {
   j := edges[sample % 8]; q := edges[(sample * 3 + 1) % 8]; r := u64(sample); x := lane_word(element, sample % 16); y := lane_word(element, (sample + 5) % 16); state, word := expected(c, j, q, r, x, y)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. (bits(element) + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   args := [j, q, r, x | ~mask(bits(element)), y | ~mask(bits(element))]
   if state == 2 { if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 7) { panic('selected undef returned') } } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 7)!; assert run.poison == (state == 1) && run.bits == bits(element) && run.steps == 7 && (run.poison || run.value == word) }
   if element < 64 { if state == 2 { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 7) { panic('integer undef returned') } } else { run := p.run_integer_function(ir, stream, pools, bodies, sf, args, 7)!; assert run.poison == (state == 1) && run.steps == 7 && (run.poison || run.value == word) } } else { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 7) { panic('FP vector entered integer API') } }; scalar += 2
   if state != 0 {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('indeterminate lane stored') } else { assert err.msg() == if state == 1 { 'AIR memory execution: poison store' } else { 'AIR vector: selected undef lane' }, err.msg() }; for i, b in actual { assert b == if i == 3 { u8(17) } else { u8(0xcc) } }; if state == 1 { poison++ } else { undef++ }
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18)!.steps == 18; unsafe { NativeInsert(voidptr(address))(&indices[1], &input[1], &native[3]) }
    mut actual_word := u64(0); for i in 0 .. (bits(element) + 7) / 8 { actual_word |= u64(actual[11 + i]) << u32(i * 8) }; assert actual_word == word
    for i in 0 .. actual.len { assert actual[i] == if i == 11 + (bits(element) + 7) / 8 - 1 && bits(element) % 8 != 0 { native[i] & u8((1 << (bits(element) % 8)) - 1) } else { native[i] }, '${c.name} j=${j} q=${q} r=${r}' }; defined++
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 17) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0], 6) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 8 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, opcode: 1}, airbitcode.IRTypedInstruction{...op, source_type: -1}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, indices_start: -1}, airbitcode.IRTypedInstruction{...op, indices_count: op.indices_count + 1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('shuffle metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
   original := p.indices[op.indices_start]
   for changed in [u32(0xfffffffe), if original == 0 { u32(1) } else { u32(0) }] { p.indices[op.indices_start] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('altered mask admitted') }; unchanged(actual); metadata++ }; p.indices[op.indices_start] = original
  }
  unsafe { indices.free(); input.free(); actual.free(); native.free(); bs.free() }
 }
 for mode in modes {
  mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]; function := fi(ir, mode)
  bad := mode in ['mask_poison', 'mask_undef', 'source_undef_hit', 'source_poison_hit', 'discard_undef']
  bound := if mode.starts_with('discard_') { 4 } else if mode in ['frozen', 'selected'] { 7 } else { 6 }
  if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('indeterminate control accepted: ' + mode) } } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == bound }
  for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + (bits(element) + 7) / 8 { u8(0) } else { u8(0xcc) } }; controls++; unsafe { output.free(); bs.free() }
 }
 for count in [u64(1), 2, 3, 16, 257]! { run := p.run_integer_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], int(10 * count + 2))!; assert !run.poison && run.value == count * (count - 1) / 2 && run.steps == int(10 * count + 2); controls++ }
 for guard in guards {
  mut output := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }
  if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100) { panic('unsupported profile: ' + guard) }; unchanged(output); controls++; unsafe { output.free(); bs.free() }
 }
 assert cases.len == 576 && defined + poison + undef == 5184 && scalar == 10368 && metadata == 11520 && budgets == 1152 && controls == 26
 return Counts{cases.len, defined, poison, undef, scalar, metadata, controls, budgets}
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  count := if storage { 1 } else { 16 }
  for i in 0 .. if storage && over { 4097 } else { 4096 } {
   if storage && i % 2 == 0 { s.write_string('%v${i} = insertelement <1 x i32> zeroinitializer, i32 7, i32 0\n') } else { s.write_string('%v${i} = shufflevector <${count} x i32> zeroinitializer, <${count} x i32> poison, <${count} x i32> zeroinitializer\n') }
  }
  if !storage { for i in 0 .. if over { 50213 } else { 50212 } { s.write_string('%x${i} = extractelement <16 x i32> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over {
  if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory vector limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output)
  if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('scalar vector limit') } else { assert err.msg() == diagnostic, err.msg() }
 } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 54310 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 54309 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut defined := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for element in 0 .. 66 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; shapes += n.shapes; defined += n.defined; poison += n.poison; undef += n.undef; scalar += n.scalar; metadata += n.metadata; controls += n.controls; budgets += n.budgets }
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 assert shapes == 38016 && defined + poison + undef == 342144 && scalar == 684288 && metadata == 760320 && controls == 1716 && budgets == 76032
 os.write_file(out + '/result.txt', 'AIR-VECTOR-SHUFFLE: ${shapes} i1-i64/half/float, input counts 1/2/3/4/8/16, output counts 1/3/8/16, both-source/duplicate/reverse/poison/legacy-undef masks, insertion/shuffle chains and old/new snapshots; ${defined} native LLVM values, ${poison} poison and ${undef} undef failures preserving earlier writes, ${scalar} scalar/integer checks, ${metadata} metadata/mask, ${controls} indeterminate/repair/freeze/select/discard/loop/profile, ${budgets} budgets and eight public storage/work boundary/over-limit controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
