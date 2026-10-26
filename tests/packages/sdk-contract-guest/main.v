// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.usleep(u32) int

fn sdk_require(condition bool, reason string) ! {
	if !condition { return error(reason) }
}

// Every child is waited for and closed, and its complete merged output reaches
// the serial log before either its result or a refusal is checked.
fn sdk_run(path string, arguments []string) (int, string) {
	mut child := os.new_process(path)
	child.set_args(arguments); child.set_redirect_stdio_merged(); child.run()
	if child.stdio_fd[0] >= 0 { C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1 }
	output := child.stdout_slurp(); child.wait()
	code := child.code; child.close()
	print(output)
	return code, output
}

fn sdk_tree(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + relative)! {
		path := relative + '/' + name
		if os.is_link(root + path) { entries[path] = 'symlink:' + os.readlink(root + path)! }
		else if os.is_dir(root + path) { entries[path] = 'directory'; sdk_tree(root, path, mut entries)! }
		else { entries[path] = sha256.hexhash(os.read_file(root + path)!) }
	}
}

fn sdk_unchanged(root string, before map[string]string) ! {
	mut after := map[string]string{}
	sdk_tree(root, '', mut after)!
	sdk_require(after == before, 'operand check changed a fixture tree')!
}

struct SdkEmptyState {
	format int
	generation u64
	previous u64
	architecture string
	requested []string
	packages []string
}

fn sdk_arity() ! {
	fixtures := '/tmp/sdk-contract-arity'
	os.mkdir(fixtures, mode: 0o700)!
	os.write_file(fixtures + '/sentinel', 'preserve unrelated data\n')!
	for kind in ['corrupt', 'valid'] {
		root := fixtures + '/' + kind
		os.mkdir_all(root + '/etc/vinix-packages', mode: 0o755)!
		os.write_file(root + '/etc/vinix-packages/config.json', if kind == 'corrupt' { '{broken\n' }
			else { '{"format":1,"architecture":"aarch64","repositories":[],"policy":{"offline":true,"reserve_bytes":0}}\n' })!
	}
	mut before := map[string]string{}
	sdk_tree(fixtures, '', mut before)!
	mut refusals := 0
	mut controls := 0
	for kind in ['missing', 'corrupt', 'valid'] {
		root := fixtures + '/' + kind
		for json in [false, true] {
			for index, command in ['view', 'updates', 'status', 'list', 'verify', 'info', 'info'] {
				mut arguments := ['--root', root]
				if json { arguments << '--json' }
				arguments << command
				// info has zero or two operands; other observations have one.
				if command != 'info' { arguments << 'org.example.extra' }
				else if index == 6 {
					arguments << ['org.example.first', 'org.example.second']
				}
				code, output := sdk_run('/usr/bin/vinix-package', arguments)
				expected := if command == 'info' { 'info requires one package ID' } else { command + ' takes no arguments' }
				sdk_require(code == 1 && output == 'vinix-package: ' + expected + '\n', 'operand refusal did not precede configuration/state access')!
				sdk_unchanged(fixtures, before)!
				refusals++
			}
		}
		progress_code, progress := sdk_run('/usr/bin/vinix-package', ['--root', root, '--progress', 'verify', 'org.example.extra'])
		sdk_require(progress_code == 1 && progress == 'vinix-package: verify takes no arguments\n', 'progress verify bypassed operand admission')!
		sdk_unchanged(fixtures, before)!
		refusals++
		for command in ['status', 'list', 'verify'] {
			code, output := sdk_run('/usr/bin/vinix-package', ['--root', root, '--json', command])
			if kind == 'valid' {
				sdk_require(code == 0, 'valid empty observation failed')!
				state := json2.decode[SdkEmptyState](output)!
				sdk_require(state.format == 1 && state.generation == 0 && state.previous == 0
					&& state.architecture == 'aarch64' && state.requested.len == 0 && state.packages.len == 0, 'empty observation changed its document contract')!
			} else {
				sdk_require(code == 1 && !output.contains('takes no arguments') && !output.contains('info requires one package ID'), 'valid operands failed at operand admission')!
			}
			sdk_unchanged(fixtures, before)!
			controls++
		}
	}
	sdk_require(refusals == 45 && controls == 9 && !os.exists(fixtures + '/missing')
		&& !os.exists(fixtures + '/valid/var'), 'incomplete operand matrix or initialized fresh package state')!
	println('SDK CONTRACT arity 45 early refusals and 9 valid controls preserve missing/corrupt/valid fixture trees PASS')
}

fn sdk_check() ! {
	for name in ['capabilities', 'deployment-writer', 'repository-url', 'policy-writer'] {
		code, output := sdk_run('/usr/share/package-fixtures/' + name, ['/usr/bin/vinix-package', '/tmp/sdk-contract-' + name])
		sdk_require(code == 0 && !output.contains(': fn test_'), name + ': consumer failed')!
		println('SDK CONTRACT PROCESS ' + name + ' PASS')
	}
	sdk_arity()!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	println('SDK CONTRACT native ' + architecture + ' executes configured aarch64 document fixtures PASS')
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-sdk-contract')
	mut passed := true
	sdk_check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-sdk-contract' } else { 'HWTEST FAIL packages-sdk-contract' })
	C.sync(); C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
