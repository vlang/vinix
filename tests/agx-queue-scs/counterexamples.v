// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 3, 'usage: counterexamples CLOSE_RUNNER FRESH_EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	for index, spec in [
		['modern.v', 'pub fn (mut f GpuFile) ioctl_modern_queue_create(data &asahi.QueueCreate) int {',
			'pub fn (mut f GpuFile) ioctl_modern_queue_create(data &asahi.QueueCreate) int {\n\tif data.render_scs_layout != [u64(0), 0]! { return -22 }',
			'--modern-source', 'queue construction must precede render SCS rejection'],
		['file.v', '\t\tworkqueue.free_workqueue(logical)\n', '', '--file-source',
			'unpublished logical queue metadata must be freed'],
		['file.v',
			'\t\t\tf.g13_queues << G13QueueOwnership{ queue_id: id, vm_id: request.vm_id, resources: g13_resources }\n',
			'', '--file-source', 'failed rollback must retain an orphan owner'],
	] {
		folder := state + '/case-' + index.str()
		os.mkdir_all(folder)!
		source := os.read_file(repo + '/kernel/gpu/agx/file/' + spec[0])!
		assert source.count(spec[1]) == 1
		os.write_file(folder + '/mutated.v', source.replace(spec[1], spec[2]))!
		os.setenv('AGX_CLOSE_TEST_BINARY', folder + '/test', true)
		os.setenv('AGX_CLOSE_TEST_C', folder + '/test.c', true)
		os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args([spec[3], folder + '/mutated.v'])
		p.set_redirect_stdio_merged()
		p.run()
		output := p.stdout_slurp()
		p.wait()
		code := p.code
		p.close()
		os.write_file(folder + '/output.log', output)!
		assert code != 0 && os.is_file(folder + '/test')
		assert output.contains('FAIL: fn file.run_modern_scs_checks') && output.contains(spec[4]), folder
		println('case-${index}: compiled mutation rejected by designated SCS precedence, logical-free or orphan-owner assertion')
	}
}
