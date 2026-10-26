// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

struct Reply {
	code int
	text string
}

struct Evidence {
	format int = 1
	scope string = 'CLI interface discovery, no runtime/ABI/publisher qualification'
	cli_sha256 string
	response string
	refusals int
	private_tree_unchanged bool
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn invoke(cli string, arguments []string, work string) !Reply {
	mut child := os.new_process(cli)
	defer { child.close() }
	child.set_args(arguments)
	child.set_work_folder(work)
	mut environment := os.environ()
	environment['HOME'] = work + '/home'
	environment['XDG_CONFIG_HOME'] = work + '/missing-config'
	environment['XDG_DATA_HOME'] = work + '/missing-data'
	environment['TMPDIR'] = work + '/missing-tmp'
	child.set_environment(environment)
	child.set_redirect_stdio_merged()
	child.run()
	text := child.stdout_slurp()
	child.wait()
	return Reply{ code: child.code, text: text }
}

fn check() ! {
	if os.args.len != 3 { return error('usage: capabilities-check PACKAGE_EXECUTABLE NEW_WORK_DIRECTORY') }
	cli := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	if !os.is_file(cli) || os.exists(work) || os.is_link(work) { return error('provide a CLI executable and a new work directory') }
	os.mkdir(work, mode: 0o700)!
	os.mkdir(work + '/home', mode: 0o700)!
	os.write_file(work + '/sentinel', 'preserve ordinary user data\n')!
	mut before := os.ls(work)!
	before.sort()
	plain := invoke(cli, ['capabilities'], work)!
	defer { unsafe { plain.text.free() } }
	json := invoke(cli, ['--json', 'capabilities'], work)!
	defer { unsafe { json.text.free() } }
	require(plain.code == 0 && json.code == 0 && plain.text == json.text, 'normal and --json discovery must agree without config')!
	mut decoded := pkgprotocol.decode_capabilities(json.text)!
	defer { decoded.close() }
	require(decoded.package_formats == [1] && decoded.application_sdks == [1]
		&& decoded.native_window_protocols == [1, 2] && decoded.deployment_formats == [1, 2], 'unexpected advertised interfaces')!
	require(decoded.supports_package(1, 1, 2) && !decoded.supports_package(1, 1, 3)
		&& !decoded.supports_package(1, 2, 0), 'exact compatibility check failed')!
	mut refusals := 0
	for arguments in [['capabilities', 'extra'], ['--offline', 'capabilities'], ['--progress', 'capabilities'],
		['--root', '/', 'capabilities'], ['--root', work + '/missing-installation', 'capabilities'],
		['--json', 'capabilities', '--help'], ['capabilities', '--json'], ['capabilities;touch sentinel']] {
		reply := invoke(cli, arguments, work)!
		defer { unsafe { reply.text.free() } }
		require(reply.code != 0, 'unexpectedly accepted operands/options or shell-like command')!
		refusals++
	}
	mut after := os.ls(work)!
	after.sort()
	require(after == before && os.ls(work + '/home')!.len == 0
		&& os.read_file(work + '/sentinel')! == 'preserve ordinary user data\n', 'capability discovery changed the private filesystem')!
	bytes := os.read_file(cli)!
	defer { unsafe { bytes.free() } }
	os.write_file(work + '/evidence.json', json2.encode(Evidence{ cli_sha256: sha256.hexhash(bytes),
		response: json.text.trim_space(), refusals: refusals, private_tree_unchanged: true }) + '\n')!
	println('PACKAGE CAPABILITIES real CLI no-config exact-version discovery, eight argument refusals and unchanged private state PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
