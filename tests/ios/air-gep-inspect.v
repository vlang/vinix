// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os

#flag -I/opt/homebrew/opt/llvm/include
#flag -L/opt/homebrew/opt/llvm/lib
#flag -lLLVM
#flag -Wl,-rpath,/opt/homebrew/opt/llvm/lib
#include <llvm-c/Core.h>
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
fn C.LLVMFunctionType(voidptr, voidptr, u32, int) voidptr
fn C.LLVMModuleCreateWithNameInContext(&char, voidptr) voidptr
fn C.LLVMDisposeModule(voidptr)
fn C.LLVMSetDataLayout(voidptr, &char)
fn C.LLVMAddFunction(voidptr, &char, voidptr) voidptr
fn C.LLVMAppendBasicBlockInContext(voidptr, voidptr, &char) voidptr
fn C.LLVMCreateBuilderInContext(voidptr) voidptr
fn C.LLVMDisposeBuilder(voidptr)
fn C.LLVMPositionBuilderAtEnd(voidptr, voidptr)
fn C.LLVMConstInt(voidptr, u64, int) voidptr
fn C.LLVMConstIntToPtr(voidptr, voidptr) voidptr
fn C.LLVMBuildGEP2(voidptr, voidptr, voidptr, voidptr, u32, &char) voidptr
fn C.LLVMBuildPtrToInt(voidptr, voidptr, voidptr, &char) voidptr
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

