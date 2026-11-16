// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER ASAHI_LINUX FRESH_EXTERNAL_DIRECTORY'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[3])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	source := os.read_file(repo + '/kernel/gpu/agx/submission/packet.v')!
	expected := {
		'barrier-sentinel': ['main.check_inputs:', 'compute barriers'],
		'compute-opcode': ['main.check_inputs:', 'compute opcode'],
		'queue-usc-base': ['main.expect_compute:', 'compute.usc_base'],
		'sampler-limit': ['main.expect_compute:', 'compute.sampler_max'],
		'clear-pipeline-default': ['main.expect_render:', 'render.flags'],
		'isp-dbias-control': ['main.expect_render:', 'render.iogpu_unk_214'],
		'zls-partial-source': ['main.expect_render:', 'render.depth_buffer_partial'],
		'attachment-exponent': ['main.expect_attachments:', 'attachment exponent'],
		'attachment-engine': ['main.expect_attachments:', 'attachment identity'],
		'timestamp-metadata': ['main.check_inputs:', 'compute timestamp metadata'],
		'timestamp-null-handle': ['main.check_failures:', 'null timestamp handle ignores offset'],
		'usable-failed-prefix': ['main.check_failures:', 'capacity cannot expose or overwrite prefix']
	}
	mut receipts := []string{}
	for name, pair in {
		'barrier-sentinel': ['ioctl.asahi_barrier_none }', 'u32(0xffff) }'],
		'compute-opcode': ['cmd_type: ioctl.asahi_cmd_compute,', 'cmd_type: u32(1),'],
		'queue-usc-base': ['\n\t\tusc_base: usc_base', '\n\t\tusc_base: input.compute.cdm_ctrl_stream_base'],
		'sampler-limit': ['sampler_max: input.compute.sampler_count + u32(1)', 'sampler_max: input.compute.sampler_count'],
		'clear-pipeline-default': ['mut flags := agxrender.no_clear_pipeline_textures', 'mut flags := u64(0)'],
		'isp-dbias-control': ['(value.flags & asahi.render_dbias_is_int)', 'u32(0)'],
		'zls-partial-source': ['depth_buffer_partial: value.depth.base', 'depth_buffer_partial: value.stencil.base'],
		'attachment-exponent': ['order: 1', 'order: 2'],
		'attachment-engine': ['packet_attachments(input.compute_count, input.compute_attachments)', 'packet_attachments(input.compute_count, input.vertex_attachments)'],
		'timestamp-metadata': ['timestamps[2] = input.compute.ts', 'timestamps[2] = asahi.Timestamps{}'],
		'timestamp-null-handle': ['timestamps.start.handle != 0 || timestamps.end.handle != 0', 'timestamps.start.offset != 0 || timestamps.end.offset != 0'],
		'usable-failed-prefix': ['if count >= u32(staged.len) { return -22, 0 }', 'if count >= u32(staged.len) { return -22, count }']
	} {
		assert source.count(pair[0]) == 1, name
		mutant := source.replace(pair[0], pair[1])
		directory := state + '/' + name
		os.mkdir_all(directory)!
		os.write_file(directory + '/packet.v', mutant)!
		os.setenv('AGX_PACKET_INPUT_BINARY', directory + '/test', true)
		os.unsetenv('AGX_PACKET_INPUT_C'); os.unsetenv('AGX_PACKET_INPUT_MODEL')
		mut process := os.new_process(os.abs_path(os.args[1]))
		process.set_args(['--asahi-linux', os.args[2], '--source', directory + '/packet.v'])
		process.set_redirect_stdio(); process.run()
		log := process.stdout_slurp() + process.stderr_slurp(); process.wait()
		os.write_file(directory + '/run.log', log)!
		assert process.code != 0 && log.contains('FAIL: fn ' + expected[name][0])
			&& log.contains(expected[name][1]) && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		process.close()
		receipts << name + ' sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; intended packet assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
