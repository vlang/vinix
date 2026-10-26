// SPDX-License-Identifier: GPL-2.0-or-later
// Extract the browser package payload and flatten its links before deployment.
module browserclosure

import crypto.sha256
import os
import tarstream

const maximum_files = 20000
const maximum_file_bytes = u64(2) * 1024 * 1024 * 1024

fn parts(name string) ![]string {
	if name == '' || name.len > 4096 || name.starts_with('/')
		|| name.contains_any('\\:') || !name.bytes().all(it >= 32 && it != 127) {
		return error('unsafe closure path: ' + name)
	}
	result := name.trim_right('/').split('/')
	if result.any(it in ['', '.', '..']) { return error('unsafe closure path: ' + name) }
	return result
}

// Keep dynamic runtime modules as well as SONAME aliases. Package metadata,
// ART, LLVM, development libraries and executable tools stay outside this tree.
pub fn approved(name string) bool {
	parts(name) or { return false }
	if name.starts_with('lib/') || name.starts_with('usr/lib/') {
		if name.starts_with('usr/lib/art/') || name.starts_with('usr/lib/llvm')
			|| name.contains('/pkgconfig/') || name.ends_with('.a')
			|| name.ends_with('.la') { return false }
		return true
	}
	if name.starts_with('usr/libexec/webkitgtk-6.0/') { return true }
	if name in ['usr/bin/Xvfb', 'usr/bin/xkbcomp', 'usr/bin/bwrap', 'etc/ssl/cert.pem'] { return true }
	for prefix in ['usr/share/fonts/', 'usr/share/X11/xkb/', 'usr/share/glib-2.0/schemas/',
		'usr/share/mime/', 'usr/share/webkitgtk-6.0/', 'usr/share/locale/', 'etc/ssl/certs/'] {
		if name.starts_with(prefix) { return true }
	}
	return false
}

pub fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

// APK absolute links are rooted in the package tree, never the host filesystem.
// Hardlink names are archive-root-relative, unlike ordinary symlink names.
fn link_path(name string, target string, hard bool) !string {
	if target == '' || target.len > 4096 || target.contains_any('\\:')
		|| !target.bytes().all(it >= 32 && it != 127) {
		return error('unsafe closure link')
	}
	name_parts := parts(name)!
	mut result := if hard || target.starts_with('/') { []string{} } else {
		name_parts[..name_parts.len - 1].clone()
	}
	for component in target.split('/') {
		if component in ['', '.'] { continue }
		if component == '..' {
			if result.len == 0 { return error('closure link escapes package root') }
			result.delete_last()
		} else {
			result << component
		}
	}
	if result.len == 0 { return error('closure link targets package root') }
	return result.join('/')
}

fn relative_link(name string, target string) !string {
	name_parts := parts(name)!
	parent := name_parts[..name_parts.len - 1]
	target_parts := parts(target)!
	mut common := 0
	for common < parent.len && common < target_parts.len
		&& parent[common] == target_parts[common] { common++ }
	mut result := []string{}
	for _ in common .. parent.len { result << '..' }
	result << target_parts[common..]
	return result.join('/')
}

fn real_directory(path string) ! {
	if os.lstat(path)!.get_filetype() != .directory {
		return error('expected a real directory: ' + path)
	}
}

fn parents(root string, components []string) ! {
	mut path := root
	for component in components {
		path += '/' + component
		if !os.exists(path) && !os.is_link(path) { os.mkdir(path)! }
		real_directory(path)!
	}
}

fn write_payload(mut archive tarstream.Reader, destination string, expected i64) ! {
	mut file := os.create(destination)!
	defer { file.close() }
	mut buffer := []u8{len: 64 * 1024}
	mut written := i64(0)
	for {
		n := archive.read(mut buffer)!
		if n == 0 { break }
		if file.write(buffer[..n])! != n { return error('short closure write') }
		written += n
	}
	if written != expected { return error('truncated browser closure member') }
}

