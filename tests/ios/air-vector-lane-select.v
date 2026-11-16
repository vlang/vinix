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
type NativeLaneSelect = fn (voidptr, voidptr, voidptr)
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
fn assemble(assembler_path string, out string, source string) ![]u8 {
 assert !os.exists(out); os.mkdir_all(out)!; os.write_file(out + '/input.ll', source)!
 mut a := os.new_process(assembler_path); a.set_args([out + '/input.ll', '-o', out + '/input.bc']); a.set_redirect_stdio_merged(); a.run(); log := a.stdout_slurp(); a.wait(); code := a.code; a.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 return os.read_bytes(out + '/input.bc')!
}
fn verify(data []u8) ! {
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; defer { C.LLVMDisposeModule(module_ptr) }; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}

struct Case { name string element int count int form int mode int }
struct Counts { shapes int defined int choices int poison int undef int scalar int metadata int controls int budgets int }
fn vector(c Case, side int) string {
 form := (c.form + side) % 5
 if form >= 2 { return ['poison', 'undef', 'zeroinitializer'][form - 2] }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; v := if form == 1 && lane % 4 == 1 { 'poison' } else if form == 1 && lane % 4 == 2 { 'undef' } else { literal(c.element, lane_word(c.element, (lane + side * 7) % 16)) }; s.write_string(typ(c.element) + ' ' + v) }; s.write_string('>'); return s.str()
}
fn mask_text(count int) string {
 mut s := strings.new_builder(512); s.write_string('<'); for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; s.write_string('i32 ${count - 1 - lane + (lane % 2) * count}') }; s.write_string('>'); return s.str()
}
fn arm_lane(c Case, side int, j u64, q u64, lane int, x u64, y u64) (int, u64) {
 index := if side == 0 { j } else { q }; form := (c.form + side) % 5
 if index >= u64(c.count) { return 1, 0 }; if index == u64(lane) { return 0, if side == 0 { x } else { y } }
 if form == 2 || (form == 1 && lane % 4 == 1) { return 1, 0 }; if form == 3 || (form == 1 && lane % 4 == 2) { return 2, 0 }
 return 0, if form == 4 { u64(0) } else { lane_word(c.element, (lane + side * 7) % 16) }
}
// State 3 denotes a permitted freeze-dependent choice, checked only against
// the interpreter's explicit oracle. Native indeterminate choices are not run.

