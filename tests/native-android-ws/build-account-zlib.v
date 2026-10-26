// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the pinned upstream zlib sources and build a PIC AArch64 musl archive.
// Static/shared link checks are construction evidence; no guest execution occurs.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const archive = repo + '/build/n64/zlib-source.tar.gz'
const archive_pin = 'd9e270d46252734aa49770fbc544125391617956266f220bd63216c834f3a522'
const upstream = '51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf'
const receipt = repo + '/build-support/native-emulator-tools/emulatorbuild/core.v'
const receipt_pin = '79a97ab36f57c50019f80e81ce3286ecb2ea237ad3f1b8d9778b56840280047c'
const receipt_revision = '39bb040f06a3faa9fa88d0f9d13bbd508163b74e'
const self_source = repo + '/tests/native-android-ws/build-account-zlib.v'
const base = state + 'headless-service-native-build-2026-10-26-r5'
const base_pin = 'd99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const cross_pin = '0b1146b08ba1c285931fbe5de0121e3d39dc4f2a827174ded0fe172ffe6254dd'
const cross_root = '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/'
const units = ['adler32', 'compress', 'crc32', 'deflate', 'gzclose', 'gzlib', 'gzread', 'gzwrite',
	'inflate', 'infback', 'inftrees', 'inffast', 'trees', 'uncompr', 'zutil']
const required_exports = ['zlibVersion', 'inflateInit2_', 'inflate', 'inflateEnd', 'deflateInit2_',
	'deflateBound', 'deflate', 'deflateEnd']
const header_pins = {
	'zlib.h':  '8a5579af72ea4f427ff00a4150f0ccb3fc5c1e4379f726e101133b1ab9fc600c'
	'zconf.h': 'f5134250a67d57459234b63858f0d9d3ef8dcc48e9e1028d3f4fdcf6eae677ae'
}

fn hash(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular {
		return error('regular input required: ' + path)
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn expect_hash(actual string, expected string) ! {
	if actual != expected { return error('input digest differs') }
}

fn copy_pin(source string, target string, pin string) ! {
	expect_hash(hash(source)!, pin)!
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
	expect_hash(hash(target)!, pin)!
	expect_hash(hash(source)!, pin)!
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn unchanged(pins map[string]string) ! {
	for path, pin in pins { expect_hash(hash(path)!, pin)! }
}

fn frozen_input(path string, pin string, pins map[string]string) ! {
	if path !in pins || pins[path]! != pin {
		return error('input outside frozen dependency closure: ' + path)
	}
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + relative)!
	names.sort()
	for name in names {
		key := if relative == '' { name } else { relative + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular bundle entry: ' + key) }
		}
	}
}

fn check_bundle(root string, pin string) ! {
	if pin.len != 64 || !pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('invalid bundle seal')
	}
	expect_hash(hash(root + '/sha256.json')!, pin)!
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	if actual != expected { return error('bundle entries or digests differ') }
}

fn command(root string, label string, argv []string) !string {
	executable := os.real_path(if argv[0].contains('/') {
		argv[0]
	} else {
		os.find_abs_path_of_executable(argv[0])!
	})
	pin := hash(executable)!
	mut fields := {
		'argv':              json2.Any(argv)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'cwd':               json2.Any(os.getwd())
		'started_utc':       json2.Any(time.utc().str())
	}
	write_json(root + '/commands/' + label + '-before.json', fields)!
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	fields['exit_code'] = r.exit_code
	fields['completed_utc'] = time.utc().str()
	write_json(root + '/commands/' + label + '.json', fields)!
	expect_hash(hash(executable)!, pin)!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
	return r.output
}

fn build_argv(parts [][]string) []string {
	mut result := []string{}
	for part in parts { result << part }
	return result
}

fn archive_listing(names string, details string) ! {
	prefix := 'zlib-' + upstream + '/'
	mut seen := map[string]bool{}
	for name in names.split_into_lines() {
		if !name.starts_with(prefix) || name.contains('..') || name.contains('//')
			|| name.bytes().any(it.is_space()) || name in seen {
			return error('unexpected source archive member')
		}
		seen[name] = true
	}
	if seen.len < units.len || prefix + 'zlib.h' !in seen || prefix + 'zconf.h' !in seen {
		return error('incomplete source archive')
	}
	lines := details.split_into_lines()
	if lines.len != seen.len || lines.any(it.len == 0 || it[0] !in [`-`, `d`]) {
		return error('nonregular source archive member')
	}
}

fn dependency_paths(text string) ![]string {
	colon := text.index(':') or { return error('missing dependency target') }
	mut paths := []string{}
	mut token := ''
	mut escaped := false
	for ch in text[colon + 1..].bytes() {
		if escaped {
			if ch != `\n` { token += ch.ascii_str() }
			escaped = false
		} else if ch == `\\` {
			escaped = true
		} else if ch.is_space() {
			if token != '' {
				paths << token
				token = ''
			}
		} else {
			token += ch.ascii_str()
		}
	}
	if escaped { return error('unterminated dependency escape') }
	if token != '' { paths << token }
	if paths.len == 0 { return error('empty dependency closure') }
	return paths
}

fn elf(bytes []u8, kind u8) ! {
	if bytes.len < 64 || bytes[..4] != [u8(127), `E`, `L`, `F`]
		|| bytes[4] != 2 || bytes[5] != 1 || bytes[6] != 1
		|| bytes[16] != kind || bytes[17] != 0 || bytes[18] != 183 || bytes[19] != 0 {
		return error('expected AArch64 little endian ELF64 object/type')
	}
}

fn archive_members(text string) ![]string {
	names := text.split_into_lines()
	mut expected := units.map(it + '.o')
	expected.sort()
	mut actual := names.clone()
	actual.sort()
	if actual != expected { return error('foreign, missing or duplicate static archive member') }
	return names
}

fn exports(text string) ! {
	mut found := map[string]bool{}
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len >= 3 && fields[fields.len - 2] == 'T' { found[fields.last()] = true }
	}
	for symbol in required_exports {
		if symbol !in found { return error('missing required zlib export: ' + symbol) }
	}
}

