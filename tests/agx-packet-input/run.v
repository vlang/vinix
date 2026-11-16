// SPDX-License-Identifier: GPL-2.0-or-later
import os
import g13contract

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	process.set_args(args); process.run(); process.wait()
	if process.code != 0 { exit(process.code) }
	process.close()
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut options := map[string]string{}
	for i := 1; i < os.args.len; i += 2 {
		assert i + 1 < os.args.len && os.args[i] in ['--asahi-linux', '--source']
		options[os.args[i]] = os.args[i + 1]
	}
	assert '--asahi-linux' in options
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	reference := options['--asahi-linux'] + '/drivers/gpu/drm/asahi/queue/'
	g13contract.packet_input_auxiliary_reference(os.read_file(reference + 'mod.rs')!, os.read_file(reference + 'common.rs')!)!
	model := g13contract.packet_input_reference_v(os.read_file(reference + 'compute.rs')!,
		os.read_file(reference + 'render.rs')!, os.read_file(repo + '/kernel/gpu/agx/compute/compute.v')!,
		os.read_file(repo + '/kernel/gpu/agx/render/render.v')!)!
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-packet-input-${os.getpid()}')
	os.mkdir_all(scratch + '/gpu/agx/submission')!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	for path in ['drm/asahi', 'drm/ioctl', 'gpu/agx/packet', 'gpu/agx/command', 'gpu/agx/compute', 'gpu/agx/render'] {
		os.mkdir_all(os.dir(scratch + '/' + path))!
		os.symlink(repo + '/kernel/' + path, scratch + '/' + path)!
	}
	os.cp_all(repo + '/tests/agx-async/fixture/usercopy', scratch + '/usercopy', false)!
	submission := os.read_file(repo + '/kernel/gpu/agx/submission/submission.v')!
	start := submission.index('pub struct Command {') or { panic('missing Command') }
	end := submission.index_after('\n}', start) or { panic('unterminated Command') }
	os.write_file(scratch + '/gpu/agx/submission/types.v', 'module submission\nimport drm.ioctl\nimport gpu.agx.compute as agxcompute\nimport gpu.agx.render as agxrender\npub const max_commands = u32(64)\n' + submission[start..end + 2] + '\n')!
	os.cp(options['--source'] or { repo + '/kernel/gpu/agx/submission/packet.v' }, scratch + '/gpu/agx/submission/packet.v')!
	os.cp(repo + '/tests/agx-packet-input/test.v', scratch + '/main.v')!
	os.write_file(scratch + '/reference.v', model)!
	if output := os.getenv_opt('AGX_PACKET_INPUT_MODEL') { os.write_file(output, model)! }
	mut flags := ['-nocache', '-no-parallel', '-gc', 'none', '-cc', 'cc', '-enable-globals',
		'-path', scratch + '|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch]
	compiler := os.getenv_opt('V') or { 'v' }
	run(compiler, flags)!
	if output := os.getenv_opt('AGX_PACKET_INPUT_BINARY') { os.cp(scratch + '/test', output)! }
	if output := os.getenv_opt('AGX_PACKET_INPUT_C') {
		assert output.ends_with('.c')
		flags[flags.len - 2] = output
		run(compiler, flags)!
	}
	run(scratch + '/test', [])!
}
