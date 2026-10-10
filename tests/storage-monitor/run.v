// SPDX-License-Identifier: GPL-2.0-or-later
// Production V CLI with only its monitor syscall boundary replaced on the host.
module main

import os

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('Command failed: ${args[0]}\n${result.output}') }
	return result.output
}

fn qualify(root string, work string) ! {
	os.mkdir_all(work + '/volumecli')!
	for file in os.ls(root + '/tools/volumes/volumecli')! {
		if !file.ends_with('.v') || file.ends_with('_test.v') { continue
		 }
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'monitor.v' {
			source =
				source.replace('fn C.sleep(u32) u32\n', '').replace('fn C.fflush(voidptr) i32\n', '')
			for name in ['open', 'close', 'ioctl', 'sleep', 'printf'] {
				source = source.replace('C.${name}(', 'monitor_mock_${name}(')
			}
			source = source.replace('C.fflush(', 'monitor_mock_flush(')
		}
		os.write_file(work + '/volumecli/' + file, source)!
	}
	os.cp(root + '/tests/storage-monitor/model.v', work + '/volumecli/model.v')!
	os.cp(root + '/tests/storage-monitor/io_test.v', work + '/volumecli/io_test.v')!
	for file in ['monitor_test.v', 'health_test.v'] {
		mut source := os.read_file(root + '/tools/volumes/volumecli/' + file)!
		if file == 'monitor_test.v' {
			start := source.index('fn test_monitor_') or { return error('Missing monitor tests') }
			source = 'module volumecli\n' + source[start..]
		}
		os.write_file(work + '/volumecli/' + file, source)!
	}
	// Fixture helpers are also needed by the I/O entry's separate module graph.
	helper := os.read_file(root + '/tools/volumes/volumecli/monitor_test.v')!
	os.write_file(work + '/volumecli/status_helper.v', helper.all_before('fn test_monitor_'))!
	v := os.getenv_opt('V') or { @VEXE }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
	for file in ['monitor_test', 'io_test', 'health_test'] {
		binary := work + '/' + file
		command([v, '-nocache', '-gc', 'none', '-no-closures', '-target-libc-headers',
			'-enable-globals', '-cc', 'clang', '-d', 'volume_library', '-cflags',
			'-I' + root +
				'/tools/volumes/volumecli -fsanitize=address,undefined', '-ldflags',
			'-fsanitize=address,undefined', '-o', binary, work + '/volumecli/' + file + '.v'])!
		output := command([binary])!
		if file == 'io_test' {
			for marker in ['sample=200 disk=91 health=healthy', 'warnings=0x80', 'health=unavailable',
				'health=offline', 'health=query-failed', 'new_errors=1', 'counters_reset=1'] {
				if !output.contains(marker) { return error('Missing monitor output: ${marker}') }
			}
		}
		print(output)
		println('PASS: ${file} under ASan/UBSan')
	}
	for arch in ['arm64', 'amd64'] {
		source := work + '/monitor-' + arch + '.c'
		command(['sh', root + '/build-support/run-v-tool.sh',
			root + '/tests/linuxkpi/generate_module.v', root + '/tools/volumes/volumecli', source,
			'--arch', arch])!
		generated := os.read_file(source)!
		for symbol in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index('] {
			if generated.contains(symbol) {
				return error('Unexpected allocation/runtime dependency ${symbol} in ${source}')
			}
		}
		println('PASS: ${arch} production CLI has no heap allocation or V runtime dependency')
	}
}

fn main() {
	if os.args.len != 3 || os.args[1] != '--work' || os.exists(os.args[2]) {
		eprintln('Usage: run.v --work NEW_DIRECTORY')
		exit(2)
	}
	os.mkdir(os.args[2]) or {
		eprintln(err)
		exit(1)
	}
	root := os.dir(os.dir(os.dir(@FILE)))
	qualify(root, os.abs_path(os.args[2])) or {
		eprintln(err)
		exit(1)
	}
}
