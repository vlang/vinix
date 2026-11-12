// SPDX-License-Identifier: GPL-2.0-or-later
module main
import airbitcode
import os
import strings
fn find_function(ir airbitcode.IRModule, name string) int { for i, f in ir.functions { if f.name == name { return i } }; panic('missing fixture') }
fn main() {
	assert os.args.len == 3
	out := os.abs_path(os.args[2]); assert !os.exists(out) && !out.starts_with(os.getwd() + '/')
	os.mkdir_all(out)!; mut source := strings.new_builder(8192)
	source.write_string('target datalayout = "e-p:64:64"\n')
	for i in 1 .. 67 {
		typ := if i <= 64 { 'i${i}' } else if i == 65 { 'half' } else { 'float' }
		source.write_string('define void @copy_${i}(ptr %src, ptr %dst) {\n %v = load ${typ}, ptr %src, align 1\n store ${typ} %v, ptr %dst, align 1\n ret void\n}\n')
	}
	source.write_string('define void @constant(ptr %dst) { store i32 305419896, ptr %dst, align 1\n ret void }\ndefine void @poison(ptr %dst) { store i32 poison, ptr %dst, align 1\n ret void }\ndefine void @undef(ptr %dst) { store i32 undef, ptr %dst, align 1\n ret void }\ndefine void @volatile(ptr %dst) { store volatile i32 1, ptr %dst, align 1\n ret void }\ndefine void @aligned(ptr %src, ptr %dst) { %v = load i32, ptr %src, align 4\n store i32 %v, ptr %dst, align 4\n ret void }\ndefine void @unsupported(ptr %dst) { store i32 1, ptr %dst, align 1\n %v = add nuw i32 2, 3\n ret void }\n')
	os.write_file(out + '/input.ll', source.str())!
	mut extra := os.open_append(out + '/input.ll')!
	extra.write_string('define void @spaces(ptr addrspace(2) %src, ptr addrspace(1) %dst) { %v = load i32, ptr addrspace(2) %src, align 1\n store i32 %v, ptr addrspace(1) %dst, align 1\n ret void }\n')!; extra.close()
	mut proc := os.new_process(os.args[1]); proc.set_args([out + '/input.ll', '-o', out + '/input.bc']); proc.set_redirect_stdio_merged(); proc.run(); log := proc.stdout_slurp(); proc.wait(); code := proc.code; proc.close(); os.write_file(out + '/assemble.log', log)!; assert code == 0
	data := os.read_bytes(out + '/input.bc')!; stream := airbitcode.parse(data)!; defer { stream.free() }; ir := stream.ir_module(data)!; defer { ir.free() }
	pools := ir.constant_pools(stream)!; defer { pools.free() }; bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }; p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	mut checks := 0
	for i in 1 .. 67 {
		bits := if i <= 64 { i } else if i == 65 { 16 } else { 32 }; bytes := (bits + 7) / 8
		function := find_function(ir, 'copy_${i}')
		for sample in 0 .. 256 {
			mut input := []u8{len: 16}; mut output := []u8{len: 16, init: 0xcc}
			word := if sample < 8 { [u64(0), ~u64(0), 0x8000000000000000, 0x7fc00001, 0x7f800000, 0xff800000, 0x7e01, 1]![sample] } else { u64(sample) * u64(0x9e3779b97f4a7c15) }
			for j in 0 .. bytes { input[1 + j] = u8(word >> u32(j * 8)) }
			mut bindings := [airbitcode.IRMemoryBinding{data: input, offset: 1}, airbitcode.IRMemoryBinding{data: output, offset: 3, writable: true}]
			assert p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3)!.steps == 3
			mask := if bits == 64 { ~u64(0) } else { (u64(1) << u32(bits)) - 1 }
			for j in 0 .. 16 { assert output[j] == if j >= 3 && j < 3 + bytes { u8((word & mask) >> u32((j - 3) * 8)) } else { u8(0xcc) } }
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 2) { panic('budget accepted') }
			bindings[1] = airbitcode.IRMemoryBinding{data: output, offset: 3}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('readonly store accepted') }
			bindings[1] = airbitcode.IRMemoryBinding{data: output, offset: 16, writable: true}
			if _ := p.run_memory_function(ir, stream, pools, bodies, function, mut bindings, 3) { panic('out of bounds accepted') }
			unsafe { input.free(); output.free(); bindings.free() }; checks++
		}
	}
	mut bytes := []u8{len: 16, init: 0xcc}; mut binding := [airbitcode.IRMemoryBinding{data: bytes, offset: 4, writable: true}]
	assert p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'constant'), mut binding, 2)!.steps == 2
	assert bytes[4] == 0x78 && bytes[5] == 0x56 && bytes[6] == 0x34 && bytes[7] == 0x12
	for name in ['poison', 'undef', 'volatile', 'unsupported'] { bytes[4] = 0xcc; if _ := p.run_memory_function(ir, stream, pools, bodies, find_function(ir, name), mut binding, 10) { panic('guard accepted') }; assert bytes[4] == 0xcc }
	mut aligned := [airbitcode.IRMemoryBinding{data: bytes, base_alignment: 4, offset: 0}, airbitcode.IRMemoryBinding{data: bytes, base_alignment: 4, offset: 8, writable: true}]
	bytes[0] = 7; bytes[1] = 13; bytes[2] = 29; bytes[3] = 53
	p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'aligned'), mut aligned, 3)!
	for i in 0 .. 4 { assert bytes[8 + i] == bytes[i] }
	p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'spaces'), mut aligned, 3)!
	aligned[0] = airbitcode.IRMemoryBinding{data: bytes, base_alignment: 4, writable: true}
	if _ := p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'spaces'), mut aligned, 3) { panic('constant address space writable') }
	aligned[0] = airbitcode.IRMemoryBinding{data: bytes, base_alignment: 4, offset: 1}
	if _ := p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'aligned'), mut aligned, 3) { panic('misalignment accepted') }
	big := airbitcode.IRModule{...ir, data_layout: 'E-p:64:64'}
	if _ := p.run_memory_function(big, stream, pools, bodies, find_function(ir, 'constant'), mut binding, 3) { panic('big endian accepted') }
	aligned[0] = airbitcode.IRMemoryBinding{data: bytes, base_alignment: 4, offset: 16}
	if _ := p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'aligned'), mut aligned, 3) { panic('out of bounds load accepted') }
	mut missing := []airbitcode.IRMemoryBinding{}
	if _ := p.run_memory_function(ir, stream, pools, bodies, find_function(ir, 'aligned'), mut missing, 3) { panic('missing bindings accepted') }
	if _ := p.run_void_function(ir, stream, pools, bodies, find_function(ir, 'copy_32'), [u64(0), 0], 3) { panic('scalar void API accepted memory') }
	os.write_file(out + '/result.txt', 'AIR-MEMORY-EXECUTION: ${checks} serialized scalar copies, i1-i64/half/float raw bits, padding guards, readonly/bounds/budgets, constant stores, poison/undef/volatile/unsupported rejection, aligned aliases, address spaces, misalignment and endian guards PASS\n')!; print(os.read_file(out + '/result.txt')!)
}
