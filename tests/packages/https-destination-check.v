// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.pkgcore

#include <sys/wait.h>
#include <unistd.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.alarm(u32) u32
fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int
fn C.setpgid(int, int) int
fn C.kill(int, int) int

fn command(args []string) ! {
	result := os.exec(args)
	if result.exit_code != 0 { return error(result.output) }
}

fn check() ! {
	if os.args.len !in [3, 4] || (os.args.len == 4 && os.args[3] != '--before') {
		return error('usage: https-destination-check HTTPS_FIXTURE NEW_WORK_DIRECTORY [--before]')
	}
	work := os.abs_path(os.args[2])
	before := os.args.len == 4
	if os.exists(work) || os.is_link(work) { return error('HTTPS destination work must be new') }
	os.mkdir_all(work + '/repository')!
	os.write_file(work + '/certificate.cnf', '[req]\nprompt=no\ndistinguished_name=subject\nx509_extensions=extensions\n[subject]\nCN=Vinix destination fixture\n[extensions]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n')!
	command(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-config',
		work + '/certificate.cnf', '-keyout', work + '/key.pem', '-out', work + '/ca.pem'])!
	os.chmod(work + '/key.pem', 0o600)!
	text := 'captured download bytes\n'.repeat(4096)
	prefix := text[..4096]
	os.write_file(work + '/repository/payload', text)!
	os.write_file(work + '/requests', '')!
	os.setenv('CURL_CA_BUNDLE', work + '/ca.pem', true)
	os.setenv('NO_PROXY', '127.0.0.1', true)
	os.setenv('no_proxy', '127.0.0.1', true)
	mut server := os.new_process(os.abs_path(os.args[1]))
	server.set_args([work + '/ca.pem', work + '/key.pem', work + '/repository', work + '/ready', work + '/requests'])
	server.set_redirect_stdio_merged(); server.run()
	defer {
		if server.is_alive() { server.signal_kill() }
		server.wait(); os.write_file(work + '/server.txt', server.stdout_slurp()) or {}; server.close()
	}
	for _ in 0 .. 500 {
		if os.exists(work + '/ready') { break }
		if !server.is_alive() { return error('TLS fixture exited') }
		time.sleep(10 * time.millisecond)
	}
	base := os.read_file(work + '/ready')!
	for kind in ['alias', 'hardlink', 'fifo', 'directory', 'nul-path', 'oversized-resume', 'delayed-alias'] {
		directory := work + '/' + kind
		os.mkdir(directory)!
		path := directory + '/payload'
		outside := directory + '/outside'
		os.write_file(path, prefix)!; os.write_file(outside, prefix)!; os.chmod(outside, 0o600)!
		match kind {
			'alias' { os.rm(path)!; os.symlink(outside, path)! }
			'hardlink' { os.rm(path)!; assert C.link(outside.str, path.str) == 0 }
			'fifo' { os.rm(path)!; assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.rm(path)!; os.mkdir(path)! }
			else {}
		}
		request_count := os.read_file(work + '/requests')!.split_into_lines().len
		child := C.fork()
		assert child >= 0
		if child == 0 {
			C.setpgid(0, 0); C.alarm(3)
			url := base + if kind == 'delayed-alias' { '/delayed/payload' } else { '/ranges/payload' }
			pkgcore.fetch(url, path + if kind == 'nul-path' { '\x00ignored' } else { '' },
				if kind == 'oversized-resume' { u64(32) } else { u64(text.len) }, kind == 'oversized-resume', false) or { C._exit(1) }
			C._exit(0)
		}
		C.setpgid(child, child)
		if kind == 'delayed-alias' {
			for _ in 0 .. 200 {
				if os.read_file(work + '/requests')!.contains('delayed payload') { break }
				time.sleep(5 * time.millisecond)
			}
			assert os.read_file(work + '/requests')!.contains('delayed payload')
			os.rename(path, path + '.saved')!; os.symlink(outside, path)!
		}
		mut status := 0
		assert C.waitpid(child, &status, 0) == child
		// Retire the old implementation's blocked curl grandchild as well.
		C.kill(-child, 9)
		expected := if !before || kind in ['directory', 'oversized-resume'] { 256 } else if kind == 'fifo' { 14 } else { 0 }
		assert status == expected, '${kind}: wait status ${status}, expected ${expected}'
		if !before {
			assert os.read_file(outside)! == prefix && os.lstat(outside)!.mode & 0o777 == 0o600
			assert os.read_file(work + '/requests')!.split_into_lines().len == request_count + if kind == 'delayed-alias' { 1 } else { 0 }
			if kind in ['nul-path', 'oversized-resume'] { assert os.read_file(path)! == prefix }
			if kind == 'directory' { assert os.ls(path)!.len == 0 }
		} else if kind in ['alias', 'hardlink', 'delayed-alias'] { assert os.read_file(outside)! == text }
		else if kind == 'nul-path' { assert os.read_file(path)! == text }
		println('${kind}: wait status ${status}; ${if before { 'previous behavior reproduced' } else { 'refused with external files preserved' }}')
	}
	println('HTTPS destination qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
