// SPDX-License-Identifier: GPL-2.0-or-later
import asahiuapi
import crypto.sha256
import os

fn capture(program string, args []string) !string {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	out := process.stdout_slurp()
	err := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program} failed (${code}): ${out}${err}') }
	return out
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	if os.args.len != 5 || os.args[1] != '--asahi-linux' || os.args[3] != '--state-dir' {
		panic('usage: run --asahi-linux PATH --state-dir FRESH_EXTERNAL_DIR')
	}
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	upstream := os.real_path(os.args[2])
	state := os.abs_path(os.args[4])
	if os.exists(state) || os.is_link(state) || state.starts_with(repo + '/') {
		panic('requires fresh external state directory')
	}
	os.mkdir_all(state + '/headers/linux')!
	compiler := os.getenv_opt('V') or { 'v' }
	for name in ['asahi_drm.h', 'drm.h', 'drm_mode.h'] {
		path := 'include/uapi/drm/' + name
		text := capture('git', ['-C', upstream, 'show', 'HEAD:' + path])!
		if os.read_file(upstream + '/' + path)! != text {
			panic('modified upstream header: ${name}')
		}
		os.write_file('${state}/headers/${name}', text)!
	}
	for name in ['bits.h', 'const.h'] {
		os.write_file('${state}/headers/linux/${name}', capture('git', ['-C', upstream, 'show',
			'HEAD:include/uapi/linux/' + name])!)!
	}
	header := os.read_file(state + '/headers/asahi_drm.h')!
	if os.read_file(repo + '/kernel/drm/asahi/types.v')! != asahiuapi.generate(header)! {
		panic('generated Asahi UAPI is stale')
	}
	os.write_file(state + '/upstream.txt', capture('git', ['-C', upstream, 'rev-parse', 'HEAD'])!)!
	os.write_file(state + '/header-sha256.txt', sha256.sum(header.bytes()).hex() + '\n')!
	os.write_file(state + '/oracle.v', asahiuapi.oracle(header)!)!
	common := ['-nocache', '-no-parallel', '-cc', 'cc', '-path', '${repo}/kernel|@vlib|@vmodules']
	mut oracle_args := common.clone()
	oracle_args << ['-cflags',
		'-D__user= -D__BITS_PER_LONG=64 -D__BITS_PER_LONG_LONG=64 -I${state}/headers', '-o',
		state + '/oracle', state + '/oracle.v']
	os.write_file(state + '/oracle-build.log', capture(compiler, oracle_args)!)!
	os.write_file(state + '/oracle.log', capture(state + '/oracle', [])!)!
	mut packet_args := common.clone()
	packet_args << ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
		'-fsanitize=address,undefined', '-o', state + '/packet-test',
		repo + '/tests/agx-packet/test.v']
	os.write_file(state + '/packet-build.log', capture(compiler, packet_args)!)!
	os.write_file(state + '/packet.log', capture(state + '/packet-test', [])!)!
	print(os.read_file(state + '/oracle.log')!)
	print(os.read_file(state + '/packet.log')!)
}
