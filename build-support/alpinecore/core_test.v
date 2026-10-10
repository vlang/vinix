// SPDX-License-Identifier: GPL-2.0-or-later
module alpinecore

import hosttest
import os

fn test_fields_unicode_whitespace_and_universal_newlines() {
	text := 'P:obsolete\rP:root\rV:1-r0\rD: a>=1\t b\u0085c\u00a0d\u2003e\u2028f\u2029g\u3000h\x1fi\rp: virtual=1 cmd:root\r\rP:missing-version\r\rV:missing-name\r\rP:\rV:\r'
	packages := parse_text(text, 'main')!
	assert packages == [
		Package{'root', '1-r0', ['a>=1', 'b'], ['virtual=1', 'cmd:root'], 'main'},
		Package{'', '', []string{}, []string{}, 'main'},
	]
	assert parse_text(text.replace('\r', '\r\n'), 'main')! == packages
	assert words('a\u0085b\u00a0c\u2003d\u2028e\u2029f\u3000g\x1fh') == ['a', 'b', 'c', 'd', 'e',
		'f', 'g', 'h']
	assert parse_text('P:first\nV:1\n\nP:second\nV:2', 'repo')!.len == 2
	// A Unicode line separator separates fields, but only an empty LF line
	// separates records, so the last value of a repeated field wins.
	assert parse_text('P:first\u2028V:1\u2029P:last\u0085V:2', 'r')! == [
		Package{'last', '2', []string{}, []string{}, 'r'},
	]
	assert parse_text('', 'r')! == []Package{}
}

fn test_utf8_decoding_is_strict_and_bom_is_retained() {
	for invalid in ['P:x\nV:1\n\xff', '\xed\xa0\x80', '\xc0\x80', '\xf4\x90\x80\x80', '\xe2\x82'] {
		parse_text(invalid, 'r') or {
			assert err.msg() == 'APKINDEX is not valid UTF-8'
			continue
		}
		assert false, 'accepted invalid UTF-8'
	}
	assert parse_text('\ufeffP:x\nV:1', 'r')! == []Package{}
	assert parse_text('P:猫\nV:é', 'r')! == [Package{'猫', 'é', []string{}, []string{}, 'r'}]
}

fn test_dependency_keys_do_not_strip_or_evaluate_versions() {
	for specification in ['so:libc.so>=1', 'so:libc.so<1', 'so:libc.so=1', 'so:libc.so~1'] {
		assert dependency_key(specification) == 'so:libc.so'
	}
	assert dependency_key('>=1') == ''
	assert dependency_key('!conflict=1') == '!conflict'
	assert dependency_key(' name (test)') == ' name (test)'
	assert dependency_key('猫>é') == '猫'
}

fn test_name_precedence_first_provider_fifo_cycles_and_ignored_dependencies() {
	packages := [
		Package{'root', '1', ['virtual>=99', 'name', 'cycle', 'cmd:sh', '!absent', '/bin/sh=9',
			'', 'cmd:busybox'], []string{}, 'main'},
		Package{'first', '1', []string{}, ['virtual=1', 'name=1'], 'main'},
		Package{'second', '9', []string{}, ['virtual=9'], 'community'},
		Package{'name', '1', []string{}, []string{}, 'main'},
		Package{'name', '9', ['absent'], []string{}, 'community'},
		Package{'cycle', '1', ['root', 'cycle'], []string{}, 'community'},
	]
	assert resolve(packages, ['root', 'root', 'first'])! == [packages[5], packages[1], packages[3],
		packages[0]]
	resolve(packages, ['root', 'missing=123']) or {
		assert err.msg() == 'unresolved Alpine dependency: missing'
		return
	}
	assert false, 'missing dependency was accepted'
}

