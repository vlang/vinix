// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

#include <sys/stat.h>
#include <unistd.h>
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.chown(&char, i32, i32) i32

fn command(binary string, args []string) !os.Result {
	mut process := os.new_process(binary)
	process.set_args(args); process.set_redirect_stdio_merged(); process.run()
	for _ in 0 .. 100 {
		if !process.is_alive() { break }
		time.sleep(50 * time.millisecond)
	}
	if process.is_alive() { process.signal_kill(); process.wait(); process.close(); return error('signing command exceeded five seconds') }
	process.wait(); code := process.code; output := process.stdout_slurp(); process.close()
	return os.Result{ exit_code: code, output: output }
}

fn success(binary string, args []string) !string {
	result := command(binary, args)!
	if result.exit_code != 0 { return error(result.output) }
	return result.output
}

fn check() ! {
	if os.args.len !in [3, 4] || (os.args.len == 4 && os.args[3] != '--before') {
		return error('usage: signing-seed-check PACKAGE_CLI NEW_WORK_DIRECTORY [--before]')
	}
	binary := os.abs_path(os.args[1])
	work := os.abs_path(os.args[2])
	before := os.args.len == 4
	if os.exists(work) || os.is_link(work) { return error('signing seed work directory must be new') }
	os.mkdir_all(work + '/source')!; os.chmod(work, 0o700)!
	os.write_file(work + '/source/data', 'ordinary payload')!
	os.write_file(work + '/manifest.json', '{"id":"data","version":"1.0.0","architecture":"all","name":"Data","license":"MIT","kind":"data"}')!
	key := success(binary, ['keygen', work + '/seed'])!.trim_space()
	seed := os.read_file(work + '/seed')!
	success(binary, ['pack', work + '/manifest.json', work + '/source', work + '/workspace'])!
	expires := (time.now().unix() + 3600).str()
	mut cases := ['legacy-public', 'legacy-hardlink', 'legacy-padded', 'release-hardlink', 'release-padded',
		'release-public', 'legacy-alias', 'release-alias', 'legacy-fifo', 'release-fifo']
	if os.geteuid() == 0 { cases << ['legacy-owner', 'release-owner'] }
	for kind in cases {
		directory := work + '/' + kind
		os.mkdir(directory, mode: 0o700)!
		path := directory + '/seed'
		outside := directory + '/original'
		os.write_file(outside, seed)!; os.chmod(outside, 0o600)!
		if kind.ends_with('hardlink') { assert C.link(outside.str, path.str) == 0
		} else if kind.ends_with('alias') { os.symlink(outside, path)!
		} else if kind.ends_with('fifo') { assert C.mkfifo(path.str, 0o600) == 0
		} else {
			os.write_file(path, if kind.ends_with('padded') { ' '.repeat(1024) + seed } else { seed })!
			os.chmod(path, if kind.ends_with('public') { 0o644 } else { 0o600 })!
			if kind.ends_with('owner') { assert C.chown(path.str, 1000, 1000) == 0 }
		}
		release := kind.starts_with('release-')
		args := if release { ['publish-release', work + '/workspace', 'fixture', path, '1', expires, directory + '/release'] }
			else { ['publish', work + '/workspace', 'fixture', path, '1', expires] }
		result := command(binary, args)!
		unsafe_old := kind in ['legacy-public', 'legacy-hardlink', 'legacy-padded', 'release-hardlink', 'release-padded', 'legacy-owner']
		accepted := before && unsafe_old
		assert (result.exit_code == 0) == accepted, kind + ': ' + result.output
		assert os.read_file(outside)! == seed && os.lstat(outside)!.mode & 0o777 == 0o600
		if release { assert os.exists(directory + '/release') == accepted }
		if !before {
			assert !os.exists(work + '/workspace/index.json') && !os.exists(work + '/workspace/index.sig')
			assert !os.exists(work + '/workspace/.publisher/history.json')
		}
		println(kind + ': ' + if accepted { 'previous unsafe acceptance reproduced' } else { 'refused without publication' })
	}
	// Restoring a private ordinary seed permits both publishing APIs; the
	// unchanged inputs must retain the same public key and signed index bytes.
	success(binary, ['publish', work + '/workspace', 'fixture', work + '/seed', '1', expires])!
	receipt := success(binary, ['publish-release', work + '/workspace', 'fixture', work + '/seed', '1', expires, work + '/retry'])!
	assert receipt.contains(key)
	assert os.read_file(work + '/workspace/index.json')! == os.read_file(work + '/retry/index.json')!
	assert os.read_file(work + '/workspace/index.sig')! == os.read_file(work + '/retry/index.sig')!
	println('Signing seed qualification: private retry and reproducible signatures PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
