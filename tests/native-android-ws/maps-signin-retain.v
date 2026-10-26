// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve one stopped, pre-credential Maps sign-in diagnostic; no auth claim.
// Build with -prod for streaming SHA256 over the retained disk image.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const source = repo + '/tests/native-android-ws/maps-signin-retain.v'
const launcher = repo + '/tests/native-android-ws/maps-signin-probe.v'
const launcher_revision = '2435364cf'
const launcher_self_test = '/Users/alex/.local/state/vinix/android/maps-signin-probe-self-test-prod-2026-10-26/self-test.json'
const scope = 'Pre-credential Google Maps sign-in diagnostic preservation only; no successful authentication is claimed.'

struct Ownership {
	pid     int
	command string
	started string
}

struct Launch {
	input_sha256 map[string]string
}

struct Stop {
	pid    int
	signal string
}

fn hash(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular file required: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(bytes[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn stopped(root string) ! {
	if os.is_link(root) || os.real_path(root) != root {
		return error('canonical state directory required')
	}
	for name in ['ownership.json', 'stop.json', 'launch-before.json'] {
		if os.lstat(root + '/' + name)!.get_filetype() != .regular {
			return error('regular receipt required: ' + name)
		}
	}
	owned := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	stop := json2.decode[Stop](os.read_file(root + '/stop.json')!)!
	if owned.pid <= 1 || stop.pid != owned.pid || stop.signal != 'SIGTERM' {
		return error('ownership and stop receipts differ')
	}
	if os.exec(['/bin/ps', '-p', owned.pid.str(), '-o', 'command=']).exit_code == 0 {
		return error('recorded guest PID remains live')
	}
	processes := os.exec(['/bin/ps', '-axo', 'command='])
	if processes.exit_code != 0 { return error('cannot verify stopped guest') }
	for command in processes.output.split_into_lines() {
		if command.trim_space().starts_with(owned.command.all_before(' ') + ' ')
			&& command.contains('unix:' + root + '/qmp.sock,server=on,wait=off') {
			return error('guest using this state directory remains live')
		}
	}
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		kind := os.lstat(path)!.get_filetype()
		if key == 'sha256.json' {
			if kind != .regular { return error('regular manifest required') }
			continue
		}
		match kind {
			.regular { files[key] = hash(path)! }
			.directory { inventory(root, key, mut files)! }
			.socket {
				if key != 'qmp.sock' { return error('unexpected socket: ' + key) }
			}
			else { return error('unexpected non-regular entry: ' + key) }
		}
	}
}

fn check(root string, pin string) ! {
	stopped(root)!
	if pin.len != 64 || !pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| hash(root + '/sha256.json')! != pin {
		return error('manifest digest differs')
	}
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	if expected != actual { return error('bundle files or checksums differ') }
	stopped(root)!
	println('MAPS-SIGNIN-BUNDLE-CHECK-PASS files=' + actual.len.str() + ' sha256=' + pin)
}

fn seal(root string) ! {
	stopped(root)!
	for name in ['sha256.json', 'seal-metadata.json', 'launcher-source.v', 'retention-source.v',
		'launcher-self-test.json'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('fresh seal required: ' + name)
		}
	}
	launch := json2.decode[Launch](os.read_file(root + '/launch-before.json')!)!
	expected_launcher := launch.input_sha256[launcher] or { return error('launcher hash missing from launch receipt') }
	original := os.exec(['/usr/bin/git', '-C', repo, 'show',
		launcher_revision + ':tests/native-android-ws/maps-signin-probe.v'])
	if original.exit_code != 0 || sha256.sum(original.output.bytes()).hex() != expected_launcher {
		return error('committed launcher does not match launch source hash')
	}
	os.write_file(root + '/launcher-source.v', original.output)!
	os.cp(source, root + '/retention-source.v')!
	os.cp(launcher_self_test, root + '/launcher-self-test.json')!
	metadata := {
		'scope':                   json2.Any(scope)
		'argv':                    json2.Any(os.args)
		'completed_utc':           json2.Any(time.utc().str())
		'launcher_revision':       json2.Any(launcher_revision)
		'launcher_sha256':         json2.Any(expected_launcher)
		'retention_source_sha256': json2.Any(hash(source)!)
		'retention_binary_sha256': json2.Any(hash(os.executable())!)
		'excluded':                json2.Any(['sha256.json (manifest itself)',
			'qmp.sock (socket only, if present)'])
	}
	os.write_file(root + '/seal-metadata.json', json2.encode(metadata, prettify: true) + '\n')!
	mut files := map[string]string{}
	inventory(root, '', mut files)!
	stopped(root)!
	os.write_file(root + '/sha256.json', json2.encode(files, prettify: true) + '\n')!
	pin := hash(root + '/sha256.json')!
	check(root, pin)!
	println('MAPS-SIGNIN-BUNDLE-SEALED root=' + root + ' sha256=' + pin)
}

fn main() {
	if os.args.len !in [3, 4] || os.args[1] !in ['seal', 'check']
		|| (os.args[1] == 'seal' && os.args.len != 3)
		|| (os.args[1] == 'check' && os.args.len != 4) {
		eprintln('usage: maps-signin-retain seal ROOT | check ROOT MANIFEST_SHA256')
		exit(2)
	}
	root := os.abs_path(os.args[2])
	if os.args[1] == 'seal' {
		seal(root) or {
			eprintln(err)
			exit(1)
		}
	} else {
		check(root, os.args[3]) or {
			eprintln(err)
			exit(1)
		}
	}
}