fn test_repeated_names_are_deduplicated_even_across_virtual_providers() {
	packages := [
		Package{'same', '1', []string{}, ['old'], 'main'},
		Package{'same', '2', ['missing'], ['new'], 'community'},
	]
	assert resolve(packages, ['old', 'new'])! == [packages[0]]
	resolve(packages, ['new', 'old']) or {
		assert err.msg() == 'unresolved Alpine dependency: missing'
		return
	}
	assert false, 'FIFO selection changed'
}

fn test_large_closure_unicode_sort_and_empty_package_name() {
	mut packages := []Package{}
	for index in 0 .. 1000 {
		packages << Package{
			name:         'p${index:04}'
			version:      '1'
			dependencies: if index < 999 { ['p${index + 1:04}', 'p0000'] } else { []string{} }
			repository:   'r'
		}
	}
	assert resolve(packages, ['p0000'])! == packages
	unicode := [Package{'猫', '', []string{}, []string{}, ''},
		Package{'é', '', []string{}, []string{}, ''}, Package{'z', '', []string{}, []string{}, ''},
		Package{'', '', []string{}, ['empty'], ''}]
	assert resolve(unicode, ['猫', 'é', 'z', 'empty'])! == [unicode[3], unicode[2], unicode[1],
		unicode[0]]
}

fn test_native_cli_manifest_arguments_and_errors() {
	tool := os.getenv('VINIX_ALPINE_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-alpine-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	first := work + '/first index'
	second := work + '/second index'
	os.write_file(first, 'P:root\nV:1\nD:virtual other\n\nP:a\nV:2\np:virtual\n')!
	os.write_file(second, 'P:a\nV:9\n\nP:other\nV:3\n')!
	for argv in [
		['--index', 'main', first, '--index', 'community', second, 'root'],
		['root', '--index=main', first, '--index', 'community', second],
		['--index', 'main', first, '--index', 'community', second, '--', 'root', '!absent'],
	] {
		mut command := [tool]
		command << argv
		result := hosttest.capture(command, '', 30, os.environ())!
		assert result.code == 0 && result.stderr == ''
		assert result.stdout == 'main\ta-2.apk\ncommunity\tother-3.apk\nmain\troot-1.apk\n'
	}
	for argv in [[]string{}, ['--index'], ['--index', 'main'], ['--index', 'main', first], ['root'],
		['--unknown'], ['--index', 'main', '--help', 'root']] {
		mut command := [tool]
		command << argv
		result := hosttest.capture(command, '', 30, os.environ())!
		assert result.code == 2 && result.stdout == '' && result.stderr != ''
	}
	for argv in [['--index', 'main', first, 'root', 'missing=4'],
		['--index', 'main', work + '/absent', 'root']] {
		mut command := [tool]
		command << argv
		result := hosttest.capture(command, '', 30, os.environ())!
		assert result.code == 1 && result.stdout == '' && result.stderr != ''
	}
	os.write_file(first, '\xff')!
	bad_utf8 := hosttest.capture([tool, '--index', 'main', first, 'root'], '', 30, os.environ())!
	assert bad_utf8.code == 1 && bad_utf8.stdout == '' && bad_utf8.stderr.contains('not valid UTF-8')
	for arg in ['-h', '--help'] {
		help := hosttest.capture([tool, arg], '', 30, os.environ())!
		assert help.code == 0 && help.stdout.contains('Usage: alpine-resolve') && help.stderr == ''
	}
}

fn test_cached_production_manifests_when_available() {
	root := os.getenv('VINIX_ALPINE_REPO')
	if root == '' { return }
	for name, requests in {
		'java':        ['openjdk25-jdk', 'ca-certificates-bundle']
		'go':          ['go', 'ca-certificates-bundle']
		'qemu-system': ['qemu-system-aarch64', 'libx11']
	} {
		build := root + '/build-aarch64-${name}'
		actual := manifest([Index{'main', build + '/downloads/main_APKINDEX'},
			Index{'community', build + '/downloads/community_APKINDEX'}], requests)!
		assert actual == os.read_file(build + '/packages')!, 'cached ${name} manifest differs'
	}
}