fn admit(root string, path string, trusted map[string]string, mut pins map[string]string) !string {
	canonical := os.real_path(path)
	if !canonical.starts_with(cross_root) {
		return error('input outside pinned cross toolchain: ' + path)
	}
	pin := hash(canonical)!
	if canonical in trusted { expect_hash(pin, trusted[canonical]!)! }
	if canonical in pins {
		expect_hash(pin, pins[canonical]!)!
		return canonical
	}
	copy_pin(canonical, root + '/inputs/cross/' + canonical.trim_left('/'), pin)!
	pins[canonical] = pin
	return canonical
}

fn headers(root string, label string, argv []string, source_pins map[string]string,
	trusted map[string]string, mut cross_pins map[string]string, discover bool) !map[string]string {
	mut consumed := map[string]string{}
	for path in dependency_paths(command(root, label, argv)!)! {
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical in source_pins {
			expect_hash(pin, source_pins[canonical]!)!
		} else if discover {
			admit(root, canonical, trusted, mut cross_pins)!
		} else {
			frozen_input(canonical, pin, cross_pins)!
		}
		consumed[canonical] = pin
	}
	write_json(root + '/dependencies/' + label + '.json', consumed)!
	return consumed
}

fn link_inputs(text string, required []string, cross_pins map[string]string) !map[string]string {
	mut consumed := map[string]string{}
	for line in text.split_into_lines() {
		path := line.trim_space()
		if !path.starts_with('/') || !os.is_file(path) { continue }
		canonical := os.real_path(path)
		pin := hash(canonical)!
		frozen_input(canonical, pin, cross_pins)!
		consumed[canonical] = pin
	}
	for path in required {
		if path !in consumed { return error('required explicit link input missing') }
	}
	if consumed.len < 5 { return error('incomplete link trace') }
	return consumed
}

fn smoke_source() string {
	return '#include "zlib.h"\nint main(void) {\n' +
		'unsigned char in[1]={65}, compressed[64]={0}, out[1]={0};\n' +
		'z_stream enc={0}, dec={0};\n' +
		'if(deflateInit2_(&enc,6,Z_DEFLATED,-15,8,0,zlibVersion(),sizeof(enc))) return 1;\n' +
		'if(deflateBound(&enc,1)>64) return 2;\n' +
		'enc.next_in=in; enc.avail_in=1; enc.next_out=compressed; enc.avail_out=64;\n' +
		'if(deflate(&enc,Z_FINISH)!=Z_STREAM_END) return 3;\n' +
		'unsigned len=enc.total_out; if(deflateEnd(&enc)) return 4;\n' +
		'if(inflateInit2_(&dec,-15,zlibVersion(),sizeof(dec))) return 5;\n' +
		'dec.next_in=compressed; dec.avail_in=len; dec.next_out=out; dec.avail_out=1;\n' +
		'if(inflate(&dec,Z_FINISH)!=Z_STREAM_END || out[0]!=65) return 6;\n' +
		'return inflateEnd(&dec);\n}\n'
}

