module androidhost

import encoding.hex
import json2
import os

fn C.mkdtemp(&char) &char

fn test_original_deterministic_probe_archive_bytes() {
	fixture := json2.decode[Value](os.read_file(os.join_path(os.dir(@FILE), 'testdata/probe-archives.json'))!)!.object()
	for value in field(fixture, 'cases').items() {
		row := value.object()
		mut items := []ProbePayload{}
		for item_value in field(row, 'items').items() {
			item := item_value.object()
			items << ProbePayload{text(item, 'name')!, hex.decode(text(item, 'data')!)!, u32(integer(field(item, 'mode')) or { panic('fixture mode is not an integer') })}
		}
		archive := make_probe_zip(items)!
		assert archive.hex() == text(row, 'archive')!, text(row, 'name')!
		zip := parse_probe_zip(archive)!
		assert zip.entries.map(it.name) == items.map(it.name)
		for item in items {
			assert zip.read_name(item.name)! == item.data
		}
	}
}

fn test_original_provider_name_rules() {
	for kind, class in {
		'lifecycle': 'AndroidActivityLifecycleProbe'
		'cookie':    'AndroidCookieProbe'
		'autofill':  'AndroidAutofillProbe'
		'location':  'AndroidLocationProbe'
	} {
		prefix := (if kind == 'lifecycle' { 'android/app/' } else { 'org/vinix/tests/' }) + class
		assert probe_class_valid(kind, prefix + '.class', class)
		assert probe_class_valid(kind, prefix + '$Inner$123_ABC.class', class)
		assert !probe_class_valid(kind, 'other/' + class + '.class', class)
		for suffix in ['Extra.class', '$.class', '$No-Hyphen.class', '/Nested.class', '$δ.class'] {
			assert probe_class_valid(kind, prefix + suffix, class) == (kind in [
				'lifecycle',
				'cookie',
			])
		}
	}
}

fn test_archive_headers_check_bounds_before_decoding() {
	for data in [[]u8{}, 'not a zip'.bytes(), [u8(0x50), 0x4b, 5, 6]] {
		parse_probe_zip(data) or {
			assert err is ZipError
			continue
		}
		assert false
	}
	archive := make_probe_zip([ProbePayload{'classes.dex', 'dex fixture'.bytes(), 0o600}])!
	for length in [0, 4, 21, archive.len - 1] {
		parse_probe_zip(archive[..length]) or {
			assert err is ZipError
			continue
		}
		assert false
	}
}

fn test_compiler_exec_failures_and_signal_status() {
	for argv, expected in {
		['/bin/sh', '-c', 'exit 47'].join('\x01'):       47
		['/bin/sh', '-c', 'kill -TERM $$'].join('\x01'): -15
	} {
		arguments := argv.split('\x01')
		probe_command(arguments) or {
			assert err is ProbeCommandError
			assert err.arguments == arguments
			assert err.status == expected
			continue
		}
		assert false
	}
	missing := '/vinix-probe-missing-compiler'
	probe_command([missing]) or {
		assert err is FileError && err.number == C.ENOENT && err.filename == missing
		return
	}
	assert false
}

fn test_compilers_restore_interpreter_ignored_signals() {
	for signal in [C.SIGPIPE, C.VINIX_PROBE_SIGXFZ, C.VINIX_PROBE_SIGXFSZ] {
		if signal == 0 { continue }
		previous := unsafe { C.signal(i32(signal), C.SIG_IGN) }
		probe_command(['/bin/sh', '-c', 'kill -"$1" $$; exit 77', '--', signal.str()]) or {
			unsafe { C.signal(i32(signal), previous) }
			assert err is ProbeCommandError && err.status == -signal
			continue
		}
		unsafe { C.signal(i32(signal), previous) }
		assert false
	}
}

fn test_compilers_close_inherited_nonstandard_descriptors() {
	mut template := (os.temp_dir().trim_right('/') + '/vinix-probe-fds-XXXXXX\x00').bytes()
	assert !isnil(C.mkdtemp(&char(template.data)))
	directory := template[..template.len - 1].bytestr()
	defer { os.rmdir_all(directory) or { panic(err) } }
	baseline := os.ls('/dev/fd')!.len
	mut files := []os.File{}
	defer {
		for mut file in files { file.close() }
	}
	for index in 0 .. 70 { files << os.create(directory + '/' + index.str())! }
	fd := files.last().fd
	assert fd >= 64
	probe_command(['/bin/sh', '-c', 'test ! -e /dev/fd/"$1"', '--', fd.str()])!
	for mut file in files { file.close() }
	assert os.ls('/dev/fd')!.len == baseline
	for _ in 0 .. 100 {
		probe_command(['/vinix-probe-missing-compiler']) or {
			assert err is FileError
			continue
		}
		assert false
	}
	assert os.ls('/dev/fd')!.len == baseline
}
