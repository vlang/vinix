// SPDX-License-Identifier: GPL-2.0-only
module prunehost

import hosttest
import os
import time

#flag -I @DIR
#include "stat_abi.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

@[typedef]
struct C.vinix_prune_stat {
	st_dev               u64
	st_ino               u64
	st_mode              u32
	st_nlink             u64
	st_uid               u32
	st_gid               u32
	st_rdev              u64
	st_size              i64
	st_blocks            u64
	st_atime             i64
	st_mtime             i64
	st_ctime             i64
	vinix_prune_atime_ns i64
	vinix_prune_mtime_ns i64
	vinix_prune_ctime_ns i64
}

fn C.vinix_prune_stat_read(&char, &C.vinix_prune_stat) i32
fn C.vinix_prune_lstat_read(&char, &C.vinix_prune_stat) i32
fn C.flock(i32, i32) i32

struct Snapshot {
	device   u64
	inode    u64
	mode     u32
	nlink    u64
	uid      u32
	gid      u32
	rdev     u64
	size     i64
	blocks   u64
	atime    i64
	mtime    i64
	ctime    i64
	atime_ns i64
	mtime_ns i64
	ctime_ns i64
}

fn snapshot(path string, follow bool) !Snapshot {
	mut state := C.vinix_prune_stat{}
	code := if follow {
		C.vinix_prune_stat_read(path.str, &state)
	} else {
		C.vinix_prune_lstat_read(path.str, &state)
	}
	if code != 0 { return os.error_posix() }
	return Snapshot{u64(state.st_dev), state.st_ino, state.st_mode, u64(state.st_nlink), state.st_uid, state.st_gid, u64(state.st_rdev), state.st_size, u64(state.st_blocks), state.st_atime, state.st_mtime, state.st_ctime, state.vinix_prune_atime_ns, state.vinix_prune_mtime_ns, state.vinix_prune_ctime_ns}
}

fn regular(path string) bool {
	state := os.stat(path) or { return false }
	return state.get_filetype() == .regular
}

fn archive_name(name string, temporary bool) bool {
	if temporary && !name.starts_with('.') { return false }
	if !temporary && name.starts_with('.') { return false }
	mut stem := if temporary { name[1..] } else { name }
	if temporary {
		if !stem.contains('.') { return false }
		suffix := stem.all_after_last('.')
		if suffix.len != 6 || !suffix.bytes().all(it.is_alnum()) { return false }
		stem = stem.all_before_last('.')
	}
	extensions := if temporary { ['.tar.gz', '.tar'] } else { ['.tar.gz', '.tar', '.iso'] }
	for extension in extensions {
		if stem.ends_with(extension) {
			body := stem[..stem.len - extension.len]
			return body.contains('initramfs') && body.runes().all(it in [rune(`.`), `-`] || hosttest.module_word_rune(it))
		}
	}
	return false
}

pub fn candidates(root string) ![]string {
	if root.contains('\x00') { return error('embedded null byte') }
	mut found := []string{}
	for relative in ['build', 'build/qemu-desktop-capture', 'build/desktop-perf',
		'build-support/init-aarch64'] {
		directory := root.trim_right('/') + '/' + relative
		if os.is_link(directory) || !os.is_dir(directory) { continue }
		for name in os.ls(directory)! {
			path := directory + '/' + name
			if os.is_link(path) || !regular(path) { continue }
			eligible := match relative {
				'build-support/init-aarch64' { archive_name(name, true) }
				'build/desktop-perf' { name.ends_with('.iso') }
				else { archive_name(name, true) || archive_name(name, false) }
			}
			if eligible && !(relative == 'build' && name in [
				'initramfs-desktop-qemu.tar',
				'initramfs-desktop-qemu.iso',
				'initramfs-desktop-full.iso',
			]) {
				found << path
			}
		}
	}
	found.sort()
	return found
}

pub interface Inspector {
	active(paths []string, root string) !map[string]bool
}

pub struct NativeInspector {}

pub fn (inspector NativeInspector) active(paths []string, root string) !map[string]bool {
	mut protected := map[string]bool{}
	// Consume process environments internally. Never log or include them in errors.
	commands := hosttest.capture(['ps', 'axeww', '-o', 'command='], '', 15, os.environ())!
	if commands.code != 0 { return error('could not inspect process build inputs') }
	hosttest.module_decode_utf8(commands.stdout)!
	for path in paths {
		if commands.stdout.contains(path) || commands.stdout.contains(path[root.trim_right('/').len + 1..]) {
			protected[path] = true
		}
	}
	if lsof := os.find_abs_path_of_executable('lsof') {
		result := hosttest.capture([lsof, '-nP', '-Fn', '--', ...paths], '', 15, os.environ())!
		if result.code !in [0, 1] { return error('could not inspect open build archives') }
		hosttest.module_decode_utf8(result.stdout)!
		for line in result.stdout.split_into_lines() {
			if line.starts_with('n/') { protected[hosttest.resolve_path(line[1..])!] = true }
		}
	} else if os.is_dir('/proc/self/fd') {
		mut identities := map[string]string{}
		for path in paths {
			state := os.stat(path)!
			identities['${state.dev}:${state.inode}'] = path
		}
		for process in os.ls('/proc')! {
			if process == '' || !process.bytes().all(it.is_digit()) { continue }
			parent := '/proc/' + process + '/fd'
			descriptors := os.ls(parent) or { continue }
			for descriptor in descriptors {
				state := os.stat(parent + '/' + descriptor) or { continue }
				if path := identities['${state.dev}:${state.inode}'] { protected[path] = true }
			}
		}
	} else {
		return error('lsof or /proc is required to protect open build archives')
	}
	return protected
}

pub struct Report {
pub:
	count int
	freed u64
}

pub fn prune(root string, days f64, keep map[string]bool, dry_run bool, now f64, inspector Inspector) !Report {
	cutoff := now - days * 86400
	mut snapshots := map[string]Snapshot{}
	for path in candidates(root)! {
		if path in keep || os.exists(path + '.keep') { continue }
		state := snapshot(path, true)!
		mtime := f64(state.mtime) + f64(state.mtime_ns) / 1e9
		ctime := f64(state.ctime) + f64(state.ctime_ns) / 1e9
		if mtime < cutoff && ctime < cutoff { snapshots[path] = state }
	}
	if snapshots.len == 0 { return Report{} }
	protected := inspector.active(snapshots.keys(), root)!
	mut count := 0
	mut freed := u64(0)
	for path, before in snapshots {
		if path in protected { continue }
		after := snapshot(path, false) or {
			if err.code() == C.ENOENT { continue }
			return err
		}
		if after != before || os.is_link(path) || os.exists(path + '.keep') { continue }
		if !dry_run {
			os.rm(path) or {
				if err.code() == C.ENOENT { continue }
				return err
			}
			if path.ends_with('.iso') {
				os.rm(path + '.json') or { if err.code() != C.ENOENT { return err } }
			}
		}
		count++
		freed += before.blocks * 512
		println((if dry_run { 'Would remove ' } else { 'Removed ' }) + path[root.trim_right('/').len + 1..])
	}
	return Report{count, freed}
}

pub fn locked_prune(root string, days f64, keep map[string]bool, dry_run bool) !Report {
	path := root.trim_right('/') + '/build/.prune-build-artifacts.lock'
	fd := unsafe { C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_APPEND | C.O_CLOEXEC, 0o666) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	if C.flock(fd, C.LOCK_EX) != 0 { return os.error_posix() }
	return prune(root, days, keep, dry_run, f64(time.now().unix_micro()) / 1e6, NativeInspector{})
}
