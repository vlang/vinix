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
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
type NativeCompare = fn (voidptr, voidptr, voidptr)

struct Case { name string predicate string space int left int right int direct bool }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn predicate(op string, a int, b int) bool { return match op { 'eq' { a == b } 'ne' { a != b } 'ugt' { a > b } 'uge' { a >= b } 'ult' { a < b } else { a <= b } } }
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut source := strings.new_builder(262144); mut cases := []Case{}
 source.write_string('target datalayout = "e-p:64:64"\ndeclare void @space_types(ptr addrspace(1), ptr addrspace(2))\n')
 for op in ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule'] { for space in 0 .. 3 { for pair in [[0, 0]!, [0, 16]!, [16, 0]!, [16, 16]!, [15, 16]!, [16, 15]!] { for direct in [false, true] {
  cases << Case{'compare_${cases.len}', op, space, pair[0], pair[1], direct}
 } } } }
 for c in cases {
  ptr := if c.space == 0 { 'ptr' } else { 'ptr addrspace(${c.space})' }; a := if c.direct { '%a' } else { '%casted' }
  source.write_string('define void @${c.name}(ptr %cond, ${ptr} %src, ptr %out) { entry: %c = load i1, ptr %cond, align 1\n store i8 17, ptr %out, align 1\n %a = getelementptr i8, ${ptr} %src, i64 ${c.left}\n %b = getelementptr i8, ${ptr} %src, i64 ${c.right}\n br i1 %c, label %left, label %right\n left: %f = freeze ${ptr} %a\n br label %join\n right: %z = getelementptr i8, ${ptr} %a, i64 0\n br label %join\n join: %tag = phi i8 [3, %left], [5, %right]\n %p = phi ${ptr} [%f, %left], [%z, %right]\n %selected = select i1 %c, ${ptr} %p, ${ptr} %a\n %casted = bitcast ${ptr} %selected to ${ptr}\n %cmp = icmp ${c.predicate} ${ptr} ${a}, %b\n %rev = icmp ${c.predicate} ${ptr} %b, ${a}\n %eq = icmp eq ${ptr} ${a}, ${a}\n %dst = select i1 %eq, ptr %out, ptr %out\n %d1 = getelementptr i8, ptr %dst, i64 1\n %d2 = getelementptr i8, ptr %dst, i64 2\n %d3 = getelementptr i8, ptr %dst, i64 3\n %d4 = getelementptr i8, ptr %dst, i64 4\n store i1 %cmp, ptr %d1, align 1\n store i1 %rev, ptr %d2, align 1\n %value = select i1 %cmp, i8 71, i8 93\n store i8 %value, ptr %d3, align 1\n br i1 %rev, label %yes, label %no\n yes: store i8 %tag, ptr %d4, align 1\n ret void\n no: store i8 9, ptr %d4, align 1\n ret void }\n')
 }
 for op in ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule'] { for space in 0 .. 3 {
  ptr := if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' }
  source.write_string('define void @direct_${op}_${space}(ptr %cond, ${ptr} %src, ptr %out) { store i8 17, ptr %out, align 1\n %cmp = icmp ${op} ${ptr} %src, %src\n %d = getelementptr i8, ptr %out, i64 1\n store i1 %cmp, ptr %d, align 1\n ret void }\n')
 } }
 for op in ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule'] {
  source.write_string('define void @guard_cross_${op}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %c = icmp ${op} ptr %src, %out\n ret void }\n')
  for state in ['null', 'poison', 'undef'] { for reverse in [false, true] {
   a := if reverse { state } else { '%src' }; b := if reverse { '%src' } else { state }
   source.write_string('define void @guard_${op}_${state}_${reverse}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %c = icmp ${op} ptr ${a}, ${b}\n ret void }\n')
  } }
 }
 for op in ['sgt', 'sge', 'slt', 'sle'] { source.write_string('define void @guard_${op}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %c = icmp ${op} ptr %src, %src\n ret void }\n') }
 for state in ['poison', 'undef'] { for early in [false, true] { for used in [false, true] {
  prior := if early { 'store i8 17, ptr %out, align 1\n' } else { '' }; later := if used { '%v = select i1 %cmp, i8 7, i8 9\n store i8 %v, ptr %out, align 1\n' } else { '' }
  source.write_string('define void @condition_${state}_${early}_${used}(ptr %out) { ${prior}%p = select i1 ${state}, ptr %out, ptr %out\n %f = freeze ptr %p\n %cmp = icmp eq ptr %f, %out\n ${later}ret void }\n')
 } } }
 source.write_string('define void @frozen_condition(ptr %out) { %c = freeze i1 poison\n %p = select i1 %c, ptr %out, ptr %out\n %cmp = icmp eq ptr %p, %out\n store i1 %cmp, ptr %out, align 1\n ret void }\ndefine void @dead_condition(ptr %out) { entry: br i1 true, label %good, label %cold\n good: store i8 9, ptr %out, align 1\n ret void\n cold: %p = select i1 poison, ptr %out, ptr %out\n %cmp = icmp eq ptr %p, %out\n ret void }\n')
 os.write_file(out + '/input.ll', source.str())!
 mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'pointer-compare'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c'')
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
 mut comparisons := 0; mut metadata := 0; mut budgets := 0; mut bounds := 0
 mut i8_type := -1; mut space_type := -1; for i, t in p.types { if t.kind == .integer_t && t.bits == 8 { i8_type = i }; if t.kind == .pointer_t && t.address_space == 1 { space_type = i } }; assert i8_type >= 0 && space_type >= 0
 for c in cases {
  function := fi(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 30 && profile.arguments[0].minimum_size == 1 && profile.arguments[1].minimum_size == u64(if c.left > c.right { c.left } else { c.right }) && profile.arguments[2].minimum_size == 5
  assert !profile.arguments[1].readable && !profile.arguments[1].writable && profile.arguments[1].alignment == 1; profile.free()
  for offset in [0, 1, 3, 7] { for choice in 0 .. 2 {
   mut cond := [u8(choice)]; mut input := []u8{len: offset + 16, init: 0xcc}; mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
   mut bs := [airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: input, offset: u64(offset)}, airbitcode.IRMemoryBinding{data: actual, offset: 5, writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30)!.steps == 26
   unsafe { NativeCompare(voidptr(address))(cond.data, &input[offset], &expected[5]) }
   expected[6] &= 1; expected[7] &= 1; assert actual == expected
   forward := predicate(c.predicate, c.left, c.right); reverse := predicate(c.predicate, c.right, c.left)
   assert actual[5] == 17 && actual[6] == u8(forward) && actual[7] == u8(reverse) && actual[8] == if forward { u8(71) } else { u8(93) }; assert actual[9] == if reverse { if choice == 1 { u8(3) } else { u8(5) } } else { u8(9) }; comparisons++
   unsafe { cond.free(); input.free(); actual.free(); expected.free(); bs.free() }
  } }
  for choice in 0 .. 2 {
   mut cond := [u8(choice)]; mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
   mut bs := [airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: actual, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
   p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30)!; unsafe { NativeCompare(voidptr(address))(cond.data, &expected[3], &expected[3]) }; expected[4] &= 1; expected[5] &= 1; assert actual == expected; comparisons++
   unsafe { cond.free(); actual.free(); expected.free(); bs.free() }
  }
  mut cond := [u8(1)]; mut input := []u8{len: 16}; mut actual := []u8{len: 5, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 29) { panic('budget accepted') }; unchanged(actual); budgets++
  for arg, offset in [u64(1), 17, 1] { saved := bs[arg]; bs[arg] = airbitcode.IRMemoryBinding{...saved, offset: offset}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30) { panic('binding accepted') }; unchanged(actual); bounds++; bs[arg] = saved }
  saved_binding := bs[2]; bs[2] = airbitcode.IRMemoryBinding{...saved_binding, writable: false}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30) { panic('readonly accepted') }; unchanged(actual); bounds++; bs[2] = saved_binding
  scope := bodies.scopes[function + 1]
  for slot in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   saved := p.instructions[slot]; if stream.records[bodies.instructions[slot].record].code !in [u64(9), 28] { continue }
   for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, result_type: i8_type}, airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, operands_count: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 3}, airbitcode.IRTypedInstruction{...saved, opcode: 0}, airbitcode.IRTypedInstruction{...saved, opcode: 38}, airbitcode.IRTypedInstruction{...saved, opcode: 39}, airbitcode.IRTypedInstruction{...saved, opcode: 40}, airbitcode.IRTypedInstruction{...saved, opcode: 41}, airbitcode.IRTypedInstruction{...saved, opcode: 42}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}] {
    p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30) { panic('metadata accepted') }; unchanged(actual); metadata++
   }; p.instructions[slot] = saved
   for operand_slot in saved.operands_start .. saved.operands_start + 2 {
    operand := p.operands[operand_slot]
    for typ in [i8_type, if c.space == 1 { bs_type(p, 2) } else { space_type }] {
     p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: typ}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30) { panic('operand type accepted') }; unchanged(actual); metadata++
    }; p.operands[operand_slot] = operand
   }
  }
  p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 30)!; assert actual[0] == 17
  unsafe { cond.free(); input.free(); actual.free(); bs.free() }
 }
 for op in ['eq', 'ne', 'ugt', 'uge', 'ult', 'ule'] { for space in 0 .. 3 {
  name := 'direct_${op}_${space}'; function := fi(ir, name); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 5 && profile.arguments[0].minimum_size == 0 && profile.arguments[1].minimum_size == 0 && !profile.arguments[1].readable && !profile.arguments[1].writable && profile.arguments[2].minimum_size == 2; profile.free()
  mut empty := []u8{}; mut actual := []u8{len: 2, init: 0xcc}; mut expected := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: empty}, airbitcode.IRMemoryBinding{data: empty}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 4) { panic('direct budget accepted') }; unchanged(actual); budgets++
  assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 5)!.steps == 5; unsafe { NativeCompare(voidptr(address))(expected.data, expected.data, expected.data) }; expected[1] &= 1; assert actual == expected && actual[0] == 17 && actual[1] == u8(predicate(op, 0, 0)); comparisons++
  unsafe { empty.free(); actual.free(); expected.free(); bs.free() }
 } }
 mut guards := 0
 for i, f in ir.functions { if !f.name.starts_with('guard_') && !f.name.starts_with('condition_') { continue }
  mut bytes := []u8{len: 16, init: 0xcc}; mut bs := if f.name.starts_with('guard_') { [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}] } else { [airbitcode.IRMemoryBinding{data: bytes, writable: true}] }
  if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 32) { panic('guard accepted') }
  if f.name.starts_with('condition_') && f.name.contains('_true_') { assert bytes[0] == 17; for j in 1 .. bytes.len { assert bytes[j] == 0xcc } } else { unchanged(bytes) }; guards++
  unsafe { bytes.free(); bs.free() }
 }
 for name in ['frozen_condition', 'dead_condition'] {
  mut bytes := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
  result := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, if name == 'frozen_condition' { 5 } else { 6 })!
  assert result.steps == if name == 'frozen_condition' { 5 } else { 3 }; assert bytes[0] == if name == 'frozen_condition' { u8(1) } else { u8(9) }; for j in 1 .. bytes.len { assert bytes[j] == 0xcc }; unsafe { bytes.free(); bs.free() }
 }
 assert cases.len == 216 && comparisons == 2178 && metadata == 11664 && budgets == 234 && bounds == 864 && guards == 54
 os.write_file(out + '/result.txt', 'AIR-MEMORY-POINTER-COMPARE: ${cases.len} chained and 18 direct functions, ${comparisons} native LLVM comparisons, six predicates, PHI/select/freeze/bitcast/GEP, scalar/branch/pointer-select consumers, spaces 0/1/2, one-past offsets, empty direct bindings, no source reads, aliasing; ${metadata} metadata, ${budgets} budget, ${bounds} binding and ${guards} rejection/condition controls, frozen/dead conditions PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
fn bs_type(p airbitcode.IRTypedProgram, space u32) int { for i, t in p.types { if t.kind == .pointer_t && t.address_space == space { return i } }; panic('pointer type') }
