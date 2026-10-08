// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import os

#include <pwd.h>
#include <unistd.h>

@[typedef]
struct C.vinix_cache_passwd {
	pw_dir &char
}

fn C.vinix_cache_getpwnam(&char) &C.vinix_cache_passwd
fn C.access(&char, i32) i32

fn join_path(base string, name string) string {
	if base in ['', '.'] { return name }
	return base + if base.ends_with('/') { name } else { '/' + name }
}

fn parent_path(path string) string {
	value := path.all_before_last('/')
	return if value == '' { '/' } else { value }
}

pub struct PathLoopError {
pub:
	filename string
}

pub fn (e PathLoopError) code() int { return 0 }

pub fn (e PathLoopError) msg() string { return 'Symlink loop from ' + e.filename }

fn resolve_from(base string, rest string, mut active map[string]bool, mut resolved map[string]string) !string {
	mut path := if rest.starts_with('/') { '' } else { base }
	for name in rest.split('/') {
		if name in ['', '.'] { continue }
		if name == '..' {
			path = path.all_before_last('/')
			continue
		}
		candidate := path + '/' + name
		if candidate in resolved {
			path = resolved[candidate]
			continue
		}
		if candidate in active { return PathLoopError{candidate} }
		target := os.readlink(candidate) or {
			path = candidate
			continue
		}
		active[candidate] = true
		path = resolve_from(path, target, mut active, mut resolved)!
		active.delete(candidate)
		resolved[candidate] = path
	}
	return path
}

pub fn resolve_path(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	mut active := map[string]bool{}
	mut resolved := map[string]string{}
	value := resolve_from(if path.starts_with('/') { '' } else { os.getwd() }, path, mut active, mut resolved)!
	return if value == '' { '/' } else { value }
}

fn expand_user(path string) !string {
	if !path.starts_with('~') { return path }
	separator := path.index('/') or { path.len }
	mut home := ''
	if separator == 1 {
		home = os.getenv_opt('HOME') or { os.home_dir() }
	} else {
		if path[1..separator].contains('\x00') { return error('embedded null byte') }
		entry := C.vinix_cache_getpwnam(&char(path[1..separator].str))
		if isnil(entry) { return path }
		home = unsafe { entry.pw_dir.vstring().clone() }
	}
	value := home.trim_right('/') + path[separator..]
	return if value == '' { '/' } else { value }
}

pub fn env_path(env map[string]string, name string, fallback string) !string {
	value := env[name] or { fallback }
	if value.contains('\x00') { return error('embedded null byte') }
	return resolve_path(expand_user(value)!)
}

fn executable(path string) bool {
	return C.access(&char(path.str), C.X_OK) == 0 && os.exists(path) && !os.is_dir(path)
}

pub fn which(command string, env map[string]string) !string {
	if command.contains('\x00') { return '' }
	if command.contains('/') { return if executable(command) { command } else { '' } }
	path := env['PATH'] or { os.getenv_opt('PATH') or { '/usr/bin:/bin' } }
	if path == '' { return '' }
	mut seen := map[string]bool{}
	for directory in path.split(':') {
		if directory in seen { continue }
		seen[directory] = true
		candidate := if directory == '' { command } else { directory + '/' + command }
		if candidate.contains('\x00') { continue }
		if executable(candidate) { return candidate }
	}
	return ''
}

pub fn tool_path(env map[string]string, variable string, fallback string) !string {
	selected := env[variable] or { '' }
	if selected != '' {
		if selected.contains('\x00') { return error('embedded null byte') }
		return resolve_path(expand_user(selected)!)
	}
	found := which(fallback, env)!
	return if found != '' { resolve_path(found)! } else { '' }
}
