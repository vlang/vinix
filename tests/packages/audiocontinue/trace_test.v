// SPDX-License-Identifier: GPL-2.0-or-later
// Intentional text/file fixtures only. The caller supplies an ordinary fixture
// parent already covered by its charged roots; there is no uncharged fallback.
module audiocontinue

import os
import time

fn trace2_cleanup(path string) {
	if os.getenv('AUDIO_CONTINUATION_RETAIN_FIXTURES') != '1' { os.rmdir_all(path) or {} }
}

struct Trace2Fixture {
	base string
	build string
	sysroot string
	gcc string
}

fn trace2_fixture() !Trace2Fixture {
	parent := os.getenv('AUDIO_CONTINUATION_TEST_ROOT')
	if parent == '' { return error('trace v2 tests require charged AUDIO_CONTINUATION_TEST_ROOT') }
	trace2_root(parent)!
	base := parent + '/vinix-audio-trace2-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	f := Trace2Fixture{base: base, build: base + '/build', sysroot: base + '/sysroot', gcc: base + '/gcc'}
	os.mkdir(base, mode: 0o700)!
	for path in [f.build, f.sysroot + '/include', f.sysroot + '/lib', f.gcc + '/include', f.gcc + '/include-fixed'] {
		os.mkdir_all(path)!
	}
	mut paths := [f.sysroot + '/include/stdint.h', f.gcc + '/include/stdarg.h', f.gcc + '/include-fixed/limits.h']
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a', 'libm.a', 'libpthread.a'] { paths << f.sysroot + '/lib/' + name }
	for name in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { paths << f.gcc + '/' + name }
	for relative in ['cross-probe.o', 'cross-probe.c', 'sandbox-build/vinix-sandbox-sandbox.o', 'sandbox-build/sandbox.c',
		'tone-build/tone.o', 'tone-build/tone.c', 'guest-build/init.o', 'guest-build/init.c',
		'tools/program-0/vinix-package.o', 'tools/program-0/vinix-package.c',
		'tools/program-1/vinix-account.o', 'tools/program-1/vinix-account.c',
		'tools/program-2/vinix-session.o', 'tools/program-2/vinix-session.c',
		'tools/program-3/vinix-authd.o', 'tools/program-3/vinix-authd.c'] {
		paths << f.build + '/' + relative
	}
	for path in paths {
		os.mkdir_all(os.dir(path))!
		os.write_file(path, 'intentional trace admission fixture\n')!
	}
	return f
}

fn trace2_text(f Trace2Fixture, name string) !string {
	mut lines := ['#include <...> search starts here:', ' ' + f.gcc + '/include',
		' ' + f.gcc + '/include-fixed', ' ' + f.sysroot + '/include', 'End of search list.',
		'. ' + f.sysroot + '/include/stdint.h']
	for value in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a'] { lines << f.sysroot + '/lib/' + value }
	for value in ['crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] { lines << f.gcc + '/' + value }
	lines << trace_object2(f.build, name)!
	return lines.join('\n') + '\n'
}

fn trace2_refuses(text string, f Trace2Fixture, name string, allowed map[string]bool) {
	mut refused := false
	verify_trace2(text, f.build, f.sysroot, f.gcc, name, allowed) or { refused = true }
	assert refused
}

fn test_trace2_admits_all_eight_unrewritten_crossroot_traces() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	for name in ['cross-search.log', 'sandbox-build/build.log', 'tone-build/build.log', 'guest-build/build.log',
		'tools/program-0/build.log', 'tools/program-1/build.log', 'tools/program-2/build.log', 'tools/program-3/build.log'] {
		text := trace2_text(f, name) or { panic(err) }
		verify_trace2(text, f.build, f.sysroot, f.gcc, name, map[string]bool{}) or { panic(err) }
	}
}

