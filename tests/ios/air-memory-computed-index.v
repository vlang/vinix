// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Run with LLVM_AS and a fresh external output directory.
// Reference overflow intrinsics are always defined. Flagged native targets
// execute only after the independent reference accepts their result/address.
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

fn untouched(data []u8) {
	for b in data {
		assert b == 0xcc
	}
}

fn control_cases(assembler string, root string) ! {
	mut text := strings.new_builder(65536)
	text.write_string('target datalayout = "e-p:64:64"\n')
	for name, instruction in {
		'load':     '%idx = load i64, ptr %out'
		'division': '%idx = udiv i64 %arg, 1'
		'select':   '%idx = select i1 true, i64 %arg, i64 0'
		'freeze':   '%idx = freeze i64 %arg'
		'remainder': '%idx = urem i64 %arg, 1'
		'undef':    '%idx = add i64 %arg, undef'
		'poison':   '%idx = add i64 %arg, poison'
	} {
		text.write_string('define void @bad_${name}(i64 %arg, ptr %out) { store i8 17, ptr %out\n ${instruction}\n %p = getelementptr i8, ptr %out, i64 %idx\n ret void }\n')
	}
	for depth in [31, 32] {
		text.write_string('define void @depth_${depth}(i64 %arg, ptr %out) { store i8 17, ptr %out\n')
		for i in 0 .. depth {
			text.write_string('%n${i} = add i64 ${if i == 0 { '%arg' } else { '%n${i - 1}' }}, 0\n')
			// Cache the previous maximal-depth expression before extending it.
			text.write_string('%p${i} = getelementptr i8, ptr %out, i64 %n${i}\n')
		}
		text.write_string('ret void }\n')
	}
	for count in [256, 257] {
		text.write_string('define void @nodes_${count}(i64 %arg, ptr %out) { store i8 17, ptr %out\n')
		for i in 0 .. 127 {
			text.write_string('%n${i} = add i64 %arg, ${i}\n %p${i} = getelementptr i8, ptr %out, i64 %n${i}\n')
		}
		text.write_string('%extra = add i64 %n0, %arg\n %p_extra = getelementptr i8, ptr %out, i64 %extra\n')
		if count == 257 {
			text.write_string('%over = add i64 %extra, %arg\n %p_over = getelementptr i8, ptr %out, i64 %over\n')
		}
		text.write_string('ret void }\n')
	}
	for name, body in {
		'cold':  'store i8 17, ptr %out\n br i1 true, label %exit, label %cold\ncold: %idx = mul i64 %arg, 2\n %p = getelementptr i8, ptr %out, i64 %idx\n store i8 42, ptr %p\n br label %exit\nexit: ret void'
		'alias': 'store i64 0, ptr %out, align 1\n %idx = add i64 %arg, 0\n %p = getelementptr i8, ptr %out, i64 %idx\n store i64 %arg, ptr %p, align 1\n ret void'
	} {
		text.write_string('define void @${name}(i64 %arg, ptr %out) { ${body} }\n')
	}
	for name, cast in {
		'trunc':     'trunc i16 %arg to i8'
		'trunc_nuw': 'trunc nuw i16 %arg to i8'
		'trunc_nsw': 'trunc nsw i16 %arg to i8'
		'zext':      'zext i8 %arg to i16'
		'zext_nneg': 'zext nneg i8 %arg to i16'
		'sext':      'sext i8 %arg to i16'
	} {
		source := if name.starts_with('trunc') { 'i16' } else { 'i8' }
		dest := if source == 'i16' { 'i8' } else { 'i16' }
		text.write_string('define void @${name}(${source} %arg, ptr %out) { store i8 17, ptr %out\n %idx = ${cast}\n %p = getelementptr i8, ptr %out, ${dest} %idx\n store i8 42, ptr %p\n ret void }\n')
	}
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
	for f, function in ir.functions {
		if !function.name.starts_with('bad_') && function.name !in ['depth_32', 'nodes_257'] {
			continue
		}
		mut bytes := []u8{len: 128, init: 0xcc}
		mut value := [u64(0)]
		mut bs := [airbitcode.IRMemoryBinding{ values: value },
			airbitcode.IRMemoryBinding{ data: bytes, writable: true }]
		if _ := p.prepare_memory_function(ir, stream, pools, bodies, f) { panic(function.name) }
		if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, 10000) {
			panic(function.name)
		}
		untouched(bytes)
		unsafe {
			bytes.free()
			value.free()
			bs.free()
		}
		guards++
	}
	assert guards == 9
	for name in ['depth_31', 'nodes_256', 'cold'] {
		plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, name))!
		mut bytes := []u8{len: 128, init: 0xcc}
		mut value := [u64(0)]
		mut bs := [airbitcode.IRMemoryBinding{ values: value },
			airbitcode.IRMemoryBinding{ data: bytes, writable: true }]
		plan.validate(bs, plan.steps())!
		untouched(bytes)
		plan.run(mut bs, plan.steps())!
		assert bytes[0] == 17
		if name == 'cold' {
			for i in 0 .. bytes.len { bytes[i] = 0xcc }
			value[0] = 64
			if _ := plan.validate(bs, plan.steps()) { panic('cold bounds') }
			if _ := plan.run(mut bs, plan.steps()) { panic('cold bounds') }
			untouched(bytes)
		}
		plan.free()
		unsafe {
			bytes.free()
			value.free()
			bs.free()
		}
	}
	for prepared in [true, false] {
		mut words := [u64(8), 0]
		bytes := unsafe { (&u8(words.data)).vbytes(16) }
		values := words[..1]
		mut bs := [airbitcode.IRMemoryBinding{ values: values },
			airbitcode.IRMemoryBinding{ data: bytes, writable: true }]
		plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'alias'))!
		plan.validate(bs, plan.steps())!
		assert words[0] == 8
		if prepared {
			plan.run(mut bs, plan.steps())!
		} else {
			p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'alias'), mut bs, plan.steps())!
		}
		assert words == [u64(0), 8]
		plan.free()
		unsafe {
			words.free()
			bs.free()
		}
	}
	mut casts := 0
	for name in ['trunc', 'trunc_nuw', 'trunc_nsw', 'zext', 'zext_nneg', 'sext'] {
		plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, name))!
		for raw in [u64(0), 1, 63, 64, 127, 128, 255, 256, 65535] {
			input := raw & if name.starts_with('trunc') { u64(65535) } else { u64(255) }
			idx := input & 255
			poison := (name == 'trunc_nuw' && input != idx) || (name == 'trunc_nsw' && input != if idx & 128 != 0 {
				idx | 65280
			} else {
				idx
			}) || (name == 'zext_nneg' && input >= 128)
			valid := !poison && idx < 64
			mut bytes := []u8{len: 64, init: 0xcc}
			mut value := [raw]
			mut bs := [airbitcode.IRMemoryBinding{ values: value },
				airbitcode.IRMemoryBinding{ data: bytes, writable: true }]
			if _ := plan.validate(bs, plan.steps()) {
				assert valid
			} else {
				assert !valid
				if poison {
					assert err.msg().contains('poison expression')
				}
			}
			untouched(bytes)
			if _ := plan.run(mut bs, plan.steps()) {
				assert valid
				assert bytes[int(idx)] == 42
			} else {
				assert !valid
				untouched(bytes)
			}
			unsafe {
				bytes.free()
				value.free()
				bs.free()
			}
			casts++
		}
		plan.free()
	}
	os.write_file(root + '/result.txt', 'AIR-COMPUTED-INDEX-CONTROLS: ${guards} unsupported/depth/node refusals; exact 32-level/256-node boundaries including cached-depth extension, cold prewrite bounds, aliased snapshots and ${casts} cast/poison cases PASS\n')!
}