fn build(root string) ! {
	if !root.starts_with(state + 'account-zlib-static-build-') || root.bytes().any(it.is_space())
		|| os.exists(root) || os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) {
		return error('fresh canonical external zlib build root required')
	}
	expect_hash(hash(archive)!, archive_pin)!
	expect_hash(hash(receipt)!, receipt_pin)!
	expect_hash(hash(base + '/sha256.json')!, base_pin)!
	expect_hash(hash(os.real_path(cross))!, cross_pin)!
	for name in ['CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH', 'GCC_EXEC_PREFIX',
		'COMPILER_PATH', 'LIBRARY_PATH'] {
		os.unsetenv(name)
	}
	os.setenv('LC_ALL', 'C', true)
	for name in ['commands', 'inputs', 'source', 'objects', 'native', 'lib', 'dependencies',
		'archive-members', 'smoke'] {
		os.mkdir_all(root + '/' + name)!
	}
	builder_path := os.real_path(os.executable())
	builder_pin := hash(builder_path)!
	mut originals := {
		archive:     archive_pin
		receipt:     receipt_pin
		self_source: hash(self_source)!
	}
	originals[builder_path] = builder_pin
	copy_pin(archive, root + '/inputs/zlib-source.tar.gz', archive_pin)!
	copy_pin(receipt, root + '/inputs/upstream-receipt.v', receipt_pin)!
	copy_pin(self_source, root + '/builder-source.v', originals[self_source]!)!
	copy_pin(builder_path, root + '/builder', builder_pin)!
	copy_pin(base + '/sha256.json', root + '/baseline-sha256.json', base_pin)!
	base_pins := json2.decode[map[string]string](os.read_file(root + '/baseline-sha256.json')!)!
	copy_pin(base + '/reused-inputs.json', root + '/baseline-reused-inputs.json', base_pins['reused-inputs.json']!)!
	copy_pin(base + '/native351/crosscompiler-specs.txt', root + '/crosscompiler-specs.txt', base_pins['native351/crosscompiler-specs.txt']!)!
	reused := json2.decode[map[string]string](os.read_file(root + '/baseline-reused-inputs.json')!)!
	mut trusted := map[string]string{}
	for path, pin in reused {
		if !path.starts_with('/opt/homebrew/') { continue }
		canonical := os.real_path(path)
		if canonical in trusted && trusted[canonical]! != pin {
			return error('conflicting sealed cross inputs')
		}
		trusted[canonical] = pin
	}
	mut cross_pins := map[string]string{}
	if os.real_path(cross) !in trusted || trusted[os.real_path(cross)]! != cross_pin {
		return error('compiler absent from pinned r5 input closure')
	}
	admit(root, cross, trusted, mut cross_pins)!
	if command(root, 'cross-specs', [cross, '-dumpspecs'])! != os.read_file(root + '/crosscompiler-specs.txt')! {
		return error('cross compiler specs differ')
	}
	mut tools := map[string]string{}
	for name in ['cc1', 'collect2', 'as', 'ld', 'ar', 'nm', 'readelf'] {
		path := command(root, 'cross-tool-' + name, [cross, '-print-prog-name=' + name])!.trim_space()
		canonical := admit(root, path, trusted, mut cross_pins)!
		if name in ['cc1', 'collect2', 'as', 'ld'] && canonical !in trusted {
			return error('compiler subtool absent from sealed r5 inputs')
		}
		tools[name] = canonical
	}
	for name in ['crt1.o', 'Scrt1.o', 'crti.o', 'crtbegin.o', 'crtbeginS.o', 'crtbeginT.o', 'crtend.o',
		'crtendS.o', 'crtn.o', 'libgcc.a', 'libgcc_eh.a', 'libgcc_s.so', 'libgcc_s.so.1', 'libc.so',
		'libc.a', 'libm.a', 'libpthread.a', 'libdl.a'] {
		path := command(root, 'cross-resource-' + name, [cross, '-print-file-name=' + name])!.trim_space()
		admit(root, path, trusted, mut cross_pins)!
	}
	for path in ['/usr/bin/tar', '/usr/bin/git'] {
		canonical := os.real_path(path)
		originals[canonical] = hash(canonical)!
		copy_pin(canonical, root + '/inputs/host-tools/' + os.file_name(path), originals[canonical]!)!
	}
	command(root, 'self-test', [root + '/builder', '--self-test'])!
	revision := command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()
	names := command(root, 'source-members', ['/usr/bin/tar', '-tzf',
		root + '/inputs/zlib-source.tar.gz'])!
	details := command(root, 'source-member-types', ['/usr/bin/tar', '-tvzf',
		root + '/inputs/zlib-source.tar.gz'])!
	archive_listing(names, details)!
	command(root, 'extract-source', ['/usr/bin/tar', '-xzf', root + '/inputs/zlib-source.tar.gz',
		'-C', root + '/source', '--strip-components', '1'])!
	mut source_relative := map[string]string{}
	inventory(root + '/source', '', mut source_relative)!
	mut source_pins := map[string]string{}
	for relative, pin in source_relative { source_pins[root + '/source/' + relative] = pin }
	write_json(root + '/source-inputs.json', source_pins)!
	for name, pin in header_pins {
		copy_pin(root + '/source/' + name, root + '/native/' + name, pin)!
	}
	flags := ['-D_GNU_SOURCE', '-DHAVE_UNISTD_H', '-DHAVE_STDARG_H', '-O2', '-fPIC', '-fwrapv',
		'-Werror=implicit-function-declaration', '-Werror=int-conversion', '-I' + root + '/source']
	mut dependency_sets := map[string]map[string]string{}
	for unit in units {
		dependency_sets[unit] = headers(root, unit + '-discover', build_argv([[cross], flags,
			['-M', '-MT', unit, root + '/source/' + unit + '.c']]), source_pins, trusted, mut cross_pins, true)!
	}
	os.write_file(root + '/smoke/roundtrip.c', smoke_source())!
	source_pins[root + '/smoke/roundtrip.c'] = hash(root + '/smoke/roundtrip.c')!
	write_json(root + '/source-inputs.json', source_pins)!
	dependency_sets['smoke'] = headers(root, 'smoke-discover', build_argv([[cross], flags,
		['-M', '-MT', 'smoke', root + '/smoke/roundtrip.c']]), source_pins, trusted, mut cross_pins, true)!
	write_json(root + '/cross-inputs.json', cross_pins)!
	unchanged(cross_pins)!
	mut objects := []string{}
	mut compile_units := units.clone()
	compile_units << 'smoke'
	for unit in compile_units {
		source := if unit == 'smoke' {
			root + '/smoke/roundtrip.c'
		} else {
			root + '/source/' + unit + '.c'
		}
		dep_argv := build_argv([[cross], flags, ['-M', '-MT', unit, source]])
		if headers(root, unit + '-before', dep_argv, source_pins, trusted, mut cross_pins, false)! != dependency_sets[unit]! {
			return error('header dependency set changed before compile')
		}
		object := root + '/objects/' + unit + '.o'
		command(root, 'compile-' + unit, build_argv([[cross], flags, ['-c', source, '-o', object]]))!
		elf(os.read_bytes(object)!, 1)!
		if headers(root, unit + '-after', dep_argv, source_pins, trusted, mut cross_pins, false)! != dependency_sets[unit]! {
			return error('header dependency set changed during compile')
		}
		if unit != 'smoke' { objects << object }
	}
	unchanged(cross_pins)!
	unchanged(source_pins)!
	library := root + '/lib/libz.a'
	command(root, 'archive', build_argv([[tools['ar']!, 'rcsD', library], objects]))!
	if os.read_bytes(library)![..8] != '!<arch>\n'.bytes() {
		return error('ordinary static archive required')
	}
	members := archive_members(command(root, 'archive-members', [tools['ar']!, 't', library])!)!
	previous := os.getwd()
	os.chdir(root + '/archive-members')!
	command(root, 'extract-members', [tools['ar']!, 'x', library])!
	os.chdir(previous)!
	mut member_pins := map[string]string{}
	for name in members {
		path := root + '/archive-members/' + name
		elf(os.read_bytes(path)!, 1)!
		expect_hash(hash(path)!, hash(root + '/objects/' + name)!)!
		member_pins[name] = hash(path)!
	}
	write_json(root + '/archive-members.json', member_pins)!
	exports(command(root, 'archive-exports', [tools['nm']!, '-g', '--defined-only', library])!)!
	mut link_pins := cross_pins.clone()
	link_pins[library] = hash(library)!
	link_pins[root + '/objects/smoke.o'] = hash(root + '/objects/smoke.o')!
	for mode in ['static', 'shared'] {
		output := root + '/smoke/' + mode
		mode_flags := if mode == 'static' {
			['-static', '-no-pie']
		} else {
			['-shared', '-Wl,-z,defs']
		}
		argv := build_argv([[cross], mode_flags, ['-Wl,-t', root + '/objects/smoke.o',
			'-Wl,--whole-archive', library, '-Wl,--no-whole-archive', '-o', output]])
		consumed := link_inputs(command(root, 'link-' + mode, argv)!, [library,
			root + '/objects/smoke.o'], link_pins)!
		write_json(root + '/dependencies/link-' + mode + '.json', consumed)!
		elf(os.read_bytes(output)!, if mode == 'static' { u8(2) } else { u8(3) })!
		dynamic := command(root, mode + '-dynamic', [tools['readelf']!, '-d', output])!
		if dynamic.contains('(NEEDED)') && (mode == 'static' || dynamic.contains('[libz.so')) {
			return error('unexpected dynamic zlib/static smoke dependency')
		}
	}
	unchanged(link_pins)!
	unchanged(source_pins)!
	unchanged(originals)!
	for path, pin in cross_pins {
		expect_hash(hash(root + '/inputs/cross/' + path.trim_left('/'))!, pin)!
	}
	for name, pin in header_pins { expect_hash(hash(root + '/native/' + name)!, pin)! }
	for name, pin in member_pins {
		expect_hash(hash(root + '/objects/' + name)!, pin)!
		expect_hash(hash(root + '/archive-members/' + name)!, pin)!
	}
	expect_hash(hash(root + '/inputs/zlib-source.tar.gz')!, archive_pin)!
	expect_hash(hash(root + '/inputs/upstream-receipt.v')!, receipt_pin)!
	expect_hash(hash(root + '/builder-source.v')!, originals[self_source]!)!
	expect_hash(hash(root + '/builder')!, builder_pin)!
	expect_hash(hash(root + '/baseline-sha256.json')!, base_pin)!
	expect_hash(hash(root + '/baseline-reused-inputs.json')!, base_pins['reused-inputs.json']!)!
	expect_hash(hash(root + '/crosscompiler-specs.txt')!, base_pins['native351/crosscompiler-specs.txt']!)!
	for path in ['/usr/bin/tar', '/usr/bin/git'] {
		expect_hash(hash(root + '/inputs/host-tools/' + os.file_name(path))!, originals[os.real_path(path)]!)!
	}
	expect_hash(hash(base + '/sha256.json')!, base_pin)!
	write_json(root + '/original-inputs.json', originals)!
	mut outputs := map[string]string{}
	for path in ['lib/libz.a', 'native/zlib.h', 'native/zconf.h'] {
		outputs[path] = hash(root + '/' + path)!
	}
	write_json(root + '/build.json', {
		'kind':                      json2.Any('vinix-account-zlib-static-v1')
		'scope':                     json2.Any('Retained upstream zlib, AArch64 PIC static archive and static/shared whole-archive link checks; no runtime or Google account claim. Host SDK/dynamic loader libraries remain environmental inputs.')
		'source_revision':           json2.Any(revision)
		'upstream_revision':         json2.Any(upstream)
		'upstream_url':              json2.Any('https://codeload.github.com/madler/zlib/tar.gz/' + upstream)
		'upstream_receipt_revision': json2.Any(receipt_revision)
		'upstream_receipt_sha256':   json2.Any(receipt_pin)
		'source_archive_sha256':     json2.Any(archive_pin)
		'version':                   json2.Any('1.3.1')
		'architecture':              json2.Any('aarch64')
		'pic':                       json2.Any(true)
		'compiler_sha256':           json2.Any(cross_pin)
		'native_base_sha256':        json2.Any(base_pin)
		'outputs_sha256':            json2.decode[json2.Any](json2.encode(outputs))!
	})!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	write_json(root + '/sha256.json', pins)!
	seal := hash(root + '/sha256.json')!
	check_bundle(root, seal)!
	println('ACCOUNT-ZLIB-STATIC-BUILD-PASS bundle=' + root + ' seal=' + seal)
}

