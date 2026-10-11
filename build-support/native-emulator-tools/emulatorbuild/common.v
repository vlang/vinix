// SPDX-License-Identifier: GPL-2.0-or-later
module emulatorbuild

import fixturehost
import hosttest
import json2
import os
import policyhost
import tarstream

#include <stdlib.h>
fn C.mkdtemp(&char) &char

struct ArgumentError { message string }
fn (e ArgumentError) msg() string { return e.message }
fn (e ArgumentError) code() int { return 2 }

pub fn command(kind string, args []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked(kind, args) or {
		eprintln(err.msg())
		if err is ArgumentError { return 2 }
		return if err.msg() == 'Host test interrupted' { 130 } else { 1 }
	}
	return 0
}

fn checked(kind string, args []string) ! {
	mut specs := [hosttest.Option{ name: '--output', value: true }]
	if kind != 'ps1-homebrew' { specs << hosttest.Option{ name: '--llvm-bin', value: true } }
	if kind == 'ps1' {
		specs << [hosttest.Option{ name: '--sysroot', value: true }, hosttest.Option{ name: '--jobs', value: true }]
	}
	usage := 'Usage: ' + kind + ' ' + if kind in ['n64-homebrew', 'ps2-homebrew'] { '--output DIR' } else { '[--output DIR]' } +
		if kind == 'ps1-homebrew' { '' } else { ' [--llvm-bin DIR]' } +
		if kind == 'ps1' { ' [--sysroot DIR] [--jobs N]' } else { '' }
	parsed := hosttest.parse_arguments(args, specs, 0, usage, 'Build pinned emulator inputs using native V.') or {
		return ArgumentError{err.msg()}
	}
	if kind in ['n64-homebrew', 'ps2-homebrew'] && '--output' !in parsed.options {
		return ArgumentError{'missing required --output'}
	}
	output := hosttest.module_resolve(parsed.options['--output'] or {
		policyhost.root() + if kind == 'ps1' { '/build/ps1' } else { '/build/ps1/homebrew' }
	})!
	llvm_argument := if '--llvm-bin' in parsed.options { if parsed.options['--llvm-bin'] == '' { '.' } else { parsed.options['--llvm-bin'] } } else { '' }
	match kind {
		'n64-homebrew' { n64_homebrew(output, llvm_argument)! }
		'ps2-homebrew' { ps2_homebrew(output, llvm_argument)! }
		'ps1-homebrew' { ps1_homebrew(output)! }
		'ps1' { ps1_build(output, parsed.options)! }
		else { return error('Unknown emulator build command') }
	}
}

pub fn mkdir(path string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	if os.is_dir(path) { return }
	parent := path.trim_right('/').all_before_last('/')
	if parent != '' && parent != path { mkdir(parent)! }
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}

fn private_directory(parent string, prefix string) !string {
	mut pattern := (parent + '/' + prefix + 'XXXXXX\x00').bytes()
	pointer := unsafe { C.mkdtemp(&char(pattern.data)) }
	if pointer == unsafe { nil } { return error('Cannot create private build directory') }
	return unsafe { pointer.vstring().clone() }
}

fn retire(path string) { hosttest.remove_work_dir(path) or { eprintln(err.msg()) } }
fn run(argv []string) ! { policyhost.inherited(argv)! }

fn tool(name string, directory string) !string {
	mut directories := []string{}
	if directory != '' { directories << hosttest.module_resolve(directory)! }
	directories << ['/opt/homebrew/opt/llvm/bin', '/opt/homebrew/opt/lld/bin', '/usr/lib/llvm-23/bin', '/usr/lib/llvm-20/bin']
	for base in directories { if os.is_file(base + '/' + name) { return base + '/' + name } }
	return os.find_abs_path_of_executable(name) or { return error('missing ' + name + ': install LLVM and pass --llvm-bin') }
}

