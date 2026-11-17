// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error(start) }
	finish := source.index_after(end, begin + start.len) or { return error(end) }
	return source[begin..finish]
}
fn checks() !int {
	assert os.args.len in [1, 2, 3, 4]
	measure := '--measure' in os.args
	mut source_path := ''
	if '--fake-source' in os.args { index := os.args.index('--fake-source'); assert index + 1 < os.args.len; source_path = os.args[index + 1] }
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-workqueue-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-workqueue-records/fixture', scratch, false)!
	os.mkdir_all(scratch + '/gpu/agx/workqueue')!
	os.cp(repo + '/kernel/gpu/agx/workqueue/workqueue.v', scratch + '/gpu/agx/workqueue/workqueue.v')!
	os.cp_all(repo + '/tests/agx-file-close/fixture/klock', scratch + '/klock', false)!
	os.cp_all(repo + '/tests/agx-file-close/fixture/drm/gem', scratch + '/drm/gem', false)!
	os.symlink(repo + '/kernel/drm/ioctl', scratch + '/drm/ioctl')!
	source := os.read_file(if source_path == '' { repo + '/kernel/gpu/agx/fake/driver.v' } else { source_path })!
	os.write_file(scratch + '/fake/production.v', 'module fake\nimport drm.ioctl\nimport drm.gem\nimport gpu.agx.workqueue\n' +
		section(source, 'fn (mut file FakeG17File) finish_close_locked()', 'pub fn release_handle(')! +
		section(source, 'fn (mut file FakeG17File) finish_pending_job(', 'fn fake_completion_worker(')! +
		section(source, 'fn (mut file FakeG17File) ioctl_queue_destroy(', 'fn wait_staged_syncs(')!)!
	os.write_file(scratch + '/fake/stats_darwin.c.v', os.read_file(repo + '/tests/agx-queue-records/stats_darwin.c.v')!.replace('module file', 'module fake'))!
	if measure { os.write_file(scratch + '/main.v', 'import fake\nfn main() { fake.measure() }\n')! }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-manualfree', '-cc', 'cc', '-enable-globals', '-path', scratch + '|@vlib|@vmodules']
	if !measure { flags << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
	flags << ['-o', scratch + '/test', scratch + '/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' }); build.set_args(flags); build.run(); build.wait()
	if build.code != 0 { return build.code }
	if path := os.getenv_opt('AGX_WORKQUEUE_C') {
		mut cflags := flags.clone(); cflags[cflags.len - 2] = path
		mut c := os.new_process(os.getenv_opt('V') or { 'v' }); c.set_args(cflags); c.run(); c.wait()
		if c.code != 0 { return c.code }
	}
	if path := os.getenv_opt('AGX_WORKQUEUE_BINARY') { os.cp(scratch + '/test', path)! }
	mut test := os.new_process(scratch + '/test'); test.run(); test.wait(); return test.code
}
fn main() { code := checks() or { panic(err) }; exit(code) }
