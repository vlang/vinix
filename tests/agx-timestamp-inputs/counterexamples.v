// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER ASAHI_LINUX FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[3]); assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	mut receipts := []string{}
	for name, spec in {
		'vertex-end-missing': ['|| vertex_user_timestamps[1] != 0', '|| false', 'vertex timestamp selection/size'],
		'fragment-start-missing': ['|| fragment_user_timestamps[0] != 0', '|| false', 'fragment timestamp selection/size'],
		'compute-end-missing': ['|| user_timestamps[1] != 0', '|| false', 'compute timestamp selection/size'],
		'legacy-compute-dropped': ['compute_timestamps := input.has_result ||', 'compute_timestamps := false ||', 'compute timestamp selection/size'],
		'truncated-pair': ['C.memcpy(destination, &pair[0], sizeof(u64) * 2)', 'C.memcpy(destination, &pair[0], u64(8))', 'resolved timestamp pair/neighbor bytes'],
		'vertex-offset': ['u64(job.vertex.cpu_address()) + vertex_user_ts_offset)', 'u64(job.vertex.cpu_address()) + vertex_user_ts_offset + 8)', 'resolved timestamp pair/neighbor bytes'],
		'compute-offset': ['u64(job.command.cpu_address()) + compute_user_ts_offset)', 'u64(job.command.cpu_address()) + compute_user_ts_offset + 8)', 'resolved timestamp pair/neighbor bytes'],
		'fragment-extent': ['u64(0x2e0)', 'u64(0x2e8)', 'fragment timestamp selection/size']
	} {
		assert source.count(spec[0]) == 1, name
		mutant := source.replace(spec[0], spec[1])
		directory := state + '/' + name; os.mkdir_all(directory)!
		os.write_file(directory + '/g13.v', mutant)!
		os.setenv('AGX_TIMESTAMP_INPUT_BINARY', directory + '/test', true)
		os.unsetenv('AGX_TIMESTAMP_INPUT_C'); os.unsetenv('AGX_TIMESTAMP_INPUT_MODEL')
		mut process := os.new_process(os.abs_path(os.args[1]))
		process.set_args(['--asahi-linux', os.args[2], '--native-source', directory + '/g13.v'])
		process.set_redirect_stdio(); process.run()
		log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
		os.write_file(directory + '/run.log', log)!
		assert process.code != 0 && log.contains('FAIL: fn gpu.run_checks:') && log.contains(spec[2]) && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		process.close()
		receipts << name + ' sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; designated timestamp input assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
