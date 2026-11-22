// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import lib
import proc

// A recording /sys with the semantics of kernel/fs/sysfs_dynamic.v: parents
// are made on demand, a taken name is refused, and removing a directory
// removes everything in it. Paths are relative to /sys.

pub enum Kind {
	directory
	text
	link
	attribute
}

pub type SysfsShow = fn (context voidptr, mut text lib.Text)
pub type SysfsNamespacedShow = fn (context voidptr, user_namespace &proc.Namespace, mut text lib.Text)

pub type SysfsStore = fn (context voidptr, data &u8, length u64) u64

pub struct Entry {
pub:
	kind  Kind
	value   string // a text's contents or a link's target
	mode    u32    // an attribute's permission bits
	show    SysfsShow = unsafe { nil }
	namespaced_show SysfsNamespacedShow = unsafe { nil }
	context voidptr
}

__global sysfs_entries = map[string]Entry{}
__global pending_directory_claim = ''

fn make_parents(path string) bool {
	mut prefix := ''
	parts := path.split('/')
	for index in 0 .. parts.len - 1 {
		prefix = if prefix.len == 0 { parts[index] } else { prefix + '/' + parts[index] }
		if existing := sysfs_entries[prefix] {
			if existing.kind != .directory { return false }
		} else {
			sysfs_entries[prefix] = Entry{kind: .directory}
		}
	}
	return true
}

pub fn sysfs_directory(path string) bool {
	return make_directory(path, false)
}

pub fn sysfs_create_directory(path string) bool {
	return make_directory(path, true)
}

// Let a competing publisher win just before the next create of this path.
pub fn compete_for_directory(path string) {
	pending_directory_claim = path
}

fn make_directory(path string, exclusive bool) bool {
	if !make_parents(path) { return false }
	if path == pending_directory_claim {
		pending_directory_claim = ''
		sysfs_entries[path] = Entry{kind: .directory}
		sysfs_entries[path + '/owner'] = Entry{kind: .text, value: 'competing device'}
	}
	if existing := sysfs_entries[path] { return !exclusive && existing.kind == .directory }
	sysfs_entries[path] = Entry{kind: .directory}
	return true
}

pub fn sysfs_text(path string, text string) bool {
	if !make_parents(path) || path in sysfs_entries { return false }
	sysfs_entries[path] = Entry{kind: .text, value: text.clone()}
	return true
}

pub fn sysfs_link(path string, target string) bool {
	if !make_parents(path) || path in sysfs_entries { return false }
	sysfs_entries[path] = Entry{kind: .link, value: target.clone()}
	return true
}

pub fn sysfs_attribute(path string, mode u32, show SysfsShow, store SysfsStore, context voidptr) bool {
	if !make_parents(path) || path in sysfs_entries { return false }
	sysfs_entries[path] = Entry{kind: .attribute, mode: mode, show: show, context: context}
	return true
}

pub fn sysfs_namespaced_attribute(path string, mode u32, show SysfsNamespacedShow, context voidptr) bool {
	if !make_parents(path) || path in sysfs_entries { return false }
	sysfs_entries[path] = Entry{kind: .attribute, mode: mode, namespaced_show: show, context: context}
	return true
}

pub fn sysfs_exists(path string) bool { return path in sysfs_entries }

pub fn sysfs_remove(path string) bool {
	if path !in sysfs_entries { return false }
	mut doomed := [path]
	for key, _ in sysfs_entries {
		if key.starts_with(path + '/') { doomed << key }
	}
	for key in doomed { sysfs_entries.delete(key) }
	return true
}

// What the checks read back.
pub fn entry(path string) ?Entry {
	return sysfs_entries[path] or { return none }
}

pub fn published(path string) bool { return path in sysfs_entries }
