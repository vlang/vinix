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
type NativeCopy = fn (voidptr, voidptr, voidptr)

struct Case { name string typ string bits int order int direct bool switching bool }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn equal(a []u8, b []u8, pos int, bits int) {
 for i in 0 .. a.len { if i == pos + (bits + 7) / 8 - 1 && bits % 8 != 0 { assert a[i] == b[i] & u8((1 << (bits % 8)) - 1) } else { assert a[i] == b[i] } }
}
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut source := strings.new_builder(1048576); mut cases := []Case{}
 source.write_string('target datalayout = "e-p:64:64-i24:32-i64:64"\n')
 for i in 1 .. 67 {
  bits := if i <= 64 { i } else if i == 65 { 16 } else { 32 }; typ := if i <= 64 { 'i${i}' } else if i == 65 { 'half' } else { 'float' }
  for order in 0 .. 3 { for direct in [false, true] { for switching in [false, true] { cases << Case{'copy_${cases.len}', typ, bits, order, direct, switching} } } }
 }
 for c in cases {
  stride := if c.bits <= 8 { 1 } else if c.bits <= 16 { 2 } else if c.bits <= 32 { 4 } else { 8 }
  transfer := if c.switching { 'switch i8 %c, label %third [i8 0, label %left i8 1, label %right]' } else { '%bit = trunc i8 %c to i1\n br i1 %bit, label %left, label %right' }
  source.write_string('define void @${c.name}(ptr %cond, ptr %src, ptr %out) { entry: %c = load i8, ptr %cond, align 1\n store i8 17, ptr %out, align 1\n %a = getelementptr i8, ptr %src, i64 8\n %b = getelementptr i8, ptr %out, i64 8\n ${transfer}\n left: %l = getelementptr [8 x i8], ptr %a, i64 1\n %dl = getelementptr i8, ptr %b, i64 8\n br label %join\n right: %r = getelementptr i8, ptr %src, i64 16\n %dr = getelementptr i8, ptr %out, i64 16\n br label %join\n')
  if c.switching { source.write_string('third: %t = getelementptr i8, ptr %a, i64 8\n %dt = getelementptr i8, ptr %b, i64 8\n br label %join\n') }
  source.write_string('join:\n')
  for item in if c.order == 0 { ['p', 'tag', 'q', 'tail'] } else if c.order == 1 { ['tag', 'p', 'tail', 'q'] } else { ['tag', 'tail', 'p', 'q'] } {
   pointer := item in ['p', 'q']; typ := if pointer { 'ptr' } else { 'i8' }
   l := if item == 'p' { if c.direct { '%src' } else { '%l' } } else if item == 'q' { if c.direct { '%out' } else { '%dl' } } else if item == 'tag' { '3' } else { '13' }
   r := if item == 'p' { if c.direct { '%src' } else { '%r' } } else if item == 'q' { if c.direct { '%out' } else { '%dr' } } else if item == 'tag' { '5' } else { '15' }
   t := if item == 'p' { if c.direct { '%src' } else { '%t' } } else if item == 'q' { if c.direct { '%out' } else { '%dt' } } else if item == 'tag' { '7' } else { '17' }
   source.write_string('%${item} = phi ${typ} [${l}, %left], [${r}, %right]' + if c.switching { ', [${t}, %third]\n' } else { '\n' })
  }
  path := if c.direct { 'i8' } else { c.typ }; index := if c.direct { 16 - stride } else { -1 }
  source.write_string('%b2 = trunc i8 %c to i1\n %pa = getelementptr i8, ptr %p, i64 0\n %qa = getelementptr i8, ptr %q, i64 0\n %px = select i1 %b2, ptr %p, ptr %pa\n %qx = select i1 %b2, ptr %qa, ptr %q\n %pz = select i1 %b2, ptr %px, ptr %pa\n')
  source.write_string('%ps = getelementptr ${path}, ptr %pz, i64 ${index}\n %qs = getelementptr ${path}, ptr %qx, i64 ${index}\n %v = load ${c.typ}, ptr %ps, align 1\n store ${c.typ} %v, ptr %qs, align 1\n %tagp = getelementptr i8, ptr %out, i64 32\n store i8 %tag, ptr %tagp, align 1\n %tailp = getelementptr i8, ptr %out, i64 33\n store i8 %tail, ptr %tailp, align 1\n ret void }\n')
 }
 for name, value in {'null': 'null', 'poison': 'poison', 'undef': 'undef', 'binding': '%src', 'offset': '%off'} {
  source.write_string('define void @guard_${name}(ptr %src, ptr %out) { entry: store i8 17, ptr %out, align 1\n %off = getelementptr i8, ptr %out, i64 1\n %p = select i1 true, ptr %out, ptr ${value}\n ret void }\n')
 }
 for state in ['poison', 'undef'] { for early in [false, true] { for used in [false, true] {
  prior := if early { 'store i8 17, ptr %out, align 1\n' } else { '' }; later := if used { 'store i8 7, ptr %p, align 1\n' } else { '' }
  source.write_string('define void @condition_${state}_${early}_${used}(ptr %out) { ${prior}%p = select i1 ${state}, ptr %out, ptr %out\n ${later}ret void }\n')
 } } }
 source.write_string('define void @frozen_condition(ptr %out) { %c = freeze i1 poison\n %p = select i1 %c, ptr %out, ptr %out\n store i8 7, ptr %p, align 1\n ret void }\ndefine void @dead_condition(ptr %out) { entry: br i1 true, label %good, label %cold\n good: store i8 9, ptr %out, align 1\n ret void\n cold: %p = select i1 poison, ptr %out, ptr %out\n ret void }\n')
 source.write_string('define void @nested(ptr %cond, ptr %src, ptr %out) { entry: %c = load i1, ptr %cond, align 1\n br i1 %c, label %left, label %right\n left: %l = getelementptr i8, ptr %src, i64 16\n br label %join\n right: %r = getelementptr i8, ptr %src, i64 16\n br label %join\n join: %p = phi ptr [%l, %left], [%r, %right]\n %z = getelementptr i8, ptr %p, i64 0\n %selected = select i1 %c, ptr %p, ptr %z\n br i1 %c, label %a, label %b\n a: br label %end\n b: br label %end\n end: %q = phi ptr [%selected, %a], [%z, %b]\n %same = select i1 %c, ptr %q, ptr %q\n %v = load i32, ptr %same, align 1\n store i32 %v, ptr %out, align 1\n ret void }\n')
 os.write_file(out + '/input.ll', source.str())!
 mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'pointer-phi'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c'')
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
 mut comparisons := 0; mut metadata := 0; mut budgets := 0; mut bounds := 0
 mut i8_type := -1; for i, t in p.types { if t.kind == .integer_t && t.bits == 8 { i8_type = i } }; assert i8_type >= 0
 for c in cases {
  function := fi(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
  bound := if c.switching { 35 } else { 31 }; stride := if c.bits <= 8 { 1 } else if c.bits <= 16 { 2 } else if c.bits <= 32 { 4 } else { 8 }; width := (c.bits + 7) / 8
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == bound && profile.arguments[0].minimum_size == 1 && profile.arguments[1].minimum_size == 16 && profile.arguments[2].minimum_size == 34; profile.free()
  mut cond := [u8(0), 0]; mut input := []u8{len: 64}; mut actual := []u8{len: 64, init: 0xcc}; mut expected := actual.clone()
  mut bindings := [airbitcode.IRMemoryBinding{data: cond, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 5, writable: true}]
  for sample in 0 .. 16 { for choice in 0 .. 4 {
   cond[1] = u8(choice)
   mut state := u64(sample + 1) * u64(0x9e3779b97f4a7c15)
   for j in 0 .. 64 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; input[j] = u8(state >> 56); actual[j] = 0xcc; expected[j] = 0xcc }
   if c.bits % 8 != 0 { input[3 + 16 - stride + width - 1] &= u8((1 << (c.bits % 8)) - 1) }
   cost := if c.switching { 27 + if choice == 0 { 1 } else { 2 } } else { 28 }
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound)!.steps == cost
   unsafe { NativeCopy(voidptr(address))(&cond[1], &input[3], &expected[5]) }; equal(actual, expected, 5 + 16 - stride, c.bits)
   tag := if c.switching { if choice == 0 { u8(3) } else if choice == 1 { u8(5) } else { u8(7) } } else { if choice & 1 != 0 { u8(3) } else { u8(5) } }
   assert actual[37] == tag && actual[38] == tag + 10; comparisons++
  } }
  for choice in 0 .. 4 {
   cond[1] = u8(choice); mut alias := input.clone(); mut reference := alias.clone(); mut bs := [airbitcode.IRMemoryBinding{data: cond, offset: 1}, airbitcode.IRMemoryBinding{data: alias, offset: 3}, airbitcode.IRMemoryBinding{data: alias, offset: 5, writable: true}]
   p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!; unsafe { NativeCopy(voidptr(address))(&cond[1], &reference[3], &reference[5]) }; equal(alias, reference, 5 + 16 - stride, c.bits); comparisons++
   unsafe { alias.free(); reference.free(); bs.free() }
  }
  for j in 0 .. 64 { actual[j] = 0xcc }
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound - 1) { panic('budget accepted') }; unchanged(actual); budgets++
  for arg, offset in [u64(2), 49, 31] { saved := bindings[arg]; bindings[arg] = airbitcode.IRMemoryBinding{...saved, offset: offset}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('bounds accepted') }; unchanged(actual); bounds++; bindings[arg] = saved }
  saved_binding := bindings[2]; bindings[2] = airbitcode.IRMemoryBinding{...saved_binding, writable: false}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('readonly accepted') }; unchanged(actual); bounds++; bindings[2] = saved_binding
  scope := bodies.scopes[function + 1]
  for slot in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   saved := p.instructions[slot]; if stream.records[bodies.instructions[slot].record].code !in [u64(5), 29] || p.types[saved.result_type].kind != .pointer_t { continue }
   for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, result_type: -1}, airbitcode.IRTypedInstruction{...saved, result_type: i8_type}, airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}] { p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('metadata accepted') }; unchanged(actual); metadata++ }; p.instructions[slot] = saved
   operand := p.operands[saved.operands_start]; p.operands[saved.operands_start] = airbitcode.IRTypedOperand{...operand, type_index: i8_type}
   if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('pointer operand type accepted') }; unchanged(actual); metadata++; p.operands[saved.operands_start] = operand
   condition := p.operands[saved.operands_start + 2]; p.operands[saved.operands_start + 2] = airbitcode.IRTypedOperand{...condition, type_index: i8_type}
   if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('condition type accepted') }; unchanged(actual); metadata++; p.operands[saved.operands_start + 2] = condition
  }
  for j in 0 .. 64 { expected[j] = 0xcc }; p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound)!; unsafe { NativeCopy(voidptr(address))(&cond[1], &input[3], &expected[5]) }; equal(actual, expected, 5 + 16 - stride, c.bits); comparisons++
  unsafe { cond.free(); input.free(); actual.free(); expected.free(); bindings.free() }
 }
 mut guards := 0
 for i, f in ir.functions { if !f.name.starts_with('guard_') && !f.name.starts_with('condition_') { continue }
  mut bytes := []u8{len: 64, init: 0xcc}; mut bs := if f.name.starts_with('guard_') { [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}] } else { [airbitcode.IRMemoryBinding{data: bytes, writable: true}] }
  if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 32) { panic('guard accepted') }
  if f.name.starts_with('condition_') && f.name.contains('_true_') { assert bytes[0] == 17; for j in 1 .. bytes.len { assert bytes[j] == 0xcc } } else { unchanged(bytes) }; guards++
  unsafe { bytes.free(); bs.free() }
 }
 nested := fi(ir, 'nested'); address := C.LLVMGetFunctionAddress(engine, c'nested'); assert address != 0; profile := p.memory_function_profile(ir, stream, pools, bodies, nested)!; assert profile.steps == 17; profile.free()
 for sample in 0 .. 32 { for choice in 0 .. 2 {
  mut cond := [u8(choice)]; mut src := []u8{len: 32, init: u8(sample)}; mut dst := []u8{len: 4}; mut expected := dst.clone(); mut bs := [airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: src}, airbitcode.IRMemoryBinding{data: dst, writable: true}]
  assert p.run_memory_function(ir, stream, pools, bodies, nested, mut bs, 17)!.steps == 14; unsafe { NativeCopy(voidptr(address))(cond.data, src.data, expected.data) }; assert dst == expected; comparisons++
  unsafe { cond.free(); src.free(); dst.free(); expected.free(); bs.free() }
 } }
 for name in ['frozen_condition', 'dead_condition'] {
  mut bytes := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
  result := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, if name == 'frozen_condition' { 4 } else { 5 })!
  assert result.steps == if name == 'frozen_condition' { 4 } else { 3 }; assert bytes[0] == if name == 'frozen_condition' { u8(7) } else { u8(9) }
  for j in 1 .. bytes.len { assert bytes[j] == 0xcc }; unsafe { bytes.free(); bs.free() }
 }
 assert cases.len == 792 && comparisons == 54712 && metadata == 21384 && budgets == 792 && bounds == 3168 && guards == 13
 os.write_file(out + '/result.txt', 'AIR-MEMORY-POINTER-SELECT: ${cases.len} functions, ${comparisons} native LLVM comparisons, branch/switch/nested joins, select/GEP/PHI chains in three mixed PHI orders, direct/GEP-equivalent pointers, i1-i64/half/float, aliasing; ${metadata} metadata, ${budgets} budget, ${bounds} binding and ${guards} rejection/condition controls, frozen and dead conditions PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
