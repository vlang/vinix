// SPDX-License-Identifier: GPL-2.0-or-later
module muslnative

import cachecli
import cachekey
import crypto.sha256
import crypto.sha512
import hosttest
import json2
import os
import sourcecommand
import time

#include <fcntl.h>
#include <sys/file.h>
#include <errno.h>
#include <unistd.h>

fn C.mkstemp(&u8) i32
fn C.flock(i32, i32) i32

pub struct InputError {
	message string
}

pub fn (failure InputError) msg() string { return failure.message }

pub fn (failure InputError) code() int { return 2 }

pub struct Options {
pub:
	root             string
	support          string
	arch             string
	stage            string
	cache            string
	cc               string
	jobs             int = 8
	extra_patches    []string
	max_page_size    i64
	required_exports []string
}

pub struct Patch {
pub:
	name string
	data []u8
}

pub struct Plan {
pub:
	options      Options
	version      string
	source_sha   string
	source_url   string
	retain       string
	cc           []string
	ar           string
	ranlib       string
	patches      []Patch
	cflags       string
	ldflags      string
	optimization string
	key          string
	manifest     map[string]json2.Any
}

pub fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

pub fn parents(path string) ! {
	if path == '' || os.is_dir(path) { return }
	parent := path.all_before_last('/')
	if parent != '' && parent != path { parents(parent)! }
	os.mkdir(path)!
}

fn temporary(target string) !string {
	parents(os.dir(target))!
	mut pattern := (os.dir(target) + '/.' + os.base(target) + '.XXXXXX\x00').bytes()
	fd := C.mkstemp(pattern.data)
	if fd < 0 { return os.error_posix() }
	C.close(fd)
	return pattern.bytestr().all_before('\x00')
}

fn replace_file(source string, target string) ! {
	// rename replaces a link itself and rejects directory destinations. os.mv
	// treats an existing directory as a container, which changes publication.
	if C.rename(source.str, target.str) != 0 { return os.error_posix() }
}

pub fn install(source string, target string, mode int) ! {
	if os.is_file(target) && !os.is_link(target) && digest(target)! == digest(source)! && os.stat(target)!.mode & 0o777 == mode {
		return
	}
	path := temporary(target)!
	defer { os.rm(path) or {} }
	os.write_file_array(path, os.read_bytes(source)!)!
	os.chmod(path, mode)!
	replace_file(path, target)!
}

pub fn replace_link(target string, destination string) ! {
	if os.is_link(target) && os.readlink(target)! == destination { return }
	path := temporary(target)!
	defer { os.rm(path) or {} }
	os.rm(path)!
	os.symlink(destination, path)!
	replace_file(path, target)!
}

pub fn captured(command []string) !string {
	cachecli.checkpoint()!
	result := sourcecommand.capture(command, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error(command.str() + '\n' + result.stdout + result.stderr) }
	eprint(result.stderr)
	hosttest.module_decode_utf8(result.stdout)!
	return result.stdout
}

fn shell_quote(value string) string { return hosttest.shell_quote(value) }

fn normalized(options Options) !Options {
	return Options{
		...options
		root:    cachekey.resolve_path(options.root)!
		support: cachekey.resolve_path(options.support)!
		stage:   cachekey.resolve_path(options.stage)!
		cache:   cachekey.resolve_path(options.cache)!
	}
}

