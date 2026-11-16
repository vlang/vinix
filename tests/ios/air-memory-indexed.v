// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Native comparisons execute only defined GEPs, loads and stores.
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
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMGetHostCPUName() &char
fn C.LLVMGetHostCPUFeatures() &char
fn C.LLVMGetFirstFunction(voidptr) voidptr
fn C.LLVMGetNextFunction(voidptr) voidptr
fn C.LLVMAddTargetDependentFunctionAttr(voidptr, &char, &char)
fn C.LLVMLinkInMCJIT()
fn C.LLVMCreateMCJITCompilerForModule(&voidptr, voidptr, voidptr, usize, &&char) int
fn C.LLVMDisposeExecutionEngine(voidptr)
fn C.LLVMGetFunctionAddress(voidptr, &char) u64
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
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'indexed-memory')
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
	os.write_file(out + '/native-layout.txt', unsafe { cstring_to_vstring(C.LLVMGetDataLayoutStr(module_ptr)) })!
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

fn indexed_controls(assembler string, root string) ! {
	mut text := strings.new_builder(16384)
	text.write_string('target datalayout = "e-p:64:64"\n')
	text.write_string('declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)\ndeclare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1 immarg)\ndeclare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)\n')
	for name, tail in {
		'chain':         '%q = getelementptr i8, ptr %p, i64 0'
		'cast':          '%q = bitcast ptr %p to ptr'
		'freeze':        '%q = freeze ptr %p'
		'address_space': '%q = addrspacecast ptr %p to ptr addrspace(1)'
		'select':        '%q = select i1 true, ptr %p, ptr %p'
		'compare':       '%q = icmp eq ptr %p, %out'
		'phi':           'br i1 true, label %left, label %right\nleft: br label %end\nright: br label %end\nend: %q = phi ptr [ %p, %left ], [ %p, %right ]'
		'copy_dest':     'call void @llvm.memcpy.p0.p0.i64(ptr %p, ptr %out, i64 0, i1 false)'
		'copy_source':   'call void @llvm.memcpy.p0.p0.i64(ptr %out, ptr %p, i64 0, i1 false)'
		'move_dest':     'call void @llvm.memmove.p0.p0.i64(ptr %p, ptr %out, i64 0, i1 false)'
		'move_source':   'call void @llvm.memmove.p0.p0.i64(ptr %out, ptr %p, i64 0, i1 false)'
		'fill':          'call void @llvm.memset.p0.i64(ptr %p, i8 0, i64 0, i1 false)'
	} {
		text.write_string('define void @guard_${name}(i64 %idx, ptr %out) { store i8 17, ptr %out\n %p = getelementptr i8, ptr %out, i64 %idx\n ${tail}\n ret void }\n')
	}
	text.write_string('define void @guard_computed(i64 %idx, ptr %out) { store i8 17, ptr %out\n %n = add i64 %idx, 1\n %p = getelementptr i8, ptr %out, i64 %n\n ret void }\ndefine void @guard_multi(i64 %idx, ptr %out) { store i8 17, ptr %out\n %p = getelementptr [4 x i8], ptr %out, i64 %idx, i64 0\n ret void }\n')
	text.write_string('define void @store(i64 %idx, ptr %out) { store i8 17, ptr %out\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n ret void }\ndefine void @aligned(i64 %idx, ptr %out) { store i8 17, ptr %out\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p, align 4\n ret void }\ndefine void @unused(i64 %idx, ptr %out) { %p = getelementptr inbounds i8, ptr %out, i64 %idx\n ret void }\n')
	text.write_string('define void @cold(i64 %idx, ptr %out) { store i8 17, ptr %out\n br i1 true, label %exit, label %cold\ncold: %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n br label %exit\nexit: ret void }\n')
	text.write_string('define void @snapshot(i64 %idx, ptr %out) { store i64 0, ptr %out, align 1\n %p = getelementptr i8, ptr %out, i64 %idx\n store i64 %idx, ptr %p, align 1\n ret void }\n')
	text.write_string('define void @spacecopy(i64 %idx, ptr addrspace(2) %src, ptr addrspace(1) %out) { %s = getelementptr i8, ptr addrspace(2) %src, i64 %idx\n %d = getelementptr i8, ptr addrspace(1) %out, i64 %idx\n %v = load i8, ptr addrspace(2) %s\n store i8 %v, ptr addrspace(1) %d\n ret void }\ndefine void @guard_readonly(i64 %idx, ptr addrspace(2) %out) { %p = getelementptr i8, ptr addrspace(2) %out, i64 %idx\n store i8 42, ptr addrspace(2) %p\n ret void }\n')
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
	mut guards := 0
	for f, func in ir.functions {
		if !func.name.starts_with('guard_') { continue }
		mut output := []u8{len: 64, init: 0xcc}
		mut value := [u64(0)]
		mut bs := [airbitcode.IRMemoryBinding{ values: value },
			airbitcode.IRMemoryBinding{ data: output, writable: true }]
		if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) {
			panic(func.name)
		} else {
			if func.name !in ['guard_computed', 'guard_multi', 'guard_readonly'] {
				assert err.msg().contains('indexed pointer flow'), '${func.name}: ${err}'
			}
		}
		if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, 100) {
			panic(func.name)
		}
		unchanged(output)
		unsafe {
			output.free()
			value.free()
			bs.free()
		}
		guards++
	}
	assert guards == 15
	mut checks := 0
	for name in ['store', 'aligned', 'unused', 'cold'] {
		f := fi(ir, name)
		plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
		for raw in [u64(0), 1, 2, 3, 4, 60, 63, 64, 65, u64(64 * 1024 * 1024), u64(0x7fffffffffffffff),
			~u64(0)] {
			valid := if name == 'unused' {
				raw <= 64
			} else {
				raw < 64 && (name != 'aligned' || raw % 4 == 0)
			}
			mut output := []u8{len: 64, init: 0xcc}
			mut value := [raw]
			mut bs := [airbitcode.IRMemoryBinding{ values: value },
				airbitcode.IRMemoryBinding{ data: output, writable: true, base_alignment: 4 }]
			if _ := plan.validate(bs, 100) {
				assert valid
			} else {
				assert !valid
			}
			unchanged(output)
			for prepared in [true, false] {
				for j in 0 .. output.len { output[j] = 0xcc }
				if prepared {
					if _ := plan.run(mut bs, 100) {
						assert valid
					} else {
						assert !valid
					}
				} else {
					if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, 100) {
						assert valid
					} else {
						assert !valid
					}
				}
				for j, b in output {
					assert b == if !valid || name == 'unused' {
						u8(0xcc)
					} else if name != 'cold' && u64(j) == raw {
						u8(42)
					} else if j == 0 {
						u8(17)
					} else {
						u8(0xcc)
					}
				}
			}
			unsafe {
				output.free()
				value.free()
				bs.free()
			}
			checks++
		}
		plan.free()
	}
	// An unused pointer may reach the maximum extent exactly, never exceed it.
	large := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'unused'))!
	mut buffer := []u8{len: 64 * 1024 * 1024, init: 0xcc}
	mut index := [u64(buffer.len)]
	mut bs := [airbitcode.IRMemoryBinding{ values: index }, airbitcode.IRMemoryBinding{ data: buffer }]
	large.validate(bs, large.steps())!
	large.run(mut bs, large.steps())!
	index[0]++
	if _ := large.validate(bs, large.steps()) { panic('extent') }
	if _ := large.run(mut bs, large.steps()) { panic('extent') }
	unchanged(buffer)
	large.free()
	unsafe {
		buffer.free()
		index.free()
		bs.free()
	}
	// A preceding store must not change either the captured word or its address.
	snapshot := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'snapshot'))!
	for prepared in [true, false] {
		mut words := [u64(8), 0]
		bytes := unsafe { (&u8(words.data)).vbytes(16) }
		values := words[..1]
		mut bindings := [airbitcode.IRMemoryBinding{ values: values },
			airbitcode.IRMemoryBinding{ data: bytes, writable: true }]
		snapshot.validate(bindings, 100)!
		assert words[0] == 8
		if prepared {
			snapshot.run(mut bindings, 100)!
		} else {
			p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'snapshot'), mut bindings, 100)!
		}
		assert words == [u64(0), 8]
		unsafe {
			words.free()
			bindings.free()
		}
	}
	snapshot.free()
	copy := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'spacecopy'))!
	for n in 0 .. 64 {
		mut value := [u64(n)]
		mut input := []u8{len: 64, init: u8(index * 7)}
		mut output := []u8{len: 64, init: 0xcc}
		mut bindings := [airbitcode.IRMemoryBinding{ values: value },
			airbitcode.IRMemoryBinding{ data: input },
			airbitcode.IRMemoryBinding{ data: output, writable: true }]
		copy.validate(bindings, 100)!
		copy.run(mut bindings, 100)!
		for j, b in output {
			assert b == if j == n { input[n] } else { u8(0xcc) }
		}
		bindings[1] = airbitcode.IRMemoryBinding{ data: input, writable: true }
		if _ := copy.validate(bindings, 100) { panic('writable constant') }
		unsafe {
			value.free()
			input.free()
			output.free()
			bindings.free()
		}
	}
	copy.free()
	default := airbitcode.IRPreparedMemoryFunction{}
	if _ := default.validate([]airbitcode.IRMemoryBinding{}, 1) {
		panic('uninitialized validation')
	}
	os.write_file(root + '/result.txt', 'AIR-MEMORY-INDEXED-CONTROLS: ${guards} unsupported pointer-flow/computed/multi-index/readonly refusals; ${checks} ordinary/prepared/validate-only bounds, alignment, one-past and cold-block cases; exact 64 MiB extent, aliased index snapshot, 64 address-space copies and default object PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}

fn main() {
	assert os.args.len == 3
	root := os.abs_path(os.args[2])
	assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!
	types := ['i8', 'i16', 'i24', 'i32', 'i64', 'half', 'float', '<3 x i24>', '<4 x i32>', '{i8, i64}',
		'[3 x i32]', '[0 x i8]', 'ptr']
	strides := [1, 2, 4, 4, 8, 2, 4, 16, 16, 16, 12, 0, 8]!
	sizes := [1, 2, 3, 4, 8, 2, 4, 9, 16, 1, 1, 1, 1]!
	mut exact := 0
	mut rejected := 0
	mut rows := os.create(root + '/comparisons.txt')!
	defer { rows.close() }
	for width in 1 .. 65 {
		mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }
		sign := u64(1) << u32(width - 1)
		candidates := [u64(0), 1, 2, 3, 7, 15, 16, 17, 30, 31, 32, 63, u64(64 * 1024 * 1024),
			u64(0x7fffffffffffffff), ~u64(0), sign]!
		mut text := strings.new_builder(131072)
		// Match the native target's i64 structure alignment; LLVM's generic
		// default is four bytes, while this host target uses eight bytes.
		text.write_string('target datalayout = "e-p:64:64-i24:32-i64:64"\n')
		for shape, t in types {
			for flag, flags in ['', 'inbounds ', 'nuw ', 'nusw '] {
				load := if shape < 9 { t } else { 'i8' }
				name := 'f_${shape}_${flag}'
				text.write_string('define void @${name}(i${width} %idx, ptr %src, ptr %out) { store i8 17, ptr %out\n %sb = getelementptr i8, ptr %src, i64 2\n %s = getelementptr ${flags}${t}, ptr %sb, i${width} %idx\n %v = load ${load}, ptr %s, align 1\n %db = getelementptr i8, ptr %out, i64 8\n %d = getelementptr ${flags}${t}, ptr %db, i${width} %idx\n store ${load} %v, ptr %d, align 1\n ret void }\n')
				text.write_string('define void @native_${name}(ptr %ip, ptr %src, ptr %out) { %idx = load i${width}, ptr %ip, align 1\n call void @${name}(i${width} %idx, ptr %src, ptr %out)\n ret void }\n')
			}
		}
		out := root + '/i${width}'
		data := assemble(os.args[1], out, text.str())!
		verify(data)!
		stream := airbitcode.parse(data)!
		ir := stream.ir_module(data)!
		pools := ir.constant_pools(stream)!
		bodies := ir.function_bodies(stream, pools)!
		p := ir.typed_operands(stream, pools, bodies)!
		native := native_module(data, out)!
		for shape, _ in types {
			for flag in 0 .. 4 {
				f := fi(ir, 'f_${shape}_${flag}')
				plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
				steps := plan.steps()
				stride := strides[shape]
				size := sizes[shape]
				assert plan.argument(1)!.minimum_size == u64(2 + size) && plan.argument(2)!.minimum_size == u64(8 + size)
				addr := C.LLVMGetFunctionAddress(native.engine, ('native_f_${shape}_${flag}').str)
				assert addr != 0
				for sample, raw in candidates {
					word := raw & mask
					valid := word & sign == 0 && (stride == 0 || word <= u64((511 - 2 - size) / stride) && word <= u64((517 - 8 - size) / stride))
					mut input := []u8{len: 512, init: u8(index * 37 + sample)}
					mut output := []u8{len: 520, init: 0xcc}
					mut reference := output.clone()
					mut index_value := [raw | ~mask]
					mut canonical := []u8{len: 8}
					for j in 0 .. 8 { canonical[j] = u8(word >> u32(j * 8)) }
					mut bs := [airbitcode.IRMemoryBinding{ values: index_value },
						airbitcode.IRMemoryBinding{ data: input, offset: 1 },
						airbitcode.IRMemoryBinding{ data: output, offset: 3, writable: true }]
					mut validation_error := ''
					if _ := plan.validate(bs, steps) {} else { validation_error = err.msg() }
					assert (validation_error.len == 0) == valid
					unchanged(output)
					if valid {
						unsafe { NativeCast(voidptr(addr))(canonical.data, &input[1], &reference[3]) }
					}
					for prepared in [true, false] {
						for j in 0 .. output.len { output[j] = 0xcc }
						if valid {
							r := if prepared {
								plan.run(mut bs, steps)!
							} else {
								p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps)!
							}
							assert r.steps == steps, '${width} ${shape} ${flag} ${word}: steps ${r.steps}/${steps}'
							for j, b in output {
								assert b == reference[j], '${width} ${shape} ${flag} ${word} prepared=${prepared}: byte ${j}: ${b}/${reference[j]}'
							}
							dest := 3 + 8 + int(word) * stride
							src := 1 + 2 + int(word) * stride
							for j, b in output {
								assert b == if j == 3 {
									u8(17)
								} else if j >= dest && j < dest + size {
									input[src + j - dest]
								} else {
									u8(0xcc)
								}
							}
						} else {
							if prepared {
								if _ := plan.run(mut bs, steps) {
									panic('invalid index')
								} else {
									assert err.msg() == validation_error
								}
							} else {
								if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, steps) {
									panic('ordinary invalid index')
								} else {
									assert err.msg() == validation_error
								}
							}
							unchanged(output)
						}
					}
					if valid { exact++ } else { rejected++ }
					rows.writeln('${width} ${shape} ${flag} ${word} ${valid} ${validation_error}')!
					unsafe {
						input.free()
						output.free()
						reference.free()
						index_value.free()
						canonical.free()
						bs.free()
					}
				}
				plan.free()
			}
		}
		native.close()
		p.free()
		bodies.free()
		pools.free()
		ir.free()
		stream.free()
	}
	assert exact + rejected == 53248
	indexed_controls(os.args[1], root + '/controls')!
	os.write_file(root + '/result.txt', 'AIR-MEMORY-INDEXED: ${exact} exact native cases, ${rejected} indexed-input refusals through ordinary/prepared execution and validate-only API, all i1..i64 indices, 13 layouts and four flag forms PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}
