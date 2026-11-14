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
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
fn C.LLVMGetNamedFunction(voidptr, &char) voidptr
fn C.LLVMDeleteFunction(voidptr)
fn C.LLVMWriteBitcodeToFile(voidptr, &char) int
type NativeFill = fn (voidptr, voidptr)

struct Case { name string space int bits int length int chained bool }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn main() {
 assert os.args.len == 3 || (os.args.len == 4 && os.args[3] == 'inline')
 inline := os.args.len == 4
 fill := if inline { 'llvm.memset.inline' } else { 'llvm.memset' }
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut source := strings.new_builder(262144); mut cases := []Case{}
 source.write_string('target datalayout = "e-p:64:64"\n')
 for space in 0 .. 3 { for bits in [32, 64] { ptr := if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' }; source.write_string('declare void @llvm.memset.p${space}.i${bits}(${ptr}, i8, i${bits}, i1 immarg)\n') } }
 if inline { for space in 0 .. 3 { for bits in [32, 64] { ptr := if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' }; source.write_string('declare void @llvm.memset.inline.p${space}.i${bits}(${ptr}, i8, i${bits} immarg, i1 immarg)\n') } } }
 // Keep rejected user calls defined so MCJIT need not resolve an external
 // symbol while compiling the module. Rejection guards never execute natively.
 source.write_string('define void @user_memset(ptr %p, i8 %v, i64 %n, i1 %volatile) { ret void }\ndeclare void @llvm.memset.inline.p0.i16(ptr, i8, i16 immarg, i1 immarg)\n')
 for space in 0 .. 2 { for bits in [32, 64] { for length in [0, 1, 2, 3, 7, 8, 15, 16, 31, 64, 257] { for chained in [false, true] { cases << Case{'fill_${cases.len}', space, bits, length, chained} } } } }
 for c in cases {
  ptr := if c.space == 0 { 'ptr' } else { 'ptr addrspace(${c.space})' }; name := '${fill}.p${c.space}.i${c.bits}'
  source.write_string('define void @${c.name}(ptr %src, ${ptr} %out) { entry: %v = load i8, ptr %src, align 1\n store i8 17, ${ptr} %out, align 1\n %a = getelementptr i8, ${ptr} %out, i64 8\n')
  if c.chained {
   source.write_string('%c = trunc i8 %v to i1\n br i1 %c, label %left, label %right\n left: %f = freeze ${ptr} %a\n br label %join\n right: %z = getelementptr i8, ${ptr} %out, i64 8\n br label %join\n join: %p = phi ${ptr} [%f, %left], [%z, %right]\n %byte = phi i8 [%v, %left], [%v, %right]\n %s = select i1 %c, ${ptr} %p, ${ptr} %a\n %casted = bitcast ${ptr} %s to ${ptr}\n')
  }
  dest := if c.chained { '%casted' } else { '%a' }; value := if c.chained { '%byte' } else { '%v' }
  source.write_string('call void @${name}(${ptr} ${dest}, i8 ${value}, i${c.bits} ${c.length}, i1 false)\n call void @${name}(${ptr} ${dest}, i8 poison, i${c.bits} 0, i1 false)\n ret void }\n')
 }
 for space in 0 .. 3 { for bits in [32, 64] { for value in ['17', 'poison', 'undef'] {
  ptr := if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' }
  source.write_string('define void @zero_${space}_${bits}_${value}(ptr %unused, ${ptr} %out) { call void @${fill}.p${space}.i${bits}(${ptr} %out, i8 ${value}, i${bits} 0, i1 false)\n ret void }\n')
 } } }
 for bits in [32, 64] {
  for length in ['poison', 'undef', '-1', '1000000'] { source.write_string('define void @guard_length_${bits}_${length}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memset.p0.i${bits}(ptr %out, i8 0, i${bits} ${length}, i1 false)\n ret void }\n') }
  source.write_string('define void @guard_dynamic_${bits}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %len = load i${bits}, ptr %src, align 1\n call void @llvm.memset.p0.i${bits}(ptr %out, i8 0, i${bits} %len, i1 false)\n ret void }\n')
  for length in [0, 1] { source.write_string('define void @guard_volatile_${bits}_${length}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @${fill}.p0.i${bits}(ptr %out, i8 0, i${bits} ${length}, i1 true)\n ret void }\n') }
  for value in ['null', 'poison', 'undef'] { for length in [0, 1] { source.write_string('define void @guard_pointer_${bits}_${value}_${length}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @${fill}.p0.i${bits}(ptr ${value}, i8 0, i${bits} ${length}, i1 false)\n ret void }\n') } }
  source.write_string('define void @guard_extent_${bits}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %p = getelementptr i8, ptr %out, i64 67108864\n call void @${fill}.p0.i${bits}(ptr %p, i8 0, i${bits} 1, i1 false)\n ret void }\n')
  source.write_string('define void @guard_readonly_${bits}(ptr %src, ptr %out, ptr addrspace(2) %constant) { store i8 17, ptr %out, align 1\n call void @${fill}.p2.i${bits}(ptr addrspace(2) %constant, i8 0, i${bits} 1, i1 false)\n ret void }\n')
 }
 for label, call in {'align': 'call void @llvm.memset.p0.i64(ptr align 8 noundef %out, i8 0, i64 1, i1 false)', 'noundef': 'call void @llvm.memset.p0.i64(ptr %out, i8 noundef 0, i64 1, i1 false)', 'tail': 'tail call void @llvm.memset.p0.i64(ptr %out, i8 0, i64 1, i1 false)', 'user': 'call void @user_memset(ptr %out, i8 0, i64 1, i1 false)', 'inline_width': 'call void @llvm.memset.inline.p0.i16(ptr %out, i8 0, i16 1, i1 false)'} {
  source.write_string('define void @guard_${label}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n ${call}\n ret void }\n')
 }
 for value in ['poison', 'undef'] { for early in [false, true] {
  prior := if early { 'store i8 17, ptr %out, align 1\n' } else { '' }
  source.write_string('define void @condition_${value}_${early}(ptr %out) { ${prior}call void @${fill}.p0.i64(ptr %out, i8 ${value}, i64 16, i1 false)\n ret void }\n')
 } }
 source.write_string('define void @frozen_byte(ptr %out) { %v = freeze i8 poison\n call void @${fill}.p0.i64(ptr %out, i8 %v, i64 16, i1 false)\n ret void }\ndefine void @dead_byte(ptr %out) { entry: br i1 true, label %good, label %cold\n good: store i8 9, ptr %out, align 1\n ret void\n cold: call void @${fill}.p0.i64(ptr %out, i8 poison, i64 16, i1 false)\n ret void }\n')
 source.write_string('define void @cumulative_budget(ptr %out) { store i8 17, ptr %out, align 1\n call void @${fill}.p0.i64(ptr %out, i8 0, i64 500000, i1 false)\n call void @${fill}.p0.i64(ptr %out, i8 0, i64 500000, i1 false)\n ret void }\n')
 source.write_string('define void @maximum_budget(ptr %out) { call void @${fill}.p0.i64(ptr %out, i8 119, i64 999998, i1 false)\n ret void }\n')
 if inline { for reverse in [false, true] {
  first := if reverse { 'llvm.memset' } else { fill }; second := if reverse { fill } else { 'llvm.memset' }
  source.write_string('define void @mixed_${reverse}(ptr %src, ptr %out) { %v = load i8, ptr %src, align 1\n %w = xor i8 %v, -1\n store i8 17, ptr %out, align 1\n %a = getelementptr i8, ptr %out, i64 8\n %b = getelementptr i8, ptr %out, i64 16\n call void @${first}.p0.i64(ptr %a, i8 %v, i64 17, i1 false)\n call void @${second}.p0.i64(ptr %b, i8 %w, i64 9, i1 false)\n ret void }\n')
 } }
 os.write_file(out + '/input.ll', source.str())!
 mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'memset'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 // Retain guards in the interpreter input, but exclude them and huge inline
 // budget bodies from native compilation. All generated IR was verified above.
 for f in ir.functions { if f.name.starts_with('guard_') || f.name.starts_with('condition_') || (inline && f.name in ['maximum_budget', 'cumulative_budget']) {
  name := f.name.clone(); native := C.LLVMGetNamedFunction(module_ptr, name.str); assert native != unsafe { nil }; C.LLVMDeleteFunction(native); unsafe { name.free() }
 } }
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c'')
 native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
 mut comparisons := 0; mut metadata := 0; mut budgets := 0; mut bounds := 0
 mut i8_type := -1; mut i1_type := -1; for i, t in p.types { if t.kind == .integer_t && t.bits == 8 { i8_type = i }; if t.kind == .integer_t && t.bits == 1 { i1_type = i } }; assert i8_type >= 0 && i1_type >= 0
 for c in cases {
  function := fi(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
  bound := c.length + if c.chained { 16 } else { 6 }; cost := c.length + if c.chained { 14 } else { 6 }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == bound && profile.arguments[0].minimum_size == 1 && profile.arguments[0].readable && !profile.arguments[0].writable && profile.arguments[1].minimum_size == u64(8 + c.length) && profile.arguments[1].writable && !profile.arguments[1].readable && profile.arguments[1].alignment == 1; profile.free()
  for sample in 0 .. 256 { for offset in [0, 1, 3] {
   mut src := [u8(sample)]; mut actual := []u8{len: offset + 8 + c.length + 7, init: 0xcc}; mut expected := actual.clone()
   mut bs := [airbitcode.IRMemoryBinding{data: src}, airbitcode.IRMemoryBinding{data: actual, offset: u64(offset), writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost
   unsafe { NativeFill(voidptr(address))(src.data, &expected[offset]) }; assert actual == expected && actual[offset] == 17; for j in 0 .. c.length { assert actual[offset + 8 + j] == u8(sample) }; comparisons++
   unsafe { src.free(); actual.free(); expected.free(); bs.free() }
  }
   mut actual := []u8{len: 8 + c.length + 11, init: 0xcc}; actual[3] = u8(sample); mut expected := actual.clone()
   mut bs := [airbitcode.IRMemoryBinding{data: actual, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
   p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!; unsafe { NativeFill(voidptr(address))(&expected[3], &expected[3]) }; assert actual == expected; comparisons++
   unsafe { actual.free(); expected.free(); bs.free() }
  }
  mut src := [u8(33)]; mut actual := []u8{len: 8 + c.length, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: src}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound - 1) { panic('budget accepted') }; unchanged(actual); budgets++
  for arg in 0 .. 2 { saved := bs[arg]; bs[arg] = airbitcode.IRMemoryBinding{...saved, offset: 1}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('bounds accepted') }; unchanged(actual); bounds++; bs[arg] = saved }
  saved_binding := bs[1]; bs[1] = airbitcode.IRMemoryBinding{...saved_binding, writable: false}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('readonly accepted') }; unchanged(actual); bounds++; bs[1] = saved_binding
  scope := bodies.scopes[function + 1]
  for slot in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   saved := p.instructions[slot]; if stream.records[bodies.instructions[slot].record].code != 34 { continue }
   for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}, airbitcode.IRTypedInstruction{...saved, operands_count: 4}, airbitcode.IRTypedInstruction{...saved, operands_count: 6}, airbitcode.IRTypedInstruction{...saved, result_type: i8_type}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}] {
    p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('metadata accepted') }; unchanged(actual); metadata++
   }; p.instructions[slot] = saved
   for ordinal in 0 .. 5 { operand_slot := saved.operands_start + ordinal; operand := p.operands[operand_slot]
    p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: if ordinal == 2 { i1_type } else { i8_type }}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('operand type accepted') }; unchanged(actual); metadata++; p.operands[operand_slot] = operand
   }
  }
  assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost
  unsafe { src.free(); actual.free(); bs.free() }
 }
 for space in 0 .. 3 { for bits in [32, 64] { for value in ['17', 'poison', 'undef'] {
  name := 'zero_${space}_${bits}_${value}'; function := fi(ir, name); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 2; for a in profile.arguments { assert a.minimum_size == 0 && !a.readable && !a.writable }; profile.free()
  mut empty := []u8{}; mut bs := [airbitcode.IRMemoryBinding{data: empty}, airbitcode.IRMemoryBinding{data: empty}]; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 2)!.steps == 2
  // No attributes make zero length a no-op, even for an indeterminate byte.
  mut native := []u8{len: 8, init: 0xcc}; address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { NativeFill(voidptr(address))(native.data, native.data) }; unchanged(native); comparisons++
  unsafe { empty.free(); bs.free(); native.free() }
 } } }
 if inline { for reverse in [false, true] {
  name := 'mixed_${reverse}'; function := fi(ir, name); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 34 && profile.arguments[0].minimum_size == 1 && profile.arguments[1].minimum_size == 25 && profile.arguments[0].readable && !profile.arguments[1].readable && profile.arguments[1].writable; profile.free()
  for sample in 0 .. 256 {
   mut src := [u8(sample)]; mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: src}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 34)!.steps == 34; unsafe { NativeFill(voidptr(address))(src.data, expected.data) }; assert actual == expected; comparisons++; unsafe { src.free(); actual.free(); expected.free(); bs.free() }
  }
  mut src := [u8(71)]; mut actual := []u8{len: 32, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: src}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 33) { panic('mixed short budget accepted') }; unchanged(actual); budgets++; unsafe { src.free(); actual.free(); bs.free() }
 } }
 // These mutations check indeterminate/runtime lengths without emitting
 // invalid LLVM calls to the explicitly length-immarg inline declarations.
 mut inline_lengths := 0
 if inline { for bits in [32, 64] {
  template_scope := bodies.scopes[fi(ir, 'zero_0_${bits}_17') + 1]; template := p.instructions[template_scope.instructions_start]
  for name in ['guard_length_${bits}_poison', 'guard_length_${bits}_undef', 'guard_length_${bits}_-1', 'guard_length_${bits}_1000000', 'guard_dynamic_${bits}'] {
   function := fi(ir, name); scope := bodies.scopes[function + 1]
   mut input := []u8{len: 32}; mut output := []u8{len: 32, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: output, writable: true}]
   for slot in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
    saved := p.instructions[slot]; if stream.records[bodies.instructions[slot].record].code != 34 { continue }; callee := p.operands[saved.operands_start]
    p.instructions[slot] = airbitcode.IRTypedInstruction{...saved, callee_function: template.callee_function, call_signature: template.call_signature}; p.operands[saved.operands_start] = p.operands[template.operands_start]
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 1000000) { panic('inline length accepted') }
    else { assert err.msg().contains('literal') || err.msg().contains('budget') || (name.starts_with('guard_dynamic_') && err.msg().contains('instruction values are not indexed')), err.msg() }
    unchanged(output); inline_lengths++; p.instructions[slot] = saved; p.operands[saved.operands_start] = callee
   }; unsafe { input.free(); output.free(); bs.free() }
  }
 } }
 assert inline_lengths == (if inline { 10 } else { 0 })
 mut guards := 0
 for i, f in ir.functions { if !f.name.starts_with('guard_') && !f.name.starts_with('condition_') { continue }
  mut bytes := []u8{len: 32, init: 0xcc}; mut bs := if f.name.starts_with('condition_') { [airbitcode.IRMemoryBinding{data: bytes, writable: true}] } else if f.name.starts_with('guard_readonly_') { [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}, airbitcode.IRMemoryBinding{data: bytes}] } else { [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}] }
  if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 1000000) { panic('guard accepted') }
  if f.name.starts_with('condition_') && f.name.ends_with('_true') { assert bytes[0] == 17; for j in 1 .. bytes.len { assert bytes[j] == 0xcc } } else { unchanged(bytes) }; guards++
  unsafe { bytes.free(); bs.free() }
 }
 for name in ['frozen_byte', 'dead_byte'] {
  mut bytes := []u8{len: 16, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
  assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, if name == 'frozen_byte' { 19 } else { 21 })!.steps == if name == 'frozen_byte' { 19 } else { 3 }
  if name == 'frozen_byte' { for b in bytes { assert b == 0 } } else { assert bytes[0] == 9; for j in 1 .. bytes.len { assert bytes[j] == 0xcc } }; unsafe { bytes.free(); bs.free() }
 }
 mut large := []u8{len: 999998, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: large, writable: true}]
 if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'cumulative_budget'), mut bs, 1000000) { panic('cumulative budget accepted') }; unchanged(large); budgets++
 if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'maximum_budget'), mut bs, 999999) { panic('maximum short budget accepted') }; unchanged(large); budgets++
 assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'maximum_budget'), mut bs, 1000000)!.steps == 1000000; for b in large { assert b == 119 }; unsafe { large.free(); bs.free() }
 assert cases.len == 88 && comparisons == (if inline { 90642 } else { 90130 }) && metadata == 3168 && budgets == (if inline { 92 } else { 90 }) && bounds == 264 && guards == 39
 os.write_file(out + '/result.txt', 'AIR-MEMORY-${if inline { 'INLINE-' } else { '' }}MEMSET: ${cases.len} functions and 18 zero bodies, ${comparisons} native LLVM comparisons, all byte values, i32/i64 lengths, spaces 0/1, direct and GEP/PHI/select/freeze/bitcast destinations, aliases, zero poison/undef bytes and readonly empty space 2; ${metadata} metadata, ${budgets} budget, ${bounds} binding, ${guards} rejection/condition and ${inline_lengths} decoded inline-length controls, frozen/dead bytes, exact million-step and cumulative limits PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
