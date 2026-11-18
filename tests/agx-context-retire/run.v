// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	a := source.index(start) or { return error(start) }; b := source.index_after(end, a + start.len) or { return error(end) }; return source[a..b]
}
fn run_checks() !int {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	mut garbage := repo + '/kernel/gpu/agx/gpu/g13_context.v'
	mut wire := repo + '/kernel/gpu/agx/fw/channels.v'; mut queue := repo + '/kernel/gpu/agx/gpu/g13.v'
	for i := 1; i < os.args.len; i += 2 { assert i + 1 < os.args.len
		match os.args[i] {
			'--source' { garbage = os.args[i + 1] }
			'--wire-source' { wire = os.args[i + 1] }
			'--queue-source' { queue = os.args[i + 1] }
			else { panic('usage: run [--source CONTEXT] [--wire-source CHANNELS] [--queue-source G13]') }
		}
	}
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-context-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!; defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-heap-gc/fixture', scratch, false)!
	os.cp_all(repo + '/tests/agx-heap/fixture/memory', scratch + '/memory', false)!
	base := os.read_file(scratch + '/gpu/fixture.v')!
	fields := '\tg13_shared alloc.HeapAllocator\n\tg13_queues []&G13QueueResources\n\tg13_context_head &G13QueueResources = unsafe { nil }\n\tg13_context_tail &G13QueueResources = unsafe { nil }\n\tcontext_refuse_map bool\n\tcontext_map_calls int\n\tcontext_backing_calls int\n'
	fixture := base.replace('\tg13_gpu_readonly alloc.HeapAllocator\n', '\tg13_gpu_readonly alloc.HeapAllocator\n' + fields)
		.replace('assert pc + rc > 0', 'assert context_test_queue == unsafe { nil } || context_test_queue.context.mapped')
	os.write_file(scratch + '/gpu/fixture.v', fixture)!
	for file in ['types.v', 'wire.v', 'test.v'] { os.cp(repo + '/tests/agx-context-retire/' + file, scratch + '/gpu/' + file)! }
	os.cp(repo + '/tests/agx-context-defer/test.v', scratch + '/gpu/defer.v')!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.check_context_retirement(); gpu.check_context_deferral() }\n')!
	for name in ['alloc', 'channel', 'fw'] {
		os.mkdir_all(scratch + '/gpu/agx/' + name)!; filename := if name == 'fw' { 'channels.v' } else { name + '.v' }
		os.cp(if name == 'fw' { wire } else { repo + '/kernel/gpu/agx/' + name + '/' + filename }, scratch + '/gpu/agx/' + name + '/' + filename)!
	}
	os.symlink(repo + '/kernel/gpu/agx/hw', scratch + '/gpu/agx/hw')!
	os.mkdir_all(scratch + '/katomic')!; os.cp(repo + '/tests/agx-g13-failure/fixture/katomic/atomic.v', scratch + '/katomic/atomic.v')!
	os.write_file(scratch + '/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n')!
	manager := os.read_file(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	enum_source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	production := 'module gpu\n' + section(enum_source, 'enum G13ContextRetirement', '\n')! + '\n' +
		section(manager, 'struct SharedBuffer {', '// The probe owns boot requests')! +
		section(os.read_file(queue)!, 'fn (mut mgr GpuManager) free_g13_queue_resources_locked(', '// Caller holds the manager and subqueue locks.')! +
		section(os.read_file(queue)!, 'fn (mut mgr GpuManager) release_all_g13_queue_resources()', '\n}\n')! + '\n}\n'
	os.write_file(scratch + '/gpu/production.v', production)!
	os.cp(garbage, scratch + '/gpu/context.v')!
	os.cp(repo + '/kernel/gpu/agx/gpu/g13_garbage.v', scratch + '/gpu/garbage.v')!
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals', '-path', scratch + '|@vlib|@vmodules',
		'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
	mut p := os.new_process(compiler); mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main.v']; p.set_args(args); p.run(); p.wait(); if p.code != 0 { return p.code }; p.close()
	if target := os.getenv_opt('AGX_CONTEXT_C') { mut c := os.new_process(compiler); mut args_c := flags.clone(); args_c << ['-o', target, scratch + '/main.v']; c.set_args(args_c); c.run(); c.wait(); if c.code != 0 { return c.code }; c.close() }
	if target := os.getenv_opt('AGX_CONTEXT_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); return test.code
}
fn main() { code := run_checks() or { panic(err) }; assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-context-${os.getpid()}')); exit(code) }
