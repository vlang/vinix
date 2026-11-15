// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode
import os
import strings
import time

// Usage: v -path '@vlib|compat/ios|@vmodules' run this_file LLVM_AS FRESH_EXTERNAL_DIR
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
	mut text := strings.new_builder(262144)
	text.write_string('target datalayout = "e-p:64:64"\n')
	mut names := []string{}
	mut bits_list := []int{}
	mut lanes_list := []int{}
	for bits in 1 .. 67 {
		t := if bits <= 64 {
			'i${bits}'
		} else if bits == 65 {
			'half'
		} else {
			'float'
		}
		name := 'scalar_${bits}'
		names << name
		bits_list << if bits <= 64 {
			bits
		} else if bits == 65 {
			16
		} else {
			32
		}
		lanes_list << 1
		text.write_string('define void @${name}(ptr %src, ptr %dst) { %v = load ${t}, ptr %src, align 1\n store ${t} %v, ptr %dst, align 1\n ret void }\n')
	}
	for element in 0 .. 10 {
		for n in 1 .. 17 {
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
			name := 'vector_${element}_${n}'
			names << name
			bits_list << bits
			lanes_list << n
			text.write_string('define void @${name}(ptr %src, ptr %dst) { %v = load <${n} x ${t}>, ptr %src, align 1\n store <${n} x ${t}> %v, ptr %dst, align 1\n ret void }\n')
		}
	}
	text.write_string('declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)\n declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1 immarg)\n declare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)\n')
	for mode in ['copy', 'move'] {
		text.write_string('define void @${mode}(ptr %src, ptr %dst) { store i8 17, ptr %dst\n %d = getelementptr i8, ptr %dst, i64 1\n call void @llvm.mem${if mode == 'copy' {
			'cpy'
		} else {
			'move'
		}}.p0.p0.i64(ptr %d, ptr %src, i64 8, i1 false)\n ret void }\n')
	}
	text.write_string('define void @fill(ptr %src, ptr %dst) { %v = load i8, ptr %src\n call void @llvm.memset.p0.i64(ptr %dst, i8 %v, i64 9, i1 false)\n ret void }\n')
	text.write_string('define void @branch(ptr %src, ptr %dst) { entry: %v = load i8, ptr %src\n %c = icmp ne i8 %v, 0\n br i1 %c, label %left, label %right\n left: %a = add i8 %v, 3\n br label %join\n right: br label %join\n join: %r = phi i8 [%a, %left], [91, %right]\n store i8 %r, ptr %dst\n ret void }\n')
	text.write_string('define void @poison(ptr %src, ptr %dst) { store i8 17, ptr %dst\n %v = load i8, ptr %src\n %r = shl nuw i8 %v, 1\n %d = getelementptr i8, ptr %dst, i64 1\n store i8 %r, ptr %d\n ret void }\n')
	text.write_string('define void @aligned(ptr %src, ptr %dst) { %v = load i32, ptr %src, align 4\n store i32 %v, ptr %dst, align 4\n ret void }\n define void @empty() { ret void }\n')
	text.write_string('define void @spaces(ptr addrspace(2) %src, ptr addrspace(1) %dst) { %v = load i32, ptr addrspace(2) %src, align 1\n store i32 %v, ptr addrspace(1) %dst, align 1\n ret void }\n')
	text.write_string('define void @cold_bad(ptr %src, ptr %dst) { store i8 17, ptr %dst\n br i1 true, label %done, label %bad\n bad: %v = load <2 x i7>, ptr %src, align 1\n ret void\n done: ret void }\n')
	text.write_string('define void @cold(ptr %src, ptr %dst) { entry: %v = load i8, ptr %src\n %c = icmp ne i8 %v, 0\n br i1 %c, label %cold, label %done\n cold:\n')
	for i in 0 .. 2048 { text.write_string('%v${i} = add i64 ${i}, 1\n') }
	text.write_string('br label %done\n done: store i8 %v, ptr %dst\n ret void }\n')
	os.write_file(root + '/input.ll', text.str())!
	r := os.exec([os.args[1], root + '/input.ll', '-o', root + '/input.bc'])
	os.write_file(root + '/assemble.log', r.output)!
	assert r.exit_code == 0, r.output
	data := os.read_bytes(root + '/input.bc')!
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
	mut copies := 0
	mut guards := 0
	mut rows := os.create(root + '/comparisons.txt')!
	defer { rows.close() }
	for i, name in names {
		f := fi(ir, name)
		plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
		assert plan.argument_count() == 2 && plan.steps() == 3
		bits := bits_list[i]
		bytes := (bits + 7) / 8 * lanes_list[i]
		assert plan.argument(0)!.minimum_size == u64(bytes) && plan.argument(1)!.writable
		mut copy := plan.argument(1)!
		copy.writable = false
		copy.minimum_size = 0
		assert plan.argument(1)!.writable && plan.argument(1)!.minimum_size == u64(bytes)
		for sample in 0 .. 128 {
			mut input := []u8{len: bytes + 8, init: u8(index * 37 + sample)}
			mut output := []u8{len: bytes + 8, init: 0xcc}
			mut bs := [airbitcode.IRMemoryBinding{ data: input, offset: 1 },
				airbitcode.IRMemoryBinding{ data: output, offset: 3, writable: true }]
			assert plan.run(mut bs, 3)!.steps == 3
			for j, b in output {
				assert b == if j >= 3 && j < 3 + bytes {
					input[j - 2] & if bits % 8 != 0 && (j - 2) % ((bits + 7) / 8) == 0 {
						u8((u32(1) << u32(bits % 8)) - 1)
					} else {
						u8(255)
					}
				} else {
					u8(0xcc)
				}
			}
			saved := output.clone()
			for j in 0 .. output.len { output[j] = 0xcc }
			assert p.run_memory_function(ir, stream, pools, bodies, f, mut bs, 3)!.steps == 3
			assert output == saved
			rows.writeln('${name} ${sample} PASS')!
			copies++
			unsafe {
				input.free()
				output.free()
				bs.free()
				saved.free()
			}
		}
		mut input := []u8{len: bytes + 8, init: 0x55}
		mut output := []u8{len: bytes + 8, init: 0xcc}
		mut bs := [airbitcode.IRMemoryBinding{ data: input },
			airbitcode.IRMemoryBinding{ data: output, writable: true }]
		for limit in [0, 2, 1000001] {
			if _ := plan.run(mut bs, limit) { panic('budget') }
			unchanged(output)
			guards++
		}
		for bad in [airbitcode.IRMemoryBinding{ data: output },
			airbitcode.IRMemoryBinding{ data: output, offset: 9, writable: true },
			airbitcode.IRMemoryBinding{ data: output, base_alignment: 3, writable: true }] {
			bs[1] = bad
			if _ := plan.run(mut bs, 3) { panic('binding') }
			unchanged(output)
			guards++
		}
		for index in [-1, 2] {
			if _ := plan.argument(index) { panic('argument index') }
			guards++
		}
		mut missing := []airbitcode.IRMemoryBinding{}
		if _ := plan.run(mut missing, 3) { panic('binding count') }
		guards++
		unsafe {
			input.free()
			output.free()
			bs.free()
			missing.free()
		}
		plan.free()
	}
	for name in ['copy', 'move', 'fill', 'branch', 'poison'] {
		f := fi(ir, name)
		plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
		for sample in 0 .. 256 {
			mut input := []u8{len: 16, init: u8(sample + index)}
			mut output := []u8{len: 16, init: 0xcc}
			mut bs := [airbitcode.IRMemoryBinding{ data: input },
				airbitcode.IRMemoryBinding{ data: output, writable: true }]
			mut error_text := ''
			if _ := plan.run(mut bs, plan.steps()) {} else { error_text = err.msg() }
			expect_poison := name == 'poison' && sample >= 128
			assert error_text == if expect_poison {
				'AIR memory execution: poison store'
			} else {
				''
			}
			for j, b in output {
				expected := if name in ['copy', 'move'] {
					if j == 0 {
						u8(17)
					} else if j <= 8 {
						input[j - 1]
					} else {
						u8(0xcc)
					}
				} else if name == 'fill' {
					if j < 9 { u8(sample) } else { u8(0xcc) }
				} else if name == 'branch' {
					if j == 0 {
						if sample == 0 { u8(91) } else { u8(sample + 3) }
					} else {
						u8(0xcc)
					}
				} else {
					if j == 0 {
						u8(17)
					} else if j == 1 && !expect_poison {
						u8(sample * 2)
					} else {
						u8(0xcc)
					}
				}
				assert b == expected, '${name} ${sample} ${j}'
			}
			saved := output.clone()
			for j in 0 .. output.len { output[j] = 0xcc }
			mut ordinary_error := ''
			if _ := p.run_memory_function(ir, stream, pools, bodies, f, mut bs, plan.steps()) {
			} else {
				ordinary_error = err.msg()
			}
			assert output == saved && ordinary_error == error_text
			unsafe {
				input.free()
				output.free()
				bs.free()
				saved.free()
			}
			guards++
		}
		if name == 'poison' {
			// The last 128 calls failed. Reuse the same preparation for a
			// defined value to check that poison/error state did not persist.
			mut input := [u8(1)]
			mut output := [u8(0xcc), 0xcc]
			mut bs := [airbitcode.IRMemoryBinding{ data: input },
				airbitcode.IRMemoryBinding{ data: output, writable: true }]
			plan.run(mut bs, plan.steps())!
			assert output == [u8(17), 2]
			unsafe {
				input.free()
				output.free()
				bs.free()
			}
		}
		plan.free()
	}
	extra_controls(p, ir, stream, pools, bodies)!
	benchmark(p, ir, stream, pools, bodies, root)!
	assert copies == 28928 && guards == 3314
	os.write_file(root + '/result.txt', 'AIR-PREPARED-MEMORY: ${copies} scalar/vector prepared-vs-ordinary byte comparisons; ${guards} changing-input, failure-recovery, bounds/budget/metadata-copy controls; aliasing, alignment, empty/default and cold-preflight controls PASS\n')!
	print(os.read_file(root + '/result.txt')!)
}

