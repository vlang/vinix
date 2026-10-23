// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual notification bridge with deterministic transport faults.
module main

import os
import crypto.sha256

fn main() {
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut source := repo + '/build-support/android/nativews/notifications.v'
	mut out := repo + '/build/android-notifications-host'
	for arg in os.args[1..] {
		if arg.starts_with('source=') {
			source = os.abs_path(arg.all_after('source='))
		} else if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else {
			panic('usage: notifications-host [source=NOTIFICATIONS_SOURCE] [out=OUTPUT_DIR]')
		}
	}
	body := os.read_file(source)!
	mut actual := body.replace('module atlframework', 'module main')
	// Keep all production encoding, request, classification, cancel and post code.
	// Redirect transport calls so both synchronous and asynchronous errors are deterministic.
	for name in ['socket', 'connect', 'getsockopt', 'send', 'recv', 'poll', 'close', 'getuid',
		'getenv', '__errno_location'] {
		actual = actual.replace('fn C.' + name + '(', 'fn UNUSED_' + name + '(')
		actual = actual.replace('C.' + name + '(', 'host_' + name + '(')
	}
	// The foreign declarations now refer to unused V symbols; remove those lines.
	actual = actual.split_into_lines().filter(!it.starts_with('fn UNUSED_')).join('\n') + '\n'
	os.mkdir_all(out + '/src')!
	os.write_file(out + '/src/actual_notifications.v', actual)!
	os.cp(repo + '/tests/native-android-ws/notificationshost/harness.v.txt', out + '/src/main.v')!
	os.write_file(out + '/notifications.v.txt', body)!
	os.write_file(out + '/source-sha256.txt', sha256.sum(body.bytes()).hex() + '\n')!
	println('NOTIFICATION-HOST source=' + sha256.sum(body.bytes()).hex())
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	build := os.exec([compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none', '-o',
		out + '/host', out + '/src'])
	print(build.output)
	if build.exit_code != 0 { exit(build.exit_code) }
	result := os.exec([out + '/host'])
	print(result.output)
	exit(result.exit_code)
}
