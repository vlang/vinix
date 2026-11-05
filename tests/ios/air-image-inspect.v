// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os

#flag -I/opt/homebrew/opt/llvm/include
#flag -L/opt/homebrew/opt/llvm/lib
#flag -lLLVM
#flag -Wl,-rpath,/opt/homebrew/opt/llvm/lib
#include <llvm-c/Core.h>
#include <llvm-c/Target.h>
#include <llvm-c/Transforms/PassBuilder.h>

fn C.LLVMContextCreate() voidptr
fn C.LLVMContextDispose(voidptr)
fn C.LLVMIntTypeInContext(voidptr, u32) voidptr
fn C.LLVMHalfTypeInContext(voidptr) voidptr
fn C.LLVMBFloatTypeInContext(voidptr) voidptr
fn C.LLVMFloatTypeInContext(voidptr) voidptr
fn C.LLVMDoubleTypeInContext(voidptr) voidptr
fn C.LLVMX86FP80TypeInContext(voidptr) voidptr
fn C.LLVMFP128TypeInContext(voidptr) voidptr
fn C.LLVMPPCFP128TypeInContext(voidptr) voidptr
fn C.LLVMPointerTypeInContext(voidptr, u32) voidptr
fn C.LLVMArrayType2(voidptr, u64) voidptr
fn C.LLVMVectorType(voidptr, u32) voidptr
fn C.LLVMStructTypeInContext(voidptr, voidptr, u32, int) voidptr
fn C.LLVMConstNull(voidptr) voidptr
fn C.LLVMConstInt(voidptr, u64, int) voidptr
fn C.LLVMConstIntOfArbitraryPrecision(voidptr, u32, voidptr) voidptr
fn C.LLVMConstBitCast(voidptr, voidptr) voidptr
fn C.LLVMConstArray2(voidptr, voidptr, u64) voidptr
fn C.LLVMConstVector(voidptr, u32) voidptr
fn C.LLVMConstStructInContext(voidptr, voidptr, u32, int) voidptr
fn C.LLVMFunctionType(voidptr, voidptr, u32, int) voidptr
fn C.LLVMModuleCreateWithNameInContext(&char, voidptr) voidptr
fn C.LLVMDisposeModule(voidptr)
fn C.LLVMSetDataLayout(voidptr, &char)
fn C.LLVMAddGlobal(voidptr, voidptr, &char) voidptr
fn C.LLVMSetInitializer(voidptr, voidptr)
fn C.LLVMSetGlobalConstant(voidptr, int)
fn C.LLVMAddFunction(voidptr, &char, voidptr) voidptr
fn C.LLVMAppendBasicBlockInContext(voidptr, voidptr, &char) voidptr
fn C.LLVMCreateBuilderInContext(voidptr) voidptr
fn C.LLVMDisposeBuilder(voidptr)
fn C.LLVMPositionBuilderAtEnd(voidptr, voidptr)
fn C.LLVMBuildGEP2(voidptr, voidptr, voidptr, voidptr, u32, &char) voidptr
fn C.LLVMBuildLoad2(voidptr, voidptr, voidptr, &char) voidptr
fn C.LLVMBuildRet(voidptr, voidptr) voidptr
fn C.LLVMGetBasicBlockTerminator(voidptr) voidptr
fn C.LLVMGetOperand(voidptr, u32) voidptr
fn C.LLVMIsAConstantInt(voidptr) voidptr
fn C.LLVMConstIntGetZExtValue(voidptr) u64
fn C.LLVMCreatePassBuilderOptions() voidptr
fn C.LLVMDisposePassBuilderOptions(voidptr)
fn C.LLVMPassBuilderOptionsSetVerifyEach(voidptr, int)
fn C.LLVMRunPasses(voidptr, &char, voidptr, voidptr) voidptr
fn C.LLVMGetErrorMessage(voidptr) &char
fn C.LLVMDisposeErrorMessage(&char)
fn C.LLVMPrintModuleToString(voidptr) &char
fn C.LLVMDisposeMessage(&char)
fn C.LLVMCreateTargetData(&char) voidptr
fn C.LLVMDisposeTargetData(voidptr)
fn C.LLVMStoreSizeOfType(voidptr, voidptr) u64
fn C.LLVMABISizeOfType(voidptr, voidptr) u64
fn C.LLVMOffsetOfElement(voidptr, voidptr, u32) u64

