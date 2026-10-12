// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidhost as ah
import androidrun
import cachecli
import hosttest
import json2
import net.unix
import os
import screenshotcore
import tarstream
import time

#include <unistd.h>
#include <fcntl.h>

fn C.link(&char, &char) int
fn C.getdtablesize() int

fn line(mut connection unix.StreamConn) !map[string]ah.Value {
	mut bytes := []u8{}
	mut buffer := []u8{len: 1}
	for {
		count := connection.read(mut buffer)!
		if count == 0 { return error('fixture EOF') }
		if buffer[0] == `\n` { break }
		bytes << buffer
	}
	return json2.decode[ah.Value](bytes.bytestr(), strict: true)!.object()
}

fn server(mut listener unix.StreamListener, mode string) ! {
	mut connection := listener.accept()!
	defer {
		connection.close() or {}
		listener.close() or {}
	}
	connection.write_string('arbitrary greeting\n')!
	assert ah.field(line(mut connection)!, 'execute').text() == 'qmp_capabilities'
	connection.write_string('{"event":"HELLO"}\n{"return":{}}\n')!
	request := line(mut connection)!
	assert ah.field(request, 'execute').text() == 'fixture-command'
	assert ah.field(ah.field(request, 'arguments').object(), 'wide') is ah.Number
	assert ah.encode(ah.field(ah.field(request, 'arguments').object(), 'wide')) == '1234567890123456789012345678901234567890'
	match mode {
		'wide' {
			connection.write_string('{"event":"IGNORE"}\n{"return":{"positive":1234567890123456789012345678901234567890,"negative":-1234567890123456789012345678901234567890,"null":null}}\n')!
		}
		'error' {
			connection.write_string('{"return":{},"error":{"class":"GenericError","desc":"controlled"}}\n')!
		}
		'json' { connection.write_string('not json\n')! }
		'utf8' { connection.write_string('{"return":"\xff"}\n')! }
		'eof' {}
		'timeout' { time.sleep(200 * time.millisecond) }
		else { return error('unknown server fixture') }
	}
}

fn qmp_cases(work string) ! {
	for mode in ['wide', 'error', 'json', 'utf8', 'eof', 'timeout'] {
		path := work + '/qmp-' + mode
		mut listener := unix.listen_stream(path)!
		mut worker := spawn server(mut listener, mode)
		mut monitor := androidrun.connect_monitor(path, if mode == 'timeout' { 0.1 } else { 5.0 })!
		mut refused := false
		value := monitor.command('fixture-command', {
			'wide': ah.Value(ah.Number{'1234567890123456789012345678901234567890'})
		}) or {
			refused = true
			ah.Value(json2.Null{})
		}
		monitor.close()
		monitor.close()
		worker.wait()!
		if os.exists(path) { os.rm(path)! }
		if mode == 'wide' {
			assert !refused
			assert ah.encode(ah.field(value.object(), 'positive')) == '1234567890123456789012345678901234567890'
			assert ah.encode(ah.field(value.object(), 'negative')) == '-1234567890123456789012345678901234567890'
		} else {
			assert refused, mode
		}
	}
}

fn archives(work string) ! {
	root := work + '/root'
	os.mkdir(root)!
	os.mkdir(root + '/usr')!
	os.mkdir(root + '/usr/lib')!
	data := 'repeatable payload '.repeat(300)
	os.write_file(root + '/usr/lib/a', data)!
	os.write_file(root + '/usr/lib/b', data)!
	os.chmod(root + '/usr/lib/a', 0o640)!
	os.chmod(root + '/usr/lib/b', 0o640)!
	assert C.link((root + '/usr/lib/a').str, (root + '/usr/lib/c').str) == 0
	os.symlink('a', root + '/usr/lib/link')!
	os.write_file(root + '/literal\\name', 'literal Unix backslash')!
	os.write_file(root + '/é', 'unicode')!
	mut context := androidrun.Context{ root: hosttest.root() }
	defer { context.close() }
	context.call('copy_layer', {
		'source':      ah.Value(root)
		'destination': ah.Value(work + '/copied')
	})!
	assert os.stat(work + '/copied/usr/lib/a')!.inode == os.stat(work + '/copied/usr/lib/c')!.inode
	assert os.readlink(work + '/copied/usr/lib/link')! == 'a'
	assert os.read_file(work + '/copied/literal\\name')! == 'literal Unix backslash'
	assert os.stat(work + '/copied/usr/lib/a')!.mode & 0o777 == 0o640
	archive := work + '/root.tar'
	context.call('archive_root', {
		'root':        ah.Value(root)
		'destination': ah.Value(archive)
	})!
	assert os.file_size(archive) % 10240 == 0
	mut reader := tarstream.open_plain(archive)!
	mut regular := 0
	mut hardlinks := 0
	mut members := []string{}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		members << member.name
		if member.kind == `1` {
			hardlinks++
			assert member.linkname == './usr/lib/a'
			assert member.size == 0
		}
		if member.regular() && member.name.starts_with('./usr/lib/') {
			regular++
			assert member.size == data.len
			assert member.mode == 0o640
		}
	}
	reader.close()
	assert regular == 1 && hardlinks == 2
	assert './literal\\name' in members
	for entry in os.ls(root)! {
		assert './' + entry in members
	}
	// Native tar -tf independently accepts the USTAR structure and end blocks.
	result := hosttest.command(['/usr/bin/tar', '-tf', archive], work + '/tar-check.log', 20, os.environ())!
	assert result.code == 0
	ppm := work + '/pixels.ppm'
	mut pixels := 'P6\n2 1\n255\n'.bytes()
	pixels << [u8(0), 1, 255, 13, 10, 32]
	os.write_file_array(ppm, pixels)!
	androidrun.encode_screenshot(ppm, work + '/pixels.png')!
	image := screenshotcore.read(work + '/pixels.png')!
	assert image.width == 2 && image.height == 1 && image.pixels == [u8(0), 1, 255, 13, 10, 32]
	for extension in ['jpg', 'bmp', 'tga'] {
		androidrun.encode_screenshot(ppm, work + '/pixels.' + extension)!
		assert os.file_size(work + '/pixels.' + extension) > 0
	}
	mut refused := false
	androidrun.encode_screenshot(ppm, work + '/pixels.unknown') or { refused = true }
	assert refused && os.exists(ppm)
}