// curl owns HTTP framing and TLS; V owns the size/digest guard, same-directory
// temporary, cancellation and atomic publication. Failed caches stay intact.
pub fn fetch(path string, url string, digest string, maximum i64) ! {
	policyhost.command_checkpoint()!
	if !os.exists(path) {
		work := private_directory(os.dir(path), 'vinix-fetch-')!
		defer { retire(work) }
		temporary := work + '/download'
		run(['curl', '--fail', '--location', '--silent', '--show-error', '--connect-timeout', '120',
			'--speed-limit', '1', '--speed-time', '120', '--max-filesize', maximum.str(),
			'--user-agent', 'Vinix-PS1-build', '--output', temporary, '--', url])!
		if os.file_size(temporary) > maximum { return error('download exceeds pinned size limit') }
		if hosttest.file_digest(temporary)! != digest { return error('upstream checksum mismatch: ' + url) }
		policyhost.command_checkpoint()!
		os.rename(temporary, path)!
	}
	if os.file_size(path) > maximum || hosttest.file_digest(path)! != digest {
		return error('cached checksum mismatch: ' + path)
	}
}

// V parses member names without libarchive's macOS Unicode normalization.
// Only regular files are extracted, with the original 32 MiB/member bound.
pub fn unpack(archive string, destination string) ! {
	mut reader := tarstream.open(archive)!
	defer { reader.close() }
	for {
		policyhost.command_checkpoint()!
		member := reader.next() or { if err is tarstream.End { break }; return err }
		name := member.name
		parts := name.split('/').filter(it != '' && it != '.')
		if name.starts_with('/') || '..' in parts || name.contains('\\') {
			return error('unsafe source archive path: ' + name)
		}
		if member.kind == `5` { continue }
		if !member.regular() || member.size > 32 * 1024 * 1024 {
			return error('unsupported source archive member: ' + name)
		}
		if parts.len < 2 { return error('missing archive root: ' + name) }
		path := destination + '/' + parts[1..].join('/')
		mkdir(os.dir(path))!
		if os.is_link(path) { return error('source destination is a symlink: ' + path) }
		extract_file(mut reader, path)!
		os.chmod(path, if member.mode & 0o111 != 0 { 0o755 } else { 0o644 })!
	}
}

fn extract_file(mut reader tarstream.Reader, path string) ! {
	mut output := os.create(path)!
	defer { output.close() }
	mut bytes := []u8{len: 1024 * 1024}
	for {
		policyhost.command_checkpoint()!
		count := reader.read(mut bytes)!
		if count == 0 { break }
		output.write(bytes[..count])!
	}
}

fn logged(argv []string, log string) !int {
	return fixturehost.logged_owned(argv, policyhost.environment(), policyhost.caller_arch(), '', log, policyhost.command_interrupted)!
}

// Match shlex.join, including literal shell metacharacters in tool paths.
pub fn shell_word(value string) string {
	if value != '' && value.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) ||
		(it >= `0` && it <= `9`) || it in [u8(`_`), `@`, `%`, `+`, `=`, `:`, `,`, `.`, `/`, `-`]) { return value }
	return "'" + value.replace("'", "'\"'\"'") + "'"
}

// Preserve the original sorted/default-spacing JSON cache key, including
// ensure_ascii behavior for Unicode compiler paths and version strings.
pub fn cache_json(value json2.Any) string {
	if value is map[string]json2.Any {
		mut keys := value.keys()
		keys.sort()
		mut fields := []string{}
		for key in keys { fields << cache_json(json2.Any(key)) + ': ' + cache_json(value[key] or { json2.Any(json2.Null{}) }) }
		return '{' + fields.join(', ') + '}'
	}
	if value is string {
		encoded := json2.encode(value)
		mut out := ''
		for ch in encoded.runes() {
			if ch < 128 { out += ch.str() } else if ch <= 0xffff { out += '\\u' + hex_width(u32(ch), 4) }
			else {
				cp := u32(ch) - 0x10000
				out += '\\u' + hex_width(0xd800 + (cp >> 10), 4) + '\\u' + hex_width(0xdc00 + (cp & 1023), 4)
			}
		}
		return out
	}
	return json2.encode(value)
}

fn hex_width(value u32, width int) string {
	text := value.hex()
	return if text.len < width { '0'.repeat(width - text.len) + text } else { text }
}
