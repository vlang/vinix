// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os

#flag -I/opt/homebrew/opt/llvm/include
#flag -L/opt/homebrew/opt/llvm/lib
#flag -lLLVM
#flag -Wl,-rpath,/opt/homebrew/opt/llvm/lib
#include <llvm-c/Core.h>
#include <llvm-c/BitReader.h>
#include <llvm-c/Target.h>
#include <llvm-c/Transforms/PassBuilder.h>

fn C.LLVMContextCreate() voidptr
fn C.LLVMContextDispose(voidptr)
fn C.LLVMCreateMemoryBufferWithMemoryRangeCopy(voidptr, usize, &char) voidptr
fn C.LLVMDisposeMemoryBuffer(voidptr)
fn C.LLVMParseBitcodeInContext2(voidptr, voidptr, &voidptr) int
fn C.LLVMDisposeModule(voidptr)
fn C.LLVMGetDataLayoutStr(voidptr) &char
fn C.LLVMGetFirstGlobal(voidptr) voidptr
fn C.LLVMGetNextGlobal(voidptr) voidptr
fn C.LLVMGetValueName2(voidptr, &usize) &char
fn C.LLVMTypeOf(voidptr) voidptr
fn C.LLVMGlobalGetValueType(voidptr) voidptr
fn C.LLVMGetTypeKind(voidptr) int
fn C.LLVMGetIntTypeWidth(voidptr) u32
fn C.LLVMGetElementType(voidptr) voidptr
fn C.LLVMGetArrayLength2(voidptr) u64
fn C.LLVMGetVectorSize(voidptr) u32
fn C.LLVMCountStructElementTypes(voidptr) u32
fn C.LLVMStructGetTypeAtIndex(voidptr, u32) voidptr
fn C.LLVMIsPackedStruct(voidptr) int
fn C.LLVMIsOpaqueStruct(voidptr) int
fn C.LLVMGetStructName(voidptr) &char
fn C.LLVMGetPointerAddressSpace(voidptr) u32
fn C.LLVMIsGlobalConstant(voidptr) int
fn C.LLVMGetInitializer(voidptr) voidptr
fn C.LLVMGetAlignment(voidptr) u32
fn C.LLVMGetThreadLocalMode(voidptr) int
fn C.LLVMIsExternallyInitialized(voidptr) int
fn C.LLVMGetLinkage(voidptr) int
fn C.LLVMCreateTargetData(&char) voidptr
fn C.LLVMDisposeTargetData(voidptr)
fn C.LLVMStoreSizeOfType(voidptr, voidptr) u64
fn C.LLVMABISizeOfType(voidptr, voidptr) u64
fn C.LLVMOffsetOfElement(voidptr, voidptr, u32) u64
fn C.LLVMIntTypeInContext(voidptr, u32) voidptr
fn C.LLVMFunctionType(voidptr, voidptr, u32, int) voidptr
fn C.LLVMModuleCreateWithNameInContext(&char, voidptr) voidptr
fn C.LLVMSetDataLayout(voidptr, &char)
fn C.LLVMAddGlobal(voidptr, voidptr, &char) voidptr
fn C.LLVMSetInitializer(voidptr, voidptr)
fn C.LLVMSetGlobalConstant(voidptr, int)
fn C.LLVMAddFunction(voidptr, &char, voidptr) voidptr
fn C.LLVMAppendBasicBlockInContext(voidptr, voidptr, &char) voidptr
fn C.LLVMCreateBuilderInContext(voidptr) voidptr
fn C.LLVMDisposeBuilder(voidptr)
fn C.LLVMPositionBuilderAtEnd(voidptr, voidptr)
fn C.LLVMConstInt(voidptr, u64, int) voidptr
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

