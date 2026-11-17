// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn remove_disposal(source string, start string, end string) string {
	a := source.index(start) or { panic(start) }; b := source.index_after(end, a) or { panic(end) }
	body := source[a..b]; call := 'gpu.free_g13_queue_record(ownership.resources)'
	assert body.count(call) == 1
	return source[..a] + body.replace(call, '') + source[b..]
}
fn main() {
	assert os.args.len == 4, 'usage: counterexamples CLOSE_RUNNER BASELINE_FILE FRESH_OUTPUT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); root := os.abs_path(os.args[3])
	assert !root.starts_with(repo + '/') && !os.exists(root); os.mkdir_all(root)!
	source := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	capture := '\tfor ownership in f.g13_queues {\n\t\tif ownership.resources.has_file_references() { f.lock.release(); return false }\n\t}\n'
	for item in [
		['baseline', os.read_file(os.args[2])!, 'final file ownership removal must free released queue records'],
		['missing-close', remove_disposal(source, 'pub fn (mut f GpuFile) close()', 'fn (mut f GpuFile) get_object_ref('), 'final file ownership removal must free released queue records'],
		['missing-detached', remove_disposal(source, 'fn (mut f GpuFile) reap_detached_g13_queues_locked()', 'fn (mut f GpuFile) reap_orphaned_g13_queues_locked()'), 'final file ownership removal must free released queue records'],
		['missing-orphan', remove_disposal(source, 'fn (mut f GpuFile) reap_orphaned_g13_queues_locked()', '// The registry lock pins'), 'final file ownership removal must free released queue records'],
		['ignore-captures', source.replace(capture, ''), 'queue record metadata must retain captured references'],
		['ignore-manager', source.replace('(f.timestamp_objects.len != 0 || f.g13_queues.len != 0)', 'f.timestamp_objects.len != 0'), 'queue record metadata must wait for backing release'],
		['duplicate-disposal', source.replace('gpu.free_g13_queue_record(ownership.resources)', 'gpu.free_g13_queue_record(ownership.resources)\n\t\tgpu.free_g13_queue_record(ownership.resources)'), 'queue metadata disposal must occur once per final owner'],
	] {
		assert item[1] != source
		dir := root + '/' + item[0]; os.mkdir_all(dir)!; os.write_file(dir + '/file.v', item[1])!
		os.setenv('AGX_CLOSE_TEST_C', dir + '/test.c', true); os.setenv('AGX_CLOSE_TEST_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1])); p.set_args(['--file-source', dir + '/file.v']); p.set_redirect_stdio_merged()
		p.run(); out := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains(item[2]) && !out.contains('error:'), item[0]
		assert os.is_file(dir + '/test.c') && os.is_file(dir + '/test')
		println(item[0] + ': compiled; designated final-owner queue lifetime assertion rejected')
	}
}
