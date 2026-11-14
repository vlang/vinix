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
type NativeMemory = fn (voidptr, voidptr)

struct Case { name string op string space int bits int dest int source int }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn ptr(space int) string { return if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' } }
fn pattern(mut bytes []u8, sample int) { mut state := u64(sample + 1) * u64(0x9e3779b97f4a7c15); for i in 0 .. bytes.len { state ^= state << 13; state ^= state >> 7; state ^= state << 17; bytes[i] = u8(state >> 56) } }
fn aligned(bytes []u8) []u8 { origin := int((u64(0) - unsafe { u64(bytes.data) }) & 255); return bytes[origin..origin + 512] }
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut source := strings.new_builder(524288); mut cases := []Case{}
 source.write_string('target datalayout = "e-p:64:64"\n')
 for space in 0 .. 3 { for bits in [32, 64] {
  dp := ptr(space)
  source.write_string('declare void @llvm.memset.p${space}.i${bits}(${dp}, i8, i${bits}, i1 immarg)\n')
  for op in ['memmove', 'memcpy'] { source.write_string('declare void @llvm.${op}.p${space}.p2.i${bits}(${dp}, ptr addrspace(2), i${bits}, i1 immarg)\n') }
 } }
 for op in ['memset', 'memmove', 'memcpy'] { for space in 0 .. 2 { for bits in [32, 64] { for dest in [1, 2, 4, 8, 16, 32, 64] { for src in if op == 'memset' { [1] } else { [1, 4, 16, 64] } {
  cases << Case{'align_${cases.len}', op, space, bits, dest, src}
 } } } } }
 for c in cases {
  dp := ptr(c.space); name := if c.op == 'memset' { 'llvm.memset.p${c.space}.i${c.bits}' } else { 'llvm.${c.op}.p${c.space}.p2.i${c.bits}' }; arg := if c.op == 'memset' { 'i8 %byte' } else { 'ptr addrspace(2) align ${c.source} %s' }
  source.write_string('define void @${c.name}(ptr addrspace(2) %src, ${dp} %out) { %byte = load i8, ptr addrspace(2) %src, align 1\n store i8 17, ${dp} %out, align 1\n %s = getelementptr i8, ptr addrspace(2) %src, i64 128\n %d = getelementptr i8, ${dp} %out, i64 128\n call void @${name}(${dp} align ${c.dest} %d, ${arg}, i${c.bits} 17, i1 false)\n call void @${name}(${dp} align ${c.dest} %d, ${arg}, i${c.bits} 0, i1 false)\n ret void }\n')
 }
 // Stronger/weaker requirements on one binding combine regardless of call order.
 source.write_string('define void @cache(ptr addrspace(2) %src, ptr addrspace(1) %out) { %byte = load i8, ptr addrspace(2) %src, align 1\n %s = getelementptr i8, ptr addrspace(2) %src, i64 128\n %d = getelementptr i8, ptr addrspace(1) %out, i64 128\n store i8 17, ptr addrspace(1) %out, align 1\n')
 for dest in [1, 2, 4, 8, 16, 32, 64] {
  source.write_string('call void @llvm.memset.p1.i64(ptr addrspace(1) align ${dest} %d, i8 %byte, i64 1, i1 false)\n')
  for src in [1, 4, 16, 64] { for op in ['memmove', 'memcpy'] { source.write_string('call void @llvm.${op}.p1.p2.i64(ptr addrspace(1) align ${dest} %d, ptr addrspace(2) align ${src} %s, i64 1, i1 false)\n') } }
 }
 source.write_string('call void @llvm.memset.p1.i64(ptr addrspace(1) align 1 %d, i8 %byte, i64 1, i1 false)\n ret void }\n')
 for space in 0 .. 3 { for op in ['memset', 'memmove', 'memcpy'] {
  dp := ptr(space); name := if op == 'memset' { 'llvm.memset.p${space}.i64' } else { 'llvm.${op}.p${space}.p2.i64' }; arg := if op == 'memset' { 'i8 poison' } else { 'ptr addrspace(2) align 32 %src' }
  source.write_string('define void @zero_${space}_${op}(ptr addrspace(2) %src, ${dp} %out) { call void @${name}(${dp} align 64 %out, ${arg}, i64 0, i1 false)\n ret void }\n')
 } }
 for side in ['dest', 'source'] {
  base := if side == 'dest' { '%out' } else { '%src' }; a := if side == 'dest' { '%p' } else { '%out' }; b := if side == 'source' { '%p' } else { '%src' }
  source.write_string('define void @guard_${side}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %p = getelementptr i8, ptr ${base}, i64 1\n call void @llvm.memmove.p0.p0.i64(ptr align 8 ${a}, ptr align 8 ${b}, i64 1, i1 false)\n ret void }\n')
 }
 source.write_string('declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1 immarg)\ndefine void @guard_cold(ptr %src, ptr %out) { entry: br i1 true, label %good, label %cold\n good: store i8 9, ptr %out, align 1\n ret void\n cold: %p = getelementptr i8, ptr %out, i64 1\n call void @llvm.memset.p0.i64(ptr align 8 %p, i8 0, i64 0, i1 false)\n ret void }\n')
 for name, attributes in {'noundef': 'align 8 noundef', 'nonnull': 'align 8 nonnull', 'dereferenceable': 'align 8 dereferenceable(1)'} {
  source.write_string('define void @guard_${name}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n call void @llvm.memset.p0.i64(ptr ${attributes} %out, i8 0, i64 1, i1 false)\n ret void }\n')
 }
 os.write_file(out + '/input.ll', source.str())!
 mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'alignment'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('guard_') { name := f.name.clone(); native := C.LLVMGetNamedFunction(module_ptr, name.str); assert native != unsafe { nil }; C.LLVMDeleteFunction(native); unsafe { name.free() } } }
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c''); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
 mut comparisons := 0; mut controls := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0
  bound := if c.op == 'memset' { 24 } else { 41 }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == bound && profile.arguments[0].alignment == u64(c.source) && profile.arguments[1].alignment == u64(c.dest) && profile.arguments[0].minimum_size == u64(if c.op == 'memset' { 128 } else { 145 }) && profile.arguments[1].minimum_size == 145; profile.free()
  for sample in 0 .. 32 { for shift in [0, 64] {
   mut input_storage := []u8{len: 768}; pattern(mut input_storage, sample); mut output_storage := []u8{len: 768, init: 0xcc}; mut expected_storage := output_storage.clone()
   input := aligned(input_storage); actual := aligned(output_storage); expected := aligned(expected_storage)
   mut bs := [airbitcode.IRMemoryBinding{data: input, offset: u64(shift), base_alignment: 256}, airbitcode.IRMemoryBinding{data: actual, offset: u64(shift), base_alignment: 256, writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == bound; unsafe { NativeMemory(voidptr(address))(&input[shift], &expected[shift]) }; assert actual == expected; comparisons++
   unsafe { input_storage.free(); output_storage.free(); expected_storage.free(); bs.free() }
  } }
  mut input_storage := []u8{len: 768}; pattern(mut input_storage, 17); mut output_storage := []u8{len: 768, init: 0xcc}; input := aligned(input_storage); actual := aligned(output_storage)
  mut bs := [airbitcode.IRMemoryBinding{data: input, base_alignment: 256}, airbitcode.IRMemoryBinding{data: actual, base_alignment: 256, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound - 1) { panic('budget accepted') }; for b in actual { assert b == 0xcc }; budgets++
  for arg, alignment in [c.source, c.dest] { if alignment == 1 { continue }
   saved := bs[arg]
   for changed in [airbitcode.IRMemoryBinding{...saved, base_alignment: u64(alignment / 2)}, airbitcode.IRMemoryBinding{...saved, offset: 1}] {
    bs[arg] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('unaligned binding accepted') }; for b in actual { assert b == 0xcc }; controls++
   }; bs[arg] = saved
  }
  assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == bound
  unsafe { input_storage.free(); output_storage.free(); bs.free() }
 }
 cache := fi(ir, 'cache'); cache_profile := p.memory_function_profile(ir, stream, pools, bodies, cache)!; assert cache_profile.steps == 189 && cache_profile.arguments[0].alignment == 64 && cache_profile.arguments[1].alignment == 64; cache_profile.free(); address := C.LLVMGetFunctionAddress(engine, c'cache'); assert address != 0
 cache_scope := bodies.scopes[cache + 1]; mut seen := map[u64]bool{}; mut tags := [16]u64{}; mut collisions := 0
 for index in cache_scope.instructions_start .. cache_scope.instructions_start + cache_scope.instructions_count {
  set := p.instructions[index].attribute_set; if set == 0 { continue }; seen[set] = true; slot := int(set % 16); if tags[slot] != 0 && tags[slot] != set { collisions++ }; tags[slot] = set
 }
 assert seen.len > 16 && collisions > 0; unsafe { seen.free() }
 for sample in 0 .. 32 {
  mut input_storage := []u8{len: 768}; pattern(mut input_storage, sample); mut output_storage := []u8{len: 768, init: 0xcc}; mut expected_storage := output_storage.clone(); input := aligned(input_storage); actual := aligned(output_storage); expected := aligned(expected_storage)
  mut bs := [airbitcode.IRMemoryBinding{data: input, base_alignment: 256}, airbitcode.IRMemoryBinding{data: actual, base_alignment: 256, writable: true}]
  assert p.run_memory_function(ir, stream, pools, bodies, cache, mut bs, 189)!.steps == 189; unsafe { NativeMemory(voidptr(address))(input.data, expected.data) }; assert actual == expected && actual[128] == input[0]; comparisons++; unsafe { input_storage.free(); output_storage.free(); expected_storage.free(); bs.free() }
 }
 mut guards := 0
 for i, f in ir.functions { if !f.name.starts_with('guard_') { continue }
  mut input := []u8{len: 256}; mut actual := []u8{len: 256, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input, base_alignment: 256}, airbitcode.IRMemoryBinding{data: actual, base_alignment: 256, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 256) { panic('guard accepted') }; for b in actual { assert b == 0xcc }; guards++
  if f.name in ['guard_source', 'guard_dest'] { saved := bs[if f.name == 'guard_source' { 0 } else { 1 }]; bs[if f.name == 'guard_source' { 0 } else { 1 }] = airbitcode.IRMemoryBinding{...saved, offset: 7}; if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 256) { panic('compensating offset accepted') }; for b in actual { assert b == 0xcc }; controls++ }
  unsafe { input.free(); actual.free(); bs.free() }
 }
 for space in 0 .. 3 { for op in ['memset', 'memmove', 'memcpy'] {
  name := 'zero_${space}_${op}'; function := fi(ir, name); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 2 && profile.arguments[1].alignment == 64 && profile.arguments[0].alignment == if op == 'memset' { u64(1) } else { u64(32) }; for a in profile.arguments { assert a.minimum_size == 0 && !a.readable && !a.writable }; profile.free()
  mut empty := []u8{}; mut bs := [airbitcode.IRMemoryBinding{data: empty, base_alignment: 32}, airbitcode.IRMemoryBinding{data: empty, base_alignment: 64}]; assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 2)!.steps == 2
  saved := bs[1]; bs[1] = airbitcode.IRMemoryBinding{...saved, base_alignment: 32}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 2) { panic('zero alignment accepted') }; controls++; bs[1] = saved
  mut native_storage := []u8{len: 768, init: 0xcc}; bytes := aligned(native_storage); address_zero := C.LLVMGetFunctionAddress(engine, name.str); assert address_zero != 0; unsafe { NativeMemory(voidptr(address_zero))(bytes.data, bytes.data) }; for b in bytes { assert b == 0xcc }; comparisons++; unsafe { empty.free(); bs.free(); native_storage.free() }
 } }
 assert cases.len == 252 && comparisons == 16169 && controls == 779 && budgets == 252 && guards == 6
 os.write_file(out + '/result.txt', 'AIR-MEMORY-ALIGNMENT: ${cases.len} functions, ${comparisons} native LLVM comparisons, memset/memmove/memcpy, i32/i64, destination align 1-64 and source 1/4/16/64, aligned backing views and offsets, 64 mixed/cache-collision calls; ${controls} binding/compensating/zero controls, ${budgets} budgets, ${guards} call-attribute/derived/untaken guards, zero readonly empty bindings PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
