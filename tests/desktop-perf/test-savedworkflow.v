// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import json2
import os
import savedworkflow

fn qualify(work string) ! {
	os.mkdir(work)!
	root := work + '/root'
	for path in ['tests/desktop-perf/perfrunner', 'tests/desktop-perf/perfconsole', 'tests/desktop-perf/perfreport', 'tools/qmpclient', 'tools/sourcecommand'] {
		os.mkdir_all(root + '/' + path)!
		os.write_file(root + '/' + path + '/fixture.v', 'independent source input')!
	}
	os.cp(os.executable(), root + '/tests/desktop-perf/run-saved')!
	os.chmod(root + '/tests/desktop-perf/run-saved', 0o755)!
	os.write_file(root + '/tests/desktop-perf/run-saved.v', 'independent harness input')!
	kernel := root + '/kernel-input'
	os.write_file(kernel, 'independent kernel')!
	for profile in ['final', 'v4', 'v5', 'v6'] {
		version := if profile == 'final' { 'v3' } else { profile }
		suffix := if profile == 'final' { 'v3' } else { profile + '-final' }
		desktop := root + if profile == 'final' { '/third_party/useralloc-pipe/build/vinix-desktop' } else { '/build/useralloc-pipe/static-desktop-' + version + '/vinix-desktop' }
		os.mkdir_all(os.dir(desktop))!
		os.write_file(desktop, 'desktop ' + profile)!
		libs := root + '/third_party/useralloc-libc/build/useralloc/optimized-arm126-' + suffix
		for path in ['lib/ld-musl-aarch64.so.1', 'usr/lib/libc.a'] { os.mkdir_all(os.dir(libs + '/' + path))!; os.write_file(libs + '/' + path, profile + ' ' + path)! }
		setup := root + '/build/useralloc-pipe/perf-' + profile + '-preparation'
		os.mkdir_all(setup)!
		for name in ['initramfs-desktop-frozen.tar', 'measure.c', 'perf-init.sh'] { os.write_file(setup + '/' + name, profile + ' ' + name)! }
		for status in [0, 7] {
			state := work + '/' + profile + '-' + status.str()
			os.setenv('VINIX_SAVED_DRIVER_RETURN', status.str(), true)
			assert savedworkflow.driver_profile(root, setup, state, 'ops,churn,cache,idle,apps,drag', kernel, profile)! == status
			actual := json2.decode[json2.Any](os.read_file(state + '/run.json')!)!.as_map()
			assert actual['runner_exit_code']!.int() == status
			command := actual['command']!.as_array().map(it.str())
			assert command[1] == profile && command[2] == setup && command[3] == 'final=' + desktop
			assert command.contains('--rounds') && command.contains('1800')
			observed := json2.decode[json2.Any](os.read_file(state + '/child.json')!)!.as_map()
			assert observed['argv']!.as_array().map(it.str()) == command[1..]
			assert observed['environment']! == actual['environment']!
			assert actual['serial_sha256']!.str() == hosttest.text_sha('independent serial ' + profile + '\n')
			assert os.read_file(state + '/serial.log')! == 'independent serial ' + profile + '\n'
			assert os.is_file(state + '/runner.pid')
		}
	}
	os.write_file(work + '/passed', 'PASS\n')!
	println('SAVED DESKTOP DRIVERS / all four profiles / actual native children / original arguments, library roots and environment / exit 0 and 7 / PID, streamed log and serial SHA receipt: PASS')
	flush_stdout()
}

fn child() ! {
	position := os.args.index('--json')
	if position < 0 || position + 1 >= os.args.len { return error('child result argument missing') }
	state := os.dir(os.args[position + 1])
	mut environment := map[string]string{}
	for key in ['VINIX_KERNEL_DIR', 'VINIX_AARCH64_SYSROOT', 'VINIX_QEMU_SMP', 'USE_TCG'] { environment[key] = os.getenv(key) }
	hosttest.write_json(state + '/child.json', {'argv': json2.Any(os.args[1..].map(json2.Any(it))), 'environment': json2.Any(hosttest.string_map(environment))})!
	os.write_file(state + '/child-serial.log', 'independent serial ' + os.args[1] + '\n')!
	println('==> Serial log: ' + state + '/child-serial.log')
	flush_stdout()
}

fn main() {
	if os.base(os.executable()) == 'run-saved' { child() or { eprintln(err); exit(1) }; exit(os.getenv('VINIX_SAVED_DRIVER_RETURN').int()) }
	if os.args.len != 2 { eprintln('usage: test-savedworkflow NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
