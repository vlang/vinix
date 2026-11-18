// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run_checks() !int {
	assert os.args.len in [1, 3, 5]
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	mut manager_path := repo + '/kernel/gpu/agx/gpu/gpu.v'
	mut allocator_path := repo + '/kernel/gpu/agx/alloc/alloc.v'
	for i := 1; i < os.args.len; i += 2 {
		match os.args[i] {
			'--manager-source' { manager_path = os.args[i + 1] }
			'--allocator-source' { allocator_path = os.args[i + 1] }
			else { panic('usage: run [--manager-source FILE] [--allocator-source FILE]') }
		}
	}
	manager := os.read_file(manager_path)!
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-pressure-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-heap-gc/fixture', scratch, false)!
	os.cp(repo + '/tests/agx-heap-pressure/fixture.v', scratch + '/gpu/pressure.v')!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.check_pressure() }\n')!
	mut factories := 'module gpu\nimport gpu.agx.alloc\n'
	for class in ['g13_private', 'g13_gpu_readonly'] {
		line := manager.all_after(class + ': ').all_before('\n').trim_space()
		assert line.starts_with('alloc.new_heap')
		factories += 'fn ' + class + '_heap() alloc.HeapAllocator { return ' + line + ' }\n'
	}
	os.write_file(scratch + '/gpu/factories.v', factories)!
	caller := manager.all_after('fn alloc_buffer_from_heap(').all_before('fn (mut mgr GpuManager) alloc_shared_buffer_with_protection(')
	assert caller.contains('memory.pmm_free(voidptr(phys), pages)')
	fixed := manager.all_after('fn alloc_fixed_buffer(').all_before('// Remove a context-zero UAT mapping')
	constants := manager.all_after('const buffer_allocator_default').all_before('// GPU states')
	types := manager.all_after('struct SharedBuffer {').all_before('@[inline]')
	// Avoid V's cross-module global/local page_size name collision in the host
	// closure runtime. Only this external binding is renamed; control flow is exact.
	os.write_file(scratch + '/gpu/caller.v', 'module gpu\nimport memory\nimport gpu.agx.alloc\nimport gpu.agx.pgtable\n' +
		'const buffer_allocator_default' + constants + 'struct SharedBuffer {' + types +
		'\nfn alloc_buffer_from_heap(' + caller.replace(' / page_size', ' / pressure_host_page_size') +
		'\nfn alloc_fixed_buffer(' + fixed.replace(' / page_size', ' / pressure_host_page_size'))!
	for directory in ['memory', 'gpu/agx/pgtable'] {
		os.mkdir_all(scratch + '/' + directory)!
		os.cp(repo + '/tests/agx-heap-pressure/' + os.file_name(directory) + '.v', scratch + '/' + directory + '/host.v')!
	}
	for name in ['alloc', 'channel', 'fw'] {
		os.mkdir_all(scratch + '/gpu/agx/' + name)!
		filename := if name == 'fw' { 'channels.v' } else { name + '.v' }
		os.cp(if name == 'alloc' { allocator_path } else { repo + '/kernel/gpu/agx/' + name + '/' + filename }, scratch + '/gpu/agx/' + name + '/' + filename)!
	}
	os.symlink(repo + '/kernel/gpu/agx/hw', scratch + '/gpu/agx/hw')!
	os.cp(repo + '/kernel/gpu/agx/gpu/g13_garbage.v', scratch + '/gpu/production.v')!
	os.write_file(scratch + '/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n')!
	os.mkdir_all(scratch + '/katomic')!
	os.cp(repo + '/tests/agx-g13-failure/fixture/katomic/atomic.v', scratch + '/katomic/atomic.v')!
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
	mut build := os.new_process(compiler); mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main.v']
	build.set_args(args); build.run(); build.wait(); if build.code != 0 { return build.code }
	if target := os.getenv_opt('AGX_PRESSURE_C') {
		mut generated := os.new_process(compiler); mut cargs := flags.clone(); cargs << ['-o', target, scratch + '/main.v']
		generated.set_args(cargs); generated.run(); generated.wait(); if generated.code != 0 { return generated.code }
	}
	if target := os.getenv_opt('AGX_PRESSURE_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); return test.code
}
fn main() { code := run_checks() or { panic(err) }; assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-pressure-${os.getpid()}')); exit(code) }