// The caller verifies the APK archive's pinned hash before calling this.
// Inventory values are SHA256 for regular files or symlink:RELATIVE_TARGET.
// Identical shared package payload is accepted; all differing collisions fail.
pub fn extract(package string, root string, mut inventory map[string]string) ! {
	real_directory(root)!
	mut archive := tarstream.open_concatenated(package)!
	defer { archive.close() }
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		components := parts(member.name)!
		name := components.join('/')
		if !approved(name) { continue }
		parents(root, components[..components.len - 1])!
		destination := root + '/' + name
		if member.kind == `5` {
			if !os.exists(destination) && !os.is_link(destination) { os.mkdir(destination)! }
			real_directory(destination)!
			continue
		}
		if inventory.len >= maximum_files && name !in inventory {
			return error('browser closure file limit exceeded')
		}
		if member.regular() {
			if member.size < 0 || u64(member.size) > maximum_file_bytes {
				return error('browser closure file too large')
			}
			existing := name in inventory
			if existing {
				if os.lstat(destination)!.get_filetype() != .regular
					|| hash(destination)! != inventory[name]
					|| (os.stat(destination)!.mode & 0o111 != 0) != (member.mode & 0o111 != 0) {
					return error('browser closure collision: ' + name)
				}
				if archive.digest()! != inventory[name] {
					return error('browser closure collision: ' + name)
				}
				continue
			}
			if os.exists(destination) || os.is_link(destination) {
				return error('unrecorded browser closure collision: ' + name)
			}
			write_payload(mut archive, destination, member.size)!
			os.chmod(destination, if member.mode & 0o111 != 0 { 0o755 } else { 0o644 })!
			inventory[name] = hash(destination)!
		} else if member.kind in [u8(`1`), `2`] {
			target := link_path(name, member.linkname, member.kind == `1`)!
			if !approved(target) { return error('closure link targets excluded payload: ' + name) }
			relative := relative_link(name, target)!
			pin := 'symlink:' + relative
			if name in inventory {
				if inventory[name] != pin || !os.is_link(destination)
					|| os.readlink(destination)! != relative {
					return error('browser closure link collision: ' + name)
				}
				continue
			}
			if os.exists(destination) || os.is_link(destination) {
				return error('unrecorded browser closure link collision: ' + name)
			}
			// Hardlinks are represented as links until flattening; no shared inode
			// survives in the deployed protected closure.
			os.symlink(relative, destination)!
			inventory[name] = pin
		} else { return error('unsupported browser closure member kind') }
	}
}

fn resolve(source string, relative string) !string {
	mut remaining := parts(relative)!
	mut traversed := []string{}
	mut links := 0
	for remaining.len > 0 {
		component := remaining[0]
		remaining.delete(0)
		traversed << component
		name := traversed.join('/')
		entry := source + '/' + name
		if os.lstat(entry)!.get_filetype() == .symbolic_link {
			links++
			if links > 40 { return error('closure link cycle or excessive depth') }
			target := os.readlink(entry)!
			if target.starts_with('/') { return error('absolute link in scratch closure') }
			resolved := link_path(name, target, false)!
			mut next := parts(resolved)!
			next << remaining
			remaining = next.clone()
			traversed.clear()
		}
	}
	return source + '/' + traversed.join('/')
}

fn flatten(source string, target string, relative string, depth int, mut inventory map[string]string) ! {
	if depth > 64 { return error('browser closure directory limit exceeded') }
	from_directory := if relative == '' { source } else { resolve(source, relative)! }
	mut names := os.ls(from_directory)!
	names.sort()
	for name in names {
		parts(name)!
		key := if relative == '' { name } else { relative + '/' + name }
		from := resolve(source, key)!
		to := target + '/' + key
		st := os.lstat(from)!
		match st.get_filetype() {
			.directory {
				os.mkdir(to)!
				flatten(source, target, key, depth + 1, mut inventory)!
				os.chmod(to, 0o755)!
			}
			.regular {
				if inventory.len >= maximum_files || st.size > maximum_file_bytes {
					return error('browser closure payload exceeds fixed bounds')
				}
				before := hash(from)!
				os.cp(from, to)!
				os.chmod(to, if st.mode & 0o111 != 0 { 0o555 } else { 0o444 })!
				if hash(from)! != before || hash(to)! != before || os.lstat(to)!.nlink != 1 {
					return error('closure changed while materializing: ' + key)
				}
				inventory[key] = before
			}
			else { return error('special file in browser closure: ' + key) }
		}
	}
}

// Create a new tree of independent, read-only files. The source may contain
// internal links, including archive hardlinks represented by extract().
// Directories remain owner-writable for the builder's generated configuration.
// The caller must seal root ownership after moving this host-built tree to Vinix.
pub fn materialize(source string, target string) !map[string]string {
	real_directory(source)!
	if os.exists(target) || os.is_link(target) { return error('closure destination already exists') }
	from := os.real_path(source)
	to := os.real_path(os.dir(target)) + '/' + os.file_name(target)
	if to == from || to.starts_with(from + '/') { return error('closure destination is inside source') }
	os.mkdir(target)!
	mut inventory := map[string]string{}
	flatten(from, target, '', 0, mut inventory)!
	os.chmod(target, 0o755)!
	return inventory
}
