module androidhost

import os
import encoding.hex
import json2

struct ProbeCaptureError {
	arguments []string
	status    int
	output    string
}

fn (e ProbeCaptureError) msg() string { return 'Captured compiler command failed' }

fn (e ProbeCaptureError) code() int { return e.status }

struct ProbeDecodeError {
	data   []u8
	start  int
	end    int
	reason string
}

fn (e ProbeDecodeError) msg() string { return e.reason }

fn (e ProbeDecodeError) code() int { return 0 }

fn advanced_utf8_length(bytes []u8, at int) int {
	ch := bytes[at]
	length := if ch < 0x80 {
		1
	} else if ch >= 0xc2 && ch <= 0xdf {
		2
	} else if ch >= 0xe0 && ch <= 0xef {
		3
	} else if ch >= 0xf0 && ch <= 0xf4 {
		4
	} else {
		0
	}
	if length == 0 || bytes.len - at < length { return 0 }
	for offset in 1 .. length {
		byte := bytes[at + offset]
		if byte < 0x80 || byte > 0xbf || (offset == 1 && ((ch == 0xe0 && byte < 0xa0) || (ch == 0xed && byte > 0x9f) || (ch == 0xf0 && byte < 0x90) || (ch == 0xf4 && byte > 0x8f))) {
			return 0
		}
	}
	return length
}

fn advanced_decode(bytes []u8) !string {
	mut index := 0
	for index < bytes.len {
		ch := bytes[index]
		length := if ch < 0x80 {
			1
		} else if ch >= 0xc2 && ch <= 0xdf {
			2
		} else if ch >= 0xe0 && ch <= 0xef {
			3
		} else if ch >= 0xf0 && ch <= 0xf4 {
			4
		} else {
			0
		}
		if length == 0 {
			return ProbeDecodeError{bytes.clone(), index, index + 1, 'invalid start byte'}
		}
		for offset in 1 .. length {
			if index + offset >= bytes.len {
				return ProbeDecodeError{bytes.clone(), index, bytes.len, 'unexpected end of data'}
			}
			byte := bytes[index + offset]
			if byte < 0x80 || byte > 0xbf || (offset == 1 && ((ch == 0xe0 && byte < 0xa0) || (ch == 0xed && byte > 0x9f) || (ch == 0xf0 && byte < 0x90) || (ch == 0xf4 && byte > 0x8f))) {
				return ProbeDecodeError{bytes.clone(), index, index + offset, 'invalid continuation byte'}
			}
		}
		index += length
	}
	return bytes.bytestr()
}

fn advanced_quote(value string) string {
	// Filesystem strings use Python's surrogateescape for non-UTF-8 bytes.
	bytes := value.bytes()
	mut result := '"'
	mut cursor := 0
	for cursor < bytes.len {
		width := advanced_utf8_length(bytes, cursor)
		if width == 0 {
			result += '\\u${(0xdc00 + u32(bytes[cursor])):04x}'
			cursor++
			continue
		}
		quoted := probe_quote(bytes[cursor..cursor + width].bytestr())
		result += quoted[1..quoted.len - 1]
		cursor += width
	}
	return result + '"'
}

fn advanced_json(value Value, depth int) string {
	padding := '  '.repeat(depth + 1)
	closing := '  '.repeat(depth)
	return match value {
		string { advanced_quote(value) }
		[]Value {
			if value.len == 0 {
				'[]'
			} else {
				'[\n' + value.map(padding + advanced_json(it, depth + 1)).join(',\n') + '\n' + closing + ']'
			}
		}
		map[string]Value {
			mut rows := []string{}
			for key, item in value {
				rows << padding + advanced_quote(key) + ': ' + advanced_json(item, depth + 1)
			}
			if rows.len == 0 { '{}' } else { '{\n' + rows.join(',\n') + '\n' + closing + '}' }
		}
		else { encode(value) }
	}
}

fn advanced_write(path string, value Value) ! {
	os.write_file(path, advanced_json(value, 0) + '\n') or { return file_error(path) }
}

