// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run(program string, args []string, log string) !int {
	mut p := os.new_process(program); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(log, out)!; return code
}
fn main() {
	assert os.args.len == 4, 'counterexamples WORKQUEUE_RUNNER CLOSE_RUNNER FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); output := os.abs_path(os.args[3])
	assert !output.starts_with(repo + '/') && !os.exists(output); os.mkdir_all(output)!
	fake := os.read_file(repo + '/kernel/gpu/agx/fake/driver.v')!
	file := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	for index, pair in [
		['fake', fake.replace('workqueue.free_workqueue(queue)', '/* omitted close disposal */'), 'fake final queue owners must free metadata'],
		['fake', fake.replace('workqueue.free_workqueue(record)', '/* omitted idle disposal */'), 'fake final queue owners must free metadata'],
		['fake', fake.replace('workqueue.free_workqueue(record)', 'workqueue.free_workqueue(queue)'), 'queue.pending_count == 0'],
		['fake', fake.replace('if file.inflight_jobs == 0 {', 'if true {'), 'file.inflight_jobs == 0'],
		['file', file.replace('workqueue.free_workqueue(queue)', '/* omitted close disposal */'), 'native final queue owners must free logical metadata'],
		['file', file.replace('workqueue.free_workqueue(q)', '/* omitted detached disposal */'), 'native final queue owners must free logical metadata'],
		['file', file.replace('workqueue.free_workqueue(record)', 'workqueue.free_workqueue(q)'), 'owned.destroyed && !owned.disposed'],
	] {
		assert pair[1] != if pair[0] == 'fake' { fake } else { file }
		name := output + '/case-' + index.str()
		os.write_file(name + '.v', pair[1])!
		os.setenv(if pair[0] == 'fake' { 'AGX_WORKQUEUE_BINARY' } else { 'AGX_CLOSE_TEST_BINARY' }, name + '.bin', true)
		code := run(os.args[if pair[0] == 'fake' { 1 } else { 2 }], [if pair[0] == 'fake' { '--fake-source' } else { '--file-source' }, name + '.v'], name + '.log')!
		assert code != 0 && os.is_file(name + '.bin') && os.read_file(name + '.log')!.contains(pair[2]), name
		println('Case ' + index.str() + ': compiled; designated logical-queue lifetime assertion rejected')
	}
}
