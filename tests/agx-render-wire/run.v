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
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-render-wire-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all('${repo}/tests/agx-render-wire/fixture', scratch, false)!
	source := os.read_file('${repo}/kernel/gpu/agx/gpu/g13.v')!
	prepare := section(source, 'pub fn (mut mgr GpuManager) prepare_g13_render_job(',
		'fn (mut mgr GpuManager) publish_g13_render_job_locked(')!
	assert prepare.contains('mgr.hw_config.num_clusters != 1')
	initializer := section(prepare, 'vertex_start := fw.G13MicroseqStartVertex{', 'mut vertex_offset :=')!
	production := 'module gpu\nimport gpu.agx.fw\nimport gpu.agx.hw\n' +
		section(source, 'fn write_g13_start_vertex(', 'fn write_g13_finalize_vertex(')! +
		section(source, 'fn write_g13_start_compute(', 'struct G13EventResources {')! +
		'fn encode(destination voidptr, v13_5 bool, sample Sample) u64 {\n' +
		'job := sample.job; buffer := sample.buffer; mgr := sample.manager; vertex_queue := sample.queue; resources := sample.resources; input := sample.input; vertex_attachments := sample.attachments\n' +
		'abi := if v13_5 { hw.FirmwareAbi.v13_5_partial } else { hw.FirmwareAbi.v12_3 }\n' +
		'vertex_tiling_params_offset := fw.g13_vertex_tiling_params_offset_for(abi) or { panic("tiling offset") }\n' +
		'vertex_job_params_1_offset := fw.g13_vertex_job_params_1_offset_for(abi) or { panic("params offset") }\n' +
		'vertex_unk_pointee_offset := fw.g13_vertex_unk_pointee_offset_for(abi) or { panic("pointee offset") }\n' +
		'vertex_unk_buf_0_offset := fw.g13_vertex_unk_buf_0_offset_for(abi) or { panic("job offset") }\n' + initializer +
		'return write_g13_start_vertex(destination, v13_5, unsafe { &vertex_start }, sample.counter, sample.notifier)\n}\n'
	os.write_file('${scratch}/gpu/production.v', production)!
	os.write_file('${scratch}/main.v', 'import gpu\nfn main() { gpu.run_checks(); gpu.run_compute_finalize_checks(); gpu.run_fragment_repack_checks() }\n')!
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals']
	$if arm64 {
		flags << ['-exclude', '${repo}/kernel/klock/klock_amd64.v', '-exclude', '${repo}/kernel/katomic/katomic_amd64.v']
	} $else $if amd64 {
		flags << ['-exclude', '${repo}/kernel/klock/klock_arm64.v', '-exclude', '${repo}/kernel/katomic/katomic_arm64.v']
	} $else { panic('unsupported host architecture') }
	flags << ['-path', '${scratch}|${repo}/kernel|@vlib|@vmodules',
		'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', '${scratch}/test', '${scratch}/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(flags); build.run(); build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_RENDER_WIRE_TEST_C') {
		assert output.ends_with('.c')
		mut cflags := flags.clone()
		cflags[cflags.len - 2] = output
		mut generated := os.new_process(os.getenv_opt('V') or { 'v' })
		generated.set_args(cflags); generated.run(); generated.wait()
		if generated.code != 0 { exit(generated.code) }
	}
	if output := os.getenv_opt('AGX_RENDER_WIRE_TEST_BINARY') { os.cp('${scratch}/test', output)! }
	mut check := os.new_process('${scratch}/test')
	check.run(); check.wait(); exit(check.code)
}
