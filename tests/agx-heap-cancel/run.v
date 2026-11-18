// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	a := source.index(start) or { return error(start) }; b := source.index_after(end, a + start.len) or { return error(end) }
	return source[a..b]
}
fn run_checks() !int {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	mut manager_path := repo + '/kernel/gpu/agx/gpu/gpu.v'; mut allocator_path := repo + '/kernel/gpu/agx/alloc/alloc.v'
	mut selected := ''
	for i := 1; i < os.args.len; i += 2 {
		assert i + 1 < os.args.len
		match os.args[i] {
			'--manager-source' { manager_path = os.args[i + 1] }
			'--allocator-source' { allocator_path = os.args[i + 1] }
			'--case' { selected = os.args[i + 1]; assert selected in ['model', 'rollback', 'measure'] }
			else { panic('usage: run [--manager-source FILE] [--allocator-source FILE] [--case model|rollback]') }
		}
	}
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-cancel-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-heap/fixture', scratch, false)!
	old_main := os.read_file(scratch + '/main/main.v')!
	os.write_file(scratch + '/main/main.v', old_main.all_before('fn main()'))!
	os.cp(repo + '/tests/agx-heap-cancel/model.v', scratch + '/main/cancel.v')!
	os.cp(repo + '/tests/agx-heap-gc/fixture/klock/lock.v', scratch + '/klock/lock.v')!
	for directory in ['gpu/agx/alloc', 'gpu/agx/pgtable', 'gpu/agx/tlb', 'gpu', 'memory', 'lib', 'aarch64/cpu'] { os.mkdir_all(scratch + '/' + directory)! }
	os.cp(allocator_path, scratch + '/gpu/agx/alloc/alloc.v')!
	os.cp(repo + '/kernel/gpu/agx/pgtable/pgtable.v', scratch + '/gpu/agx/pgtable/pgtable.v')!
	os.cp(repo + '/kernel/gpu/agx/tlb/plan.v', scratch + '/gpu/agx/tlb/plan.v')!
	os.cp(repo + '/tests/agx-tlb/fixture/gpu/agx/tlb/tlb.v', scratch + '/gpu/agx/tlb/tlb.v')!
	os.cp(repo + '/tests/agx-tlb/fixture/aarch64/cpu/cpu.v', scratch + '/aarch64/cpu/cpu.v')!
	os.cp(repo + '/kernel/lib/math.v', scratch + '/lib/math.v')!
	os.write_file(scratch + '/gpu/agx/pgtable/host.v', 'module pgtable\n__global higher_half = u64(0)\n')!
	os.cp(repo + '/tests/agx-heap-cancel/rollback.v', scratch + '/gpu/fixture.v')!
	os.cp(repo + '/tests/agx-heap-cancel/memory.v', scratch + '/memory/memory.v')!
	source := os.read_file(manager_path)!
	types := section(source, 'struct SharedBuffer {', '@[inline]')!
	caller := section(source, 'fn alloc_buffer_from_heap(', 'fn (mut mgr GpuManager) alloc_shared_buffer_with_protection(')!
	default_allocator := 'const buffer_allocator_default' + source.all_after('const buffer_allocator_default').all_before('\n')
	os.write_file(scratch + '/gpu/production.v', 'module gpu\nimport gpu.agx.alloc\nimport gpu.agx.pgtable\nimport memory\n' +
		default_allocator + '\n' + types + caller.replace(' / page_size', ' / cancel_host_page_size'))!
	compiler := os.getenv_opt('V') or { 'v' }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-d', 'agx_heap_sanitized', '-d', 'agx_heap_history_invariants', '-d', 'agx_heap_garbage',
		'-path', scratch + '|@vlib|@vmodules']
	if selected == 'measure' {
		flags << ['-d', 'agx_cancel_measure']; os.setenv('MallocNanoZone', '0', true)
	} else { flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
	mut p := os.new_process(compiler); mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main']
	p.set_args(args); p.run(); p.wait(); if p.code != 0 { return p.code }; p.close()
	if target := os.getenv_opt('AGX_CANCEL_C') {
		mut c := os.new_process(compiler); mut cargs := flags.clone(); cargs << ['-o', target, scratch + '/main']; c.set_args(cargs); c.run(); c.wait(); if c.code != 0 { return c.code }; c.close()
	}
	if target := os.getenv_opt('AGX_CANCEL_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test'); if selected != '' { test.set_args([selected]) }; test.run(); test.wait(); return test.code
}
fn main() { code := run_checks() or { panic(err) }; assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-cancel-${os.getpid()}')); exit(code) }