fn main() {
	assert os.args.len == 3
	root := os.abs_path(os.args[2])
	assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!
	mut rows := os.create(root + '/comparisons.txt')!
	defer { rows.close() }
	mut exact := 0
	mut rejected := 0
	mut poison := 0
	mut vectors := 0
	for width in 1 .. 65 {
		mask := if width == 64 { ~u64(0) } else { (u64(1) << u32(width)) - 1 }
		sign := u64(1) << u32(width - 1)
		mut text := strings.new_builder(65536)
		text.write_string('target datalayout = "e-p:64:64-i64:64"\n')
		for op in ['add', 'sub', 'mul'] {
			for prefix in ['u', 's'] {
				text.write_string('declare {i${width}, i1} @llvm.${prefix}${op}.with.overflow.i${width}(i${width}, i${width})\n')
			}
		}
		for op in ['add', 'sub', 'mul'] {
			for flags, spelling in ['', 'nuw ', 'nsw ', 'nuw nsw '] {
				name := '${op}_${flags}'
				text.write_string('define void @${name}(i${width} %a, i${width} %b, ptr %src, ptr %out) { store i8 17, ptr %out\n %idx = ${op} ${spelling}i${width} %a, %b\n %s = getelementptr i8, ptr %src, i${width} %idx\n %v = load i8, ptr %s\n %d = getelementptr i8, ptr %out, i${width} %idx\n store i8 %v, ptr %d\n ret void }\n')
				text.write_string('define void @native_${name}(ptr %ip, ptr %src, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n call void @${name}(i${width} %a, i${width} %b, ptr %src, ptr %out)\n ret void }\n')
				text.write_string('define void @ref_${name}(ptr %ip, ptr %unused, ptr %out) { %bp = getelementptr i8, ptr %ip, i64 8\n %a = load i${width}, ptr %ip, align 1\n %b = load i${width}, ptr %bp, align 1\n %u = call {i${width}, i1} @llvm.u${op}.with.overflow.i${width}(i${width} %a, i${width} %b)\n %s = call {i${width}, i1} @llvm.s${op}.with.overflow.i${width}(i${width} %a, i${width} %b)\n %idx = extractvalue {i${width}, i1} %u, 0\n %uo = extractvalue {i${width}, i1} %u, 1\n %so = extractvalue {i${width}, i1} %s, 1\n %p = or i1 ${if flags & 1 != 0 {
					'%uo'
				} else {
					'false'
				}}, ${if flags & 2 != 0 { '%so' } else { 'false' }}\n %nonnegative = icmp sge i${width} %idx, 0\n %bounded = icmp ule i${width} %idx, ${if mask < 63 {
					mask
				} else {
					u64(63)
				}}\n %valid = and i1 %nonnegative, %bounded\n %tag0 = select i1 %valid, i8 1, i8 0\n %tag = select i1 %p, i8 2, i8 %tag0\n store i8 %tag, ptr %out\n ret void }\n')
			}
		}
		text.write_string('define void @vector(<3 x i${width}> %arg, ptr %src, ptr %out) { store i8 17, ptr %out\n %x = extractelement <3 x i${width}> %arg, i32 0\n %y = extractelement <3 x i${width}> %arg, i32 1\n %z = extractelement <3 x i${width}> %arg, i32 2\n %yy = mul i${width} %y, 2\n %zz = mul i${width} %z, 4\n %a = add i${width} %x, %yy\n %idx = add i${width} %a, %zz\n %s = getelementptr i8, ptr %src, i${width} %idx\n %v = load i8, ptr %s\n %d = getelementptr i8, ptr %out, i${width} %idx\n store i8 %v, ptr %d\n ret void }\n define void @native_vector(ptr %ip, ptr %src, ptr %out) {\n')
		for lane in 0 .. 3 {
			text.write_string('%p${lane} = getelementptr i8, ptr %ip, i64 ${lane * 8}\n %v${lane} = load i${width}, ptr %p${lane}, align 1\n %a${lane} = insertelement <3 x i${width}> ${if lane == 0 {
				'zeroinitializer'
			} else {
				'%a${lane - 1}'
			}}, i${width} %v${lane}, i32 ${lane}\n')
		}
		text.write_string('call void @vector(<3 x i${width}> %a2, ptr %src, ptr %out)\n ret void }\n')
		out := root + '/i${width}'
		data := assemble(os.args[1], out, text.str())!
		verify(data)!
		stream := airbitcode.parse(data)!
		ir := stream.ir_module(data)!
		pools := ir.constant_pools(stream)!
		bodies := ir.function_bodies(stream, pools)!
		p := ir.typed_operands(stream, pools, bodies)!
		native := native_module(data, out)!
		candidates := [u64(0), 1, 2, 7, 31, 63, mask, sign, sign - 1, sign + 1]!
		for op in ['add', 'sub', 'mul'] {
			for flag in 0 .. 4 {
				name := '${op}_${flag}'
				f := fi(ir, name)
				plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
				address := C.LLVMGetFunctionAddress(native.engine, ('native_' + name).str)
				reference := C.LLVMGetFunctionAddress(native.engine, ('ref_' + name).str)
				assert address != 0 && reference != 0
				for a in candidates {
					for b in candidates {
						mut input_words := [a & mask, b & mask]
						mut tag := [u8(0)]
						unsafe { NativeCast(voidptr(reference))(input_words.data, input_words.data, tag.data) }
						valid := tag[0] == 1
						mut input := []u8{len: 64, init: u8(index * 37 + width)}
						mut actual := []u8{len: 64, init: 0xcc}
						mut expected := actual.clone()
						mut av := [a | ~mask]
						mut bv := [b | ~mask]
						mut bs := [airbitcode.IRMemoryBinding{ values: av },
							airbitcode.IRMemoryBinding{ values: bv },
							airbitcode.IRMemoryBinding{ data: input },
							airbitcode.IRMemoryBinding{ data: actual, writable: true }]
						if _ := plan.validate(bs, plan.steps()) {
							assert valid
						} else {
							assert !valid
							if tag[0] == 2 {
								assert err.msg().contains('poison expression')
							}
						}
						untouched(actual)
						if valid {
							unsafe { NativeCast(voidptr(address))(input_words.data, input.data, expected.data) }
						}
						for prepared in [true, false] {
							for j in 0 .. actual.len { actual[j] = 0xcc }
							if prepared {
								if _ := plan.run(mut bs, plan.steps()) {
									assert valid
								} else {
									assert !valid
								}
							} else {
								if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, plan.steps()) {
									assert valid
								} else {
									assert !valid
								}
							}
							if valid {
								assert actual == expected, '${width} ${op} ${flag} ${a} ${b}'
							} else {
								untouched(actual)
							}
						}
						if valid {
							exact++
						} else {
							rejected++
							if tag[0] == 2 { poison++ }
						}
						rows.writeln('${width} ${name} ${a & mask} ${b & mask} ${tag[0]} PASS')!
						unsafe {
							input_words.free()
							tag.free()
							input.free()
							actual.free()
							expected.free()
							av.free()
							bv.free()
							bs.free()
						}
					}
				}
				plan.free()
			}
		}
		plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'vector'))!
		address := C.LLVMGetFunctionAddress(native.engine, c'native_vector')
		assert address != 0
		for sample in 0 .. 64 {
			mut words := [u64(sample & 3), u64(sample >> 2 & 3), u64(sample >> 4 & 3)]
			canonical := [words[0] & mask, words[1] & mask, words[2] & mask]
			index := (words[0] + 2 * words[1] + 4 * words[2]) & mask
			for i in 0 .. 3 { words[i] |= ~mask }
			valid := index & sign == 0 && index < 64
			mut input := []u8{len: 64, init: u8(index * 37 + sample)}
			mut actual := []u8{len: 64, init: 0xcc}
			mut expected := actual.clone()
			mut bs := [airbitcode.IRMemoryBinding{ values: words },
				airbitcode.IRMemoryBinding{ data: input },
				airbitcode.IRMemoryBinding{ data: actual, writable: true }]
			if _ := plan.validate(bs, plan.steps()) {
				assert valid
			} else {
				assert !valid
			}
			if valid {
				unsafe { NativeCast(voidptr(address))(canonical.data, input.data, expected.data) }
				plan.run(mut bs, plan.steps())!
				assert actual == expected
				for i in 0 .. actual.len { actual[i] = 0xcc }
				p.run_memory_function(ir, stream, pools, bodies, fi(ir, 'vector'), mut bs, plan.steps())!
				assert actual == expected
			} else {
				if _ := plan.run(mut bs, plan.steps()) { panic('vector bounds') }
				untouched(actual)
			}
			unsafe {
				words.free()
				canonical.free()
				input.free()
				actual.free()
				expected.free()
				bs.free()
			}
			vectors++
		}
		plan.free()
		native.close()
		p.free()
		bodies.free()
		pools.free()
		ir.free()
		stream.free()
	}
	control_cases(os.args[1], root + '/controls')!
	assert exact + rejected == 76800 && vectors == 4096
	os.write_file(root + '/result.txt', 'AIR-COMPUTED-INDEX: ${exact} native exact cases, ${rejected} prewrite refusals (${poison} LLVM overflow cases), ${vectors} vector-coordinate cases, i1..i64 and ordinary/prepared/validation APIs PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}
