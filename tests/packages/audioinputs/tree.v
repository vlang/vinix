// SPDX-License-Identifier: GPL-2.0-or-later
module audioinputs

import os

pub struct Snapshot {
pub:
	root  string
	files map[string]string
	links map[string]string
}

// Absolute link targets are guest paths, rooted exclusively in this sysroot.
// Resolve each component ourselves so host /lib and intermediate links cannot
// redirect reads outside that root. Retain every literal link in the chain.
fn resolve(root string, name string, mut links map[string]string) !string {
	mut pending := name.split('/').filter(it != '')
	mut resolved := []string{}
	mut seen := []string{}
	for _ in 0 .. 4096 {
		if pending.len == 0 { return root + if resolved.len == 0 { '' } else { '/' + resolved.join('/') } }
		part := pending[0]
		pending.delete(0)
		if part == '.' { continue }
		if part == '..' {
			if resolved.len == 0 { return error('sysroot link escapes its root') }
			resolved.delete_last()
			continue
		}
		entry := if resolved.len == 0 { part } else { resolved.join('/') + '/' + part }
		path := root + '/' + entry
		mode := (os.lstat(path)!).mode & 0o170000
		if mode == 0o120000 {
			if entry in seen || seen.len >= 64 { return error('cyclic or excessive sysroot link: ' + entry) }
			seen << entry
			target := os.readlink(path)!
			links[entry] = target
			if target.starts_with('/') { resolved.clear() }
			mut next := target.split('/').filter(it != '')
			next << pending
			pending = next.clone()
			continue
		}
		if mode != 0o040000 && (mode != 0o100000 || pending.len != 0) {
			return error('nonregular sysroot input: ' + path)
		}
		resolved << part
	}
	return error('excessive sysroot path: ' + name)
}

fn walk(root string, name string, ancestors []string, mut files map[string]string,
	mut links map[string]string) ! {
	path := resolve(root, name, mut links)!
	mode := (os.lstat(path)!).mode & 0o170000
	if mode == 0o100000 { files[name] = path; return }
	if mode != 0o040000 { return error('nonregular sysroot input: ' + path) }
	if path in ancestors { return error('cyclic sysroot directory: ' + name) }
	mut chain := ancestors.clone()
	chain << path
	for child in os.ls(path)! {
		walk(root, if name == '' { child } else { name + '/' + child }, chain,
			mut files, mut links)!
	}
}

pub fn snapshot(directory string) !Snapshot {
	root := os.real_path(directory)
	if !os.is_abs_path(root) || (os.lstat(root)!).mode & 0o170000 != 0o040000 {
		return error('sysroot must be an existing absolute directory')
	}
	mut files := map[string]string{}
	mut links := map[string]string{}
	walk(root, '', [], mut files, mut links)!
	return Snapshot{root: root, files: files, links: links}
}
