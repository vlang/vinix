// SPDX-License-Identifier: GPL-2.0-only
// Native producer for the freestanding ARM init and its host policy fixture.
module main

import os

fn command(args []string) ! {
	result := os.exec(args)
	if result.exit_code != 0 { return error('Command failed: ${args[0]}\n${result.output}') }
}

fn generate(tool string, output string, options []string) ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.join_path(os.temp_dir(), 'vinix-init-v-' + os.getpid().str())
	os.mkdir(work)!
	defer { os.rmdir_all(work) or { eprintln(err) } }
	os.mkdir(work + '/initcore')!
	for name in ['core.v', 'native.v'] {
		mut text := os.read_file(root + '/build-support/init-aarch64/initcore/' + name)!
		if '--host' in options {
			for symbol in ['memcpy', 'memset', 'memmove', '_start'] {
				text = text.replace("@[export: '" + symbol + "']", "@[export: 'vinix_init_host_" + symbol + "']")
			}
		}
		os.write_file(work + '/initcore/' + name, text)!
	}
	mut args := ['sh', root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/generate_module.v',
		work + '/initcore', os.abs_path(output), '--arch', 'arm64']
	if tool != 'shell' { args << ['-d', 'init_' + tool] }
	for option in options {
		define := match option { '--host' { 'init_host' } '--wifi-bundle' { 'init_wifi_bundle' } else { 'init_busybox_echo_test' } }
		args << ['-d', define]
	}
	command(args)!
	text := os.read_file(output)!
	os.write_file(output, '#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n'
		+ text.replace('#include <inttypes.h>\n', '')
		+ '\n_Static_assert(sizeof(initcore__SignalAction) == 32 && offsetof(initcore__SignalAction, flags) == 8 && offsetof(initcore__SignalAction, restorer) == 16 && offsetof(initcore__SignalAction, mask) == 24, "raw ARM signal ABI");\n_Static_assert(sizeof(initcore__Delay) == 16 && offsetof(initcore__Delay, nanoseconds) == 8, "raw ARM time ABI");\n')!
}

fn main() {
	if os.args.len < 3 || os.args[1] !in ['shell', 'full', 'desktop']
		|| os.args[3..].any(it !in ['--host', '--wifi-bundle', '--busybox-echo-test']) {
		eprintln('Usage: compile_init.v shell|full|desktop OUTPUT [--host] [--wifi-bundle] [--busybox-echo-test]'); exit(2)
	}
	generate(os.args[1], os.args[2], os.args[3..]) or { eprintln(err); exit(1) }
}
