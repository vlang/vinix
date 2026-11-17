// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_G13 FRESH_OUTPUT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); root := os.abs_path(os.args[3])
	assert !root.starts_with(repo + '/') && !os.exists(root); os.mkdir_all(root)!
	source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	for item in [
		['baseline', os.read_file(os.args[2])!, 'failed unpublished construction must free its unreturned queue record'],
		['missing-free', source.replace('unsafe { free(resources) }', ''), 'failed unpublished construction must free its unreturned queue record'],
		['quarantine-free', source.replace('resources.quarantined = true\n\t\t\t\tmgr.g13_queues << resources', 'resources.quarantined = true\n\t\t\t\tmgr.g13_queues << resources\n\t\t\t\tunsafe { free(resources) }'), 'quarantined metadata must remain live for manager/file adoption'],
		['returned-free', source.replace('complete = true\n\treturn resources', 'complete = true\n\tunsafe { free(resources) }\n\treturn resources'), 'successful returned metadata must remain live'],
		['double-free', source.replace('unsafe { free(resources) }', 'unsafe { free(resources); free(resources) }'), 'AddressSanitizer: attempting double-free'],
	] {
		assert item[1] != source
		dir := root + '/' + item[0]; os.mkdir_all(dir)!; os.write_file(dir + '/source.v', item[1])!
		os.setenv('AGX_UNWIND_C', dir + '/test.c', true); os.setenv('AGX_UNWIND_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1])); p.set_args(['--source', dir + '/source.v']); p.set_redirect_stdio_merged()
		p.run(); out := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains(item[2]) && !out.contains('error:'), item[0]
		assert os.is_file(dir + '/test.c') && os.is_file(dir + '/test')
		println(item[0] + ': compiled; designated failure-only queue lifetime assertion rejected')
	}
}
