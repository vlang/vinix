// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native comparisons execute only defined loads, stores and bitwise operations.
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

fn fi(ir airbitcode.IRModule, name string) int {
	for i, f in ir.functions { if f.name == name { return i } }
	panic(name)
}

fn unchanged(data []u8) {
	for b in data {
		assert b == 0xcc
	}
}

fn main() {
	assert os.args.len == 3
	root := os.args[2]
	assert !os.exists(root)
	os.mkdir_all(root)!
	mut comparisons := 0
	mut refusals := 0
	mut states := 0
	mut rows := os.create(root + '/comparisons.txt')!
	defer { rows.close() }
	for element in 0 .. 10 {
		bits := if element < 8 {
			(element + 1) * 8
		} else if element == 8 {
			16
		} else {
			32
		}
		t := if element < 8 {
			'i${bits}'
		} else if element == 8 {
			'half'
		} else {
			'float'
		}
		out := root + '/type${element}'
		mut source := strings.new_builder(32768)
		source.write_string('target datalayout = "e-p:64:64"\n')
		for n in 1 .. 17 {
			v := '<${n} x ${t}>'
			i := '<${n} x i${bits}>'
			mut ones := ''
			for lane in 0 .. n { ones += if lane == 0 { 'i${bits} -1' } else { ', i${bits} -1' } }
			for mode in ['copy', 'invert', 'snapshot'] {
				cast := if element < 8 { '' } else { '%raw = bitcast ${v} %a to ${i}\n' }
				back := if element < 8 { '' } else { '%result = bitcast ${i} %changed to ${v}\n' }
				ops := if mode == 'invert' {
					cast + '%changed = xor ${i} ${if element < 8 { '%a' } else { '%raw' }}, <${ones}>\n' + back
				} else {
					''
				}
				result := if mode != 'invert' {
					'%a'
				} else if element < 8 {
					'%changed'
				} else {
					'%result'
				}
				// Snapshot stores back to an overlapping address through a second binding.
				source.write_string('define void @${mode}_${n}(ptr %unused, ptr %src, ptr %dst) { %a = load ${v}, ptr %src, align 1\n ${ops}store ${v} ${result}, ptr %dst, align 1\n ret void }\n')
			}
			for state in ['poison', 'undef'] {
				for frozen in [false, true] {
					source.write_string('define void @${state}_${frozen}_${n}(ptr %unused, ptr %src, ptr %dst) { store i8 17, ptr %dst\n %a = load ${v}, ptr %src, align 1\n %b = insertelement ${v} %a, ${t} ${state}, i32 ${n - 1}\n ${if frozen {
						'%c = freeze ' + v + ' %b\n'
					} else {
						''
					}}%p = getelementptr i8, ptr %dst, i64 1\n store ${v} ${if frozen {
						'%c'
					} else {
						'%b'
					}}, ptr %p, align 1\n ret void }\n')
				}
			}
		}
		data := assemble(os.args[1], out, source.str())!
		verify(data)!
		stream := airbitcode.parse(data)!
		ir := stream.ir_module(data)!
		pools := ir.constant_pools(stream)!
		bodies := ir.function_bodies(stream, pools)!
		mut p := ir.typed_operands(stream, pools, bodies)!
		native := native_module(data, out)!
		for n in 1 .. 17 {
			bytes := n * bits / 8
			for mode in ['copy', 'invert', 'snapshot'] {
				name := '${mode}_${n}'
				f := fi(ir, name)
				steps := bodies.scopes[f + 1].instructions_count
				profile := p.memory_function_profile(ir, stream, pools, bodies, f)!
				assert profile.arguments[1].minimum_size == u64(bytes) && profile.arguments[1].readable && !profile.arguments[1].writable
				assert profile.arguments[2].minimum_size == u64(bytes) && profile.arguments[2].writable
				profile.free()
				address := C.LLVMGetFunctionAddress(native.engine, name.str)
				assert address != 0
				for sample in 0 .. 128 {
					mut input := []u8{len: bytes + 8, init: u8(index * 37 + sample)}
					// Include signed zeros, infinities, signaling/quiet NaNs and
					// subnormals as raw half/float bits, alongside byte patterns.
					if sample < 16 {
						edges := [u64(0), ~u64(0), 0x80000000, 0x7f800000, 0xff800000, 0x7f800001,
							0x7fc12345, 1, 0x7fffff, 0x7f7fffff, 0x8000, 0x7c00, 0xfc00, 0x7c01,
							0x7e55, 0x3ff]!
						for lane in 0 .. n {
							word := edges[(sample + lane) % edges.len]
							for byte in 0 .. bits / 8 {
								input[1 + lane * bits / 8 + byte] = u8(word >> u32(byte * 8))
							}
						}
					}
					mut output := []u8{len: bytes + 10, init: 0xcc}
					mut reference := output.clone()
					mut shared := input.clone()
					mut native_shared := input.clone()
					mut unused := [u8(0)]
					mut bs := [airbitcode.IRMemoryBinding{ data: unused },
						airbitcode.IRMemoryBinding{ data: input, offset: 1 },
						airbitcode.IRMemoryBinding{ data: output, offset: 3, writable: true }]
					if mode == 'snapshot' {
						bs[1] = airbitcode.IRMemoryBinding{ data: shared, offset: 1 }
						bs[2] = airbitcode.IRMemoryBinding{ data: shared, offset: 2, writable: true }
					}
					assert p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps)!.steps == steps
					if mode == 'snapshot' {
						unsafe { NativeCast(voidptr(address))(unused.data, &native_shared[1], &native_shared[2]) }
						assert shared == native_shared
						for j in 0 .. bytes {
							assert shared[j + 2] == input[j + 1]
						}
					} else {
						unsafe { NativeCast(voidptr(address))(unused.data, &input[1], &reference[3]) }
						assert output == reference
						for j, b in output {
							assert b == if j >= 3 && j < bytes + 3 {
								if mode == 'invert' { ~input[j - 2] } else { input[j - 2] }
							} else {
								u8(0xcc)
							}
						}
					}
					rows.writeln('${element} ${n} ${mode} ${sample} PASS')!
					comparisons++
					unsafe {
						input.free()
						output.free()
						reference.free()
						shared.free()
						native_shared.free()
						unused.free()
						bs.free()
					}
				}
				mut unused := [u8(0)]
				mut input := []u8{len: bytes + 8, init: 0x5a}
				mut output := []u8{len: bytes + 8, init: 0xcc}
				mut bs := [airbitcode.IRMemoryBinding{ data: unused },
					airbitcode.IRMemoryBinding{ data: input },
					airbitcode.IRMemoryBinding{ data: output, writable: true }]
				if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps - 1) {
					panic('short budget')
				}
				unchanged(output)
				refusals++
				for bad in [airbitcode.IRMemoryBinding{ data: output },
					airbitcode.IRMemoryBinding{ data: output, offset: 9, writable: true }] {
					bs[2] = bad
					if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
						panic('binding guard')
					}
					unchanged(output)
					refusals++
				}
				bs[2] = airbitcode.IRMemoryBinding{ data: output, writable: true }
				if _ := p.run_void_function(ir, stream, pools, bodies, f, [u64(0), 0, 0], steps) {
					panic('void API accepted memory')
				}
				refusals++
				for index in bodies.scopes[f + 1].instructions_start .. bodies.scopes[f + 1].instructions_start + steps {
					op := p.instructions[index]
					if stream.records[bodies.instructions[index].record].code !in [
						u64(20),
						24,
						44,
					]! {
						continue
					}
					for changed in [
						airbitcode.IRTypedInstruction{ ...op, is_volatile: true },
						airbitcode.IRTypedInstruction{ ...op, alignment: 0 },
						airbitcode.IRTypedInstruction{ ...op, opcode: 1 },
						airbitcode.IRTypedInstruction{ ...op, flags: 1 },
						airbitcode.IRTypedInstruction{ ...op, indices_count: 1 },
						airbitcode.IRTypedInstruction{ ...op, operands_count: 0 },
						airbitcode.IRTypedInstruction{ ...op, source_type: -1 },
					] {
						p.instructions[index] = changed
						if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
							panic('access metadata')
						}
						unchanged(output)
						refusals++
					}
					p.instructions[index] = op
				}
				unsafe {
					unused.free()
					input.free()
					output.free()
					bs.free()
				}
			}
			for state in ['poison', 'undef'] {
				for frozen in [false, true] {
					f := fi(ir, '${state}_${frozen}_${n}')
					steps := bodies.scopes[f + 1].instructions_count
					mut unused := [u8(0)]
					mut input := []u8{len: bytes, init: 0x55}
					mut output := []u8{len: bytes + 2, init: 0xcc}
					mut bs := [airbitcode.IRMemoryBinding{ data: unused },
						airbitcode.IRMemoryBinding{ data: input },
						airbitcode.IRMemoryBinding{ data: output, writable: true }]
					if frozen {
						assert p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps)!.steps == steps
					} else {
						if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
							panic('indeterminate store')
						} else {
							assert err.msg() == if state == 'poison' {
								'AIR memory execution: poison store'
							} else {
								'AIR memory execution: undef vector store'
							}
						}
					}
					for j, b in output {
						assert b == if j == 0 {
							u8(17)
						} else if frozen && j <= bytes {
							if j > bytes - bits / 8 { u8(0) } else { u8(0x55) }
						} else {
							u8(0xcc)
						}
					}
					states++
					unsafe {
						unused.free()
						input.free()
						output.free()
						bs.free()
					}
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
	controls(os.args[1], root + '/controls')!
	assert comparisons == 61440 && states == 640
	os.write_file(root + '/result.txt', 'AIR-MEMORY-VECTOR: ${comparisons} exact native copies/inversions/overlap snapshots, ${states} poison/undef/freeze checks, ${refusals} bounds/budget/metadata/API refusals PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}

fn controls(assembler string, out string) ! {
	mut source := strings.new_builder(131072)
	source.write_string('target datalayout = "e-p:64:64"\n')
	for i, t in ['<2 x i7>', '<17 x i8>', '<2 x double>', '<2 x ptr>', '<vscale x 2 x i32>'] {
		source.write_string('define void @bad_${i}(ptr %src, ptr %dst) { store i8 17, ptr %dst\n %v = load ${t}, ptr %src, align 1\n ret void }\n')
	}
	source.write_string('define void @cold(ptr %src, ptr %dst) { store i8 17, ptr %dst\n br i1 true, label %done, label %bad\n bad: %v = load <2 x i7>, ptr %src, align 1\n ret void\n done: ret void }\n')
	source.write_string('define void @constant(ptr %src, ptr %dst) { store <3 x i24> <i24 1193046, i24 11259375, i24 66051>, ptr %dst, align 1\n ret void }\n')
	source.write_string('define void @aligned(ptr %src, ptr %dst) { %v = load <2 x i32>, ptr %src, align 8\n store <2 x i32> %v, ptr %dst, align 8\n ret void }\n')
	source.write_string('define void @constant_space(ptr %src, ptr addrspace(2) %dst) { store <2 x i32> zeroinitializer, ptr addrspace(2) %dst, align 1\n ret void }\n')
	source.write_string('define void @gep(ptr %src, ptr %dst) { %p = getelementptr <3 x i24>, ptr %src, i64 1\n %v = load <3 x i24>, ptr %p, align 1\n store <3 x i24> %v, ptr %dst, align 1\n ret void }\n')
	for n in [4096, 4097] {
		source.write_string('define void @slots_${n}(ptr %src, ptr %dst) { store i8 17, ptr %dst\n')
		for i in 0 .. n { source.write_string('%v${i} = load <1 x i8>, ptr %src, align 1\n') }
		source.write_string('ret void }\n')
	}
	data := assemble(assembler, out, source.str())!
	verify(data)!
	stream := airbitcode.parse(data)!
	defer { stream.free() }
	ir := stream.ir_module(data)!
	defer { ir.free() }
	pools := ir.constant_pools(stream)!
	defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!
	defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!
	defer { p.free() }
	mut input := []u8{len: 64, init: u8(index)}
	mut output := []u8{len: 32, init: 0xcc}
	mut bs := [airbitcode.IRMemoryBinding{ data: input },
		airbitcode.IRMemoryBinding{ data: output, writable: true }]
	for name in ['bad_0', 'bad_1', 'bad_2', 'bad_3', 'bad_4', 'cold', 'constant_space', 'slots_4097'] {
		if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, name), mut bs, 10000) {
			panic(name)
		}
		unchanged(output)
	}
	assert p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'slots_4096'), mut bs, 4098)!.steps == 4098
	assert output[0] == 17
	for j in 0 .. output.len { output[j] = 0xcc }
	p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'constant'), mut bs, 2)!
	assert output[..9] == [u8(0x56), 0x34, 0x12, 0xef, 0xcd, 0xab, 3, 2, 1]
	for j in 9 .. output.len {
		assert output[j] == 0xcc
	}
	for j in 0 .. output.len { output[j] = 0xcc }
	p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'gep'), mut bs, 4)!
	// <3 x i24> has nine stored bytes but a sixteen-byte allocation stride.
	assert output[..9] == input[16..25]
	for j in 0 .. output.len { output[j] = 0xcc }
	if _ := p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'aligned'), mut bs, 3) {
		panic('base alignment')
	}
	unchanged(output)
	bs[0] = airbitcode.IRMemoryBinding{ data: input, base_alignment: 8 }
	bs[1] = airbitcode.IRMemoryBinding{ data: output, base_alignment: 8, writable: true }
	p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'aligned'), mut bs, 3)!
	assert output[..8] == input[..8]
	unsafe {
		input.free()
		output.free()
		bs.free()
	}
	os.write_file(out + '/result.txt', 'AIR-MEMORY-VECTOR-CONTROLS: unsupported shapes, cold blocks, readonly space, 4096/4097 slots, constant stores, vector GEP allocation stride and explicit alignment PASS\n')!
}
