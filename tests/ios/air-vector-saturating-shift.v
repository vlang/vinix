// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run: v -path '@vlib|compat/ios|@vmodules' run this_file LLVM_AS FRESH_EXTERNAL_DIR
// Native LLVM executes only defined shifts. Poison cases use an independent
// checked-doubling oracle and require a poison-store refusal from the interpreter.

import airbitcode
import os
import strings
import crypto.sha256

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
	OptLevel           u32
	CodeModel          int
	NoFramePointerElim int
	EnableFastISel     int
	MCJMM              voidptr
}

fn C.LLVMInitializeMCJITCompilerOptions(&C.LLVMMCJITCompilerOptions, usize)

type NativeCast = fn (voidptr, voidptr, voidptr)

fn assemble(assembler_path string, out string, source string) ![]u8 {
	assert !os.exists(out)
	os.mkdir_all(out)!
	os.write_file(out + '/input.ll', source)!
	mut a := os.new_process(assembler_path)
	a.set_args([out + '/input.ll', '-o', out + '/input.bc'])
	a.set_redirect_stdio_merged()
	a.run()
	log := a.stdout_slurp()
	a.wait()
	code := a.code
	a.close()
	os.write_file(out + '/assemble.log', log)!
	assert code == 0, log
	return os.read_bytes(out + '/input.bc')!
}

fn verify(data []u8) ! {
	context := C.LLVMContextCreate()
	defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'verify')
	defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut module_ptr := unsafe { nil }
	assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	defer { C.LLVMDisposeModule(module_ptr) }
	mut message := &char(unsafe { nil })
	assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
}

struct NativeModule {
	context voidptr
	buffer  voidptr
	engine  voidptr
}

fn native_module(data []u8, out string) !NativeModule {
	assert C.LLVMInitializeNativeTarget() == 0 && C.LLVMInitializeNativeAsmPrinter() == 0
	C.LLVMLinkInMCJIT()
	context := C.LLVMContextCreate()
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'vector-saturating-intrinsics')
	mut module_ptr := unsafe { nil }
	assert C.LLVMParseBitcodeInContext2(context, buffer, &module_ptr) == 0
	mut message := &char(unsafe { nil })
	assert C.LLVMVerifyModule(module_ptr, 2, &message) == 0
	if message != unsafe { nil } { C.LLVMDisposeMessage(message) }
	message = unsafe { nil }

	C.LLVMSetDataLayout(module_ptr, c'')
	triple := C.LLVMGetDefaultTargetTriple()
	C.LLVMSetTarget(module_ptr, triple)
	os.write_file(out + '/native-target.txt', unsafe { cstring_to_vstring(triple) })!
	C.LLVMDisposeMessage(triple)
	path := out + '/native-input.bc'
	assert C.LLVMWriteBitcodeToFile(module_ptr, path.str) == 0
	cpu := C.LLVMGetHostCPUName()
	features := C.LLVMGetHostCPUFeatures()
	os.write_file(out + '/native-features.txt', unsafe { cstring_to_vstring(cpu) } + '\n' + unsafe { cstring_to_vstring(features) } + '\n')!
	mut f := C.LLVMGetFirstFunction(module_ptr)
	for f != unsafe { nil } {
		C.LLVMAddTargetDependentFunctionAttr(f, c'target-cpu', cpu)
		C.LLVMAddTargetDependentFunctionAttr(f, c'target-features', features)
		f = C.LLVMGetNextFunction(f)
	}
	C.LLVMDisposeMessage(cpu)
	C.LLVMDisposeMessage(features)
	assert C.LLVMWriteBitcodeToFile(module_ptr, (out + '/native-input-features.bc').str) == 0
	mut options := C.LLVMMCJITCompilerOptions{}
	C.LLVMInitializeMCJITCompilerOptions(&options, sizeof(C.LLVMMCJITCompilerOptions))
	options.OptLevel = 2
	options.EnableFastISel = 0
	mut engine := unsafe { nil }
	assert C.LLVMCreateMCJITCompilerForModule(&engine, module_ptr, &options, sizeof(C.LLVMMCJITCompilerOptions), &message) == 0
	return NativeModule{context, buffer, engine}
}

fn (n NativeModule) close() {
	C.LLVMDisposeExecutionEngine(n.engine)
	C.LLVMDisposeMemoryBuffer(n.buffer)
	C.LLVMContextDispose(n.context)
}

struct Expected {
	value  u64
	poison bool
}

fn bit_mask(w u32) u64 { return if w == 64 { ~u64(0) } else { (u64(1) << w) - 1 } }

