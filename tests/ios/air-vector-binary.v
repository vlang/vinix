// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
import math.bits as mbits
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
type NativeBinary = fn (voidptr, voidptr, voidptr)
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

struct Case { name string count int opcode int flags int mode int }
struct Counts {
mut:
 shapes int defined int choices int poison int scalar int metadata int budgets int hard int
}

fn flag_mask(op int) int { return match op { 0, 1, 2, 7 { 3 } 3, 4, 8, 9, 11 { 1 } else { 0 } } }
fn binary_text(op int, flags int) string {
 name := ['add', 'sub', 'mul', 'udiv', 'sdiv', 'urem', 'srem', 'shl', 'lshr', 'ashr', 'and', 'or', 'xor'][op]
 suffix := if flags == 0 { '' } else if op in [0, 1, 2, 7] { if flags == 1 { ' nuw' } else if flags == 2 { ' nsw' } else { ' nuw nsw' } } else if op == 11 { ' disjoint' } else { ' exact' }
 return name + suffix
}
fn lane_seed(c Case, element int, side int, lane int) u64 {
 return if side == 1 && c.opcode in [7, 8, 9] { u64(lane % (bits(element) + 1)) } else { lane_word(element, (lane + side * 7) % 16) }
}
fn vector_text(c Case, element int, side int) string {
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; s.write_string(typ(element) + ' ' + lane_seed(c, element, side, lane).str()) }; s.write_string('>'); return s.str()
}
fn bad_flags(c Case, width int, a u64, b u64) bool {
 limit := mask(width); sign := u64(1) << u32(width - 1); x := a & limit; y := b & limit
 if c.opcode in [7, 8, 9] && y >= u64(width) { return true }
 if c.flags == 0 { return false }
 nx := x >= sign; ny := y >= sign
 mut unsigned := false; mut signed := false
 match c.opcode {
  0 { sum := x + y; unsigned = sum < x || sum > limit; signed = nx == ny && nx != ((sum & limit) >= sign) }
  1 { unsigned = x < y; signed = nx != ny && nx != (((x - y) & limit) >= sign) }
  2, 7 {
   high, low := mbits.mul_64(x, if c.opcode == 7 { u64(1) << y } else { y }); unsigned = high != 0 || low > limit
   mag_x := if nx { (~x & limit) + 1 } else { x }; mag_y := if c.opcode == 7 { u64(1) << y } else if ny { (~y & limit) + 1 } else { y }
   hi, lo := mbits.mul_64(mag_x, mag_y); negative := if c.opcode == 7 { nx } else { nx != ny }; signed = hi != 0 || lo > if negative { sign } else { sign - 1 }
  }
  3 { return (x / y) * y != x }
  4 { mx := if nx { (~x & limit) + 1 } else { x }; my := if ny { (~y & limit) + 1 } else { y }; return (mx / my) * my != mx }
  8, 9 { return x % (u64(1) << y) != 0 }
  11 { return ((x + y) & limit) != x | y }
  else {}
 }
 return (c.flags & 1 != 0 && unsigned) || (c.flags & 2 != 0 && signed)
}
fn state_for(c Case, element int, j u64, q u64, r u64, x u64, y u64) int {
 width := bits(element); limit := mask(width); sign := u64(1) << u32(width - 1)
 if c.opcode in [3, 4, 5, 6] {
  if j >= u64(c.count) || q >= u64(c.count) { return 3 }
  for lane in 0 .. c.count {
   a := if j == u64(lane) { x & limit } else { lane_seed(c, element, 0, lane) }; b := if q == u64(lane) { y & limit } else { lane_seed(c, element, 1, lane) }
   if b == 0 || (c.opcode in [4, 6] && a == sign && b == limit) { return 3 }
  }
 }
 if r >= u64(c.count) { return 1 }
 a := if j == r { x & limit } else { lane_seed(c, element, 0, int(r)) }; b := if q == r { y & limit } else { lane_seed(c, element, 1, int(r)) }
 poison := j >= u64(c.count) || q >= u64(c.count) || bad_flags(c, width, a, b)
 return if !poison { 0 } else if c.mode == 0 { 1 } else { 2 }
}
fn run_batch(assembler_path string, out string, element int) !Counts {
 mut s := strings.new_builder(4194304); mut cases := []Case{}; t := typ(element)
 s.write_string('target datalayout = "e-p:64:64"\n')
 for count in [1, 2, 3, 4, 8, 16] { for opcode in 0 .. 13 { for flags in 0 .. flag_mask(opcode) + 1 { for mode in 0 .. 3 {
  c := Case{'case_${cases.len}', count, opcode, flags, mode}; cases << c
  ops := '%a = insertelement <${count} x ${t}> ${vector_text(c, element, 0)}, ${t} %x, i64 %j\n %b = insertelement <${count} x ${t}> ${vector_text(c, element, 1)}, ${t} %y, i64 %q\n %v = ${binary_text(opcode, flags)} <${count} x ${t}> %a, %b\n %f = freeze <${count} x ${t}> %v\n %c = icmp ne <${count} x ${t}> %f, zeroinitializer\n %s = select <${count} x i1> %c, <${count} x ${t}> %f, <${count} x ${t}> zeroinitializer\n %word = extractelement <${count} x ${t}> ${['%v', '%f', '%s'][mode]}, i64 %r\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops} %d = getelementptr i8, ptr %out, i64 8\n store ${t} %word, ptr %d, align 1\n ret void }\n')
  s.write_string('define ${t} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${t} %x, ${t} %y) { ${ops} ret ${t} %word }\n')
 } } } }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-compare'); defer { C.LLVMDisposeMemoryBuffer(buffer) }; mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); C.LLVMDeleteFunction(C.LLVMGetNamedFunction(module_ptr, name.str)); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut totals := Counts{shapes: cases.len}
 for c in cases {
  function := fi(ir, c.name); scalar_function := fi(ir, 'scalar_' + c.name); name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 19 && profile.arguments[0].minimum_size == 24 && profile.arguments[1].minimum_size == 8 + (bits(element) + 7) / 8 && profile.arguments[2].minimum_size == 8 + (bits(element) + 7) / 8; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut native := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), u64(c.count), ~u64(0), 1, 2, 3, 4]!
  for sample in 0 .. (c.count + 1) * 2 {
   r := u64(sample / 2); j := edges[(sample / 2 + sample % 2) % 8]; q := edges[(sample / 2 * 3 + 1) % 8]; x := lane_word(element, sample % 16); y := if c.opcode in [7, 8, 9] { u64(sample % (bits(element) + 1)) } else { lane_word(element, (sample + 5) % 16) }; state := state_for(c, element, j, q, r, x, y)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. (bits(element) + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; native[i] = 0xcc }
   args := [j, q, r, x | ~mask(bits(element)), y | ~mask(bits(element))]
   if state == 3 {
    if _ := p.run_scalar_function(ir, stream, pools, bodies, scalar_function, args, 8) { panic('undefined vector division returned') }
    if _ := p.run_integer_function(ir, stream, pools, bodies, scalar_function, args, 8) { panic('integer vector division returned') }; totals.scalar += 2
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('undefined vector division stored') } else { assert err.msg() in ['AIR integer: undefined division/remainder', 'AIR integer: poison division/remainder outside profile'], err.msg() }
    for i, byte in actual { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } }; totals.hard++; unsafe { args.free() }; continue
   }
   run := p.run_scalar_function(ir, stream, pools, bodies, scalar_function, args, 8)!; assert run.bits == bits(element) && run.steps == 8 && run.poison == (state == 1)
   integer := p.run_integer_function(ir, stream, pools, bodies, scalar_function, args, 8)!; assert integer.steps == 8 && integer.poison == run.poison && (integer.poison || integer.value == run.value); totals.scalar += 2
   if state == 1 {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19) { panic('poison comparison stored') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() }; for i, byte in actual { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } }; totals.poison++
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 19)!.steps == 19
    for i, byte in actual { assert byte == if i == 3 { u8(17) } else if i >= 11 && i < 11 + (bits(element) + 7) / 8 { u8(run.value >> u32((i - 11) * 8)) } else { u8(0xcc) } }
    if state == 0 { unsafe { NativeBinary(voidptr(address))(&indices[1], &input[1], &native[3]) }; if bits(element) % 8 != 0 { native[11 + (bits(element) + 7) / 8 - 1] &= u8((1 << (bits(element) % 8)) - 1) }; assert actual == native, '${c.name}: j=${j} q=${q} r=${r}'; totals.defined++ }
    else { assert run.value == 0; totals.choices++ }
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 18) { panic('memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, scalar_function, [u64(0), 0, 0, 0, 0], 7) { panic('scalar budget') }; totals.budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 2 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 4}, airbitcode.IRTypedInstruction{...op, opcode: 99}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 1}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
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
  for i in 0 .. if storage && over { 4097 } else { 4096 } { s.write_string('%v${i} = add <${count} x i32> zeroinitializer, zeroinitializer\n') }
  if !storage { for i in 0 .. if over { 50213 } else { 50212 } { s.write_string('%x${i} = extractelement <16 x i32> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
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
 for element in 0 .. 64 { n := run_batch(os.args[1], out + '/batch-${element}', element)!; total = Counts{total.shapes + n.shapes, total.defined + n.defined, total.choices + n.choices, total.poison + n.poison, total.scalar + n.scalar, total.metadata + n.metadata, total.budgets + n.budgets, total.hard + n.hard} }
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 assert total.shapes == 34560 && total.defined + total.choices + total.poison + total.hard == 460800 && total.scalar == 921600 && total.metadata == 380160 && total.budgets == 69120
 os.write_file(out + '/result.txt', 'AIR-VECTOR-BINARY: ${total.shapes} i1-i64 shapes, counts 1/2/3/4/8/16, thirteen binary opcodes and thirty flag variants; ${total.defined} native LLVM values, ${total.choices} fixed-zero freeze choices, ${total.poison} poison stores and ${total.hard} whole-vector division/remainder rejections preserving earlier writes, ${total.scalar} scalar/integer checks, ${total.metadata} metadata/source and ${total.budgets} budget controls, eight public storage/work boundaries PASS\n')!; print(os.read_file(out + '/result.txt')!)
}

fn controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(2097152); s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['defined', 'poison', 'undef', 'frozen_result', 'frozen_sources', 'discard_poison', 'discard_undef', 'old', 'zero', 'signed_overflow', 'overshift']
 mut names := []string{}; mut errors := []int{}; mut poisoned := []bool{}; mut words := []u64{}; mut budgets := []int{}
 for op in 0 .. 13 { for flags in 0 .. flag_mask(op) + 1 { for mode in modes {
  if (mode == 'zero' && op !in [3, 4, 5, 6]) || (mode == 'signed_overflow' && op !in [4, 6]) || (mode == 'overshift' && op !in [7, 8, 9]) { continue }
  for lane in 0 .. 3 {
   name := 'op${op}_${flags}_${mode}_${lane}'; names << name
   undef := mode in ['undef', 'discard_undef', 'frozen_sources']; poison := mode in ['poison', 'frozen_result', 'discard_poison', 'old']
   lhs := if undef { '<i32 7, i32 undef>' } else if poison { '<i32 7, i32 poison>' } else if mode == 'signed_overflow' { '<i32 7, i32 2147483648>' } else { '<i32 7, i32 7>' }
   rhs := if mode == 'zero' { '<i32 1, i32 0>' } else if mode == 'signed_overflow' { '<i32 1, i32 4294967295>' } else if mode == 'overshift' { '<i32 1, i32 32>' } else { '<i32 1, i32 1>' }
   pre := if mode == 'frozen_sources' { '%a = freeze <2 x i32> ${lhs}\n %b = freeze <2 x i32> ${rhs}\n' } else { '' }
   post := if mode in ['frozen_result', 'old'] { '%f = freeze <2 x i32> %v\n' } else { '' }
   discard := mode.starts_with('discard_')
   tail := if discard { '' } else { '${post}%word = extractelement <2 x i32> ${if mode == 'frozen_result' { '%f' } else { '%v' }}, i32 ${lane}\n %d = getelementptr i8, ptr %out, i64 8\n store i32 %word, ptr %d, align 1\n' }
   s.write_string('define void @${name}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%v = ${binary_text(op, flags)} <2 x i32> ${if mode == 'frozen_sources' { '%a, %b' } else { lhs + ', ' + rhs }}\n ${tail} ret void }\n')
   mut hard := 0; mut selected_poison := lane == 2; mut selected_word := u64(0)
   for i in 0 .. 2 {
    if i == 1 && undef && mode != 'frozen_sources' { hard = 4; break }
    if i == 1 && poison {
     if op in [3, 4, 5, 6] { hard = 3; break }
     if i == lane { selected_poison = true }; continue
    }
    a := if i == 1 && mode == 'frozen_sources' { u64(0) } else if i == 1 && mode == 'signed_overflow' { u64(2147483648) } else { u64(7) }
    b := if i == 1 && mode == 'zero' { u64(0) } else if i == 1 && mode == 'signed_overflow' { u64(4294967295) } else if i == 1 && mode == 'overshift' { u64(32) } else { u64(1) }
    if bad, word := control_expected(u32(op), u64(flags), 32, a, b) { if i == lane { selected_poison = bad; selected_word = word } } else { hard = 3; break }
   }
   if mode == 'frozen_result' && lane < 2 && selected_poison { selected_poison = false; selected_word = 0 }
   if discard { selected_poison = false }
   errors << hard; poisoned << selected_poison; words << selected_word
   budgets << if discard { 3 } else if pre != '' { 8 } else if post != '' { 7 } else { 6 }
  }
 } } }
 s.write_string('define void @guard_argument(<2 x i32> %v, ptr %out) { store i8 17, ptr %out\n %x = add <2 x i32> %v, zeroinitializer\n ret void }\n define void @guard_load(ptr %src, ptr %out) { store i8 17, ptr %out\n %v = load volatile <2 x i32>, ptr %src\n %x = add <2 x i32> %v, zeroinitializer\n ret void }\n define void @guard_phi(ptr %out) { entry: store i8 17, ptr %out\n br label %body\n body: %v = phi <2 x i32> [zeroinitializer, %entry]\n %x = add <2 x i32> %v, zeroinitializer\n ret void }\n define void @guard_cold(ptr %out) { store i8 17, ptr %out\n br i1 true, label %done, label %cold\n done: ret void\n cold: %x = add <17 x i32> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_float(ptr %out) { store i8 17, ptr %out\n %x = fadd nnan <2 x float> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_half(ptr %out) { store i8 17, ptr %out\n %x = fadd nnan <2 x half> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_scalable(ptr %out) { store i8 17, ptr %out\n %x = add <vscale x 2 x i32> zeroinitializer, zeroinitializer\n ret void }\n define void @guard_wide_integer(ptr %out) { store i8 17, ptr %out\n %x = add <2 x i65> zeroinitializer, zeroinitializer\n ret void }\n')
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut checks := 0
 for i, name in names {
  mut output := []u8{len: 20, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 2, writable: true}]
  if errors[i] != 0 || poisoned[i] {
   if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, budgets[i]) { panic('invalid binary control: ' + name) } else { assert if errors[i] == 4 { err.msg() == 'AIR vector: undef binary lane' } else if errors[i] == 3 { err.msg() in ['AIR integer: undefined division/remainder', 'AIR integer: poison division/remainder outside profile'] } else { err.msg() == 'AIR memory execution: poison store' }, name + ': ' + err.msg() }
  } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, budgets[i])!.steps == budgets[i] }
  for j, byte in output { assert byte == if j == 2 { u8(17) } else if errors[i] == 0 && !poisoned[i] && !name.contains('discard_') && j >= 10 && j < 14 { u8(words[i] >> u32((j - 10) * 8)) } else { u8(0xcc) }, name }; checks++
  scope := bodies.scopes[fi(ir, name) + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 2 { continue }
   result_type := p.types[op.result_type]
   for changed in [airbitcode.IRType{...result_type, count: 0}, airbitcode.IRType{...result_type, count: 17}, airbitcode.IRType{...result_type, refs_start: -1}] {
    for j in 0 .. output.len { output[j] = 0xcc }; p.types[op.result_type] = changed
    if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, budgets[i]) { panic('binary result shape') }; unchanged(output); checks++
   }; p.types[op.result_type] = result_type
  }; unsafe { output.free(); bs.free() }
 }
 for name in ['argument', 'load', 'phi', 'cold', 'float', 'half', 'scalable', 'wide_integer'] {
  mut output := []u8{len: 16, init: 0xcc}; mut bs := if name in ['argument', 'load'] { [airbitcode.IRMemoryBinding{data: output}, airbitcode.IRMemoryBinding{data: output, writable: true}] } else { [airbitcode.IRMemoryBinding{data: output, writable: true}] }
  if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + name), mut bs, 20) { panic('unsupported binary: ' + name) }; unchanged(output); checks++; unsafe { output.free(); bs.free() }
 }
 assert names.len == 771 && checks == 3092
 os.write_file(out + '/result.txt', 'AIR-VECTOR-BINARY-CONTROLS: ${checks} values/flags, poison/undef, division/remainder, overshifts, source/result freezing, discards, old snapshots, result-shape mutations and unsupported profiles PASS\n')!
}

