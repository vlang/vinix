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
fn C.fegetround() int
fn C.fesetround(int) int
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
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
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
fn native_word(address u64, width int, a u64, b u64, c u64) u64 {
 mut input := [24]u8{}; mut output := [24]u8{init: 0xcc}; mut indices := [24]u8{}
 for j, value in [a, b, c]! { for i in 0 .. width / 8 { input[j * 8 + i] = u8(value >> u32(i * 8)) } }
 unsafe { NativeCast(voidptr(address))(&indices[0], &input[0], &output[0]) }
 mut word := u64(0); for i in 0 .. width / 8 { word |= u64(output[8 + i]) << u32(i * 8) }
 for i, value in output { if i < 8 || i >= 8 + width / 8 { assert value == 0xcc } }
 return if is_nan(width, word) { if width == 16 { u64(0x7e00) } else { u64(0x7fc00000) } } else { word }
}
fn is_nan(width int, word u64) bool { return word & ((u64(1) << u32(width - 1)) - 1) > if width == 16 { u64(0x7c00) } else { u64(0x7f800000) } }
fn same_result(width int, a u64, b u64) bool { return a == b || (is_nan(width, a) && is_nan(width, b)) }
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
 context := C.LLVMContextCreate(); buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-fmuladd-intrinsics'); mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
 mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
 for f in ir.functions { if f.name.starts_with('case_') || f.name.starts_with('native_') || f.name.starts_with('oracle_') || f.name.starts_with('llvm.') { continue }; name := f.name.clone(); found := C.LLVMGetNamedFunction(module_ptr, name.str); assert found != unsafe { nil }; C.LLVMDeleteFunction(found); unsafe { name.free() } }
 C.LLVMSetDataLayout(module_ptr, c''); triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!; C.LLVMDisposeMessage(triple); path := out + '/native-input.bc'; assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
 cpu := C.LLVMGetHostCPUName(); features := C.LLVMGetHostCPUFeatures(); os.write_file(out + '/native-features.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
 mut f := C.LLVMGetFirstFunction(module_ptr); for f != unsafe { nil } { C.LLVMAddTargetDependentFunctionAttr(f, c'target-cpu', cpu); C.LLVMAddTargetDependentFunctionAttr(f, c'target-features', features); f = C.LLVMGetNextFunction(f) }; C.LLVMDisposeMessage(cpu); C.LLVMDisposeMessage(features)
 assert C.LLVMWriteBitcodeToFile(module_ptr, (out + '/native-input-features.bc').str) == 0
 mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0; mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
 return NativeModule{context, buffer, engine}
}
fn (n NativeModule) close() { C.LLVMDisposeExecutionEngine(n.engine); C.LLVMDisposeMemoryBuffer(n.buffer); C.LLVMContextDispose(n.context) }
struct Case { name string source int dest int count int form int mode int operation int }
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
fn expected(c Case, j u64, q u64, r u64, x u64, y u64, z u64, oracle u64) (int, u64) {
 for index in 0 .. c.count { state, _ := lane(c, j, index, x); if state == 3 && c.mode != 2 { return 3, 0 } }
 if r >= u64(c.count) { return 1, 0 }
 index := if c.mode == 4 { c.count - 1 - int(r) } else { int(r) }
 if c.mode == 4 && r % 2 == 0 { if q >= u64(c.count) { return 1, 0 }; if q == u64(index) { return 0, y } }
 mut state, mut word := lane(c, j, index, x)
 if state != 0 && c.mode == 4 { return 2, 0 }
 mut choice := c.mode == 2 && state != 0
 if choice { state = 0; word = 0 }
 mut right_state := 0; mut right_word := u64(0)
 if c.mode == 0 { right_word = if c.form == 4 { u64(0) } else { lane_word(c.source, index) } } else if j >= u64(c.count) { right_state = 1 } else if j == u64(index) { right_word = y }
 if c.mode == 2 && right_state != 0 { choice = true; right_state = 0; right_word = 0 }
 if right_state != 0 { return if c.mode == 4 { 2 } else { 1 }, 0 }
 if state == 1 { return 1, 0 }
 addend := if c.mode == 0 { right_word } else if j == u64(index) { z } else { u64(0) }
 return if choice { 2 } else { state }, native_word(oracle, bits(c.source), word, right_word, addend)
}
fn run_batch(assembler_path string, out string) ! {
 mut s := strings.new_builder(4194304); mut cases := []Case{}
 s.write_string('target datalayout = "e-p:64:64"\n')
 for source in [64, 65] { for count in 1 .. 17 { t := typ(source); width := bits(source); s.write_string('declare <${count} x ${t}> @llvm.fmuladd.v${count}f${width}(<${count} x ${t}>, <${count} x ${t}>, <${count} x ${t}>)\n'); s.write_string('declare <${count} x ${t}> @llvm.fma.v${count}f${width}(<${count} x ${t}>, <${count} x ${t}>, <${count} x ${t}>)\n') } }
 for width in [16, 32] { t := if width == 16 { 'half' } else { 'float' }; s.write_string('declare ${t} @llvm.fma.f${width}(${t}, ${t}, ${t})\n define void @oracle_${width}(ptr %indices, ptr %src, ptr %out) { %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n %zp = getelementptr i8, ptr %src, i64 16\n %z = load ${t}, ptr %zp, align 1\n %n = call ${t} @llvm.fma.f${width}(${t} %x, ${t} %y, ${t} %z)\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} %n, ptr %d, align 1\n ret void }\n') }
 for width in [16, 32] { t := if width == 16 { 'half' } else { 'float' }; s.write_string('define void @oracle_separate_${width}(ptr %indices, ptr %src, ptr %out) { %x = load ${t}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${t}, ptr %yp, align 1\n %zp = getelementptr i8, ptr %src, i64 16\n %z = load ${t}, ptr %zp, align 1\n %p = fmul ${t} %x, %y\n %n = fadd ${t} %p, %z\n %d = getelementptr i8, ptr %out, i64 8\n store ${t} %n, ptr %d, align 1\n ret void }\n') }
 for source in [64, 65] { for operation in 0 .. 1 { dest := source
  for count in 1 .. 17 { for form in 0 .. 5 { for mode in 0 .. 5 {
   c := Case{'case_${cases.len}', source, dest, count, form, mode, operation}; cases << c
   src := typ(source); dst := typ(dest); width := bits(source)
   mut masks := []string{}; for index in 0 .. count { masks << 'i32 ${count - 1 - index + (index % 2) * count}' }
   selected := if mode == 3 { '%back' } else if mode == 4 { '%t' } else { '%n' }; result_type := if mode == 3 { src } else { dst }; result_element := if mode == 3 { source } else { dest }
   ops := '%a = insertelement <${count} x ${src}> ${vector(c)}, ${src} %x, i64 %j
 %sig = insertelement <${count} x ${src}> zeroinitializer, ${src} %y, i64 %j
 %third = insertelement <${count} x ${src}> zeroinitializer, ${src} %z, i64 %j
 %fs = freeze <${count} x ${src}> ${if mode == 0 { vector(c) } else { '%a' }}
 %gs = freeze <${count} x ${src}> %sig
 %hs = freeze <${count} x ${src}> %third
 %n = call <${count} x ${src}> @llvm.fmuladd.v${count}f${width}(<${count} x ${src}> ${if mode == 2 { '%fs' } else if mode == 0 { vector(c) } else { '%a' }}, <${count} x ${src}> ${if mode == 2 { '%gs' } else if mode == 0 { vector(c) } else { '%sig' }}, <${count} x ${src}> ${if mode == 2 { '%hs' } else if mode == 0 { vector(c) } else { '%third' }})
 %words = bitcast <${count} x ${src}> %n to <${count} x i${width}>
 %back = bitcast <${count} x i${width}> %words to <${count} x ${dst}>
 %f = freeze <${count} x ${dst}> %n
 %b = insertelement <${count} x ${dst}> %f, ${dst} %y, i64 %q
 %t = shufflevector <${count} x ${dst}> %b, <${count} x ${dst}> %f, <${count} x i32> <${masks.join(', ')}>
 %v = extractelement <${count} x ${result_type}> ${selected}, i64 %r
 %raw = bitcast ${result_type} %v to i${width}
'
   value := if result_element >= 64 { '%raw' } else { '%v' }
   kernel := 'define void @${c.name}(ptr %indices, ptr %src, ptr %out) { %j = load i64, ptr %indices, align 1\n %qp = getelementptr i8, ptr %indices, i64 8\n %q = load i64, ptr %qp, align 1\n %rp = getelementptr i8, ptr %indices, i64 16\n %r = load i64, ptr %rp, align 1\n %x = load ${src}, ptr %src, align 1\n %yp = getelementptr i8, ptr %src, i64 8\n %y = load ${dst}, ptr %yp, align 1\n %zp = getelementptr i8, ptr %src, i64 16\n %z = load ${src}, ptr %zp, align 1\n store i8 17, ptr %out, align 1\n ${ops}%d = getelementptr i8, ptr %out, i64 8\n store i${width} ${value}, ptr %d, align 1\n ret void }\n'
   s.write_string(kernel)
   s.write_string(kernel.replace('@' + c.name + '(', '@native_fused_' + c.name + '(').replace('@llvm.fmuladd.', '@llvm.fma.'))
   s.write_string('define i${width} @scalar_${c.name}(i64 %j, i64 %q, i64 %r, ${src} %x, ${dst} %y, ${src} %z) { ${ops}ret i${width} ${value} }\n')
   unsafe { masks.free() }
  } } }
 } }
 data := assemble(assembler_path, out, s.str())!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 native := native_module(data, out, ir)!; defer { native.close() }
 mut exact := 0; mut choices := 0; mut poison := 0; mut undef := 0; mut scalar := 0; mut metadata := 0; mut budgets := 0; mut sweeps := 0; mut edge_pairs := 0
 mut diagnostics := 0; mut fused_only := 0; mut separate_only := 0; mut both := 0; mut distinctions := 0
 mut diagnostic_rows := os.create(out + '/native-optional.tsv')!; defer { diagnostic_rows.close() }; diagnostic_rows.writeln('case\tx\ty\tz\tfused\tseparate\toptional\tmatches_fused\tmatches_separate')!
 mut rows := os.create(out + '/comparisons.tsv')!; defer { rows.close() }; rows.writeln('element\toperation\tlanes\tform\tmode\tj\tq\tr\tx\ty\tz\tvalue')!
 for c in cases {
  function := fi(ir, c.name); sf := fi(ir, 'scalar_' + c.name); width := bits(c.source); bytes := width / 8; floating_result := if c.mode == 3 { c.source >= 64 } else { c.dest >= 64 }; scalar_steps := if floating_result { 15 } else { 14 }; steps := scalar_steps + 13
  profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == steps && profile.arguments[0].minimum_size == 24 && profile.arguments[1].minimum_size == 16 + bytes && profile.arguments[2].minimum_size == 8 + bytes; profile.free()
  oracle := C.LLVMGetFunctionAddress(native.engine, 'oracle_${width}'.str); assert oracle != 0
  address := C.LLVMGetFunctionAddress(native.engine, ('native_fused_' + c.name).str); assert address != 0
  optional := C.LLVMGetFunctionAddress(native.engine, c.name.str); separate := C.LLVMGetFunctionAddress(native.engine, 'oracle_separate_${width}'.str); assert optional != 0 && separate != 0
  mut indices := []u8{len: 32}; mut input := []u8{len: 32}; mut actual := []u8{len: 24, init: 0xcc}; mut reference := actual.clone(); mut bs := [airbitcode.IRMemoryBinding{data: indices, offset: 1}, airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: actual, offset: 3, writable: true}]
  sweep := c.count == 16 && c.form == 4 && c.mode == 1
  edges := [u64(0), u64(c.count - 1), u64(c.count), ~u64(0), 1, 2, 3, u64(c.count + 1)]!
  for sample in 0 .. if sweep { 200704 } else { c.count + 2 } {
   j := if sweep { u64(sample % 16) } else { edges[(sample * 3) % 8] }; q := edges[(sample * 5 + 1) % 8]; r := if sweep { j } else { u64(sample) }
   edge_pair := sweep && sample >= 196608
   x, y, z := sample_words(c.source, sample, sweep)
   state, word := expected(c, j, q, r, x, y, z, oracle)
   for i in 0 .. 8 { indices[1 + i] = u8(j >> u32(i * 8)); indices[9 + i] = u8(q >> u32(i * 8)); indices[17 + i] = u8(r >> u32(i * 8)) }; for i in 0 .. bytes { input[1 + i] = u8(x >> u32(i * 8)); input[9 + i] = u8(y >> u32(i * 8)); input[17 + i] = u8(z >> u32(i * 8)) }; for i in 0 .. actual.len { actual[i] = 0xcc; reference[i] = 0xcc }
   args := [j, q, r, x | ~mask(width), y | ~mask(width), z | ~mask(width)]
   if state == 3 { if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, args, scalar_steps) { panic('undef scalar bitcast') } else { assert err.msg() == 'AIR vector intrinsic: undef source lane', err.msg() } } else { run := p.run_scalar_function(ir, stream, pools, bodies, sf, args, scalar_steps)!; assert run.poison == (state == 1) && run.bits == width && run.steps == scalar_steps && (run.poison || run.value == word), '${c} sample=${sample} j=${j} q=${q} r=${r} x=${x} y=${y} state=${state} word=${word} run=${run}' }
   if _ := p.run_integer_function(ir, stream, pools, bodies, sf, args, scalar_steps) { panic('floating bitcast entered integer API') }; scalar += 2
   if state in [1, 3] { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps) { panic('indeterminate bitcast stored') } else { assert err.msg() == if state == 3 { 'AIR vector intrinsic: undef source lane' } else { 'AIR memory execution: poison store' }, err.msg() }; if state == 1 { poison++ } else { undef++ } } else { assert p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps)!.steps == steps; if state == 0 { exact++ } else { choices++ } }
   for i, b in actual { assert b == if i == 3 { u8(17) } else if state in [0, 2] && i >= 11 && i < 11 + bytes { u8(word >> u32((i - 11) * 8)) } else { u8(0xcc) }, '${c.name} state=${state} j=${j} q=${q} r=${r} byte=${i}' }
   if state == 0 { unsafe { NativeCast(voidptr(address))(&indices[1], &input[1], &reference[3]) }; mut native_word := u64(0); for i in 0 .. bytes { native_word |= u64(reference[11 + i]) << u32(i * 8) }; if is_nan(width, word) { assert is_nan(width, native_word); for i in 0 .. bytes { reference[11 + i] = u8(word >> u32(i * 8)) } }; assert actual == reference, '${c.name} ${sample}'; row := '${c.source}\t${c.operation}\t${c.count}\t${c.form}\t${c.mode}\t${j}\t${q}\t${r}\t${x}\t${y}\t${z}\t${word}'; rows.writeln(row)!; unsafe { row.free() } }
   if state == 0 {
    other_state, other := expected(c, j, q, r, x, y, z, separate); assert other_state == 0
    for i in 0 .. reference.len { reference[i] = 0xcc }; unsafe { NativeCast(voidptr(optional))(&indices[1], &input[1], &reference[3]) }
    mut observed := u64(0); for i in 0 .. bytes { observed |= u64(reference[11 + i]) << u32(i * 8) }; for i, byte in reference { if i == 3 { assert byte == 17 } else if i < 11 || i >= 11 + bytes { assert byte == 0xcc } }
    matches_fused := same_result(width, observed, word); matches_separate := same_result(width, observed, other); assert matches_fused || matches_separate, '${c.name} unsupported native choice'
    if matches_fused && matches_separate { both++ } else if matches_fused { fused_only++ } else { separate_only++ }; diagnostics++
    if !same_result(width, word, other) { distinctions++ }
    diagnostic_rows.writeln('${c.name}\t${x}\t${y}\t${z}\t${word}\t${other}\t${observed}\t${matches_fused}\t${matches_separate}')!
   }
   if edge_pair { edge_pairs++ } else if sweep { sweeps++ }; unsafe { args.free() }
  }
  for i in 0 .. actual.len { actual[i] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bs, steps - 1) { panic('short memory budget') }; unchanged(actual); if _ := p.run_scalar_function(ir, stream, pools, bodies, sf, [u64(0), 0, 0, 0, 0, 0], scalar_steps - 1) { panic('short scalar budget') }; budgets += 2
  metadata += metadata_checks(ir, stream, pools, bodies, mut p, function, sf, mut bs, actual, steps)!
  unsafe { indices.free(); input.free(); actual.free(); reference.free(); bs.free() }
 }
 assert cases.len == 800 && scalar == (exact + choices + poison + undef) * 2 && metadata == 20800 && budgets == 1600 && sweeps == 393216 && edge_pairs == 8192
 assert diagnostics == exact && fused_only + separate_only + both == diagnostics && distinctions > 0
 os.write_file(out + '/native-optional-summary.txt', '${diagnostics} native optional choices: ${fused_only} fused-only, ${separate_only} separate-only, ${both} both; ${distinctions} fused/separate distinctions. Production comparisons require the fused refinement.\n')!
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FMULADD: ${cases.len} shapes, every count 1-16, both formats, five source forms and five constructions; ${exact} LLVM values (preferred arithmetic NaNs) including ${sweeps} exhaustive half/deterministic float sweep samples and ${edge_pairs} directed edge triples, ${choices} fixed-zero choices, ${poison} poison stores, ${undef} strict undef failures, ${scalar} scalar/integer checks, ${metadata} metadata/source and ${budgets} budgets PASS\n')!
}
fn metadata_checks(ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, mut p airbitcode.IRTypedProgram, function int, scalar_function int, mut bindings []airbitcode.IRMemoryBinding, output []u8, steps int) !int {
 assert scalar_function >= 0
 scope := bodies.scopes[function + 1]; mut count := 0
 for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
  op := p.instructions[index]; if stream.records[bodies.instructions[index].record].code != 34 { continue }
  for changed in [airbitcode.IRTypedInstruction{...op, flags: 0}, airbitcode.IRTypedInstruction{...op, flags: 32769}, airbitcode.IRTypedInstruction{...op, opcode: 1}, airbitcode.IRTypedInstruction{...op, calling_convention: 8}, airbitcode.IRTypedInstruction{...op, fast_math_flags: 1}, airbitcode.IRTypedInstruction{...op, attribute_set: 1}, airbitcode.IRTypedInstruction{...op, call_signature: -1}, airbitcode.IRTypedInstruction{...op, callee_function: -1}, airbitcode.IRTypedInstruction{...op, callee_function: ir.functions.len}, airbitcode.IRTypedInstruction{...op, operands_count: 0}, airbitcode.IRTypedInstruction{...op, operands_count: 1}, airbitcode.IRTypedInstruction{...op, operands_count: 5}, airbitcode.IRTypedInstruction{...op, result_type: -1}, airbitcode.IRTypedInstruction{...op, targets_count: 1}, airbitcode.IRTypedInstruction{...op, indices_count: 1}] {
   p.instructions[index] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, steps) { panic('intrinsic metadata admitted') }; unchanged(output); count++
  }; p.instructions[index] = op
  for operand in 0 .. op.operands_count {
   slot := op.operands_start + operand; original := p.operands[slot]
   changes := if operand == 0 { [airbitcode.IRTypedOperand{...original, number: ~u32(0)}, airbitcode.IRTypedOperand{...original, type_index: -1}] } else { [airbitcode.IRTypedOperand{...original, number: 0}, airbitcode.IRTypedOperand{...original, number: bodies.instructions[index].next_value}, airbitcode.IRTypedOperand{...original, type_index: -1}] }
   for changed in changes { p.operands[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, steps) { panic('intrinsic operand admitted') }; unchanged(output); count++ }; p.operands[slot] = original; unsafe { changes.free() }
  }
 }
 return count
}

