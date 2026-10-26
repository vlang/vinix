// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only build, source-retention and overlay checks; never launches a guest.
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
	if r.exit_code != expected { return error('unexpected command status: ' + r.output) }
	return r.output
}

fn check() ! {
	if os.args.len != 2 { return error('usage: account-ui-stage-check FRESH_EXTERNAL_OUTPUT') }
	repo := os.real_path(@DIR + '/../..')
	root := os.args[1]
	if !os.is_abs_path(root) || root != os.real_path(os.dir(root)) + '/' + os.file_name(root)
		|| os.exists(root) || os.is_link(root) || root == repo || root.starts_with(repo + '/') {
		return error('fresh canonical external output required')
	}
	os.mkdir(root)!
	stage_source := repo + '/tests/native-android-ws/account-ui-stage.v'
	mut paths := ['tests/native-android-ws/account-ui-stage.v']
	for line in os.read_file(stage_source)!.split_into_lines() {
		marker := if line.contains('\u0024embed_file("') {
			'\u0024embed_file("'
		} else if line.contains("\u0024embed_file('") {
			"\u0024embed_file('"
		} else {
			continue
		}
		quote := marker[marker.len - 1..]
		name := line.all_after(marker).all_before(quote)
		absolute := os.real_path(os.dir(stage_source) + '/' + name)
		if !absolute.starts_with(repo + '/') { return error('embedded source outside repository') }
		relative := absolute[repo.len + 1..]
		if relative !in paths { paths << relative }
	}
	if 'tests/native-android-ws/account-ui-guest.v' !in paths
		|| 'tests/android-webview-browser-probe/collect.v' !in paths {
		return error('guest and collector embedded sources absent')
	}
	mut pins := map[string]string{}
	for relative in paths {
		bytes := os.read_bytes(repo + '/' + relative)!
		pins[relative] = sha256.sum(bytes).hex()
		os.mkdir_all(os.dir(root + '/copy/' + relative))!
		os.write_file_array(root + '/copy/' + relative, bytes)!
	}
	source := root + '/copy/tests/native-android-ws/account-ui-stage.v'
	module_path := '@vlib|' + root + '/copy/build-support|' + root + '/copy/build-support/android'
	mut checks := []Check{}
	run(mut checks, [compiler, '-new-compiler', '-prod', '-path', module_path, '-o',
		root + '/stage-prod', source], 0)!
	before := run(mut checks, [root + '/stage-prod', '--self-test'], 0)!
	expected := 'ACCOUNT-UI-STAGE COMPILED-SOURCES ' + pins['tests/native-android-ws/account-ui-stage.v']! +
		' ' + pins['tests/native-android-ws/account-ui-guest.v']! +
		' ' + pins['tests/android-webview-browser-probe/collect.v']!
	if !before.split_into_lines().contains(expected) {
		return error('compiled source identity missing')
	}
	run(mut checks, [compiler, '-new-compiler', '-path', module_path, '-o', root + '/stage-debug',
		source], 0)!
	debug := os.exec([root + '/stage-debug', '--self-test'])
	checks << Check{[root + '/stage-debug', '--self-test'], debug.exit_code, debug.output}
	if debug.exit_code == 0 || !debug.output.contains('requires embedded source bytes; compile with -prod') {
		return error('debug source auto-read was not rejected')
	}
	run(mut checks, [root + '/stage-prod', '--host-check', root + '/host'], 0)!
	for relative in paths {
		os.write_file(root + '/copy/' + relative, '// changed after build\n')!
	}
	after := run(mut checks, [root + '/stage-prod', '--self-test'], 0)!
	if after != before { return error('compiled source changed with checkout mutation') }
	os.write_file(root + '/checks.json', json2.encode({
		'scope':           json2.Any('Host-only source retention, static target build and archive checks; no guest execution.')
		'compiler_sha256': json2.Any(sha256.sum(os.read_bytes(compiler)!).hex())
		'inputs_sha256':   json2.decode[json2.Any](json2.encode(pins))!
		'checks':          json2.decode[json2.Any](json2.encode(checks))!
	}, prettify: true) + '\n')!
	println('ACCOUNT-UI-STAGE-CHECK PASS prod-retention debug-rejection post-build-source-mutation ' + root + '/checks.json')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
