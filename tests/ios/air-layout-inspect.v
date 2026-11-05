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
fn C.LLVMCreateTargetData(&char) voidptr
fn C.LLVMDisposeTargetData(voidptr)
fn C.LLVMByteOrder(voidptr) int
fn C.LLVMSizeOfTypeInBits(voidptr, voidptr) u64
fn C.LLVMStoreSizeOfType(voidptr, voidptr) u64
fn C.LLVMABISizeOfType(voidptr, voidptr) u64
fn C.LLVMABIAlignmentOfType(voidptr, voidptr) u32
fn C.LLVMPreferredAlignmentOfType(voidptr, voidptr) u32
fn C.LLVMOffsetOfElement(voidptr, voidptr, u32) u64

struct Oracle {
	context voidptr
	types []airbitcode.IRType
	refs []int
mut:
	native []voidptr
}
fn (mut o Oracle) build(index int, depth int) !voidptr {
	if depth > 64 { return error('LLVM oracle type depth') }
	if o.native[index] != unsafe { nil } { return o.native[index] }
	typ := o.types[index]
	mut result := unsafe { nil }
	match typ.kind {
		.integer_t { result = C.LLVMIntTypeInContext(o.context, typ.bits) }
		.half_t { result = C.LLVMHalfTypeInContext(o.context) }
		.bfloat_t { result = C.LLVMBFloatTypeInContext(o.context) }
		.float_t { result = C.LLVMFloatTypeInContext(o.context) }
		.double_t { result = C.LLVMDoubleTypeInContext(o.context) }
		.x86_fp80_t { result = C.LLVMX86FP80TypeInContext(o.context) }
		.fp128_t { result = C.LLVMFP128TypeInContext(o.context) }
		.ppc_fp128_t { result = C.LLVMPPCFP128TypeInContext(o.context) }
		.pointer_t { result = C.LLVMPointerTypeInContext(o.context, typ.address_space) }
		.array_t, .vector_t {
			child := o.build(o.refs[typ.refs_start], depth + 1)!
			result = if typ.kind == .array_t { C.LLVMArrayType2(child, typ.count) } else { C.LLVMVectorType(child, u32(typ.count)) }
		}
		.struct_t {
			mut fields := []voidptr{len: typ.refs_count, init: unsafe { nil }}; defer { unsafe { fields.free() } }
			for i in 0 .. typ.refs_count { fields[i] = o.build(o.refs[typ.refs_start + i], depth + 1)! }
			result = C.LLVMStructTypeInContext(o.context, fields.data, u32(fields.len), int(typ.packed))
		}
		else { return error('unsupported LLVM oracle construction') }
	}
	if result == unsafe { nil } { return error('LLVM type construction failed') }
	o.native[index] = result; return result
}
fn compare_layouts(text string, types []airbitcode.IRType, refs []int, layouts airbitcode.IRTypeLayouts) !(int, int, int) {
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	target := C.LLVMCreateTargetData(text.str); defer { C.LLVMDisposeTargetData(target) }
	if layouts.entries.len != types.len || (C.LLVMByteOrder(target) == 1) != layouts.little_endian { return error('LLVM layout inventory/endianness differs') }
	mut o := Oracle{context: context, types: types, refs: refs, native: []voidptr{len: types.len, init: unsafe { nil }}}
	defer { unsafe { o.native.free() } }
	mut checked := 0; mut fields := 0; mut skipped := 0
	for i, layout in layouts.entries {
		if layout.status != .fixed { skipped++; continue }
		if layout.fields_count != (if types[i].kind == .struct_t { types[i].refs_count } else { 0 }) || layout.fields_start < 0 || layout.fields_start > layouts.field_offsets.len || layout.fields_count > layouts.field_offsets.len - layout.fields_start { return error('decoded structure field range differs') }
		typ := o.build(i, 0)!
		if C.LLVMSizeOfTypeInBits(target, typ) != layout.size_bits || C.LLVMStoreSizeOfType(target, typ) != layout.store_size
			|| C.LLVMABISizeOfType(target, typ) != layout.alloc_size || C.LLVMABIAlignmentOfType(target, typ) != layout.abi_alignment
			|| C.LLVMPreferredAlignmentOfType(target, typ) != layout.preferred_alignment { return error('LLVM type layout differs at type ${i} (${types[i].kind})') }
		for j in 0 .. layout.fields_count {
			if C.LLVMOffsetOfElement(target, typ, u32(j)) != layouts.field_offsets[layout.fields_start + j] { return error('LLVM structure field offset differs') }
			fields++
		}
		checked++
	}
	return checked, fields, skipped
}
fn fresh(path string) ! {
	if os.exists(path) || os.is_link(path) || os.abs_path(path).starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	os.mkdir_all(path)!
}
fn corpus(input string, out string) ! {
	fresh(out)!
	mut files := os.ls(input)!; files.sort(); defer { unsafe { files.free() } }
	mut modules := 0; mut types := 0; mut fields := 0; mut skipped := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		path := input + '/' + file; defer { unsafe { path.free() } }
		if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
		data := os.read_bytes(path)!; defer { unsafe { data.free() } }
		stream := airbitcode.parse(data)!; defer { stream.free() }
		ir := stream.ir_module(data)!; defer { ir.free() }
		layouts := ir.type_layouts()!; defer { layouts.free() }
		t, f, s := compare_layouts(ir.data_layout, ir.types, ir.references, layouts)!
		os.cp(path, out + '/' + file)!
		os.write_file(out + '/' + file + '.layout', 'types=${t} fields=${f} unsized_or_unsupported=${s}\n')!
		modules++; types += t; fields += f; skipped += s
	}
	if modules == 0 { return error('no modules') }
	println('LLVM-LAYOUT-CORPUS: ${modules} modules, ${types} fixed type layouts, ${fields} field offsets match; ${skipped} unsized/unsupported entries excluded; no execution')
}
fn self_test(out string) ! {
	fresh(out)!
	// The oracle receives matching indexed type graphs; it independently computes
	// all sizes and offsets through LLVM TargetData, without our layout algorithms.
	types := [airbitcode.IRType{kind: .integer_t, bits: 1}, airbitcode.IRType{kind: .integer_t, bits: 8}, airbitcode.IRType{kind: .integer_t, bits: 24},
		airbitcode.IRType{kind: .integer_t, bits: 64}, airbitcode.IRType{kind: .float_t}, airbitcode.IRType{kind: .x86_fp80_t},
		airbitcode.IRType{kind: .pointer_t, address_space: 3}, airbitcode.IRType{kind: .vector_t, count: 3, refs_count: 1},
		airbitcode.IRType{kind: .array_t, count: 2, refs_start: 1, refs_count: 1}, airbitcode.IRType{kind: .struct_t, refs_start: 2, refs_count: 3},
		airbitcode.IRType{kind: .struct_t, packed: true, refs_start: 2, refs_count: 3}, airbitcode.IRType{kind: .struct_t},
		airbitcode.IRType{kind: .vector_t, count: 5, refs_start: 5, refs_count: 1}, airbitcode.IRType{kind: .array_t, count: 2, refs_start: 6, refs_count: 1},
		airbitcode.IRType{kind: .integer_t, bits: 65}, airbitcode.IRType{kind: .integer_t, bits: 130}, airbitcode.IRType{kind: .half_t}, airbitcode.IRType{kind: .bfloat_t},
		airbitcode.IRType{kind: .double_t}, airbitcode.IRType{kind: .fp128_t}, airbitcode.IRType{kind: .ppc_fp128_t}, airbitcode.IRType{kind: .vector_t, count: 3, refs_start: 7, refs_count: 1},
		airbitcode.IRType{kind: .array_t, refs_start: 8, refs_count: 1}, airbitcode.IRType{kind: .vector_t, count: 3, refs_start: 9, refs_count: 1}]
	refs := [4, 7, 1, 7, 1, 0, 10, 6, 2, 2]
	defer { unsafe { types.free(); refs.free() } }
	mut total_types := 0; mut total_fields := 0
	for i, text in ['', 'e-p:64:64-p3:32:32:64:16-i64:64-v96:128:256', 'E-a:64:128-f80:32:128-i24:64:128', 'e-p:32:32-p3:36:64:128:16-v96:32:64'] {
		ir := airbitcode.IRModule{data_layout: text, types: types, references: refs}
		layouts := ir.type_layouts()!; defer { layouts.free() }
		t, f, _ := compare_layouts(text, types, refs, layouts)!
		total_types += t; total_fields += f
		os.write_file(out + '/profile-${i}.layout', 'layout=${text}\ntypes=${t} fields=${f}\n')!
	}
	ir := airbitcode.IRModule{types: types, references: refs}
	l := ir.type_layouts()!; defer { l.free() }
	mut controls := 0
	for mode in ['bits', 'store', 'allocation', 'ABI', 'preferred', 'offset', 'fields', 'endian'] {
		mut entries := l.entries.clone(); mut offsets := l.field_offsets.clone()
		defer { unsafe { entries.free(); offsets.free() } }
		x := entries[9]
		match mode {
			'bits' { entries[9] = airbitcode.IRTypeLayout{...x, size_bits: x.size_bits + 8} }
			'store' { entries[9] = airbitcode.IRTypeLayout{...x, store_size: x.store_size + 1} }
			'allocation' { entries[9] = airbitcode.IRTypeLayout{...x, alloc_size: x.alloc_size + 1} }
			'ABI' { entries[9] = airbitcode.IRTypeLayout{...x, abi_alignment: x.abi_alignment * 2} }
			'preferred' { entries[9] = airbitcode.IRTypeLayout{...x, preferred_alignment: x.preferred_alignment * 2} }
			'offset' { offsets[x.fields_start + 1]++ }
			'fields' { entries[9] = airbitcode.IRTypeLayout{...x, fields_count: 0} }
			else {}
		}
		changed := airbitcode.IRTypeLayouts{...l, entries: entries, field_offsets: offsets, little_endian: mode != 'endian'}
		compare_layouts('', types, refs, changed) or { controls++; continue }
		return error('accepted changed layout evidence')
	}
	println('LLVM-LAYOUT-SELFTEST: ${total_types} fixed type layouts and ${total_fields} offsets across four profiles match; ${controls} corrupted layout controls rejected; no execution')
}
fn main() {
	if os.args.len == 4 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3])!; return }
	if os.args.len == 3 && os.args[1] == 'self-test' { self_test(os.args[2])!; return }
	panic('usage: air-layout-inspect self-test FRESH_EXTERNAL_DIR | corpus INPUT_DIR FRESH_EXTERNAL_DIR')
}
