module main

import json2
import os

#include <sys/resource.h>

struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.getrlimit(i32, &C.rlimit) i32

struct Execution {
	argv        []string
	environment map[string]string
	stack_limit []i64
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-loader' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o755) or { panic(err) }
		return
	}
	mut stack := C.rlimit{}
	assert C.getrlimit(C.RLIMIT_STACK, &stack) == 0
	mut record := os.open_append(os.getenv('LAUNCHER_TEST_RECORD')) or { panic(err) }
	defer { record.close() }
	record.writeln(json2.encode(Execution{os.args.clone(), os.environ(), [
		i64(stack.rlim_cur),
		i64(stack.rlim_max),
	]}, escape_unicode: true, time_as_unix: true)) or { panic(err) }
	record.close()
	assert os.args.len >= 4 && os.args[1] == '--library-path'
	name := os.file_name(os.args[3])
	if name == os.getenv('LAUNCHER_TEST_FAIL_HELPER') { exit(33) }
	match name {
		'glib-compile-schemas' {
			os.write_file(os.join_path(os.args[4], 'gschemas.compiled'), 'schemas') or { panic(err) }
		}
		'gdk-pixbuf-query-loaders' { println('loaders') }
		'gio-querymodules' {
			os.write_file(os.join_path(os.args[4], 'giomodule.cache'), 'modules') or { panic(err) }
		}
		'android-translation-layer' { exit(os.getenv('LAUNCHER_TEST_EXIT').int()) }
		else { panic('unexpected fixture command ' + os.args[3]) }
	}
}
