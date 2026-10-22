// SPDX-License-Identifier: GPL-2.0-or-later
// v run desktop/tools/test-session-runtime.v
module main

import crypto.sha256
import os

fn invoke(program string, args []string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.run()
	child.wait()
	if child.code != 0 { return error('${program} failed (${child.code})') }
}

fn main() {
	check() or { eprintln(err) exit(1) }
}

fn check() ! {
	root := os.real_path('.')
	work := os.join_path(os.temp_dir(), 'vinix-session-runtime-${os.getpid()}')
	os.mkdir_all(work)!
	defer {
		if os.getenv('VINIX_SESSION_RUNTIME_KEEP') != '1' { os.rmdir_all(work) or {} }
	}
	println('Session runtime check artifacts: ${work}')
	compiler := os.real_path(os.find_abs_path_of_executable(os.getenv_opt('V') or { @VEXE })!)
	println('Compiler sha256: ' + sha256.sum(os.read_bytes(compiler)!).hex())
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VEXE', compiler, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', compiler, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	for index, path in ['desktop/sessionruntime/runtime_test.v',
		'desktop/sessionruntime/tests/integration_test.v', 'desktop/windowfb/protocol_test.v'] {
		output := '${work}/test-${index}'
		invoke(compiler, ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none',
			'-manualfree', '-enable-globals', '-d', 'no_segfault_handler',
			'-path', '@vlib|${root}|@vmodules',
			'-o', output + '.c', '${root}/${path}'])!
		mut source := os.read_file(output + '.c')!
		source = source.replace('\t#endif#define V_MANUAL_STDLIB_HEADERS 1',
			'\t#endif\n};\n#endif\n#undef V_CRT_STDIO_LINKAGE\n#undef V_CRT_LINKAGE\n#undef V_CRT_CALL\n#define V_MANUAL_STDLIB_HEADERS 1')
		$if macos { source = source.replace('ptrdiff_t offset);', 'int64_t offset);') }
		os.write_file(output + '.c', source)!
		if index == 0 {
			start := source.index('bool sessionruntime__owned_directory(string path, u32 uid, bool private) {') or {
				return error('generated C is missing the runtime ownership function')
			}
			function := source[start..].all_before('\n}\n') + '\n}\n'
			os.write_file(work + '/owned-directory.c.txt', function)!
		}
		invoke('clang', ['-w', '-O0', output + '.c',
			'${os.dir(compiler)}/vlib/os/execute_capture_nix.c', '-lpthread', '-lm',
			'-o', output])!
		invoke(output, [])!
		println('PASS ${path}')
		println('  source sha256: ' + sha256.sum(os.read_bytes('${root}/${path}')!).hex())
		println('  generated C sha256: ' + sha256.sum(os.read_bytes(output + '.c')!).hex())
		println('  executable sha256: ' + sha256.sum(os.read_bytes(output)!).hex())
	}
}
