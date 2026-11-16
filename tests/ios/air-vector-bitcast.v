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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-bitcast'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Case { name string source int dest int count int form int mode int }
fn vector(c Case) string {
 if c.form >= 2 { return ['poison', 'undef', 'zeroinitializer'][c.form - 2] }
 mut s := strings.new_builder(1024); s.write_string('<')
 for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; value := if c.form == 1 && lane % 4 == 1 { 'poison' } else if c.form == 1 && lane % 4 == 2 { 'undef' } else { literal(c.source, lane_word(c.source, lane)) }; s.write_string(typ(c.source) + ' ' + value) }; s.write_string('>'); return s.str()
}
fn lane(c Case, j u64, index int, x u64) (int, u64) {
 if c.mode != 0 { if j >= u64(c.count) { return 1, 0 }; if j == u64(index) { return 0, x } }
 if c.form == 3 || (c.form == 1 && index % 4 == 2) { return 3, 0 }
 if c.form == 2 || (c.form == 1 && index % 4 == 1) { return 1, 0 }
 return 0, if c.form == 4 { u64(0) } else { lane_word(c.source, index) }
}
// 0 exact native bits, 1 poison, 2 explicit frozen zero, 3 strict undef.
fn expected(c Case, j u64, q u64, r u64, x u64, y u64) (int, u64) {
 for index in 0 .. c.count { state, _ := lane(c, j, index, x); if state == 3 && c.mode != 2 { return 3, 0 } }
 if r >= u64(c.count) { return 1, 0 }
 index := if c.mode == 4 { c.count - 1 - int(r) } else { int(r) }
 if c.mode == 4 && r % 2 == 0 { if q >= u64(c.count) { return 1, 0 }; if q == u64(index) { return 0, y } }
 state, word := lane(c, j, index, x)
 if state != 0 && c.mode in [2, 4] { return 2, 0 }
 return state, word
}
fn run_batch(assembler_path string, out string) ! {
 mut s := strings.new_builder(4194304); mut cases := []Case{}
 s.write_string('target datalayout = "e-p:64:64"\n')
 for source in [15, 64, 31, 65] { dest := if source == 15 { 64 } else if source == 64 { 15 } else if source == 31 { 65 } else { 31 }
  for count in 1 .. 17 { for form in 0 .. 5 { for mode in 0 .. 5 {
   c := Case{'case_${cases.len}', source, dest, count, form, mode}; cases << c
   src := typ(source); dst := typ(dest); width := bits(source)
   mut masks := []string{}; for index in 0 .. count { masks << 'i32 ${count - 1 - index + (index % 2) * count}' }
   selected := if mode == 3 { '%back' } else if mode == 4 { '%t' } else { '%n' }; result_type := if mode == 3 { src } else { dst }; result_element := if mode == 3 { source } else { dest }
   ops := '%a = insertelement <${count} x ${src}> ${vector(c)}, ${src} %x, i64 %j\n %fs = freeze <${count} x ${src}> ${if mode == 0 { vector(c) } else { '%a' }}\n %n = bitcast <${count} x ${src}> ${if mode == 2 { '%fs' } else if mode == 0 { vector(c) } else { '%a' }} to <${count} x ${dst}>\n %back = bitcast <${count} x ${dst}> %n to <${count} x ${src}>\n %f = freeze <${count} x ${dst}> %n\n %b = insertelement <${count} x ${dst}> %f, ${dst} %y, i64 %q\n %t = shufflevector <${count} x ${dst}> %b, <${count} x ${dst}> %f, <${count} x i32> <${masks.join(', ')}>\n %v = extractelement <${count} x ${result_type}> ${selected}, i64 %r\n' + if result_element >= 64 { ' %raw = bitcast ${result_type} %v to i${width}\n' } else { '' }
   value := if result_element >= 64 { '%raw' } else { '%v' }
   s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${src}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${dst}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i${width} ${value}, ptr %d, align 1\n ret void }\n')
   s.write_string('define i${width} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${src} %x, ${dst} %y) { ${ops}ret i${width} ${value} }\n')
   unsafe { masks.free() }
  } } }
 }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 native := native_module(data, out, ir)!; defer { native.close() }
 mut exact := 0; mut choices := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut budgets := 0; mut sweeps := 0
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); width := bits(c.source); bytes := width / 8; floating_result := if c.mode == 3 { c.source >= 64 } else { c.dest >= 64 }; scalar_steps := if floating_result { 10 } else { 9 }; steps := scalar_steps + 11
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == steps && profile.arguments[0].minimum_size == 24 && profile.arguments[1].minimum_size == 8 + bytes && profile.arguments[2].minimum_size == 8 + bytes; profile.free()
  address := C.LLVMGetFunctionAddress(native.engine, c.name.str); assert address != 0
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut reference := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  sweep := c.count == 16 && c.form == 4 && c.mode == 1
  edges := [u64(0), u64(c.count - 1), u64(c.count), ~u64(0), 1, 2, 3, u64(c.count + 1)]!
  for sample in 0 .. if sweep { 65536 } else { c.count + 2 } {
   j := if sweep { u64(sample % 16) } else { edges[(sample * 3) % 8] }; q := edges[(sample * 5 + 1) % 8]; r := if sweep { j } else { u64(sample) }
   x := if sweep { if width == 16 { u64(sample) } else { u64(u32(sample) * u32(0x9e3779b9)) } } else { lane_word(if width == 16 { 64 } else { 65 }, sample % 16) }; y := lane_word(if width == 16 { 64 } else { 65 }, (sample + 5) % 16)
   state, word := expected(c, j, q, r, x, y)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. bytes { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; reference[i] = 0xcc }
   args := [j, q, r, x | ~mask(width), y | ~mask(width)]
   if state == 3 { if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, scalar_steps) { panic('undef scalar bitcast') } else { assert err.msg() == 'AIR vector: undef bitcast lane', err.msg() } } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, scalar_steps)!; assert run.poison == (state == 1) && run.bits == width && run.steps == scalar_steps && (run.poison || run.value == word) }
   if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, scalar_steps) { panic('floating bitcast entered integer API') }; scalar += 2
   if state in [1, 3] { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps) { panic('indeterminate bitcast stored') } else { assert err.msg() == if state == 3 { 'AIR vector: undef bitcast lane' } else { 'AIR memory execution: poison store' }, err.msg() }; if state == 1 { poison++ } else { undef++ } } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps)!.steps == steps; if state == 0 { exact++ } else { choices++ } }
   for i, b in actual { assert b == if i == 3 { u8(17) } else if state in [0, 2] && i >= 11 && i < 11 + bytes { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${c.name} state=${state} j=${j} q=${q} r=${r} byte=${i}' }
   if state == 0 { unsafe { NativeCast(voidptr(address))(&indices[1], &input[1], &reference[3]) }; assert actual == reference, '${c.name} ${sample}' }
   if sweep { sweeps++ }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps - 1) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0], scalar_steps - 1) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 || p.types[op.result_type].kind != .vector_t { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 1}, airbitcode.IRTypedInstruction{...op, opcode: 9}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] { p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps) { panic('bitcast metadata admitted') }; unchanged(actual); metadata++ }; p.instructions[index] = op
   original := p.operands[op.operands_start]
   for changed in [airbitcode.IRTypedOperand{...original, number: 0}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: -1}] { p.operands[op.operands_start] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps) { panic('bitcast source admitted') }; unchanged(actual); metadata++ }; p.operands[op.operands_start] = original
  }; unsafe { indices.free(); input.free(); actual.free(); reference.free(); bs.free() }
 }
 assert cases.len == 1600 && scalar == (exact + choices + poison + undef) * 2 && metadata == 32000 && budgets == 3200 && sweeps == 262144
 os.write_file(out + '/result.txt', 'AIR-VECTOR-BITCAST: ${cases.len} shapes, every count 1-16 and four directions, five source forms and five constructions; ${exact} exact LLVM values including ${sweeps} exhaustive half/deterministic float sweep samples, ${choices} fixed-zero choices, ${poison} poison stores, ${undef} strict undef failures, ${scalar} scalar/integer checks, ${metadata} metadata/source and ${budgets} budgets PASS\n')!
}
fn controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(65536)
 s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['poison', 'undef', 'partial_poison', 'partial_undef', 'source_poison', 'source_undef', 'result_poison', 'result_undef', 'discard_poison', 'discard_undef', 'old', 'roundtrip', 'compose', 'isolation', 'prior_undef', 'index_undef']
 guards := ['argument', 'load', 'phi', 'coldwide', 'scalable', 'wide', 'double', 'bfloat', 'reshape', 'scalar_source', 'scalar_result', 'pointer', 'conversion']
 for source in [15, 64, 31, 65] {
  dest := if source == 15 { 64 } else if source == 64 { 15 } else if source == 31 { 65 } else { 31 }; src := typ(source); dst := typ(dest); width := bits(source); raw := lane_word(if width == 16 { 64 } else { 65 }, 4)
  for mode in modes {
   initial := if mode in ['poison', 'source_poison', 'result_poison', 'discard_poison'] { 'poison' } else if mode in ['undef', 'source_undef', 'result_undef', 'discard_undef', 'prior_undef'] { 'undef' } else if mode.starts_with('partial_') { '<${src} ${literal(source, raw)}, ${src} ${if mode == 'partial_undef' { 'undef' } else { 'poison' }}>' } else if mode == 'isolation' { '<${src} poison, ${src} ${literal(source, 1)}>' } else { '<${src} ${literal(source, raw)}, ${src} ${literal(source, 1)}>' }
   pre := if mode == 'prior_undef' { '%prior = extractelement <2 x ${src}> undef, i32 0\n' } else if mode == 'index_undef' { '%prior = insertelement <2 x ${src}> poison, ${src} zeroinitializer, i32 undef\n' } else if mode.starts_with('source_') { '%prior = freeze <2 x ${src}> ${initial}\n' } else { '' }
   operand := if mode.starts_with('source_') || mode == 'index_undef' { '%prior' } else { initial }
   mut post := if mode == 'old' { '%changed = insertelement <2 x ${dst}> %n, ${dst} zeroinitializer, i32 0\n' } else if mode.starts_with('result_') { '%f = freeze <2 x ${dst}> %n\n' } else if mode == 'roundtrip' { '%back = bitcast <2 x ${dst}> %n to <2 x ${src}>\n' } else { '' }
   if mode == 'compose' { fp := if dest >= 64 { dst } else { src }; post = if dest >= 64 { '' } else { '%fp = bitcast <2 x ${dst}> %n to <2 x ${src}>\n' }; post += '%neg = fneg <2 x ${fp}> ${if dest >= 64 { '%n' } else { '%fp' }}\n %words = bitcast <2 x ${fp}> %neg to <2 x i${width}>\n %cmp = icmp eq <2 x i${width}> %words, %words\n %selected = select <2 x i1> %cmp, <2 x i${width}> %words, <2 x i${width}> zeroinitializer\n' }
   result_element := if mode == 'compose' { width - 1 } else if mode == 'roundtrip' { source } else { dest }; t := typ(result_element)
   selected := if mode == 'compose' { '%selected' } else if mode == 'roundtrip' { '%back' } else if mode.starts_with('result_') { '%f' } else { '%n' }
   store := if mode.starts_with('discard_') { '' } else { '%v = extractelement <2 x ${t}> ${selected}, i32 ${if mode == 'isolation' { 1 } else { 0 }}\n' + if result_element >= 64 { '%raw = bitcast ${t} %v to i${width}\n' } else { '' } + '%d = getelementptr i8, ptr %out, i64 8\n store i${width} %${if result_element >= 64 { 'raw' } else { 'v' }}, ptr %d, align 1\n' }
   s.write_string('define void @${mode}_${source}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%n = bitcast <2 x ${src}> ${operand} to <2 x ${dst}>\n ${post}${store}ret void }\n')
  }
  s.write_string('define i32 @loop_${source}(i32 %limit) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %small = trunc i32 %i to i16\n ${if source >= 64 { '%x = bitcast i${width} ${if width == 16 { '%small' } else { '%i' }} to ${src}\n' } else { '' }}%a = insertelement <2 x ${src}> poison, ${src} ${if source >= 64 { '%x' } else if width == 16 { '%small' } else { '%i' }}, i32 0\n %n = bitcast <2 x ${src}> %a to <2 x ${dst}>\n %back = bitcast <2 x ${dst}> %n to <2 x ${src}>\n %f = freeze <2 x ${src}> %back\n %v = extractelement <2 x ${src}> %f, i32 0\n ${if source >= 64 { '%raw = bitcast ${src} %v to i${width}\n' } else { '' }}%wide = zext i${width} %${if source >= 64 { 'raw' } else { 'v' }} to i64\n %word = trunc i64 %wide to i32\n %added = add i32 %sum, %word\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i32 %added }\n')
 }
 for guard in guards {
  signature := if guard == 'argument' { '<2 x i16> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
  body := match guard {
   'argument' { '%n = bitcast <2 x i16> %v to <2 x half>' }
   'load' { '%v = load volatile <2 x i16>, ptr %src\n %n = bitcast <2 x i16> %v to <2 x half>' }
   'phi' { 'br label %body\n body: %v = phi <2 x i16> [zeroinitializer, %entry]\n %n = bitcast <2 x i16> %v to <2 x half>' }
   'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold: %n = bitcast <17 x i16> zeroinitializer to <17 x half>' }
   'scalable' { '%n = bitcast <vscale x 2 x i16> zeroinitializer to <vscale x 2 x half>' }
   'wide' { '%n = bitcast <17 x i32> zeroinitializer to <17 x float>' }
   'double' { '%n = bitcast <2 x i64> zeroinitializer to <2 x double>' }
   'bfloat' { '%n = bitcast <2 x i16> zeroinitializer to <2 x bfloat>' }
   'reshape' { '%n = bitcast <4 x i8> zeroinitializer to <2 x bfloat>' }
   'scalar_source' { '%n = bitcast i128 0 to <2 x i64>' }
   'scalar_result' { '%n = bitcast <2 x i64> zeroinitializer to i128' }
   'pointer' { '%n = ptrtoint <2 x ptr> zeroinitializer to <2 x i64>' }
   else { '%n = fptosi <2 x double> zeroinitializer to <2 x i32>' }
  }
  s.write_string('define void @guard_${guard}(${signature}) { entry: store i8 17, ptr %out, align 1\n ${body}\n ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut checks := 0
 for source in [15, 64, 31, 65] {
  width := bits(source); raw := lane_word(if width == 16 { 64 } else { 65 }, 4)
  for mode in modes {
   mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
   profile := p.memory_function_profile(ir, stream, pools, bodies, fi(ir, '${mode}_${source}'))!; profile.free()
   bad := mode in ['poison', 'undef', 'partial_undef', 'result_undef', 'discard_undef', 'prior_undef', 'index_undef']
   if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, '${mode}_${source}'), mut bs, 100) { panic('indeterminate bitcast accepted: ' + mode) } else { assert if mode == 'poison' { err.msg() == 'AIR memory execution: poison store' } else { err.msg().contains('undef') }, err.msg() } } else { p.run_memory_function(ir, stream, pools, bodies, fi(ir, '${mode}_${source}'), mut bs, 100)! }
   word := if mode.starts_with('source_') || mode == 'result_poison' { u64(0) } else if mode == 'isolation' { u64(1) } else if mode == 'compose' { raw ^ (u64(1) << u32(width - 1)) } else { raw }
   for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + width / 8 { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${mode}_${source} byte=${i}' }; checks++; unsafe { output.free(); bs.free() }
  }
  for count in [u64(1), 2, 3, 16, 257, 513]! { steps := int(count * if source >= 64 { 16 } else { 14 } + 2); run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop_${source}'), [count], steps)!; assert !run.poison && run.value == count * (count - 1) / 2 && run.steps == steps; checks++ }
  function := fi(ir, 'roundtrip_${source}'); scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 || p.types[op.result_type].kind != .vector_t { continue }
   ref := p.references[p.types[op.result_type].refs_start]; original := p.types[ref]
   // Equal-width integer bitcasts are supported. Keep this mutation invalid
   // with unequal total widths, including floating-to-floating casts.
   same_category := if source < 64 { airbitcode.IRType{...original, kind: .integer_t, bits: u32(width + 1)} } else { airbitcode.IRType{...original, kind: if width == 16 { .float_t } else { .half_t }} }
   wrong_width := if source < 64 { airbitcode.IRType{...original, kind: if width == 16 { .float_t } else { .half_t }} } else { airbitcode.IRType{...original, bits: if width == 16 { u32(32) } else { u32(16) }} }
   for variant, changed in [same_category, wrong_width, airbitcode.IRType{...original, kind: .double_t}, airbitcode.IRType{...original, kind: .bfloat_t}, airbitcode.IRType{...original, kind: .pointer_t}] {
    p.types[ref] = changed; mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]
    if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 100) { panic('bitcast lane type mutation admitted') } else { if variant < 2 { assert err.msg() == if variant == 0 && source < 64 { 'AIR vector: integer bitcast shape' } else { 'AIR vector: integer/floating bitcast shape' }, err.msg() } }; unchanged(output); checks++; unsafe { output.free(); bs.free() }
   }; p.types[ref] = original; break
  }
 }
 for guard in guards { mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }; if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100) { panic('unsupported bitcast profile: ' + guard) }; unchanged(output); checks++; unsafe { output.free(); bs.free() } }
 assert checks == 121
 os.write_file(out + '/result.txt', 'AIR-VECTOR-BITCAST-CONTROLS: ${checks} source/result freezes, discards, old snapshots, round trips, fneg/comparison/select composition, poison isolation, loop slot reuse and unsupported profiles PASS\n')!
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } { count := if storage { 1 } else { 16 }; s.write_string('%v${i} = bitcast <${count} x i16> zeroinitializer to <${count} x half>\n') }
  if !storage { for i in 0 .. if over { 54309 } else { 54308 } { s.write_string('%x${i} = extractelement <16 x half> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory bitcast limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('void bitcast limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 58406 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 58405 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len in [3, 4]; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 if os.args.len == 4 { controls(os.args[1], out + '/controls')!; print(os.read_file(out + '/controls/result.txt')!); return }
 run_batch(os.args[1], out + '/batch')!
 controls(os.args[1], out + '/controls')!
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 result := os.read_file(out + '/batch/result.txt')!; os.write_file(out + '/result.txt', result)!; print(result)
}