pub fn advanced_native_elf(path string) ! {
	data := probe_bytes(path)!
	if data.len < 6 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] {
		return ProbeExit{'fixture native library is not an ARM64 little-endian ELF'}
	}
	needed_unpack(data, 18, 2)!
	if elf_u16(data, 18) != 183 {
		return ProbeExit{'fixture native library is not an ARM64 little-endian ELF'}
	}
	needed_unpack(data, 32, 8)!
	headers := elf_u64(data, 32)
	needed_unpack(data, 54, 4)!
	size := u64(elf_u16(data, 54))
	count := u64(elf_u16(data, 56))
	mut loads := 0
	for index := u64(0); index < count; index++ {
		delta := index * size
		if headers > 0x7fffffffffffffff || delta > 0x7fffffffffffffff - headers {
			return error('OverflowError: Python int too large to convert to C ssize_t')
		}
		at := headers + delta
		needed_unpack(data, at, 56)!
		kind := elf_u32(data, int(at))
		offset := elf_u64(data, int(at) + 8)
		address := elf_u64(data, int(at) + 16)
		filesz := elf_u64(data, int(at) + 32)
		align := elf_u64(data, int(at) + 48)
		if kind == 1 {
			loads++
			if align < 16384 || offset % 16384 != address % 16384 {
				return ProbeExit{'fixture native library cannot load with 16 KiB pages'}
			}
		}
		if kind == 2 {
			for consumed := u64(0); consumed < filesz; consumed += 16 {
				if offset > 0x7fffffffffffffff || consumed > 0x7fffffffffffffff - offset {
					return error('OverflowError: Python int too large to convert to C ssize_t')
				}
				position := offset + consumed
				needed_unpack(data, position, 16)!
				tag := elf_u64(data, int(position))
				if tag == 0 { break }
				if tag == 1 {
					return ProbeExit{'fixture must import platform APIs without a host-library DT_NEEDED'}
				}
			}
		}
	}
	if loads == 0 { return ProbeExit{'fixture native library has no loadable segments'} }
}

fn advanced_classes(root string, mut paths []string) {
	for name in os.ls(root) or { return } {
		path := path_join(root, name)
		if name.ends_with('.class') { paths << path }
		if os.is_dir(path) && !os.is_link(path) { advanced_classes(path, mut paths) }
	}
}

fn advanced_archive(path string, root string, class string, split bool) ! {
	mut stream := os.create(path) or { return file_error(path) }
	defer { stream.close() }
	mut paths := []string{}
	advanced_classes(root, mut paths)
	paths.sort()
	mut output := []u8{}
	mut central := []u8{}
	mut published := 0
	mut count := 0
	for fullpath in paths {
		name := fullpath[root.len + 1..]
		if !probe_class_valid('autofill', name, class) {
			finish_probe_zip(mut output, central, count, []u8{})!
			write_probe_bytes(mut stream, output[published..])!
			return ProbeExit{if split {
				'fixture contains an unexpected provider class'
			} else {
				'fixture contains a class outside its own app'
			}}
		}
		data := probe_bytes(fullpath) or {
			finish_probe_zip(mut output, central, count, []u8{})!
			write_probe_bytes(mut stream, output[published..])!
			return err
		}
		central << add_probe_entry(mut output, ProbePayload{name, data, 0o600})!
		write_probe_bytes(mut stream, output[published..])!
		published = output.len
		count++
	}
	finish_probe_zip(mut output, central, count, []u8{})!
	write_probe_bytes(mut stream, output[published..])!
	if split && count == 0 { return ProbeExit{'fixture contains no classes'} }
}

fn advanced_clear_classes(classes string) ! {
	if os.exists(classes) {
		if os.is_link(classes) {
			return ProbeFilesystemError{'Cannot call rmtree on a symbolic link'}
		}
		if !os.is_dir(classes) {
			return FileError{ message: os.get_error_msg(C.ENOTDIR), number: int(C.ENOTDIR), filename: classes, filename_is_path: true }
		}
		state := os.lstat(classes) or { return file_error(classes) }
		remove_probe_tree_at(C.AT_FDCWD, classes, classes, state.dev, state.inode)!
	}
	if C.mkdir(classes.str, 0o777) != 0 { return file_error(classes) }
}

