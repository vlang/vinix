// SPDX-License-Identifier: GPL-2.0-or-later
// Pin complete direct-build/stopped-guest evidence. No login success inference.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const source = '/Users/alex/code/vinix/tests/native-android-ws/account-contract-retain.v'

struct Ownership {
	pid     int
	command string
	started string
}

struct Stop {
	pid    int
	signal string
}

fn digest(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular file required: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn ready(root string) ! {
	if !root.starts_with(state + 'account-contract-') || os.is_link(root)
		|| os.real_path(root) != root {
		return error('canonical account-contract state required')
	}
	if os.is_file(root + '/prepare.json') {
		for name in ['prepare.json', 'ownership.json', 'stop.json'] {
			if os.lstat(root + '/' + name)!.get_filetype() != .regular {
				return error('regular guest receipt required: ' + name)
			}
		}
		owned := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
		stopped := json2.decode[Stop](os.read_file(root + '/stop.json')!)!
		if owned.pid <= 1 || stopped.pid != owned.pid || stopped.signal != 'SIGTERM' {
			return error('guest ownership and stop receipts differ')
		}
		if os.exec(['/bin/ps', '-p', owned.pid.str(), '-o', 'command=']).exit_code == 0 {
			return error('recorded guest PID remains live')
		}
	} else if !os.is_file(root + '/build.json') {
		return error('build or prepared guest receipt required')
	}
	processes := os.exec(['/bin/ps', '-axo', 'command='])
	if processes.exit_code != 0 { return error('cannot inspect live guests') }
	for command in processes.output.split_into_lines() {
		if command.contains('unix:' + root + '/qmp.sock,server=on,wait=off') {
			return error('guest using this state remains live')
		}
	}
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		kind := os.lstat(root + '/' + key)!.get_filetype()
		if key == 'sha256.json' {
			if kind != .regular { return error('regular manifest required') }
			continue
		}
		match kind {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = digest(root + '/' + key)! }
			.socket {
				if key != 'qmp.sock' { return error('unexpected socket: ' + key) }
			}
			else { return error('nonregular evidence entry: ' + key) }
		}
	}
}

fn check(root string, pin string) ! {
	ready(root)!
	if pin.len != 64 || !pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| digest(root + '/sha256.json')! != pin {
		return error('manifest digest differs')
	}
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	if expected != actual { return error('evidence file set or checksums differ') }
	ready(root)!
	println('ACCOUNT-CONTRACT-INTEGRITY-PASS files=' + actual.len.str() + ' sha256=' + pin)
}

fn seal(root string) !string {
	ready(root)!
	for name in ['sha256.json', 'retention.json', 'retention-source.v'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('fresh seal required: ' + name)
		}
	}
	os.cp(source, root + '/retention-source.v')!
	revision := os.exec(['/usr/bin/git', '-C', '/Users/alex/code/vinix', 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { return error('cannot record retention revision') }
	os.write_file(root + '/retention.json', json2.encode({
		'scope':              json2.Any('Complete account-contract evidence integrity only; no Google authentication success claim')
		'completed_utc':      json2.Any(time.utc().str())
		'retention_revision': json2.Any(revision.output.trim_space())
		'source_sha256':      json2.Any(digest(root + '/retention-source.v')!)
		'binary_sha256':      json2.Any(digest(os.executable())!)
		'excluded':           json2.Any(['sha256.json (manifest itself)',
			'qmp.sock (socket only, if present)'])
	}, prettify: true) + '\n')!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	ready(root)!
	os.write_file(root + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	pin := digest(root + '/sha256.json')!
	check(root, pin)!
	return pin
}

fn reject(root string, pin string) ! {
	check(root, pin) or { return }
	return error('invalid evidence accepted')
}

fn self_test(root string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh self-test directory required') }
	os.mkdir_all(root)!
	os.write_file(root + '/build.json', '{}\n')!
	os.write_file(root + '/sample', 'original\n')!
	pin := seal(root)!
	reject(root, '0'.repeat(64))!
	os.write_file(root + '/sample', 'changed\n')!
	reject(root, pin)!
	os.rm(root + '/sample')!
	reject(root, pin)!
	os.write_file(root + '/sample', 'original\n')!
	os.write_file(root + '/extra', 'extra\n')!
	reject(root, pin)!
	os.rm(root + '/extra')!
	os.symlink('sample', root + '/extra-link')!
	reject(root, pin)!
	os.rm(root + '/extra-link')!
	check(root, pin)!
	println('ACCOUNT-CONTRACT-RETENTION-SELF-TEST-PASS wrong digest, modification, omission, addition and symlink rejected')
}

fn main() {
	if os.args.len !in [3, 4] || os.args[1] !in ['seal', 'check', 'self-test']
		|| (os.args[1] == 'check' && os.args.len != 4)
		|| (os.args[1] != 'check' && os.args.len != 3) {
		eprintln('usage: account-contract-retain seal ROOT | check ROOT PIN | self-test FRESH_ROOT')
		exit(2)
	}
	root := os.abs_path(os.args[2])
	match os.args[1] {
		'seal' {
			pin := seal(root) or {
				eprintln(err)
				exit(1)
			}
			println('ACCOUNT-CONTRACT-SEALED root=' + root + ' sha256=' + pin)
		}
		'check' { check(root, os.args[3]) or {
			eprintln(err)
			exit(1)
		} }
		else { self_test(root) or {
			eprintln(err)
			exit(1)
		} }
	}
}