struct NativeTypes {
	context voidptr
	p airbitcode.IRTypedProgram
mut:
	cache []voidptr
}
fn (mut n NativeTypes) build(index int, depth int) !voidptr {
	if depth > 64 { return error('oracle type depth') }
	if n.cache[index] != unsafe { nil } { return n.cache[index] }
	t := n.p.types[index]
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
			child := n.build(n.p.references[t.refs_start], depth + 1)!
			result = if t.kind == .array_t { C.LLVMArrayType2(child, t.count) } else { C.LLVMVectorType(child, u32(t.count)) }
		}
		.struct_t {
			mut fields := []voidptr{len: t.refs_count, init: unsafe { nil }}; defer { unsafe { fields.free() } }
			for i in 0 .. t.refs_count { fields[i] = n.build(n.p.references[t.refs_start + i], depth + 1)! }
			result = C.LLVMStructTypeInContext(n.context, fields.data, u32(fields.len), int(t.packed))
		}
		else { return error('unsupported oracle type') }
	}
	if result == unsafe { nil } { return error('oracle type construction failed') }
	n.cache[index] = result; return result
}
struct Probe {
	block voidptr
	expected u64
}
fn sample_word(sample int, ordinal int) u64 {
	return match sample { 0 { u64(0) } 1 { u64(1 + ordinal) } 2 { ~u64(0) } 3 { u64(1) << 63 } 4 { u64(0x100000081) } else { u64(0xfedcba9876543210) + u64(ordinal) } }
}
fn add_probe(mut n NativeTypes, module_ptr voidptr, builder voidptr, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, index int, plan airbitcode.IRGEPOffsetPlan, sample int) !Probe {
	op := n.p.instructions[index]
	i64type := C.LLVMIntTypeInContext(n.context, 64)
	function := C.LLVMAddFunction(module_ptr, c'', C.LLVMFunctionType(i64type, unsafe { nil }, 0, 0))
	block := C.LLVMAppendBasicBlockInContext(n.context, function, c'entry')
	C.LLVMPositionBuilderAtEnd(builder, block)
	mut indexes := []voidptr{len: op.operands_count - 1, init: unsafe { nil }}
	mut values := []u64{}
	values.flags |= .noslices
	defer { unsafe { indexes.free(); values.free() } }
	mut current := op.source_type
	mut term := 0
	for j in 0 .. indexes.len {
		operand_index := op.operands_start + j + 1
		operand := n.p.operands[operand_index]
		mut bits := sample_word(sample, j)
		node := n.p.types[current]
		if j > 0 && node.kind == .struct_t {
			value := pools.lookup(bodies.instructions[index].scope, operand.number)!
			if value.kind != .constant { return error('oracle struct index is not constant') }
			bits = pools.scalar_bits(value.constant_index)!
			current = n.p.references[node.refs_start + int(bits)]
		} else {
			if term >= plan.terms.len || plan.terms[term].operand_index != operand_index || plan.terms[term].bits != n.p.types[operand.type_index].bits { return error('plan term identity/width differs') }
			values << bits; term++
			if j > 0 { current = n.p.references[node.refs_start] }
		}
		// SignExtend=false supplies precisely the low limb for i128 too; upper
		// limbs cannot affect an offset whose pointer index width is <=64.
		indexes[j] = C.LLVMConstInt(n.build(operand.type_index, 0)!, bits, 0)
	}
	if term != plan.terms.len { return error('extra plan terms') }
	base := if sample < 3 { u64(0) } else { u64(0x12345678fffffff0) }
	base_type := n.p.operands[op.operands_start].type_index
	// LLVM derives pointer/index widths from the module's data layout.
	pointer := n.build(base_type, 0)!
	base_value := C.LLVMConstIntToPtr(C.LLVMConstInt(i64type, base, 0), pointer)
	gep := C.LLVMBuildGEP2(builder, n.build(op.source_type, 0)!, base_value, indexes.data, u32(indexes.len), c'')
	C.LLVMBuildRet(builder, C.LLVMBuildPtrToInt(builder, gep, i64type, c''))
	return Probe{block, plan.address(base, values)!}
}
fn check(path string, out string, corrupt string) !(int, int, int) {
	if os.file_size(path) > airbitcode.max_input_size { return error('input size limit') }
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	stream := airbitcode.parse(data)!; defer { stream.free() }
	ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }
	bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	layouts := p.type_layouts(ir)!; defer { layouts.free() }
	context := C.LLVMContextCreate(); defer { C.LLVMContextDispose(context) }
	module_ptr := C.LLVMModuleCreateWithNameInContext(c'gep-offset-oracle', context); defer { C.LLVMDisposeModule(module_ptr) }
	C.LLVMSetDataLayout(module_ptr, ir.data_layout.str)
	builder := C.LLVMCreateBuilderInContext(context); defer { C.LLVMDisposeBuilder(builder) }
	mut n := NativeTypes{context: context, p: p, cache: []voidptr{len: p.types.len, init: unsafe { nil }}}
	mut probes := []Probe{}
	probes.flags |= .noslices
	defer { unsafe { n.cache.free(); probes.free() } }
	mut count := 0; mut excluded := 0
	for i, op in p.instructions {
		if stream.records[bodies.instructions[i].record].code !in [u64(4), 30, 43]! { continue }
		if op.status != .decoded { return error('undecoded GEP in qualification input') }
		if p.types[op.result_type].kind == .vector_t { excluded++; continue }
		plan := p.gep_offset_plan(stream, pools, bodies, layouts, i)!; defer { plan.free() }
		mut terms := plan.terms.clone(); defer { unsafe { terms.free() } }
		mut changed := airbitcode.IRGEPOffsetPlan{...plan, terms: terms}
		if corrupt == 'stride' && terms.len > 0 { terms[0] = airbitcode.IRGEPScale{...terms[0], stride: terms[0].stride + 1} }
		if corrupt == 'identity' && terms.len > 0 { terms[0] = airbitcode.IRGEPScale{...terms[0], operand_index: terms[0].operand_index + 1} }
		if corrupt == 'bits' && terms.len > 0 { terms[0] = airbitcode.IRGEPScale{...terms[0], bits: terms[0].bits + 1} }
		if corrupt == 'constant' { changed = airbitcode.IRGEPOffsetPlan{...changed, constant_offset: changed.constant_offset + 1} }
		if corrupt == 'index' { changed = airbitcode.IRGEPOffsetPlan{...changed, index_bits: 8} }
		if corrupt == 'pointer' { changed = airbitcode.IRGEPOffsetPlan{...changed, pointer_bits: 8} }
		for sample in 0 .. 6 { probes << add_probe(mut n, module_ptr, builder, pools, bodies, i, changed, sample)! }
		count++
	}
	options := C.LLVMCreatePassBuilderOptions(); defer { C.LLVMDisposePassBuilderOptions(options) }
	C.LLVMPassBuilderOptionsSetVerifyEach(options, 1)
	err := C.LLVMRunPasses(module_ptr, c'function(instcombine)', unsafe { nil }, options)
	if err != unsafe { nil } {
		message := C.LLVMGetErrorMessage(err); defer { C.LLVMDisposeErrorMessage(message) }
		return error(unsafe { cstring_to_vstring(message) }.clone())
	}
	if out.len > 0 {
		text := C.LLVMPrintModuleToString(module_ptr); defer { C.LLVMDisposeMessage(text) }
		os.write_file(out, unsafe { cstring_to_vstring(text) })!
	}
	for i, probe in probes {
		value := C.LLVMGetOperand(C.LLVMGetBasicBlockTerminator(probe.block), 0)
		if C.LLVMIsAConstantInt(value) == unsafe { nil } || C.LLVMConstIntGetZExtValue(value) != probe.expected { return error('LLVM folded GEP address differs at probe ${i}') }
	}
	return count, probes.len, excluded
}
fn fresh(path string) ! {
	if os.exists(path) || os.is_link(path) || os.abs_path(path).starts_with(os.getwd() + '/') { return error('requires fresh external output') }
	os.mkdir_all(path)!
}
fn self_test(assembler string, out string) ! {
	fresh(out)!
	mut total := 0; mut probes := 0; mut controls := 0
	for i, layout in ['e-p:64:64-p3:64:64-i24:64', 'E-p:32:32-p3:32:32-i24:32', 'e-p:64:64-p3:64:64:64:16-i24:64'] {
		prefix := out + '/profile-${i}'; defer { unsafe { prefix.free() } }
		source := 'target datalayout = "${layout}"
%Packet = type { i8, [4 x i24], <3 x i24> }
%Packed = type <{ i8, [4 x i24], <3 x i24> }>
define ptr addrspace(3) @nested(ptr addrspace(3) %p, i8 %x, i128 %y) {
  %r = getelementptr %Packet, ptr addrspace(3) %p, i8 %x, i32 1, i128 %y
  ret ptr addrspace(3) %r
}
define ptr addrspace(3) @packed(ptr addrspace(3) %p, i64 %x, i32 %y) {
  %r = getelementptr %Packed, ptr addrspace(3) %p, i64 %x, i32 1, i32 %y
  ret ptr addrspace(3) %r
}
define ptr addrspace(3) @vector_element(ptr addrspace(3) %p, i64 %x, i64 %y) {
  %r = getelementptr <3 x i24>, ptr addrspace(3) %p, i64 %x, i64 %y
  ret ptr addrspace(3) %r
}
define ptr addrspace(3) @identity(ptr addrspace(3) %p) {
  %r = getelementptr i8, ptr addrspace(3) %p
  ret ptr addrspace(3) %r
}
define <2 x ptr addrspace(3)> @vector_shape(ptr addrspace(3) %p, <2 x i64> %x) {
  %r = getelementptr i32, ptr addrspace(3) %p, <2 x i64> %x
  ret <2 x ptr addrspace(3)> %r
}
'
		defer { unsafe { source.free() } }
		os.write_file(prefix + '.ll', source)!
		mut process := os.new_process(assembler); defer { process.close() }
		process.set_args([prefix + '.ll', '-o', prefix + '.bc']); process.set_redirect_stdio(); process.run(); process.wait()
		stdout := process.stdout_slurp(); stderr := process.stderr_slurp()
		log := stdout + stderr; status := process.code.str()
		defer { unsafe { stdout.free(); stderr.free(); log.free(); status.free() } }
		os.write_file(prefix + '.assemble.log', log)!
		os.write_file(prefix + '.assemble.status', status)!
		if process.code != 0 { return error('LLVM fixture assembly failed') }
		c, p, excluded := check(prefix + '.bc', prefix + '.folded.ll', '')!
		if c != 4 || p != 24 || excluded != 1 { return error('fixture coverage differs') }
		total += c; probes += p
		if i == 0 {
			for mode in ['stride', 'constant', 'index', 'pointer', 'identity', 'bits'] {
				check(prefix + '.bc', '', mode) or { controls++; continue }
				return error('accepted corrupted GEP plan')
			}
		}
	}
	println('LLVM-GEP-SELFTEST: ${total} scalar GEP plans, ${probes} address probes; three vector GEPs explicitly excluded; ${controls} corruptions rejected; no memory access or shader execution')
}
fn corpus(input string, out string) ! {
	fresh(out)!
	mut files := os.ls(input)!; files.sort(); defer { unsafe { files.free() } }
	mut modules := 0; mut count := 0; mut probes := 0; mut excluded := 0
	for file in files {
		if !file.starts_with('module-') || !file.ends_with('.bc') { continue }
		path := input + '/' + file; defer { unsafe { path.free() } }
		c, p, x := check(path, out + '/' + file + '.folded.ll', '')!
		os.cp(path, out + '/' + file)!
		os.write_file(out + '/' + file + '.counts', 'geps=${c} probes=${p} vector_excluded=${x}\n')!
		modules++; count += c; probes += p; excluded += x
	}
	if modules == 0 { return error('no modules') }
	println('LLVM-GEP-CORPUS: ${modules} modules, ${count} scalar plans, ${probes} address probes match; ${excluded} vector GEPs excluded; no memory access or shader execution')
}
fn main() {
	if os.args.len == 4 && os.args[1] == 'self-test' { self_test(os.args[2], os.args[3])!; return }
	if os.args.len == 4 && os.args[1] == 'corpus' { corpus(os.args[2], os.args[3])!; return }
	panic('usage: air-gep-inspect self-test LLVM_AS FRESH_EXTERNAL_DIR | corpus INPUT_DIR FRESH_EXTERNAL_DIR')
}
