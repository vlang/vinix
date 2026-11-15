// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing ${start}') }
	finish := source.index_after(end, begin + start.len) or { return error('missing ${end}') }
	return source[begin..finish]
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-async-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-async/fixture', scratch, false)!
	os.mkdir_all('${scratch}/aarch64')!
	os.cp_all('${repo}/tests/agx-g13-failure/fixture/klock', '${scratch}/klock', false)!
	os.cp_all('${repo}/tests/agx-g13-failure/fixture/aarch64/timer', '${scratch}/aarch64/timer', false)!
	for path in ['drm/ioctl', 'drm/syncobj', 'gpu/agx/command', 'gpu/agx/compute', 'gpu/agx/render',
		'gpu/agx/submission'] {
		os.mkdir_all(os.dir('${scratch}/${path}'))!
		os.symlink('${repo}/kernel/${path}', '${scratch}/${path}')!
	}
	source := os.read_file('${repo}/kernel/gpu/agx/file/file.v')!
	production := 'module file\nimport drm.gem\nimport drm.ioctl\nimport drm.syncobj\nimport gpu.agx.gpu\nimport gpu.agx.mmu\nimport gpu.agx.submission as agxsubmission\nimport katomic\nimport memory\nimport aarch64.timer\n' +
		'const max_g13_submission_commands = agxsubmission.max_commands\nconst max_submission_syncs = agxsubmission.max_syncs\n' +
		section(source, '@[heap]\nstruct G13SubmitCompletion {', 'pub struct GpuFile {')! +
		section(source, 'fn discard_g13_completion(', 'fn dispatch(')!
	os.write_file('${scratch}/gpu/agx/file/production.v', production)!
	os.cp('${repo}/kernel/gpu/agx/file/pending.v', '${scratch}/gpu/agx/file/pending.v')!
	gpu := os.read_file('${repo}/kernel/gpu/agx/gpu/gpu.v')!
	g13 := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v')!
	errors := os.read_file('${repo}/kernel/gpu/agx/gpu/g13_recovery.v')!
	os.write_file('${scratch}/gpu/agx/gpu/production.v', 'module gpu\n' +
		section(gpu, 'pub fn (mut mgr GpuManager) queue_g13_submission(', '__global (')! +
		section(g13, 'pub fn (mut mgr GpuManager) g13_queue_dispatch_blocked(', '// Caller holds the manager lock during shutdown.')! +
		section(errors, 'pub struct G13JobError {', 'fn g13_error_at_stamp(')!)!
	os.write_file('${scratch}/main.v', 'import gpu.agx.file\nfn main() { file.run_checks() }\n')!
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags',
		'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v'])
	build.run()
	build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_ASYNC_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run()
	check.wait()
	exit(check.code)
}