fn extra_controls(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies) ! {
	mut bytes := []u8{len: 32, init: u8(index)}
	mut output := []u8{len: 32, init: 0xcc}
	mut bs := [airbitcode.IRMemoryBinding{ data: bytes },
		airbitcode.IRMemoryBinding{ data: bytes, offset: 1, writable: true }]
	copy_plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'copy'))!
	saved := bytes.clone()
	if _ := copy_plan.run(mut bs, copy_plan.steps()) { panic('aliased memcpy') }
	assert bytes == saved
	bs[1] = airbitcode.IRMemoryBinding{ data: output, writable: true }
	copy_plan.run(mut bs, copy_plan.steps())!
	copy_plan.free()
	move_plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'move'))!
	bs[1] = airbitcode.IRMemoryBinding{ data: bytes, offset: 1, writable: true }
	move_plan.run(mut bs, move_plan.steps())!
	assert bytes[1] == 17 && bytes[2..10] == [u8(0), 17, 2, 3, 4, 5, 6, 7]
	move_plan.free()
	for j in 0 .. output.len { output[j] = 0xcc }
	align_plan := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'aligned'))!
	bs[1] = airbitcode.IRMemoryBinding{ data: output, writable: true }
	if _ := align_plan.run(mut bs, 3) { panic('base alignment') }
	unchanged(output)
	bs[0] = airbitcode.IRMemoryBinding{ data: bytes, base_alignment: 4, offset: 1 }
	bs[1] = airbitcode.IRMemoryBinding{ data: output, base_alignment: 4, writable: true }
	if _ := align_plan.run(mut bs, 3) { panic('offset alignment') }
	unchanged(output)
	bs[0] = airbitcode.IRMemoryBinding{ data: bytes, base_alignment: 4 }
	align_plan.run(mut bs, 3)!
	assert output[..4] == bytes[..4]
	align_plan.free()
	spaces := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'spaces'))!
	for j in 0 .. output.len { output[j] = 0xcc }
	bs[0] = airbitcode.IRMemoryBinding{ data: bytes, writable: true }
	if _ := spaces.run(mut bs, 3) { panic('writable constant address space') }
	unchanged(output)
	bs[0] = airbitcode.IRMemoryBinding{ data: bytes }
	spaces.run(mut bs, 3)!
	assert output[..4] == bytes[..4]
	spaces.free()
	if _ := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'cold_bad')) {
		panic('cold block')
	}
	empty := p.prepare_memory_function(ir, stream, pools, bodies, fi(ir, 'empty'))!
	mut no_bindings := []airbitcode.IRMemoryBinding{}
	assert empty.run(mut no_bindings, 1)!.steps == 1
	empty.free()
	default_plan := airbitcode.IRPreparedMemoryFunction{}
	if _ := default_plan.run(mut no_bindings, 1) { panic('uninitialized') }
	default_plan.free()
	unsafe {
		bytes.free()
		output.free()
		bs.free()
		saved.free()
		no_bindings.free()
	}
}

