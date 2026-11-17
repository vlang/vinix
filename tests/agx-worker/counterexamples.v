// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_ROOT FRESH_DIRECTORY'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	root := os.abs_path(os.args[3]); assert !root.starts_with(repo + '/') && !os.exists(root)
	os.mkdir_all(root)!
	current := {
		'gpu': os.read_file(repo + '/kernel/gpu/agx/gpu/gpu.v')!
		'g17': os.read_file(repo + '/kernel/gpu/agx/gpu/g17.v')!
		'fake': os.read_file(repo + '/kernel/gpu/agx/fake/driver.v')!
	}
	variants := [
		['old-g13', 'gpu', os.read_file(os.args[2] + '/gpu.v')!, 'g13', 'active AGX work entered a non-returning scheduler path'],
		['old-g17', 'g17', os.read_file(os.args[2] + '/g17.v')!, 'g17', 'active AGX work entered a non-returning scheduler path'],
		['old-fake', 'fake', os.read_file(os.args[2] + '/fake.v')!, 'fake', 'active AGX work entered a non-returning scheduler path'],
		['missing-g13', 'gpu', current['gpu'].replace('sched.reschedule()', '// omitted reschedule'), 'g13', 'G13 worker failed to make progress'],
		['missing-g17', 'g17', current['g17'].replace('sched.reschedule()', '// omitted reschedule'), 'g17', 'G17 worker failed to make progress'],
		['missing-fake', 'fake', current['fake'].replace('sched.reschedule()', '// omitted reschedule'), 'fake', 'fence wait failed to make progress'],
		['missing-shutdown', 'gpu', current['gpu'].replace('mgr.shutdown()', '// omitted shutdown'), 'g13', 'G13 failure must finish shutdown'],
		['ignored-error', 'fake', current['fake'].replace('if syncobj.get_error(fence) != 0', 'if false'), 'fake', 'dependency error must survive returning reschedule'],
	]
	for item in variants {
		assert current[item[1]] != item[2]
		dir := root + '/' + item[0]; os.mkdir_all(dir)!
		for name, code in current { os.write_file(dir + '/' + name + '.v', if name == item[1] { item[2] } else { code })! }
		os.setenv('AGX_WORKER_C', dir + '/test.c', true); os.setenv('AGX_WORKER_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args(['--source-root', dir, '--case', item[3]]); p.set_redirect_stdio_merged(); p.run()
		out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
		os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains(item[4]) && !out.contains('error:'), item[0] + ': ' + out
		assert os.is_file(dir + '/test') && os.is_file(dir + '/test.c')
		println(item[0] + ': compiled; designated worker liveness/cleanup assertion rejected')
	}
}