fn input_cases() {
	assert androidrun.absolute(0, 1024) == 0
	assert androidrun.absolute(1023, 1024) == 32767
	assert androidrun.absolute(-1, 1024) == 0
	assert androidrun.absolute(9223372036854775807, 1024) == 32767
	assert androidrun.absolute(1, 3) == 16384
	assert androidrun.absolute(1, 1) == 32767
	assert androidrun.key_events('A') or { []ah.Value{} } == [
		androidrun.key_press('shift', true),
		androidrun.key_press('a', true),
		androidrun.key_press('a', false),
		androidrun.key_press('shift', false),
	]
	assert androidrun.key_events('+') or { []ah.Value{} } == [
		androidrun.key_press('shift', true),
		androidrun.key_press('equal', true),
		androidrun.key_press('equal', false),
		androidrun.key_press('shift', false),
	]
	for character in ['0', '²', '١', '𝟠'] {
		assert (androidrun.key_events(character) or { []ah.Value{} }).len == 2
	}
	for character in ['', 'é', '½', 'Ⅲ', '🦊'] {
		assert (androidrun.key_events(character) or { []ah.Value{} }).len == 0
	}
}

fn json_cases() ! {
	for source in ['null', 'true', 'false', '0', '-10', '1234567890123456789012345678901234567890',
		'NaN', 'Infinity', '-Infinity', '"escaped\\n\\t\\u00e9\\ud800"', '"\\ud83e\\udd8a"', '[1,2,3]',
		'{"duplicate":1,"duplicate":2}'] {
		value := androidrun.load_json(source)!
		assert androidrun.load_json(androidrun.dump_json(value, -1))! == value, source
	}
	assert androidrun.dump_json(androidrun.load_json('"\\ud800"')!, -1) == '"\\ud800"'
	assert androidrun.dump_json(androidrun.load_json('"\\ud83e\\udd8a"')!, -1) == '"\\ud83e\\udd8a"'
	assert androidrun.dump_json(ah.Value({
		'é': ah.Value([ah.Value(true), ah.Value(1)])
	}), 2) == '{\n  "\\u00e9": [\n    true,\n    1\n  ]\n}'
	for invalid in ['', '[1,]', '{"a":1,}', '01', '+1', '1.', '1e', '1e+', 'true false', '"\\x00"',
		'"\\u+000"', '"\\uZZZZ"', '"\x01"'] {
		mut refused := false
		androidrun.load_json(invalid) or { refused = true }
		assert refused, invalid
	}
}

fn descriptor_count() int {
	mut count := 0
	limit := C.getdtablesize()
	for descriptor in 0 .. if limit < 16384 { limit } else { 16384 } {
		if C.fcntl(descriptor, C.F_GETFD) >= 0 { count++ }
	}
	return count
}

fn archive_owners(work string) ! {
	root := work + '/bad-root'
	os.mkdir(root)!
	os.write_file(root + '/' + 'x'.repeat(201), 'x')!
	before := descriptor_count()
	for _ in 0 .. 100 {
		mut context := androidrun.Context{ root: hosttest.root() }
		mut refused := false
		context.call('archive_root', {
			'root':        ah.Value(root)
			'destination': ah.Value(work + '/failed.tar')
		}) or { refused = true }
		context.close()
		context.close()
		assert refused && os.file_size(work + '/failed.tar') == 0
	}
	assert descriptor_count() == before
	for _ in 0 .. 100 {
		mut refused := false
		androidrun.connect_monitor(work + '/absent-qmp', 0.1) or { refused = true }
		assert refused
	}
	assert descriptor_count() == before
}

fn qualify(work string) ! {
	os.mkdir(work)!
	input_cases()
	json_cases()!
	qmp_cases(work)!
	archives(work)!
	archive_owners(work)!
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE ANDROID PRIMITIVES / actual QMP wide values, event/error precedence, UTF-8, malformed JSON, EOF and deadline / USTAR hardlink and content deduplication / literal paths, copy2 identity and modes / pixel-exact native PNG / key and coordinate events: PASS')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	qualify(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
