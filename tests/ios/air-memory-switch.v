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
struct C.LLVMMCJITCompilerOptions {
mut:
	OptLevel u32
	CodeModel int
	NoFramePointerElim int
	EnableFastISel int
	MCJMM voidptr
}
fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)
type NativeSwitch = fn (voidptr, voidptr, voidptr)
type NativeTwo = fn (voidptr, voidptr)
struct Case { name string bits int kind string }
struct Guard { name string bits int early bool empty bool }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn keys(bits int) []u64 { return if bits == 1 { [u64(0)] } else { [u64(0), mask(bits), u64(1) << u32(bits - 1)] } }
fn word(bytes []u8, offset int, count int) u64 { mut value := u64(0); for j in 0 .. count { value |= u64(bytes[offset + j]) << u32(8 * j) }; return value }
fn function_index(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name) }
fn unchanged(bytes []u8) { for byte in bytes { assert byte == 0xcc } }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); mut cases := []Case{}; mut guards := []Guard{}
	source.write_string('target datalayout = "e-p:64:64"\n')
	for bits in 1 .. 65 {
		cases << Case{'scalar_${bits}', bits, 'scalar'}; if bits in [16, 32] { cases << Case{'float_${bits}', bits, 'float'} }
		for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] { cases << Case{'${op}_${bits}', bits, op}; source.write_string('declare {i${bits}, i1} @llvm.${op}.with.overflow.i${bits}(i${bits}, i${bits})\n') }
		for state in ['poison', 'undef'] { for empty in [false, true] { for early in [false, true] {
			name := 'guard_${bits}_${state}_${empty}_${early}'; guards << Guard{name, bits, early, empty}
			store := if early { 'store i8 17, ptr %out, align 1\n' } else { '' }; labels := if empty { '' } else { 'i${bits} 0, label %zero' }; zero := if empty { '' } else { 'zero: store i8 9, ptr %out, align 1\n ret void\n' }
			source.write_string('define void @${name}(ptr %out) { entry: ${store}switch i${bits} ${state}, label %default [${labels}]\n ${zero}default: store i8 7, ptr %out, align 1\n ret void }\n')
		} } }
		source.write_string('define void @frozen_${bits}(ptr %out) { entry: %c = freeze i${bits} poison\n switch i${bits} %c, label %default [i${bits} 0, label %zero]\n zero: store i${bits} ${u64(7) & mask(bits)}, ptr %out, align 1\n ret void\n default: store i${bits} ${u64(9) & mask(bits)}, ptr %out, align 1\n ret void }\n')
		source.write_string('define void @empty_${bits}(ptr %a, ptr %out) { entry: %c = load i${bits}, ptr %a, align 1\n store i8 17, ptr %out, align 1\n switch i${bits} %c, label %default []\n default: store i${bits} ${u64(17) & mask(bits)}, ptr %out, align 1\n ret void }\n')
	}
	for c in cases {
		pair := c.kind !in ['scalar', 'float']; typ := if c.kind == 'float' { if c.bits == 16 { 'half' } else { 'float' } } else { 'i${c.bits}' }; phi_type := if pair { '{i${c.bits}, i1}' } else { typ }; values := keys(c.bits)
		source.write_string('define void @${c.name}(ptr %a, ptr %b, ptr %out) { entry: %x = load i${c.bits}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n store i8 17, ptr %out, align 1\n switch i${c.bits} %x, label %default [\n')
		for j, value in values { source.write_string('i${c.bits} ${value}, label %c${j}\n') }; source.write_string(']\n')
		for j in 0 .. values.len + 1 {
			label := if j == values.len { 'default' } else { 'c${j}' }
			expr := if pair { if j == 0 { 'call ${phi_type} @llvm.${c.kind}.with.overflow.i${c.bits}(i${c.bits} %x, i${c.bits} %y)' } else if j == 1 { 'call ${phi_type} @llvm.${c.kind}.with.overflow.i${c.bits}(i${c.bits} %y, i${c.bits} %x)' } else { 'call ${phi_type} @llvm.${c.kind}.with.overflow.i${c.bits}(i${c.bits} ${mask(c.bits)}, i${c.bits} %y)' } } else if c.kind == 'float' { if j % 2 == 0 { 'fneg ${typ} %y' } else { 'freeze ${typ} %y' } } else { if j == 0 { 'xor ${typ} %y, 0' } else { 'add ${typ} %y, ${u64(j) & mask(c.bits)}' } }
			source.write_string('${label}: %v${j} = ${expr}\n br label %join\n')
		}
		source.write_string('join: %p = phi ${phi_type} ')
		for j in 0 .. values.len + 1 { label := if j == values.len { 'default' } else { 'c${j}' }; source.write_string(if j == 0 { '' } else { ', ' }); source.write_string('[%v${j}, %${label}]') }
		ending := if pair { '%v = extractvalue ${phi_type} %p, 0\n store ${typ} %v, ptr %out, align 1\n %f = extractvalue ${phi_type} %p, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n' } else { 'store ${typ} %p, ptr %out, align 1\n' }
		source.write_string('\n ${ending}ret void }\n'); unsafe { values.free() }
	}
	for count in [64, 65] {
		source.write_string('define void @cap_${count}(ptr %a, ptr %out) { entry: %c = load i8, ptr %a, align 1\n store i8 17, ptr %out, align 1\n switch i8 %c, label %default [\n')
		for j in 0 .. count { source.write_string('i8 ${j}, label %c${j}\n') }; source.write_string(']\n')
		for j in 0 .. count { source.write_string('c${j}: store i32 ${j + 1000}, ptr %out, align 1\n ret void\n') }; source.write_string('default: store i32 2000, ptr %out, align 1\n ret void }\n')
	}
	source.write_string('define void @nested(ptr %a, ptr %out) { entry: %x = load i8, ptr %a, align 1\n switch i8 %x, label %d [i8 0, label %a0 i8 1, label %a1]\n a0: %v0 = add i8 %x, 3\n br label %merge\n a1: %v1 = add i8 %x, 4\n br label %merge\n d: %vd = add i8 0, 7\n br label %merge\n merge: %v = phi i8 [%v0, %a0], [%v1, %a1], [%vd, %d]\n %k = and i8 %x, 1\n switch i8 %k, label %f [i8 0, label %t]\n t: %tv = add i8 %v, 10\n br label %end\n f: %fv = sub i8 %v, 10\n br label %end\n end: %p = phi i8 [%tv, %t], [%fv, %f]\n store i8 %p, ptr %out, align 1\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'switch'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) } + '\n')!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c'')
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	mut comparisons := 0; mut metadata := 0; mut types := 0; mut budgets := 0; mut rejected := 0; mut choices := 0
	for c in cases {
		pair := c.kind !in ['scalar', 'float']; count := (c.bits + 7) / 8; full := mask(c.bits); values := keys(c.bits); ending := if pair { 7 } else { 3 }; bound := 4 + 2 * (values.len + 1) + ending + values.len
		function := function_index(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0; profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == bound; profile.free()
		mut a := []u8{len: 12}; mut b := []u8{len: 12}; mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. 160 { for variant in 0 .. values.len + 1 {
			candidate := u64(sample) * u64(0x9e3779b97f4a7c15) & full; x := if variant < values.len { values[variant] } else if candidate !in values { candidate } else { u64(1) }; y := if sample < 144 { (u64(sample % 12) * u64(0xaaaaaaaaaaaaaaaa)) & full } else { (~x ^ u64(sample) * u64(0x123456789abcdef)) & full }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)) }; if c.bits % 8 != 0 { a[count] |= u8(0xff << u32(c.bits % 8)) }; for j in 0 .. 32 { actual[j] = 0xcc; expected[j] = 0xcc }
			mut checks := 0; for value in values { checks++; if value == x { break } }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound)!.steps == 4 + 2 + ending + checks
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)) }; unsafe { NativeSwitch(voidptr(address))(&a[1], &b[2], &expected[4]) }
			assert word(actual, 4, count) == word(expected, 4, count) & full && word(actual, 4, count) <= full, c.name; if pair { assert actual[16] == expected[16] & 1 && actual[16] <= 1 }
			for j in 0 .. 32 { if (j < 4 || j >= 4 + count) && !(pair && j == 16) { assert actual[j] == 0xcc && expected[j] == 0xcc } }; comparisons++
		} }
		for j in 0 .. 32 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound - 1) { panic('switch budget accepted') }; unchanged(actual); budgets++
		scope := bodies.scopes[function + 1]; slot := scope.instructions_start + 3; saved := p.instructions[slot]
		for changed in [airbitcode.IRTypedInstruction{...saved, flags: 1}, airbitcode.IRTypedInstruction{...saved, opcode: 1}, airbitcode.IRTypedInstruction{...saved, operands_count: 0}, airbitcode.IRTypedInstruction{...saved, operands_count: 66}, airbitcode.IRTypedInstruction{...saved, targets_count: 0}, airbitcode.IRTypedInstruction{...saved, targets_count: saved.targets_count + 1}, airbitcode.IRTypedInstruction{...saved, source_type: -1}, airbitcode.IRTypedInstruction{...saved, indices_count: 1}, airbitcode.IRTypedInstruction{...saved, targets_start: -1}, airbitcode.IRTypedInstruction{...saved, operands_start: -1}] { p.instructions[slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('switch metadata accepted') }; unchanged(actual); metadata++ }; p.instructions[slot] = saved
		target := p.targets[saved.targets_start]; for bad in [scope.blocks_start, scope.blocks_start - 1, scope.blocks_start + scope.blocks_count, p.targets[saved.targets_start + 1]] { p.targets[saved.targets_start] = bad; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('switch destination accepted') }; unchanged(actual); metadata++ }; p.targets[saved.targets_start] = target
		literal := p.operands[saved.operands_start + 1]; p.operands[saved.operands_start + 1] = airbitcode.IRTypedOperand{...literal, number: p.operands[saved.operands_start].number}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('nonliteral case accepted') }; unchanged(actual); p.operands[saved.operands_start + 1] = literal; metadata++
		if values.len > 1 { other := p.operands[saved.operands_start + 2]; p.operands[saved.operands_start + 2] = airbitcode.IRTypedOperand{...other, number: literal.number}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('duplicate case accepted') }; unchanged(actual); p.operands[saved.operands_start + 2] = other; metadata++ }
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == if c.bits == 2 { u32(3) } else { u32(2) } { wrong = i; break } }; assert wrong >= 0
		for at in saved.operands_start .. saved.operands_start + saved.operands_count { operand := p.operands[at]; p.operands[at] = airbitcode.IRTypedOperand{...operand, type_index: wrong}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('switch operand type accepted') }; unchanged(actual); p.operands[at] = operand; types++ }
		phi_slot := bodies.blocks[scope.blocks_start + scope.blocks_count - 1].first; phi := p.instructions[phi_slot]
		for changed in [airbitcode.IRTypedInstruction{...phi, operands_count: 0}, airbitcode.IRTypedInstruction{...phi, targets_count: 0}, airbitcode.IRTypedInstruction{...phi, result_type: -1}] { p.instructions[phi_slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('switch PHI metadata accepted') }; unchanged(actual); metadata++ }; p.instructions[phi_slot] = phi
		pred := p.targets[phi.targets_start]; for bad in [scope.blocks_start, p.targets[phi.targets_start + 1], scope.blocks_start + scope.blocks_count] { p.targets[phi.targets_start] = bad; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('switch PHI predecessor accepted') }; unchanged(actual); metadata++ }; p.targets[phi.targets_start] = pred
		dead_slot := bodies.blocks[scope.blocks_start + scope.blocks_count - 2].first; dead := p.instructions[dead_slot]; p.instructions[dead_slot] = airbitcode.IRTypedInstruction{...dead, flags: u64(1) << 32}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound) { panic('default metadata accepted') }; unchanged(actual); p.instructions[dead_slot] = dead; metadata++
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, bound)!.steps <= bound
		unsafe { values.free(); a.free(); b.free(); actual.free(); expected.free(); bindings.free() }
	}
	for guard in guards {
		mut bytes := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		if _ := p.run_memory_function(ir, stream, pools, bodies, function_index(ir, guard.name), mut bindings, 32) { panic('switch condition guard accepted') }
		for j in 0 .. 16 { assert bytes[j] == if guard.early && j == 0 { u8(17) } else { u8(0xcc) } }; rejected++; unsafe { bytes.free(); bindings.free() }
	}
	for bits in 1 .. 65 {
		count := (bits + 7) / 8; mut a := []u8{len: 8}; mut bytes := []u8{len: 16, init: 0xcc}; mut expected := bytes.clone(); mut bindings := [airbitcode.IRMemoryBinding{data: bytes, writable: true}]
		assert p.run_memory_function(ir, stream, pools, bodies, function_index(ir, 'frozen_${bits}'), mut bindings, 7)!.steps == 5
		assert word(bytes, 0, count) == u64(7) & mask(bits); for j in count .. 16 { assert bytes[j] == 0xcc }; choices++
		mut empty_bindings := [airbitcode.IRMemoryBinding{data: a}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]; index := function_index(ir, 'empty_${bits}'); address := C.LLVMGetFunctionAddress(engine, ('empty_${bits}').str); assert address != 0
		for variant in 0 .. 2 { for j in 0 .. 8 { a[j] = if variant == 0 { u8(0) } else { u8(mask(bits) >> u32(8 * j)) } }; for j in 0 .. 16 { bytes[j] = 0xcc; expected[j] = 0xcc }; assert p.run_memory_function(ir, stream, pools, bodies, index, mut empty_bindings, 5)!.steps == 5; unsafe { NativeTwo(voidptr(address))(a.data, expected.data) }; assert bytes == expected; comparisons++ }
		unsafe { a.free(); bytes.free(); expected.free(); bindings.free(); empty_bindings.free() }
	}
	mut input := [u8(0)]; mut output := []u8{len: 16, init: 0xcc}; mut expected := output.clone(); mut bindings := [airbitcode.IRMemoryBinding{data: input}, airbitcode.IRMemoryBinding{data: output, writable: true}]
	for name in ['cap_64', 'nested'] {
		index := function_index(ir, name); bound := if name == 'cap_64' { 197 } else { 21 }; address := C.LLVMGetFunctionAddress(engine, name.str); assert address != 0
		for value in 0 .. 256 { input[0] = u8(value); for j in 0 .. 16 { output[j] = 0xcc; expected[j] = 0xcc }; checks := if name == 'cap_64' { 5 + if value < 64 { value + 1 } else { 64 } } else { 12 + if value == 0 { 1 } else { 2 } + 1 }; assert p.run_memory_function(ir, stream, pools, bodies, index, mut bindings, bound)!.steps == checks; unsafe { NativeTwo(voidptr(address))(input.data, expected.data) }; assert output == expected; comparisons++ }
		for j in 0 .. 16 { output[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, index, mut bindings, bound - 1) { panic('maximum search bound ignored') }; unchanged(output)
	}
	if _ := p.run_memory_function(ir, stream, pools, bodies, function_index(ir, 'cap_65'), mut bindings, 300) { panic('65 cases accepted') }; unchanged(output)
	assert cases.len == 450 && comparisons == 286400 && metadata == 10343 && types == 1786 && budgets == 450 && rejected == 512 && choices == 64
	result := 'AIR-MEMORY-SWITCH: ${comparisons} exact native scalar/half/float/pair comparisons, i1-i64 case/default paths and PHIs, empty/64-case edges and nested searches; ${metadata} metadata/literal/target/PHI/default-block, ${types} type and ${budgets} conservative-budget controls before stores; ${rejected} poison/undef conditions with retained prior writes and ${choices} frozen choices; exact executed comparison costs, 65-case rejection, masked inputs, offsets/padding PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
