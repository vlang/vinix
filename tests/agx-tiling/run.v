// SPDX-License-Identifier: GPL-2.0-or-later
import os
import g13contract

fn section(source string, start string, end string) !string {
	return g13contract.section(source, start, end, 'native tiling fixture')
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut options := map[string]string{}
	mut i := 1
	for i < os.args.len {
		assert os.args[i] in ['--asahi-linux', '--gpu-source'] && i + 1 < os.args.len
		options[os.args[i]] = os.args[i + 1]; i += 2
	}
	assert '--asahi-linux' in options
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	base := options['--asahi-linux'] + '/drivers/gpu/drm/asahi'
	_ = g13contract.check_queue_recovery_reference(options['--asahi-linux'], repo)!
	render := os.read_file(base + '/queue/render.rs')!
	model := g13contract.tiling_reference_v(render, os.read_file(base + '/util.rs')!)!
	source := os.read_file(options['--gpu-source'] or { repo + '/kernel/gpu/agx/gpu/g13.v' })!
	production := 'module gpu\nimport gpu.agx.fw\n' +
		section(source, 'struct G13TileInfo {', 'pub struct G13ComputeJobResources {')! +
		section(source, 'fn g13_div_round_up(', 'fn (mut mgr GpuManager) reserve_g13_tvb_slot(')! + model
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-tiling-${os.getpid()}')
	os.mkdir_all(scratch + '/gpu')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.write_file(scratch + '/gpu/production.v', production)!
	os.cp(repo + '/tests/agx-tiling/check.v', scratch + '/gpu/check.v')!
	os.write_file(scratch + '/main.v', 'import gpu\nfn main() { gpu.run_checks() }\n')!
	if output := os.getenv_opt('AGX_TILING_MODEL') { os.write_file(output, model)! }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals']
	$if arm64 { flags << ['-exclude', repo + '/kernel/klock/klock_amd64.v', '-exclude', repo + '/kernel/katomic/katomic_amd64.v'] }
	$else $if amd64 { flags << ['-exclude', repo + '/kernel/klock/klock_arm64.v', '-exclude', repo + '/kernel/katomic/katomic_arm64.v'] }
	$else { panic('unsupported host architecture') }
	flags << ['-path', '${scratch}|${repo}/kernel|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch + '/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' }); build.set_args(flags); build.run(); build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_TILING_C') {
		assert output.ends_with('.c'); flags[flags.len - 2] = output
		mut c := os.new_process(os.getenv_opt('V') or { 'v' }); c.set_args(flags); c.run(); c.wait()
		if c.code != 0 { exit(c.code) }
	}
	if output := os.getenv_opt('AGX_TILING_BINARY') { os.cp(scratch + '/test', output)! }
	mut check := os.new_process(scratch + '/test'); check.run(); check.wait(); exit(check.code)
}
