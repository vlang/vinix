// SPDX-License-Identifier: GPL-2.0-or-later
module browserlaunch

import crypto.sha256
import os

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.open(&char, i32, ...voidptr) i32
fn C.openat(i32, &char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.read(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.getuid() u32
fn C.geteuid() u32

const manifest_header = 'vinix-android-browser-launch-v1'
const manifest_limit = 4 * 1024 * 1024
const file_limit = u64(2) * 1024 * 1024 * 1024
const external_helpers = ['/lib/ld-musl-aarch64.so.1', '/usr/bin/xkbcomp', '/usr/bin/bwrap',
	'/usr/libexec/webkitgtk-6.0/WebKitWebProcess',
	'/usr/libexec/webkitgtk-6.0/WebKitNetworkProcess',
	'/usr/libexec/webkitgtk-6.0/WebKitGPUProcess']

// Retained dirfds detect replacement across the identity change and lazy wait.
// The administrator must keep the deployment immutable through execution.
// Admission descriptors never reach ART, Xvfb or the engine.
pub struct Config {
pub:
	enabled bool
mut:
	manifest_fd i32 = -1
	root_fd i32 = -1
	manifest string
	digest string
	root string
	uid u32
	gid u32
	data string
	loader string
	engine string
	xvfb string
	libraries []string
	xkb string
	fonts string
	fontconfig string
	files map[string]string
	externals map[string]string
}

fn clean_path(path string, absolute bool) bool {
	if path.len == 0 || path.len > 4096 || path.starts_with('/') != absolute
		|| path.ends_with('/') || path.contains_any('\\:\x00\t\n\r')
		|| !path.bytes().all(it >= 32 && it != 127) { return false }
	parts := if absolute { path[1..].split('/') } else { path.split('/') }
	return parts.all(it != '' && it != '.' && it != '..')
}

fn hash_valid(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn parse_manifest(text string) !Config {
	if text.len > manifest_limit || !text.ends_with('\n') || text.contains_any('\r\x00') {
		return error('invalid browser manifest framing')
	}
	lines := text[..text.len - 1].split('\n')
	if lines.len < 16 || lines.len > 20032 || lines[0] != manifest_header {
		return error('invalid browser manifest version or entry count')
	}
	mut config := Config{enabled: true}
	mut seen := map[string]bool{}
	for line in lines[1..] {
		fields := line.split('\t')
		if fields.len < 2 { return error('invalid browser manifest entry') }
		key := fields[0]
		if key in ['file', 'external'] {
			if fields.len != 3 || !hash_valid(fields[1]) || !clean_path(fields[2], key == 'external') {
				return error('invalid browser file pin')
			}
			if key == 'file' {
				if fields[2] in config.files { return error('duplicate browser file pin') }
				config.files[fields[2]] = fields[1]
			} else {
				if fields[2] !in external_helpers || fields[2] in config.externals {
					return error('invalid or duplicate browser external helper')
				}
				config.externals[fields[2]] = fields[1]
			}
			continue
		}
		if key in seen { return error('duplicate browser configuration entry') }
		seen[key] = true
		if key == 'exclusive-principal' {
			if fields.len != 4 || !clean_path(fields[3], true) { return error('invalid exclusive browser principal') }
			for value in fields[1..3] {
				if value.len != 5 || !value.bytes().all(it >= `0` && it <= `9`)
					|| value.int() < 10000 || value.int() > 19999 { return error('invalid browser Unix identity') }
			}
			config.uid, config.gid, config.data = fields[1].u32(), fields[2].u32(), fields[3]
			continue
		}
		if fields.len != 2 { return error('invalid browser configuration value') }
		value := fields[1]
		if key == 'root' {
			if !clean_path(value, true) { return error('invalid browser closure root') }
			config.root = value
		} else if key == 'libraries' {
			parts := value.split(':')
			if parts.len > 8 || !parts.all(clean_path(it, false)) { return error('invalid browser library directories') }
			config.libraries = parts
		} else {
			if !clean_path(value, false) { return error('invalid browser closure selector') }
			match key {
				'loader' { config.loader = value }
				'engine' { config.engine = value }
				'xvfb' { config.xvfb = value }
				'xkb' { config.xkb = value }
				'fonts' { config.fonts = value }
				'fontconfig' { config.fontconfig = value }
				else { return error('unknown browser configuration key') }
			}
		}
	}
	for key in ['exclusive-principal', 'root', 'loader', 'engine', 'xvfb', 'libraries', 'xkb', 'fonts', 'fontconfig'] {
		if key !in seen { return error('missing browser configuration key: ' + key) }
	}
	for file in [config.loader, config.engine, config.xvfb, config.fontconfig] {
		if file !in config.files { return error('browser executable/configuration lacks a file pin') }
	}
	for helper in external_helpers {
		if helper !in config.externals { return error('browser fixed-path helper lacks a file pin: ' + helper) }
	}
	return config
}

fn protected_metadata(info C.stat, directory bool) bool {
	if info.st_uid != 0 { return false }
	mode := u32(info.st_mode)
	return if directory {
		mode & 0o170000 == 0o040000 && mode & 0o022 == 0
	} else {
		mode & 0o170000 == 0o100000 && mode & 0o7222 == 0 && info.st_nlink == 1
			&& info.st_size >= 0 && u64(info.st_size) <= file_limit
	}
}

fn protected_stat(fd i32, directory bool) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || !protected_metadata(info, directory) {
		return error('browser closure requires root-owned protected directories and read-only regular files')
	}
	return info
}

// No symlink, writable ancestor, FIFO or device may redirect a pin read.
fn open_protected(path string, directory bool) !i32 {
	if !clean_path(path, true) { return error('browser protected path must be absolute and canonical') }
	mut fd := unsafe { C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC) }
	if fd < 0 { return error('cannot open browser filesystem root') }
	defer { C.close(fd) }
	protected_stat(fd, true)!
	parts := path[1..].split('/')
	for index, part in parts {
		is_dir := index < parts.len - 1 || directory
		flags := C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK | if is_dir { C.O_DIRECTORY } else { 0 }
		next := unsafe { C.openat(fd, &char(part.str), i32(flags)) }
		if next < 0 { return error('cannot open protected browser input: ' + path) }
		protected_stat(next, is_dir) or { C.close(next); return err }
		if index == parts.len - 1 { return next }
		C.close(fd)
		fd = next
	}
	return error('invalid browser protected path')
}

fn digest_fd(fd i32, limit u64) !string {
	if C.lseek(fd, 0, C.SEEK_SET) != 0 { return error('cannot seek browser input') }
	mut digest := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	defer { unsafe { bytes.free(); digest.free(); free(digest) } }
	mut total := u64(0)
	for {
		n := C.read(fd, bytes.data, usize(bytes.len))
		if n < 0 { return error('cannot hash browser input') }
		if n == 0 { break }
		total += u64(n)
		if total > limit { return error('browser input exceeds size bound') }
		digest.write(bytes[..int(n)])!
	}
	protected_stat(fd, false)!
	mut checksum := []u8{len: 32}
	defer { unsafe { checksum.free() } }
	digest.checksum_into(mut checksum)
	return checksum.hex()
}

fn manifest_text(fd i32) !string {
	if C.lseek(fd, 0, C.SEEK_SET) != 0 { return error('cannot seek browser manifest') }
	mut bytes := []u8{len: manifest_limit + 1}
	mut used := 0
	for used < bytes.len {
		n := unsafe { C.read(fd, &bytes[used], usize(bytes.len - used)) }
		if n < 0 { return error('cannot read browser manifest') }
		if n == 0 { return bytes[..used].bytestr() }
		used += int(n)
	}
	return error('browser manifest exceeds size bound')
}

fn (config Config) inventory(path string, relative string, depth int) !int {
	if depth > 64 { return error('browser closure exceeds directory depth bound') }
	mut count := 0
	fd := open_protected(path, true)!
	C.close(fd)
	for name in os.ls(path)! {
		if !clean_path(name, false) || name.contains('/') { return error('invalid browser closure entry name') }
		child := path + '/' + name
		key := if relative == '' { name } else { relative + '/' + name }
		info := os.lstat(child)!
		if info.get_filetype() == .directory {
			count += config.inventory(child, key, depth + 1)!
		} else {
			if key !in config.files { return error('unlisted browser closure file: ' + key) }
			file := open_protected(child, false)!
			digest := digest_fd(file, file_limit) or { C.close(file); return err }
			C.close(file)
			if digest != config.files[key] { return error('browser closure file digest mismatch: ' + key) }
			count++
		}
		if count > 20000 { return error('browser closure exceeds file count bound') }
	}
	return count
}

fn (config Config) verify_closure() ! {
	count := config.inventory(config.root, '', 0)!
	if count != config.files.len { return error('browser closure inventory is incomplete') }
	for file in [config.loader, config.engine, config.xvfb] {
		fd := open_protected(config.root + '/' + file, false)!
		info := protected_stat(fd, false) or { C.close(fd); return err }
		C.close(fd)
		if info.st_mode & 0o111 == 0 { return error('browser executable is not executable') }
	}
	mut directories := [config.xkb, config.fonts]
	directories << config.libraries
	for directory in directories {
		fd := open_protected(config.root + '/' + directory, true)!
		C.close(fd)
	}
	for path, expected in config.externals {
		fd := open_protected(path, false)!
		info := protected_stat(fd, false) or { C.close(fd); return err }
		actual := digest_fd(fd, file_limit) or { C.close(fd); return err }
		C.close(fd)
		if actual != expected || info.st_mode & 0o111 == 0 { return error('browser fixed helper pin/mode mismatch: ' + path) }
	}
}

fn same_inode(first C.stat, second C.stat) bool {
	return first.st_dev == second.st_dev && first.st_ino == second.st_ino
}

fn (config Config) verify_snapshot() ! {
	file := open_protected(config.manifest, false)!
	defer { C.close(file) }
	root := open_protected(config.root, true)!
	defer { C.close(root) }
	if !same_inode(protected_stat(file, false)!, protected_stat(config.manifest_fd, false)!)
		|| !same_inode(protected_stat(root, true)!, protected_stat(config.root_fd, true)!)
		|| digest_fd(config.manifest_fd, manifest_limit)! != config.digest {
		return error('browser manifest/root snapshot was replaced')
	}
	config.verify_closure()!
}

pub fn (mut config Config) close() {
	if config.manifest_fd >= 0 { C.close(config.manifest_fd); config.manifest_fd = -1 }
	if config.root_fd >= 0 { C.close(config.root_fd); config.root_fd = -1 }
}

// Registry admission already authenticates APK/UID/GID. The manifest explicitly
// attests that the provisioned Unix principal has no legacy bypass launcher.
pub fn from_environment(uid u32, gid u32, data string, identity_enabled bool, registry_enabled bool) !Config {
	os.unsetenv('VINIX_ANDROID_WEBVIEW_FD')
	environment := os.environ()
	path := os.getenv('VINIX_ANDROID_BROWSER_MANIFEST')
	digest := os.getenv('VINIX_ANDROID_BROWSER_MANIFEST_SHA256')
	if 'VINIX_ANDROID_BROWSER_MANIFEST' !in environment && 'VINIX_ANDROID_BROWSER_MANIFEST_SHA256' !in environment {
		return Config{}
	}
	if !identity_enabled || !registry_enabled || C.getuid() != 0 || C.geteuid() != 0
		|| !hash_valid(digest) || !clean_path(path, true) {
		return error('browser launch requires root-pinned configuration, registered APK and exclusive provisioned Unix identity')
	}
	if 'WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS' in environment {
		return error('browser launch refuses a sandbox-disable environment')
	}
	fd := open_protected(path, false)!
	mut keep := false
	defer { if !keep { C.close(fd) } }
	text := manifest_text(fd)!
	if sha256.sum(text.bytes()).hex() != digest { return error('browser manifest digest mismatch') }
	mut config := parse_manifest(text)!
	if config.uid != uid || config.gid != gid || config.data != data {
		return error('browser manifest does not admit the selected exclusive Unix identity/data directory')
	}
	config.manifest, config.digest, config.manifest_fd = path, digest, fd
	config.root_fd = open_protected(config.root, true)!
	config.verify_snapshot() or { C.close(config.root_fd); return err }
	keep = true
	return config
}
