// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn body(source string, name string) string { return source.all_after('fn (mut mgr GpuManager) ' + name + '(').all_before('\n}\n') }
fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_SOURCE FRESH_OUTPUT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); root := os.abs_path(os.args[3])
	assert !root.starts_with(repo + '/') && !os.exists(root); os.mkdir_all(root)!
	source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	mut variants := [['baseline', os.read_file(os.args[2])!]]
	for name in ['free_g13_render_buffer_locked', 'free_g13_queue_resources_locked', 'free_g13_render_job_locked', 'free_g13_compute_job_locked'] {
		original := body(source, name)
		for heap in if name.contains('_job_') { ['g13_private', 'g13_gpu_readonly'] } else { ['g13_private'] } {
			variants << [name + '-' + heap, source.replace(original, original.replace('mgr.g13_shared.gc()', 'mgr.' + heap + '.gc()\n\tmgr.g13_shared.gc()'))]
		}
	}
	for item in variants {
		assert item[1] != source
		dir := root + '/' + item[0]; os.mkdir_all(dir)!; os.write_file(dir + '/g13.v', item[1])!
		os.setenv('AGX_TEARDOWN_C', dir + '/test.c', true); os.setenv('AGX_TEARDOWN_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1])); p.set_args(['--source', dir + '/g13.v']); p.set_redirect_stdio_merged(); p.run()
		out := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains('teardown must preserve unrelated pending firmware ranges') && !out.contains('error:'), item[0]
		assert os.is_file(dir + '/test.c') && os.is_file(dir + '/test')
		println(item[0] + ': compiled; premature teardown collection rejected')
	}
}