fn sample_words(element int, sample int, sweep bool) (u64, u64, u64) {
 if sweep && sample >= 196608 { k := sample - 196608; return lane_word(element, k / 256), lane_word(element, (k / 16) % 16), lane_word(element, k % 16) }
 if sweep {
  k := sample % 65536; raw := if element == 64 { u64(k) } else { u64(u32(k) * u32(0x9e3779b9)) }
  a := lane_word(element, (k * 7 + 5) % 16); b := lane_word(element, (k * 11 + 9) % 16)
  return if sample < 65536 { raw } else { a }, if sample >= 65536 && sample < 131072 { raw } else { b }, if sample >= 131072 { raw } else { a }
 }
 return lane_word(element, sample % 16), lane_word(element, (sample + 5) % 16), lane_word(element, (sample + 9) % 16)
}

fn focused_controls(assembler_path string, out string) ! {
 mut s := strings.new_builder(65536)
 s.write_string('target datalayout = "e-p:64:64"\n')
 modes := ['raw', 'source', 'result', 'discard', 'old', 'chain']
 guards := ['fmf', 'tail', 'attribute', 'argument', 'load', 'phi', 'wide', 'scalable', 'double', 'alias']
 for width in [16, 32] {
  t := if width == 16 { 'half' } else { 'float' }; one := if width == 16 { u64(0x3c00) } else { u64(0x3f800000) }; sign := u64(1) << u32(width - 1); element := if width == 16 { 64 } else { 65 }
  for count in [2, 17] { s.write_string('declare <${count} x ${t}> @llvm.fmuladd.v${count}f${width}(<${count} x ${t}>, <${count} x ${t}>, <${count} x ${t}>)\n'); s.write_string('declare <${count} x ${t}> @llvm.fma.v${count}f${width}(<${count} x ${t}>, <${count} x ${t}>, <${count} x ${t}>)\n') }
  s.write_string('declare <vscale x 2 x ${t}> @llvm.fmuladd.nxv2f${width}(<vscale x 2 x ${t}>, <vscale x 2 x ${t}>, <vscale x 2 x ${t}>)\n declare <2 x ${t}> @air.fmuladd.v2f${width}(<2 x ${t}>, <2 x ${t}>, <2 x ${t}>)\n declare <2 x ${t}> @reserved_alias_${width}(<2 x ${t}>, <2 x ${t}>, <2 x ${t}>)\n')
  for side in 0 .. 3 { for state in ['defined', 'poison', 'undef'] { for mode in modes {
   mut args := []string{}; for i, word in [one + 1, one - 2, one | sign]! { args << if i == side && state != 'defined' { state } else { '<${t} ${literal(element, word)}, ${t} ${literal(element, word)}>' } }
   mut pre := ''; if mode == 'source' { pre = '%s = freeze <2 x ${t}> ${args[side]}\n'; args[side] = '%s' }
   post := if mode == 'result' { '%r = freeze <2 x ${t}> %n\n' } else if mode == 'old' { '%changed = insertelement <2 x ${t}> %n, ${t} zeroinitializer, i32 0\n' } else if mode == 'chain' { '%neg = fneg <2 x ${t}> %n\n %raws = bitcast <2 x ${t}> %neg to <2 x i${width}>\n %cmp = icmp eq <2 x i${width}> %raws, %raws\n %selected = select <2 x i1> %cmp, <2 x i${width}> %raws, <2 x i${width}> zeroinitializer\n' } else { '' }
   result := if mode == 'result' { '%r' } else if mode == 'chain' { '%selected' } else { '%n' }; result_t := if mode == 'chain' { 'i${width}' } else { t }
   store := if mode == 'discard' { '' } else { '%v = extractelement <2 x ${result_t}> ${result}, i32 0\n ' + if mode == 'chain' { '' } else { '%raw = bitcast ${t} %v to i${width}\n ' } + '%d = getelementptr i8, ptr %out, i64 8\n store i${width} %${if mode == 'chain' { 'v' } else { 'raw' }}, ptr %d, align 1\n' }
   old := if mode == 'old' { '%v2 = extractelement <2 x ${t}> %changed, i32 0\n %raw2 = bitcast ${t} %v2 to i${width}\n %d2 = getelementptr i8, ptr %out, i64 16\n store i${width} %raw2, ptr %d2, align 1\n' } else { '' }
   s.write_string('define void @case_${width}_${side}_${state}_${mode}(ptr %out) { store i8 17, ptr %out\n ${pre}%n = call <2 x ${t}> @llvm.fmuladd.v2f${width}(<2 x ${t}> ${args[0]}, <2 x ${t}> ${args[1]}, <2 x ${t}> ${args[2]})\n ${post}${store}${old}ret void }\n')
   unsafe { args.free() }
  } } }
  for guard in guards {
   count := if guard == 'wide' { 17 } else { 2 }; vt := if guard == 'scalable' { '<vscale x 2 x ${t}>' } else if guard == 'double' { '<2 x double>' } else { '<${count} x ${t}>' }
   callee := if guard == 'scalable' { 'llvm.fmuladd.nxv2f${width}' } else if guard == 'double' { 'llvm.fmuladd.v2f64' } else if guard == 'alias' { 'air.fmuladd.v2f${width}' } else { 'llvm.fmuladd.v${count}f${width}' }
   signature := if guard == 'argument' { '<2 x ${t}> %a, ptr %out' } else if guard == 'load' { 'ptr %src, ptr %out' } else { 'ptr %out' }
   pre := if guard == 'load' { '%a = load volatile <2 x ${t}>, ptr %src, align 1\n' } else if guard == 'phi' { 'br label %body\n body: %a = phi <2 x ${t}> [zeroinitializer, %entry]\n' } else if guard == 'wide' { 'br i1 true, label %done, label %cold\n done: ret void\n cold:' } else { '' }
   s.write_string('define void @guard_${width}_${guard}(${signature}) { entry: store i8 17, ptr %out\n ${pre}%n = ${if guard == 'tail' { 'tail ' } else { '' }}call ${if guard == 'fmf' { 'nnan ' } else { '' }}${vt} @${callee}(${vt} ${if guard in ['argument', 'load', 'phi'] { '%a' } else { 'zeroinitializer' }}, ${vt} zeroinitializer, ${vt} zeroinitializer)${if guard == 'attribute' { ' #1' } else { '' }}\n ret void }\n')
  }
  for name in ['memory', 'void'] { s.write_string('define void @duplicate_${name}_${width}(${if name == 'memory' { 'ptr %out' } else { '' }}) { ${if name == 'memory' { 'store i8 17, ptr %out\n' } else { '' }}%a = call <2 x ${t}> @llvm.fmuladd.v2f${width}(<2 x ${t}> zeroinitializer, <2 x ${t}> zeroinitializer, <2 x ${t}> zeroinitializer)\n %b = call <2 x ${t}> @reserved_alias_${width}(<2 x ${t}> %a, <2 x ${t}> %a, <2 x ${t}> %a)\n ret void }\n') }
  s.write_string('define i32 @loop_${width}(i32 %limit) { entry: br label %body\n body: %i = phi i32 [0, %entry], [%next, %body]\n %sum = phi i32 [0, %entry], [%added, %body]\n %small = trunc i32 %i to i16\n %x = bitcast i${width} %${if width == 16 { 'small' } else { 'i' }} to ${t}\n %a = insertelement <2 x ${t}> poison, ${t} %x, i32 0\n %first = call <2 x ${t}> @llvm.fma.v2f${width}(<2 x ${t}> %a, <2 x ${t}> <${t} ${literal(element, one)}, ${t} ${literal(element, one)}>, <2 x ${t}> zeroinitializer)\n %n = call <2 x ${t}> @llvm.fmuladd.v2f${width}(<2 x ${t}> %first, <2 x ${t}> <${t} ${literal(element, one)}, ${t} ${literal(element, one)}>, <2 x ${t}> zeroinitializer)\n %v = extractelement <2 x ${t}> %n, i32 0\n %raw = bitcast ${t} %v to i${width}\n %extended = zext i${width} %raw to i64\n %word = trunc i64 %extended to i32\n %added = add i32 %sum, %word\n %next = add i32 %i, 1\n %c = icmp ult i32 %next, %limit\n br i1 %c, label %body, label %done\n done: ret i32 %added }\n')
 }
 s.write_string('declare <2 x double> @llvm.fmuladd.v2f64(<2 x double>, <2 x double>, <2 x double>)\n attributes #1 = { nounwind }\n')
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut functions := ir.functions.clone(); defer { unsafe { functions.free() } }; view := airbitcode.IRModule{...ir, functions: functions}; mut checks := 0
 for width in [16, 32] {
  one := if width == 16 { u64(0x3c00) } else { u64(0x3f800000) }; sign := u64(1) << u32(width - 1); epsilon := if width == 16 { u64(0x10) } else { u64(0x28800000) }
  for side in 0 .. 3 { for state in ['defined', 'poison', 'undef'] { for mode in modes {
   mut output := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
   bad := (state == 'undef' && mode != 'source') || (state == 'poison' && mode !in ['source', 'result', 'discard'])
   function := fi(ir, 'case_${width}_${side}_${state}_${mode}'); profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; profile.free()
   if bad { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 100) { panic('indeterminate FMA admitted') } } else { p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 100)! }
   value := if state != 'defined' && mode == 'source' { if side == 2 { one } else { one | sign } } else if state == 'poison' && mode == 'result' { u64(0) } else { epsilon | sign }; result := if mode == 'chain' { value ^ sign } else { value }
   for i, byte in output { assert byte == if i == 3 { u8(17) } else if !bad && mode != 'discard' && i >= 11 && i < 11 + width / 8 { u8(result >> u32((i - 11) * 8)) } else if !bad && mode == 'old' && i >= 19 && i < 19 + width / 8 { u8(0) } else { u8(0xcc) }, '${width} ${side} ${state} ${mode} byte=${i}' }; checks++; unsafe { output.free(); bindings.free() }
  } } }
  for guard in guards { mut output := []u8{len: 32, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if guard in ['argument', 'load'] { bindings << airbitcode.IRMemoryBinding{data: output, writable: true} }; if guard == 'phi' { p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_${width}_${guard}'), mut bindings, 100)!; for i, b in output { assert b == if i == 0 { u8(17) } else { u8(0xcc) } } } else { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'guard_${width}_${guard}'), mut bindings, 100) { panic('unsupported FMA admitted') }; unchanged(output) }; checks++; unsafe { output.free(); bindings.free() } }
  for count in [u64(1), 2, 3, 16, 257, 513]! { run := p.run_scalar_function(ir, stream, pools, bodies, fi(ir, 'loop_${width}'), [count], 10000)!; assert !run.poison && run.value == count * (count - 1) / 2; checks++ }
  alias := fi(ir, 'reserved_alias_${width}'); old := functions[alias]; functions[alias] = airbitcode.IRFunction{...old, name: 'llvm.fmuladd.v2f${width}'}
  mut output := [u8(0xcc)]; mut bindings := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if _ := p.run_memory_function(view, stream, pools, bodies, fi(ir, 'duplicate_memory_${width}'), mut bindings, 100) { panic('duplicate memory FMA') } else { assert err.msg() == 'AIR vector intrinsic: duplicate reserved declaration' }; unchanged(output); if _ := p.run_void_function(view, stream, pools, bodies, fi(ir, 'duplicate_void_${width}'), [], 100) { panic('duplicate void FMA') } else { assert err.msg() == 'AIR vector intrinsic: duplicate reserved declaration' }; functions[alias] = old; checks += 2; unsafe { output.free(); bindings.free() }
 }
 assert checks == 144
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FMULADD-CONTROLS: ${checks} exact fused witnesses, three-source states, discards, freezes, snapshots, composition, loops, unsupported profile and duplicate-cache controls PASS\n')!
}
fn attribute_controls(assembler_path string, out string) ! {
 source := 'target datalayout = "e-p:64:64"\ndeclare <2 x half> @llvm.fmuladd.v2f16(<2 x half>, <2 x half>, <2 x half>) #0\ndeclare <2 x float> @llvm.fmuladd.v2f32(<2 x float>, <2 x float>, <2 x float>) #0\nattributes #0 = { strictfp }\n'
 mut s := strings.new_builder(4096); s.write_string(source)
 for width in [16, 32] { t := if width == 16 { 'half' } else { 'float' }; for kind in ['memory', 'void'] { s.write_string('define void @${kind}_${width}(${if kind == 'memory' { 'ptr %out' } else { '' }}) { ${if kind == 'memory' { 'store i8 17, ptr %out\n' } else { '' }}%n = call <2 x ${t}> @llvm.fmuladd.v2f${width}(<2 x ${t}> zeroinitializer, <2 x ${t}> zeroinitializer, <2 x ${t}> zeroinitializer)\n ret void }\n') } }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 // LLVM canonicalizes intrinsic declaration attributes, removing strictfp.
 // Admit that canonical baseline, then mutate its retained attribute group.
 for width in [16, 32] { profile := p.memory_function_profile(ir, stream, pools, bodies, fi(ir, 'memory_${width}'))!; profile.free(); assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'void_${width}'), [], 2)!.steps == 2 }
 mut values := stream.values.clone(); defer { unsafe { values.free() } }; mutated := airbitcode.Stream{...stream, values: values}
 mut group := -1
 for record in stream.records { if stream.blocks[record.block].id == 10 && record.code == 3 && record.values_count >= 4 && stream.values[record.values_start + 1] == 0xffffffff { group = record.values_start; break } }
 assert group >= 0 && values[group + 2] == 0
 for change in 0 .. 4 {
  values[group + 1] = stream.values[group + 1]; values[group + 2] = stream.values[group + 2]; values[group + 3] = stream.values[group + 3]
  if change == 0 { values[group + 3] = 54 } else if change == 1 { values[group + 1] = 0 } else if change == 2 { values[group + 1] = 1 } else { values[group + 2] = 3 }
  for width in [16, 32] { mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; if _ := p.run_memory_function(ir, mutated, pools, bodies, fi(ir, 'memory_${width}'), mut bs, 100) { panic('declaration attributes admitted') }; unchanged(output); if _ := p.run_void_function(ir, mutated, pools, bodies, fi(ir, 'void_${width}'), [], 100) { panic('void declaration attributes admitted') }; unsafe { output.free(); bs.free() } }
 }
 os.write_file(out + '/result.txt', 'AIR-VECTOR-FMULADD-ATTRIBUTES: canonical declaration acceptance and 16 memory/void strictfp/return/parameter/string attribute refusals before writes PASS\n')!
}
fn limits(assembler_path string, out string, storage bool, over bool) ! {
 mut s := strings.new_builder(10485760); count := if storage { 1 } else { 16 }; op := 'fmuladd'
 s.write_string('declare <${count} x half> @llvm.${op}.v${count}f16(<${count} x half>, <${count} x half>, <${count} x half>)\n')
 for name in ['memory', 'scalar'] {
  s.write_string('define void @${name}(${if name == 'memory' { 'ptr %out' } else { '' }}) {\n'); if name == 'memory' { s.write_string('store i8 17, ptr %out, align 1\n') }
  for i in 0 .. if storage && over { 4097 } else { 4096 } { s.write_string('%v${i} = call <${count} x half> @llvm.${op}.v${count}f16(<${count} x half> zeroinitializer, <${count} x half> zeroinitializer, <${count} x half> zeroinitializer)\n') }
  if !storage { for i in 0 .. if over { 46117 } else { 46116 } { s.write_string('%x${i} = extractelement <16 x half> %v4095, i32 0\n') } }; s.write_string('ret void }\n')
 }
 data := assemble(assembler_path, out, s.str())!; verify(data)!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
 mut output := [u8(0xcc)]; mut bs := [airbitcode.IRMemoryBinding{data: output, writable: true}]; diagnostic := if storage { 'AIR vector: update result limit' } else { 'AIR vector: constant lane work limit' }
 if over { if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000) { panic('memory intrinsic limit') } else { assert err.msg() == diagnostic, err.msg() }; unchanged(output); if _ := p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000) { panic('scalar intrinsic limit') } else { assert err.msg() == diagnostic, err.msg() } } else { assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'memory'), mut bs, 70000)!.steps == if storage { 4098 } else { 50214 }; assert output[0] == 17; assert p.run_void_function(ir, stream, pools, bodies, fi(ir, 'scalar'), [], 70000)!.steps == if storage { 4097 } else { 50213 } }
 unsafe { output.free(); bs.free() }
}
fn main() {
 assert os.args.len == 3; out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
 saved := C.fegetround(); assert saved >= 0; defer { assert C.fesetround(saved) == 0 }; assert C.fesetround(C.FE_TONEAREST) == 0
 run_batch(os.args[1], out + '/primary')!; focused_controls(os.args[1], out + '/controls')!; attribute_controls(os.args[1], out + '/attributes')!
 for storage in [false, true] { for over in [false, true] { limits(os.args[1], out + '/${if storage { 'storage' } else { 'work' }}-${if over { 'over' } else { 'boundary' }}', storage, over)! } }
 result := os.read_file(out + '/primary/result.txt')! + 'AIR-VECTOR-FMULADD: 144 focused controls, 16 declaration attribute guards and eight shared storage/lane-work boundaries PASS\n'; os.write_file(out + '/result.txt', result)!; print(result)
}