fn advanced_append_dex(dex_path string, apk_path string, split bool, native string) ! {
	dex := read_probe_zip(dex_path)!
	mut apk := open_probe_append(apk_path)!
	defer { apk.stream.close() }
	if dex.entries.map(it.name) != ['classes.dex'] {
		if apk.new_archive { apk.publish(none)! }
		return ProbeExit{if split {
			'unexpected D8 payload'
		} else {
			'fixture D8 archive contains unexpected entries'
		}}
	}
	data := dex.read_name('classes.dex') or {
		if apk.new_archive { apk.publish(none)! }
		return err
	}
	apk.publish(ProbePayload{'classes.dex', data, 0o600})!
	if !split {
		apk.publish(ProbePayload{'lib/arm64-v8a/libvinix_egl_queue_probe.so', probe_bytes(native)!, 0o600})!
	}
}

fn advanced_apk_names(path string) ![]string { return read_probe_zip(path)!.entries.map(it.name) }

pub fn build_advanced_probe_with_pins(row map[string]Value, r8_pin string, core_pin string) ! {
	split := text(row, 'kind')! == 'split'
	r8 := text(row, 'r8')!
	core := text(row, 'core_classes')!
	ordered := if split { [core, r8] } else { [r8, core] }
	pins := if split { [core_pin, r8_pin] } else { [r8_pin, core_pin] }
	for index, path in ordered {
		if digest(path)! != pins[index] {
			return ProbeExit{'pinned compiler input mismatch: ' + path}
		}
	}
	mut target := ''
	cc := text(row, 'cc')!
	if !split {
		target = advanced_strip(probe_command_output_preferred([cc, '-dumpmachine'], true, field(row, 'tool_arch').text())!)
		if !target.starts_with('aarch64') || !target.contains('musl') {
			return ProbeExit{'fixture compiler must target ARM64 musl Linux'}
		}
	}
	output := text(row, 'output')!
	mkdir_parents(output)!
	class := if split { 'AndroidSplitApkProbe' } else { 'AndroidEglQueueProbe' }
	framework := text(row, 'framework_classes')!
	resources := text(row, 'framework_res')!
	source := text(row, 'source')!
	native_source := text(row, 'native_source')!
	manifest := text(row, 'manifest')!
	jni := text(row, 'jni_include')!
	native := path_join(output, if split {
		'libvinix_split_probe.so'
	} else {
		'libvinix_egl_queue_probe.so'
	})
	native_command := if split {
		[cc, '-shared', '-fPIC', '-nostdlib', '-Wl,-z,max-page-size=65536', '-I' + jni,
			'-I' + path_join(jni, 'linux'), native_source, '-o', native]
	} else {
		[cc, '-std=gnu11', '-O2', '-shared', '-fPIC', '-nostdlib', '-fno-stack-protector', '-Wall',
			'-Wextra', '-Werror', '-Wl,-z,max-page-size=16384', '-I' + jni,
			'-I' + path_join(jni, 'linux'), native_source, '-o', native]
	}
	if !split {
		advanced_command(row, native_command)!
		advanced_native_elf(native)!
	}
	classes := path_join(output, 'classes')
	advanced_clear_classes(classes)!
	advanced_command(row, [text(row, 'javac')!, '-source', '8', '-target', '8', '-bootclasspath',
		core, '-cp', framework, '-d', classes, source])!
	jar := path_join(output, if split {
		'split-fixture-classes.jar'
	} else {
		'egl-queue-fixture-classes.jar'
	})
	advanced_archive(jar, classes, class, split)!
	dex := path_join(output, if split {
		'split-fixture-dex.jar'
	} else {
		'android-egl-queue-probe.jar'
	})
	advanced_command(row, [text(row, 'java')!, '-cp', r8, 'com.android.tools.r8.D8', '--min-api',
		'26', '--lib', core, '--lib', framework, '--output', dex, jar])!
	base := path_join(output, if split {
		'android-split-probe.apk'
	} else {
		'android-egl-queue-probe.apk'
	})
	advanced_command(row, [text(row, 'aapt2')!, 'link', '--manifest', manifest, '-I', resources,
		'-o', base])!
	advanced_append_dex(dex, base, split, native)!
	if split {
		advanced_command(row, native_command)!
		elf := probe_bytes(native)!
		if elf.len < 4 || elf[..4] != [u8(0x7f), `E`, `L`, `F`] {
			return ProbeExit{'fixture compiler did not produce a genuine ARM64 ELF library'}
		}
		if elf.len == 4 { return error('IndexError: index out of range') }
		machine := if elf.len >= 20 {
			elf_u16(elf, 18)
		} else if elf.len == 19 {
			u16(elf[18])
		} else {
			u16(0)
		}
		if elf[4] != 2 || machine != 183 {
			return ProbeExit{'fixture compiler did not produce a genuine ARM64 ELF library'}
		}
		build_split_variants(row, base, dex, native, elf)!
		return
	}
	names := advanced_apk_names(base)!
	required := ['AndroidManifest.xml', 'classes.dex', 'lib/arm64-v8a/libvinix_egl_queue_probe.so']
	if required.any(it !in names) || names.any(it !in required && it != 'resources.arsc') {
		return ProbeExit{'fixture APK contains unexpected payloads'}
	}
	mut receipt := map[string]Value{}
	for key, path in {
		'source_sha256':            source
		'native_source_sha256':     native_source
		'manifest_sha256':          manifest
		'helper_sha256':            text(row, 'helper')!
		'framework_classes_sha256': framework
		'framework_res_sha256':     resources
		'core_classes_sha256':      core
		'r8_sha256':                r8
		'native_library_sha256':    native
		'fixture_apk_sha256':       base
	} {
		receipt[key] = Value(digest(path)!)
	}
	receipt['compiler_target'] = Value(target)
	receipt['native_compile_command'] = Value(native_command.map(Value(it)))
	receipt['native_dt_needed'] = Value([]Value{})
	receipt['activity'] = Value('org.vinix.tests.AndroidEglQueueProbe$BootstrapActivity')
	receipt['expected_marker'] = Value('ANDROID-EGL-QUEUE-PASS')
	receipt['runtime_tested'] = Value(false)
	receipt['fixture_uses_public_api'] = Value(true)
	advanced_write(path_join(output, 'egl-queue-probe-build.json'), Value(receipt))!
	println(base)
}

