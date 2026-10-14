// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

#include <fcntl.h>
#include <sys/file.h>
fn C.flock(int, int) int

fn command(binary string, arguments []string, require_success bool) !int {
	mut child := os.new_process(binary)
	defer { child.close() }
	child.set_args(arguments); child.set_redirect_stdio_merged(); child.run()
	deadline := time.sys_mono_now() + 10 * time.second
	for child.is_alive() && time.sys_mono_now() < deadline { time.sleep(time.millisecond) }
	if child.is_alive() { child.signal_kill(); child.wait(); return error('publisher command exceeded ten seconds') }
	child.wait()
	text := child.stdout_slurp()
	if require_success && child.code != 0 { return error('publisher command failed: ' + text) }
	return child.code
}

fn publisher_arguments(operation string, work string, repository string, destination string) []string {
	return match operation {
		'pack' { ['pack', work + '/manifest.json', work + '/source', repository] }
		'publish' { ['publish', repository, 'fixture', work + '/seed', '2', '2000000000'] }
		else { ['publish-release', repository, 'fixture', work + '/seed', '2', '2000000000', destination] }
	}
}

fn documents(work string) ![]string {
	mut result := []string{}
	for name in ['manifests/data-all-1.0.0.json', 'index.json', 'index.sig', '.publisher/history.json'] {
		result << os.read_file(work + '/repository/' + name)!
	}
	result << os.ls(work + '/repository/objects')!.sorted().join('\n')
	return result
}

fn check() ! {
	if os.args.len !in [3, 4] || (os.args.len == 4 && os.args[3] != '--before') {
		return error('usage: publisher-workspace-check PACKAGE_BINARY NEW_WORK_DIRECTORY [--before]')
	}
	binary := os.real_path(os.args[1]); work := os.abs_path(os.args[2]); before := os.args.len == 4
	if !os.is_file(binary) || os.exists(work) || os.is_link(work) { return error('qualification needs a package executable and a new directory') }
	os.mkdir_all(work + '/source')!
	os.write_file(work + '/source/data', 'payload')!
	// A public deterministic fixture seed, never a release credential.
	os.write_file(work + '/seed', '01'.repeat(32) + '\n')!; os.chmod(work + '/seed', 0o600)!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'data', name: 'Data',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	command(binary, publisher_arguments('pack', work, work + '/repository', ''), true)!
	command(binary, ['publish', work + '/repository', 'fixture', work + '/seed', '1', '2000000000'], true)!
	command(binary, ['publish-release', work + '/repository', 'fixture', work + '/seed', '1', '2000000000', work + '/first'], true)!
	initial := documents(work)!
	os.write_file(work + '/source/data', 'updated payload')!
	fd := C.open((work + '/repository/.publisher/lock').str, C.O_RDWR | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	assert fd >= 0 && C.flock(fd, C.LOCK_EX | C.LOCK_NB) == 0
	for operation in ['pack', 'publish', 'release'] {
		code := command(binary, publisher_arguments(operation, work, work + '/repository', work + '/blocked-release'), false)!
		assert (code == 0) == (before && operation != 'release'), operation
		if !before { assert documents(work)! == initial }
		assert !os.exists(work + '/blocked-release')
		println('${operation}: ${if before && operation != 'release' { 'previous writer ignored the held release lock' } else { 'busy workspace refused without publishing' }}')
	}
	C.close(fd)
	for operation in ['pack', 'publish', 'release'] {
		command(binary, publisher_arguments(operation, work, work + '/repository', work + '/retry'), true)!
	}
	assert os.read_file(work + '/repository/index.json')! == os.read_file(work + '/retry/index.json')!
	assert os.read_file(work + '/repository/index.sig')! == os.read_file(work + '/retry/index.sig')!
	println('All writers recover after lock release with identical legacy/release metadata')
	if !before {
		stable := documents(work)!
		os.symlink(work + '/repository', work + '/alias')!
		for operation in ['pack', 'publish', 'release'] {
			for path in [work + '/alias', work + '/alias///'] {
				assert command(binary, publisher_arguments(operation, work, path, work + '/alias-release'), false)! != 0
				assert documents(work)! == stable && !os.exists(work + '/alias-release')
			}
		}
		os.mkdir(work + '/source/sub')!; os.symlink(work + '/source/sub', work + '/source-alias')!
		for path in [work + '/source/new/deep/repository', work + '/source-alias/../new/repository'] {
			assert command(binary, publisher_arguments('pack', work, path, ''), false)! != 0
			assert !os.exists(work + '/source/new') && os.ls(work + '/source/sub')!.len == 0
		}
		println('Unsafe workspace aliases and nested/alias-dotdot outputs refuse without changing source or publication')
	}
	println('Publisher workspace qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
