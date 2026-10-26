// SPDX-License-Identifier: GPL-2.0-or-later
// Retain inputs and host logs before sealing a stopped account-contract guest.
module main

import crypto.sha256
import json2
import os

const state = '/Users/alex/.local/state/vinix/android/'
const repo = '/Users/alex/code/vinix'

fn digest(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular input required: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn copy_file(from string, to string) ! {
	if os.lstat(from)!.get_filetype() != .regular || os.is_link(to) {
		return error('regular evidence copy required: ' + to)
	}
	if os.exists(to) {
		if digest(from)! != digest(to)! { return error('existing evidence differs: ' + to) }
		return
	}
	os.mkdir_all(os.dir(to))!
	os.cp(from, to)!
	if digest(from)! != digest(to)! { return error('evidence copy differs: ' + to) }
}

fn copy_tree(from string, to string) ! {
	if os.lstat(from)!.get_filetype() != .directory { return error('regular evidence directory required') }
	os.mkdir_all(to)!
	for name in os.ls(from)! {
		path := from + '/' + name
		if os.lstat(path)!.get_filetype() == .directory {
			copy_tree(path, to + '/' + name)!
		} else { copy_file(path, to + '/' + name)! }
	}
}

fn write_source(to string, value string) ! {
	if os.is_link(to) { return error('source destination is a symlink') }
	if os.exists(to) {
		if os.lstat(to)!.get_filetype() != .regular || os.read_file(to)! != value {
			return error('existing historical source differs')
		}
		return
	}
	os.write_file(to, value)!
}

fn receipt(build string) !string {
	if !build.starts_with(state) || os.real_path(build) != build || os.is_link(build) {
		return error('canonical retained build required')
	}
	mut found := []string{}
	for relative in ['build.json', 'apk/build.json'] {
		path := build + '/' + relative
		if os.exists(path) { digest(path)!; found << path }
	}
	if found.len != 1 { return error('one build receipt required: ' + build) }
	return found[0]
}

fn main() {
	if os.args.len != 6 {
		eprintln('usage: account-contract-collect ROOT RUNNER_REVISION LOG_PREFIX FRAMEWORK_BUILD FIXTURE_BUILD')
		exit(2)
	}
	run() or { eprintln(err); exit(1) }
}

fn run() ! {
	root, revision, prefix := os.args[1], os.args[2], os.args[3]
	if !root.starts_with(state + 'account-contract-') || os.real_path(root) != root
		|| os.is_link(root) || !os.is_file(root + '/stop.json') || os.exists(root + '/sha256.json')
		|| os.exists(root + '/collection.json') { return error('fresh stopped unsealed guest required') }
	if revision.len != 40 || !revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| prefix == '' || os.base(prefix) != prefix { return error('full revision and basename prefix required') }
	owner := json2.decode[map[string]json2.Any](os.read_file(root + '/ownership.json')!)!
	stop := json2.decode[map[string]json2.Any](os.read_file(root + '/stop.json')!)!
	pid := owner['pid']!.int()
	if pid <= 1 || stop['pid']!.int() != pid || stop['signal']!.str() != 'SIGTERM'
		|| os.exec(['/bin/ps', '-p', pid.str(), '-o', 'command=']).exit_code != 1 {
		return error('guest is not verified stopped')
	}
	// Keep the source observed during preparation intact. An older retained
	// binary can differ from the checkout; preserve its actual Git source too.
	source := os.exec(['/usr/bin/git', '-C', repo, 'show', revision + ':tests/native-android-ws/account-contract-run.v'])
	if source.exit_code != 0 { return error('cannot retain historical runner source') }
	// Historical fixtures put their receipt under apk/ without a separate seal.
	mut receipts := []string{}
	for build in os.args[4..] { receipts << receipt(build)! }
	digest(os.args[4] + '/sha256.json')!
	write_source(root + '/runner-compiled-source.v', source.output)!
	mut refs := map[string]string{}
	for i, build in os.args[4..] {
		mut inputs := [receipts[i]]
		if os.exists(build + '/sha256.json') { inputs << build + '/sha256.json' }
		for path in inputs {
			refs[path] = digest(path)!
			copy_file(path, root + '/input-receipts/' + i.str() + '-' + os.base(path))!
		}
	}
	copy_tree(os.args[5], root + '/fixture-build')!
	mut logs := 0
	for name in os.ls(state)! {
		if name.starts_with(prefix + '-') && name.ends_with('.log') && !name.contains('-collect-') {
			copy_file(state + name, root + '/host-logs/' + name)!
			logs++
		}
	}
	if logs == 0 { return error('no host logs matched') }
	for name in ['maps-interact-unique258', 'android-run', 'account-contract-retain-opt'] {
		copy_file(repo + '/build/' + if name == 'android-run' { name } else { 'android-maps/' + name }, root + '/' + name)!
	}
	copy_file(repo + '/tests/native-android-ws/maps-interact.v', root + '/maps-interact.v')!
	copy_file(repo + '/tests/native-android-ws/account-contract-collect.v', root + '/collection-source.v')!
	copy_file(os.executable(), root + '/collector')!
	os.write_file(root + '/collection.json', json2.encode({
		'runner_revision': json2.Any(revision)
		'runner_binary_sha256': json2.Any(digest(root + '/runner')!)
		'runner_compiled_source_sha256': json2.Any(digest(root + '/runner-compiled-source.v')!)
		'build_receipt_sha256': json2.decode[json2.Any](json2.encode(refs))!
		'host_log_count': json2.Any(logs)
		'scope': json2.Any('Retained evidence inputs only; runner source revision supplied by operator; no Google login claim')
	}, prettify: true) + '\n')!
	println('ACCOUNT-CONTRACT-COLLECTED logs=' + logs.str())
}