// Control operands keep all widened intermediates within i64.
fn control_expected(op u32, flags u64, bits u32, a u64, b u64) !(bool, u64) {
	modulus := i64(1) << bits; limit := modulus - 1; sign := modulus / 2
	x := i64(a & u64(limit)); y := i64(b & u64(limit))
	sx := if x >= sign { x - modulus } else { x }; sy := if y >= sign { y - modulus } else { y }
	if op in [u32(3), 4, 5, 6]! && (y == 0 || (op in [u32(4), 6]! && sx == -sign && sy == -1)) { return error('invalid division') }
	if op in [u32(7), 8, 9]! && y >= bits { return true, 0 }
	mut value := i64(0); mut signed_value := i64(0); mut poison := false
	match op {
		0 { value = x + y; signed_value = sx + sy }
		1 { value = x - y; signed_value = sx - sy }
		2 { value = x * y; signed_value = sx * sy }
		3 { value = x / y; poison = flags != 0 && value * y != x }
		4 { value = sx / sy; poison = flags != 0 && value * sy != sx }
		5 { value = x % y }
		6 { value = sx % sy }
		7 { value = x * (i64(1) << y); signed_value = sx * (i64(1) << y) }
		8 { value = x / (i64(1) << y); poison = flags != 0 && value * (i64(1) << y) != x }
		9 { value = sx >> y; poison = flags != 0 && value * (i64(1) << y) != sx }
		10 { value = x & y }
		11 { value = x | y; poison = flags != 0 && value != x + y }
		else { value = x ^ y }
	}
	if op in [u32(0), 1, 2, 7]! { poison = (flags & 1 != 0 && (value < 0 || value > limit)) || (flags & 2 != 0 && (signed_value < -sign || signed_value >= sign)) }
	return poison, u64(value) & u64(limit)
}
