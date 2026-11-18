// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error(start) }
	finish := source.index_after(end, begin + start.len) or { return error(end) }
	return source[begin..finish]
}
fn main() {
	assert os.args.len == 1 || os.args.len == 3 && os.args[1] == '--manager-source'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-uat-flush-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-uat-flush/fixture', scratch, false)!
	manager := os.read_file(if os.args.len == 3 { os.args[2] } else { repo + '/kernel/gpu/agx/gpu/gpu.v' })!
	method := section(manager, 'pub fn (mut mgr GpuManager) flush_g13_uat_range(', '// Notify one of the four priority instances')!
	buffer := section(manager, 'struct SharedBuffer {', '@[inline]')!
	teardown := section(manager, 'fn unmap_shared_buffer(', 'fn (mut mgr GpuManager) invalidate_g13_driver_buffer(')!
	os.write_file(scratch + '/gpu/production.v', 'module gpu\nimport gpu.agx.mmu\nimport gpu.agx.pgtable\nimport gpu.agx.fw\nimport aarch64.timer\nimport katomic\nimport sched\n' + method + buffer + teardown)!
	mmu := os.read_file(repo + '/kernel/gpu/agx/mmu/mmu.v')!
	flush_start := mmu.index('pub fn (mgr &UatManager) begin_flush(') or { panic('begin_flush') }
	flushes := mmu[flush_start..]
	// These methods are the end of mmu.v; keep their exact implementation.
	assert flushes.starts_with('pub fn (mgr &UatManager) begin_flush(')
	layout := section(mmu, '@[packed]\npub struct UatFlushInfo', '@[packed]\nstruct SlotTtbs')!
	mappings := section(mmu, 'pub fn (mgr &UatManager) map_kernel(', '// Prepare one firmware cache-flush slot.')!
	os.write_file(scratch + '/gpu/agx/mmu/production.v', 'module mmu\nimport katomic\nimport aarch64.cpu\nimport gpu.agx.pgtable\n' + layout + mappings + flushes)!
	for name in ['channel', 'fw', 'hw'] {
		os.mkdir_all(scratch + '/gpu/agx/' + name)!
		if name == 'hw' {
			os.rmdir(scratch + '/gpu/agx/hw')!; os.symlink(repo + '/kernel/gpu/agx/hw', scratch + '/gpu/agx/hw')!
		} else {
			file := if name == 'fw' { 'channels.v' } else { 'channel.v' }
			os.cp(repo + '/kernel/gpu/agx/' + name + '/' + file, scratch + '/gpu/agx/' + name + '/' + file)!
		}
	}
	os.write_file(scratch + '/gpu/agx/channel/host.v', 'module channel\n__global higher_half = u64(0)\n')!
	for name in ['lib', 'memory', 'gpu/agx/tlb'] {
		os.cp_all(repo + '/tests/agx-tlb/fixture/' + name, scratch + '/' + name, false)!
	}
	os.mkdir_all(scratch + '/gpu/agx/pgtable')!
	os.cp(repo + '/kernel/gpu/agx/pgtable/pgtable.v', scratch + '/gpu/agx/pgtable/pgtable.v')!
	os.write_file(scratch + '/gpu/agx/pgtable/host.v', 'module pgtable\n__global higher_half = u64(0)\n')!
	for name, path in {'klock': 'tests/agx-heap-gc/fixture/klock/lock.v', 'katomic': 'tests/agx-g13-failure/fixture/katomic/atomic.v',
		'aarch64/timer': 'tests/agx-heap-gc/fixture/aarch64/timer/timer.v', 'aarch64/cpu': 'tests/agx-tlb/fixture/aarch64/cpu/cpu.v'} {
		os.mkdir_all(scratch + '/' + name)!; os.cp(repo + '/' + path, scratch + '/' + name + '/host.v')!
	}
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined']
	mut build := os.new_process(compiler)
	mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main.v']
	build.set_args(args); build.run(); build.wait(); assert build.code == 0
	if target := os.getenv_opt('AGX_UAT_FLUSH_C') {
		mut generated := os.new_process(compiler)
		mut c_args := flags.clone(); c_args << ['-o', target, scratch + '/main.v']
		generated.set_args(c_args); generated.run(); generated.wait(); assert generated.code == 0
	}
	if target := os.getenv_opt('AGX_UAT_FLUSH_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); assert test.code == 0
}
