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
type NativeFneg = fn (voidptr, voidptr, voidptr)
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
struct Counts { shapes int native int choices int poison int scalar int metadata int controls int budgets int }
fn vector(c Case) string {
 if c.form >= 2 { return ['poison', 'undef', 'zeroinitializer'][c.form - 2] }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; v := if c.form == 1 && lane % 4 == 1 { 'poison' } else if c.form == 1 && lane % 4 == 2 { 'undef' } else { literal(c.element, lane_word(c.element, lane)) }; s.write_string(typ(c.element) + ' ' + v) }; s.write_string('>'); return s.str()
}
fn mask_text(count int, second bool) string {
 mut s := strings.new_builder(512); s.write_string('<')
 for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; selected := if second { count - 1 - lane + (lane % 2) * count } else if lane % 4 == 3 { -1 } else if lane % 4 == 2 { count + lane } else { count - 1 - lane }; s.write_string('i32 ' + if selected < 0 { 'poison' } else { selected.str() }) }; s.write_string('>'); return s.str()
}
fn literal_lane(c Case, lane int) (bool, u64) {
 if c.form in [2, 3] || (c.form == 1 && lane % 4 in [1, 2]) { return true, 0 }
 return false, if c.form == 4 { u64(0) } else { lane_word(c.element, lane) }
}
fn source_lane(c Case, j u64, lane int, x u64) (bool, u64) {
 if c.mode != 0 { if j >= u64(c.count) { return true, 0 }; if j == u64(lane) { return false, x } }
 return literal_lane(c, lane)
}
fn expected(c Case, j u64, q u64, r u64, x u64, y u64) (int, u64) {
 // Undef in any active fneg source lane rejects, even if another lane is selected.
 if c.mode == 0 || j < u64(c.count) { for lane in 0 .. c.count {
  if c.mode != 0 && j == u64(lane) { continue }
  if c.form == 3 || (c.form == 1 && lane % 4 == 2) { return 3, 0 }
 } }
 if r >= u64(c.count) { return 1, 0 }
 mut lane := int(r); mut updated := c.mode == 3
 if c.mode == 4 { lane = c.count - 1 - int(r); updated = int(r) % 2 == 0 }
 if updated { if q >= u64(c.count) { return 1, 0 }; if q == u64(lane) { return 0, y } }
 poison, word := source_lane(c, j, lane, x)
 if poison { return if c.mode >= 3 { 2 } else { 1 }, 0 }
 sign := u64(1) << u32(bits(c.element) - 1)
 return 0, if c.mode == 2 { word } else if word < sign { word + sign } else { word - sign }
}
fn run_batch(assembler_path string, out string, element int) !Counts {
 mut s := strings.new_builder(2097152); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for form in 0 .. 5 { for mode in 0 .. 5 {
  c := Case{'case_${cases.len}', element, count, form, mode}; cases << c
  selected := ['%n', '%n', '%doubled', '%b', '%t'][mode]
  source := if mode == 0 { vector(c) } else { '%a' }
  ops := '%a = insertelement <${count} x ${t}> ${vector(c)}, ${t} %x, i64 %j\n %n = fneg <${count} x ${t}> ${source}\n %doubled = fneg <${count} x ${t}> %n\n %f = freeze <${count} x ${t}> %n\n %b = insertelement <${count} x ${t}> %f, ${t} %y, i64 %q\n %t = shufflevector <${count} x ${t}> %b, <${count} x ${t}> %f, <${count} x i32> ${mask_text(count, true)}\n %v = extractelement <${count} x ${t}> ${selected}, i64 %r\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops} %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${t} %x, ${t} %y) { ${ops} ret ${t} %v }\n')
 } } }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-fneg'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut native_count := 0; mut choices := 0; mut poison := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 19 && profile.arguments[0].minimum_size == 24 && profile.arguments[1].minimum_size == 8 + (bits(element) + 7) / 8 && profile.arguments[2].minimum_size == 8 + (bits(element) + 7) / 8; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut native := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), u64(c.count), u64(c.count + 1), ~u64(0), 1, 2, 3]!
  for sample in 0 .. c.count + 2 {
   j := edges[sample % 8]; q := edges[(sample * 3 + 1) % 8]; r := u64(sample); x := lane_word(element, sample % 16); y := lane_word(element, (sample + 5) % 16); state, word := expected(c, j, q, r, x, y)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. (bits(element) + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   args := [j, q, r, x | ~mask(bits(element)), y | ~mask(bits(element))]
   if state == 3 {
    if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 8) { panic('undef scalar fneg') } else { assert err.msg() == 'AIR vector: undef fneg lane', err.msg() }
   } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 8)!; assert run.poison == (state == 1) && run.bits == bits(element) && run.steps == 8 && (run.poison || run.value == word) }
   if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 8) { panic('FP vector entered integer API') }; scalar += 2
   if state in [1, 3] {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('post-freeze poison stored') } else { assert err.msg() == if state == 3 { 'AIR vector: undef fneg lane' } else { 'AIR memory execution: poison store' }, err.msg() }; for i, b in actual { assert b == if i == 3 { u8(17) } else { u8(0xcc) } }; if state == 3 { controls++ } else { poison++ }
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19)!.steps == 19
    mut actual_word := u64(0); for i in 0 .. (bits(element) + 7) / 8 { actual_word |= u64(actual[11 + i]) << u32(i * 8) }; assert actual_word == word
    if state == 0 { unsafe { NativeFneg(voidptr(address))(&indices[1], &input[1], &native[3]) }; for i in 0 .. actual.len { assert actual[i] == if i == 11 + (bits(element) + 7) / 8 - 1 && bits(element) % 8 != 0 { native[i] & u8((1 << (bits(element) % 8)) - 1) } else { native[i] }, '${c.name} j=${j} q=${q} r=${r}' }; native_count++ } else { for i, b in actual { assert b == if i == 3 { u8(17) } else if i >= 11 && i < 11 + (bits(element) + 7) / 8 { u8(0) } else { u8(0xcc) } }; choices++ }
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0], 7) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 56 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, opcode: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('fneg metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
   original := p.operands[op.operands_start]
   for number in [u32(0), bodies.instructions[index].next_value] { p.operands[op.operands_start] = airbitcode.IRTypedOperand{...original, number: number}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('invalid fneg source admitted') }; unchanged(actual); metadata++ }; p.operands[op.operands_start] = original
  }; unsafe { indices.free(); input.free(); actual.free(); native.free(); bs.free() }
 }
 assert cases.len == 150 && native_count + choices + poison + controls == 1150 && scalar == 2300 && metadata == 2700 && budgets == 300
 return Counts{cases.len, native_count, choices, poison, scalar, metadata, controls, budgets}
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } {
   s.write_string('%v${i} = fneg <${if storage { 1 } else { 16 }} x half> zeroinitializer\n')
  }
  if !storage { for i in 0 .. if over { 54309 } else { 54308 } { s.write_string('%x${i} = extractelement <16 x half> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory vector limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('scalar vector limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 58406 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 58405 } }
 unsafe { output.free(); bs.free() }
}
fn focused_controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(32768)
 s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['literal', 'poison', 'undef', 'partial_poison', 'partial_undef', 'source_poison', 'source_undef', 'result_poison', 'result_undef', 'discard_poison', 'discard_undef', 'old', 'double', 'compare_select', 'prior_undef', 'index_undef']
 guards := ['flags', 'wide', 'coldwide', 'scalable', 'double', 'argument', 'load', 'phi']
 for element in 64 .. 66 {
  t := typ(element); width := bits(element)
  defined := '<${t} ${literal(element, lane_word(element, 4))}, ${t} ${literal(element, lane_word(element, 1))}>'
  for mode in modes {
   initial := if mode.ends_with('poison') { 'poison' } else if mode.ends_with('undef') { 'undef' } else { defined }
   source := if mode.starts_with('partial_') { '<${t} ${literal(element, lane_word(element, 4))}, ${t} ${if mode.ends_with('undef') { 'undef' } else { 'poison' }}>' } else { initial }
   pre := if mode == 'prior_undef' { '%prior = extractelement <2 x ${t}> undef, i32 0\n' } else if mode == 'index_undef' { '%prior = insertelement <2 x ${t}> poison, ${t} zeroinitializer, i32 undef\n' } else if mode.starts_with('source_') { '%prior = freeze <2 x ${t}> ${source}\n' } else { '' }
   operand := if mode.starts_with('source_') || mode == 'index_undef' { '%prior' } else { source }
   post := match mode {
    'old' { '%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n' }
    'double' { '%other = fneg <2 x ${t}> %n\n' }
    'compare_select' { '%c = fcmp uno <2 x ${t}> %n, %n\n %other = select <2 x i1> %c, <2 x ${t}> %n, <2 x ${t}> zeroinitializer\n' }
    else { if mode.starts_with('result_') { '%other = freeze <2 x ${t}> %n\n' } else { '' } }
   }
   selected := if mode == 'double' || mode == 'compare_select' || mode.starts_with('result_') { '%other' } else { '%n' }
   store := if mode.starts_with('discard_') { '' } else { '%v = extractelement <2 x ${t}> ${selected}, i32 0\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n' }
   s.write_string('define void @${mode}_${element}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%n = fneg <2 x ${t}> ${operand}\n ${post}${store}ret void }\n')
  }
  for guard in guards {
   signature := if guard == 'argument' { '<2 x ${t}> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
   body := match guard {
    'flags' { '%n = fneg nnan <2 x ${t}> zeroinitializer' }
    'wide', 'coldwide' { '${if guard == 'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold:' } else { '' }} %n = fneg <17 x ${t}> zeroinitializer' }
    'scalable' { '%n = fneg <vscale x 2 x ${t}> zeroinitializer' }
    'double' { '%n = fneg <2 x double> zeroinitializer' }
    'argument' { '%n = fneg <2 x ${t}> %v' }
    'load' { '%v = load <2 x ${t}>, ptr %src, align 1\n %n = fneg <2 x ${t}> %v' }
    else { 'br label %body\n body: %v = phi <2 x ${t}> [zeroinitializer, %entry]\n %n = fneg <2 x ${t}> %v' }
   }
   s.write_string('define void @guard_${guard}_${element}(${signature}) { entry: store i8 17, ptr %out, align 1\n ${body}\n ret void }\n')
  }
  s.write_string('define i32 @loop_${element}(i32 %limit) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %small = trunc i32 %i to i16\n %x = bitcast i${width} ${if width == 16 { '%small' } else { '%i' }} to ${t}\n %a = insertelement <2 x ${t}> poison, ${t} %x, i32 0\n %n = fneg <2 x ${t}> %a\n %d = fneg <2 x ${t}> %n\n %f = freeze <2 x ${t}> %d\n %v = extractelement <2 x ${t}> %f, i32 0\n %raw = bitcast ${t} %v to i${width}\n %extended = zext i${width} %raw to i64\n %word = trunc i64 %extended to i32\n %added = add i32 %sum, %word\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i32 %added }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!
 stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut controls := 0
 for element in 64 .. 66 {
  for mode in modes {
   mut output := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
   bad := mode in ['poison', 'undef', 'partial_undef', 'result_undef', 'discard_undef', 'prior_undef', 'index_undef']
   if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, '${mode}_${element}'), mut bindings, 40) { panic('indeterminate fneg accepted: ' + mode) } } else { p.run_memory_function(ir, stream, pools, bodies, fi(ir, '${mode}_${element}'), mut bindings, 40)! }
   sign := u64(1) << u32(bits(element) - 1)
   word := if mode.starts_with('source_') { sign } else if mode == 'result_poison' { u64(0) } else if mode == 'double' { lane_word(element, 4) } else { lane_word(element, 4) + sign }
   for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + bits(element) / 8 { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) }, mode }; controls++; unsafe { output.free(); bindings.free() }
  }
  for guard in guards {
   mut output := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bindings << airbitcode.IRMemoryBinding{data: output, writable: true} }
   if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_${guard}_${element}'), mut bindings, 100) { panic('unsupported fneg profile: ' + guard) }; unchanged(output); controls++; unsafe { output.free(); bindings.free() }
  }
  for count in [u64(1), 2, 3, 16, 257]! {
   run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop_${element}'), [count], int(count * 16 + 2))!; assert !run.poison && run.value == count * (count - 1) / 2 && run.steps == int(count * 16 + 2); controls++
  }
  function := fi(ir, 'literal_${element}'); scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   if stream.records[bodies.instructions[index].record].code != 56 { continue }
   op := p.instructions[index]; typ := p.types[op.result_type]; ref := p.references[typ.refs_start]; lane := p.types[ref]
   for changed in [airbitcode.IRType{...lane, kind: .integer_t, bits: u32(bits(element))}, airbitcode.IRType{...lane, kind: .double_t}, airbitcode.IRType{...lane, kind: .pointer_t}] {
    p.types[ref] = changed; mut output := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: output, writable: true}]
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 100) { panic('nonfloating vector fneg admitted') }; unchanged(output); controls++; unsafe { output.free(); bindings.free() }
   }; p.types[ref] = lane
  }
 }
 assert controls == 64
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FNEG-CONTROLS: ${controls} source/result freezing, strict undef, localized poison, discarded results, old snapshots, repeated loop slots, comparison/select composition, unsupported profiles and lane-type mutations PASS\n')!
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut native := 0; mut choices := 0; mut poison := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for element in 64 .. 66 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; shapes += n.shapes; native += n.native; choices += n.choices; poison += n.poison; scalar += n.scalar; metadata += n.metadata; controls += n.controls; budgets += n.budgets }
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 focused_controls(os.args[1], out + '/controls')!
 assert shapes == 300 && native + choices + poison + controls == 2300 && scalar == 4600 && metadata == 5400 && budgets == 600
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FNEG: ${shapes} half/float, 1/2/3/4/8/16-lane shapes, five forms and literal/computed/double/inserted/shuffled snapshots; ${native} exact native LLVM values, ${choices} fixed-zero choices, ${poison} poison-store failures, ${controls} strict undef rejections, ${scalar} scalar/integer checks, ${metadata} metadata/source, ${budgets} budgets and eight storage/work boundary controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
