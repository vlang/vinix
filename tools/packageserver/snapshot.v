// SPDX-License-Identifier: GPL-2.0-or-later
module packageserver

import hosttest
import os
import sourcecommand
import stagehost
import tarcore
import tarstream

pub const maximum_shared_file = 64 * 1024 * 1024

pub fn validate_overlay(path string, maximum i64) ! {
	mut reader := tarstream.open_plain_bounded(path, i64(os.file_size(path)))!
	defer { reader.close() }
	mut count := 0
	mut total := i64(0)
	for {
		checkpoint()!
		member := reader.next() or { if err is tarstream.End { break }; return error('invalid tar archive: ' + err.msg()) }
		count++
		if count > 300_000 { return error('too many archive members') }
		if !safe_path(member.name.trim_string_left('./')) { return error('unsafe archive path') }
		if member.kind !in [u8(0), `0`, `7`, `5`, `2`, `1`] { return error('unsupported archive member') }
		if member.kind == `1` && !safe_path(member.linkname.trim_string_left('./')) { return error('unsafe hard-link target') }
		if member.size > maximum - total { return error('expanded overlay is too large') }
		total += member.size
	}
	if count == 0 { return error('empty archive') }
}

fn git_files(root string) ![]string {
	result := sourcecommand.capture(['git', '-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], os.environ(), -1, 64 * 1024 * 1024, cancelled)!
	if result.status != 0 { return error('cannot enumerate host worktree: ' + result.stderr) }
	return result.stdout.split('\x00').filter(it != '')
}

fn extra_files(root string, relative string) ![]string {
	extra := root + '/' + relative
	if !os.is_dir(extra) { return error('host source extra is missing: ' + relative) }
	if os.exists(extra + '/.git') { return git_files(extra)!.map(if relative == '.' { it } else { relative + '/' + it }) }
	mut output := []string{}
	walk_extra(root, relative, mut output)!
	return output
}

fn walk_extra(root string, relative string, mut output []string) ! {
	checkpoint()!
	for name in os.ls(root + '/' + relative)! {
		if name == '.git' { continue }
		child := if relative == '.' { name } else { relative + '/' + name }
		if os.is_dir(root + '/' + child) {
			if !os.is_link(root + '/' + child) { walk_extra(root, child, mut output)! }
		} else { output << child }
	}
}

pub fn stage_sources(root string, ui2 string, work string) !string {
	for path in [root + '/desktop/tools/stage_app', root + '/desktop/tools/stage_ui2', root + '/desktop/tools/ui2_headless_bounds.v', ui2 + '/v.mod', ui2 + '/examples/calculator/main.v'] {
		if !os.is_file(path) { return error('cannot stage desktop sources; required host file is missing: ' + path) }
	}
	linked := work + '/linked'
	stagehost.ui_main([linked + '/vmodules/ui2', ui2, root + '/desktop/tools/ui2_headless_bounds.v'])!
	stagehost.app_main([linked + '/desktop', root + '/desktop', ui2 + '/examples/calculator'])!
	checkpoint()!
	materialized := work + '/materialized'
	hosttest.module_copy_tree(linked, materialized)!
	return materialized
}

pub fn snapshot(config Config, output string, work string) ! {
	mut files := git_files(config.source)!
	for extra in config.extras { files << extra_files(config.source, extra)! }
	files.sort()
	staged := stage_sources(config.source, config.ui2, work)!
	mut writer := tarcore.create_stream(output)!
	defer { writer.close() }
	mut previous := ''
	mut links := map[string]string{}
	for relative in files {
		checkpoint()!
		if relative == previous { continue }; previous = relative
		if !safe_path(relative) { return error('unsafe host source path: ' + relative) }
		source := config.source + '/' + relative
		state := os.lstat(source) or { if err.code() == 2 { continue }; return err }
		if state.get_filetype() !in [.regular, .symbolic_link] { continue }
		if state.size > maximum_shared_file { eprintln('qemu-package-store: not sharing ' + relative + ' (${state.size} bytes)'); continue }
		add_source_member(mut writer, source, relative, mut links)!
	}
	add_tree(mut writer, staged, '.vinix-build')!
	writer.finish()!
	writer.close_checked()!
}

fn add_source_member(mut writer tarcore.Writer, source string, relative string, mut links map[string]string) ! {
	state := os.lstat(source)!
	if state.get_filetype() == .regular && state.nlink > 1 {
		identity := '${state.dev}:${state.inode}'
		if target := links[identity] {
			writer.add(tarcore.Member{name: relative, kind: `1`, linkname: target, mode: i64(state.mode & 0o7777),
				uid: i64(state.uid), gid: i64(state.gid), mtime: state.mtime, uname: user_name(state.uid), gname: group_name(state.gid)}, [])!
			return
		}
		links[identity] = relative
	}
	add_member(mut writer, source, relative, false)!
}

fn add_tree(mut writer tarcore.Writer, source string, relative string) ! {
	checkpoint()!
	add_member(mut writer, source, relative, true)!
	if os.is_dir(source) {
		mut names := os.ls(source)!; names.sort()
		for name in names { add_tree(mut writer, source + '/' + name, relative + '/' + name)! }
	}
}

fn add_member(mut writer tarcore.Writer, source string, relative string, normalized bool) ! {
	state := os.lstat(source)!
	kind := state.get_filetype()
	mut member := tarcore.Member{name: relative, mode: i64(state.mode & 0o7777), uid: if normalized { 0 } else { i64(state.uid) },
		gid: if normalized { 0 } else { i64(state.gid) }, mtime: if normalized { 0 } else { state.mtime },
		kind: if kind == .directory { `5` } else if kind == .symbolic_link { `2` } else { `0` },
		size: if kind == .regular { i64(state.size) } else { 0 }}
	if kind == .symbolic_link { member.linkname = os.readlink(source)! }
	if !normalized {
		member.uname = user_name(state.uid)
		member.gname = group_name(state.gid)
	}
	writer.write(tarcore.header(member)!)!
	if kind == .regular {
		mut file := os.open(source)!; defer { file.close() }
		mut buffer := []u8{len: 1024 * 1024}
		mut remaining := member.size
		for remaining > 0 {
			checkpoint()!
			mut part := unsafe { buffer[..int_min(int(remaining), buffer.len)] }
			count := file.read(mut part)!
			if count == 0 { return error('host source shortened while archiving: ' + source) }
			writer.write(part[..count])!; remaining -= count
		}
		writer.padding(member.size)!
	}
}

#include <pwd.h>
#include <grp.h>
struct C.passwd { pw_name &char }
struct C.group { gr_name &char }
fn C.getpwuid_r(u32, &C.passwd, &char, usize, &&C.passwd) int
fn C.getgrgid_r(u32, &C.group, &char, usize, &&C.group) int
fn user_name(uid u32) string {
	mut state := C.passwd{}; mut storage := []u8{len: 16384}; mut result := &C.passwd(unsafe { nil })
	if C.getpwuid_r(uid, &state, storage.data, usize(storage.len), &result) == 0 && !isnil(result) { return unsafe { state.pw_name.vstring().clone() } }
	return ''
}
fn group_name(gid u32) string {
	mut state := C.group{}; mut storage := []u8{len: 16384}; mut result := &C.group(unsafe { nil })
	if C.getgrgid_r(gid, &state, storage.data, usize(storage.len), &result) == 0 && !isnil(result) { return unsafe { state.gr_name.vstring().clone() } }
	return ''
}
