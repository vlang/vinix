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
type NativeCompare = fn (voidptr, voidptr, voidptr)
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

struct Case { name string count int predicate int mode int }
struct Counts {
mut:
 shapes int defined int choices int poison int scalar int metadata int budgets int
}
fn pred_text(element int, predicate int) string {
 if element >= 64 { return 'fcmp ' + ['false', 'oeq', 'ogt', 'oge', 'olt', 'ole', 'one', 'ord', 'uno', 'ueq', 'ugt', 'uge', 'ult', 'ule', 'une', 'true'][predicate] }
 return 'icmp ' + if predicate >= 10 { 'samesign ' } else { '' } + ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule', 'sgt', 'sge', 'slt', 'sle'][predicate % 10]
}
fn vector_text(element int, count int, side int) string {
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; s.write_string(typ(element) + ' ' + literal(element, lane_word(element, (lane + side * 7) % 16))) }; s.write_string('>'); return s.str()
}
fn filled(count int, value int) string {
 mut s := strings.new_builder(512); s.write_string('<')
 for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; s.write_string('i32 ${value}') }; s.write_string('>'); return s.str()
}
fn state_for(c Case, element int, j u64, q u64, r u64, x u64, y u64) int {
 if r >= u64(c.count) { return 1 }
 if element >= 64 && c.predicate in [0, 15] { return 0 }
 mut poison := j >= u64(c.count) || q >= u64(c.count)
 if element < 64 && c.predicate >= 10 && !poison {
  a := if j == r { x } else { lane_word(element, int(r)) }; b := if q == r { y } else { lane_word(element, (int(r) + 7) % 16) }
  sign := u64(1) << u32(bits(element) - 1); poison = (a & sign != 0) != (b & sign != 0)
 }
 return if !poison { 0 } else if c.mode == 0 { 1 } else { 2 }
}
fn run_batch(assembler_path string, out string, element int) !Counts {
 mut s := strings.new_builder(4194304); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for predicate in 0 .. if element < 64 { 20 } else { 16 } { for mode in 0 .. 3 {
  c := Case{'case_${cases.len}', count, predicate, mode}; cases << c
  tail := if mode == 2 { '%v = extractelement <${count} x i32> %s, i64 %r\n %word = add i32 %v, 0\n' } else { '%v = extractelement <${count} x i1> ${if mode == 0 { '%c' } else { '%f' }}, i64 %r\n %word = zext i1 %v to i32\n' }
  ops := '%a = insertelement <${count} x ${t}> ${vector_text(element, count, 0)}, ${t} %x, i64 %j\n %b = insertelement <${count} x ${t}> ${vector_text(element, count, 1)}, ${t} %y, i64 %q\n %c = ${pred_text(element, predicate)} <${count} x ${t}> %a, %b\n %f = freeze <${count} x i1> %c\n %s = select <${count} x i1> %f, <${count} x i32> ${filled(count, 7)}, <${count} x i32> ${filled(count, 11)}\n ${tail}'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops} %d = getelementptr i8, ptr %out, i64 8\n store i32 %word, ptr %d, align 1\n ret void }\n')
  s.write_string('define i32 @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${t} %x, ${t} %y) { ${ops} ret i32 %word }\n')
 } } }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-compare'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); C.LLVMDeleteFunction(C.LLVMGetNamedFunction(module_ptr, name.str)); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut totals := Counts{shapes: cases.len}
 for c in cases {
  function := fi(ir, c.name); scalar_function := fi(ir, 'scalar_' + c.name); name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 19 && profile.arguments[0].minimum_size == 24 && profile.arguments[1].minimum_size == 8 + (bits(element) + 7) / 8 && profile.arguments[2].minimum_size == 12; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut native := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), u64(c.count), ~u64(0), 1, 2, 3, 4]!
  for sample in 0 .. (c.count + 1) * 2 {
   r := u64(sample / 2); j := edges[(sample / 2 + sample % 2) % 8]; q := edges[(sample / 2 * 3 + 1) % 8]; x := lane_word(element, sample % 16); y := lane_word(element, (sample + 5) % 16); state := state_for(c, element, j, q, r, x, y)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. (bits(element) + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   args := [j, q, r, x | ~mask(bits(element)), y | ~mask(bits(element))]
   run := p.run_scalar_function(ir, stream, pools, bodies, scalar_function, args, 8)!; assert run.bits == 32 && run.steps == 8 && run.poison == (state == 1)
   if element < 64 { integer := p.run_integer_function(ir, stream, pools, bodies, scalar_function, args, 8)!; assert integer.steps == 8 && integer.poison == run.poison && (integer.poison || integer.value == run.value) } else { if _ := p.run_integer_function(ir, stream, pools, bodies, scalar_function, args, 8) { panic('FP comparison entered integer API') } }; totals.scalar += 2
   if state == 1 {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('poison comparison stored') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() }; for i, byte in actual { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } }; totals.poison++
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19)!.steps == 19
    for i, byte in actual { assert byte == if i == 3 { u8(17) } else if i >= 11 && i < 15 { u8(run.value >> u32((i - 11) * 8)) } else { u8(0xcc) } }
    if state == 0 { unsafe { NativeCompare(voidptr(address))(&indices[1], &input[1], &native[3]) }; assert actual == native, '${c.name}: j=${j} q=${q} r=${r}'; totals.defined++ }
    else { assert run.value == if c.mode == 1 { u64(0) } else { u64(11) }; totals.choices++ }
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, scalar_function, [u64(0), 0, 0, 0, 0], 7) { panic('scalar budget') }; totals.budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code !in [u64(9), 28] { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 2}, airbitcode.IRTypedInstruction{...op, opcode: 99}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 1}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('comparison metadata') }; unchanged(actual); totals.metadata++
   }; p.instructions[index] = op
   for slot in 0 .. 2 { original := p.operands[op.operands_start + slot]
    for changed in [airbitcode.IRTypedOperand{...original, type_index: -1}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}] { p.operands[op.operands_start + slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('comparison source') }; unchanged(actual); totals.metadata++ }; p.operands[op.operands_start + slot] = original
   }
  }; unsafe { indices.free(); input.free(); actual.free(); native.free(); bs.free() }
 }
 return totals
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'void'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out\n') }
  count := if storage { 1 } else { 16 }
  for i in 0 .. if storage && over { 4097 } else { 4096 } { s.write_string('%v${i} = icmp eq <${count} x i32> zeroinitializer, zeroinitializer\n') }
  if !storage { for i in 0 .. if over { 50213 } else { 50212 } { s.write_string('%x${i} = extractelement <16 x i1> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory comparison limit') }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'void'), [], 70000) { panic('void comparison limit') } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 54310 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'void'), [], 70000)!.steps == if storage { 4097 } else { 54309 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 controls(os.args[1], out + '/controls')!
 mut total := Counts{}
 for element in 0 .. 66 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; total = Counts{total.shapes + n.shapes, total.defined + n.defined, total.choices + n.choices, total.poison + n.poison, total.scalar + n.scalar, total.metadata + n.metadata, total.budgets + n.budgets} }
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 assert total.shapes == 23616 && total.defined + total.choices + total.poison == 314880 && total.scalar == 629760 && total.metadata == 259776 && total.budgets == 47232
 os.write_file(out + '/result.txt', 'AIR-VECTOR-COMPARE: ${total.shapes} i1-i64/half/float shapes, counts 1/2/3/4/8/16, all ten ICMP predicates with/without samesign and sixteen FCMP predicates; ${total.defined} native LLVM values, ${total.choices} fixed-zero freeze choices, ${total.poison} poison failures preserving earlier writes, ${total.scalar} scalar/integer checks, ${total.metadata} metadata/source and ${total.budgets} budget controls, eight public storage/work boundaries PASS\n')!; print(os.read_file(out + '/result.txt')!)
}

