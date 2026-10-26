// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed-source preparation only. This performs no build, seal or qualification.
module main

import crypto.sha256
import json2
import os

const donor = '/Users/alex/code/vinix/build/package-audio-peer-login-guarded-worktree'
const target = '/Users/alex/code/vinix/build/package-peer-login-atomic-fresh-worktree'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026/setup-01'
const revision = '9acefa77bee69247c837e97987a2377536aa41cc'

fn inputs() map[string]string {
	return {
		'kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
		'kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
		'kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
		'kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
		'kernel/socket/public/public.v': '19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a'
		'kernel/socket/socket.v': '98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8'
		'kernel/socket/unix/unix.v': 'c869568959cd09e16b58dbcc5400b49fdb0a1cb27275d0b73c430dce8f82f810'
		'tests/kernel-allocs/frame-page-check.v': '72cfd39dcf6516a0366ca678781edaeea512252142241600505a99a2e2519270'
		'tests/kernel-allocs/frame-page-host-check.v': 'cf000cd5f31e752fdbbcc5a3fb14fa6d8f1b370d66e2c7bff38918263b08e38d'
		'tests/socket-peer-login/README.md': 'eabb6f950d589a4938542ede564dcd1aceca82312e048c8cf7261082e71f7877'
		'tests/socket-peer-login/abi.h': '363c81fbbf005e6a396c43c9f66834ed31098caf2b71c89d134e623d30654a5e'
		'tests/socket-peer-login/dylibclosure/core.v': '503f30711a16017ef56a12555bf609dfb5ecb5bad4d0ec5ff18e3768caf6727c'
		'tests/socket-peer-login/dylibclosure/core_test.v': 'ca9b386e31bc3ccd92b02c91d3d8322b4778e844dc7735d3736620f0fd464346'
		'tests/socket-peer-login/guarded-build-check.v': '20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd'
		'tests/socket-peer-login/guest.v': '209bc73d84912d2a6ea290a8801d05082ed4449823305bbe22123e616f90bc3a'
		'tests/socket-peer-login/matched-kernel-check.md': '8d6a12c3182ff7d438a5b895d43867a2645dd0e419472fa4c990e52e3c596dd4'
		'tests/socket-peer-login/matched-kernel-retain.v': 'b264e9b53b5caa16d3cef88322d54fdf2ef1cc0f28b7485c45560dfe24830034'
	}
}

fn present(path string) bool { return os.exists(path) || os.is_link(path) }

fn digest_regular(path string) !string {
	before := os.lstat(path)!
	if before.mode & 0o170000 != 0o100000 || before.size > 4 * 1024 * 1024 {
		return error('bounded ordinary source file required: ' + path)
	}
	bytes := os.read_bytes(path)!
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.uid != after.uid || before.gid != after.gid || before.size != after.size
		|| before.mtime != after.mtime || before.ctime != after.ctime || u64(bytes.len) != before.size {
		return error('source changed during read: ' + path)
	}
	return sha256.sum(bytes).hex()
}

fn run() ! {
	if os.args.len != 1 { return error('fixed preparation takes no arguments') }
	for path in [donor, target, os.dir(state)] {
		if path != os.real_path(path) || os.lstat(path)!.mode & 0o170000 != 0o040000 {
			return error('canonical ordinary directory required: ' + path)
		}
	}
	if present(state) { return error('fresh setup state required') }
	provenance := os.dir(state) + '/bootstrap-01/source/socket-peer-login'
	if present(os.dir(provenance)) { return error('fresh bootstrap source copy required') }
	gitdir := '/Users/alex/code/vinix/.git/worktrees/package-peer-login-atomic-fresh-worktree'
	if digest_regular(target + '/.git')! != sha256.sum(('gitdir: ' + gitdir + '\n').bytes()).hex()
		|| digest_regular(gitdir + '/HEAD')! != sha256.sum((revision + '\n').bytes()).hex() {
		return error('fresh detached source-base worktree required')
	}
	for relative in ['kernel/alloctrack/frame_page.v', 'tests/kernel-allocs/frame-page-check.v',
		'tests/kernel-allocs/frame-page-host-check.v', 'tests/socket-peer-login',
		'kernel/freestnd-c-hdrs', 'kernel/cc-runtime', 'kernel/c/flanterm', 'kernel/c/lwip',
		'kernel/c/uacpi', 'kernel/c/nanoprintf.h', 'kernel/obj', 'kernel/bin',
		'kernel/cc-runtime-x86_64', 'kernel/cc-runtime-aarch64'] {
		if present(target + '/' + relative) { return error('fresh destination required: ' + relative) }
	}
	pins := inputs()
	mut names := pins.keys()
	names.sort()
	for relative in names {
		if digest_regular(donor + '/' + relative)! != pins[relative] {
			return error('reviewed donor source changed: ' + relative)
		}
		path := target + '/' + relative
		if present(path) && os.lstat(path)!.mode & 0o170000 != 0o100000 {
			return error('ordinary tracked destination required: ' + relative)
		}
	}
	os.mkdir(state)!
	os.write_file(state + '/inputs.json', json2.encode(pins) + '\n')!
	for relative in names {
		path := target + '/' + relative
		os.mkdir_all(os.dir(path))!
		os.cp(donor + '/' + relative, path)!
		if digest_regular(path)! != pins[relative] || digest_regular(donor + '/' + relative)! != pins[relative] {
			return error('copied source differs; preserve failed setup: ' + relative)
		}
	}
	for name in ['guest.v', 'abi.h', 'dylibclosure/core.v', 'dylibclosure/core_test.v',
		'guarded-build-check.v', 'README.md'] {
		relative := 'tests/socket-peer-login/' + name
		path := provenance + '/' + name
		os.mkdir_all(os.dir(path))!
		os.cp(donor + '/' + relative, path)!
		if digest_regular(path)! != pins[relative] || digest_regular(donor + '/' + relative)! != pins[relative] {
			return error('bootstrap source copy differs; preserve failed setup: ' + relative)
		}
	}
	os.write_file(state + '/source-copy.json', json2.encode({'donor': donor, 'target': target,
		'source_base': revision, 'source_files': names.len.str(), 'bootstrap_source_files': '6',
		'scope': 'Exact reviewed source copy only; require external git diff check and unchanged guarded controller qualification. No build, seal or qualification performed.'}) + '\n')!
	println('FRESH ATOMIC SOURCE COPY COMPLETE; NO BUILD OR QUALIFICATION')
}

fn main() { run() or { eprintln(err); exit(1) } }