fn compare_type(ir airbitcode.IRModule, index int, native voidptr, depth int) ! {
	if index < 0 || index >= ir.types.len || depth > 64 { return error('global type index/depth') }
	t := ir.types[index]
	kind := match t.kind { .integer_t { 8 } .half_t { 1 } .float_t { 2 } .double_t { 3 } .x86_fp80_t { 4 } .fp128_t { 5 } .ppc_fp128_t { 6 } .struct_t, .opaque_t { 10 } .array_t { 11 } .pointer_t { 12 } .vector_t { if t.scalable { 17 } else { 13 } } .bfloat_t { 18 } else { return error('unsupported global oracle type') } }
	if C.LLVMGetTypeKind(native) != kind { return error('LLVM global storage type kind differs') }
	if t.kind == .integer_t && C.LLVMGetIntTypeWidth(native) != t.bits { return error('LLVM integer width differs') }
	if t.kind == .pointer_t && C.LLVMGetPointerAddressSpace(native) != t.address_space { return error('LLVM pointer address space differs') }
	if t.kind in [.struct_t, .opaque_t] {
		name := C.LLVMGetStructName(native)
		if name != unsafe { nil } { if unsafe { cstring_to_vstring(name) } != t.name { return error('LLVM structure name differs') } }
		else if t.name.len != 0 { return error('missing LLVM structure name') }
		if (C.LLVMIsOpaqueStruct(native) != 0) != (t.kind == .opaque_t) { return error('LLVM opaque structure differs') }
		if t.kind == .opaque_t { return }
		if C.LLVMCountStructElementTypes(native) != u32(t.refs_count) || (C.LLVMIsPackedStruct(native) != 0) != t.packed { return error('LLVM structure shape differs') }
		for i in 0 .. t.refs_count { compare_type(ir, ir.references[t.refs_start + i], C.LLVMStructGetTypeAtIndex(native, u32(i)), depth + 1)! }
	}
	if t.kind in [.array_t, .vector_t] {
		count := if t.kind == .array_t { C.LLVMGetArrayLength2(native) } else { u64(C.LLVMGetVectorSize(native)) }
		if count != t.count { return error('LLVM sequential count differs') }
		compare_type(ir, ir.references[t.refs_start], C.LLVMGetElementType(native), depth + 1)!
	}
}
fn linkage(raw u32) int {
	return match raw { 0, 5, 6, 15 { 0 } 2 { 7 } 3 { 8 } 7 { 12 } 8 { 14 } 9, 13, 14 { 9 } 12 { 1 } 1, 16 { 5 } 10, 17 { 6 } 4, 18 { 2 } 11, 19 { 3 } else { 0 } }
}
fn compare_global(ir airbitcode.IRModule, g airbitcode.IRGlobalVariable, native voidptr) ! {
	mut size := usize(0); name := C.LLVMGetValueName2(native, &size)
	actual := if size == 0 { '' } else { unsafe { tos(name, int(size)) } }
	if actual != g.name || C.LLVMGetPointerAddressSpace(C.LLVMTypeOf(native)) != g.address_space || (C.LLVMIsGlobalConstant(native) != 0) != g.is_constant { return error('LLVM global name/address space/constant flag differs') }
	if (C.LLVMGetInitializer(native) != unsafe { nil }) != g.has_initializer || u64(C.LLVMGetAlignment(native)) != g.alignment || C.LLVMGetThreadLocalMode(native) != int(g.thread_local) || (C.LLVMIsExternallyInitialized(native) != 0) != g.externally_initialized || C.LLVMGetLinkage(native) != linkage(g.linkage) { return error('LLVM global initializer/alignment/TLS/external/linkage differs') }
	compare_type(ir, g.type_index, C.LLVMGlobalGetValueType(native), 0)!
}
fn payload(typ voidptr, offset u64, target voidptr, depth int) !bool {
	if depth > 64 { return error('LLVM payload depth') }
	if offset >= C.LLVMStoreSizeOfType(target, typ) { return false }
	kind := C.LLVMGetTypeKind(typ)
	if kind in [11, 13] { child := C.LLVMGetElementType(typ); stride := if kind == 13 { C.LLVMStoreSizeOfType(target, child) } else { C.LLVMABISizeOfType(target, child) }; return stride != 0 && payload(child, offset % stride, target, depth + 1)! }
	if kind == 10 {
		for i in 0 .. C.LLVMCountStructElementTypes(typ) { child := C.LLVMStructGetTypeAtIndex(typ, i); start := C.LLVMOffsetOfElement(target, typ, i); if offset >= start && offset - start < C.LLVMABISizeOfType(target, child) { return payload(child, offset - start, target, depth + 1)! } }
		return false
	}
	return true
}
struct GlobalProbe { block voidptr expected u8 }
struct GlobalCounts {
mut:
	globals int
	definitions int
	images int
	unavailable int
	bytes int
	padding int
	unresolved int
}
fn positions(size int) []int { if size > 16 { return [0, 1, 2, 3, size / 2, size - 2, size - 1] }; return []int{len: size, init: index} }
fn altered(g airbitcode.IRGlobalVariable, mode string) airbitcode.IRGlobalVariable {
	return match mode {
		'name' { airbitcode.IRGlobalVariable{...g, name: 'changed-name'} }
		'type' { airbitcode.IRGlobalVariable{...g, type_index: -1} }
		'AS' { airbitcode.IRGlobalVariable{...g, address_space: g.address_space + 1} }
		'constant' { airbitcode.IRGlobalVariable{...g, is_constant: !g.is_constant} }
		'initializer' { airbitcode.IRGlobalVariable{...g, has_initializer: !g.has_initializer} }
		'alignment' { airbitcode.IRGlobalVariable{...g, alignment: g.alignment + 1} }
		'TLS' { airbitcode.IRGlobalVariable{...g, thread_local: (g.thread_local + 1) % 5} }
		'external' { airbitcode.IRGlobalVariable{...g, externally_initialized: !g.externally_initialized} }
		'linkage' { airbitcode.IRGlobalVariable{...g, linkage: if g.linkage == 0 { u32(3) } else { u32(0) }} }
		else { g }
	}
}
fn check(path string, out string, corrupt string) !GlobalCounts {
	if os.file_size(path) > airbitcode.max_input_size { return error('input limit') }
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; layouts := ir.type_layouts()!; defer { layouts.free() }
	globals := ir.global_variables(data, stream, pools)!; defer { globals.free() }
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	buffer := C.LLVMCreateMemoryBufferWithMemoryRangeCopy(data.data, usize(data.len), c'original-AIR'); defer { C.LLVMDisposeMemoryBuffer(buffer) }
	mut original := unsafe { nil }
	if C.LLVMParseBitcodeInContext2(context, buffer, &original) != 0 { return error('LLVM original bitcode parse failed') }
	defer { C.LLVMDisposeModule(original) }
	mut handles := []voidptr{len: globals.entries.len, init: unsafe { nil }}; defer { unsafe { handles.free() } }
	mut current := C.LLVMGetFirstGlobal(original)
	for i, entry in globals.entries {
		if current == unsafe { nil } { return error('missing LLVM global') }
		compare_global(ir, if i == 0 { altered(entry, corrupt) } else { entry }, current)!
		handles[i] = current; current = C.LLVMGetNextGlobal(current)
	}
	if current != unsafe { nil } { return error('extra LLVM global') }
	oracle := C.LLVMModuleCreateWithNameInContext(c'initializer-templates', context); defer { C.LLVMDisposeModule(oracle) }
	C.LLVMSetDataLayout(oracle, C.LLVMGetDataLayoutStr(original))
	target := C.LLVMCreateTargetData(C.LLVMGetDataLayoutStr(original)); defer { C.LLVMDisposeTargetData(target) }
	builder := C.LLVMCreateBuilderInContext(context); defer { C.LLVMDisposeBuilder(builder) }
	byte_type := C.LLVMIntTypeInContext(context, 8); index_type := C.LLVMIntTypeInContext(context, 64)
	mut probes := []GlobalProbe{}; probes.flags |= .noslices; defer { unsafe { probes.free() } }
	mut counts := GlobalCounts{globals: globals.entries.len}
	for i, entry in globals.entries {
		if entry.has_initializer { counts.definitions++ }
		image := globals.initializer_image(ir, stream, pools, layouts, i)!; defer { image.free() }
		if image.status == .unavailable { counts.unavailable++; if image.bytes.len != 0 || image.value_mask.len != 0 { return error('partial image') }; continue }
		actual_type := C.LLVMGlobalGetValueType(handles[i])
		if u64(image.bytes.len) != C.LLVMABISizeOfType(target, actual_type) || image.bytes.len != image.value_mask.len { return error('LLVM image size differs') }
		template_global := C.LLVMAddGlobal(oracle, actual_type, c''); C.LLVMSetInitializer(template_global, C.LLVMGetInitializer(handles[i])); C.LLVMSetGlobalConstant(template_global, 1)
		points := positions(image.bytes.len); defer { unsafe { points.free() } }
		for point in points {
			is_payload := payload(actual_type, u64(point), target, 0)!
			mask := if corrupt == 'image-mask' && i == 0 && point == 0 { u8(0) } else { image.value_mask[point] }
			if mask != (if is_payload { u8(255) } else { u8(0) }) { return error('LLVM image mask differs') }
			if !is_payload { if image.bytes[point] != 0 { return error('chosen padding differs') }; counts.padding++; continue }
			function := C.LLVMAddFunction(oracle, c'', C.LLVMFunctionType(byte_type, unsafe { nil }, 0, 0)); block := C.LLVMAppendBasicBlockInContext(context, function, c'entry'); C.LLVMPositionBuilderAtEnd(builder, block)
			mut indexes := [C.LLVMConstInt(index_type, u64(point), 0)]!
			address := C.LLVMBuildGEP2(builder, byte_type, template_global, unsafe { &indexes[0] }, 1, c'')
			C.LLVMBuildRet(builder, C.LLVMBuildLoad2(builder, byte_type, address, c''))
			probes << GlobalProbe{block, if corrupt == 'image-byte' && i == 0 && point == 0 { image.bytes[point] ^ 1 } else { image.bytes[point] }}
		}
		counts.images++
	}
	options := C.LLVMCreatePassBuilderOptions(); defer { C.LLVMDisposePassBuilderOptions(options) }; C.LLVMPassBuilderOptionsSetVerifyEach(options, 1)
	err := C.LLVMRunPasses(oracle, c'function(instcombine)', unsafe { nil }, options)
	if err != unsafe { nil } { msg := C.LLVMGetErrorMessage(err); defer { C.LLVMDisposeErrorMessage(msg) }; return error(unsafe { cstring_to_vstring(msg) }.clone()) }
	if out.len > 0 { msg := C.LLVMPrintModuleToString(oracle); defer { C.LLVMDisposeMessage(msg) }; os.write_file(out, unsafe { cstring_to_vstring(msg) })! }
	for probe in probes { value := C.LLVMGetOperand(C.LLVMGetBasicBlockTerminator(probe.block), 0); if C.LLVMIsAConstantInt(value) == unsafe { nil } { counts.unresolved++; continue }; if C.LLVMConstIntGetZExtValue(value) != probe.expected { return error('LLVM original initializer byte differs') }; counts.bytes++ }
	return counts
}
fn fresh(out string) ! { if os.exists(out) || os.is_link(out) || os.abs_path(out).starts_with(os.getwd() + '/') { return error('requires fresh external output') }; os.mkdir_all(out)! }
fn describe(c GlobalCounts) string { return 'globals=${c.globals} definitions=${c.definitions} images=${c.images} unavailable=${c.unavailable} compared_bytes=${c.bytes} padding=${c.padding} unresolved=${c.unresolved}' }
fn self_test(assembler string, out string) ! {
	fresh(out)!; mut controls := 0
	for i, layout in ['e-p:64:64-p3:32:32-i24:64', 'E-p:64:64-p3:32:32-i24:64'] {
		prefix := out + '/profile-${i}'; defer { unsafe { prefix.free() } }
		source := 'target datalayout = "${layout}"
@value = internal addrspace(3) constant i32 287454020, align 4
@external = external global [4 x i32]
@tls = thread_local(localexec) global i32 9, align 16
@dynamic = externally_initialized global i32 7
@packed = private constant <{i8, i24}> <{i8 17, i24 1193046}>, align 1
@pointer = global ptr @external
@nested = constant {i32, <3 x i32>} {i32 19, <3 x i32> <i32 -1, i32 2, i32 3>}
@u = global i32 undef
@p = global i32 poison
@expression = global ptr getelementptr(i8, ptr @external, i64 1)
@alias = alias <{i8, i24}>, ptr @packed
define void @function() { ret void }
'
		defer { unsafe { source.free() } }; os.write_file(prefix + '.ll', source)!
		mut process := os.new_process(assembler); defer { process.close() }; process.set_args([prefix + '.ll', '-o', prefix + '.bc']); process.set_redirect_stdio(); process.run(); process.wait()
		stdout := process.stdout_slurp(); stderr := process.stderr_slurp(); log := stdout + stderr; status := process.code.str(); defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
		os.write_file(prefix + '.assemble.log', log)!; os.write_file(prefix + '.assemble.status', status)!
		if process.code != 0 { return error('fixture assembly failed') }
		c := check(prefix + '.bc', prefix + '.folded.ll', '')!
		if c.globals != 10 || c.definitions != 9 || c.images != 5 || c.unavailable != 5 || c.bytes < 15 { return error('fixture coverage missing') }
		text := describe(c); defer { unsafe { text.free() } }; os.write_file(prefix + '.counts', text)!
		if i == 0 { for mode in ['name', 'type', 'AS', 'constant', 'initializer', 'alignment', 'TLS', 'external', 'linkage', 'image-byte', 'image-mask'] { check(prefix + '.bc', '', mode) or { controls++; continue }; return error('accepted corrupted global evidence') } }
	}
	println('LLVM-GLOBALS-SELFTEST: original bitcode metadata/types and initializer bytes in both byte orders; ${controls} corruptions rejected; no global installation or shader execution')
}
fn corpus(input string, out string) ! {
	fresh(out)!; mut files := os.ls(input)!; files.sort(); defer { unsafe { files.free() } }; mut total := GlobalCounts{}; mut modules := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		path := input + '/' + file; defer { unsafe { path.free() } }
		c := check(path, out + '/' + file + '.folded.ll', '')!
		os.cp(path, out + '/' + file)!; text := describe(c); defer { unsafe { text.free() } }; os.write_file(out + '/' + file + '.counts', text)!
		total.globals += c.globals; total.definitions += c.definitions; total.images += c.images; total.unavailable += c.unavailable; total.bytes += c.bytes; total.padding += c.padding; total.unresolved += c.unresolved; modules++
	}
	if modules == 0 { return error('no modules') }; text := describe(total); defer { unsafe { text.free() } }; println('LLVM-GLOBALS-CORPUS: ${modules} modules ${text}; unresolved bytes excluded; no execution')
}
fn main() {
	if os.args.len == 4 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3])!; return }
	if os.args.len == 4 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3])!; return }
	panic('usage: air-globals-inspect self-test LLVM_AS FRESH_EXTERNAL_DIR | corpus INPUT_DIR FRESH_EXTERNAL_DIR')
}
