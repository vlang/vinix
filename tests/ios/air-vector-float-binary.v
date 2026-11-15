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
type NativeFloatBinary = fn (voidptr, voidptr, voidptr)
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

struct Case { name string element int count int form int mode int operation int }
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
fn expected(c Case, j u64, q u64, r u64, x u64) (int, u64) {
 if c.mode == 0 || j < u64(c.count) { for lane in 0 .. c.count {
  if c.mode != 0 && j == u64(lane) { continue }
  if c.form == 3 || (c.form == 1 && lane % 4 == 2) { return 3, 0 }
 } }
 if r >= u64(c.count) { return 1, 0 }
 mut lane := int(r); mut updated := c.mode == 3
 if c.mode == 4 { lane = c.count - 1 - int(r); updated = int(r) % 2 == 0 }
 if updated { if q >= u64(c.count) { return 1, 0 }; if q == u64(lane) { return 4, x } }
 poison, _ := source_lane(c, j, lane, x)
 if poison || (c.mode != 0 && q >= u64(c.count)) { return if c.mode >= 2 { 2 } else { 1 }, 0 }
 return 0, 0
}
fn right_vector(c Case) string {
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; s.write_string(typ(c.element) + ' ' + literal(c.element, lane_word(c.element, (lane + 7) % 16))) }; s.write_string('>'); return s.str()
}
fn is_nan(element int, word u64) bool { return if element == 64 { word & 0x7fff > 0x7c00 } else { word & 0x7fffffff > 0x7f800000 } }
fn preferred_nan(element int) u64 { return if element == 64 { u64(0x7e00) } else { u64(0x7fc00000) } }
fn run_batch(assembler_path string, out string, element int) !Counts {
 mut s := strings.new_builder(2097152); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for form in 0 .. 5 { for mode in 0 .. 5 { for operation in 0 .. 5 {
  c := Case{'case_${cases.len}', element, count, form, mode, operation}; cases << c
  selected := ['%n', '%n', '%f', '%u', '%t'][mode]
  lhs := if mode == 0 { vector(c) } else { '%a' }; rhs := if mode == 0 { right_vector(c) } else { '%b' }
  binary := ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'][operation]
  ops := '%a = insertelement <${count} x ${t}> ${vector(c)}, ${t} %x, i64 %j\n %b = insertelement <${count} x ${t}> ${right_vector(c)}, ${t} %y, i64 %q\n %n = ${binary} <${count} x ${t}> ${lhs}, ${rhs}\n %f = freeze <${count} x ${t}> %n\n %u = insertelement <${count} x ${t}> %f, ${t} %x, i64 %q\n %t = shufflevector <${count} x ${t}> %u, <${count} x ${t}> %f, <${count} x i32> ${mask_text(count, true)}\n %v = extractelement <${count} x ${t}> ${selected}, i64 %r\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops} %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${t} %x, ${t} %y) { ${ops} ret ${t} %v }\n')
 } } } }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-float-binary'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
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
   j := edges[sample % 8]; q := edges[(sample * 3 + 1) % 8]; r := u64(sample); x := lane_word(element, sample % 16); y := lane_word(element, (sample + 5) % 16); state, direct_word := expected(c, j, q, r, x)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. bits(element) / 8 { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   mut word := direct_word
   if state in [0, 4] {
    unsafe { NativeFloatBinary(voidptr(address))(&indices[1], &input[1], &native[3]) }
    mut native_word := u64(0); for i in 0 .. bits(element) / 8 { native_word |= u64(native[11 + i]) << u32(i * 8) }
    if state == 4 { assert native_word == direct_word } else { word = if is_nan(element, native_word) { preferred_nan(element) } else { native_word } }
    for i, b in native { if i >= 11 && i < 11 + bits(element) / 8 { continue }; assert b == if i == 3 { u8(17) } else { u8(0xcc) } }
   }
   args := [j, q, r, x | ~mask(bits(element)), y | ~mask(bits(element))]
   if state == 3 {
    if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 8) { panic('undef scalar binary') } else { assert err.msg() == 'AIR vector: undef binary lane', err.msg() }
   } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 8)!; assert run.poison == (state == 1) && run.bits == bits(element) && run.steps == 8 && (run.poison || run.value == word), '${c.name} scalar j=${j} q=${q} r=${r}' }
   if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 8) { panic('FP vector entered integer API') }; scalar += 2
   if state in [1, 3] {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('indeterminate binary stored') } else { assert err.msg() == if state == 3 { 'AIR vector: undef binary lane' } else { 'AIR memory execution: poison store' }, err.msg() }
    for i, b in actual { assert b == if i == 3 { u8(17) } else { u8(0xcc) } }; if state == 3 { controls++ } else { poison++ }
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19)!.steps == 19
    for i, b in actual { assert b == if i == 3 { u8(17) } else if i >= 11 && i < 11 + bits(element) / 8 { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${c.name} memory j=${j} q=${q} r=${r}' }
    if state == 2 { choices++ } else { native_count++ }
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0], 7) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 2 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, opcode: 3}, airbitcode.IRTypedInstruction{...op, operands_count: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 3}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('floating binary metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
   for operand in op.operands_start .. op.operands_start + 2 {
    original := p.operands[operand]
    for changed in [airbitcode.IRTypedOperand{...original, number: 0}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: -1}] {
     p.operands[operand] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('invalid binary source admitted') }; unchanged(actual); metadata++
    }; p.operands[operand] = original
   }
  }; unsafe { indices.free(); input.free(); actual.free(); native.free(); bs.free() }
 }
 assert cases.len == 750 && native_count + choices + poison + controls == 5750 && scalar == 11500 && metadata == 9750 && budgets == 1500
 return Counts{cases.len, native_count, choices, poison, scalar, metadata, controls, budgets}
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } {
   s.write_string('%v${i} = fadd <${if storage { 1 } else { 16 }} x half> zeroinitializer, zeroinitializer\n')
  }
  if !storage { for i in 0 .. if over { 50213 } else { 50212 } { s.write_string('%x${i} = extractelement <16 x half> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory vector limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('scalar vector limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 54310 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 54309 } }
 unsafe { output.free(); bs.free() }
}
struct FloatControl { name string word u64 fail bool discard bool guard bool }
fn fp_word(element int, value int) u64 {
 // Exact constants for 0,1,2,3.5,4.5,5,6,7,9,10,14,15 and -2.
 values := [0, 1, 2, 35, 45, 5, 6, 7, 9, 10, 14, 15, -2]!
 half := [u64(0), 0x3c00, 0x4000, 0x4300, 0x4480, 0x4500, 0x4600, 0x4700, 0x4880, 0x4900, 0x4b00, 0x4b80, 0xc000]!
 single := [u64(0), 0x3f800000, 0x40000000, 0x40600000, 0x40900000, 0x40a00000, 0x40c00000, 0x40e00000, 0x41100000, 0x41200000, 0x41600000, 0x41700000, 0xc0000000]!
 for i, x in values { if x == value { return if element == 64 { half[i] } else { single[i] } } }; panic('constant')
}
fn focused_controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(131072); mut cases := []FloatControl{}
 s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['defined', 'poison_left', 'poison_right', 'undef_left', 'undef_right', 'partial_poison_left', 'partial_poison_right', 'partial_undef_left', 'partial_undef_right', 'source_left', 'source_right', 'result_poison', 'result_undef', 'discard_poison', 'discard_undef', 'old', 'chain', 'prior_undef', 'index_undef', 'zero_divisor', 'infinite_dividend', 'nan']
 for element in 64 .. 66 {
  t := typ(element); infinity := if element == 64 { u64(0x7c00) } else { u64(0x7f800000) }
  for operation, binary in ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'] {
   for mode in modes {
    name := '${mode}_${operation}_${element}'; lhs := literal(element, fp_word(element, 7)); rhs := literal(element, fp_word(element, 2))
    left := if mode in ['poison_left', 'result_poison', 'discard_poison'] { 'poison' } else if mode in ['undef_left', 'source_left', 'result_undef', 'discard_undef', 'prior_undef'] { 'undef' } else if mode.starts_with('partial_') && mode.ends_with('_left') { '<${t} ${lhs}, ${t} ${if mode.contains('undef') { 'undef' } else { 'poison' }}>' } else { '<${t} ${if mode == 'infinite_dividend' { literal(element, infinity) } else if mode == 'nan' { literal(element, lane_word(element, 4)) } else { lhs }}, ${t} ${lhs}>' }
    right := if mode == 'poison_right' { 'poison' } else if mode in ['undef_right', 'source_right'] { 'undef' } else if mode.starts_with('partial_') && mode.ends_with('_right') { '<${t} ${rhs}, ${t} ${if mode.contains('undef') { 'undef' } else { 'poison' }}>' } else if mode == 'zero_divisor' { 'zeroinitializer' } else { '<${t} ${rhs}, ${t} ${rhs}>' }
    pre := if mode == 'prior_undef' { '%prior = extractelement <2 x ${t}> undef, i32 0\n' } else if mode == 'index_undef' { '%prior = insertelement <2 x ${t}> zeroinitializer, ${t} ${lhs}, i32 undef\n' } else if mode == 'source_left' { '%prior = freeze <2 x ${t}> ${left}\n' } else if mode == 'source_right' { '%prior = freeze <2 x ${t}> ${right}\n' } else { '' }
    a := if mode in ['source_left', 'index_undef'] { '%prior' } else { left }; b := if mode == 'source_right' { '%prior' } else { right }
    post := if mode == 'old' { '%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n' } else if mode.starts_with('result_') { '%other = freeze <2 x ${t}> %n\n' } else if mode == 'chain' { '%added = fadd <2 x ${t}> %n, <${t} ${literal(element, fp_word(element, 1))}, ${t} ${literal(element, fp_word(element, 1))}>\n %neg = fneg <2 x ${t}> %added\n %c = fcmp oeq <2 x ${t}> %n, %n\n %selected = select <2 x i1> %c, <2 x ${t}> %neg, <2 x ${t}> %n\n %shuffled = shufflevector <2 x ${t}> %selected, <2 x ${t}> %n, <2 x i32> <i32 0, i32 2>\n %other = fneg <2 x ${t}> %shuffled\n' } else { '' }
    selected := if mode.starts_with('result_') || mode == 'chain' { '%other' } else { '%n' }
    store := if mode.starts_with('discard_') { '' } else { '%v = extractelement <2 x ${t}> ${selected}, i32 0\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} %v, ptr %d, align 1\n' }
    s.write_string('define void @${name}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%n = ${binary} <2 x ${t}> ${a}, ${b}\n ${post}${store}ret void }\n')
    word := if mode == 'result_poison' { u64(0) } else if mode == 'chain' { fp_word(element, [10, 6, 15, 45, 2]![operation]) } else if mode == 'source_left' { fp_word(element, [2, -2, 0, 0, 0]![operation]) } else if mode in ['source_right', 'zero_divisor'] { if operation < 3 { fp_word(element, [7, 7, 0]![operation]) } else if operation == 3 { infinity } else { preferred_nan(element) } } else if mode == 'infinite_dividend' { if operation == 4 { preferred_nan(element) } else { infinity } } else if mode == 'nan' { preferred_nan(element) } else { fp_word(element, [9, 5, 14, 35, 1]![operation]) }
    fail := mode in ['poison_left', 'poison_right', 'undef_left', 'undef_right', 'partial_undef_left', 'partial_undef_right', 'result_undef', 'discard_undef', 'prior_undef', 'index_undef']
    cases << FloatControl{name, word, fail, mode.starts_with('discard_'), false}
   }
   for flag in ['nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast'] {
    name := 'flag_${flag}_${operation}_${element}'; s.write_string('define void @${name}(ptr %out) { store i8 17, ptr %out\n %n = ${binary} ${flag} <2 x ${t}> zeroinitializer, zeroinitializer\n ret void }\n'); cases << FloatControl{name: name, guard: true}
   }
  }
  for guard in ['wide', 'coldwide', 'scalable', 'double', 'bfloat', 'argument', 'load', 'phi'] {
   name := 'guard_${guard}_${element}'; signature := if guard == 'argument' { '<2 x ${t}> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
   body := match guard {
    'wide', 'coldwide' { '${if guard == 'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold:' } else { '' }} %n = fadd <17 x ${t}> zeroinitializer, zeroinitializer' }
    'scalable' { '%n = fadd <vscale x 2 x ${t}> zeroinitializer, zeroinitializer' }
    'double', 'bfloat' { '%n = fadd <2 x ${guard}> zeroinitializer, zeroinitializer' }
    'argument' { '%n = fadd <2 x ${t}> %v, zeroinitializer' }
    'load' { '%v = load volatile <2 x ${t}>, ptr %src, align 1\n %n = fadd <2 x ${t}> %v, zeroinitializer' }
    else { 'br label %body\n body: %v = phi <2 x ${t}> [zeroinitializer, %entry]\n %n = fadd <2 x ${t}> %v, zeroinitializer' }
   }
   s.write_string('define void @${name}(${signature}) { entry: store i8 17, ptr %out\n ${body}\n ret void }\n'); cases << FloatControl{name: name, guard: true}
  }
  width := bits(element)
  s.write_string('define i32 @float_loop_${element}(i32 %limit) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %small = trunc i32 %i to i16\n %x = bitcast i${width} ${if width == 16 { '%small' } else { '%i' }} to ${t}\n %a = insertelement <2 x ${t}> poison, ${t} %x, i32 0\n %n = fadd <2 x ${t}> %a, zeroinitializer\n %d = fsub <2 x ${t}> %n, zeroinitializer\n %f = freeze <2 x ${t}> %d\n %v = extractelement <2 x ${t}> %f, i32 0\n %raw = bitcast ${t} %v to i${width}\n %extended = zext i${width} %raw to i64\n %word = trunc i64 %extended to i32\n %added = add i32 %sum, %word\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i32 %added }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!
 stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 for c in cases {
  element := if c.name.ends_with('_64') { 64 } else { 65 }
  mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
  if c.name.starts_with('guard_argument') || c.name.starts_with('guard_load') { bs << airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true} }
  if c.fail || c.guard { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, c.name), mut bs, 100) { panic('invalid binary control accepted: ' + c.name) } } else { p.run_memory_function(ir, stream, pools, bodies, fi(ir, c.name), mut bs, 100)! }
  for i, b in output { assert b == if !c.guard && i == 3 { u8(17) } else if !c.guard && !c.fail && !c.discard && i >= 11 && i < 11 + bits(element) / 8 { u8(c.word >> u32((i - 11) * 8)) } else { u8(0xcc) }, c.name }
  unsafe { output.free(); bs.free() }
 }
 for element in 64 .. 66 { for count in [u64(1), 2, 3, 16, 257]! {
  function := fi(ir, 'float_loop_${element}')
  run := p.run_scalar_function(ir, stream, pools, bodies, function, [count], int(count * 16 + 2))!; assert !run.poison && run.value == count * (count - 1) / 2 && run.steps == int(count * 16 + 2)
  if _ := p.run_integer_function(ir, stream, pools, bodies, function, [count], int(count * 16 + 2)) { panic('floating vector loop entered integer API') }
 } }
 assert cases.len == 316
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FLOAT-BINARY-CONTROLS: ${cases.len + 20} left/right poison/undef, source/result freezing, discards, immutable old snapshots, arithmetic/negation/comparison/select/shuffle chains, IEEE zero/inf/NaN, all fast-math flags, inactive blocks, loop slot reuse and unsupported profiles PASS\n')!
}
fn native_sweep(assembler_path string, out string) ! {
 mut s := strings.new_builder(65536)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for element in 64 .. 66 { for operation, binary in ['fadd', 'fsub', 'fmul', 'fdiv', 'frem'] {
  t := typ(element); bytes := bits(element) / 8
  s.write_string('define void @sweep_${element}_${operation}(ptr %left, ptr %right, ptr %out) { store i8 17, ptr %out, align 1\n')
  for lane in 0 .. 16 { for side, input in ['left', 'right'] {
   prefix := if side == 0 { 'a' } else { 'b' }
   s.write_string('%${prefix}p${lane} = getelementptr i8, ptr %${input}, i64 ${lane * bytes}\n %${prefix}x${lane} = load ${t}, ptr %${prefix}p${lane}, align 1\n %${prefix}${lane} = insertelement <16 x ${t}> ${if lane == 0 { 'poison' } else { '%${prefix}${lane - 1}' }}, ${t} %${prefix}x${lane}, i32 ${lane}\n')
  } }
  s.write_string('%n = ${binary} <16 x ${t}> %a15, %b15\n')
  for lane in 0 .. 16 { s.write_string('%v${lane} = extractelement <16 x ${t}> %n, i32 ${lane}\n %d${lane} = getelementptr i8, ptr %out, i64 ${8 + lane * bytes}\n store ${t} %v${lane}, ptr %d${lane}, align 1\n') }; s.write_string('ret void }\n')
 } }
 data := assemble(assembler_path, out, s.str())!; verify(data)!
 stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-float-sweep'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; mut message := &char(unsafe { nil }); assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut comparisons := 0; mut nan_choices := 0; mut seed := u64(0x9e3779b97f4a7c15)
 for element in 64 .. 66 {
  bytes := bits(element) / 8
  mut left := []u8{len: 16 * bytes + 3, init: 0xcc}; mut right := []u8{len: 16 * bytes + 5, init: 0xcc}; mut actual := []u8{len: 16 * bytes + 13, init: 0xcc}; mut native := actual.clone()
  mut bs := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 2, writable: true}]
  mut functions := []int{}; mut addresses := []u64{}
  for operation in 0 .. 5 {
   name := 'sweep_${element}_${operation}'; function := fi(ir, name); functions << function; addresses << C.LLVMGetFunctionAddress(engine, name.str); assert addresses.last() != 0
   profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 147 && profile.arguments[0].minimum_size == 16 * bytes && profile.arguments[1].minimum_size == 16 * bytes && profile.arguments[2].minimum_size == 8 + 16 * bytes; profile.free()
  }
  for batch in 0 .. 4112 {
   for lane in 0 .. 16 {
    index := batch * 16 + lane
    mut a := u64(0); mut b := u64(0)
    if index < 256 { a = lane_word(element, index / 16); b = lane_word(element, index % 16) }
    else if element == 64 { a = u64(index - 256); b = (a * 40503 + 97) & 65535 }
    else { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; a = seed & 0xffffffff; seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; b = seed & 0xffffffff }
    for i in 0 .. bytes { left[1 + lane * bytes + i] = u8(a >> u32(i * 8)); right[3 + lane * bytes + i] = u8(b >> u32(i * 8)) }
   }
   for operation in 0 .. 5 {
    for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
    unsafe { NativeFloatBinary(voidptr(addresses[operation]))(&left[1], &right[3], &native[2]) }
    assert p.run_memory_function(ir, stream, pools, bodies, functions[operation], mut bs, 147)!.steps == 147
    for lane in 0 .. 16 {
     mut actual_word := u64(0); mut native_word := u64(0)
     for i in 0 .. bytes { actual_word |= u64(actual[10 + lane * bytes + i]) << u32(i * 8); native_word |= u64(native[10 + lane * bytes + i]) << u32(i * 8) }
     if is_nan(element, native_word) { assert actual_word == preferred_nan(element); nan_choices++ } else { assert actual_word == native_word, 'format=${element} op=${operation} batch=${batch} lane=${lane}' }; comparisons++
    }
    for i in 0 .. actual.len { if i >= 10 && i < 10 + 16 * bytes { continue }; expected := if i == 2 { u8(17) } else { u8(0xcc) }; assert actual[i] == expected && native[i] == expected }
   }
  }
  unsafe { left.free(); right.free(); actual.free(); native.free(); bs.free(); functions.free(); addresses.free() }
 }
 assert comparisons == 657920
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FLOAT-BINARY-SWEEP: ${comparisons} native LLVM lane comparisons (${nan_choices} preferred-NaN choices), all 65536 half left encodings, permuted half right encodings, deterministic float pairs and complete 16x16 edge grids; all five operations, unaligned scalar accesses and every output byte PASS\n')!
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut native := 0; mut choices := 0; mut poison := 0; mut scalar := 0; mut metadata := 0; mut controls := 0; mut budgets := 0
 for element in 64 .. 66 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; shapes += n.shapes; native += n.native; choices += n.choices; poison += n.poison; scalar += n.scalar; metadata += n.metadata; controls += n.controls; budgets += n.budgets }
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 focused_controls(os.args[1], out + '/controls')!
 native_sweep(os.args[1], out + '/sweep')!
 assert shapes == 1500 && native + choices + poison + controls == 11500 && scalar == 23000 && metadata == 19500 && budgets == 3000
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FLOAT-BINARY: ${shapes} half/float, 1/2/3/4/8/16-lane shapes, five forms and literal/computed/frozen/inserted/shuffled snapshots; ${native} native LLVM values (arithmetic NaNs normalized), ${choices} fixed-zero choices, ${poison} poison-store failures, ${controls} strict undef rejections, ${scalar} scalar/integer checks, ${metadata} metadata/source, ${budgets} budgets and eight storage/work boundary controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