pub fn plan(raw Options, retain string) !Plan {
	options := normalized(raw)!
	loader := options.stage + '/lib/ld-musl-' + options.arch + '.so.1'
	data := os.read_bytes(loader)!
	if data.len < 20 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || int(data[18]) + (int(data[19]) << 8) != if options.arch == 'x86_64' {
		62
	} else {
		183
	} {
		return InputError{'staged loader architecture does not match --arch'}
	}
	mut versions := []string{}
	mut position := 0
	for position <= data.len - 7 {
		if data[position] == 0 && data[position + 1] == `1` && data[position + 2] == `.` && data[position + 3] == `2` && data[position + 4] == `.` && data[position + 5] in [
			u8(`5`),
			`6`,
		] && data[position + 6] == 0 {
			found := if data[position + 5] == `5` { '1.2.5' } else { '1.2.6' }
			if found !in versions { versions << found }
			position += 7
		} else {
			position++
		}
	}
	if versions.len != 1 {
		return InputError{'only the pinned musl 1.2.5 and 1.2.6 loaders are supported'}
	}
	version := if versions[0] == '1.2.5' && data.bytestr().contains('posix_getdents\x00') {
		'1.2.6'
	} else {
		versions[0]
	}
	package := if version == '1.2.5' { 'musl-1.2.5-r11' } else { 'musl-1.2.6-r2' }
	patch_dir := if version == '1.2.5' { 'alpine' } else { 'alpine-1.2.6' }
	source_sha := if version == '1.2.5' {
		'a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4'
	} else {
		'd585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a'
	}
	source_url := 'https://musl.libc.org/releases/musl-' + version + '.tar.gz'
	mut cc := cachekey.shell_words(if options.cc != '' {
		options.cc
	} else {
		os.getenv_opt('VINIX_MUSL_CC_' + options.arch.to_upper()) or { options.arch + '-linux-musl-gcc' }
	})!
	if cc.len == 0 { return InputError{'target compiler missing'} }
	selected := cachekey.which(cc[0], os.environ()) or { return InputError{'target compiler missing: ' + hosttest.shell_join(cc)} }
	if selected == '' { return InputError{'target compiler missing: ' + hosttest.shell_join(cc)} }
	cc[0] = cachekey.resolve_path(selected)!
	machine := captured([...cc, '-dumpmachine'])!.trim_space()
	if !machine.starts_with(options.arch + '-') || !machine.contains('linux') {
		return InputError{'compiler target must be ' + options.arch + '-linux: ' + machine}
	}
	versions_cc := captured([...cc, '--version'])!.split_into_lines()
	if versions_cc.len == 0 { return error('empty compiler version') }
	ar := captured([...cc, '-print-prog-name=ar'])!.trim_space()
	ranlib := captured([...cc, '-print-prog-name=ranlib'])!.trim_space()
	records := hosttest.decode_json(os.read_file(options.support + '/' + patch_dir + '/manifest.json')!)!.as_array()
	mut patches := []Patch{}
	for value in records {
		row := value.as_map()
		name := row['name']!.str()
		path := options.support + '/' + patch_dir + '/' + name
		bytes := os.read_bytes(path)!
		if sha512.sum512(bytes).hex() != row['sha512']!.str() {
			return error('Alpine musl patch checksum mismatch: ' + path)
		}
		patches << Patch{name, bytes}
	}
	patches << Patch{'malloc-retain.patch', os.read_bytes(options.support + '/malloc-retain.patch')!}
	for extra in options.extra_patches {
		path := cachekey.resolve_path(cachekey.expand_user(extra)!)!
		patches << Patch{os.base(path), os.read_bytes(path)!}
	}
	mut names := map[string]bool{}
	for patch in patches {
		if patch.name in names { return InputError{'patch filenames must be distinct'} }
		names[patch.name] = true
	}
	cflags := '-fstack-protector-strong -DVINIX_MALLOC_RETAIN=' + retain
	ldflags := '-Wl,-soname,libc.musl-' + options.arch + '.so.1' + if options.max_page_size > 0 {
		' -Wl,-z,max-page-size=' + options.max_page_size.str()
	} else {
		''
	}
	optimization := 'internal,malloc,malloc/mallocng/*.c,string'
	manifest := {
		'version':          json2.Any(version)
		'alpine_package':   json2.Any(package)
		'arch':             json2.Any(options.arch)
		'source_url':       json2.Any(source_url)
		'source_sha256':    json2.Any(source_sha)
		'patches':          json2.Any(patches.map(json2.Any({
			'name':   json2.Any(it.name)
			'sha256': json2.Any(sha256.sum(it.data).hex())
		})))
		'cc':               json2.Any(cc.map(json2.Any(it)))
		'compiler_version': json2.Any(versions_cc[0])
		'compiler_target':  json2.Any(machine)
		'cflags':           json2.Any(cflags)
		'ldflags':          json2.Any(ldflags)
		'optimize':         json2.Any(optimization)
		'retention':        json2.Any(u64(retain.int()))
	}
	key := sha256.sum(canonical(manifest)!.bytes()).hex()
	if options.cache in ['/', options.root] { return InputError{'unsafe build directory'} }
	parents(options.cache)!
	return Plan{options, version, source_sha, source_url, retain, cc, ar, ranlib, patches, cflags, ldflags, optimization, key, manifest}
}

fn wait_child(pid int, _ voidptr) ! {
	for !sourcecommand.child_exited(pid)! {
		cachecli.checkpoint()!
		time.sleep(20 * time.millisecond)
	}
}

fn logged(command []string, environment map[string]string, directory string, log string, append bool) ! {
	result := sourcecommand.run_logged_owned(command, environment, cachecli.cancelled, log, append, directory, wait_child, unsafe { nil }, 0)!
	if result.status != 0 { return error('command failed; see ' + log) }
}
