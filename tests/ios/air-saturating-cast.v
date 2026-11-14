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
#include <fenv.h>
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
fn C.fegetround() int
fn C.fesetround(int) int
fn C.feclearexcept(int) int
fn C.fetestexcept(int) int
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
struct Case { name string source int dest int signed bool }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
fn word(c Case, sample int) u64 {
 if c.source == 16 {
  if c.dest in [1, 8, 16, 32, 64] { return u64(sample) }
  fraction := match sample / 64 { 0 { 0 } 1 { 1 } 2 { 1023 } 3 { 512 } else { sample * 487 & 1023 } }
  return u64((sample % 64) << 10 | fraction)
 }
 if sample < 16 { return [u64(0), 0x80000000, 0x7f800000, 0xff800000, 0x7f800001, 0xff800001, 0x7fc12345, 0xffc12345, 1, 0x80000001, 0x3f7fffff, 0xbf7fffff, 0x3fc00000, 0xbfc00000, 0x7f7fffff, 0xff7fffff]![sample] }
 if sample < 40 {
  // Neighbors on both sides of +/- 2^(dest-1) and +/- 2^dest.
  center := u32(127 + c.dest - if sample % 2 == 0 { 1 } else { 0 }) << 23
  delta := (sample - 16) / 2 % 3 - 1
  return u64(u32(i64(center) + delta) | if sample >= 28 { u32(0x80000000) } else { u32(0) })
 }
 // All sign/exponent combinations, with varied fraction patterns.
 return u64((u32(sample) % 512) << 23 | ((u32(sample) * u32(0x1f123bb5)) & 0x7fffff))
}
fn main() {
 assert os.args.len == 3
 out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut text := strings.new_builder(1048576); mut cases := []Case{}
 text.write_string('target datalayout = "e-p:64:64"\n')
 for source in [16, 32] { for dest in 1 .. 65 { for signed in [false, true] {
  op := if signed { 'fptosi' } else { 'fptoui' }; typ := if source == 16 { 'half' } else { 'float' }; name := '${op}_${dest}_${source}'
  cases << Case{name, source, dest, signed}
  text.write_string('declare i${dest} @llvm.${op}.sat.i${dest}.f${source}(${typ})\n')
  text.write_string('define void @${name}(ptr %src, ptr %out) { %x = load ${typ}, ptr %src, align 1\n store i8 17, ptr %out, align 1\n %v = call i${dest} @llvm.${op}.sat.i${dest}.f${source}(${typ} %x)\n %d = getelementptr i8, ptr %out, i64 8\n store i${dest} %v, ptr %d, align 1\n ret void }\n')
  text.write_string('define i${dest} @scalar_${name}(${typ} %x) { %v = call i${dest} @llvm.${op}.sat.i${dest}.f${source}(${typ} %x)\n ret i${dest} %v }\n')
  for mode in ['poison', 'undef', 'freeze', 'select'] {
   input := if mode == 'undef' { 'undef' } else { 'poison' }; choice := if mode == 'freeze' { '%w = freeze i${dest} %v' } else if mode == 'select' { '%w = select i1 false, i${dest} %v, i${dest} 1' } else { '' }; result := if mode in ['freeze', 'select'] { '%w' } else { '%v' }
   text.write_string('define void @${mode}_${name}(ptr %out) { store i8 17, ptr %out, align 1\n %v = call i${dest} @llvm.${op}.sat.i${dest}.f${source}(${typ} ${input})\n ${choice}\n %d = getelementptr i8, ptr %out, i64 8\n store i${dest} ${result}, ptr %d, align 1\n ret void }\n')
  }
 } } }
 text.write_string('define void @cached(ptr %src, ptr %out) { %x = load float, ptr %src, align 1\n %a = call i32 @llvm.fptosi.sat.i32.f32(float %x)\n store i8 17, ptr %out, align 1\n %b = call i32 @llvm.fptosi.sat.i32.f32(float %x)\n ret void }\n')
 text.write_string('define void @discard(float %x) { %v = call i32 @llvm.fptosi.sat.i32.f32(float %x)\n ret void }\ndefine i32 @returned_poison() { %v = call i32 @llvm.fptosi.sat.i32.f32(float poison)\n ret i32 %v }\ndefine i32 @returned_undef() { %v = call i32 @llvm.fptosi.sat.i32.f32(float undef)\n ret i32 %v }\n')
 // Coexistence of all four conversion variants with previous floating,
 // classification and integer families in one declaration-cache lifetime.
 text.write_string('declare i32 @llvm.ctpop.i32(i32)\ndeclare float @llvm.fabs.f32(float)\ndeclare i1 @llvm.is.fpclass.f32(float, i32 immarg)\ndefine void @mixed(ptr %src, ptr %out) { %f = load float, ptr %src, align 1\n %h = fptrunc float %f to half\n %a = call i32 @llvm.fptosi.sat.i32.f32(float %f)\n %b = call i32 @llvm.fptoui.sat.i32.f32(float %f)\n %c = call i32 @llvm.fptosi.sat.i32.f16(half %h)\n %d = call i32 @llvm.fptoui.sat.i32.f16(half %h)\n %e = call float @llvm.fabs.f32(float %f)\n %i = bitcast float %e to i32\n %p = call i32 @llvm.ctpop.i32(i32 %i)\n %q = call i1 @llvm.is.fpclass.f32(float %e, i32 1023)\n %r = zext i1 %q to i32\n %ab = add i32 %a, %b\n %cd = add i32 %c, %d\n %ac = add i32 %ab, %cd\n %pq = add i32 %p, %r\n %v = add i32 %ac, %pq\n store i32 %v, ptr %out, align 1\n ret void }\n')
 os.write_file(out + '/input.ll', text.str())!
 mut assembler := os.new_process(os.args[1]); assembler.set_args([out + '/input.ll', '-o', out + '/input.bc']); assembler.set_redirect_stdio_merged(); assembler.run(); log := assembler.stdout_slurp(); assembler.wait(); code := assembler.code; assembler.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
 data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'saturating-cast'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
 mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 // Explicit VM layout; MCJIT selects its compatible host layout for the byte
 // GEP and align-1 integer/floating loads and stores used by these fixtures.
 C.LLVMSetDataLayout(module_ptr, c'')
 triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple)
 native_input := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, native_input.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
 mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }
 mut comparisons := 0; mut scalar_checks := 0; mut controls := 0; mut budgets := 0; mut environments := 0
 rounding := C.fegetround(); defer { assert C.fesetround(rounding) == 0 }; assert C.fesetround(C.FE_TONEAREST) == 0
 for c in cases {
  function := fi(ir, c.name); scalar := fi(ir, 'scalar_' + c.name); native_name := c.name.clone(); address := C.LLVMGetFunctionAddress(engine, native_name.str); assert address != 0; unsafe { native_name.free() }
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 6 && profile.arguments[0].minimum_size == c.source / 8 && profile.arguments[1].minimum_size == 8 + (c.dest + 7) / 8; profile.free()
  mut input := []u8{len: 8, init: 0xcc}; mut actual := []u8{len: 24, init: 0xcc}; mut expected := actual.clone(); mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  samples := if c.source == 16 && c.dest in [1, 8, 16, 32, 64] { 65536 } else { 4096 }
  for sample in 0 .. samples {
   bits := word(c, sample); for j in 0 .. c.source / 8 { input[1 + j] = u8(bits >> u32(j * 8)) }; for j in 0 .. actual.len { actual[j] = 0xcc; expected[j] = 0xcc }
   assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 6)!.steps == 6
   unsafe { NativeCast(voidptr(address))(&input[1], &expected[3]) }
   for j in 0 .. actual.len { assert actual[j] == if j == 11 + (c.dest + 7) / 8 - 1 && c.dest % 8 != 0 { expected[j] & u8((1 << (c.dest % 8)) - 1) } else { expected[j] }, '${c.name} sample=${sample} input=${bits.hex()}' }; comparisons++
   if sample < 4096 {
    run := p.run_scalar_function(ir, stream, pools, bodies, scalar, [bits | if c.source == 16 { u64(0xffffffffffff0000) } else { u64(0xffffffff00000000) }], 2)!
    mut value := u64(0); for j in 0 .. (c.dest + 7) / 8 { value |= u64(actual[11 + j]) << u32(j * 8) }
    assert run.kind == .integer && run.bits == c.dest && !run.poison && run.steps == 2 && run.value == value; scalar_checks++
    if _ := p.run_integer_function(ir, stream, pools, bodies, scalar, [bits], 2) { panic('floating signature entered integer API') }
   }
  }
  for j in 0 .. actual.len { actual[j] = 0xcc }
  if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 5) { panic('short budget') }; unchanged(actual); budgets++
  for mode in ['poison', 'undef', 'freeze', 'select'] {
   for j in 0 .. actual.len { actual[j] = 0xcc }; mut choice_bindings := [airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
   if mode in ['poison', 'undef'] { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, mode + '_' + c.name), mut choice_bindings, 5) { panic('indeterminate input accepted') } else { if mode == 'poison' { assert err.msg() == 'AIR memory execution: poison store' } }; for j, byte in actual { assert byte == if j == 3 { u8(17) } else { u8(0xcc) } } } else {
    assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, mode + '_' + c.name), mut choice_bindings, 6)!.steps == 6
    for j, byte in actual { assert byte == if j == 3 { u8(17) } else if j >= 11 && j < 11 + (c.dest + 7) / 8 { if j == 11 && mode == 'select' { u8(1) } else { u8(0) } } else { u8(0xcc) } }
   }; controls++; unsafe { choice_bindings.free() }
  }
  mut nearest := [8]u64{}
  for mode in [C.FE_TONEAREST, C.FE_DOWNWARD, C.FE_UPWARD, C.FE_TOWARDZERO]! { assert C.fesetround(mode) == 0; for sample in 0 .. 8 {
   bits := if c.source == 16 { [u64(0x7c01), 0xfc01, 0x7e00, 0x7c00, 0xfc00, 0x3e00, 0xbe00, 0x8001]![sample] } else { [u64(0x7f800001), 0xff800001, 0x7fc00000, 0x7f800000, 0xff800000, 0x3fc00000, 0xbfc00000, 0x80000001]![sample] }
   assert C.feclearexcept(C.FE_ALL_EXCEPT) == 0; run := p.run_scalar_function(ir, stream, pools, bodies, scalar, [bits], 2)!; assert !run.poison && C.fetestexcept(C.FE_ALL_EXCEPT) == 0
   if mode == C.FE_TONEAREST { nearest[sample] = run.value } else { assert run.value == nearest[sample] }; environments++
  } }; assert C.fesetround(C.FE_TONEAREST) == 0
  unsafe { input.free(); actual.free(); expected.free(); bindings.free() }
 }
 mut metadata := 0; cached := fi(ir, 'cached'); scope := bodies.scopes[cached + 1]
 mut guard_input := []u8{len: 8}; mut guard_output := []u8{len: 8, init: 0xcc}; mut guard_bindings := [airbitcode.IRMemoryBinding{data: guard_input}, airbitcode.IRMemoryBinding{data: guard_output, writable: true}]
 for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
  op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 34 { continue }
  for changed in [airbitcode.IRTypedInstruction{...op, flags: 0}, airbitcode.IRTypedInstruction{...op, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...op, attribute_set: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 3}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, calling_convention: 8}, airbitcode.IRTypedInstruction{...op, callee_function: -1}, airbitcode.IRTypedInstruction{...op, call_signature: -1}] {
   p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut guard_bindings, 5) { panic('call metadata accepted') }; unchanged(guard_output); metadata++
  }; p.instructions[index] = op
  operand := p.operands[op.operands_start + 1]; p.operands[op.operands_start + 1] = airbitcode.IRTypedOperand{...operand, type_index: op.result_type}
  if _ := p.run_memory_function(ir, stream, pools, bodies, cached, mut guard_bindings, 5) { panic('cached argument type accepted') }; unchanged(guard_output); metadata++; p.operands[op.operands_start + 1] = operand
 }
 mut changed_functions := ir.functions.clone(); declaration := fi(ir, 'llvm.fptosi.sat.i32.f32'); original_declaration := changed_functions[declaration]
 for wrong in ['llvm.fptosi.sat.i16.f32', 'llvm.fptosi.sat.i32.f16', 'llvm.fptosi.sat.i032.f32', 'llvm.fptosi.sat.i65.f32'] {
  changed_functions[declaration] = airbitcode.IRFunction{...original_declaration, name: wrong}
  changed_ir := airbitcode.IRModule{...ir, functions: changed_functions}
  if _ := p.run_memory_function(changed_ir, stream, pools, bodies, cached, mut guard_bindings, 5) { panic('overload identity accepted') }; unchanged(guard_output); metadata++
 }; unsafe { changed_functions.free() }
 discard := fi(ir, 'discard'); for bits in [u64(0x7f800001), 0x7f800000, 0xff800000, 0x3fc00000]! { assert p.run_void_function(ir, stream, pools, bodies, discard, [bits], 2)!.steps == 2; controls++ }
 returned := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'returned_poison'), [], 2)!; assert returned.kind == .integer && returned.bits == 32 && returned.poison && returned.steps == 2; controls++
 if _ := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'returned_undef'), [], 2) { panic('scalar undef accepted') }; controls++
 mixed := fi(ir, 'mixed'); mixed_address := C.LLVMGetFunctionAddress(engine, c'mixed'); assert mixed_address != 0
 mixed_profile := p.memory_function_profile(ir, stream, pools, bodies, mixed)!; bound := mixed_profile.steps; mixed_profile.free()
 for sample in 0 .. 64 { bits := u32(sample) * u32(0x9e3779b9); for j in 0 .. 4 { guard_input[j] = u8(bits >> u32(j * 8)) }; for j in 0 .. 8 { guard_output[j] = 0xcc }; mut expected := guard_output.clone()
  assert p.run_memory_function(ir, stream, pools, bodies, mixed, mut guard_bindings, bound)!.steps == bound; unsafe { NativeCast(voidptr(mixed_address))(guard_input.data, expected.data) }; assert guard_output == expected; comparisons++; unsafe { expected.free() }
 }
 unsafe { guard_input.free(); guard_output.free(); guard_bindings.free() }
 assert cases.len == 256 && comparisons == 1663040 && scalar_checks == 1048576 && controls == 1030 && budgets == 256 && metadata == 22 && environments == 8192
 os.write_file(out + '/result.txt', 'AIR-SATURATING-CAST: ${cases.len} half/float signed/unsigned i1-i64 overloads, ${comparisons} defined native LLVM comparisons (exhaustive half at five destination widths), ${scalar_checks} scalar checks with high input masking, ${controls} poison/undef/freeze/select, ${budgets} budget, ${metadata} cached call/type and ${environments} rounding/exception controls; mixed old/new cache identities PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
