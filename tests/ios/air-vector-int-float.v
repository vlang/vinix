// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
#include <fenv.h>
fn C.fesetenv(voidptr) int
fn C.fesetround(int) int
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-int-float'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Shape { name string source int dest int count int opcode int }
fn fp(width int) string { return if width == 16 { 'half' } else { 'float' } }
fn word(width int, sample int) u64 { return [u64(0), 1, mask(width), u64(1) << u32(width - 1), (u64(1) << u32(width - 1)) - 1, (u64(1) << u32(width - 1)) + 1, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]![sample % 8] & mask(width) }
fn vector(c Shape) string { mut s := strings.new_builder(512); s.write_string('<'); for lane in 0 .. c.count { if lane != 0 { s.write_string(', ') }; s.write_string('i${c.source} ${word(c.source, lane)}') }; s.write_string('>'); return s.str() }
fn samples(width int, dest int) []u64 {
 mut values := []u64{}
 for i in 0 .. 8 { values << word(width, i) }
 for x in [u64(65519), 65520, 65521]! { values << x & mask(width); values << (u64(0) - x) & mask(width) }
 fraction := if dest == 16 { 10 } else { 23 }
 for exponent in fraction + 1 .. width {
  base := u64(1) << u32(exponent); step := u64(1) << u32(exponent - fraction)
  for odd in 0 .. 2 { midpoint := base + u64(odd) * step + step / 2; for x in [midpoint - 1, midpoint, midpoint + 1]! { values << x & mask(width); values << (u64(0) - x) & mask(width) } }
 }
 mut seed := u64(0x9e3779b97f4a7c15)
 for _ in 0 .. 128 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; values << seed & mask(width) }
 return values
}
// Native execution is used only for state 0. State 1 is poison; state 2 is
// the interpreter's permitted fixed-zero freeze choice.
fn state(c Shape, j u64, q u64, r u64, raw bool) int {
 if r >= u64(c.count) { return 1 }
 if !raw && r % 2 == 0 { if q >= u64(c.count) { return 1 }; if q == u64(c.count - 1 - int(r)) { return 0 } }
 if j >= u64(c.count) { return if raw { 1 } else { 2 } }
 return 0
}
fn run_batch(assembler_path string, out string, width int) !string {
 mut s := strings.new_builder(65536); mut cases := []Shape{}; s.write_string('target datalayout = "e-p:64:64"\n')
 for dest in [16, 32] { for opcode in [5, 6] { for count in [1, 3, 16] {
  c := Shape{'case_${cases.len}', width, dest, count, opcode}; cases << c; t := fp(dest)
  mut indices := []string{}; for lane in 0 .. count { indices << 'i32 ${count - 1 - lane + (lane % 2) * count}' }
  ops := '%a = insertelement <${count} x i${width}> ${vector(c)}, i${width} %x, i64 %j\n %n = ${if opcode == 5 { 'uitofp' } else { 'sitofp' }} <${count} x i${width}> %a to <${count} x ${t}>\n %f = freeze <${count} x ${t}> %n\n %fy = bitcast i${dest} %y to ${t}\n %u = insertelement <${count} x ${t}> %f, ${t} %fy, i64 %q\n %t = shufflevector <${count} x ${t}> %u, <${count} x ${t}> %f, <${count} x i32> <${indices.join(', ')}>\n %s = select i1 %raw, <${count} x ${t}> %n, <${count} x ${t}> %t\n %v = extractelement <${count} x ${t}> %s, i64 %r\n %bits = bitcast ${t} %v to i${dest}\n'
  s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %cp = getelementptr i8, ptr %indices, i64 24\n %raw = load i1, ptr %cp, align 1\n %x = load i${width}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load i${dest}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i${dest} %bits, ptr %d, align 1\n ret void }\n')
  s.write_string('define i${dest} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, i${width} %x, i${dest} %y, i1 %raw) { ${ops}ret i${dest} %bits }\n'); unsafe { indices.free() }
 } } }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 native := native_module(data, out, ir)!; defer { native.close() }
 mut compared := 0; mut choices := 0; mut poison := 0; mut scalar := 0; mut metadata := 0; mut budgets := 0; mut exhaustive := 0; mut wide_samples := 0
 mut runtime_rows := strings.new_builder(8192)
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); bytes := c.dest / 8
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 23 && profile.arguments[0].minimum_size == 25 && profile.arguments[1].minimum_size == 8 + bytes && profile.arguments[2].minimum_size == 8 + bytes; profile.free()
  address := C.LLVMGetFunctionAddress(native.engine, c.name.str); assert address != 0
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut reference := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), 1, 2, u64(c.count), ~u64(0), 0, u64(c.count - 1)]!; values := samples(width, c.dest)
  for raw in [false, true] {
   sweep := raw && c.count == 16
   count := if sweep { if width <= 16 { 1 << width } else { values.len } } else { 8 }
   for sample in 0 .. count {
    j := if sweep { u64(sample % 16) } else { edges[(sample * 3) % 8] }; q := edges[(sample * 5 + 1) % 8]; r := if sweep { j } else { edges[sample % 8] }
    x := if sweep { if width <= 16 { u64(sample) } else { values[sample] } } else { word(width, sample + c.dest) }; y := word(c.dest, sample + width); kind := state(c, j, q, r, raw)
    for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; indices[25] = u8(raw)
    // Give native narrow loads canonical padding; separately exercise the
    // interpreter's masking with nonzero unused bits below.
    for i in 0 .. (width + 7) / 8 { input[1 + i] = u8(x >> u32(i * 8)) }; for i in 0 .. bytes { input[9 + i] = u8(y >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; reference[i] = 0xcc }
    mut expected := u64(0)
    if kind == 0 { unsafe { NativeCast(voidptr(address))(&indices[1], &input[1], &reference[3]) }; for i in 0 .. bytes { expected |= u64(reference[11 + i]) << u32(i * 8) }; compared++ } else if kind == 1 { poison++ } else { choices++ }
    if kind == 0 && sweep { for edge in 0 .. 8 { if x == word(width, edge) { runtime_rows.writeln('${width}\t${c.dest}\t${c.opcode}\t${edge}\t${x}\t${expected}') } } }
    for i in 0 .. (width + 7) / 8 { input[1 + i] = u8((x | ~mask(width)) >> u32(i * 8)) }
    args := [j, q, r, x | ~mask(width), y | ~mask(c.dest), u64(raw)]
    run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 10)!; assert run.poison == (kind == 1) && run.bits == c.dest && run.steps == 10 && (run.poison || run.value == expected), 'width=${width} dest=${c.dest} opcode=${c.opcode} count=${c.count} raw=${raw} sample=${sample} state=${kind} expected=${expected} run=${run}'
    if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 10) { panic('floating vector entered integer-only API') }; scalar += 2
    if kind == 1 { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 23) { panic('poison cast stored') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 23)!.steps == 23 }
    for i, b in actual { assert b == if i == 3 { u8(17) } else if kind != 1 && i >= 11 && i < 11 + bytes { u8(expected >> u32((i - 11) * 8)) } else { u8(0xcc) }, 'i${width} ${c.dest} ${c.opcode} ${c.count} raw=${raw} sample=${sample} byte=${i}' }
    if kind == 0 { assert actual == reference }; if sweep { if width <= 16 { exhaustive++ } else { wide_samples++ } }; unsafe { args.free() }
   }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 22) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0, 1], 9) { panic('short scalar budget') }; budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 || p.types[op.result_type].kind != .vector_t { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 4}, airbitcode.IRTypedInstruction{...op, opcode: 9}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] { p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 23) { panic('conversion metadata admitted') }; unchanged(actual); metadata++ }; p.instructions[index] = op
   original := p.operands[op.operands_start]
   for changed in [airbitcode.IRTypedOperand{...original, number: 0}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: -1}] { p.operands[op.operands_start] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 23) { panic('conversion source admitted') }; unchanged(actual); metadata++ }; p.operands[op.operands_start] = original
  }; unsafe { indices.free(); input.free(); actual.free(); reference.free(); bs.free(); values.free() }
 }
 assert metadata == 120 && budgets == 24 && scalar == (compared + choices + poison) * 2
 os.write_file(out + '/runtime-values.tsv', runtime_rows.str())!
 return '${compared} ${choices} ${poison} ${scalar} ${metadata} ${budgets} ${exhaustive} ${wide_samples}'
}
fn one(width int, dest int, opcode int) u64 { return if dest == 16 { if width == 1 && opcode == 6 { u64(0xbc00) } else { u64(0x3c00) } } else { if width == 1 && opcode == 6 { u64(0xbf800000) } else { u64(0x3f800000) } } }
fn controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(262144); s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['literal', 'poison', 'undef', 'partial_poison', 'partial_undef', 'source_poison', 'source_undef', 'result_poison', 'result_undef', 'discard_poison', 'discard_undef', 'old', 'compose', 'isolation', 'prior_undef', 'index_undef']
 for width in [1, 2, 8, 16, 31, 32, 64] { for dest in [16, 32] { for opcode in [5, 6] {
  t := fp(dest); operation := if opcode == 5 { 'uitofp' } else { 'sitofp' }
  for mode in modes {
   initial := if mode in ['poison', 'source_poison', 'result_poison', 'discard_poison'] { 'poison' } else if mode in ['undef', 'source_undef', 'result_undef', 'discard_undef', 'prior_undef'] { 'undef' } else if mode.starts_with('partial_') { '<i${width} 1, i${width} ${if mode == 'partial_undef' { 'undef' } else { 'poison' }}>' } else if mode == 'isolation' { '<i${width} poison, i${width} 1>' } else { '<i${width} 1, i${width} 0>' }
   pre := if mode == 'prior_undef' { '%prior = extractelement <2 x i${width}> undef, i32 0\n' } else if mode == 'index_undef' { '%prior = insertelement <2 x i${width}> poison, i${width} 0, i32 undef\n' } else if mode.starts_with('source_') { '%prior = freeze <2 x i${width}> ${initial}\n' } else { '' }
   operand := if mode.starts_with('source_') || mode == 'index_undef' { '%prior' } else { initial }
   post := if mode == 'old' { '%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n' } else if mode.starts_with('result_') { '%f = freeze <2 x ${t}> %n\n' } else if mode == 'compose' { '%neg = fneg <2 x ${t}> %n\n %words = bitcast <2 x ${t}> %neg to <2 x i${dest}>\n %cmp = icmp eq <2 x i${dest}> %words, %words\n %selected = select <2 x i1> %cmp, <2 x i${dest}> %words, <2 x i${dest}> zeroinitializer\n' } else { '' }
   selected := if mode == 'compose' { '%selected' } else if mode.starts_with('result_') { '%f' } else { '%n' }; result_type := if mode == 'compose' { 'i${dest}' } else { t }
   store := if mode.starts_with('discard_') { '' } else { '%v = extractelement <2 x ${result_type}> ${selected}, i32 ${if mode == 'isolation' { 1 } else { 0 }}\n' + if mode != 'compose' { '%raw = bitcast ${t} %v to i${dest}\n' } else { '' } + '%d = getelementptr i8, ptr %out, i64 8\n store i${dest} %${if mode == 'compose' { 'v' } else { 'raw' }}, ptr %d, align 1\n' }
   s.write_string('define void @${mode}_${width}_${dest}_${opcode}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%n = ${operation} <2 x i${width}> ${operand} to <2 x ${t}>\n ${post}${store}ret void }\n')
  }
  s.write_string('define i${dest} @constant_${width}_${dest}_${opcode}() { %n = ${operation} <1 x i${width}> <i${width} 1> to <1 x ${t}>\n %v = extractelement <1 x ${t}> %n, i32 0\n %bits = bitcast ${t} %v to i${dest}\n ret i${dest} %bits }\n')
 } } }
 for dest in [16, 32] { for opcode in [5, 6] {
  t := fp(dest); operation := if opcode == 5 { 'uitofp' } else { 'sitofp' }
  for flag in ['nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast'] { s.write_string('define void @flag_${dest}_${opcode}_${flag}(ptr %out) { store i8 17, ptr %out\n %n = ${operation} ${flag} <2 x i32> zeroinitializer to <2 x ${t}>\n ret void }\n') }
  s.write_string('define i64 @loop_${dest}_${opcode}(i64 %limit) { entry: br label %body\n body: %i = phi i64 [0, %entry], [%next, %body]\n %sum = phi i64 [0, %entry], [%added, %body]\n %a = insertelement <2 x i64> poison, i64 %i, i32 0\n %n = ${operation} <2 x i64> %a to <2 x ${t}>\n %f = freeze <2 x ${t}> %n\n %v = extractelement <2 x ${t}> %f, i32 0\n %back = fptoui ${t} %v to i64\n %added = add i64 %sum, %back\n %next = add i64 %i, 1\n %c = icmp ult i64 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i64 %added }\n')
  s.write_string('define i${dest} @round_${dest}_${opcode}(i64 %x) { %a = insertelement <1 x i64> zeroinitializer, i64 %x, i32 0\n %n = ${operation} <1 x i64> %a to <1 x ${t}>\n %v = extractelement <1 x ${t}> %n, i32 0\n %bits = bitcast ${t} %v to i${dest}\n ret i${dest} %bits }\n')
 } }
 guards := ['argument', 'load', 'phi', 'coldwide', 'scalable', 'wideint', 'double', 'bfloat', 'fptosi', 'fptoui', 'reshape', 'scalar_source', 'scalar_result', 'nneg']
 for guard in guards {
  signature := if guard == 'argument' { '<2 x i32> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
  body := match guard {
   'argument' { '%n = uitofp <2 x i32> %v to <2 x float>' }
   'load' { '%v = load volatile <2 x i32>, ptr %src\n %n = sitofp <2 x i32> %v to <2 x half>' }
   'phi' { 'br label %body\n body: %v = phi <2 x i32> [zeroinitializer, %entry]\n %n = uitofp <2 x i32> %v to <2 x float>' }
   'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold: %n = sitofp <17 x i32> zeroinitializer to <17 x float>' }
   'scalable' { '%n = uitofp <vscale x 2 x i32> zeroinitializer to <vscale x 2 x float>' }
   'wideint' { '%n = sitofp <2 x i65> zeroinitializer to <2 x float>' }
   'double' { '%n = uitofp <2 x i64> zeroinitializer to <2 x double>' }
   'bfloat' { '%n = sitofp <2 x i16> zeroinitializer to <2 x bfloat>' }
   'fptosi' { '%n = fptosi <2 x double> zeroinitializer to <2 x i32>' }
   'fptoui' { '%n = fptoui <2 x bfloat> zeroinitializer to <2 x i64>' }
   'reshape' { '%n = bitcast <2 x float> zeroinitializer to <4 x bfloat>' }
   'scalar_source' { '%n = bitcast i128 0 to <2 x i64>' }
   'scalar_result' { '%n = bitcast <2 x i64> zeroinitializer to i128' }
   else { '%n = uitofp nneg <2 x i32> zeroinitializer to <2 x float>' }
  }; s.write_string('define void @guard_${guard}(${signature}) { entry: store i8 17, ptr %out, align 1\n ${body}\n ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut checks := 0
 for width in [1, 2, 8, 16, 31, 32, 64] { for dest in [16, 32] { for opcode in [5, 6] {
  for mode in modes {
   function := fi(ir, '${mode}_${width}_${dest}_${opcode}'); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; profile.free()
   mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
   bad := mode in ['poison', 'undef', 'partial_undef', 'result_undef', 'discard_undef', 'prior_undef', 'index_undef']
   if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 100) { panic('conversion control accepted: ' + mode) } else { assert if mode == 'poison' { err.msg() == 'AIR memory execution: poison store' } else { err.msg().contains('undef') }, err.msg() } } else { p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 100)! }
   value := if mode.starts_with('source_') || mode == 'result_poison' { u64(0) } else if mode == 'compose' { one(width, dest, opcode) ^ (u64(1) << u32(dest - 1)) } else { one(width, dest, opcode) }
   for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + dest / 8 { u8(value >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${width} ${dest} ${opcode} ${mode} byte=${i}' }; checks++; unsafe { output.free(); bs.free() }
  }
  function := fi(ir, 'constant_${width}_${dest}_${opcode}'); run := p.run_scalar_function(ir, stream, pools, bodies, function, [], 4)!; assert !run.poison && run.bits == dest && run.value == one(width, dest, opcode) && run.steps == 4; if _ := p.run_integer_function(ir, stream, pools, bodies, function, [], 4) { panic('constant floating vector entered integer API') }; checks += 2
 } } }
 for dest in [16, 32] { for opcode in [5, 6] {
  for count in [u64(1), 2, 3, 16, 257, 513]! { run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop_${dest}_${opcode}'), [count], int(count * 11 + 2))!; assert !run.poison && run.value == count * (count - 1) / 2 && run.steps == int(count * 11 + 2); checks++ }
  for flag in ['nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast'] { mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'flag_${dest}_${opcode}_${flag}'), mut bs, 100) { panic('conversion flags admitted') }; unchanged(output); checks++; unsafe { output.free(); bs.free() } }
 } }
 for guard in guards { mut output := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }; if guard == 'phi' { p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100)!; for i, b in output { assert b == if i == 0 { u8(17) } else { u8(0xcc) } } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100) { panic('unsupported conversion profile: ' + guard) }; unchanged(output) }; checks++; unsafe { output.free(); bs.free() } }
 for rounding in [C.FE_UPWARD, C.FE_DOWNWARD] { assert C.fesetround(rounding) == 0; for dest in [16, 32] { for opcode in [5, 6] { for odd in 0 .. 2 { value := if dest == 16 { u64(2049 + 2 * odd) } else { u64(16777217 + 2 * odd) }; expected := if dest == 16 { u64(0x6800 + 2 * odd) } else { u64(0x4b800000 + 2 * odd) }; run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'round_${dest}_${opcode}'), [value], 5)!; assert !run.poison && run.value == expected && run.steps == 5; checks++ } } } }; assert C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) == 0
 assert checks == 590
 os.write_file(out + '/result.txt', 'AIR-VECTOR-INT-FLOAT-CONTROLS: ${checks} literal/poison/undef, source/result freezing, discards, snapshots, fneg/bitcast/comparison/select composition, integer-only API rejection, loops, flags/profiles and host-rounding controls PASS\n')!
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } { count := if storage { 1 } else { 16 }; s.write_string('%v${i} = uitofp <${count} x i64> zeroinitializer to <${count} x float>\n') }
  if !storage { for i in 0 .. if over { 54309 } else { 54308 } { s.write_string('%x${i} = extractelement <16 x float> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory cast limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('void cast limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 58406 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 58405 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) == 0
 assert os.args.len in [3, 4]; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 if os.args.len == 4 { controls(os.args[1], out + '/controls')!; print(os.read_file(out + '/controls/result.txt')!); return }
 mut totals := [u64(0), 0, 0, 0, 0, 0, 0, 0]!
 for width in 1 .. 65 { fields := run_batch(os.args[1], out + '/batch-${width}', width)!.split(' '); assert fields.len == 8; for i, field in fields { totals[i] += field.u64() } }
 controls(os.args[1], out + '/controls')!; for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 assert totals[4] == 7680 && totals[5] == 1536 && totals[6] == 524280
 result := 'AIR-VECTOR-INT-FLOAT: 768 shapes across i1-i64, half/float, both signs and 1/3/16 lanes; ${totals[0]} exact LLVM comparisons, ${totals[1]} frozen zero choices, ${totals[2]} poison stores preserving earlier writes, ${totals[3]} scalar/integer checks, ${totals[4]} metadata/source, ${totals[5]} budgets, ${totals[6]} exhaustive i1-i16 samples and ${totals[7]} wide rounding/boundary/random samples PASS\n'
 os.write_file(out + '/result.txt', result)!; print(result)
}