fn controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(1048576); s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['left_undef', 'right_undef', 'partial_undef', 'left_poison', 'right_poison', 'partial_poison', 'discard_poison', 'discard_undef', 'frozen_sources', 'frozen_mask', 'frozen_after_undef', 'false', 'true', 'old_mask', 'comparison_source']
 mut names := []string{}; mut bad_undef := []bool{}; mut bad_poison := []bool{}; mut values := []u32{}; mut budgets := []int{}
 for element, t in ['i32', 'half', 'float'] { for mode in modes { if element == 0 && mode in ['false', 'true'] { continue }; for lane in 0 .. 3 {
  name := '${t}_${mode}_${lane}'; names << name
  lhs := if mode in ['left_undef', 'discard_undef', 'frozen_sources', 'frozen_after_undef', 'false', 'true'] { 'undef' } else if mode in ['left_poison', 'discard_poison', 'frozen_mask', 'old_mask'] { 'poison' } else if mode == 'partial_undef' { '<${t} zeroinitializer, ${t} undef>' } else if mode == 'partial_poison' { '<${t} zeroinitializer, ${t} poison>' } else { 'zeroinitializer' }
  rhs := if mode == 'right_undef' { 'undef' } else if mode in ['right_poison', 'false', 'true'] { 'poison' } else { 'zeroinitializer' }
  pre := if mode == 'frozen_sources' { '%a = freeze <2 x ${t}> ${lhs}\n %b = freeze <2 x ${t}> ${rhs}\n' } else { '' }
  comparison := if element == 0 { 'icmp eq' } else if mode in ['false', 'true'] { 'fcmp ' + mode } else { 'fcmp oeq' }
  post := if mode in ['frozen_mask', 'old_mask', 'frozen_after_undef'] { '%f = freeze <2 x i1> %c\n' } else if mode == 'comparison_source' { '%s = shufflevector <2 x i1> %c, <2 x i1> poison, <2 x i32> <i32 1, i32 0>\n %i = insertelement <2 x i1> %s, i1 true, i32 0\n %w = icmp eq <2 x i1> %i, %c\n' } else { '' }
  selected := if mode == 'frozen_mask' { '%f' } else if mode == 'comparison_source' { '%w' } else { '%c' }
  discarded := mode.starts_with('discard_')
  tail := if discarded { '' } else { '${post}%v = extractelement <2 x i1> ${selected}, i32 ${lane}\n %word = zext i1 %v to i32\n %d = getelementptr i8, ptr %out, i64 8\n store i32 %word, ptr %d, align 1\n' }
  s.write_string('define void @${name}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%c = ${comparison} <2 x ${t}> ${if mode == 'frozen_sources' { '%a' } else { lhs }}, ${if mode == 'frozen_sources' { '%b' } else { rhs }}\n ${tail} ret void }\n')
  bad_undef << mode in ['left_undef', 'right_undef', 'partial_undef', 'discard_undef', 'frozen_after_undef']
  bad_poison << !discarded && (lane == 2 || mode in ['left_poison', 'right_poison', 'old_mask'] || (mode == 'partial_poison' && lane == 1))
  values << if mode in ['false', 'frozen_mask'] { u32(0) } else { u32(1) }
  budgets << if discarded { 3 } else if mode == 'frozen_sources' { 9 } else if mode == 'comparison_source' { 10 } else if post != '' { 8 } else { 7 }
 } } }
 s.write_string('define void @guard_argument(<2 x i32> %v, ptr %out) { store i8 17, ptr %out\n %c = icmp eq <2 x i32> %v, zeroinitializer\n ret void }\n define void @guard_load(ptr %src, ptr %out) { store i8 17, ptr %out\n %v = load <2 x i32>, ptr %src\n %c = icmp eq <2 x i32> %v, zeroinitializer\n ret void }\n define void @guard_phi(ptr %out) { entry: store i8 17, ptr %out\n br label %body\n body: %v = phi <2 x i32> [zeroinitializer, %entry]\n %c = icmp eq <2 x i32> %v, zeroinitializer\n ret void }\n define void @guard_cold(ptr %out) { store i8 17, ptr %out\n br i1 true, label %done, label %cold\n done: ret void\n cold: %v = icmp eq <17 x i32> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_double(ptr %out) { store i8 17, ptr %out\n %v = fcmp oeq <2 x double> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_flags(ptr %out) { store i8 17, ptr %out\n %v = fcmp nnan oeq <2 x float> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_pointer(ptr %out) { store i8 17, ptr %out\n %v = icmp eq <2 x ptr> zeroinitializer, zeroinitializer\n ret void }\n')
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut checks := 0
 for i, name in names {
  mut output := []u8{len: 20, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 2, writable: true}]
  if bad_undef[i] || bad_poison[i] { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, budgets[i]) { panic('indeterminate control: ' + name) } else { assert err.msg() == if bad_undef[i] { 'AIR vector: undef comparison lane' } else { 'AIR memory execution: poison store' }, name + ': ' + err.msg() } }
  else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, budgets[i])!.steps == budgets[i] }
  for j, byte in output { assert byte == if j == 2 { u8(17) } else if !bad_undef[i] && !bad_poison[i] && !name.contains('discard_') && j >= 10 && j < 14 { u8(values[i] >> u32((j - 10) * 8)) } else { u8(0xcc) }, name }; checks++
  scope := bodies.scopes[fi(ir, name) + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code !in [u64(9), 28] { continue }
   result_type := p.types[op.result_type]
   for changed in [airbitcode.IRType{...result_type, count: 1}, airbitcode.IRType{...result_type, count: 17}, airbitcode.IRType{...result_type, refs_start: -1}] {
    for j in 0 .. output.len { output[j] = 0xcc }; p.types[op.result_type] = changed
    if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, budgets[i]) { panic('comparison result shape') }; unchanged(output); checks++
   }; p.types[op.result_type] = result_type
  }; unsafe { output.free(); bs.free() }
 }
 for name in ['argument', 'load', 'phi', 'cold', 'double', 'flags', 'pointer'] {
  mut output := []u8{len: 16, init: 0xcc}; mut bs := if name in ['argument', 'load'] { [airbitcode.IRMemoryBinding{data: output}, airbitcode.IRMemoryBinding{data: output, writable: true}] } else { [airbitcode.IRMemoryBinding{data: output, writable: true}] }
  if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + name), mut bs, 20) { panic('unsupported comparison: ' + name) }; unchanged(output); checks++; unsafe { output.free(); bs.free() }
 }
 assert checks == 550
 os.write_file(out + '/result.txt', 'AIR-VECTOR-COMPARE-CONTROLS: ${checks} undef/poison, constant FP predicates, source/result freezing, discards, comparison sources and snapshots, result-shape mutations and unsupported profiles PASS\n')!
}