fn test_trace2_preserves_generated_warning_and_note_grammar() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	name := 'cross-search.log'
	text := trace2_text(f, name) or { panic(err) }
	source := f.build + '/cross-probe.c'
	diagnostics := source + ': In function main:\n' + source + ': At top level:\n'
		+ source + ':7:3: warning: intentional diagnostic\n' + source + ':8: note: intentional note\n'
	verify_trace2(text + diagnostics, f.build, f.sysroot, f.gcc, name, map[string]bool{}) or { panic(err) }
	trace2_refuses(text + source + ':7:3: error: intentional error\n', f, name, map[string]bool{})
	trace2_refuses(text + source + ':x:3: warning: invalid location\n', f, name, map[string]bool{})
}

fn test_trace2_refuses_foreign_relative_and_wrong_root_link_inputs() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	name := 'cross-search.log'
	text := trace2_text(f, name) or { panic(err) }
	for changed in [text + f.base + '/foreign.a\n', text + 'foreign.a\n', text + 'relative/libother.so\n',
		text.replace(f.build + '/cross-probe.o', f.sysroot + '/cross-probe.o')] {
		trace2_refuses(changed, f, name, map[string]bool{})
	}
}

fn test_trace2_requires_complete_startup_and_observed_header_inputs() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	name := 'cross-search.log'
	text := trace2_text(f, name) or { panic(err) }
	trace2_refuses(text.replace(f.sysroot + '/lib/libc.a\n', ''), f, name, map[string]bool{})
	trace2_refuses(text.replace('. ' + f.sysroot + '/include/stdint.h\n', ''), f, name, map[string]bool{})
	trace2_refuses(text + '. relative/header.h\n', f, name, map[string]bool{})
	os.rm(f.sysroot + '/lib/libc.a') or { panic(err) }
	trace2_refuses(text, f, name, map[string]bool{})
}

fn test_trace2_requires_exact_allowed_source_include_parent() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	name := 'cross-search.log'
	text := trace2_text(f, name) or { panic(err) }
	directory := f.base + '/source/include'
	header := directory + '/project.h'
	os.mkdir_all(directory) or { panic(err) }
	os.write_file(header, 'intentional allowed source header\n') or { panic(err) }
	allowed := {header: true}
	with_source := text.replace('End of search list.', ' ' + directory + '\nEnd of search list.') + '. ' + header + '\n'
	verify_trace2(with_source, f.build, f.sysroot, f.gcc, name, allowed) or { panic(err) }
	trace2_refuses(with_source.replace(' ' + directory + '\n', ' ' + f.base + '\n'), f, name, allowed)
	trace2_refuses(with_source, f, name, {header: false})
}

fn test_trace2_refuses_symlink_aliases_and_shared_generated_objects() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	name := 'cross-search.log'
	text := trace2_text(f, name) or { panic(err) }
	alias := f.sysroot + '/include/alias.h'
	os.symlink('stdint.h', alias) or { panic(err) }
	trace2_refuses(text.replace(f.sysroot + '/include/stdint.h', alias), f, name, map[string]bool{})
	root_alias := f.base + '/sysroot-alias'
	os.symlink(f.sysroot, root_alias) or { panic(err) }
	mut refused := false
	verify_trace2(text, f.build, root_alias, f.gcc, name, map[string]bool{}) or { refused = true }
	assert refused
	os.link(f.build + '/cross-probe.o', f.base + '/object-alias') or { panic(err) }
	trace2_refuses(text, f, name, map[string]bool{})
}

fn test_trace2_refuses_overlapping_roots_and_unknown_trace_names() {
	f := trace2_fixture() or { panic(err) }
	defer { trace2_cleanup(f.base) }
	text := trace2_text(f, 'cross-search.log') or { panic(err) }
	mut refused := false
	verify_trace2(text, f.base, f.sysroot, f.gcc, 'cross-search.log', map[string]bool{}) or { refused = true }
	assert refused
	trace2_refuses(text, f, 'not-a-target-trace.log', map[string]bool{})
}