pub fn build_advanced_probe(row map[string]Value) ! {
	build_advanced_probe_with_pins(row, probe_r8_sha, probe_core_sha)!
}

struct AdvancedExit {
	message string
}

fn (e AdvancedExit) msg() string { return e.message }

fn (e AdvancedExit) code() int { return 0 }

struct AdvancedCommandError {
	arguments []string
	status    int
}

fn (e AdvancedCommandError) msg() string { return 'Compiler command failed' }

fn (e AdvancedCommandError) code() int { return e.status }

fn advanced_error(err IError) IError {
	if err is FileError { return RunnerFileError{err} }
	if err is ProbeExit { return AdvancedExit{err.message} }
	if err is ProbeCommandError { return AdvancedCommandError{err.arguments.clone(), err.status} }
	return err
}

pub fn advanced_query(row map[string]Value, operation string) !Value {
	if operation == 'advanced_native_elf' {
		advanced_native_elf(hex.decode(text(row, 'path_hex')!)!.bytestr()) or { return advanced_error(err) }
	} else {
		mut fields := map[string]Value{}
		for key, value in field(row, 'fields').object() {
			fields[key] = Value(hex.decode(value.text())!.bytestr())
		}
		build_advanced_probe(fields) or { return advanced_error(err) }
	}
	return Value(json2.null)
}

fn advanced_command(row map[string]Value, arguments []string) ! {
	probe_command_output_preferred(arguments, false, field(row, 'tool_arch').text())!
}

fn advanced_space(ch rune) bool {
	return ch in [rune(9), 10, 11, 12, 13, 32, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f,
		0x3000] || (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a)
}

fn advanced_strip(text string) string {
	runes := text.runes()
	mut first := 0
	mut last := runes.len
	for first < last && advanced_space(runes[first]) { first++ }
	for last > first && advanced_space(runes[last - 1]) { last-- }
	return runes[first..last].string()
}
