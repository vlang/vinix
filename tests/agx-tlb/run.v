// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing production section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing production terminator: ${end}') }
	return source[begin..finish]
}

fn main() {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-tlb-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-tlb/fixture', scratch, false)!
	os.mkdir_all('${scratch}/gpu/agx/pgtable')!
	os.cp('${repo}/kernel/gpu/agx/pgtable/pgtable.v', '${scratch}/gpu/agx/pgtable/pgtable.v')!
	os.write_file('${scratch}/gpu/agx/pgtable/host.v', 'module pgtable\n__global higher_half = u64(0)\n')!
	// Run the actual root publishers against real host page tables. Replace
	// privileged instructions and handoff arbitration, not the PTE operations.
	source := os.read_file('${repo}/kernel/gpu/agx/mmu/mmu.v')!
	mut production := 'module mmu\nimport aarch64.cpu\n'
	production += section(source, 'fn (mut mgr UatManager) publish_initial_context_roots()', 'pub fn (mut mgr UatManager) create_context(')!
	production += section(source, 'pub fn (mgr &UatManager) bind_context(', '// Map a driver-owned allocation into context zero.')!
	os.write_file('${scratch}/gpu/agx/mmu/production.v', production)!
	os.cp('${repo}/tests/agx-tlb/test.v', '${scratch}/main.v')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	mut flags := ['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-path',
		'${scratch}|@vlib|@vmodules']
	if '--sanitize' in os.args {
		flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address,undefined']
	}
	flags << ['-o', '${scratch}/test', '${scratch}/main.v']
	build.set_args(flags)
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	mut test := os.new_process('${scratch}/test')
	test.run()
	test.wait()
	exit(test.code)
}
