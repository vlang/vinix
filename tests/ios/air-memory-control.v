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
type NativeControl = fn (voidptr, voidptr, voidptr, voidptr)
struct Case { name string bits int kind string }
struct Guard { name string bits int pair bool frozen bool reject bool zero bool }
fn mask(bits int) u64 { return if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 } }
fn word(bytes []u8, offset int, count int) u64 {
	mut value := u64(0); for j in 0 .. count { value |= u64(bytes[offset + j]) << u32(8 * j) }; return value
}
fn function_index(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }; panic('missing ' + name)
}
fn unchanged(bytes []u8) { for byte in bytes { assert byte == 0xcc } }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/'); os.mkdir_all(out)!
	mut source := strings.new_builder(2097152); mut cases := []Case{}; mut guards := []Guard{}
	source.write_string('target datalayout = "e-p:64:64"\n')
	for bits in 1 .. 65 {
		cases << Case{'scalar_${bits}', bits, 'scalar'}
		if bits in [16, 32] { cases << Case{'float_${bits}', bits, 'float'} }
		for op in ['sadd', 'uadd', 'ssub', 'usub', 'smul', 'umul'] {
			cases << Case{'${op}_${bits}', bits, op}
			source.write_string('declare {i${bits}, i1} @llvm.${op}.with.overflow.i${bits}(i${bits}, i${bits})\n')
		}
	}
	for c in cases {
		bits := c.bits; pair := c.kind !in ['scalar', 'float']; typ := if c.kind == 'float' { if bits == 16 { 'half' } else { 'float' } } else { 'i${bits}' }; phi_type := if pair { '{i${bits}, i1}' } else { typ }
		left := if pair { 'call ${phi_type} @llvm.${c.kind}.with.overflow.i${bits}(${typ} %x, ${typ} %y)' } else if c.kind == 'float' { 'fneg ${typ} %x' } else { 'add ${typ} %x, 0' }
		right := if pair { 'call ${phi_type} @llvm.${c.kind}.with.overflow.i${bits}(${typ} %y, ${typ} %x)' } else if c.kind == 'float' { 'fneg ${typ} %y' } else { 'xor ${typ} %y, 0' }
		ending := if pair { '%v = extractvalue ${phi_type} %p, 0\n store ${typ} %v, ptr %out, align 1\n %f = extractvalue ${phi_type} %p, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n' } else { 'store ${typ} %p, ptr %out, align 1\n' }
		source.write_string('define void @${c.name}(ptr %a, ptr %b, ptr %cond, ptr %out) { entry: %x = load ${typ}, ptr %a, align 1\n %y = load ${typ}, ptr %b, align 1\n %c = load i1, ptr %cond, align 1\n store i8 17, ptr %out, align 1\n br i1 %c, label %left, label %right\n left: %l = ${left}\n br label %join\n right: %r = ${right}\n br label %join\n join: %p = phi ${phi_type} [%l, %left], [%r, %right]\n ${ending}ret void }\n')
	}
	for bits in [1, 2, 8, 16, 24, 32, 48, 64] { for pair in [false, true] { for side in 0 .. 2 { for state in ['poison', 'undef'] { for condition in ['true', 'false', 'poison', 'undef'] { for frozen in [false, true] {
		name := 'guard_${bits}_${pair}_${side}_${state}_${condition}_${frozen}'; typ := if pair { '{i${bits}, i1}' } else { 'i${bits}' }
		prefix := if pair { '%g = insertvalue ${typ} zeroinitializer, i${bits} ${u64(17) & mask(bits)}, 0\n %good = insertvalue ${typ} %g, i1 true, 1\n' } else { '' }; good := if pair { '%good' } else { (u64(17) & mask(bits)).str() }
		left := if side == 0 { state } else { good }; right := if side == 1 { state } else { good }
		chosen := condition == if side == 0 { 'true' } else { 'false' }
		reject := condition in ['poison', 'undef'] || (pair && state == 'undef') || (chosen && (state == 'undef' || !frozen))
		guards << Guard{name, bits, pair, frozen, reject, chosen}
		freezing := if frozen { '%frozen = freeze ${typ} %p\n' } else { '' }; value := if frozen { '%frozen' } else { '%p' }
		ending := if pair { '%v = extractvalue ${typ} ${value}, 0\n store i${bits} %v, ptr %out, align 1\n %f = extractvalue ${typ} ${value}, 1\n %d = getelementptr i8, ptr %out, i64 12\n store i1 %f, ptr %d, align 1\n' } else { 'store i${bits} ${value}, ptr %out, align 1\n' }
		source.write_string('define void @${name}(ptr %out) { entry: ${prefix}br i1 ${condition}, label %left, label %right\n left: br label %join\n right: br label %join\n join: %p = phi ${typ} [${left}, %left], [${right}, %right]\n ${freezing}${ending}ret void }\n')
	} } } } } }
	source.write_string('define void @nested(ptr %a, ptr %b, ptr %cond, ptr %out) { entry: %x = load i32, ptr %a, align 1\n %y = load i32, ptr %b, align 1\n %c = load i1, ptr %cond, align 1\n store i8 17, ptr %out, align 1\n br i1 %c, label %left, label %right\n left: %l = add i32 %x, 1\n br label %merge\n right: %r = add i32 %y, 2\n br label %merge\n merge: %v = phi i32 [%l, %left], [%r, %right]\n %k = phi i32 [%x, %left], [%y, %right]\n br i1 %c, label %t, label %f\n t: %tv = add i32 %v, %k\n br label %end\n f: %fv = sub i32 %v, %k\n br label %end\n end: %p = phi i32 [%tv, %t], [%fv, %f]\n %q = phi i32 [%k, %t], [%v, %f]\n %z = xor i32 %p, %q\n store i32 %z, ptr %out, align 1\n ret void }\n')
	source.write_string('define void @extent(ptr %cond, ptr %out) { entry: %c = load i1, ptr %cond, align 1\n store i8 17, ptr %out, align 1\n br i1 %c, label %left, label %right\n left: store i8 3, ptr %out, align 1\n br label %join\n right: %far = getelementptr i8, ptr %out, i64 64\n store i8 7, ptr %far, align 1\n br label %join\n join: ret void }\n')
	source.write_string('define void @dead_error(ptr %cond, ptr %out) { entry: %c = load i1, ptr %cond, align 1\n br i1 %c, label %safe, label %bad\n safe: store i32 17, ptr %out, align 1\n ret void\n bad: %q = udiv i32 1, 0\n store i32 %q, ptr %out, align 1\n ret void }\n')
	source.write_string('define void @early_return(ptr %cond, ptr %out) { entry: %c = load i1, ptr %cond, align 1\n br i1 %c, label %yes, label %no\n yes: store i32 17, ptr %out, align 1\n ret void\n no: ret void }\n')
	source.write_string('define void @poison_branch(ptr %out) { entry: store i8 17, ptr %out, align 1\n br i1 poison, label %left, label %right\n left: ret void\n right: ret void }\n')
	source.write_string('define void @looping(ptr %out) { entry: store i8 17, ptr %out, align 1\n br label %loop\n loop: br label %loop }\n')
	source.write_string('define void @backwards(ptr %out) { entry: store i8 17, ptr %out, align 1\n br label %later\n earlier: ret void\n later: br label %earlier }\n')
	source.write_string('define void @pointer_phi(ptr %out) { entry: br i1 true, label %left, label %right\n left: br label %join\n right: br label %join\n join: %p = phi ptr [%out, %left], [%out, %right]\n store i8 17, ptr %p, align 1\n ret void }\n')
	source.write_string('define void @dead_bad(ptr %out) { entry: store i8 17, ptr %out, align 1\n br i1 true, label %good, label %bad\n good: ret void\n bad: %p = alloca i32\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0, log
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }; pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; mut p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0; C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }; buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'control'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }; assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0; mut message := &char(unsafe { nil }); assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0; if message != unsafe { nil } { C.LLVMDisposeMessage(message) }; message = unsafe { nil }
	triple := C.LLVMGetDefaultTargetTriple(); C.LLVMSetTarget(module_ptr, triple); os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) } + '\n')!; C.LLVMDisposeMessage(triple); C.LLVMSetDataLayout(module_ptr, c'')
	mut options := C.LLVMMCJITCompilerOptions{}; C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions)); options.OptLevel = 2; options.EnableFastISel = 0
	mut engine := unsafe { nil }; assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0; defer { C.LLVMDisposeExecutionEngine(engine) }; os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
	mut comparisons := 0; mut metadata := 0; mut types := 0; mut budgets := 0; mut rejected := 0; mut choices := 0
	for c in cases {
		pair := c.kind !in ['scalar', 'float']; count := (c.bits + 7) / 8; full := mask(c.bits); sign := u64(1) << u32(c.bits - 1)
		function := function_index(ir, c.name); address := C.LLVMGetFunctionAddress(engine, c.name.str); assert address != 0; static_steps := if pair { 16 } else { 12 }
		profile := p.memory_function_profile(ir, stream, pools, bodies, function)!; assert profile.steps == static_steps; profile.free()
		edges := [u64(0), full, sign, sign - 1, (sign + 1) & full, u64(1), full - 1, 0xaaaaaaaaaaaaaaaa & full, 0x5555555555555555 & full, 0x0123456789abcdef & full, 0xfedcba9876543210 & full, sign >> 1]!
		mut a := []u8{len: 12}; mut b := []u8{len: 12}; mut cond := [u8(0)]; mut actual := []u8{len: 32, init: 0xcc}; mut expected := actual.clone()
		mut bindings := [airbitcode.IRMemoryBinding{data: a, offset: 1}, airbitcode.IRMemoryBinding{data: b, offset: 2}, airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: actual, offset: 4, writable: true}]
		for sample in 0 .. 160 { for condition in 0 .. 2 {
			x := if sample < 144 { edges[sample / 12] } else { u64(sample) * u64(0x9e3779b97f4a7c15) & full }; y := if sample < 144 { edges[sample % 12] } else { (~x ^ (x >> 17)) & full }
			for j in 0 .. count { a[1 + j] = u8(x >> u32(8 * j)); b[2 + j] = u8(y >> u32(8 * j)) }; cond[0] = u8(0xfe + condition); for j in 0 .. 32 { actual[j] = 0xcc; expected[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps)!.steps == static_steps - 2
			cond[0] = u8(condition); unsafe { NativeControl(voidptr(address))(&a[1], &b[2], cond.data, &expected[4]) }
			assert word(actual, 4, count) == word(expected, 4, count) & full && word(actual, 4, count) <= full, c.name
			if pair { assert actual[16] == expected[16] & 1 && actual[16] <= 1 }
			for j in 0 .. 32 { if (j < 4 || j >= 4 + count) && !(pair && j == 16) { assert actual[j] == 0xcc && expected[j] == 0xcc } }; comparisons++
		} }
		for j in 0 .. 32 { actual[j] = 0xcc }; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps - 1) { panic('short conservative budget accepted') }; unchanged(actual); budgets++
		scope := bodies.scopes[function + 1]; branch_slot := scope.instructions_start + 4; branch := p.instructions[branch_slot]; phi_slot := scope.instructions_start + 9; phi := p.instructions[phi_slot]
		for changed in [airbitcode.IRTypedInstruction{...branch, flags: 1}, airbitcode.IRTypedInstruction{...branch, opcode: 1}, airbitcode.IRTypedInstruction{...branch, operands_count: 2}, airbitcode.IRTypedInstruction{...branch, operands_count: 0}, airbitcode.IRTypedInstruction{...branch, targets_count: 0}, airbitcode.IRTypedInstruction{...branch, targets_count: 3}, airbitcode.IRTypedInstruction{...branch, indices_count: 1}, airbitcode.IRTypedInstruction{...branch, targets_start: -1}, airbitcode.IRTypedInstruction{...branch, operands_start: -1}] {
			p.instructions[branch_slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps) { panic('branch metadata accepted') }; unchanged(actual); metadata++
		}; p.instructions[branch_slot] = branch
		branch_target := p.targets[branch.targets_start]
		for target in [scope.blocks_start, scope.blocks_start - 1, scope.blocks_start + 4, p.targets[branch.targets_start + 1]] { p.targets[branch.targets_start] = target; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps) { panic('branch target accepted') }; unchanged(actual); metadata++ }; p.targets[branch.targets_start] = branch_target
		for changed in [airbitcode.IRTypedInstruction{...phi, flags: 1}, airbitcode.IRTypedInstruction{...phi, opcode: 1}, airbitcode.IRTypedInstruction{...phi, operands_count: 0}, airbitcode.IRTypedInstruction{...phi, targets_count: 1}, airbitcode.IRTypedInstruction{...phi, result_type: -1}, airbitcode.IRTypedInstruction{...phi, indices_count: 1}, airbitcode.IRTypedInstruction{...phi, targets_start: -1}, airbitcode.IRTypedInstruction{...phi, operands_start: -1}] {
			p.instructions[phi_slot] = changed; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps) { panic('PHI metadata accepted') }; unchanged(actual); metadata++
		}; p.instructions[phi_slot] = phi
		phi_target := p.targets[phi.targets_start]
		for target in [scope.blocks_start, p.targets[phi.targets_start + 1], scope.blocks_start + 4] { p.targets[phi.targets_start] = target; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps) { panic('PHI predecessor accepted') }; unchanged(actual); metadata++ }; p.targets[phi.targets_start] = phi_target
		mut wrong := -1; for i, typ in p.types { if typ.kind == .integer_t && typ.bits == if c.bits == 2 { u32(3) } else { u32(2) } { wrong = i; break } }; assert wrong >= 0
		for slot in [branch.operands_start, phi.operands_start, phi.operands_start + 1] { operand := p.operands[slot]; p.operands[slot] = airbitcode.IRTypedOperand{...operand, type_index: wrong}; if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps) { panic('control operand type accepted') }; unchanged(actual); p.operands[slot] = operand; types++ }
		dead_slot := scope.instructions_start + 7; dead := p.instructions[dead_slot]; p.instructions[dead_slot] = airbitcode.IRTypedInstruction{...dead, flags: u64(1) << 32}
		if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps) { panic('untaken metadata accepted') }; unchanged(actual); p.instructions[dead_slot] = dead; metadata++
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, static_steps)!.steps == static_steps - 2
		unsafe { a.free(); b.free(); cond.free(); actual.free(); expected.free(); bindings.free() }
	}
	for guard in guards {
		function := function_index(ir, guard.name); steps := (if guard.pair { 12 } else { 6 }) + int(guard.frozen); count := (guard.bits + 7) / 8
		mut bytes := []u8{len: 24, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: bytes, offset: 1, writable: true}]
		if guard.reject { if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, steps) { panic('guard accepted: ' + guard.name) }; unchanged(bytes); rejected++ }
		else {
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, steps)!.steps == steps - 1
			assert word(bytes, 1, count) == if guard.zero { u64(0) } else { u64(17) & mask(guard.bits) }, guard.name
			if guard.pair { assert bytes[13] == u8(!guard.zero) }; for j in 0 .. 24 { if (j < 1 || j >= 1 + count) && !(guard.pair && j == 13) { assert bytes[j] == 0xcc } }; choices++
		}; unsafe { bytes.free(); bindings.free() }
	}
	// Nested joins publish two PHIs together, then feed another branch and join.
	function := function_index(ir, 'nested'); address := C.LLVMGetFunctionAddress(engine, c'nested'); assert address != 0
	mut a := []u8{len: 4}; mut b := []u8{len: 4}; mut cond := [u8(0)]; mut bytes := []u8{len: 16, init: 0xcc}; mut expected := bytes.clone()
	mut nested_bindings := [airbitcode.IRMemoryBinding{data: a}, airbitcode.IRMemoryBinding{data: b}, airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: bytes, writable: true}]
	for sample in 0 .. 160 { for condition in 0 .. 2 {
		for j in 0 .. 4 { a[j] = u8((u32(sample) * u32(0x9e3779b9)) >> u32(8 * j)); b[j] = u8(~u32(sample) >> u32(8 * j)) }; cond[0] = u8(condition); for j in 0 .. 16 { bytes[j] = 0xcc; expected[j] = 0xcc }
		assert p.run_memory_function(ir, stream, pools, bodies, function, mut nested_bindings, 21)!.steps == 17; unsafe { NativeControl(voidptr(address))(a.data, b.data, cond.data, expected.data) }; assert bytes == expected; comparisons++
	} }
	mut special := 0
	for name in ['extent', 'dead_error', 'early_return'] {
		index := function_index(ir, name); limit := if name == 'extent' { 9 } else if name == 'dead_error' { 7 } else { 5 }
		mut output := []u8{len: 65, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: cond}, airbitcode.IRMemoryBinding{data: output, writable: true}]
		for condition in 0 .. 2 {
			cond[0] = u8(condition); for j in 0 .. 65 { output[j] = 0xcc }
			if name == 'extent' {
				assert p.run_memory_function(ir, stream, pools, bodies, index, mut bindings, limit)!.steps == if condition == 1 { 6 } else { 7 }
				for j in 0 .. 65 { assert output[j] == if j == 0 { if condition == 1 { u8(3) } else { u8(17) } } else if j == 64 && condition == 0 { u8(7) } else { u8(0xcc) } }
				for j in 0 .. 65 { output[j] = 0xcc }; bindings[1] = airbitcode.IRMemoryBinding{data: output, offset: 1, writable: true}; if _ := p.run_memory_function(ir, stream, pools, bodies, index, mut bindings, limit) { panic('inactive extent ignored') }; unchanged(output); bindings[1] = airbitcode.IRMemoryBinding{data: output, writable: true}
			} else if name == 'dead_error' && condition == 0 { if _ := p.run_memory_function(ir, stream, pools, bodies, index, mut bindings, limit) { panic('executed division accepted') }; unchanged(output) }
			else { assert p.run_memory_function(ir, stream, pools, bodies, index, mut bindings, limit)!.steps == if condition == 1 { 4 } else { 3 }; for j in 0 .. 65 { assert output[j] == if condition == 1 && j < 4 { if j == 0 { u8(17) } else { u8(0) } } else { u8(0xcc) } } }
			special++
		}; unsafe { output.free(); bindings.free() }
	}
	for name in ['looping', 'backwards', 'pointer_phi', 'dead_bad', 'poison_branch'] {
		mut output := []u8{len: 16, init: 0xcc}; mut bindings := [airbitcode.IRMemoryBinding{data: output, writable: true}]
		if _ := p.run_memory_function(ir, stream, pools, bodies, function_index(ir, name), mut bindings, 32) { panic('unsupported guard accepted: ' + name) }
		if name == 'poison_branch' { assert output[0] == 17; for j in 1 .. 16 { assert output[j] == 0xcc } } else { unchanged(output) }; special++; unsafe { output.free(); bindings.free() }
	}
	assert cases.len == 450 && comparisons == 144320 && metadata == 11250 && types == 1350 && budgets == 450 && guards.len == 512 && rejected == 384 && choices == 128 && special == 11
	result := 'AIR-MEMORY-CONTROL: ${comparisons} exact native integer/half/float/pair comparisons, both forward branches, lazy PHIs and nested parallel joins; ${metadata} metadata/target/dead-block, ${types} type and ${budgets} conservative budget controls before stores; ${guards.len} poison/undef/freeze cases (${rejected} rejected, ${choices} choices); ${special} extent/early-return/dead-error/loop/pointer-PHI/dynamic-write guards PASS\n'
	os.write_file(out + '/result.txt', result)!; print(result)
}
