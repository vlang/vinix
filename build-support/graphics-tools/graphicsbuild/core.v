// SPDX-License-Identifier: GPL-2.0-or-later
module graphicsbuild

import cachecli
import crypto.blake2b
import crypto.sha256
import crypto.sha512
import hosttest
import os
import sourcecommand

#include <stdlib.h>
fn C.mkdtemp(&char) &char

fn exclusive_directory(pattern string) !string {
	mut bytes := (pattern + '\x00').bytes()
	result := unsafe { C.mkdtemp(&char(bytes.data)) }
	if isnil(result) { return os.error_posix() }
	return unsafe { result.vstring().clone() }
}

pub const mesa_digest = 'f17f8c2a733fd3c37f346b9304241dc1d13e01df9c8c723b73b10279dd3c2ebed062ec1f15cdbc8b9936bae840a087b23ac38cae7d8982228d582d468ab8c9c9'

pub struct Package {
pub:
	name string
	digest string
}

pub struct Options {
pub:
	mirror string = 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64'
	curl string = 'curl'
	tar string = 'tar'
	source_digest string = mesa_digest
}

// Fixed-size streaming avoids reading the Mesa archive into memory at once.
pub fn digest(algorithm string, path string) !string {
	if algorithm !in ['blake2b', 'sha512', 'sha256'] { return error('unsupported checksum algorithm') }
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 65536}
	match algorithm {
		'blake2b' {
			mut hash := blake2b.new512()!
			for {
				cachecli.checkpoint()!
				count := input.read(mut buffer) or { if err is os.Eof { break }; return err }
				if count == 0 { break }
				hash.write(buffer[..count])!
			}
			return hash.checksum().hex()
		}
		'sha512' {
			mut hash := sha512.new()
			defer { unsafe { hash.free() } }
			for {
				cachecli.checkpoint()!
				count := input.read(mut buffer) or { if err is os.Eof { break }; return err }
				if count == 0 { break }
				hash.write(buffer[..count])!
			}
			return hash.sum([]u8{}).hex()
		}
		else {
			mut hash := sha256.new()
			defer { unsafe { hash.free() } }
			for {
				cachecli.checkpoint()!
				count := input.read(mut buffer) or { if err is os.Eof { break }; return err }
				if count == 0 { break }
				hash.write(buffer[..count])!
			}
			return hash.sum([]u8{}).hex()
		}
	}
}

pub fn verify(algorithm string, path string, expected string, label string) ! {
	actual := digest(algorithm, path)!
	if actual != expected { return error(label + ' checksum mismatch: ' + actual) }
}

pub fn manifest(text string) ![]Package {
	mut packages := []Package{}
	mut names := map[string]bool{}
	for line in text.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		fields := line.fields()
		if fields.len != 2 { return error('invalid Alpine package manifest row: ' + line) }
		name := fields[0]
		if !name.ends_with('.apk') || name.starts_with('.') ||
			!name.bytes().all(it.is_alnum() || it in [`+`, `.`, `-`, `_`]) || name in names {
			return error('invalid or duplicate Alpine package name: ' + name)
		}
		if fields[1].len != 64 || !fields[1].bytes().all(it.is_digit() || (it >= `a` && it <= `f`)) {
			return error('invalid Alpine package checksum: ' + name)
		}
		names[name] = true
		packages << Package{name, fields[1]}
	}
	return packages
}

fn command(argv []string) ! {
	result := sourcecommand.capture_full(argv, os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error('graphics build command failed: ' + argv.str() + '\n' + result.stderr) }
}

struct Fetched {
	path string
	failure string
}

fn fetch(build string, package Package, options Options) Fetched {
	path := build + '/downloads/' + package.name
	fetch_body(path, package, options) or { return Fetched{path, err.msg()} }
	return Fetched{path, ''}
}

fn fetch_body(path string, package Package, options Options) ! {
	if !os.exists(path) {
		// An exclusive directory owns its partial download; an interrupt or failed
		// checksum cannot publish that partial file under the cache key.
		temporary := exclusive_directory(os.dir(path) + '/.venus-fetch.XXXXXX')!
		defer { os.rm(temporary + '/payload') or {}; os.rmdir(temporary) or {} }
		pending := temporary + '/payload'
		command([options.curl, '-fL', '--retry', '3', '-sS', options.mirror + '/' + package.name, '-o', pending])!
		verify('sha256', pending, package.digest, 'Alpine: ' + package.name)!
		os.mv(pending, path)!
	}
	verify('sha256', path, package.digest, 'Alpine: ' + package.name)!
}

pub fn prepare(archive string, build string, manifest_path string, options Options) ! {
	verify('blake2b', archive, options.source_digest, 'Mesa source')!
	os.mkdir_all(build + '/downloads')!
	os.mkdir_all(build + '/sysroot')!
	source := build + '/mesa-25.0.5'
	if !os.exists(source) { command([options.tar, '-xf', archive, '-C', build])! }
	packages := manifest(os.read_file(manifest_path)!)!
	mut archives := []string{}
	// Wait for every worker, including on failure, before extraction or return.
	for start := 0; start < packages.len; start += 8 {
		mut workers := []thread Fetched{}
		end := if start + 8 < packages.len { start + 8 } else { packages.len }
		for package in packages[start..end] { workers << spawn fetch(build, package, options) }
		results := workers.wait()
		mut failure := ''
		for result in results {
			if result.failure != '' && failure == '' { failure = result.failure }
			archives << result.path
		}
		if failure != '' { return error(failure) }
	}
	for path in archives { command([options.tar, '-xf', path, '-C', build + '/sysroot'])! }
}

pub fn libraries(source string, destination string) ! {
	// pathlib.glob has no matches for a missing source directory.
	if !os.is_dir(source) { return }
	for name in os.ls(source)! {
		if !name.contains('.so') { continue }
		from := source + '/' + name
		target := destination + '/' + name
		if os.exists(target) || os.is_link(target) { os.rm(target)! }
		if os.is_link(from) {
			os.symlink(os.readlink(from)!, target)!
		} else {
			hosttest.module_copy_file_preserving_stat(from, target)!
		}
	}
}
