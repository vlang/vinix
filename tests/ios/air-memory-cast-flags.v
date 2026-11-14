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
fn C.LLVMDisposeMessage(&char)
fn C.LLVMVerifyModule(voidptr, int, &&char) int
fn C.LLVMInitializeNativeTarget() int
fn C.LLVMInitializeNativeAsmPrinter() int
fn C.LLVMGetDefaultTargetTriple() &char
fn C.LLVMSetTarget(voidptr, &char)
fn C.LLVMSetDataLayout(voidptr, &char)
fn C.LLVMWriteBitcodeToFile(voidptr, &char) int
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
struct C.LLVMMCJITCompilerOptions {
mut:
 OptLevel u32
 CodeModel int
 NoFramePointerElim int
 EnableFastISel int
 MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeCast = fn (voidptr, voidptr)
struct Case { name string source int dest int flags int }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
// Independent range oracle: signed order is biased into unsigned order. Native
// flagged casts are invoked ONLY for inputs satisfying all promises.
fn invalid(c Case, word u64) bool {
 sign := u64(1) << u32(c.source - 1)
 if c.source < c.dest { return word >= sign }
 radius := u64(1) << u32(c.dest - 1); ordered := word ^ sign
 return (c.flags & 1 != 0 && word > mask(c.dest)) || (c.flags & 2 != 0 && (ordered < sign - radius || ordered > sign + radius - 1))
}
fn sample_word(c Case, sample int) u64 {
 sm := mask(c.source); dm := mask(c.dest); ss := u64(1) << u32(c.source - 1); ds := u64(1) << u32(c.dest - 1)
 return match sample {
  0 { u64(0) } 1 { u64(1) } 2 { sm } 3 { sm - 1 } 4 { ss } 5 { ss - 1 }
  6 { ss + 1 } 7 { dm } 8 { dm + 1 } 9 { dm - 1 } 10 { ds } 11 { ds - 1 }
  12 { (sm - ds) + 1 } 13 { sm - ds } 14 { (sm - ds) + 2 }
  else { u64(sample) * u64(0x9e3779b97f4a7c15) ^ u64(0xfedcba9876543210) }
 } & sm
}
struct Counts { shapes int defined int poison int metadata int budgets int controls int }
// Keep each independently assembled module below the decoder's work limits.
fn run_batch(assembler_path string, out string, first int, last int) !Counts {
 assert !os.exists(out); os.mkdir_all(out)!
 mut source := strings.new_builder(4194304); mut cases := []Case{}
 source.write_string('target datalayout = "e-p:64:64"\n')
 for a in first .. last { for b in 1 .. 65 { if a == b { continue }; for flags in 1 .. if a > b { 4 } else { 2 } {
  c := Case{'cast_${cases.len}', a, b, flags}; cases << c
  op := if a > b { 'trunc' } else { 'zext' }; flag := if a < b { 'nneg' } else if flags == 1 { 'nuw' } else if flags == 2 { 'nsw' } else { 'nuw nsw' }
  source.write_string('define void @${c.name}(ptr %src, ptr %out) { %x = load i${a}, ptr %src, align 1\n store i8 17, ptr %out, align 1\n %v = ${op} ${flag} i${a} %x to i${b}\n %d = getelementptr i8, ptr %out, i64 8\n store i${b} %v, ptr %d, align 1\n ret void }\n')
  source.write_string('define i${b} @scalar_${c.name}(i${a} %x) { %v = ${op} ${flag} i${a} %x to i${b}\n ret i${b} %v }\n')
 } } }
 for mode in ['freeze', 'select', 'chain', 'poison', 'undef'] {
  prefix := if mode == 'poison' { '%v = trunc nuw i16 poison to i8' } else if mode == 'undef' { '%v = zext nneg i8 undef to i16' } else { '%v = trunc nuw nsw i16 128 to i8' }
  result := if mode == 'freeze' { '%w = freeze i8 %v' } else if mode == 'select' { '%w = select i1 false, i8 %v, i8 29' } else if mode == 'chain' { '%w = zext nneg i8 %v to i16' } else { '' }
  typ := if mode in ['chain', 'undef'] { 'i16' } else { 'i8' }; value := if mode in ['freeze', 'select', 'chain'] { '%w' } else { '%v' }
  source.write_string('define void @control_${mode}(ptr %out) { store i8 17, ptr %out, align 1\n ${prefix}\n ${result}\n %d = getelementptr i8, ptr %out, i64 8\n store ${typ} ${value}, ptr %d, align 1\n ret void }\n')
 }
 source.write_string('define void @ignored(i8 %x) { %v = zext nneg i8 %x to i64\n ret void }\n')
 os.write_file(out + '/input.ll', source.str())!
 mut assembler := os.new_process(assembler_path); assembler.set_args([out + '/input.ll', '-o', out + '/input.bc']); assembler.set_redirect_stdio_merged(); assembler.run(); log := assembler.stdout_slurp(); assembler.wait(); code := assembler.code; assembler.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'cast-flags'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 // Let MCJIT choose its host layout. The explicit VM layout and native host
 // agree on the byte GEP and align-1 integer loads/stores used by this fixture.
 C.LLVMSetDataLayout(module_ptr, c'')
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple)
 native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut comparisons := 0; mut poison := 0; mut metadata := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); scalar := fi(ir, 'scalar_' + c.name)
  name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 6 && profile.arguments.len == 2 && profile.arguments[0].minimum_size == (c.source + 7) / 8 && profile.arguments[1].minimum_size == 8 + (c.dest + 7) / 8 && profile.arguments[0].readable && !profile.arguments[0].writable && !profile.arguments[1].readable && profile.arguments[1].writable; profile.free()
  for sample in 0 .. 32 {
   word := sample_word(c, sample); bad := invalid(c, word)
   args := [word]; integer := p.run_integer_function(ir, stream, pools, bodies, scalar, args, 2)!; mixed := p.run_scalar_function(ir, stream, pools, bodies, scalar, args, 2)!
   assert integer.bits == c.dest && integer.steps == 2 && integer.poison == bad && mixed.kind == .integer && mixed.bits == integer.bits && mixed.steps == 2 && mixed.poison == bad
   if !bad { assert integer.value == word & mask(c.dest) && mixed.value == integer.value }
   mut input := []u8{len: 16, init: 0xcc}; mut actual := []u8{len: 24, init: 0xcc}; mut expected := actual.clone()
   for i in 0 .. (c.source + 7) / 8 { input[1 + i] = u8(word >> u32(i * 8)) }
   mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
   if bad {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6) { panic('poison store accepted: ' + c.name) }
    for i, b in actual { assert b == if i == 3 { u8(17) } else { u8(0xcc) } }; poison++
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6)!.steps == 6
    unsafe { NativeCast(voidptr(address))(&input[1], &expected[3]) }
    for i in 0 .. actual.len { assert actual[i] == if i == 11 + (c.dest + 7) / 8 - 1 && c.dest % 8 != 0 { expected[i] & u8((1 << (c.dest % 8)) - 1) } else { expected[i] }, c.name }; comparisons++
   }
   unsafe { input.free(); actual.free(); expected.free(); bindings.free(); args.free() }
  }
  mut guard_input := []u8{len: 16}; mut guard_output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: guard_input}, airbitcode.IRMemoryBinding{data: guard_output, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 5) { panic('short memory budget') }; unchanged(guard_output)
  if _ := p.run_integer_function(ir, stream, pools, bodies, scalar, [u64(0)], 1) { panic('short scalar budget') }; budgets += 2
  for selected in [function, scalar] { scope := bodies.scopes[selected + 1]; for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 4}, airbitcode.IRTypedInstruction{...op, flags: 8}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, result_type: p.operands[op.operands_start].type_index}, airbitcode.IRTypedInstruction{...op, opcode: 2, flags: 1}] {
    p.instructions[index] = changed
    if selected == function { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6) { panic('memory metadata accepted') }; unchanged(guard_output) } else {
     if _ := p.run_integer_function(ir, stream, pools, bodies, scalar, [u64(0)], 2) { panic('integer metadata accepted') }
     if _ := p.run_scalar_function(ir, stream, pools, bodies, scalar, [u64(0)], 2) { panic('mixed metadata accepted') }
    }; metadata++
   }; p.instructions[index] = op
  } }
  unsafe { guard_input.free(); guard_output.free(); bs.free() }
 }
 mut controls := 0
 for mode in ['freeze', 'select', 'chain', 'poison', 'undef'] {
  function := fi(ir, 'control_' + mode); mut bytes := []u8{len: 16, init: 0xcc}; mut binding := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
  if mode in ['freeze', 'select'] { assert p.run_memory_function(ir, stream, pools, bodies, function, mut binding, 6)!.steps == 6; assert bytes[8] == if mode == 'select' { 29 } else { 0 } } else {
   if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut binding, 6) { panic('control accepted') }; assert bytes[8] == 0xcc
  }
  for i, b in bytes { if i == 8 { continue }; assert b == if i == 0 { u8(17) } else { u8(0xcc) } }; controls++
  unsafe { bytes.free(); binding.free() }
 }
 ignored := fi(ir, 'ignored'); for word in [u64(0), 127, 128, 255]! { assert p.run_void_function(ir, stream, pools, bodies, ignored, [word], 2)!.steps == 2; controls++ }
 assert comparisons > 0 && poison > 0 && comparisons + poison == cases.len * 32 && metadata == cases.len * 10 && budgets == cases.len * 2 && controls == 9
 return Counts{cases.len, comparisons, poison, metadata, budgets, controls}
}
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut defined := 0; mut poison := 0; mut metadata := 0; mut budgets := 0; mut controls := 0
 for batch in 0 .. 8 {
  n := run_batch(os.args[1], out + '/batch-${batch}', 1 + batch * 8, 9 + batch * 8)!
  shapes += n.shapes; defined += n.defined; poison += n.poison; metadata += n.metadata; budgets += n.budgets; controls += n.controls
 }
 assert shapes == 8064 && defined + poison == 258048 && metadata == 80640 && budgets == 16128 && controls == 72
 os.write_file(out + '/result.txt', 'AIR-MEMORY-CAST-FLAGS: ${shapes} flagged width/flag shapes across i1-i64 in eight bounded modules, ${defined} defined native LLVM comparisons, ${poison} poison-store failures preserving prior writes, 516096 integer/mixed scalar checks, ${metadata} metadata, ${budgets} budget and ${controls} poison/undef/freeze/select/chain/void controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
