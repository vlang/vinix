// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing production section: ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing production terminator: ${end}') }
	return source[begin..finish]
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-tlb-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-tlb/fixture', scratch, false)!
	os.cp_all('${repo}/tests/agx-async/fixture/event', '${scratch}/event', false)!
	os.cp_all('${repo}/tests/agx-async/fixture/proc', '${scratch}/proc', false)!
	os.cp_all('${repo}/tests/agx-g13-failure/fixture/katomic', '${scratch}/katomic', false)!
	os.mkdir_all('${scratch}/gpu/agx/pgtable')!
	os.cp('${repo}/kernel/gpu/agx/pgtable/pgtable.v', '${scratch}/gpu/agx/pgtable/pgtable.v')!
	os.cp('${repo}/kernel/gpu/agx/tlb/plan.v', '${scratch}/gpu/agx/tlb/plan.v')!
	os.write_file('${scratch}/gpu/agx/pgtable/host.v', 'module pgtable\n__global higher_half = u64(0)\n')!
	// Run the actual root publishers against real host page tables. Replace
	// privileged instructions and handoff arbitration, not the PTE operations.
	source := os.read_file(os.getenv_opt('AGX_TLB_MMU_SOURCE') or { '${repo}/kernel/gpu/agx/mmu/mmu.v' })!
	mut production := 'module mmu\nimport aarch64.cpu\nimport event\nimport katomic\n'
	production += section(source, 'fn (mut mgr UatManager) publish_initial_context_roots()', 'pub fn (mut mgr UatManager) create_context(')!
	production += section(source, 'pub fn (ctx &UatContext) is_bound(', '// Map a driver-owned allocation into context zero.')!
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
	if output := os.getenv_opt('AGX_TLB_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut test := os.new_process('${scratch}/test')
	test.run()
	test.wait()
	exit(test.code)
}