fn self_test() ! {
	expect_hash('wrong', archive_pin) or {
		mut bytes := []u8{len: 64}
		bytes[0] = 127
		bytes[1] = 69
		bytes[2] = 76
		bytes[3] = 70
		bytes[4] = 2
		bytes[5] = 1
		bytes[6] = 1
		bytes[16] = 1
		bytes[18] = 183
		elf(bytes, 1)!
		for at in [0, 4, 5, 6, 16, 17, 18, 19] {
			mut bad := bytes.clone()
			bad[at] = 255
			elf(bad, 1) or { continue }
			return error('foreign ELF accepted')
		}
		good := units.map(it + '.o').join('\n') + '\n'
		archive_members(good)!
		for bad in [good + 'foreign.o\n', good + 'inflate.o\n', good.replace('inflate.o\n', ''),
			good.replace('inflate.o', '../inflate.o')] {
			archive_members(bad) or { continue }
			return error('foreign/missing/duplicate archive member accepted')
		}
		listing := required_exports.map('00000000 T ' + it).join('\n')
		exports(listing)!
		for name in required_exports {
			exports(listing.replace(' T ' + name + '\n', ' U ' + name + '\n').replace(' T ' + name, ' U ' + name)) or { continue }
			return error('missing zlib export accepted')
		}
		if dependency_paths('x: /one /path\\ with\\ spaces \\\n /last')! != ['/one', '/path with spaces',
			'/last'] {
			return error('dependency escape parser differs')
		}
		for text in ['missing target', 'x:', 'x: /last\\'] {
			dependency_paths(text) or { continue }
			return error('malformed dependency listing accepted')
		}
		mut source_members := units.map('zlib-' + upstream + '/' + it + '.c')
		source_members << 'zlib-' + upstream + '/zlib.h'
		source_members << 'zlib-' + upstream + '/zconf.h'
		source_names := source_members.join('\n')
		source_details := source_members.map('-rw-r--r-- ' + it).join('\n')
		archive_listing(source_names, source_details)!
		mut rejected_type := false
		archive_listing(source_names, source_details.replace('-rw-r--r--', 'lrwxr-xr-x')) or { rejected_type = true }
		if !rejected_type { return error('source archive symlink accepted') }
		for names in ['../outside', '/absolute', 'zlib-' + upstream + '/../outside'] {
			archive_listing(names, '-rw-r--r-- entry') or { continue }
			return error('unsafe source archive accepted')
		}
		known := {
			'/header.h': 'header-pin'
			'/tool':     'tool-pin'
		}
		frozen_input('/header.h', 'header-pin', known)!
		for row in [['/extra.h', 'header-pin'], ['/header.h', 'changed'],
			['/unknown-tool', 'tool-pin'], ['/tool', 'changed']] {
			frozen_input(row[0], row[1], known) or { continue }
			return error('unpinned or changed header/tool accepted')
		}
		self_test_seal()!
		println('ACCOUNT-ZLIB-STATIC-SELF-TEST-PASS digest, ELF ABI, archive membership, exports, dependency escapes, frozen inputs and bundle archive/header drift')
		return
	}
	return error('wrong source archive digest accepted')
}

