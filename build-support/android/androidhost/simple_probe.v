module androidhost

import os

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn simple_probe_temporary(parent string, prefix string) !string {
	mut name := (path_join(parent, prefix + 'XXXXXX') + '\x00').bytes()
	if isnil(C.mkdtemp(&char(name.data))) {
		number := int(C.errno)
		return FileError{
			message:  os.get_error_msg(number)
			number:   number
			filename: name[..name.len - 1].bytestr()
		}
	}
	return name[..name.len - 1].bytestr()
}

pub fn archive_simple_classes(root string, path string) ! {
	mut stream := os.create(path) or { return file_error(path) }
	defer { stream.close() }
	mut output := []u8{}
	mut central := []u8{}
	mut count := 0
	mut published := 0
	for name in probe_class_paths(root, '') {
		data := probe_bytes(name) or {
			finish_probe_zip(mut output, central, count, []u8{})!
			write_probe_bytes(mut stream, output[published..])!
			return err
		}
		central << add_probe_entry(mut output, ProbePayload{name[root.len + 1..], data, 0o644})!
		write_probe_bytes(mut stream, output[published..])!
		published = output.len
		count++
	}
	finish_probe_zip(mut output, central, count, []u8{})!
	write_probe_bytes(mut stream, output[published..])!
}

const simple_layout_logger = 'package android.util;\n// Fixture-only logging adapter; parser and focus behavior use the actual framework.\npublic final class Log {\n    public static int println_native(int buffer, int priority, String tag, String message) { return 0; }\n    public static String getStackTraceString(Throwable error) { return error.toString(); }\n}\n'

fn build_simple_probe_with_pins(row map[string]Value, r8_pin string, core_pin string) !string {
	kind := text(row, 'kind')!
	if kind !in ['pointer-capture', 'layout-focus'] {
		return error('Unknown Android simple probe kind')
	}
	r8 := text(row, 'r8')!
	core := text(row, 'core_classes')!
	for pair in [[r8, r8_pin], [core, core_pin]] {
		if digest(pair[0])! != pair[1] { return pair[0] }
	}
	output := text(row, 'output')!
	parent := path_parent(output)
	mkdir_parents(parent)!
	scratch := simple_probe_temporary(parent, kind + '-')!
	build_simple_in_scratch(row, scratch, kind, r8, core, output) or {
		failure := err
		retire_simple_probe(scratch)!
		return failure
	}
	retire_simple_probe(scratch)!
	println('Built separate ' + kind + ' probe: ' + output)
	return ''
}

fn retire_simple_probe(scratch string) ! {
	state := os.lstat(scratch) or { return file_error(scratch) }
	remove_probe_tree_at(C.AT_FDCWD, scratch, scratch, state.dev, state.inode)!
}

fn build_simple_in_scratch(row map[string]Value, scratch string, kind string, r8 string, core string, output string) ! {
	classes := path_join(scratch, 'classes')
	if C.mkdir(classes.str, 0o777) != 0 { return file_error(classes) }
	logger := path_join(scratch, 'Log.java')
	if kind == 'layout-focus' {
		os.write_file(logger, simple_layout_logger) or { return file_error(logger) }
	}
	framework := resolved_path(text(row, 'framework_classes')!)!
	stub := resolved_path(text(row, 'stub_classes')!)!
	resolved_core := resolved_path(core)!
	classpath := [framework, stub, resolved_core].join(':')
	mut compiler_argv := [text(row, 'javac')!, '-source', '1.8', '-target', '1.8', '-classpath',
		classpath, '-d', classes]
	if kind == 'layout-focus' {
		compiler_argv << logger
	}
	compiler_argv << path_join(path_parent(text(row, 'helper')!), if kind == 'layout-focus' {
		'AndroidLayoutFocusProbe.java'
	} else {
		'AndroidPointerCaptureProbe.java'
	})
	probe_command(compiler_argv)!
	program := path_join(scratch, 'probe-classes.jar')
	archive_simple_classes(classes, program)!
	dex := path_join(scratch, 'dex')
	if C.mkdir(dex.str, 0o777) != 0 { return file_error(dex) }
	probe_command([text(row, 'java')!, '-cp', resolved_path(r8)!, 'com.android.tools.r8.D8', '--release',
		'--min-api', '26', '--android-platform-build', '--force-passthrough-assertions', '--lib',
		resolved_core, '--lib', framework, '--lib', stub, '--output', dex, program])!
	// The original opens its final archive before reading classes.dex.
	mut stream := os.create(output) or { return file_error(output) }
	defer { stream.close() }
	data := probe_bytes(path_join(dex, 'classes.dex')) or {
		write_probe_bytes(mut stream, make_probe_zip([]ProbePayload{})!)!
		return err
	}
	write_probe_bytes(mut stream, make_probe_zip([ProbePayload{'classes.dex', data, 0o644}])!)!
}

pub fn build_simple_probe(row map[string]Value) !string {
	return build_simple_probe_with_pins(row, probe_r8_sha, probe_core_sha)
}
