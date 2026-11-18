// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error(start) }
	finish := source.index_after(end, begin + start.len) or { return error(end) }
	return source[begin..finish]
}
fn run_checks() !int {
	assert os.args.len in [1, 3, 5]
	mut source_root := ''
	mut selected := ''
	for i := 1; i < os.args.len; i += 2 {
		match os.args[i] {
			'--source-root' { source_root = os.args[i + 1] }
			'--case' { selected = os.args[i + 1]; assert selected in ['g13', 'g17', 'fake'] }
			else { panic('usage: run [--source-root DIR] [--case g13|g17|fake]') }
		}
	}
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-worker-${os.getpid()}')
	assert !os.exists(scratch); os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-worker/fixture', scratch, false)!
	manager := os.read_file(if source_root != '' { source_root + '/gpu.v' } else { repo + '/kernel/gpu/agx/gpu/gpu.v' })!
	g17 := os.read_file(if source_root != '' { source_root + '/g17.v' } else { repo + '/kernel/gpu/agx/gpu/g17.v' })!
	fake := os.read_file(if source_root != '' { source_root + '/fake.v' } else { repo + '/kernel/gpu/agx/fake/driver.v' })!
	error_handler := if manager.contains('fn (mut mgr GpuManager) mark_g13_worker_error()') {
		section(manager, 'fn (mut mgr GpuManager) mark_g13_worker_error()', 'pub fn (mut mgr GpuManager) handle_event()')!
	} else {
		''
	}
	production := 'module gpu\nimport sched\nimport gpu.agx.event\n' + error_handler +
		section(manager, 'fn event_worker(', '// Shutdown the GPU')! +
		section(g17, 'const g17_worker_messages_per_role', '\n')! + '\n' +
		section(g17, 'fn g17_event_worker(', '// Apple decodes bits 53:48.')!
	os.write_file(scratch + '/gpu/production.v', production)!
	os.write_file(scratch + '/fake/production.v', 'module fake\nimport sched\nimport syncobj\nimport agxsubmission\n' +
		section(fake, 'fn wait_staged_syncs(', 'fn mapped(')!)!
	compiler := os.getenv_opt('V') or { 'v' }
	flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals',
		'-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined']
	mut build := os.new_process(compiler)
	mut args := flags.clone(); args << ['-o', scratch + '/test', scratch + '/main.v']
	build.set_args(args); build.run(); build.wait()
	if build.code != 0 { return build.code }
	if target := os.getenv_opt('AGX_WORKER_C') {
		mut generated := os.new_process(compiler)
		mut c_args := flags.clone(); c_args << ['-o', target, scratch + '/main.v']
		generated.set_args(c_args); generated.run(); generated.wait()
		if generated.code != 0 { return generated.code }
	}
	if target := os.getenv_opt('AGX_WORKER_BINARY') { os.cp(scratch + '/test', target)! }
	mut test := os.new_process(scratch + '/test')
	if selected != '' { test.set_args([selected]) }
	test.run(); test.wait(); return test.code
}

fn main() {
	code := run_checks() or { panic(err) }
	assert !os.exists(os.join_path(os.temp_dir(), 'vinix-agx-worker-${os.getpid()}')),
		'worker fixture cleanup must finish before process exit'
	exit(code)
}
