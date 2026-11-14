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
type NativeMove = fn (voidptr, voidptr)

struct Case { name string dest int source int bits int length int chained bool }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn ptr(space int) string { return if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' } }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn pattern(mut bytes []u8, sample int) { mut state := u64(sample + 1) * u64(0x9e3779b97f4a7c15); for i in 0 .. bytes.len { state ^= state << 13; state ^= state >> 7; state ^= state << 17; bytes[i] = u8(state >> 56) } }
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut source := strings.new_builder(524288); mut cases := []Case{}
 source.write_string('target datalayout = "e-p:64:64"\n')
 for d in 0 .. 3 { for s in 0 .. 3 { for bits in [32, 64] { source.write_string('declare void @llvm.memmove.p${d}.p${s}.i${bits}(${ptr(d)}, ${ptr(s)}, i${bits}, i1 immarg)\n') } } }
 source.write_string('declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)\ndeclare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)\ndeclare void @llvm.memcpy.inline.p0.p0.i64(ptr, ptr, i64 immarg, i1 immarg)\ndeclare void @llvm.memmove.element.unordered.atomic.p0.p0.i64(ptr, ptr, i64, i32 immarg)\ndefine void @user_move(ptr %d, ptr %s, i64 %n, i1 %v) { ret void }\n')
 for d in 0 .. 2 { for s in 0 .. 3 { for bits in [32, 64] { for length in [0, 1, 2, 7, 8, 15, 16, 31, 64, 257] { for chained in [false, true] { cases << Case{'move_${cases.len}', d, s, bits, length, chained} } } } } }
 for c in cases {
  dp := ptr(c.dest); sp := ptr(c.source); name := 'llvm.memmove.p${c.dest}.p${c.source}.i${c.bits}'
  source.write_string('define void @${c.name}(${sp} %src, ${dp} %out) { entry: %byte = load i8, ${sp} %src, align 1\n store i8 17, ${dp} %out, align 1\n %a = getelementptr i8, ${sp} %src, i64 16\n %b = getelementptr i8, ${dp} %out, i64 8\n')
  if c.chained { source.write_string('%c = trunc i8 %byte to i1\n br i1 %c, label %left, label %right\n left: %af = freeze ${sp} %a\n %bf = freeze ${dp} %b\n br label %join\n right: %az = getelementptr i8, ${sp} %a, i64 0\n %bz = getelementptr i8, ${dp} %b, i64 0\n br label %join\n join: %ap = phi ${sp} [%af, %left], [%az, %right]\n %bp = phi ${dp} [%bf, %left], [%bz, %right]\n %as = select i1 %c, ${sp} %ap, ${sp} %a\n %bs = select i1 %c, ${dp} %b, ${dp} %bp\n %ac = bitcast ${sp} %as to ${sp}\n %bc = bitcast ${dp} %bs to ${dp}\n') }
  a := if c.chained { '%ac' } else { '%a' }; b := if c.chained { '%bc' } else { '%b' }
  source.write_string('call void @${name}(${dp} ${b}, ${sp} ${a}, i${c.bits} ${c.length}, i1 false)\n call void @${name}(${dp} ${b}, ${sp} ${a}, i${c.bits} 0, i1 false)\n ret void }\n')
 }
 for d in 0 .. 3 { for s in 0 .. 3 { for bits in [32, 64] { source.write_string('define void @zero_${d}_${s}_${bits}(${ptr(s)} %src, ${ptr(d)} %out) { call void @llvm.memmove.p${d}.p${s}.i${bits}(${ptr(d)} %out, ${ptr(s)} %src, i${bits} 0, i1 false)\n ret void }\n') } } }
 for bits in [32, 64] {
  for length in ['poison', 'undef', '-1', '500000', '1000000'] { source.write_string('define void @guard_length_${bits}_${length}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memmove.p0.p0.i${bits}(ptr %out, ptr %src, i${bits} ${length}, i1 false)\n ret void }\n') }
  source.write_string('define void @guard_dynamic_${bits}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %n = load i${bits}, ptr %src, align 1\n call void @llvm.memmove.p0.p0.i${bits}(ptr %out, ptr %src, i${bits} %n, i1 false)\n ret void }\n')
  for length in [0, 1] { source.write_string('define void @guard_volatile_${bits}_${length}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memmove.p0.p0.i${bits}(ptr %out, ptr %src, i${bits} ${length}, i1 true)\n ret void }\n') }
  for side in ['source', 'dest'] { for state in ['null', 'poison', 'undef'] { for length in [0, 1] {
   a := if side == 'source' { state } else { '%src' }; b := if side == 'dest' { state } else { '%out' }
   source.write_string('define void @guard_pointer_${bits}_${side}_${state}_${length}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memmove.p0.p0.i${bits}(ptr ${b}, ptr ${a}, i${bits} ${length}, i1 false)\n ret void }\n')
  } } }
  for side in ['source', 'dest'] { a := if side == 'source' { '%p' } else { '%src' }; b := if side == 'dest' { '%p' } else { '%out' }
   source.write_string('define void @guard_extent_${bits}_${side}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %p = getelementptr i8, ptr %out, i64 67108864\n call void @llvm.memmove.p0.p0.i${bits}(ptr ${b}, ptr ${a}, i${bits} 1, i1 false)\n ret void }\n')
  }
  source.write_string('define void @guard_readonly_${bits}(ptr %src, ptr %out, ptr addrspace(2) %constant) { store i8 17, ptr %out, align 1\n call void @llvm.memmove.p2.p0.i${bits}(ptr addrspace(2) %constant, ptr %src, i${bits} 1, i1 false)\n ret void }\n')
 }
 for label, call in {'dest_align': 'call void @llvm.memmove.p0.p0.i64(ptr align 8 %out, ptr %src, i64 1, i1 false)', 'source_align': 'call void @llvm.memmove.p0.p0.i64(ptr %out, ptr align 8 %src, i64 1, i1 false)', 'source_noundef': 'call void @llvm.memmove.p0.p0.i64(ptr %out, ptr noundef %src, i64 1, i1 false)', 'tail': 'tail call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %src, i64 1, i1 false)', 'user': 'call void @user_move(ptr %out, ptr %src, i64 1, i1 false)', 'copy': 'call void @llvm.memcpy.p0.p0.i64(ptr %out, ptr %src, i64 1, i1 false)', 'inline': 'call void @llvm.memcpy.inline.p0.p0.i64(ptr %out, ptr %src, i64 1, i1 false)', 'atomic': 'call void @llvm.memmove.element.unordered.atomic.p0.p0.i64(ptr align 1 %out, ptr align 1 %src, i64 1, i32 1)'} { source.write_string('define void @guard_${label}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n ${call}\n ret void }\n') }
 for state in ['poison', 'undef'] { for early in [false, true] { for side in ['source', 'dest'] { for length in [0, 1] {
  prior := if early { 'store i8 17, ptr %out, align 1\n' } else { '' }; selected := if side == 'source' { '%src' } else { '%out' }; a := if side == 'source' { '%p' } else { '%src' }; b := if side == 'dest' { '%p' } else { '%out' }
  source.write_string('define void @condition_${state}_${side}_${length}_${early}(ptr %src, ptr %out) { ${prior}%p = select i1 ${state}, ptr ${selected}, ptr ${selected}\n call void @llvm.memmove.p0.p0.i64(ptr ${b}, ptr ${a}, i64 ${length}, i1 false)\n ret void }\n')
 } } } }
 source.write_string('define void @frozen_condition(ptr %src, ptr %out) { %c = freeze i1 poison\n %p = select i1 %c, ptr %src, ptr %src\n call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %p, i64 17, i1 false)\n ret void }\ndefine void @dead_condition(ptr %src, ptr %out) { entry: br i1 true, label %good, label %cold\n good: store i8 9, ptr %out, align 1\n ret void\n cold: %p = select i1 poison, ptr %src, ptr %src\n call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %p, i64 1, i1 false)\n ret void }\n')
 source.write_string('define void @sequence(ptr %src, ptr %out) { %a = getelementptr i8, ptr %src, i64 16\n %b = getelementptr i8, ptr %out, i64 8\n call void @llvm.memmove.p0.p0.i64(ptr %b, ptr %a, i64 17, i1 false)\n %c = getelementptr i8, ptr %b, i64 1\n call void @llvm.memmove.p0.p0.i64(ptr %c, ptr %b, i64 9, i1 false)\n ret void }\n')
 source.write_string('define void @maximum_budget(ptr %src, ptr %out) { call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %src, i64 499999, i1 false)\n ret void }\ndefine void @cumulative_budget(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %src, i64 250000, i1 false)\n call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %src, i64 250000, i1 false)\n ret void }\ndefine void @mixed_budget(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memset.p0.i64(ptr %out, i8 0, i64 1, i1 false)\n call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %src, i64 499998, i1 false)\n ret void }\n')
 os.write_file(out + '/input.ll', source.str())!
 mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'memmove'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 // Rejection-only bodies stay in the interpreter input. Exclude them from
 // native compilation, where atomic guards may need unavailable helpers.
 for f in ir.functions { if f.name.starts_with('guard_') || f.name.starts_with('condition_') {
  name := f.name.clone(); native := C.LLVMGetNamedFunction(module_ptr, name.str); assert native != unsafe { nil }; C.LLVMDeleteFunction(native); unsafe { name.free() }
 } }
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c'')
 native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
 mut comparisons := 0; mut metadata := 0; mut budgets := 0; mut bounds := 0
 mut i8_type := -1; for i, t in p.types { if t.kind == .integer_t && t.bits == 8 { i8_type = i } }; assert i8_type >= 0
 pairs := [[0, 0]!, [0, 7]!, [7, 0]!, [0, 8]!, [8, 0]!, [0, 16]!, [16, 0]!, [0, 40]!, [40, 0]!]!
 for c in cases {
  function := fi(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
  bound := c.length * 2 + if c.chained { 21 } else { 7 }; cost := c.length * 2 + if c.chained { 18 } else { 7 }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == bound && profile.arguments[0].minimum_size == u64(16 + c.length) && profile.arguments[0].readable && !profile.arguments[0].writable && profile.arguments[1].minimum_size == u64(8 + c.length) && profile.arguments[1].writable && !profile.arguments[1].readable; profile.free()
  for sample in 0 .. 32 {
   mut input := []u8{len: 19 + c.length}; pattern(mut input, sample); mut actual := []u8{len: 20 + c.length, init: 0xcc}; mut expected := actual.clone()
   mut bs := [airbitcode.IRMemoryBinding{data: input, offset: 3}, airbitcode.IRMemoryBinding{data: actual, offset: 5, writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost; unsafe { NativeMove(voidptr(address))(&input[3], &expected[5]) }; assert actual == expected; for j in 0 .. c.length { assert actual[13 + j] == input[19 + j] }; comparisons++
   unsafe { input.free(); actual.free(); expected.free(); bs.free() }
  }
  for sample in 0 .. 8 { for pair in pairs { for sliced in [false, true] {
   mut actual := []u8{len: 80 + c.length}; pattern(mut actual, sample); mut expected := actual.clone()
   source_origin := if sliced { 3 } else { 0 }; dest_origin := if sliced { 5 } else { 0 }
   source_view := if sliced { actual[3..actual.len - 1] } else { actual }; dest_view := if sliced { actual[5..actual.len - 2] } else { actual }
   mut bs := [airbitcode.IRMemoryBinding{data: source_view, offset: u64(pair[0])}, airbitcode.IRMemoryBinding{data: dest_view, offset: u64(pair[1]), writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost; unsafe { NativeMove(voidptr(address))(&expected[source_origin + pair[0]], &expected[dest_origin + pair[1]]) }; assert actual == expected; comparisons++
   unsafe { actual.free(); expected.free(); bs.free() }
  } } }
  mut input := []u8{len: 16 + c.length}; mut actual := []u8{len: 8 + c.length, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound - 1) { panic('budget accepted') }; unchanged(actual); budgets++
  for arg in 0 .. 2 { saved := bs[arg]; bs[arg] = airbitcode.IRMemoryBinding{...saved, offset: 1}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('bounds accepted') }; unchanged(actual); bounds++; bs[arg] = saved }
  saved_binding := bs[1]; bs[1] = airbitcode.IRMemoryBinding{...saved_binding, writable: false}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('readonly accepted') }; unchanged(actual); bounds++; bs[1] = saved_binding
  scope := bodies.scopes[function + 1]
  for slot in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   saved := p.instructions[slot]; if stream.records[bodies.instructions[slot].record].code != 34 { continue }
   for changed in [airbitcode.IRTypedInstruction{...saved, flags: 0}, airbitcode.IRTypedInstruction{...saved, flags: 32769}, airbitcode.IRTypedInstruction{...saved, calling_convention: 1}, airbitcode.IRTypedInstruction{...saved, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...saved, attribute_set: 1}, airbitcode.IRTypedInstruction{...saved, callee_function: -1}, airbitcode.IRTypedInstruction{...saved, call_signature: -1}, airbitcode.IRTypedInstruction{...saved, operands_count: 4}, airbitcode.IRTypedInstruction{...saved, operands_count: 6}, airbitcode.IRTypedInstruction{...saved, result_type: i8_type}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_count: 1}] {
    p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('metadata accepted') }; unchanged(actual); metadata++
   }; p.instructions[slot] = saved
   for ordinal in 0 .. 5 { operand_slot := saved.operands_start + ordinal; operand := p.operands[operand_slot]; p.operands[operand_slot] = airbitcode.IRTypedOperand{...operand, type_index: i8_type}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('operand type accepted') }; unchanged(actual); metadata++; p.operands[operand_slot] = operand }
  }
  assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost
  unsafe { input.free(); actual.free(); bs.free() }
 }
 for d in 0 .. 3 { for s in 0 .. 3 { for bits in [32, 64] {
  name := 'zero_${d}_${s}_${bits}'; function := fi(ir, name); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 2; for a in profile.arguments { assert a.minimum_size == 0 && !a.readable && !a.writable }; profile.free()
  mut empty := []u8{}; mut bs := [airbitcode.IRMemoryBinding{data: empty}, airbitcode.IRMemoryBinding{data: empty}]; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 2)!.steps == 2
  mut bytes := []u8{len: 8, init: 0xcc}; address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0; unsafe { NativeMove(voidptr(address))(bytes.data, bytes.data) }; unchanged(bytes); comparisons++; unsafe { empty.free(); bs.free(); bytes.free() }
 } } }
 sequence := fi(ir, 'sequence'); address := C.LLVMGetFunctionAddress(engine, c'sequence'); assert address != 0
 for sample in 0 .. 32 { for pair in pairs {
  mut actual := []u8{len: 128}; pattern(mut actual, sample); mut expected := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: actual, offset: u64(pair[0])}, airbitcode.IRMemoryBinding{data: actual, offset: u64(pair[1]), writable: true}]
  assert p.run_memory_function(ir, stream, pools, bodies, sequence, mut bs, 58)!.steps == 58; unsafe { NativeMove(voidptr(address))(&expected[pair[0]], &expected[pair[1]]) }; assert actual == expected; comparisons++; unsafe { actual.free(); expected.free(); bs.free() }
 } }
 mut guards := 0
 for i, f in ir.functions { if !f.name.starts_with('guard_') && !f.name.starts_with('condition_') { continue }
  mut bytes := []u8{len: 64, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: bytes}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]; if f.name.starts_with('guard_readonly_') { bs << airbitcode.IRMemoryBinding{data: bytes} }
  if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 1000000) { panic('guard accepted') }
  if f.name.starts_with('condition_') && f.name.ends_with('_true') { assert bytes[0] == 17; for j in 1 .. bytes.len { assert bytes[j] == 0xcc } } else { unchanged(bytes) }; guards++; unsafe { bytes.free(); bs.free() }
 }
 for name in ['frozen_condition', 'dead_condition'] {
  mut input := []u8{len: 64}; pattern(mut input, 9); mut actual := []u8{len: 64, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
  assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, if name == 'frozen_condition' { 38 } else { 8 })!.steps == if name == 'frozen_condition' { 38 } else { 3 }
  for j in 0 .. actual.len { assert actual[j] == if name == 'frozen_condition' && j < 17 { input[j] } else if name == 'dead_condition' && j == 0 { u8(9) } else { u8(0xcc) } }; unsafe { input.free(); actual.free(); bs.free() }
 }
 mut input := []u8{len: 499999}; pattern(mut input, 19); mut actual := []u8{len: 499999, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
 for name in ['cumulative_budget', 'mixed_budget'] { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, 1000000) { panic('cumulative budget accepted') }; unchanged(actual); budgets++ }
 if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'maximum_budget'), mut bs, 999999) { panic('maximum short budget accepted') }; unchanged(actual); budgets++
 assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'maximum_budget'), mut bs, 1000000)!.steps == 1000000 && actual == input; unsafe { input.free(); actual.free(); bs.free() }
 assert cases.len == 240 && comparisons == 42546 && metadata == 8640 && budgets == 243 && bounds == 720 && guards == 70
 os.write_file(out + '/result.txt', 'AIR-MEMORY-MEMMOVE: ${cases.len} functions, ${comparisons} native LLVM comparisons, i32/i64 lengths, destination spaces 0/1 and source 0/1/2, pointer-control chains, forward/backward/identical/disjoint aliases and overlapping slices, reusable scratch and zero readonly empty bindings; ${metadata} metadata, ${budgets} budget, ${bounds} binding and ${guards} rejection/condition controls, frozen/dead selects, exact million-step and cumulative/mixed limits PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
