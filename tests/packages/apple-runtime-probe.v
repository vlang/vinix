// SPDX-License-Identifier: GPL-2.0-or-later
// A signed fixture launcher: check the package boundary, then exec the actual
// compatibility runtime in the same sandbox without creating another process.
module main

import os
import strconv
import tools.packages.appsdk

#include <unistd.h>
fn C.execv(&char, &&char) int
fn C.getgroups(int, voidptr) int

fn write_private(path string, text string) ! {
	mut file := os.open_file(path, 'w', 0o600)!
	defer { file.close() }
	file.write_string(text)!
}

fn probe() ! {
	mut context := appsdk.load()!
	defer { context.close() }
	assert context.kind == 'apple' && os.getuid() > 0 && os.getuid() == os.geteuid()
	assert C.getgroups(0, unsafe { nil }) == 0
	assert os.getenv('HOME') == context.data_directory
	assert os.getenv('TMPDIR') == context.data_directory + '/tmp'
	assert os.getenv('VINIX_IOS_DOCUMENTS') == context.data_directory + '/Documents'
	assert os.getenv('VINIX_IOS_KEYCHAIN') == context.data_directory + '/Keychains'
	assert os.getenv('VINIX_AUTH_UID') == ''
	assert !os.is_file('/etc/shadow') && !os.is_file('/usr/bin/vinix-package')
	assert !os.is_file('/usr/share/apple-fixtures/hidden.txt')
	assert os.args.len in [1, 2]
	if os.args.len == 2 { assert os.read_file(os.args[1])! == 'literal Apple document\n' }
	path := context.data_directory + '/boundary-counter.txt'
	previous := if os.exists(path) { strconv.atoi(os.read_file(path)!)! } else { 0 }
	write_private(path, (previous + 1).str())!
	println('PACKAGE APPLE CONTEXT uid=' + os.getuid().str() + ' app=' + context.id + ' version=' + context.version + ' runtime=' + context.runtime_version + ' counter=' + (previous + 1).str() + ' PASS')
	flush_stdout()
	runner := context.runtime_directory + '/bin/run-ios'
	program := context.app_directory + '/Example.app/Example'
	arguments := [runner, program]
	mut argv := []&char{}
	for argument in arguments { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	C.execv(runner.str, &argv[0])
	return error('cannot execute the signed Apple runtime: ' + os.last_error().msg())
}

fn main() { probe() or { eprintln(err); exit(89) } }
