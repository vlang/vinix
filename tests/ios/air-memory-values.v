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
	root := os.abs_path(os.args[2])
	assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!
	mut cases := 0
	mut guards := 0
	mut rows := os.create(root + '/comparisons.txt')!
	defer { rows.close() }
	for kind in 1 .. 67 {
		bits := if kind <= 64 {
			kind
		} else if kind == 65 {
			16
		} else {
			32
		}
		t := if kind <= 64 {
			'i${bits}'
		} else if kind == 65 {
			'half'
		} else {
			'float'
		}
		mask := if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 }
		mut source := strings.new_builder(131072)
		source.write_string('target datalayout = "e-p:64:64"\n')
		for n in 0 .. 17 {
			lanes := if n == 0 { 1 } else { n }
			typ := if n == 0 { t } else { '<${n} x ${t}>' }
			integer := if n == 0 { 'i${bits}' } else { '<${n} x i${bits}>' }
			source.write_string('define void @f_${n}(${typ} %a, ptr %out, ${typ} %b) { store i8 17, ptr %out\n')
			if kind > 64 {
				source.write_string('%ia = bitcast ${typ} %a to ${integer}\n %ib = bitcast ${typ} %b to ${integer}\n')
			}
			source.write_string('%x = xor ${integer} ${if kind > 64 { '%ia' } else { '%a' }}, ${if kind > 64 {
				'%ib'
			} else {
				'%b'
			}}\n')
			for lane in 0 .. lanes {
				if n != 0 {
					source.write_string('%lane${lane} = extractelement ${integer} %x, i32 ${lane}\n')
				}
				value := if n == 0 { '%x' } else { '%lane${lane}' }
				if bits != 64 {
					source.write_string('%wide${lane} = zext i${bits} ${value} to i64\n')
				}
				source.write_string('%p${lane} = getelementptr i8, ptr %out, i64 ${8 + lane * 8}\n store i64 ${if bits == 64 {
					value
				} else {
					'%wide' + lane.str()
				}}, ptr %p${lane}, align 1\n')
			}
			source.write_string('ret void }\n')
			source.write_string('define void @native_${n}(ptr %unused, ptr %src, ptr %out) {\n')
			for side in 0 .. 2 {
				for lane in 0 .. lanes {
					source.write_string('%p${side}_${lane} = getelementptr i8, ptr %src, i64 ${(side * lanes + lane) * 8}\n %v${side}_${lane} = load ${t}, ptr %p${side}_${lane}, align 1\n')
					if n != 0 {
						source.write_string('%s${side}_${lane} = insertelement ${typ} ${if lane == 0 {
							'poison'
						} else {
							'%s' + side.str() + '_' + (lane - 1).str()
						}}, ${t} %v${side}_${lane}, i32 ${lane}\n')
					}
				}
			}
			a := if n == 0 { '%v0_0' } else { '%s0_' + (lanes - 1).str() }
			b := if n == 0 { '%v1_0' } else { '%s1_' + (lanes - 1).str() }
			source.write_string('call void @f_${n}(${typ} ${a}, ptr %out, ${typ} ${b})\n ret void }\n')
		}
		out := root + '/kind${kind}'
		data := assemble(os.args[1], out, source.str())!
		verify(data)!
		stream := airbitcode.parse(data)!
		ir := stream.ir_module(data)!
		pools := ir.constant_pools(stream)!
		bodies := ir.function_bodies(stream, pools)!
		p := ir.typed_operands(stream, pools, bodies)!
		native := native_module(data, out)!
		for n in 0 .. 17 {
			lanes := if n == 0 { 1 } else { n }
			f := fi(ir, 'f_${n}')
			plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
			steps := plan.steps()
			assert plan.argument_count() == 3 && plan.argument(0)!.value_bits == u32(bits) && plan.argument(0)!.value_lanes == lanes && plan.argument(1)!.minimum_size == u64(8 + 8 * lanes) && plan.argument(2)!.value_lanes == lanes
			address := C.LLVMGetFunctionAddress(native.engine, ('native_${n}').str)
			assert address != 0
			for sample in 0 .. 32 {
				mut a := []u64{len: lanes}
				mut b := a.clone()
				mut input := []u8{len: lanes * 16}
				mut unused := [u8(0)]
				mut actual := []u8{len: 8 * lanes + 16, init: 0xcc}
				mut reference := actual.clone()
				for lane in 0 .. lanes {
					a[lane] = (u64(sample + lane) * u64(0x9e3779b97f4a7c15)) | ~mask
					b[lane] = (u64(sample * 7 + lane + 3) * u64(0x123456789abcdef)) | ~mask
					if sample < 16 && kind > 64 {
						edges := [u64(0), ~u64(0), 0x80000000, 0x7f800000, 0xff800000, 0x7f800001,
							0x7fc12345, 1, 0x7fffff, 0x7f7fffff, 0x8000, 0x7c00, 0xfc00, 0x7c01,
							0x7e55, 0x3ff]!
						a[lane] = edges[(sample + lane) % edges.len] | ~mask
						b[lane] = edges[(sample + lane + 3) % edges.len] | ~mask
					}
					for j in 0 .. 8 {
						input[lane * 8 + j] = u8((a[lane] & mask) >> u32(j * 8))
						input[(lanes + lane) * 8 + j] = u8((b[lane] & mask) >> u32(j * 8))
					}
				}
				unsafe { NativeCast(voidptr(address))(unused.data, input.data, &reference[3]) }
				mut bs := [airbitcode.IRMemoryBinding{ values: a },
					airbitcode.IRMemoryBinding{ data: actual, offset: 3, writable: true },
					airbitcode.IRMemoryBinding{ values: b }]
				for prepared in [true, false] {
					for j in 0 .. actual.len { actual[j] = 0xcc }
					result := if prepared {
						plan.run(mut bs, steps)!
					} else {
						p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps)!
					}
					assert result.steps == steps && actual == reference
					for j, v in actual {
						expected := if j == 3 {
							u8(17)
						} else if j >= 11 && j < 11 + 8 * lanes {
							lane := (j - 11) / 8
							u8(((a[lane] ^ b[lane]) & mask) >> u32(((j - 11) % 8) * 8))
						} else {
							u8(0xcc)
						}
						assert v == expected
					}
				}
				rows.writeln('${kind} ${n} ${sample} PASS')!
				cases++
				unsafe {
					a.free()
					b.free()
					input.free()
					unused.free()
					actual.free()
					reference.free()
					bs.free()
				}
			}
			mut a := []u64{len: lanes, init: 7}
			mut wrong := []u64{len: lanes + 1}
			mut output := []u8{len: 8 * lanes + 16, init: 0xcc}
			mut bytes := [u8(0)]
			mut bs := [airbitcode.IRMemoryBinding{ values: a },
				airbitcode.IRMemoryBinding{ data: output, writable: true },
				airbitcode.IRMemoryBinding{ values: a }]
			for slot in [0, 2] {
				for bad in [airbitcode.IRMemoryBinding{}, airbitcode.IRMemoryBinding{ data: bytes },
					airbitcode.IRMemoryBinding{ values: wrong },
					airbitcode.IRMemoryBinding{ values: a, writable: true },
					airbitcode.IRMemoryBinding{ values: a, offset: 1 },
					airbitcode.IRMemoryBinding{ values: a, base_alignment: 2 },
					airbitcode.IRMemoryBinding{ values: a, data: bytes }] {
					bs[slot] = bad
					if _ := plan.run(mut bs, steps) { panic('value binding guard') }
					unchanged(output)
					guards++
				}
				bs[slot] = airbitcode.IRMemoryBinding{ values: a }
			}
			bs[1] = airbitcode.IRMemoryBinding{ data: output, writable: true, values: a }
			if _ := plan.run(mut bs, steps) { panic('buffer value guard') }
			unchanged(output)
			guards++
			unsafe {
				a.free()
				wrong.free()
				output.free()
				bytes.free()
				bs.free()
			}
			plan.free()
		}
		native.close()
		p.free()
		bodies.free()
		pools.free()
		ir.free()
		stream.free()
	}
	controls(os.args[1], root + '/controls')!
	assert cases == 35904 && guards == 16830
	os.write_file(root + '/result.txt', 'AIR-MEMORY-VALUES: ${cases} exact native scalar/vector argument comparisons through ordinary and prepared APIs; ${guards} binding guard refusals PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}

fn controls(assembler string, root string) ! {
	mut text := strings.new_builder(16384)
	text.write_string('target datalayout = "e-p:64:64"\n')
	for i, t in ['i65', 'double', '<17 x i32>', '<vscale x 2 x i32>', '<2 x ptr>', '{i32, i32}',
		'[2 x i32]'] {
		text.write_string('define void @bad_${i}(${t} %value, ptr %dst) { store i8 17, ptr %dst\n ret void }\n')
	}
	text.write_string('define void @dynamic(i32 %index, ptr %dst) { %next = load i32, ptr %dst, align 1\n %p = getelementptr i8, ptr %dst, i32 %next\n store i8 17, ptr %p\n ret void }\n')
	text.write_string('define void @pointer(i64 %value, ptr %dst) { %p = inttoptr i64 %value to ptr\n %v = load i8, ptr %p\n store i8 %v, ptr %dst\n ret void }\n')
	text.write_string('define void @snapshot(i64 %value, ptr %dst) { store i64 0, ptr %dst, align 1\n %p = getelementptr i8, ptr %dst, i64 8\n store i64 %value, ptr %p, align 1\n ret void }\n')
	text.write_string('define void @empty(i32 %value) { ret void }\n')
	text.write_string('define void @poison(i8 %value, ptr %dst) { store i8 17, ptr %dst\n %v = shl nuw i8 %value, 1\n %p = getelementptr i8, ptr %dst, i64 1\n store i8 %v, ptr %p\n ret void }\n')
	text.write_string('define void @branch(i1 %cond, i32 %value, ptr %dst) { entry: br i1 %cond, label %left, label %right\n left: %a = add i32 %value, 3\n br label %join\n right: %b = xor i32 %value, -1\n br label %join\n join: %v = phi i32 [%a, %left], [%b, %right]\n store i32 %v, ptr %dst, align 1\n ret void }\n')
	text.write_string('define void @too_many(')
	for i in 0 .. 65 { text.write_string('${if i == 0 { '' } else { ', ' }}i32 %a${i}') }
	text.write_string(') { ret void }\n')
	data := assemble(assembler, root, text.str())!
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
	for name in ['bad_0', 'bad_1', 'bad_2', 'bad_3', 'bad_4', 'bad_5', 'bad_6', 'dynamic', 'pointer',
		'too_many'] {
		if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, name)) { panic(name) }
	}
	mut words := [u64(0x0123456789abcdef), 0]
	mut bytes := unsafe { (&u8(words.data)).vbytes(16) }
	values := words[..1]
	mut bs := [airbitcode.IRMemoryBinding{ values: values },
		airbitcode.IRMemoryBinding{ data: bytes, writable: true }]
	plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'snapshot'))!
	plan.run(mut bs, plan.steps())!
	assert words == [u64(0), 0x0123456789abcdef]
	plan.free()
	// `bytes` and `values` borrow the owned words array.
	unsafe {
		bs.free()
		words.free()
	}
	empty := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'empty'))!
	mut one := [u64(7)]
	mut empty_bindings := [airbitcode.IRMemoryBinding{ values: one }]
	assert empty.run(mut empty_bindings, 1)!.steps == 1
	empty.free()
	branch := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'branch'))!
	mut cond := [u64(0)]
	mut value := [u64(0)]
	mut output := []u8{len: 8, init: 0xcc}
	mut bindings := [airbitcode.IRMemoryBinding{ values: cond },
		airbitcode.IRMemoryBinding{ values: value },
		airbitcode.IRMemoryBinding{ data: output, writable: true }]
	for i in 0 .. 256 {
		cond[0] = u64(i) | ~u64(1)
		value[0] = u64(i) | ~u64(0xffffffff)
		branch.run(mut bindings, branch.steps())!
		expected := if i & 1 != 0 { u32(i + 3) } else { ~u32(i) }
		for j in 0 .. 4 {
			assert output[j] == u8(expected >> u32(j * 8))
		}
		for j in 4 .. output.len {
			assert output[j] == 0xcc
		}
	}
	branch.free()
	poison := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'poison'))!
	mut poison_bindings := [airbitcode.IRMemoryBinding{ values: value },
		airbitcode.IRMemoryBinding{ data: output, writable: true }]
	for i in 0 .. 256 {
		word := if i % 2 == 0 { u64(i / 2 + 128) } else { u64(i / 2) }
		value[0] = word | ~u64(255)
		for j in 0 .. output.len { output[j] = 0xcc }
		if i % 2 == 0 {
			if _ := poison.run(mut poison_bindings, poison.steps()) {
				panic('poison stored')
			} else {
				assert err.msg() == 'AIR memory execution: poison store'
			}
		} else {
			assert poison.run(mut poison_bindings, poison.steps())!.steps == poison.steps()
		}
		assert output[0] == 17 && output[1] == if i % 2 == 0 { u8(0xcc) } else { u8(word * 2) }
		for j in 2 .. output.len {
			assert output[j] == 0xcc
		}
	}
	poison.free()
	unsafe { poison_bindings.free() }
	unsafe {
		one.free()
		empty_bindings.free()
		cond.free()
		value.free()
		output.free()
		bindings.free()
	}
	os.write_file(root + '/result.txt', 'AIR-MEMORY-VALUES-CONTROLS: unsupported shapes, 65 arguments, loaded GEP/inttoptr refusal, aliased value snapshot, bufferless function, 256 masked branch/PHI cases and 256 alternating poison/recovery calls PASS\n')!
}
