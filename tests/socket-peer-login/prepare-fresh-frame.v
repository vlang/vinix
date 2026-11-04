// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed source preparation only; no build, audit or qualification is performed.
module main

import crypto.sha256
import json2
import os

const frame_donor = '/Users/alex/code/vinix/build/package-alloc-track-frame-worktree'
const control_donor = '/Users/alex/code/vinix/build/package-audio-peer-login-guarded-worktree'
const target = '/Users/alex/code/vinix/build/package-peer-login-frame-fresh-worktree'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026/setup-01'
const checkout = 'b262bf48f44b6cd1e9f3b73a7d8b0a079bc98943'
const source_base = '9acefa77bee69247c837e97987a2377536aa41cc'
const controller_hash = '20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd'
const old_binding = "const frame_baseline_root = repository + '/build/package-alloc-track-frame-worktree'"
const new_binding = "const frame_baseline_root = repository + '/build/package-peer-login-frame-fresh-worktree'"

fn frame_inputs() map[string]string {
	return {
		'kernel/alloctrack/frame_page.v': 'be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d'
		'kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'
		'kernel/file/locks.v': '74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6'
		'kernel/memory/slab.v': '5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4'
		'tests/kernel-allocs/frame-page-check.v': '72cfd39dcf6516a0366ca678781edaeea512252142241600505a99a2e2519270'
		'tests/kernel-allocs/frame-page-host-check.v': 'cf000cd5f31e752fdbbcc5a3fb14fa6d8f1b370d66e2c7bff38918263b08e38d'
	}
}

fn peer_inputs() map[string]string {
	return {
		'kernel/socket/public/public.v': 'fd712e3ba325aef0f35294e99a66b478f1d8793efb27e650b4bf9a09eaf8fa61'
		'kernel/socket/socket.v': '35fd58065b385cea8e0d29cf3aba2438230a3340f369679065f15221525b71cb'
		'kernel/socket/unix/unix.v': '5a133bfc68668f4dff1d21e4dea02ac2146d0f12ab6e96d2e0289c98bc5c3656'
	}
}

fn control_inputs() map[string]string {
	return {
		'abi.h': '363c81fbbf005e6a396c43c9f66834ed31098caf2b71c89d134e623d30654a5e'
		'dylibclosure/core.v': '503f30711a16017ef56a12555bf609dfb5ecb5bad4d0ec5ff18e3768caf6727c'
		'dylibclosure/core_test.v': 'ca9b386e31bc3ccd92b02c91d3d8322b4778e844dc7735d3736620f0fd464346'
	}
}

fn present(path string) bool { return os.exists(path) || os.is_link(path) }

fn digest_regular(path string) !string {
	before := os.lstat(path)!
	if before.mode & 0o170000 != 0o100000 || before.size > 4 * 1024 * 1024 {
		return error('bounded ordinary source required: ' + path)
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
	for path in [frame_donor, control_donor, target, os.dir(state)] {
		if path != os.real_path(path) || os.lstat(path)!.mode & 0o170000 != 0o040000 {
			return error('canonical ordinary directory required: ' + path)
		}
	}
	if present(state) { return error('fresh setup state required') }
	gitdir := '/Users/alex/code/vinix/.git/worktrees/package-peer-login-frame-fresh-worktree'
	if digest_regular(target + '/.git')! != sha256.sum(('gitdir: ' + gitdir + '\n').bytes()).hex()
		|| digest_regular(gitdir + '/HEAD')! != sha256.sum((checkout + '\n').bytes()).hex() {
		return error('fresh detached b262 worktree required')
	}
	for relative in ['kernel/alloctrack/frame_page.v', 'tests/socket-peer-login',
		'kernel/freestnd-c-hdrs', 'kernel/cc-runtime', 'kernel/c/flanterm', 'kernel/c/lwip',
		'kernel/c/uacpi', 'kernel/c/nanoprintf.h', 'kernel/obj', 'kernel/bin',
		'kernel/cc-runtime-x86_64', 'kernel/cc-runtime-aarch64'] {
		if present(target + '/' + relative) { return error('fresh destination required: ' + relative) }
	}
	frame := frame_inputs()
	peers := peer_inputs()
	controls := control_inputs()
	for relative, hash in frame {
		if digest_regular(frame_donor + '/' + relative)! != hash { return error('frame donor changed: ' + relative) }
		if present(target + '/' + relative) && os.lstat(target + '/' + relative)!.mode & 0o170000 != 0o100000 {
			return error('ordinary destination required: ' + relative)
		}
	}
	for relative, hash in peers {
		if digest_regular(target + '/' + relative)! != hash { return error('pristine peer source differs: ' + relative) }
	}
	control_root := control_donor + '/tests/socket-peer-login'
	controller := control_root + '/guarded-build-check.v'
	if digest_regular(controller)! != controller_hash { return error('reviewed controller changed') }
	source := os.read_file(controller)!
	if sha256.sum(source.bytes()).hex() != controller_hash { return error('controller read buffer differs') }
	if source.count(old_binding) != 1 { return error('unique fixed baseline root binding required') }
	changed := source.replace(old_binding, new_binding)
	changed_hash := sha256.sum(changed.bytes()).hex()
	for relative, hash in controls {
		if digest_regular(control_root + '/' + relative)! != hash { return error('controller closure changed: ' + relative) }
	}
	os.mkdir(state)!
	os.write_file(state + '/inputs.json', json2.encode({'frame': frame, 'peer': peers, 'controller': controls}) + '\n')!
	for relative, hash in frame {
		path := target + '/' + relative
		os.mkdir_all(os.dir(path))!
		os.cp(frame_donor + '/' + relative, path)!
		if digest_regular(path)! != hash || digest_regular(frame_donor + '/' + relative)! != hash {
			return error('frame copy differs; preserve failed setup: ' + relative)
		}
	}
	for relative, hash in controls {
		path := target + '/tests/socket-peer-login/' + relative
		os.mkdir_all(os.dir(path))!
		os.cp(control_root + '/' + relative, path)!
		if digest_regular(path)! != hash || digest_regular(control_root + '/' + relative)! != hash {
			return error('controller closure copy differs; preserve failed setup: ' + relative)
		}
	}
	output := target + '/tests/socket-peer-login/guarded-build-check.v'
	os.write_file(output, changed)!
	if digest_regular(output)! != changed_hash || digest_regular(controller)! != controller_hash {
		return error('controller binding copy differs; preserve failed setup')
	}
	for relative, hash in peers {
		if digest_regular(target + '/' + relative)! != hash { return error('peer source changed during setup: ' + relative) }
	}
	os.write_file(state + '/source-copy.json', json2.encode({'target': target, 'checkout': checkout,
		'source_base': source_base, 'controller_input_sha256': controller_hash,
		'controller_output_sha256': changed_hash, 'controller_only_change_from': old_binding,
		'controller_only_change_to': new_binding,
		'scope': 'Fixed frame4 source copy and one fixed controller root substitution only. No build, audit or qualification.'}) + '\n')!
	println('FRESH FRAME SOURCE COPY COMPLETE; NO BUILD OR QUALIFICATION')
}

fn main() { run() or { eprintln(err); exit(1) } }