fn benchmark(p airbitcode.IRTypedProgram, ir airbitcode.IRModule, stream airbitcode.Stream, pools airbitcode.IRConstantPools, bodies airbitcode.IRFunctionBodies, root string) ! {
	f := fi(ir, 'cold')
	plan := p.prepare_memory_function(ir, stream, pools, bodies, f)!
	defer { plan.free() }
	mut input := [u8(0)]
	mut output := [u8(0xcc)]
	mut bs := [airbitcode.IRMemoryBinding{ data: input },
		airbitcode.IRMemoryBinding{ data: output, writable: true }]
	mut samples := ''
	for round in 0 .. 5 {
		for prepared in if round % 2 == 0 { [true, false] } else { [false, true] } {
			start := time.sys_mono_now()
			for _ in 0 .. 100 {
				if prepared {
					assert plan.run(mut bs, plan.steps())!.steps == 5
				} else {
					assert p.run_memory_function(ir, stream, pools, bodies, f, mut bs, plan.steps())!.steps == 5
				}
				assert output[0] == 0
			}
			elapsed := time.sys_mono_now() - start
			samples += '${round} ${prepared} ${elapsed}\n'
		}
	}
	os.write_file(root + '/benchmark-nanoseconds.txt', samples)!
	unsafe {
		input.free()
		output.free()
		bs.free()
	}
}
