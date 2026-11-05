// SPDX-License-Identifier: GPL-2.0-or-later
// Version 2 keeps generated outputs and captured target inputs at distinct
// roots. Historical audioinputs.verify_trace and its evidence stay unchanged.
module audiocontinue

import os

fn trace2_under(path string, root string) bool {
	return path.starts_with(root + '/')
}

fn trace2_path(path string) ! {
	if !os.is_abs_path(path) || path.bytes().any(it < 32 || it == 127)
		|| os.real_path(path) != path {
		return error('trace v2 requires canonical absolute paths without aliases: ' + path)
	}
}

fn trace2_root(path string) ! {
	trace2_path(path)!
	if path == '/' || os.lstat(path)!.mode & 0o170000 != 0o040000 {
		return error('trace v2 root must be an ordinary bounded directory: ' + path)
	}
}

fn trace2_file(path string, owned bool) ! {
	trace2_path(path)!
	stat := os.lstat(path)!
	if stat.mode & 0o170000 != 0o100000 || (owned && stat.nlink != 1) {
		detail := if owned { ' with one link: ' } else { ': ' }
		return error('trace v2 requires an ordinary file' + detail + path)
	}
}

// The caller creates and retains a fresh build root. Mapping an output path
// does not establish freshness; verification additionally refuses object/source
// aliases and shared output inodes. Captured files may retain store hardlinks.
pub fn trace_object2(build_root string, name string) !string {
	trace2_root(build_root)!
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
	relative := paths[name] or { return error('unknown target compiler trace v2: ' + name) }
	return build_root + '/' + relative
}

fn trace2_generated_diagnostic(line string, source string) bool {
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

// The text is the original, unrewritten GCC trace. Only the three exact target
// include directories and exact parents of explicit allowed source files may
// appear in include-search output. This is selection admission, not a compiler
// inventory or proof of the caller's source hashes or fresh-directory claim.
pub fn verify_trace2(text string, build_root string, sysroot string, gcc string,
	trace_name string, allowed map[string]bool) ! {
	if text.contains('\x00') { return error('invalid NUL compiler trace v2') }
	roots := [build_root, sysroot, gcc]
	for root in roots {
		trace2_root(root)!
		if roots.filter(it == root).len != 1
			|| roots.any(it != root && trace2_under(root, it)) {
			return error('trace v2 build/sysroot/GCC roots must be disjoint components')
		}
	}
	include_dirs := [gcc + '/include', gcc + '/include-fixed', sysroot + '/include']
	for directory in include_dirs { trace2_root(directory)! }
	mut allowed_parents := map[string]bool{}
	for path, admitted in allowed {
		if !admitted { continue }
		trace2_file(path, false)!
		allowed_parents[os.dir(path)] = true
	}
	mut expected := map[string]bool{}
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { expected[sysroot + '/lib/' + name] = false }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { expected[gcc + '/' + name] = false }
	object := trace_object2(build_root, trace_name)!
	if !trace2_under(object, build_root) { return error('trace v2 object escaped its build root') }
	trace2_file(object, true)!
	expected[object] = false
	source := if trace_name == 'sandbox-build/build.log' {
		build_root + '/sandbox-build/sandbox.c'
	} else { object[..object.len - 2] + '.c' }
	if !trace2_under(source, build_root) { return error('trace v2 source escaped its build root') }
	trace2_file(source, true)!
	for path, _ in expected { trace2_file(path, path == object)! }
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
			trace2_root(directory)!
			if directory !in include_dirs && !allowed_parents[directory] {
				return error('uncaptured target include search directory v2: ' + directory)
			}
			directories << directory
			continue
		}
		if line.starts_with('.') {
			path := line.trim_left('.').trim_space()
			if !path.starts_with('/') { return error('invalid observed header path v2') }
			if include_dirs.any(trace2_under(path, it)) || allowed[path] {
				trace2_file(path, false)!
				headers++
			} else { return error('uncaptured selected header v2: ' + path) }
		}
		if !line.starts_with('/') {
			if !line.starts_with(' ') && !line.starts_with('\t')
				&& (line.ends_with('.o') || line.ends_with('.a') || line.contains('.so')) {
				return error('relative selected target link input v2: ' + line)
			}
			continue
		}
		if guard_advice {
			if include_dirs.any(trace2_under(line, it)) || allowed[line] {
				trace2_file(line, false)!
				continue
			}
			return error('uncaptured selected header v2: ' + line)
		}
		if line in expected { expected[line] = true; continue }
		if trace2_generated_diagnostic(line, source) {
			trace2_file(source, true)!
			continue
		}
		if line in [sysroot + '/lib/libm.a', sysroot + '/lib/libpthread.a'] {
			trace2_file(line, false)!
			continue
		}
		return error('uncaptured selected target link input v2: ' + line)
	}
	if search { return error('unterminated target include search list v2') }
	for directory in include_dirs {
		if directory !in directories { return error('missing captured target include search directory v2: ' + directory) }
	}
	if headers == 0 { return error('no captured target header was selected v2') }
	for path, seen in expected {
		if !seen { return error('missing captured selected target input v2: ' + path) }
		trace2_file(path, path == object)!
	}
}