fn self_test_seal() ! {
	root := os.join_path(os.temp_dir(), 'vinix-account-zlib-self-test-' + os.getpid().str() + '-' + time.now().unix_nano().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	for path in ['lib/libz.a', 'native/zlib.h', 'native/zconf.h'] {
		os.mkdir_all(os.dir(root + '/' + path))!
		os.write_file(root + '/' + path, 'fixture:' + path)!
	}
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	write_json(root + '/sha256.json', pins)!
	seal := hash(root + '/sha256.json')!
	check_bundle(root, seal)!
	for path in ['lib/libz.a', 'native/zlib.h', 'native/zconf.h'] {
		os.write_file(root + '/' + path, 'changed')!
		mut rejected := false
		check_bundle(root, seal) or { rejected = true }
		if !rejected { return error('changed retained archive/header accepted') }
		os.write_file(root + '/' + path, 'fixture:' + path)!
	}
	os.write_file(root + '/extra', 'unsealed')!
	mut rejected := false
	check_bundle(root, seal) or { rejected = true }
	if !rejected { return error('unsealed extra input accepted') }
	os.rm(root + '/extra')!
	os.rm(root + '/native/zlib.h')!
	check_bundle(root, seal) or { return }
	return error('missing retained header accepted')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 4 && os.args[1] == '--check' {
		check_bundle(os.abs_path(os.args[2]), os.args[3]) or {
			eprintln(err)
			exit(1)
		}
		println('ACCOUNT-ZLIB-STATIC-INTEGRITY-PASS ' + os.args[3])
		return
	}
	if os.args.len != 2 {
		eprintln('usage: build-account-zlib FRESH_OUTPUT | --self-test | --check BUNDLE SHA256')
		exit(2)
	}
	build(os.abs_path(os.args[1])) or {
		eprintln(err)
		exit(1)
	}
}
