// SPDX-License-Identifier: GPL-2.0-or-later
// Verify source retention and reject a development build before any staging.
module main

import crypto.sha256
import json2
import os

const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'

struct Check {
	argv      []string
	exit_code int
	output    string
}

fn run(mut checks []Check, argv []string, expected int) !string {
	r := os.exec(argv)
	checks << Check{argv, r.exit_code, r.output}
	if r.exit_code != expected {
		return error('unexpected status for ' + argv[0] + ': ' + r.output)
	}
	return r.output
}

fn check() ! {
	if os.args.len != 2 {
		return error('usage: headless-service-stage-check FRESH_EXTERNAL_OUTPUT')
	}
	repo := os.real_path(os.dir(@FILE) + '/../..')
	root := os.args[1]
	if !os.is_abs_path(root) || root != os.real_path(os.dir(root)) + '/' + os.file_name(root)
		|| os.exists(root) || os.is_link(root) || root == repo || root.starts_with(repo + '/') {
		return error('fresh canonical external output required')
	}
	os.mkdir(root)!
	mut pins := map[string]string{}
	for relative in [
		'tests/native-android-ws/headless-service-stage.v',
		'tests/native-android-ws/headless-service-guest.v',
		'tests/android-webview-browser-probe/collect.v',
		'build-support/android/modulestream/stream.v',
		'build-support/android/modulestream/spawn_abi.h',
		'build-support/tarcore/writer.v',
		'build-support/tarcore/gzip.v',
		'build-support/tarstream/reader.v',
		'build-support/tarstream/filter_abi.h',
		'build-support/tarstream/sparse.v',
	] {
		bytes := os.read_bytes(repo + '/' + relative)!
		pins[relative] = sha256.sum(bytes).hex()
		os.mkdir_all(os.dir(root + '/copy/' + relative))!
		os.write_file_array(root + '/copy/' + relative, bytes)!
	}
	retained := root + '/copy'
	source := retained + '/tests/native-android-ws/headless-service-stage.v'
	module_path := '@vlib|' + retained + '/build-support|' + retained + '/build-support/android'
	mut checks := []Check{}
	run(mut checks, [compiler, '-new-compiler', '-prod', '-path', module_path, '-o',
		root + '/stage-prod', source], 0)!
	before := run(mut checks, [root + '/stage-prod', '--self-test'], 0)!
	expected := 'HEADLESS-STAGE COMPILED-SOURCES ' + pins['tests/native-android-ws/headless-service-stage.v']! +
		' ' + pins['tests/native-android-ws/headless-service-guest.v']! +
		' ' + pins['tests/android-webview-browser-probe/collect.v']!
	if !before.split_into_lines().contains(expected) {
		return error('compiled source hash missing')
	}
	run(mut checks, [compiler, '-new-compiler', '-path', module_path, '-o', root + '/stage-debug',
		source], 0)!
	debug := os.exec([root + '/stage-debug', '--self-test'])
	checks << Check{[root + '/stage-debug', '--self-test'], debug.exit_code, debug.output}
	if debug.exit_code == 0 || !debug.output.contains('requires embedded source bytes; compile with -prod') {
		return error('debug source auto-read was not rejected')
	}
	for relative in ['tests/native-android-ws/headless-service-stage.v',
		'tests/native-android-ws/headless-service-guest.v',
		'tests/android-webview-browser-probe/collect.v'] {
		os.write_file(retained + '/' + relative, '// source changed after build\n')!
	}
	after := run(mut checks, [root + '/stage-prod', '--self-test'], 0)!
	if after != before { return error('retained source changed with checkout mutation') }
	for relative, pin in pins {
		if !relative.starts_with('tests/') && sha256.sum(os.read_bytes(retained + '/' + relative)!).hex() != pin {
			return error('dependency copy changed')
		}
	}
	os.write_file(root + '/checks.json', json2.encode({
		'scope':           json2.Any('Host-only source retention and archive self-tests; no guest execution.')
		'compiler_sha256': json2.Any(sha256.sum(os.read_bytes(compiler)!).hex())
		'inputs_sha256':   json2.decode[json2.Any](json2.encode(pins))!
		'checks':          json2.decode[json2.Any](json2.encode(checks))!
	}, prettify: true) + '\n')!
	println('HEADLESS-STAGE-CHECK PASS prod-retention debug-rejection post-build-source-mutation ' + root + '/checks.json')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
