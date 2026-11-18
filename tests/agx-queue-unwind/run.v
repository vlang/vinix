// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	a := source.index(start) or { return error(start) }; b := source.index_after(end, a) or { return error(end) }; return source[a..b]
}
fn checks() !int {
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	mut source := repo + '/kernel/gpu/agx/gpu/g13.v'; mut measure := false
	for i := 1; i < os.args.len; i++ {
		if os.args[i] == '--measure' { measure = true }
		else { assert os.args[i] == '--source' && i + 1 < os.args.len; i++; source = os.args[i] }
	}
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-queue-unwind-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!; defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-queue-unwind/fixture', scratch, false)!
	os.mkdir_all(scratch + '/klock')!
	os.cp(repo + '/tests/agx-g13-failure/fixture/klock/lock.v', scratch + '/klock/lock.v')!
	code := os.read_file(source)!
	os.write_file(scratch + '/gpu/production.v', 'module gpu\nimport gpu.agx.fw\nimport gpu.agx.mmu\nimport gpu.agx.event\nimport gpu.agx.pgtable\nimport drm.syncobj\n' +
		section(code, 'struct G13QueueIds {', '// Asahi\'s ordinary submit policy')! +
		section(code, 'pub fn free_g13_queue_record(', 'pub fn (mut mgr GpuManager) release_g13_queue_resources(')! +
		section(code, 'fn (mut mgr GpuManager) release_all_g13_queue_resources()', '\n}\n')! + '\n}\n')!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.check_queue_unwind(' + measure.str() + ') }\n')!
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals', '-path', scratch + '|@vlib|@vmodules']
	if !measure { flags << ['-d', 'queue_sanitized', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
	mut p := os.new_process(os.getenv_opt('V') or { 'v' }); mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main.v']
	p.set_args(args); p.run(); p.wait(); code_result := p.code; p.close(); if code_result != 0 { return code_result }
	if target := os.getenv_opt('AGX_UNWIND_C') {
		mut c := os.new_process(os.getenv_opt('V') or { 'v' }); mut args_c := flags.clone(); args_c << ['-o', target, scratch + '/main.v']
		c.set_args(args_c); c.run(); c.wait(); status := c.code; c.close(); if status != 0 { return status }
	}
	if target := os.getenv_opt('AGX_UNWIND_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); return test.code
}
fn main() { code := checks() or { panic(err) }; exit(code) }
