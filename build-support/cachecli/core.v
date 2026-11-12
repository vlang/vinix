// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module cachecli

import cachekey
import os
import sourcecommand

#include <stdlib.h>
#include <unistd.h>

fn C.mkstemp(&u8) i32
fn C.rename(&char, &char) i32

// os.rename treats an existing destination directory as a move into it.
// Cache and artifact publication must replace exactly the requested path.
pub fn replace_file(source string, destination string) ! {
	if source.contains('\x00') || destination.contains('\x00') {
		return error('embedded null byte')
	}
	if C.rename(source.str, destination.str) != 0 { return os.error_posix() }
}

pub fn publish(path string, text string) ! {
	os.mkdir_all(os.dir(path))!
	mut pattern := (path + '.XXXXXX\x00').bytes()
	fd := C.mkstemp(pattern.data)
	if fd < 0 { return os.error_posix() }
	temporary := pattern[..pattern.len - 1].bytestr()
	mut closed := false
	defer {
		if !closed { C.close(fd) }
		os.rm(temporary) or {}
	}
	mut written := 0
	for written < text.len {
		count := unsafe { C.write(fd, text.str + written, uint(text.len - written)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if count == 0 { return error('empty cache-state write') }
		written += int(count)
	}
	closed = true
	if C.close(fd) != 0 { return os.error_posix() }
	replace_file(temporary, path)!
}

fn content(argv []string) !int {
	metadata := argv.len > 0 && argv[0] == '--metadata'
	paths := if metadata { argv[1..] } else { argv }
	if paths.len == 0 {
		eprintln('usage: content-key [--metadata] PATH [PATH ...]')
		return 2
	}
	println(cachekey.content_key(paths.map(if it == '' { '.' } else { it }), metadata)!)
	return 0
}

fn staging(argv []string, root string) !int {
	args := arguments(argv, ['--state', '--staging'], ['--source', '--metadata', '--vlib', '--value',
		'--required', '--executable', '--executable-any'], []string{}, 1, 1, 'usage: staging-cache check|record --state FILE --staging DIRECTORY [inputs and requirements]') or { return error_with_code(err.msg(), 2) }
	state := args.required('--state') or { return error_with_code(err.msg(), 2) }
	stage := args.required('--staging') or { return error_with_code(err.msg(), 2) }
	if args.positional[0] !in ['check', 'record'] {
		return error_with_code('action must be check or record', 2)
	}
	key := cachekey.staging_key(root, args.options['--value'], args.options['--source'].map(if it == '' {
		'.'
	} else {
		it
	}), args.options['--metadata'].map(if it == '' { '.' } else { it }), args.options['--vlib'].map(if it == '' {
		'.'
	} else {
		it
	}))!
	complete := cachekey.staging_complete(if stage == '' { '.' } else { stage }, args.options['--required'], args.options['--executable'], args.options['--executable-any'])!
	if args.positional[0] == 'check' {
		stored := os.read_file(if state == '' { '.' } else { state }) or { return 1 }
		return if complete && stored.trim_space() == key { 0 } else { 1 }
	}
	if !complete { return error_with_code('refusing to cache an incomplete staging tree', 2) }
	publish(state, key + '\n')!
	return 0
}

fn desktop(argv []string) !int {
	args := arguments(argv, ['--root', '--v'], []string{}, []string{}, 0, 0, 'usage: desktop-build-key --root REPOSITORY --v V_COMPILER') or { return error_with_code(err.msg(), 2) }
	root := args.required('--root') or { return error_with_code(err.msg(), 2) }
	v := args.required('--v') or { return error_with_code(err.msg(), 2) }
	env := os.environ()
	input := cachekey.desktop_prepare(root, v, env, root + '/build-support/desktop-build-key')!
	command := cachekey.shell_words(env['VINIX_MUSL_CC_AARCH64'] or { 'aarch64-linux-musl-gcc' })!
	mut path := ''
	mut version := 'missing'
	if command.len > 0 {
		found := cachekey.which(command[0], env)!
		path = if found == '' { '' } else { cachekey.resolve_path(found)! }
		if path != '' {
			result := sourcecommand.capture_combined([path, ...command[1..], '--version'], env, 10, 4 * 1024 * 1024, cancelled) or { sourcecommand.Output{ status: 1 } }
			checkpoint()!
			version = if result.status == 0 && result.stdout.len > 0 {
				result.stdout.split_into_lines()[0]
			} else {
				'unavailable'
			}
		}
	}
	system := $if darwin { 'Darwin' } $else { 'Linux' }
	println(cachekey.desktop_native_complete(input, env, system, path, version)!)
	return 0
}

pub fn cli(kind string, argv []string, root string) int {
	guard := own_commands()
	defer { guard.close() }
	return checked(kind, argv, root) or {
		eprintln(err.msg())
		return if cancelled() {
			interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		}
	}
}

fn checked(kind string, argv []string, root string) !int {
	return match kind {
		'content' { content(argv)! }
		'staging' { staging(argv, root)! }
		'desktop' { desktop(argv)! }
		else { return error('unknown cache command') }
	}
}