struct NativeImage {
	context voidptr
	ir airbitcode.IRModule
	stream airbitcode.Stream
	pools airbitcode.IRConstantPools
mut:
	types []voidptr
	values []voidptr
}
fn (mut n NativeImage) typ(index int, depth int) !voidptr {
	if depth > 64 { return error('oracle type depth') }
	if n.types[index] != unsafe { nil } { return n.types[index] }
	t := n.ir.types[index]
	mut result := unsafe { nil }
	match t.kind {
		.integer_t { result = C.LLVMIntTypeInContext(n.context, t.bits) }
		.half_t { result = C.LLVMHalfTypeInContext(n.context) }
		.bfloat_t { result = C.LLVMBFloatTypeInContext(n.context) }
		.float_t { result = C.LLVMFloatTypeInContext(n.context) }
		.double_t { result = C.LLVMDoubleTypeInContext(n.context) }
		.x86_fp80_t { result = C.LLVMX86FP80TypeInContext(n.context) }
		.fp128_t { result = C.LLVMFP128TypeInContext(n.context) }
		.ppc_fp128_t { result = C.LLVMPPCFP128TypeInContext(n.context) }
		.pointer_t { result = C.LLVMPointerTypeInContext(n.context, t.address_space) }
		.array_t, .vector_t {
			child := n.typ(n.ir.references[t.refs_start], depth + 1)!
			result = if t.kind == .array_t { C.LLVMArrayType2(child, t.count) } else { C.LLVMVectorType(child, u32(t.count)) }
		}
		.struct_t {
			mut fields := []voidptr{len: t.refs_count, init: unsafe { nil }}; defer { unsafe { fields.free() } }
			for i in 0 .. t.refs_count { fields[i] = n.typ(n.ir.references[t.refs_start + i], depth + 1)! }
			result = C.LLVMStructTypeInContext(n.context, fields.data, u32(fields.len), int(t.packed))
		}
		else { return error('unsupported oracle type') }
	}
	n.types[index] = result; return result
}
fn (mut n NativeImage) payload(typ int, offset u64, target voidptr, depth int) !bool {
	if depth > 64 { return error('oracle payload depth') }
	if offset >= C.LLVMStoreSizeOfType(target, n.typ(typ, 0)!) { return false }
	t := n.ir.types[typ]
	if t.kind in [.array_t, .vector_t] {
		child := n.ir.references[t.refs_start]; child_type := n.typ(child, 0)!
		stride := if t.kind == .vector_t { C.LLVMStoreSizeOfType(target, child_type) } else { C.LLVMABISizeOfType(target, child_type) }
		return stride != 0 && n.payload(child, offset % stride, target, depth + 1)!
	}
	if t.kind == .struct_t {
		for i in 0 .. t.refs_count {
			child := n.ir.references[t.refs_start + i]; start := C.LLVMOffsetOfElement(target, n.typ(typ, 0)!, u32(i))
			if offset >= start && offset - start < C.LLVMABISizeOfType(target, n.typ(child, 0)!) { return n.payload(child, offset - start, target, depth + 1)! }
		}
		return false
	}
	return true
}
fn (mut n NativeImage) numeric(typ int, bits u32, start int, count int) !voidptr {
	integer := C.LLVMConstIntOfArbitraryPrecision(C.LLVMIntTypeInContext(n.context, bits), u32(count), unsafe { &n.pools.words[start] })
	return if n.ir.types[typ].kind == .integer_t { integer } else { C.LLVMConstBitCast(integer, n.typ(typ, 0)!) }
}
fn (mut n NativeImage) constant(index int, depth int) !voidptr {
	if depth > 64 { return error('oracle constant depth') }
	if n.values[index] != unsafe { nil } { return n.values[index] }
	c := n.pools.constants[index]; t := n.ir.types[c.type_index]
	type_ptr := n.typ(c.type_index, 0)!
	mut value := unsafe { nil }
	if c.kind == .zero { value = C.LLVMConstNull(type_ptr) }
	else if c.kind in [.integer, .floating] && !c.splat { value = n.numeric(c.type_index, c.bits, c.words_start, c.words_count)! }
	else {
		count := if t.kind == .struct_t { t.refs_count } else { int(t.count) }
		mut children := []voidptr{len: count, init: unsafe { nil }}; defer { unsafe { children.free() } }
		for i in 0 .. count {
			child := n.ir.references[t.refs_start + if t.kind == .struct_t { i } else { 0 }]
			if c.kind == .aggregate {
				r := n.stream.records[c.record]
				v := n.pools.lookup(c.scope, n.stream.values[r.values_start + i])!
				if v.kind != .constant { return error('oracle requires resolved constant') }
				children[i] = n.constant(v.constant_index, depth + 1)!
			} else if c.splat { children[i] = n.numeric(child, c.bits, c.words_start, c.words_count)! }
			else {
				child_type := n.ir.types[child]
				bits := if child_type.kind == .integer_t { child_type.bits } else if child_type.kind in [.half_t, .bfloat_t] { u32(16) } else if child_type.kind == .float_t { u32(32) } else { u32(64) }
				children[i] = n.numeric(child, bits, c.words_start + i, 1)!
			}
		}
		value = match t.kind {
			.array_t { C.LLVMConstArray2(n.typ(n.ir.references[t.refs_start], 0)!, children.data, u64(count)) }
			.vector_t { C.LLVMConstVector(children.data, u32(count)) }
			.struct_t { C.LLVMConstStructInContext(n.context, children.data, u32(count), int(t.packed)) }
			else { return error('oracle constant kind') }
		}
	}
	n.values[index] = value; return value
}
struct ByteProbe { block voidptr expected u8 constant_index int offset int }
struct ImageCounts {
mut:
	complete int
	unavailable int
	bytes u64
	checked int
	unresolved int
	padding int
	reasons [7]int
}
fn positions(size int) []int {
	if size > 16 { return [0, 1, 2, 3, size / 2, size - 2, size - 1] }
	return []int{len: size, init: index}
}
fn check(path string, out string, corrupt string) !ImageCounts {
	if os.file_size(path) > airbitcode.max_input_size { return error('input limit') }
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	layouts := ir.type_layouts()!; defer { layouts.free() }
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	module_ptr := C.LLVMModuleCreateWithNameInContext(c'literal-image-oracle', context); defer { C.LLVMDisposeModule(module_ptr) }
	C.LLVMSetDataLayout(module_ptr, ir.data_layout.str)
	target := C.LLVMCreateTargetData(ir.data_layout.str); defer { C.LLVMDisposeTargetData(target) }
	builder := C.LLVMCreateBuilderInContext(context); defer { C.LLVMDisposeBuilder(builder) }
	mut n := NativeImage{context: context, ir: ir, stream: stream, pools: pools, types: []voidptr{len: ir.types.len, init: unsafe { nil }}, values: []voidptr{len: pools.constants.len, init: unsafe { nil }}}
	mut probes := []ByteProbe{}; probes.flags |= .noslices
	defer { unsafe { n.types.free(); n.values.free(); probes.free() } }
	byte_type := C.LLVMIntTypeInContext(context, 8); index_type := C.LLVMIntTypeInContext(context, 64)
	mut counts := ImageCounts{}
	for i, c in pools.constants {
		image := pools.constant_image(ir, stream, layouts, i)!; defer { image.free() }
		if image.status == .unavailable { counts.unavailable++; counts.reasons[int(image.reason)]++; if image.bytes.len != 0 || image.value_mask.len != 0 { return error('partial image exposed') }; continue }
		mut expected := image.bytes.clone(); defer { unsafe { expected.free() } }
		mut mask := image.value_mask.clone(); defer { unsafe { mask.free() } }
		if corrupt.len > 0 && ir.types[c.type_index].kind == .integer_t && ir.types[c.type_index].bits == 32 && expected.len == 4 && expected[0] != expected[3] {
			if corrupt == 'byte' { expected[0] ^= 1 }
			if corrupt == 'endian' { expected.reverse_in_place() }
			if corrupt == 'size' { expected.delete_last() }
			if corrupt == 'mask' { mask[0] = 0 }
		}
		if u64(expected.len) != C.LLVMABISizeOfType(target, n.typ(c.type_index, 0)!) || mask.len != expected.len { return error('image allocation/mask size differs') }
		global := C.LLVMAddGlobal(module_ptr, n.typ(c.type_index, 0)!, c'')
		C.LLVMSetInitializer(global, n.constant(i, 0)!); C.LLVMSetGlobalConstant(global, 1)
		points := positions(expected.len); defer { unsafe { points.free() } }
		for point in points {
			payload := n.payload(c.type_index, u64(point), target, 0)!
			if mask[point] != (if payload { u8(255) } else { u8(0) }) { return error('LLVM payload/padding classification differs') }
			if !payload { if expected[point] != 0 { return error('chosen padding is not zero') }; counts.padding++; continue }
			function := C.LLVMAddFunction(module_ptr, c'', C.LLVMFunctionType(byte_type, unsafe { nil }, 0, 0))
			block := C.LLVMAppendBasicBlockInContext(context, function, c'entry'); C.LLVMPositionBuilderAtEnd(builder, block)
			mut indexes := [C.LLVMConstInt(index_type, u64(point), 0)]!
			address := C.LLVMBuildGEP2(builder, byte_type, global, unsafe { &indexes[0] }, 1, c'')
			C.LLVMBuildRet(builder, C.LLVMBuildLoad2(builder, byte_type, address, c''))
			probes << ByteProbe{block, expected[point], i, point}
		}
		counts.complete++; counts.bytes += u64(expected.len)
	}
	options := C.LLVMCreatePassBuilderOptions(); defer { C.LLVMDisposePassBuilderOptions(options) }; C.LLVMPassBuilderOptionsSetVerifyEach(options, 1)
	err := C.LLVMRunPasses(module_ptr, c'function(instcombine)', unsafe { nil }, options)
	if err != unsafe { nil } { msg := C.LLVMGetErrorMessage(err); defer { C.LLVMDisposeErrorMessage(msg) }; return error(unsafe { cstring_to_vstring(msg) }.clone()) }
	if out.len > 0 { msg := C.LLVMPrintModuleToString(module_ptr); defer { C.LLVMDisposeMessage(msg) }; os.write_file(out, unsafe { cstring_to_vstring(msg) })! }
	for probe in probes {
		value := C.LLVMGetOperand(C.LLVMGetBasicBlockTerminator(probe.block), 0)
		if C.LLVMIsAConstantInt(value) == unsafe { nil } { counts.unresolved++; continue }
		if C.LLVMConstIntGetZExtValue(value) != probe.expected { return error('LLVM folded byte differs: constant=${probe.constant_index} offset=${probe.offset} expected=${probe.expected} actual=${C.LLVMConstIntGetZExtValue(value)}') }
		counts.checked++
	}
	return counts
}
fn fresh(out string) ! { if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { return error('requires fresh external output') }; os.mkdir_all(out)! }
fn describe(c ImageCounts) string { return 'complete=${c.complete} unavailable=${c.unavailable} bytes=${c.bytes} checked=${c.checked} unresolved=${c.unresolved} padding=${c.padding} reasons=${c.reasons}' }
fn self_test(assembler string, out string) ! {
	fresh(out)!; mut controls := 0
	for i, layout in ['e-i24:64', 'E-i24:64'] {
		prefix := out + '/profile-${i}'; defer { unsafe { prefix.free() } }
		source := 'target datalayout = "${layout}"
@word = constant i32 287454020
@wide = constant i128 340282366920938463463374607431768211454
@record = constant { i8, i24, <3 x i16> } { i8 -85, i24 1193046, <3 x i16> <i16 1, i16 -32768, i16 32767> }
@packed = constant <{i8, i24}> <{i8 17, i24 1193046}>
@str = constant [4 x i8] c"A\\00Z\\00"
@array = constant [2 x i24] [i24 1193046, i24 -2]
@nan = constant float 0x7FF8000000000000
@negativezero = constant half 0xH8000
@bad = constant i32 undef
@poison = constant i32 poison
@relocation = constant { ptr } { ptr @word }
@expression = constant ptr getelementptr(i8, ptr @word, i64 1)
@onebit = constant i1 true
@zeros = constant [3 x i1] zeroinitializer
@nullptr = constant ptr null
'
		defer { unsafe { source.free() } }; os.write_file(prefix + '.ll', source)!
		mut process := os.new_process(assembler); defer { process.close() }
		process.set_args([prefix + '.ll', '-o', prefix + '.bc']); process.set_redirect_stdio(); process.run(); process.wait()
		stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str()
		defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
		os.write_file(prefix + '.assemble.log', log)!; os.write_file(prefix + '.assemble.status', status)!
		if process.code != 0 { return error('fixture assembly failed') }
		counts := check(prefix + '.bc', prefix + '.folded.ll', '')!
		if counts.checked < 50 || counts.unavailable < 5 { return error('fixture coverage missing') }
		text := describe(counts); defer { unsafe { text.free() } }; os.write_file(prefix + '.counts', text)!
		if i == 0 { for mode in ['byte', 'endian', 'size', 'mask'] { check(prefix + '.bc', '', mode) or { controls++; continue }; return error('accepted corrupted image') } }
	}
	println('LLVM-IMAGE-SELFTEST: little/big endian byte folding, aggregate/packed/array/vector/string/FP fixtures; ${controls} corrupted images rejected; inspect counts for unresolved bytes; no shader execution')
}
fn corpus(input string, out string) ! {
	fresh(out)!; mut files := os.ls(input)!; files.sort(); defer { unsafe { files.free() } }
	mut total := ImageCounts{}; mut modules := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		path := input + '/' + file; defer { unsafe { path.free() } }
		c := check(path, out + '/' + file + '.folded.ll', '')!
		os.cp(path, out + '/' + file)!; text := describe(c); defer { unsafe { text.free() } }; os.write_file(out + '/' + file + '.counts', text)!
		total.complete += c.complete; total.unavailable += c.unavailable; total.bytes += c.bytes; total.checked += c.checked; total.unresolved += c.unresolved; total.padding += c.padding
		for i in 0 .. 7 { total.reasons[i] += c.reasons[i] }; modules++
	}
	if modules == 0 { return error('no modules') }
	text := describe(total); defer { unsafe { text.free() } }
	println('LLVM-IMAGE-CORPUS: ${modules} modules ${text}; unresolved bytes excluded, no shader execution')
}
fn main() {
	if os.args.len == 4 && os.args[1] == 'inspect' { c := check(os.args[2], os.args[3], '')!; text := describe(c); println(text); unsafe { text.free() }; return }
	if os.args.len == 4 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3])!; return }
	if os.args.len == 4 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3])!; return }
	panic('usage: air-image-inspect self-test LLVM_AS FRESH_EXTERNAL_DIR | corpus INPUT_DIR FRESH_EXTERNAL_DIR')
}