fn expected(c Case, j u64, q u64, r u64, condition u64, x u64, y u64) (int, u64) {
 if r >= u64(c.count) { return 1, 0 }
 lane := if c.mode == 4 { c.count - 1 - int(r) } else { int(r) }
 updated := c.mode == 3 || (c.mode == 4 && r % 2 == 1)
 if updated { if j >= u64(c.count) { return 1, 0 }; if j == u64(lane) { return 0, x } }
 // cm chooses a frozen reversed condition or the original inserted condition.
 // An invalid insertion poisons ci; cf makes the reversed poison all false.
 if j >= u64(c.count) && condition == 0 { return if c.mode == 1 { 3 } else { 1 }, 0 }
 at := if condition == 1 { c.count - 1 - lane } else { lane }
 bit := if j >= u64(c.count) { u64(0) } else if j == u64(at) { condition } else { u64(at % 2) }
 state, word := arm_lane(c, if bit == 1 { 0 } else { 1 }, j, q, lane, x, y)
 frozen := c.mode == 1 || ((c.mode in [2, 3] || updated) && bit == 1)
 return if (frozen && state != 0) || (state == 0 && j >= u64(c.count) && condition == 1) { 3 } else { state }, if frozen && state != 0 { u64(0) } else { word }
}
fn condition_literal(count int) string {
 mut s := strings.new_builder(512); s.write_string('<')
 for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; s.write_string('i1 ${lane % 2}') }; s.write_string('>'); return s.str()
}
fn reverse_mask(count int) string {
 mut s := strings.new_builder(512); s.write_string('<')
 for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; s.write_string('i32 ${count - lane - 1}') }; s.write_string('>'); return s.str()
}
fn run_batch(assembler_path string, out string, element int) !Counts {
 mut s := strings.new_builder(2097152); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for form in 0 .. 5 { for mode in 0 .. 5 {
  c := Case{'case_${cases.len}', element, count, form, mode}; cases << c; chosen := ['%s', '%f', '%z', '%u', '%t'][mode]
  ops := '%a = insertelement <${count} x ${t}> ${vector(c, 0)}, ${t} %x, i64 %j\n %b = insertelement <${count} x ${t}> ${vector(c, 1)}, ${t} %y, i64 %q\n %ci = insertelement <${count} x i1> ${condition_literal(count)}, i1 %condition, i64 %j\n %cs = shufflevector <${count} x i1> %ci, <${count} x i1> zeroinitializer, <${count} x i32> ${reverse_mask(count)}\n %cf = freeze <${count} x i1> %cs\n %cm = select i1 %condition, <${count} x i1> %cf, <${count} x i1> %ci\n %s = select <${count} x i1> %cm, <${count} x ${t}> %a, <${count} x ${t}> %b\n %f = freeze <${count} x ${t}> %s\n %z = select <${count} x i1> %cm, <${count} x ${t}> %f, <${count} x ${t}> %s\n %u = insertelement <${count} x ${t}> %z, ${t} %x, i64 %j\n %t = shufflevector <${count} x ${t}> %s, <${count} x ${t}> %u, <${count} x i32> ${mask_text(count)}\n %v = extractelement <${count} x ${t}> ${chosen}, i64 %r\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %cp = getelementptr i8, ptr %indices, i64 24\n %condition = load i1, ptr %cp, align 1\n %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops} %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, i1 %condition, ${t} %x, ${t} %y) { ${ops} ret ${t} %v }\n')
 } } }
 modes := ['true_poison', 'false_poison', 'true_undef', 'false_undef', 'selected_poison', 'selected_undef', 'condition_poison', 'condition_undef', 'frozen_condition', 'frozen_result', 'discard_poison', 'discard_undef', 'prior_undef']
 good := '<${t} ${literal(element, lane_word(element, 4))}, ${t} poison>'
 for mode in modes {
  condition := if mode in ['condition_poison', 'frozen_result', 'discard_poison'] { 'poison' } else if mode == 'condition_undef' { 'undef' } else if mode == 'frozen_condition' { '%c' } else if mode.starts_with('false_') { 'false' } else { 'true' }
  left := if mode.starts_with('false_') || mode in ['selected_poison', 'discard_poison', 'frozen_condition'] { if mode.contains('undef') { 'undef' } else { 'poison' } } else if mode in ['selected_undef', 'discard_undef'] { 'undef' } else { good }
  right := if mode.starts_with('true_') { if mode.ends_with('undef') { 'undef' } else { 'poison' } } else { good }
  pre := if mode == 'prior_undef' { '%prior = extractelement <2 x ${t}> undef, i32 0\n' } else if mode == 'frozen_condition' { '%c = freeze i1 poison\n' } else { '' }
  freeze := if mode == 'frozen_result' { '%f = freeze <2 x ${t}> %s\n' } else { '' }
  rest := if mode.starts_with('discard_') { '' } else { '${freeze}%v = extractelement <2 x ${t}> ${if mode == 'frozen_result' { '%f' } else { '%s' }}, i32 0\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n' }
  s.write_string('define void @${mode}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%s = select i1 ${condition}, <2 x ${t}> ${left}, <2 x ${t}> ${right}\n ${rest} ret void }\n')
 }
 s.write_string('define i32 @loop(i32 %n) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %c = trunc i32 %i to i1\n %a = insertelement <2 x i32> poison, i32 %i, i32 0\n %b = insertelement <2 x i32> undef, i32 7, i32 0\n %cv = insertelement <2 x i1> zeroinitializer, i1 %c, i32 0\n %s = select <2 x i1> %cv, <2 x i32> %a, <2 x i32> %b\n %f = freeze <2 x i32> %s\n %x = extractelement <2 x i32> %f, i32 0\n %added = add i32 %sum, %x\n %next = add i32 %i, 1\n %cond = icmp ult i32 %next, %n\n br i1 %cond, label %body, label %done\n done: ret i32 %added }\n')
 guards := ['argument', 'load', 'phi', 'wide_condition', 'wide', 'coldwide', 'opaque_left', 'opaque_right', 'scalable', 'double']
 for guard in guards {
  signature := if guard == 'argument' { '<2 x ${t}> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
  body := match guard {
   'argument' { '%s = select i1 true, <2 x ${t}> zeroinitializer, <2 x ${t}> %v' }
   'load' { '%v = load volatile <2 x ${t}>, ptr %src, align 1\n %s = select i1 true, <2 x ${t}> zeroinitializer, <2 x ${t}> %v' }
   'phi' { 'br label %body\n body: %v = phi <2 x ${t}> [zeroinitializer, %entry]\n %s = select i1 true, <2 x ${t}> zeroinitializer, <2 x ${t}> %v' }
   'wide_condition' { '%s = select <17 x i1> zeroinitializer, <17 x ${t}> zeroinitializer, <17 x ${t}> poison' }
   'wide', 'coldwide' { '${if guard == 'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold:' } else { '' }} %s = select i1 true, <17 x ${t}> zeroinitializer, <17 x ${t}> poison' }
   'scalable' { '%s = select i1 true, <vscale x 2 x i32> zeroinitializer, <vscale x 2 x i32> poison' }
   'double' { '%s = select i1 true, <2 x double> zeroinitializer, <2 x double> poison' }
   else { '%s = select i1 ${if guard == 'opaque_left' { 'false' } else { 'true' }}, <2 x i64> ${if guard == 'opaque_left' { '<i64 7, i64 ptrtoint (ptr @case_0 to i64)>' } else { 'zeroinitializer' }}, <2 x i64> ${if guard == 'opaque_right' { '<i64 7, i64 ptrtoint (ptr @case_0 to i64)>' } else { 'zeroinitializer' }}' }
  }; s.write_string('define void @guard_${guard}(${signature}) { entry: store i8 17, ptr %out, align 1\n ${body}\n ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-select'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut defined := 0; mut choices := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 26 && profile.arguments[0].minimum_size == 25 && profile.arguments[1].minimum_size == 8 + (bits(element) + 7) / 8 && profile.arguments[2].minimum_size == 8 + (bits(element) + 7) / 8; profile.free()
  mut indices := []u8{len: 40}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut native := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), u64(c.count), u64(c.count + 1), ~u64(0), 1, 2, 3]!
  for sample in 0 .. (c.count + 2) * 2 {
   j := edges[(sample / 2) % 8]; q := edges[(sample / 2 * 3 + 1) % 8]; r := u64(sample / 2); condition := u64(sample % 2); x := lane_word(element, (sample / 2) % 16); y := lane_word(element, (sample / 2 + 5) % 16); state, word := expected(c, j, q, r, condition, x, y)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; indices[25] = u8(condition); for i in 0 .. (bits(element) + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   args := [j, q, r, condition | ~u64(1), x | ~mask(bits(element)), y | ~mask(bits(element))]
   if state == 2 { if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 13) { panic('selected undef returned') } } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 13)!; assert run.poison == (state == 1) && run.bits == bits(element) && run.steps == 13 && (run.poison || run.value == word) }
   if element < 64 { if state == 2 { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 13) { panic('integer undef returned') } } else { run := p.run_integer_function(ir, stream, pools, bodies, sf, args, 13)!; assert run.poison == (state == 1) && run.steps == 13 && (run.poison || run.value == word) } } else { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 13) { panic('FP vector entered integer API') } }; scalar += 2
   if state in [1, 2] {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 26) { panic('indeterminate lane selection stored') } else { assert err.msg() == if state == 1 { 'AIR memory execution: poison store' } else { 'AIR vector: selected undef lane' }, err.msg() }; for i, b in actual { assert b == if i == 3 { u8(17) } else { u8(0xcc) } }; if state == 1 { poison++ } else { undef++ }
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 26)!.steps == 26
    mut actual_word := u64(0); for i in 0 .. (bits(element) + 7) / 8 { actual_word |= u64(actual[11 + i]) << u32(i * 8) }; assert actual_word == word
    if state == 0 { unsafe { NativeLaneSelect(voidptr(address))(&indices[1], &input[1], &native[3]) }; for i in 0 .. actual.len { assert actual[i] == if i == 11 + (bits(element) + 7) / 8 - 1 && bits(element) % 8 != 0 { native[i] & u8((1 << (bits(element) % 8)) - 1) } else { native[i] }, '${c.name} c=${condition} j=${j} q=${q} r=${r}' }; defined++ } else { for i, b in actual { assert b == if i == 3 { u8(17) } else if i >= 11 && i < 11 + (bits(element) + 7) / 8 { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) } }; choices++ }
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 25) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0, 0], 12) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code !in [u64(5), 29] { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, opcode: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 26) { panic('select metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
   for slot in 0 .. 3 { original := p.operands[op.operands_start + slot]; p.operands[op.operands_start + slot] = airbitcode.IRTypedOperand{...original, type_index: -1}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 26) { panic('select operand type admitted') }; unchanged(actual); metadata++; p.operands[op.operands_start + slot] = original }
   for slot in 0 .. 2 { original := p.operands[op.operands_start + slot]; p.operands[op.operands_start + slot] = airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 26) { panic('select self source admitted') }; unchanged(actual); metadata++; p.operands[op.operands_start + slot] = original }
  }; unsafe { indices.free(); input.free(); actual.free(); native.free(); bs.free() }
 }
 for mode in modes {
  mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
  bad := mode in ['selected_poison', 'selected_undef', 'condition_poison', 'condition_undef', 'prior_undef']
  bound := if mode.starts_with('discard_') { 3 } else if mode in ['frozen_condition', 'frozen_result', 'prior_undef'] { 7 } else { 6 }
  if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, mode), mut bs, bound) { panic('indeterminate control accepted: ' + mode) } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, mode), mut bs, bound)!.steps == bound }
  word := if mode == 'frozen_result' { u64(0) } else { lane_word(element, 4) }
  for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + (bits(element) + 7) / 8 { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) } }; controls++; unsafe { output.free(); bs.free() }
 }
 for count in [u64(1), 2, 3, 16, 257]! { mut expected_sum := u64(0); for i in u64(0) .. count { expected_sum += if i & 1 != 0 { i } else { u64(7) } }; run := p.run_integer_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], int(13 * count + 2))!; assert !run.poison && run.value == expected_sum && run.steps == int(13 * count + 2); controls++ }
 for guard in guards { mut output := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }; if guard == 'phi' { p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100)!; for i, b in output { assert b == if i == 0 { u8(17) } else { u8(0xcc) } } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100) { panic('unsupported profile: ' + guard) }; unchanged(output) }; controls++; unsafe { output.free(); bs.free() } }
 assert cases.len == 150 && defined + choices + poison + undef == 2300 && scalar == 4600 && metadata == 5400 && budgets == 300 && controls == 28
 return Counts{cases.len, defined, choices, poison, undef, scalar, metadata, controls, budgets}
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } {
   if storage && i % 4 == 0 { s.write_string('%v${i} = insertelement <1 x i32> poison, i32 7, i32 0\n') } else if storage && i % 4 == 1 { s.write_string('%v${i} = shufflevector <1 x i32> zeroinitializer, <1 x i32> poison, <1 x i32> zeroinitializer\n') } else if storage && i % 4 == 2 { s.write_string('%v${i} = freeze <1 x i32> undef\n') } else { count := if storage { 1 } else { 16 }; s.write_string('%v${i} = select <${count} x i1> zeroinitializer, <${count} x i32> zeroinitializer, <${count} x i32> zeroinitializer\n') }
  }
  if !storage { for i in 0 .. if over { 46117 } else { 46116 } { s.write_string('%x${i} = extractelement <16 x i32> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory vector limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('scalar vector limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 50214 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 50213 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut defined := 0; mut choices := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for element in 0 .. 66 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; shapes += n.shapes; defined += n.defined; choices += n.choices; poison += n.poison; undef += n.undef; scalar += n.scalar; metadata += n.metadata; controls += n.controls; budgets += n.budgets }
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 lane_controls(os.args[1], out + '/lane-controls')!
 assert shapes == 9900 && defined + choices + poison + undef == 151800 && scalar == 303600 && metadata == 356400 && controls == 1848 && budgets == 19800
 os.write_file(out + '/result.txt', 'AIR-VECTOR-LANE-SELECT: ${shapes} i1-i64/half/float, 1/2/3/4/8/16-lane, five paired constant forms, inserted/shuffled/frozen/selected vector conditions and selected/frozen/chained/inserted/shuffled snapshots; ${defined} defined native LLVM values, ${choices} permitted freeze-dependent choices, ${poison} poison and ${undef} undef failures preserving earlier writes, ${scalar} scalar/integer checks, ${metadata} metadata/source, ${controls} indeterminate/lazy-arm/snapshot/discard/loop/profile, ${budgets} budgets, 389 additional lane-condition controls and eight public storage/work boundary controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}

fn lane_controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(1048576)
 s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['good', 'poison', 'undef', 'frozen_condition', 'frozen_result', 'all_poison', 'all_undef', 'chosen_undef', 'discard_poison', 'discard_undef', 'discard_bad_condition']
 for mode in modes { for lane in 0 .. 5 {
  condition := if mode in ['all_poison', 'discard_poison'] { 'poison' } else if mode in ['all_undef', 'discard_bad_condition'] { 'undef' } else if mode in ['frozen_condition', 'frozen_result'] { '%c' } else if mode in ['chosen_undef', 'discard_undef'] { '<i1 false, i1 true, i1 false, i1 true>' } else if mode == 'poison' { '<i1 poison, i1 false, i1 true, i1 false>' } else if mode == 'undef' { '<i1 true, i1 undef, i1 true, i1 false>' } else { '<i1 true, i1 false, i1 true, i1 false>' }
  pre := if mode in ['frozen_condition', 'frozen_result'] { '%c = freeze <4 x i1> <i1 true, i1 undef, i1 poison, i1 false>\n' } else { '' }
  frozen := if mode == 'frozen_result' { '%f = freeze <4 x i32> %s\n' } else { '' }
  rest := if mode.starts_with('discard_') { '' } else { '${frozen}%v = extractelement <4 x i32> ${if mode == 'frozen_result' { '%f' } else { '%s' }}, i32 ${lane}\n %d = getelementptr i8, ptr %out, i64 8\n store i32 %v, ptr %d, align 1\n' }
  s.write_string('define void @${mode}_${lane}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%s = select <4 x i1> ${condition}, <4 x i32> <i32 11, i32 poison, i32 33, i32 undef>, <4 x i32> <i32 poison, i32 22, i32 undef, i32 44>\n ${rest} ret void }\n')
 } }
 // Each is valid LLVM IR, but the whole profile must reject these condition sources.
 s.write_string('define void @guard_argument(<4 x i1> %c, ptr %out) { store i8 17, ptr %out\n %v = select <4 x i1> %c, <4 x i32> zeroinitializer, <4 x i32> poison\n ret void }\n define void @guard_load(ptr %src, ptr %out) { store i8 17, ptr %out\n %c = load volatile <4 x i1>, ptr %src\n %v = select <4 x i1> %c, <4 x i32> zeroinitializer, <4 x i32> poison\n ret void }\n define void @guard_phi(ptr %out) { entry: store i8 17, ptr %out\n br label %body\n body: %c = phi <4 x i1> [zeroinitializer, %entry]\n %v = select <4 x i1> %c, <4 x i32> zeroinitializer, <4 x i32> poison\n ret void }\n define void @guard_cold(ptr %out) { store i8 17, ptr %out\n br i1 true, label %done, label %cold\n done: ret void\n cold: %v = select <17 x i1> zeroinitializer, <17 x i32> zeroinitializer, <17 x i32> poison\n ret void }\n')
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut checks := 0
 for mode in modes { for lane in 0 .. 5 {
  mut output := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]
  discarded := mode.starts_with('discard_'); bad_condition := mode in ['undef', 'all_undef', 'discard_bad_condition']
  poisoned := !discarded && (lane == 4 || mode == 'all_poison' || (mode == 'poison' && lane == 0) || (mode == 'chosen_undef' && lane < 2))
  undefined := !discarded && ((mode == 'chosen_undef' && lane in [2, 3]) || (mode == 'frozen_condition' && lane == 2))
  budget := if discarded { 3 } else if mode == 'frozen_condition' { 7 } else if mode == 'frozen_result' { 8 } else { 6 }
  function := fi(ir, '${mode}_${lane}')
  if bad_condition || poisoned || undefined {
   if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, budget) { panic('indeterminate lane control') } else { assert err.msg() == if bad_condition { 'AIR vector: undef select condition lane' } else if undefined { 'AIR vector: selected undef lane' } else { 'AIR memory execution: poison store' }, err.msg() }
  } else {
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, budget)!.steps == budget
  }
  word := if mode == 'frozen_result' && lane == 2 { u32(0) } else { [u32(11), 22, 33, 44, 0]![lane] }
  for i, byte in output { assert byte == if i == 0 { u8(17) } else if !discarded && !bad_condition && !poisoned && !undefined && i >= 8 && i < 12 { u8(word >> u32((i - 8) * 8)) } else { u8(0xcc) } }; checks++
  // Corrupt normalized condition identity, lane count and lane type; reject before the marker.
  for index in bodies.scopes[function + 1].instructions_start .. bodies.scopes[function + 1].instructions_start + bodies.scopes[function + 1].instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code !in [u64(5), 29] { continue }
   slot := op.operands_start + 2; original := p.operands[slot]
   for changed in [airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: op.result_type}, airbitcode.IRTypedOperand{...original, type_index: -1}] {
    for i in 0 .. output.len { output[i] = 0xcc }; p.operands[slot] = changed
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, budget) { panic('condition source mutation') }; unchanged(output); checks++
   }; p.operands[slot] = original
   condition_type := p.types[original.type_index]
   for changed in [airbitcode.IRType{...condition_type, count: 3}, airbitcode.IRType{...condition_type, count: 17}, airbitcode.IRType{...condition_type, refs_start: -1}] {
    for i in 0 .. output.len { output[i] = 0xcc }; p.types[original.type_index] = changed
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, budget) { panic('condition shape mutation') }; unchanged(output); checks++
   }; p.types[original.type_index] = condition_type
  }; unsafe { output.free(); bs.free() }
 } }
 for name in ['argument', 'load', 'phi', 'cold'] {
  mut output := []u8{len: 16, init: 0xcc}; mut bs := if name in ['argument', 'load'] { [airbitcode.IRMemoryBinding{data: output}, airbitcode.IRMemoryBinding{data: output, writable: true}] } else { [airbitcode.IRMemoryBinding{data: output, writable: true}] }
  if name == 'phi' { p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + name), mut bs, 20)!; for i, b in output { assert b == if i == 0 { u8(17) } else { u8(0xcc) } } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + name), mut bs, 20) { panic('unsupported condition source') }; unchanged(output) }; checks++; unsafe { output.free(); bs.free() }
 }
 assert checks == 389
 os.write_file(out + '/result.txt', 'AIR-VECTOR-LANE-SELECT-CONTROLS: ${checks} mixed-lane poison/undef/freeze/discard, full-buffer failure ordering, condition source/type mutations and unsupported condition profiles PASS\n')!
}
