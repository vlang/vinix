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
type NativeCopy = fn (voidptr, voidptr)
struct Case { name string typ string bits int source int view int dest int chained bool }
fn ptr(space int) string { return if space == 0 { 'ptr' } else { 'ptr addrspace(${space})' } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn pattern(mut bytes []u8, seed int) { mut s := u64(seed + 1) * u64(0x9e3779b97f4a7c15); for i in 0 .. bytes.len { s ^= s << 13; s ^= s >> 7; s ^= s << 17; bytes[i] = u8(s >> 56) } }
fn equal(a []u8, b []u8, pos int, bits int) { for i in 0 .. a.len { assert a[i] == if i == pos + (bits + 7) / 8 - 1 && bits % 8 != 0 { b[i] & u8((1 << (bits % 8)) - 1) } else { b[i] } } }
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut text := strings.new_builder(2097152); mut cases := []Case{}
 text.write_string('target datalayout = "e-p:64:64-p1:64:64-p2:64:64-i24:32-i64:64"\n')
 for i in 1 .. 67 { for source in 0 .. 3 { for view in 0 .. 3 { if source == view { continue }; for dest in 0 .. 2 { for chained in [false, true] {
  cases << Case{'cast_${cases.len}', if i <= 64 { 'i${i}' } else if i == 65 { 'half' } else { 'float' }, if i <= 64 { i } else if i == 65 { 16 } else { 32 }, source, view, dest, chained}
 } } } } }
 for c in cases {
  sp := ptr(c.source); sv := ptr(c.view); dp := ptr(c.dest); dv := ptr(1 - c.dest)
  text.write_string('define void @${c.name}(${sp} %src, ${dp} %out) { entry: %cond = load i8, ${sp} %src, align 1\n store i8 17, ${dp} %out, align 1\n %sp = getelementptr i8, ${sp} %src, i64 16\n %dp = getelementptr i8, ${dp} %out, i64 16\n %a = addrspacecast ${sp} %sp to ${sv}\n %b = addrspacecast ${dp} %dp to ${dv}\n')
  if c.chained {
   text.write_string('%back = addrspacecast ${sv} %a to ${sp}\n %again = addrspacecast ${sp} %back to ${sv}\n %c = trunc i8 %cond to i1\n br i1 %c, label %left, label %right\n left: %l = freeze ${sv} %again\n %dl = bitcast ${dv} %b to ${dv}\n br label %join\n right: %r = getelementptr i8, ${sv} %again, i64 0\n %dr = getelementptr i8, ${dv} %b, i64 0\n br label %join\n join: %s = phi ${sv} [%l, %left], [%r, %right]\n %d = phi ${dv} [%dl, %left], [%dr, %right]\n %ss = select i1 %c, ${sv} %s, ${sv} %again\n %dd = select i1 %c, ${dv} %d, ${dv} %b\n %sf = freeze ${sv} %ss\n %df = freeze ${dv} %dd\n')
  }
  src := if c.chained { '%sf' } else { '%a' }; dst := if c.chained { '%df' } else { '%b' }
  text.write_string('%same = icmp eq ${sv} ${src}, %a\n %v = load ${c.typ}, ${sv} ${src}, align 1\n store ${c.typ} %v, ${dv} ${dst}, align 1\n %tag = getelementptr i8, ${dp} %out, i64 32\n store i1 %same, ${dp} %tag, align 1\n ret void }\n')
 }
 for space in 0 .. 3 {
  for fill in ['memset', 'memset.inline'] { text.write_string('declare void @llvm.${fill}.p${space}.i64(${ptr(space)}, i8, i64, i1 immarg)\n') }
  for copy in ['memmove', 'memcpy', 'memcpy.inline'] { text.write_string('declare void @llvm.${copy}.p${space}.p0.i64(${ptr(space)}, ptr, i64, i1 immarg)\n') }
 }
 for source in 0 .. 3 { for view in 0 .. 3 { if source == view { continue }
  sp := ptr(source); vp := ptr(view)
  for state in ['null', 'poison', 'undef'] { text.write_string('define void @guard_literal_${source}_${view}_${state}(${sp} %src, ptr %out) { store i8 17, ptr %out, align 1\n %a = addrspacecast ${sp} ${state} to ${vp}\n ret void }\n') }
  if source != 2 && view != 2 { continue }
  for op in ['store', 'memset', 'memset.inline', 'memmove', 'memcpy', 'memcpy.inline'] {
   operation := if op == 'store' { 'store i8 7, ${vp} %d, align 1' } else if op.starts_with('memset') { 'call void @llvm.${op}.p${view}.i64(${vp} %d, i8 7, i64 1, i1 false)' } else { 'call void @llvm.${op}.p${view}.p0.i64(${vp} %d, ptr %out, i64 1, i1 false)' }
   text.write_string('define void @guard_write_${source}_${view}_${op}(${sp} %src, ptr %out) { store i8 17, ptr %out, align 1\n %a = addrspacecast ${sp} %src to ${vp}\n %b = getelementptr i8, ${vp} %a, i64 0\n %d = freeze ${vp} %b\n ${operation}\n ret void }\n')
   if op == 'store' { continue }
   zero := if op.starts_with('memset') { 'call void @llvm.${op}.p${view}.i64(${vp} %a, i8 poison, i64 0, i1 false)' } else { 'call void @llvm.${op}.p${view}.p0.i64(${vp} %a, ptr %out, i64 0, i1 false)' }
   text.write_string('define void @zero_${source}_${view}_${op}(${sp} %src, ptr %out) { %a = addrspacecast ${sp} %src to ${vp}\n ${zero}\n ret void }\n')
  }
 } }
 text.write_string('define void @transfers(ptr addrspace(2) %src, ptr addrspace(1) %out) { %s = addrspacecast ptr addrspace(2) %src to ptr\n %d = addrspacecast ptr addrspace(1) %out to ptr\n %d1 = addrspacecast ptr %d to ptr addrspace(1)\n call void @llvm.memset.inline.p1.i64(ptr addrspace(1) %d1, i8 90, i64 8, i1 false)\n %c = getelementptr i8, ptr addrspace(1) %d1, i64 16\n %input = getelementptr i8, ptr %s, i64 8\n call void @llvm.memcpy.inline.p1.p0.i64(ptr addrspace(1) %c, ptr %input, i64 17, i1 false)\n %m = getelementptr i8, ptr %d, i64 17\n %cp = addrspacecast ptr addrspace(1) %c to ptr\n call void @llvm.memmove.p0.p0.i64(ptr %m, ptr %cp, i64 16, i1 false)\n ret void }\n')
 text.write_string('define void @probe(ptr %src, ptr %out) { %a = addrspacecast ptr %src to ptr addrspace(1)\n %b = addrspacecast ptr addrspace(1) %a to ptr addrspace(2)\n %c = addrspacecast ptr addrspace(2) %b to ptr\n %v = load i8, ptr %c, align 1\n store i8 %v, ptr %out, align 1\n ret void }\n')
 text.write_string('define void @guard_space(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %a = addrspacecast ptr %src to ptr addrspace(3)\n ret void }\ndefine void @guard_vector(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %a = addrspacecast <2 x ptr> zeroinitializer to <2 x ptr addrspace(1)>\n ret void }\n')
 text.write_string('define void @guard_cold(ptr %src, ptr %out) { entry: store i8 17, ptr %out, align 1\n br i1 true, label %good, label %cold\n good: ret void\n cold: %a = addrspacecast ptr %src to ptr addrspace(2)\n store i8 7, ptr addrspace(2) %a, align 1\n ret void }\n')
 for op in ['select', 'compare'] { expr := if op == 'select' { '%v = select i1 true, ptr addrspace(1) %a, ptr addrspace(1) %b' } else { '%v = icmp eq ptr addrspace(1) %a, %b' }; text.write_string('define void @guard_binding_${op}(ptr %src, ptr %out) { store i8 17, ptr %out, align 1\n %a = addrspacecast ptr %src to ptr addrspace(1)\n %b = addrspacecast ptr %out to ptr addrspace(1)\n ${expr}\n ret void }\n') }
 os.write_file(out + '/input.ll', text.str())!
 mut assembler := os.new_process(os.args[1]); assembler.set_args([out + '/input.ll', '-o', out + '/input.bc']); assembler.set_redirect_stdio_merged(); assembler.run(); log := assembler.stdout_slurp(); assembler.wait(); code := assembler.code; assembler.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'address-space'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('guard_') { name := f.name.clone(); native := C.LLVMGetNamedFunction(module_ptr, name.str); assert native != unsafe { nil }; C.LLVMDeleteFunction(native); unsafe { name.free() } } }
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c''); native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, unsafe { nil }, 0, &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
 mut comparisons := 0; mut budgets := 0; mut bounds := 0; mut metadata := 0
 mut i8_type := -1; for i, t in p.types { if t.kind == .integer_t && t.bits == 8 { i8_type = i } }; assert i8_type >= 0
 for c in cases {
  function := fi(ir, c.name); lookup := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, lookup.str); assert address != 0, c.name; unsafe { lookup.free() }; bound := if c.chained { 28 } else { 12 }; cost := if c.chained { 25 } else { 12 }; bytes := (c.bits + 7) / 8
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == bound && profile.arguments[0].address_space == u32(c.source) && profile.arguments[1].address_space == u32(c.dest) && profile.arguments[0].minimum_size == u64(16 + bytes) && profile.arguments[1].minimum_size == 33 && profile.arguments[0].readable && !profile.arguments[0].writable && !profile.arguments[1].readable && profile.arguments[1].writable; profile.free()
  for sample in 0 .. 16 { for shift in [0, 3] {
   mut input := []u8{len: 40 + shift}; pattern(mut input, sample); mut output := []u8{len: 40 + shift, init: 0xcc}; mut expected := output.clone(); mut bs := [airbitcode.IRMemoryBinding{data: input, offset: u64(shift)}, airbitcode.IRMemoryBinding{data: output, offset: u64(shift), writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost; unsafe { NativeCopy(voidptr(address))(&input[shift], &expected[shift]) }; equal(output, expected, 16 + shift, c.bits); comparisons++; unsafe { input.free(); output.free(); expected.free(); bs.free() }
  }
   mut actual := []u8{len: 40}; pattern(mut actual, sample); mut expected := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: actual}, airbitcode.IRMemoryBinding{data: actual, writable: true}]
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound)!.steps == cost; unsafe { NativeCopy(voidptr(address))(expected.data, expected.data) }; equal(actual, expected, 16, c.bits); comparisons++; unsafe { actual.free(); expected.free(); bs.free() }
  }
  mut input := []u8{len: 16 + bytes}; mut output := []u8{len: 33, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: output, writable: true}]
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound - 1) { panic('budget accepted') }; unchanged(output); budgets++
  for arg in 0 .. 2 { saved := bs[arg]; bs[arg] = airbitcode.IRMemoryBinding{...saved, offset: 1}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('bounds accepted') }; unchanged(output); bounds++; bs[arg] = saved }
  saved := bs[1]; bs[1] = airbitcode.IRMemoryBinding{...saved, writable: false}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('permission accepted') }; unchanged(output); bounds++; bs[1] = saved
  if c.source == 2 { saved_source := bs[0]; bs[0] = airbitcode.IRMemoryBinding{...saved_source, writable: true}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('writable constant binding accepted') }; unchanged(output); bounds++; bs[0] = saved_source }
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 || op.opcode != 12 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, opcode: 11}, airbitcode.IRTypedInstruction{...op, opcode: 10}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, indices_count: 1}, airbitcode.IRTypedInstruction{...op, result_type: i8_type}] { p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('cast metadata accepted') }; unchanged(output); metadata++ }; p.instructions[index] = op
   operand := p.operands[op.operands_start]
   for typ in [i8_type, op.result_type] { p.operands[op.operands_start] = airbitcode.IRTypedOperand{...operand, type_index: typ}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, bound) { panic('cast operand accepted') }; unchanged(output); metadata++ }; p.operands[op.operands_start] = operand
  }; unsafe { input.free(); output.free(); bs.free() }
 }
 mut guards := 0; mut zeros := 0
 for i, f in ir.functions {
  if f.name.starts_with('guard_') { first_type := ir.references[ir.types[f.signature].refs_start + 1]; mut input := []u8{len: 64, init: 0xcc}; mut output := []u8{len: 64, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: input, writable: p.types[first_type].address_space != 2}, airbitcode.IRMemoryBinding{data: output, writable: true}]; if _ := p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 1000) { panic('guard accepted: ' + f.name) }; unchanged(input); unchanged(output); guards++; unsafe { input.free(); output.free(); bs.free() } }
  if f.name.starts_with('zero_') { profile := p.memory_function_profile(ir, stream, pools, bodies, i)!; assert profile.steps == 3; for a in profile.arguments { assert a.minimum_size == 0 && !a.readable && !a.writable }; profile.free(); mut empty := []u8{}; mut bs := [airbitcode.IRMemoryBinding{data: empty}, airbitcode.IRMemoryBinding{data: empty}]; assert p.run_memory_function(ir, stream, pools, bodies, i, mut bs, 3)!.steps == 3; mut bytes := []u8{len: 8, init: 0xcc}; name := f.name.clone(); address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0, name; unsafe { NativeCopy(voidptr(address))(bytes.data, bytes.data) }; unchanged(bytes); comparisons++; zeros++; unsafe { bytes.free(); empty.free(); bs.free(); name.free() } }
 }
 probe := fi(ir, 'probe'); address := C.LLVMGetFunctionAddress(engine, c'probe'); assert address != 0
 for sample in 0 .. 32 { mut input := [u8(sample * 7)]; mut output := [u8(0xcc)]; mut expected := output.clone(); mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: output, writable: true}]; assert p.run_memory_function(ir, stream, pools, bodies, probe, mut bs, 6)!.steps == 6; unsafe { NativeCopy(voidptr(address))(input.data, expected.data) }; assert output == expected; comparisons++; unsafe { input.free(); output.free(); expected.free(); bs.free() } }
 mut layouts := 0; mut layout_input := [u8(7)]; mut layout_output := [u8(0xcc)]; mut layout_bindings := [airbitcode.IRMemoryBinding{data: layout_input}, airbitcode.IRMemoryBinding{data: layout_output, writable: true}]
 for bad in ['', 'E-p:64:64', 'e-p:32:32', 'e-p:64:64-p1:32:32', 'e-p:64:64-p2:32:32', 'e-p:64:64-p1:64:64:64:32', 'e-p:64:64-p2:64:64:64:32', 'e-p:64:64-p1:128:128', 'e-p:64:64-ni:1', 'e-p:64:64-ni:2'] { changed := airbitcode.IRModule{...ir, data_layout: bad}; if _ := p.run_memory_function(changed, stream, pools, bodies, probe, mut layout_bindings, 6) { panic('layout accepted') }; unchanged(layout_output); layouts++ }; unsafe { layout_input.free(); layout_output.free(); layout_bindings.free() }
 transfer := fi(ir, 'transfers'); transfer_address := C.LLVMGetFunctionAddress(engine, c'transfers'); assert transfer_address != 0
 transfer_profile := p.memory_function_profile(ir, stream, pools, bodies, transfer)!; assert transfer_profile.steps == 85 && transfer_profile.arguments[0].minimum_size == 25 && transfer_profile.arguments[1].minimum_size == 33 && transfer_profile.arguments[0].readable && !transfer_profile.arguments[0].writable && transfer_profile.arguments[1].readable && transfer_profile.arguments[1].writable; transfer_profile.free()
 for sample in 0 .. 32 { mut input := []u8{len: 32}; pattern(mut input, sample); mut output := []u8{len: 40, init: 0xcc}; mut expected := output.clone(); mut bs := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: output, writable: true}]; assert p.run_memory_function(ir, stream, pools, bodies, transfer, mut bs, 85)!.steps == 85; unsafe { NativeCopy(voidptr(transfer_address))(input.data, expected.data) }; assert output == expected; comparisons++; unsafe { input.free(); output.free(); expected.free(); bs.free() } }
 mut transfer_input := []u8{len: 32}; mut transfer_output := []u8{len: 40, init: 0xcc}; mut transfer_bindings := [airbitcode.IRMemoryBinding{data: transfer_input}, airbitcode.IRMemoryBinding{data: transfer_output, writable: true}]; if _ := p.run_memory_function(ir, stream, pools, bodies, transfer, mut transfer_bindings, 84) { panic('transfer short budget accepted') }; unchanged(transfer_output); budgets++; unsafe { transfer_input.free(); transfer_output.free(); transfer_bindings.free() }
 assert cases.len == 1584 && comparisons == 76116 && metadata == 42768 && budgets == 1585 && bounds == 5280 && guards == 47 && zeros == 20 && layouts == 10
 os.write_file(out + '/result.txt', 'AIR-MEMORY-ADDRESS-SPACE: ${cases.len} functions, ${comparisons} native LLVM comparisons, all six space-0/1/2 casts, i1-i64/half/float, round trips, GEP/PHI/select/freeze/bitcast/compare chains, shifted and aliased bindings; ${metadata} metadata, ${budgets} budget, ${bounds} binding, ${guards} readonly/literal/vector/space/cold/binding guards, ${zeros} zero operations and ${layouts} layout controls PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
