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

pub fn trace_files() []string {
	return ['cross-search.log', 'sandbox-build/build.log', 'tone-build/build.log',
		'guest-build/build.log', 'tools/program-0/build.log', 'tools/program-1/build.log',
		'tools/program-2/build.log', 'tools/program-3/build.log']
}

pub fn trace_object(out string, name string) !string {
	paths := {
		'cross-search.log': 'cross-probe.o'
		'sandbox-build/build.log': 'sandbox-build/vinix-sandbox-sandbox.o'
		'tone-build/build.log': 'tone-build/tone.o'
		'guest-build/build.log': 'guest-build/init.o'
		'tools/program-0/build.log': 'tools/program-0/vinix-package.o'
		'tools/program-1/build.log': 'tools/program-1/vinix-account.o'
		'tools/program-2/build.log': 'tools/program-2/vinix-session.o'
		'tools/program-3/build.log': 'tools/program-3/vinix-authd.o'
	}
	path := paths[name] or { return error('unknown target compiler trace: ' + name) }
	return out + '/' + path
}

fn generated_diagnostic(line string, source string) bool {
	if !line.starts_with(source + ':') { return false }
	tail := line[source.len + 1..]
	if tail.starts_with(' In function ') || tail == ' At top level:' { return true }
	parts := tail.split(':')
	if parts.len < 3 || parts[0] == '' || !parts[0].bytes().all(it >= `0` && it <= `9`) { return false }
	mut kind := parts[1].trim_space()
	if parts[1] != '' && parts[1].bytes().all(it >= `0` && it <= `9`) {
		if parts.len < 4 { return false }
		kind = parts[2].trim_space()
	}
	return kind in ['warning', 'note']
}

pub fn header_allowlist(root string, sources map[string]string, origins map[string]string) map[string]bool {
	mut allowed := map[string]bool{}
	for name, _ in sources { allowed[root + '/' + name] = true }
	for name, path in origins {
		if (name.starts_with('vlib/') || name.starts_with('v-thirdparty/')) && name.ends_with('.h') { allowed[path] = true }
	}
	return allowed
}

// Admit the headers and target startup/libraries selected by GCC, not its
// advertised search options. Compiler-generated temporary objects are distinct
// from target inputs; executable host tools remain separately pinned.
pub fn verify_trace(text string, out string, trace_name string, allowed map[string]bool) ! {
	if text.contains('\x00') { return error('invalid NUL compiler trace') }
	sysroot := out + '/inputs/cross-sysroot'
	gcc := out + '/inputs/cross-gcc'
	mut expected := map[string]bool{}
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { expected[sysroot + '/lib/' + name] = false }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { expected[gcc + '/' + name] = false }
	expected[trace_object(out, trace_name)!] = false
	object := trace_object(out, trace_name)!
	source := if trace_name == 'sandbox-build/build.log' { out + '/sandbox-build/sandbox.c' } else { object[..object.len - 2] + '.c' }
	mut search := false
	mut directories := []string{}
	mut headers := 0
	mut guard_advice := false
	for line in text.split_into_lines() {
		if line == 'Multiple include guards may be useful for:' { guard_advice = true; continue }
		if guard_advice && !line.starts_with('/') { guard_advice = false }
		if line == '#include <...> search starts here:' { search = true; continue }
		if search {
			if line == 'End of search list.' { search = false; continue }
			directory := line.trim_space()
			if directory !in [gcc + '/include', gcc + '/include-fixed', sysroot + '/include'] {
				mut known := false
				for path, _ in allowed { if path.starts_with(directory + '/') { known = true; break } }
				if !known { return error('uncaptured target include search directory: ' + directory) }
			}
			directories << directory
			continue
		}
		if line.starts_with('.') {
			path := line.trim_left('.').trim_space()
			if !path.starts_with('/') { return error('invalid observed header path') }
			if path.starts_with(sysroot + '/include/') || path.starts_with(gcc + '/include/') || path.starts_with(gcc + '/include-fixed/') {
				if '..' in path.split('/') || (os.lstat(path)!).mode & 0o170000 != 0o100000 { return error('selected captured header is not regular: ' + path) }
				headers++
			}
			else if !allowed[path] { return error('uncaptured selected header: ' + path) }
		}
		if !line.starts_with('/') {
			if !line.starts_with(' ') && !line.starts_with('\t') && (line.ends_with('.o') || line.ends_with('.a') || line.contains('.so')) {
				return error('relative selected target link input: ' + line)
			}
			continue
		}
		if guard_advice {
			if line.starts_with(sysroot + '/include/') || line.starts_with(gcc + '/include/') || line.starts_with(gcc + '/include-fixed/') || allowed[line] { continue }
			return error('uncaptured selected header: ' + line)
		}
		if line in expected { expected[line] = true; continue }
		if generated_diagnostic(line, source) {
			if (os.lstat(source)!).mode & 0o170000 != 0o100000 { return error('diagnostic generated source is not regular: ' + source) }
			continue
		}
		if line in [sysroot + '/lib/libm.a', sysroot + '/lib/libpthread.a'] {
			if (os.lstat(line)!).mode & 0o170000 != 0o100000 { return error('selected optional captured target input is not regular: ' + line) }
			continue
		}
		return error('uncaptured selected target link input: ' + line)
	}
	for directory in [gcc + '/include', gcc + '/include-fixed', sysroot + '/include'] {
		if directory !in directories { return error('missing captured target include search directory') }
	}
	if headers == 0 { return error('no captured target header was selected') }
	for path, seen in expected {
		if !seen { return error('missing captured selected target input: ' + path) }
		if (os.lstat(path)!).mode & 0o170000 != 0o100000 { return error('selected captured target input is not regular: ' + path) }
	}
}