fn vector_shift_reference(signed bool, width u32, value u64, amount u64) Expected {
	mask := bit_mask(width)
	x := value & mask
	shift := amount & mask
	if shift >= u64(width) { return Expected{ poison: true } }
	if !signed {
		mut v := x
		for _ in u64(0) .. shift {
			if v > mask - v { return Expected{ value: mask } }
			v += v
		}
		return Expected{ value: v }
	}
	sign := u64(1) << (width - 1)
	maximum := i64(sign - 1)
	minimum := -maximum - 1
	mut v := if x & sign == 0 { i64(x) } else { -i64((~x) & mask) - 1 }
	for _ in u64(0) .. shift {
		if v > maximum / 2 { return Expected{ value: u64(maximum) } }
		if v < minimum / 2 { return Expected{ value: u64(minimum) & mask } }
		v += v
	}
	return Expected{ value: u64(v) & mask }
}

fn fi(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }
	panic(name)
}

fn main() {
	assert os.args.len == 3
	root := os.args[2]
	assert !os.exists(root)
	os.mkdir_all(root)!
	mut exact := 0
	mut poison := 0
	mut scalar := 0
	mut metadata := 0
	mut rows := os.create(root + '/comparisons.txt')!
	defer { rows.close() }
	for w in u32(1) .. 65 {
		out := root + '/w${w}'
		mut irtext := strings.new_builder(131072)
		irtext.write_string('target datalayout = "e-p:64:64"\n')
		for id in ['sshl.sat', 'ushl.sat'] {
			for n in 1 .. 17 {
				t := '<${n} x i${w}>'
				name := 'f_${id}_${n}'
				irtext.write_string('declare ${t} @llvm.${id}.v${n}i${w}(${t}, ${t})\n')
				mut ops := ''
				for arg in ['a', 'b'] {
					for lane in 0 .. n {
						ops += '%${arg}${lane} = insertelement ${t} ${if lane == 0 {
							'poison'
						} else {
							'%' + arg + (lane - 1).str()
						}}, i${w} %${arg}, i32 ${lane}\n'
					}
				}
				ops += '%r = call ${t} @llvm.${id}.v${n}i${w}(${t} %a${n - 1}, ${t} %b${n - 1})\n %v = extractelement ${t} %r, i32 ${n - 1}\n'
				if w != 64 { ops += '%wide = zext i${w} %v to i64\n' }
				v := if w == 64 { '%v' } else { '%wide' }
				irtext.write_string('define void @${name}(ptr %unused, ptr %src, ptr %out) { %a = load i${w}, ptr %src, align 1\n %bp = getelementptr i8, ptr %src, i64 8\n %b = load i${w}, ptr %bp, align 1\n store i8 17, ptr %out\n ${ops}%dst = getelementptr i8, ptr %out, i64 8\n store i64 ${v}, ptr %dst, align 1\n ret void }\n define i64 @s_${name}(i${w} %a, i${w} %b) { ${ops}ret i64 ${v} }\n')
			}
		}
		data := assemble(os.args[1], out, irtext.str())!
		verify(data)!
		stream := airbitcode.parse(data)!
		ir := stream.ir_module(data)!
		pools := ir.constant_pools(stream)!
		bodies := ir.function_bodies(stream, pools)!
		mut p := ir.typed_operands(stream, pools, bodies)!
		native := native_module(data, out)!
		m := bit_mask(w)
		sign := u64(1) << (w - 1)
		values := [u64(0), m, sign, sign - 1, sign + 1, u64(1), m - 1, u64(0xaaaaaaaaaaaaaaaa),
			u64(0x5555555555555555), u64(0x0123456789abcdef), u64(0xfedcba9876543210), sign >> 1]!
		shifts := [u64(0), 1, u64(w - 1), u64(w), u64(w + 1), m, 2, u64(w / 2), 31, 32, 63, 64]!
		for id in ['sshl.sat', 'ushl.sat'] {
			for n in 1 .. 17 {
				name := 'f_${id}_${n}'
				f := fi(ir, name)
				sf := fi(ir, 's_' + name)
				steps := bodies.scopes[f + 1].instructions_count
				ss := bodies.scopes[sf + 1].instructions_count
				profile := p.memory_function_profile(ir, stream, pools, bodies, f)!
				assert profile.arguments[1].minimum_size == 8 + int((w + 7) / 8) && profile.arguments[2].minimum_size == 16
				profile.free()
				address := C.LLVMGetFunctionAddress(native.engine, name.str)
				assert address != 0
				mut unused := [u8(0)]
				mut input := []u8{len: 17}
				mut output := []u8{len: 24, init: 0xcc}
				mut reference := output.clone()
				mut bs := [airbitcode.IRMemoryBinding{ data: unused },
					airbitcode.IRMemoryBinding{ data: input, offset: 1 },
					airbitcode.IRMemoryBinding{ data: output, writable: true }]
				for x in values {
					for y in shifts {
						a := x | ~m
						b := y | ~m
						expected := vector_shift_reference(id == 'sshl.sat', w, a, b)
						for j in 0 .. 8 {
							input[1 + j] = u8(a >> u32(j * 8))
							input[9 + j] = u8(b >> u32(j * 8))
						}
						for j in 0 .. 24 {
							output[j] = 0xcc
							reference[j] = 0xcc
						}
						result := p.run_scalar_function(ir, stream, pools, bodies, sf, [
							a,
							b,
						], ss)!
						integer := p.run_integer_function(ir, stream, pools, bodies, sf, [
							a,
							b,
						], ss)!
						assert result.poison == expected.poison && integer.poison == expected.poison
						assert result.steps == ss && integer.steps == ss
						if !expected.poison {
							assert result.value == expected.value && integer.value == expected.value
						}
						scalar += 2
						if expected.poison {
							if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
								panic('poison stored')
							} else {
								assert err.msg() == 'AIR memory execution: poison store'
							}
							poison++
						} else {
							assert p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps)!.steps == steps
							for j in 0 .. 8 {
								input[1 + j] = u8((a & m) >> u32(j * 8))
								input[9 + j] = u8((b & m) >> u32(j * 8))
							}
							unsafe { NativeCast(voidptr(address))(unused.data, &input[1], reference.data) }
							assert output == reference
							exact++
						}
						for j, v in output {
							assert v == if j == 0 {
								u8(17)
							} else if !expected.poison && j >= 8 && j < 16 {
								u8(expected.value >> u32((j - 8) * 8))
							} else {
								u8(0xcc)
							}
						}
						rows.writeln('${w} ${n} ${id} ${a} ${b} ${expected.poison} ${expected.value}')!
					}
				}
				for j in 0 .. 24 { output[j] = 0xcc }
				metadata += metadata_checks(ir, stream, pools, bodies, mut p, f, mut bs, output, steps)!
				if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps - 1) {
					panic('budget')
				}
				for v in output {
					assert v == 0xcc
				}
				unsafe {
					unused.free()
					input.free()
					output.free()
					reference.free()
					bs.free()
				}
			}
		}
		native.close()
		p.free()
		bodies.free()
		pools.free()
		ir.free()
		stream.free()
	}
	assert exact + poison == 294912 && scalar == 589824
	os.write_file(root + '/result.txt', 'VECTOR-SAT-SHIFT-LLVM: ${exact} exact native comparisons, ${poison} poison-store refusals, ${scalar} scalar/integer results, ${metadata} malformed calls and 2048 short budgets PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}

fn unchanged(data []u8) {
	for v in data {
		assert v == 0xcc
	}
}

fn metadata_checks(ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, mut p airbitcode.IRTypedProgram, f int, mut bs []airbitcode.IRMemoryBinding, output []u8, steps int) !int {
	scope := bodies.scopes[f + 1]
	mut checks := 0
	for index in scope.instructions_start .. scope.instructions_start + scope.instructions_count {
		op := p.instructions[index]
		if stream.records[bodies.instructions[index].record].code != 34 { continue }
		for changed in [airbitcode.IRTypedInstruction{ ...op, flags: 0 },
			airbitcode.IRTypedInstruction{ ...op, flags: 32769 },
			airbitcode.IRTypedInstruction{ ...op, opcode: 1 },
			airbitcode.IRTypedInstruction{ ...op, calling_convention: 8 },
			airbitcode.IRTypedInstruction{ ...op, fast_math_flags: 1 },
			airbitcode.IRTypedInstruction{ ...op, attribute_set: 1 },
			airbitcode.IRTypedInstruction{ ...op, call_signature: -1 },
			airbitcode.IRTypedInstruction{ ...op, callee_function: -1 },
			airbitcode.IRTypedInstruction{ ...op, callee_function: ir.functions.len },
			airbitcode.IRTypedInstruction{ ...op, operands_count: 0 },
			airbitcode.IRTypedInstruction{ ...op, operands_count: 1 },
			airbitcode.IRTypedInstruction{ ...op, operands_count: 5 },
			airbitcode.IRTypedInstruction{ ...op, result_type: -1 },
			airbitcode.IRTypedInstruction{ ...op, targets_count: 1 },
			airbitcode.IRTypedInstruction{ ...op, indices_count: 1 }] {
			p.instructions[index] = changed
			if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
				panic('metadata admitted')
			}
			unchanged(output)
			checks++
		}
		p.instructions[index] = op
		for operand in 0 .. op.operands_count {
			slot := op.operands_start + operand
			original := p.operands[slot]
			changes := if operand == 0 {
				[airbitcode.IRTypedOperand{ ...original, number: ~u32(0) },
					airbitcode.IRTypedOperand{ ...original, type_index: -1 }]
			} else {
				[airbitcode.IRTypedOperand{ ...original, number: ~u32(0) },
					airbitcode.IRTypedOperand{ ...original, number: bodies.instructions[index].next_value },
					airbitcode.IRTypedOperand{ ...original, type_index: -1 }]
			}
			for changed in changes {
				p.operands[slot] = changed
				if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
					panic('source admitted')
				}
				unchanged(output)
				checks++
			}
			p.operands[slot] = original
			unsafe { changes.free() }
		}
	}
	return checks
}
