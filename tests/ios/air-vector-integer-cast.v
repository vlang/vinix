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
type NativeCast = fn (voidptr, voidptr, voidptr)
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
struct NativeModule { context voidptr buffer voidptr engine voidptr }
fn native_module(data []u8, out string, ir airbitcode.IRModule) !NativeModule {
 assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-integer-cast'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Case { name string source int dest int count int operation int flags int }
struct Counts { shapes int native int choices int poison int scalar int metadata int budgets int }
fn instruction(c Case) string { return ['trunc', 'zext', 'sext'][c.operation] + if c.flags == 0 { '' } else if c.operation == 1 { ' nneg' } else if c.flags == 1 { ' nuw' } else if c.flags == 2 { ' nsw' } else { ' nuw nsw' } }
fn word(bits int, lane int) u64 { return [u64(0), 1, mask(bits), u64(1) << u32(bits - 1), (u64(1) << u32(bits - 1)) - 1, (u64(1) << u32(bits - 1)) + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]![lane % 8] & mask(bits) }
fn vector(c Case) string {
 mut s := strings.new_builder(512); s.write_string('<'); for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; s.write_string('i${c.source} ${word(c.source, lane)}') }; s.write_string('>'); return s.str()
}
fn shuffle(count int) string {
 mut s := strings.new_builder(512); s.write_string('<'); for lane in 0 .. count { if lane != 0 { s.write_string(', ') }; s.write_string('i32 ${count - 1 - lane + (lane % 2) * count}') }; s.write_string('>'); return s.str()
}
// Per-bit arithmetic is independent of the production reconstruction masks.
fn converted(c Case, input u64) (bool, u64) {
 mut poison := c.operation == 1 && c.flags == 1 && input >> u32(c.source - 1) & 1 != 0
 if c.operation == 0 { for bit in c.dest .. c.source {
  v := input >> u32(bit) & 1
  poison = poison || (c.flags & 1 != 0 && v != 0) || (c.flags & 2 != 0 && v != input >> u32(c.dest - 1) & 1)
 } }
 mut output := u64(0)
 for bit in 0 .. c.dest { v := if bit < c.source { input >> u32(bit) & 1 } else if c.operation == 2 { input >> u32(c.source - 1) & 1 } else { u64(0) }; output |= v << u32(bit) }
 return poison, output
}
// State 0 is a defined native comparison, 1 poison and 2 a fixed-zero freeze.
fn expected(c Case, j u64, q u64, r u64, x u64, y u64, raw bool) (int, u64) {
 if r >= u64(c.count) { return 1, 0 }
 lane := if raw { int(r) } else { c.count - 1 - int(r) }
 if !raw && int(r) % 2 == 0 { if q >= u64(c.count) { return 1, 0 }; if q == u64(lane) { return 0, y & mask(c.dest) } }
 if j >= u64(c.count) { return if raw { 1 } else { 2 }, 0 }
 poison, value := converted(c, if j == u64(lane) { x } else { word(c.source, lane) })
 return if poison { if raw { 1 } else { 2 } } else { 0 }, if poison { u64(0) } else { value }
}
fn run_batch(assembler_path string, out string, source int) !Counts {
 mut s := strings.new_builder(2097152); mut cases := []Case{}
 s.write_string('target datalayout = "e-p:64:64"\n')
 for dest in 1 .. 65 { if source == dest { continue }; for operation in 0 .. 3 {
  if (operation == 0) != (dest < source) { continue }
  for flags in 0 .. if operation == 0 { 4 } else if operation == 1 { 2 } else { 1 } { for count in [1, 3, 16] {
   c := Case{'case_${cases.len}', source, dest, count, operation, flags}; cases << c
   ops := '%a = insertelement <${count} x i${source}> ${vector(c)}, i${source} %x, i64 %j\n %n = ${instruction(c)} <${count} x i${source}> %a to <${count} x i${dest}>\n %f = freeze <${count} x i${dest}> %n\n %u = insertelement <${count} x i${dest}> %f, i${dest} %y, i64 %q\n %t = shufflevector <${count} x i${dest}> %u, <${count} x i${dest}> %f, <${count} x i32> ${shuffle(count)}\n %s = select i1 %raw, <${count} x i${dest}> %n, <${count} x i${dest}> %t\n %v = extractelement <${count} x i${dest}> %s, i64 %r\n'
   s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %cp = getelementptr i8, ptr %indices, i64 24\n %raw = load i1, ptr %cp, align 1\n %x = load i${source}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load i${dest}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i${dest} %v, ptr %d, align 1\n ret void }\n')
   s.write_string('define i${dest} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, i${source} %x, i${dest} %y, i1 %raw) { ${ops}ret i${dest} %v }\n')
  } }
 } }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 native := native_module(data, out, ir)!; defer { native.close() }
 mut compared := 0; mut choices := 0; mut poison := 0; mut scalar := 0; mut metadata := 0; mut budgets := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); address := C.LLVMGetFunctionAddress(native.engine, c.name.str); assert address != 0
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 21 && profile.arguments[0].minimum_size == 25 && profile.arguments[1].minimum_size == 8 + (c.dest + 7) / 8 && profile.arguments[2].minimum_size == 8 + (c.dest + 7) / 8; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut reference := actual.clone(); mut bindings := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), 1, 2, u64(c.count), ~u64(0), 0, u64(c.count - 1)]!
  for raw in [false, true] { for sample in 0 .. 8 {
   j := edges[(sample * 3) % 8]; q := edges[(sample * 5 + 1) % 8]; r := edges[sample]; x := word(c.source, sample + c.dest); y := word(c.dest, sample + c.source); state, value := expected(c, j, q, r, x, y, raw)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; indices[25] = u8(raw)
   for i in 0 .. (c.source + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)) }; for i in 0 .. (c.dest + 7) / 8 { input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; reference[i] = 0xcc }
   args := [j, q, r, x | ~mask(c.source), y | ~mask(c.dest), u64(raw)]
   run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 8)!; integer := p.run_integer_function(ir, stream, pools, bodies, sf, args, 8)!
   assert run.poison == (state == 1) && integer.poison == run.poison && run.bits == c.dest && run.steps == 8 && integer.steps == 8 && (run.poison || (run.value == value && integer.value == value)); scalar += 2
   if state == 1 {
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 21) { panic('poison vector cast stored') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() }; poison++
   } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 21)!.steps == 21; if state == 2 { choices++ } else { compared++ } }
   for i, b in actual { assert b == if i == 3 { u8(17) } else if state != 1 && i >= 11 && i < 11 + (c.dest + 7) / 8 { u8(value >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${c.name} src=${source} dst=${c.dest} flags=${c.flags} raw=${raw} sample=${sample}' }
   if state == 0 {
    unsafe { NativeCast(voidptr(address))(&indices[1], &input[1], &reference[3]) }
    for i, b in actual { assert b == if c.dest % 8 != 0 && i == 11 + (c.dest + 7) / 8 - 1 { reference[i] & u8((1 << (c.dest % 8)) - 1) } else { reference[i] } }
   }; unsafe { args.free() }
  } }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 20) { panic('short memory budget') }; unchanged(actual); if _ := p.run_integer_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0, 1], 7) { panic('short integer budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 4}, airbitcode.IRTypedInstruction{...op, opcode: 11}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
    p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 21) { panic('cast metadata admitted') }; unchanged(actual); metadata++
   }; p.instructions[index] = op
   original := p.operands[op.operands_start]
   for changed in [airbitcode.IRTypedOperand{...original, number: 0}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: -1}] {
    p.operands[op.operands_start] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 21) { panic('cast source admitted') }; unchanged(actual); metadata++
   }; p.operands[op.operands_start] = original
  }; unsafe { indices.free(); input.free(); actual.free(); reference.free(); bindings.free() }
 }
 assert scalar == cases.len * 32 && metadata == cases.len * 10 && budgets == cases.len * 2
 return Counts{cases.len, compared, choices, poison, scalar, metadata, budgets}
}
fn controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(65536)
 s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['poison', 'undef', 'partial_poison', 'partial_undef', 'source_poison', 'source_undef', 'result_poison', 'result_undef', 'discard_poison', 'discard_undef', 'old', 'chain', 'prior_undef', 'index_undef', 'isolation']
 mut checks := 0
 for operation in 0 .. 3 { for flags in 0 .. if operation == 0 { 4 } else if operation == 1 { 2 } else { 1 } {
  source := if operation == 0 { 32 } else { 8 }; dest := if operation == 0 { 8 } else { 32 }; c := Case{'', source, dest, 2, operation, flags}
  for mode in modes {
   name := '${mode}_${operation}_${flags}'
   initial := if mode in ['undef', 'source_undef', 'result_undef', 'discard_undef', 'prior_undef'] { 'undef' } else if mode in ['poison', 'source_poison', 'result_poison', 'discard_poison'] { 'poison' } else if mode == 'partial_undef' { '<i${source} 0, i${source} undef>' } else if mode == 'partial_poison' { '<i${source} 0, i${source} poison>' } else { '<i${source} 3, i${source} 7>' }
   pre := if mode == 'prior_undef' { '%prior = extractelement <2 x i${source}> undef, i32 0\n' } else if mode == 'index_undef' { '%prior = insertelement <2 x i${source}> poison, i${source} 0, i32 undef\n' } else if mode.starts_with('source_') { '%prior = freeze <2 x i${source}> ${initial}\n' } else { '' }
   input := if mode.starts_with('source_') || mode == 'index_undef' { '%prior' } else { initial }
   post := if mode == 'old' { '%changed = insertelement <2 x i${dest}> %n, i${dest} 99, i32 0\n' } else if mode.starts_with('result_') { '%other = freeze <2 x i${dest}> %n\n' } else if mode == 'chain' { '%back = ${if operation == 0 { 'zext' } else { 'trunc' }} <2 x i${dest}> %n to <2 x i${source}>\n %cmp = icmp eq <2 x i${source}> %back, <i${source} 3, i${source} 7>\n %other = zext <2 x i1> %cmp to <2 x i64>\n' } else { '' }
   selected := if mode.starts_with('result_') || mode == 'chain' { '%other' } else { '%n' }; result_bits := if mode == 'chain' { 64 } else { dest }
   store := if mode.starts_with('discard_') { '' } else { '%v = extractelement <2 x i${result_bits}> ${selected}, i32 ${if mode == 'isolation' { 1 } else { 0 }}\n %d = getelementptr i8, ptr %out, i64 8\n store i${result_bits} %v, ptr %d, align 1\n' }
   // A promise violation in lane one must not affect lane zero.
   iso := if mode == 'isolation' { '%m = insertelement <2 x i${source}> ${initial}, i${source} poison, i32 0\n' } else { '' }
   s.write_string('define void @${name}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}${iso}%n = ${instruction(c)} <2 x i${source}> ${if mode == 'isolation' { '%m' } else { input }} to <2 x i${dest}>\n ${post}${store}ret void }\n')
  }
 } }
 guards := ['argument', 'load', 'phi', 'coldwide', 'scalable', 'wide', 'float', 'float_result', 'bitcast', 'reshape', 'scalar_source', 'scalar_result', 'pointer']
 for guard in guards {
  sig := if guard == 'argument' { '<2 x i8> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
  body := match guard {
   'argument' { '%n = zext <2 x i8> %v to <2 x i16>' }
   'load' { '%v = load volatile <2 x i8>, ptr %src\n %n = zext <2 x i8> %v to <2 x i16>' }
   'phi' { 'br label %body\n body: %v = phi <2 x i8> [zeroinitializer, %entry]\n %n = zext <2 x i8> %v to <2 x i16>' }
   'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold: %n = zext <17 x i8> zeroinitializer to <17 x i16>' }
   'scalable' { '%n = zext <vscale x 2 x i8> zeroinitializer to <vscale x 2 x i16>' }
   'wide' { '%n = zext <2 x i64> zeroinitializer to <2 x i65>' }
   'float' { '%n = fptosi <2 x double> zeroinitializer to <2 x i32>' }
   'float_result' { '%n = uitofp nneg <2 x i32> zeroinitializer to <2 x float>' }
   'bitcast' { '%n = bitcast <2 x i64> zeroinitializer to <2 x double>' }
   'reshape' { '%n = bitcast <4 x i8> zeroinitializer to <2 x i16>' }
   'scalar_source' { '%n = bitcast i32 0 to <2 x i16>' }
   'scalar_result' { '%n = bitcast <2 x i16> zeroinitializer to i32' }
   else { '%n = ptrtoint <2 x ptr> zeroinitializer to <2 x i64>' }
  }
  s.write_string('define void @guard_${guard}(${sig}) { entry: store i8 17, ptr %out\n ${body}\n ret void }\n')
 }
 s.write_string('define i32 @loop(i32 %limit) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %a = insertelement <2 x i32> poison, i32 %i, i32 0\n %n = trunc <2 x i32> %a to <2 x i8>\n %f = freeze <2 x i8> %n\n %b = zext <2 x i8> %f to <2 x i32>\n %v = extractelement <2 x i32> %b, i32 0\n %added = add i32 %sum, %v\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i32 %added }\n')
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 for operation in 0 .. 3 { for flags in 0 .. if operation == 0 { 4 } else if operation == 1 { 2 } else { 1 } { for mode in modes {
  name := '${mode}_${operation}_${flags}'; mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
  bad := mode in ['poison', 'undef', 'partial_undef', 'result_undef', 'discard_undef', 'prior_undef', 'index_undef']
  if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, 100) { panic('cast control accepted: ' + name) } } else { p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, 100)! }
  value := if mode == 'chain' { u64(1) } else if mode == 'isolation' { u64(7) } else if mode == 'old' { u64(3) } else { u64(0) }; bytes := if mode == 'chain' { 8 } else if operation == 0 { 1 } else { 4 }
  for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + bytes { u8(value >> u32((i - 11) * 8)) } else { u8(0xcc) }, name }; checks++; unsafe { output.free(); bs.free() }
 } } }
 for guard in guards { mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }; if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100) { panic('unsupported cast admitted: ' + guard) }; unchanged(output); checks++; unsafe { output.free(); bs.free() } }
 for count in [u64(1), 2, 3, 16, 257, 513]! { mut sum := u64(0); for i in u64(0) .. count { sum += i % 256 }; for mixed in [false, true] { run := if mixed { r := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], int(count * 11 + 2))!; airbitcode.IRIntegerRun{bits: r.bits, value: r.value, poison: r.poison, steps: r.steps} } else { p.run_integer_function(ir, stream, pools, bodies, fi(ir, 'loop'), [count], int(count * 11 + 2))! }; assert !run.poison && run.value == sum && run.steps == int(count * 11 + 2); checks++ } }
 assert checks == 130
 os.write_file(out + '/result.txt', 'AIR-VECTOR-INTEGER-CAST-CONTROLS: ${checks} poison/undef, source/result freeze, discards, old snapshots, composed casts/comparisons, poison isolation, integer/mixed loop slot reuse and unsupported profiles PASS\n')!
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } { s.write_string('%v${i} = zext <${if storage { 1 } else { 16 }} x i1> zeroinitializer to <${if storage { 1 } else { 16 }} x i64>\n') }
  if !storage { for i in 0 .. if over { 54309 } else { 54308 } { s.write_string('%x${i} = extractelement <16 x i64> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory cast limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('void cast limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 58406 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 58405 } }
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 mut shapes := 0; mut native := 0; mut choices := 0; mut poison := 0; mut scalar := 0; mut metadata := 0; mut budgets := 0
 for source in 1 .. 65 { c := run_batch(os.args[1], out + '/batch-${source}', source)!; shapes += c.shapes; native += c.native; choices += c.choices; poison += c.poison; scalar += c.scalar; metadata += c.metadata; budgets += c.budgets }
 controls(os.args[1], out + '/controls')!
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 assert shapes == 42336 && native + choices + poison == shapes * 16 && scalar == shapes * 32
 os.write_file(out + '/result.txt', 'AIR-VECTOR-INTEGER-CAST: ${shapes} shapes across every i1-i64 width pair, seven variants and 1/3/16 lanes; ${native} exact LLVM values, ${choices} fixed-zero freeze choices, ${poison} poison-store failures preserving prior writes, ${scalar} scalar/integer checks, ${metadata} metadata/source and ${budgets} budgets PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
