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
type NativeCast = fn (u64) u64
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn fi(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic(name) }
fn unchanged(bytes []u8) { for b in bytes { assert b == 0xcc } }
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-float-int'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('native_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Shape { name string source int dest int count int opcode int }
struct Counts {
mut:
 values int
 poison int
 choices int
 scalar int
 metadata int
 budgets int
 exhaustive int
 wide int
 corruptions int
}
fn fp(width int) string { return if width == 16 { 'half' } else { 'float' } }
fn word(source int, sample int) u64 {
 if source == 16 { return [u64(0), 0x8000, 0x3800, 0xb800, 0x3c00, 0xbc00, 0x3e00, 0xbe00, 0x5bfc, 0x5c00, 0x7bff, 0xfbff, 0x7c00, 0xfc00, 0x7e55, 0x7c01]![sample % 16] }
 return [u64(0), 0x80000000, 0x3f000000, 0xbf000000, 0x3f800000, 0xbf800000, 0x3fc00000, 0xbfc00000, 0x5f7fffff, 0x5f800000, 0x5effffff, 0xdf000000, 0x7f800000, 0xff800000, 0x7fc12345, 0x7f800001]![sample % 16]
}
fn samples(source int, width int) []u64 {
 mut values := []u64{}
 for i in 0 .. 16 { values << word(source, i) }
 for exponent in [width, width - 1] {
  base := if source == 16 { if exponent < 16 { u32(exponent + 15) << 10 } else { u32(0x7c00) } } else { u32(exponent + 127) << 23 }
  for sign in [u32(0), if source == 16 { u32(0x8000) } else { u32(0x80000000) }] { for raw in [base - 1, base, base + 1] { values << u64(raw | sign) } }
  fraction := if source == 16 { 10 } else { 23 }
  if exponent <= fraction { unit := base + (u32(1) << u32(fraction - exponent)); for raw in [unit - 1, unit, unit + 1] { values << u64(raw | if source == 16 { u32(0x8000) } else { u32(0x80000000) }) } }
 }
 if source == 32 { for raw in [u64(1), 0x80000001, 0x7fffff, 0x800000, 0x3f7fffff, 0xbf7fffff, 0xbf800001, 0xc3008000, 0xc3010000, 0x437f8000, 0x43800000, 0x7f7fffff, 0xff7fffff, 0xff800001] { values << raw } }
 mut seed := u64(0x9e3779b97f4a7c15)
 for _ in 0 .. 128 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; values << seed & mask(source) }
 return values
}
// The native projection contains only defined saturation and range predicates.
// Truncate as float before the predicates, including fractional signed minima.
fn oracle_fixture(mut s strings.Builder, source int, width int, opcode int) {
 t := fp(source); name := '${source}_${width}_${opcode}'; op := if opcode == 3 { 'fptoui' } else { 'fptosi' }
 pre := '%raw = trunc i64 %input to i${source}\n %x = bitcast i${source} %raw to ${t}\n' + if source == 16 { '%v = fpext half %x to float\n' } else { '' }
 value := if source == 16 { '%v' } else { '%x' }; bound := u32(if opcode == 3 { width + 127 } else { width + 126 }) << 23
 s.write_string('define i64 @native_value_${name}(i64 %input) { ${pre}%wide = call i64 @llvm.${op}.sat.i64.f32(float ${value})\n')
 if width == 64 { s.write_string('ret i64 %wide }\n') } else { s.write_string('%small = trunc i64 %wide to i${width}\n %out = zext i${width} %small to i64\n ret i64 %out }\n') }
 s.write_string('define i64 @native_poison_${name}(i64 %input) { ${pre}%t = call float @llvm.trunc.f32(float ${value})\n %bound = bitcast i32 ${bound} to float\n')
 if opcode == 4 { s.write_string('%lower = fneg float %bound\n') }
 s.write_string('%low = fcmp olt float %t, ${if opcode == 4 { '%lower' } else { '0.0' }}\n %high = fcmp oge float %t, %bound\n %nan = fcmp uno float ${value}, ${value}\n %range = or i1 %low, %high\n %bad = or i1 %range, %nan\n %tag = zext i1 %bad to i64\n ret i64 %tag }\n')
}
// kind 0 is defined, kind 1 poison, kind 2 the explicit zero freeze choice.
fn expected(c Shape, j u64, q u64, r u64, raw bool, x u64, y u64, value NativeCast, tag NativeCast) (int, u64) {
 if r >= u64(c.count) { return 1, 0 }
 index := if raw { r } else { u64(c.count - 1) - r }
 if !raw && r % 2 == 0 { if q >= u64(c.count) { return 1, 0 }; if q == index { return 0, y & mask(c.dest) } }
 if j >= u64(c.count) { return if raw { 1 } else { 2 }, 0 }
 if j != index { return 0, 0 }
 if tag(x) != 0 { return if raw { 1 } else { 2 }, 0 }
 return 0, value(x)
}
fn matches(run airbitcode.IRScalarRun, width int, kind int, value u64) bool {
 return run.kind == .integer && run.bits == width && run.steps == 9 && run.poison == (kind == 1) && (run.poison || run.value == value)
}
fn run_batch(assembler_path string, out string, width int) !Counts {
 mut s := strings.new_builder(65536); mut cases := []Shape{}
 s.write_string('target datalayout = "e-p:64:64"\ndeclare float @llvm.trunc.f32(float)\ndeclare i64 @llvm.fptoui.sat.i64.f32(float)\ndeclare i64 @llvm.fptosi.sat.i64.f32(float)\n')
 for source in [16, 32] { for opcode in [3, 4] {
  oracle_fixture(mut s, source, width, opcode)
  for count in [1, 3, 16] {
   c := Shape{'case_${cases.len}', source, width, count, opcode}; cases << c; t := fp(source)
   mut indices := []string{}; for lane in 0 .. count { indices << 'i32 ${count - 1 - lane + (lane % 2) * count}' }
   ops := '%x = bitcast i${source} %input to ${t}\n %a = insertelement <${count} x ${t}> zeroinitializer, ${t} %x, i64 %j\n %n = ${if opcode == 3 { 'fptoui' } else { 'fptosi' }} <${count} x ${t}> %a to <${count} x i${width}>\n %f = freeze <${count} x i${width}> %n\n %u = insertelement <${count} x i${width}> %f, i${width} %y, i64 %q\n %t = shufflevector <${count} x i${width}> %u, <${count} x i${width}> %f, <${count} x i32> <${indices.join(', ')}>\n %s = select i1 %raw, <${count} x i${width}> %n, <${count} x i${width}> %t\n %v = extractelement <${count} x i${width}> %s, i64 %r\n'
   s.write_string('define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %cp = getelementptr i8, ptr %indices, i64 24\n %raw = load i1, ptr %cp, align 1\n %input = load i${source}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load i${width}, ptr %yp, align 1\n store i8 17, ptr %out, align 1\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i${width} %v, ptr %d, align 1\n ret void }\n')
   s.write_string('define i${width} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, i${source} %input, i${width} %y, i1 %raw) { ${ops}ret i${width} %v }\n'); unsafe { indices.free() }
  }
 } }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 native := native_module(data, out, ir)!; defer { native.close() }
 mut counts := Counts{}; mut runtime := strings.new_builder(8192)
 mut good := airbitcode.IRScalarRun{}; mut bad := airbitcode.IRScalarRun{}; mut good_value := u64(0); mut have_good := false; mut have_bad := false
 mut rows := os.create(out + '/comparisons.tsv')!; defer { rows.close() }; rows.writeln('source\tdest\topcode\tlanes\traw\tsample\tx\tkind\texpected\tactual\tpoison\tsteps')!
 for c in cases {
  name := '${c.source}_${width}_${c.opcode}'; vn := 'native_value_' + name; pn := 'native_poison_' + name
  va := C.LLVMGetFunctionAddress(native.engine, vn.str); pa := C.LLVMGetFunctionAddress(native.engine, pn.str); assert va != 0 && pa != 0
  value := unsafe { NativeCast(voidptr(va)) }; tag := unsafe { NativeCast(voidptr(pa)) }
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); bytes := (width + 7) / 8
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == 22 && profile.arguments[0].minimum_size == 25 && profile.arguments[1].minimum_size == 8 + bytes && profile.arguments[2].minimum_size == 8 + bytes; profile.free()
  mut indices := []u8{len: 32}; mut input := []u8{len: 24}; mut actual := []u8{len: 24, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  edges := [u64(0), u64(c.count - 1), 1, 2, u64(c.count), ~u64(0), 0, u64(c.count - 1)]!; values := samples(c.source, width)
  for raw in [false, true] {
   sweep := raw && c.count == 16; exhaustive := sweep && c.source == 16 && width in [1, 8, 16, 32, 64]
   count := if exhaustive { 65536 } else if sweep { values.len } else { 16 }
   for sample in 0 .. count {
    j := if sweep { u64(sample % 16) } else { edges[(sample * 3) % 8] }; q := edges[(sample * 5 + 1) % 8]; r := if sweep { j } else { edges[sample % 8] }
    x := if exhaustive { u64(sample) } else if sweep { values[sample] } else { word(c.source, sample) }; y := (u64(sample) * u64(0x9e3779b97f4a7c15)) & mask(width)
    kind, wanted := expected(c, j, q, r, raw, x, y, value, tag)
    for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; indices[25] = u8(raw)
    for i in 0 .. c.source / 8 { input[1 + i] = u8(x >> u32(i * 8)) }; for i in 0 .. bytes { input[9 + i] = u8((y | ~mask(width)) >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc }
    args := [j, q, r, x | ~mask(c.source), y | ~mask(width), u64(raw)]
    run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, 9)!; assert matches(run, width, kind, wanted), '${c} raw=${raw} sample=${sample} x=${x} kind=${kind} wanted=${wanted} run=${run}'
    if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, 9) { panic('floating source entered integer-only API') }; counts.scalar += 2
    if kind == 1 { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 22) { panic('poison conversion stored') } else { assert err.msg() == 'AIR memory execution: poison store', err.msg() }; counts.poison++; if !have_bad { bad = run; have_bad = true } } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 22)!.steps == 22; if kind == 2 { counts.choices++ } else { counts.values++; if !have_good { good = run; good_value = wanted; have_good = true } } }
    for i, b in actual { assert b == if i == 3 { u8(17) } else if kind != 1 && i >= 11 && i < 11 + bytes { u8(wanted >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${c} raw=${raw} sample=${sample} byte=${i}' }
    rows.writeln('${c.source}\t${width}\t${c.opcode}\t${c.count}\t${raw}\t${sample}\t${x}\t${kind}\t${wanted}\t${run.value}\t${run.poison}\t${run.steps}')!
    if sweep { if exhaustive { counts.exhaustive++ } else { counts.wide++ }; for edge in 0 .. 16 { if x == word(c.source, edge) { runtime.writeln('${c.source}\t${width}\t${c.opcode}\t${edge}\t${x}\t${u8(tag(x) != 0)}\t${if tag(x) != 0 { u64(0) } else { value(x) }}') } } }; unsafe { args.free() }
   }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 21) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0, 1], 8) { panic('short scalar budget') }; counts.budgets += 2
  scope := bodies.scopes[function + 1]
  for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
   op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 3 || p.types[op.result_type].kind != .vector_t { continue }
   for changed in [airbitcode.IRTypedInstruction{...op, flags: 4}, airbitcode.IRTypedInstruction{...op, opcode: 9}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 2}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] { p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 22) { panic('conversion metadata admitted') }; unchanged(actual); counts.metadata++ }; p.instructions[index] = op
   original := p.operands[op.operands_start]
   for changed in [airbitcode.IRTypedOperand{...original, number: 0}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: -1}] { p.operands[op.operands_start] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 22) { panic('conversion source admitted') }; unchanged(actual); counts.metadata++ }; p.operands[op.operands_start] = original
  }; unsafe { indices.free(); input.free(); actual.free(); bs.free(); values.free() }
 }
 assert have_good && have_bad
 for changed in [airbitcode.IRScalarRun{...good, value: good.value ^ 1}, airbitcode.IRScalarRun{...good, kind: .binary32}, airbitcode.IRScalarRun{...good, bits: 0}, airbitcode.IRScalarRun{...good, poison: true}, airbitcode.IRScalarRun{...good, steps: 0}] { assert !matches(changed, width, 0, good_value); counts.corruptions++ }
 assert !matches(airbitcode.IRScalarRun{...bad, poison: false}, width, 1, 0); counts.corruptions++
 assert counts.metadata == 120 && counts.budgets == 24 && counts.corruptions == 6
 os.write_file(out + '/runtime-values.tsv', runtime.str())!
 return counts
}
fn controls(assembler_path string, out string) !int {
 mut s := strings.new_builder(262144); s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['literal', 'poison', 'undef', 'partial_poison', 'partial_undef', 'source_poison', 'source_undef', 'result_poison', 'result_undef', 'discard_poison', 'discard_undef', 'old', 'compose', 'isolation', 'prior_undef', 'index_undef', 'invalid', 'isolation_invalid', 'freeze_invalid', 'discard_invalid', 'source_invalid']
 for width in [1, 8, 16, 32, 64] { for source in [16, 32] { for opcode in [3, 4] {
  t := fp(source); op := if opcode == 3 { 'fptoui' } else { 'fptosi' }; raw := (if source == 16 { u64(0x3c00) } else { u64(0x3f800000) }) | if width == 1 && opcode == 4 { u64(1) << u32(source - 1) } else { u64(0) }; one := 'bitcast (i${source} ${raw} to ${t})'
  for mode in modes {
   initial := if mode in ['poison', 'source_poison', 'result_poison', 'discard_poison'] { 'poison' } else if mode in ['undef', 'source_undef', 'result_undef', 'discard_undef', 'prior_undef'] { 'undef' } else if mode.starts_with('partial_') { '<${t} ${one}, ${t} ${if mode == 'partial_undef' { 'undef' } else { 'poison' }}>' } else if mode == 'isolation' { '<${t} poison, ${t} ${one}>' } else if mode in ['invalid', 'isolation_invalid', 'freeze_invalid', 'discard_invalid', 'source_invalid'] { '<${t} bitcast (i${source} ${if source == 16 { u64(0x7e55) } else { u64(0x7fc12345) }} to ${t}), ${t} ${one}>' } else { '<${t} ${one}, ${t} zeroinitializer>' }
   pre := if mode == 'prior_undef' { '%prior = extractelement <2 x ${t}> undef, i32 0\n' } else if mode == 'index_undef' { '%prior = insertelement <2 x ${t}> poison, ${t} zeroinitializer, i32 undef\n' } else if mode.starts_with('source_') { '%prior = freeze <2 x ${t}> ${initial}\n' } else { '' }
   operand := if mode.starts_with('source_') || mode == 'index_undef' { '%prior' } else { initial }
   post := if mode == 'old' { '%changed = insertelement <2 x i${width}> %n, i${width} 0, i32 0\n' } else if mode.starts_with('result_') || mode == 'freeze_invalid' { '%f = freeze <2 x i${width}> %n\n' } else if mode == 'compose' { '%complement = xor <2 x i${width}> %n, <i${width} -1, i${width} -1>\n %cmp = icmp eq <2 x i${width}> %complement, %complement\n %selected = select <2 x i1> %cmp, <2 x i${width}> %complement, <2 x i${width}> zeroinitializer\n' } else { '' }
   selected := if mode == 'compose' { '%selected' } else if mode.starts_with('result_') || mode == 'freeze_invalid' { '%f' } else { '%n' }
   store := if mode.starts_with('discard_') { '' } else { '%v = extractelement <2 x i${width}> ${selected}, i32 ${if mode in ['isolation', 'isolation_invalid'] { 1 } else { 0 }}\n %d = getelementptr i8, ptr %out, i64 8\n store i${width} %v, ptr %d, align 1\n' }
   old_store := if mode == 'old' { '%v2 = extractelement <2 x i${width}> %changed, i32 0\n %d2 = getelementptr i8, ptr %out, i64 16\n store i${width} %v2, ptr %d2, align 1\n' } else { '' }
   s.write_string('define void @${mode}_${source}_${width}_${opcode}(ptr %out) { store i8 17, ptr %out, align 1\n ${pre}%n = ${op} <2 x ${t}> ${operand} to <2 x i${width}>\n ${post}${store}${old_store}ret void }\n')
  }
  s.write_string('define i${width} @constant_${source}_${width}_${opcode}() { %n = ${op} <1 x ${t}> <${t} ${one}> to <1 x i${width}>\n %v = extractelement <1 x i${width}> %n, i32 0\n ret i${width} %v }\n')
 } } }
 for source in [16, 32] { for opcode in [3, 4] {
  t := fp(source); op := if opcode == 3 { 'fptoui' } else { 'fptosi' }
  // LLVM does not admit FMF syntax on fptoui/fptosi. Mutate decoded flags below.
  for flag in ['nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast'] { s.write_string('define void @flag_${source}_${opcode}_${flag}(ptr %out) { store i8 17, ptr %out\n %n = ${op} <2 x ${t}> zeroinitializer to <2 x i32>\n ret void }\n') }
  s.write_string('define i64 @loop_${source}_${opcode}(i64 %limit) { entry: br label %body\n body: %i = phi i64 [0, %entry], [%next, %body]\n %sum = phi i64 [0, %entry], [%added, %body]\n %x = uitofp i64 %i to ${t}\n %a = insertelement <2 x ${t}> poison, ${t} %x, i32 0\n %n = ${op} <2 x ${t}> %a to <2 x i64>\n %f = freeze <2 x i64> %n\n %v = extractelement <2 x i64> %f, i32 0\n %added = add i64 %sum, %v\n %next = add i64 %i, 1\n %c = icmp ult i64 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i64 %added }\n')
  s.write_string('define i8 @round_${source}_${opcode}(i${source} %raw) { %x = bitcast i${source} %raw to ${t}\n %a = insertelement <1 x ${t}> zeroinitializer, ${t} %x, i32 0\n %n = ${op} <1 x ${t}> %a to <1 x i8>\n %v = extractelement <1 x i8> %n, i32 0\n ret i8 %v }\n')
 } }
 guards := ['argument', 'load', 'phi', 'coldwide', 'scalable', 'wideint', 'double', 'bfloat', 'reshape', 'scalar_source', 'scalar_result', 'pointer', 'flagged_int_fp', 'flagged_precision']
 for guard in guards {
  signature := if guard == 'argument' { '<2 x float> %v, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
  body := match guard {
   'argument' { '%n = fptoui <2 x float> %v to <2 x i32>' }
   'load' { '%v = load volatile <2 x half>, ptr %src\n %n = fptosi <2 x half> %v to <2 x i64>' }
   'phi' { 'br label %body\n body: %v = phi <2 x float> [zeroinitializer, %entry]\n %n = fptoui <2 x float> %v to <2 x i32>' }
   'coldwide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold: %n = fptosi <17 x half> zeroinitializer to <17 x i32>' }
   'scalable' { '%n = fptoui <vscale x 2 x float> zeroinitializer to <vscale x 2 x i32>' }
   'wideint' { '%n = fptosi <2 x float> zeroinitializer to <2 x i65>' }
   'double' { '%n = fptoui <2 x double> zeroinitializer to <2 x i64>' }
   'bfloat' { '%n = fptosi <2 x bfloat> zeroinitializer to <2 x i16>' }
   'reshape' { '%n = bitcast <2 x i32> zeroinitializer to <4 x bfloat>' }
   'scalar_source' { '%n = bitcast i128 0 to <2 x i64>' }
   'scalar_result' { '%n = bitcast <2 x i64> zeroinitializer to i128' }
   'pointer' { '%n = ptrtoint <2 x ptr> zeroinitializer to <2 x i64>' }
   'flagged_int_fp' { '%n = uitofp nneg <2 x i32> zeroinitializer to <2 x float>' }
   else { '%n = fpext nnan <2 x half> zeroinitializer to <2 x float>' }
  }; s.write_string('define void @guard_${guard}(${signature}) { entry: store i8 17, ptr %out, align 1\n ${body}\n ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut checks := 0
 for width in [1, 8, 16, 32, 64] { for source in [16, 32] { for opcode in [3, 4] {
  for mode in modes {
   function := fi(ir, '${mode}_${source}_${width}_${opcode}'); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; profile.free()
   mut output := []u8{len: 32, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
   bad := mode in ['poison', 'undef', 'partial_undef', 'result_undef', 'discard_undef', 'prior_undef', 'index_undef', 'invalid', 'source_invalid']
   if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 100) { panic('conversion control accepted: ' + mode) } else { assert if mode in ['poison', 'invalid', 'source_invalid'] { err.msg() == 'AIR memory execution: poison store' } else { err.msg().contains('undef') }, err.msg() } } else { p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 100)! }
   value := if mode.starts_with('source_') || mode in ['result_poison', 'freeze_invalid'] { u64(0) } else if mode == 'compose' { mask(width) ^ 1 } else { u64(1) }
   for i, b in output { assert b == if i == 3 { u8(17) } else if !bad && !mode.starts_with('discard_') && i >= 11 && i < 11 + (width + 7) / 8 { u8(value >> u32((i - 11) * 8)) } else if mode == 'old' && i >= 19 && i < 19 + (width + 7) / 8 { u8(0) } else { u8(0xcc) }, '${source} ${width} ${opcode} ${mode} byte=${i}' }; checks++; unsafe { output.free(); bs.free() }
  }
  function := fi(ir, 'constant_${source}_${width}_${opcode}'); run := p.run_scalar_function(ir, stream, pools, bodies, function, [], 3)!; assert run.kind == .integer && !run.poison && run.bits == width && run.value == 1 && run.steps == 3; if _ := p.run_integer_function(ir, stream, pools, bodies, function, [], 3) { panic('constant floating source entered integer API') }; checks += 2
 } } }
 for source in [16, 32] { for opcode in [3, 4] {
  for count in [u64(1), 2, 3, 16, 257, 513]! { run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop_${source}_${opcode}'), [count], int(count * 11 + 2))!; assert !run.poison && run.value == count * (count - 1) / 2 && run.steps == int(count * 11 + 2); checks++ }
  for bit, flag in ['nnan', 'ninf', 'nsz', 'arcp', 'contract', 'afn', 'reassoc', 'fast'] { mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; function := fi(ir, 'flag_${source}_${opcode}_${flag}'); index := bodies.scopes[function + 1].instructions_start + 1; op := p.instructions[index]; assert op.opcode == opcode && p.types[op.result_type].kind == .vector_t; p.instructions[index] = airbitcode.IRTypedInstruction{...op, flags: u64(1) << u32(bit)}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, 100) { panic('conversion flags admitted') }; unchanged(output); p.instructions[index] = op; checks++; unsafe { output.free(); bs.free() } }
 } }
 for guard in guards { mut output := []u8{len: 32, init: 0xcc}; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bs << airbitcode.IRMemoryBinding{data: output, writable: true} }; if guard == 'phi' { p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100)!; for i, b in output { assert b == if i == 0 { u8(17) } else { u8(0xcc) } } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_' + guard), mut bs, 100) { panic('unsupported profile: ' + guard) }; unchanged(output) }; checks++; unsafe { output.free(); bs.free() } }
 for rounding in [C.FE_UPWARD, C.FE_DOWNWARD] { assert C.fesetround(rounding) == 0; for source in [16, 32] { for opcode in [3, 4] { for negative in [false, true] { raw := (if source == 16 { u64(0x3e00) } else { u64(0x3fc00000) }) | if negative { u64(1) << u32(source - 1) } else { u64(0) }; run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'round_${source}_${opcode}'), [raw], 5)!; assert run.poison == (negative && opcode == 3) && run.steps == 5 && (run.poison || run.value == if negative { u64(255) } else { u64(1) }); checks++ } } } }; assert C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) == 0
 assert checks == 546
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FLOAT-INT-CONTROLS: ${checks} literals, poison/undef, numeric invalidity, source/result freezes, discards, snapshots, integer composition, loops, flags/profiles, API isolation and host-rounding controls PASS\n')!
 return checks
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760)
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } { count := if storage { 1 } else { 16 }; s.write_string('%v${i} = fptoui <${count} x half> zeroinitializer to <${count} x i64>\n') }
  if !storage { for i in 0 .. if over { 54309 } else { 54308 } { s.write_string('%x${i} = extractelement <16 x i64> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory cast limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('void cast limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 58406 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 58405 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert C.fesetenv(unsafe { voidptr(C.FE_DFL_ENV) }) == 0
 assert os.args.len in [3, 4]; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 if os.args.len == 4 { count := controls(os.args[1], out + '/controls')!; println('AIR-VECTOR-FLOAT-INT-CONTROLS: ${count} PASS'); return }
 mut total := Counts{}
 for width in 1 .. 65 { c := run_batch(os.args[1], out + '/batch-${width}', width)!; total.values += c.values; total.poison += c.poison; total.choices += c.choices; total.scalar += c.scalar; total.metadata += c.metadata; total.budgets += c.budgets; total.exhaustive += c.exhaustive; total.wide += c.wide; total.corruptions += c.corruptions }
 controls_count := controls(os.args[1], out + '/controls')!; for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 assert total.metadata == 7680 && total.budgets == 1536 && total.exhaustive == 655360 && total.corruptions == 384
 result := 'AIR-VECTOR-FLOAT-INT: 768 half/float to i1-i64 shapes, both signs and 1/3/16 lanes; ${total.values} defined LLVM values, ${total.poison} poison stores preserving prior writes, ${total.choices} frozen-zero choices, ${total.scalar} scalar/integer API checks, ${total.metadata} metadata/source, ${total.budgets} budgets, ${total.corruptions} corruptions, ${total.exhaustive} exhaustive half samples, ${total.wide} boundary/random samples, ${controls_count} controls and eight storage/work boundaries PASS\n'
 os.write_file(out + '/result.txt', result)!; print(result)
}
