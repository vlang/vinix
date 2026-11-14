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
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
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
type NativePromise = fn (voidptr, voidptr, voidptr)
struct Case { name string bits int predicate string }
struct Counts { shapes int defined int poison int scalar int controls int metadata int budgets int }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for byte in bytes { assert byte == 0xcc } }
fn pair(c Case, sample int) (u64, u64) {
 m := mask(c.bits); sign := u64(1) << u32(c.bits - 1)
 edges := [u64(0), 1, m, m - 1, sign, sign - 1, sign + 1, 0x5555555555555555, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]!
 x := if sample < 100 { edges[sample / 10] & m } else { u64(sample) * u64(0x9e3779b97f4a7c15) & m }
 mut y := if sample < 100 { edges[sample % 10] & m } else { (~x ^ (u64(sample) * u64(0x1f123bb5))) & m }
 if sample >= 100 && sample % 2 == 0 { y = if c.predicate == '' { y & ~x } else { (y & ~sign) | (x & sign) } }
 return x, y
}
// No invalid promise is executed natively. The independent oracle compares
// addition with OR, or classifies signs by unsigned ranges.
fn bad(c Case, x u64, y u64) bool {
 if c.predicate == '' { return x + y != x | y }
 sign := u64(1) << u32(c.bits - 1); return (x >= sign) != (y >= sign)
}
fn run_batch(assembler_path string, out string, first int, last int) !Counts {
 assert !os.exists(out); os.mkdir_all(out)!
 mut text := strings.new_builder(2097152); mut cases := []Case{}
 text.write_string('target datalayout = "e-p:64:64"\n')
 for bits in first .. last { for pred in ['', 'eq', 'ne', 'ugt', 'uge', 'ult', 'ule', 'sgt', 'sge', 'slt', 'sle'] {
  c := Case{'case_${cases.len}', bits, pred}; cases << c
  result := if pred == '' { bits } else { 1 }; operation := if pred == '' { 'or disjoint' } else { 'icmp samesign ${pred}' }
  text.write_string('define void @${c.name}(ptr %a, ptr %b, ptr %out) { %x = load i${bits}, ptr %a, align 1\n %y = load i${bits}, ptr %b, align 1\n store i8 17, ptr %out, align 1\n %v = ${operation} i${bits} %x, %y\n %d = getelementptr i8, ptr %out, i64 8\n store i${result} %v, ptr %d, align 1\n ret void }\n')
  text.write_string('define i${result} @scalar_${c.name}(i${bits} %x, i${bits} %y) { %v = ${operation} i${bits} %x, %y\n ret i${result} %v }\ndefine void @void_${c.name}(i${bits} %x, i${bits} %y) { %v = ${operation} i${bits} %x, %y\n ret void }\n')
  for mode in ['poison', 'undef', 'freeze', 'select'] {
   input := if mode == 'undef' { 'undef' } else { 'poison' }; choice := if mode == 'freeze' { '%w = freeze i${result} %v' } else if mode == 'select' { '%w = select i1 false, i${result} %v, i${result} 1' } else { '' }; value := if mode in ['freeze', 'select'] { '%w' } else { '%v' }
   text.write_string('define void @${mode}_${c.name}(ptr %out) { store i8 17, ptr %out, align 1\n %v = ${operation} i${bits} ${input}, 0\n ${choice}\n %d = getelementptr i8, ptr %out, i64 8\n store i${result} ${value}, ptr %d, align 1\n ret void }\n')
  }
 } }
 text.write_string('define void @pointer(ptr %out) { store i8 17, ptr %out, align 1\n %v = icmp eq ptr %out, %out\n ret void }\ndefine void @floating(ptr %out) { store i8 17, ptr %out, align 1\n %v = fcmp oeq float 1.0, 1.0\n ret void }\n')
 for kind in ['branch_or', 'branch_sign', 'frozen_or', 'frozen_sign', 'selected_or', 'selected_sign'] {
  operation := if kind.ends_with('_or') { '%v = or disjoint i8 1, 1\n %condition = icmp ne i8 %v, 0' } else { '%condition = icmp samesign eq i8 0, -1' }
  choice := if kind.starts_with('frozen_') { '%c = freeze i1 %condition' } else if kind.starts_with('selected_') { '%c = select i1 false, i1 %condition, i1 false' } else { '%c = and i1 %condition, true' }
  text.write_string('define void @${kind}(ptr %out) { entry: store i8 17, ptr %out, align 1\n ${operation}\n ${choice}\n br i1 %c, label %yes, label %no\n yes: store i8 1, ptr %out, align 1\n ret void\n no: ret void }\n')
 }
 os.write_file(out + '/input.ll', text.str())!
 mut assembler := os.new_process(assembler_path); assembler.set_args([out + '/input.ll', '-o', out + '/input.bc']); assembler.set_redirect_stdio_merged(); assembler.run(); log := assembler.stdout_slurp(); assembler.wait(); code := assembler.code; assembler.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'bit-sign-promises'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple)
 native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut defined := 0; mut poison := 0; mut scalar := 0; mut controls := 0; mut metadata := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); vf := fi(ir, 'void_' + c.name); result := if c.predicate == '' { c.bits } else { 1 }
  name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 7 && profile.arguments.len == 3 && profile.arguments[0].minimum_size == (c.bits + 7) / 8 && profile.arguments[1].minimum_size == (c.bits + 7) / 8 && profile.arguments[2].minimum_size == 8 + (result + 7) / 8; profile.free()
  mut left := []u8{len: 16, init: 0xcc}; mut right := []u8{len: 16, init: 0xcc}; mut actual := []u8{len: 24, init: 0xcc}; mut expected := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: left, offset: 1}, airbitcode.IRMemoryBinding{data: right, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  for sample in 0 .. 256 {
   x, y := pair(c, sample); invalid := bad(c, x, y)
   for i in 0 .. (c.bits + 7) / 8 { left[1 + i] = u8(x >> u32(i * 8)); right[2 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; expected[i] = 0xcc }
   args := [x | ~mask(c.bits), y | ~mask(c.bits)]
   irun := p.run_integer_function(ir, stream, pools, bodies, sf, args, 2)!; srun := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 2)!
   assert irun.bits == result && irun.poison == invalid && irun.steps == 2 && srun.kind == .integer && srun.bits == irun.bits && srun.poison == invalid && srun.steps == 2
   assert p.run_void_function(ir, stream, pools, bodies, vf, args, 2)!.steps == 2; scalar += 3
   if invalid {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 7) { panic('violated promise stored') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() }
    for i, byte in actual { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } }; poison++
   } else {
    assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 7)!.steps == 7
    unsafe { NativePromise(voidptr(address))(&left[1], &right[2], &expected[3]) }
    mut word := u64(0); for i in 0 .. (result + 7) / 8 { word |= u64(actual[11 + i]) << u32(i * 8) }
    assert irun.value == word && srun.value == word
    for i in 0 .. actual.len { assert actual[i] == if i == 11 + (result + 7) / 8 - 1 && result % 8 != 0 { expected[i] & u8((1 << (result % 8)) - 1) } else { expected[i] }, c.name }; defined++
   }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 6) { panic('short memory budget') }; unchanged(actual)
  if _ := p.run_integer_function(ir, stream, pools, bodies, sf, [u64(0), 0], 1) { panic('short scalar budget') }; budgets += 2
  for selected in [function, sf] { scope := bodies.scopes[selected + 1]; for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if op.flags != 1 { continue }
   for flags in [u64(2), 3, 4, ~u64(0)]! {
    p.instructions[index] = airbitcode.IRTypedInstruction{...op, flags: flags}
    if selected == function { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 7) { panic('memory flag admitted') }; unchanged(actual) } else { if _ := p.run_integer_function(ir, stream, pools, bodies, sf, [u64(0), 0], 2) { panic('integer flag admitted') }; if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0], 2) { panic('scalar flag admitted') } }; metadata++
   }; p.instructions[index] = op
  } }
  for mode in ['poison', 'undef', 'freeze', 'select'] {
   for i in 0 .. actual.len { actual[i] = 0xcc }; mut binding := [airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
   if mode in ['poison', 'undef'] { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, mode + '_' + c.name), mut binding, 5) { panic('indeterminate input accepted') }; for i, byte in actual { assert byte == if i == 3 { u8(17) } else { u8(0xcc) } } } else {
    assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, mode + '_' + c.name), mut binding, 6)!.steps == 6
    for i, byte in actual { assert byte == if i == 3 { u8(17) } else if i >= 11 && i < 11 + (result + 7) / 8 { if i == 11 && mode == 'select' { u8(1) } else { u8(0) } } else { u8(0xcc) } }
   }; controls++; unsafe { binding.free() }
  }
  unsafe { left.free(); right.free(); actual.free(); expected.free(); bs.free() }
 }
 for name in ['pointer', 'floating'] {
  function := fi(ir, name); scope := bodies.scopes[function + 1]; mut output := []u8{len: 8, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count { op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code !in [u64(9), 28]! { continue }; p.instructions[index] = airbitcode.IRTypedInstruction{...op, flags: 1}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 3) { panic('noninteger comparison flag admitted') }; unchanged(output); metadata++; p.instructions[index] = op }
  unsafe { output.free(); bs.free() }
 }
 for kind in ['branch_or', 'branch_sign', 'frozen_or', 'frozen_sign', 'selected_or', 'selected_sign'] {
  mut output := []u8{len: 8, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; function := fi(ir, kind); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; bound := profile.steps; profile.free()
  if kind.starts_with('branch_') { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('poison branch accepted') } else { assert err.msg() == 'AIR memory execution: poison branch condition' } } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == if kind.ends_with('_or') { 6 } else { 5 } }
  assert output[0] == 17; unchanged(output[1..]); controls++; unsafe { output.free(); bs.free() }
 }
 assert cases.len == 176 && defined + poison == cases.len * 256 && scalar == cases.len * 256 * 3 && metadata == cases.len * 8 + 2 && budgets == cases.len * 2 && controls == cases.len * 4 + 6
 return Counts{cases.len, defined, poison, scalar, controls, metadata, budgets}
}
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut defined := 0; mut poison := 0; mut scalar := 0; mut controls := 0; mut metadata := 0; mut budgets := 0
 for batch in 0 .. 4 { n := run_batch(os.args[1], out + '/batch-${batch}', 1 + batch * 16, 17 + batch * 16)!; shapes += n.shapes; defined += n.defined; poison += n.poison; scalar += n.scalar; controls += n.controls; metadata += n.metadata; budgets += n.budgets }
 assert shapes == 704 && defined + poison == 180224 && scalar == 540672 && controls == 2840 && metadata == 5640 && budgets == 1408
 os.write_file(out + '/result.txt', 'AIR-BIT-SIGN-PROMISES: ${shapes} i1-i64 OR-disjoint/ten ICMP-samesign shapes, ${defined} defined native LLVM comparisons, ${poison} poison-store failures preserving earlier writes, ${scalar} integer/mixed/void checks, ${controls} indeterminate/freeze/select/branch, ${metadata} unknown/noninteger flag and ${budgets} budget controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
