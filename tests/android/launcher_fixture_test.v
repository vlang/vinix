module main

import crypto.sha256
import json2
import os
import strings
import time

#include <sys/resource.h>
#include <stdlib.h>

fn C.mkdtemp(&char) &char

struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.getrlimit(i32, &C.rlimit) i32

const removed_environment = ['RUN_FROM_BUILDDIR', 'BIONIC_LD_LIBRARY_PATH', 'QEMU_LD_PREFIX',
	'QEMU_SET_ENV', 'QEMU_RESERVED_VA', 'VINIX_X86_64_ROOT', 'VINIX_X86_MULTIARCH']

struct Execution {
	argv        []string
	environment map[string]string
	stack_limit []i64
}

struct LaunchResult {
	status int
	stdout string
	stderr string
}

struct LauncherFixture {
	directory   string
	runtime     string
	record      string
	home        string
	apk         string
	apk_digest  string
	environment map[string]string
}

fn fixture(case_name string) !LauncherFixture {
	mut template := (os.join_path(os.temp_dir(), 'vinix-android-launcher-${case_name}-XXXXXX') + '\x00').bytes()
	assert !isnil(C.mkdtemp(&char(template.data)))
	directory := template[..template.len - 1].bytestr()
	runtime := os.join_path(directory, 'native runtime')
	record := os.join_path(directory, 'executions.jsonl')
	home := os.join_path(directory, 'home')
	apk := os.join_path(directory, 'calculator unchanged.apk')
	os.write_file(apk, 'unchanged APK fixture\x00\xff\n')!
	mut environment := {
		'PATH':                 if os.getenv('PATH') == '' {
			'/bin:/usr/bin'
		} else {
			os.getenv('PATH')
		}
		'HOME':                 home
		'VINIX_ANDROID_ROOT':   runtime
		'XDG_RUNTIME_DIR':      os.join_path(directory, 'session')
		'LAUNCHER_TEST_RECORD': record
	}
	for name in ['ASAN_OPTIONS', 'UBSAN_OPTIONS'] {
		if os.getenv(name) != '' { environment[name] = os.getenv(name) }
	}
	mut limits := C.rlimit{}
	assert C.getrlimit(C.RLIMIT_STACK, &limits) == 0
	if limits.rlim_max != ~u64(0) && limits.rlim_max < 32 * 1024 * 1024 {
		environment['VINIX_ANDROID_STACK_KB'] = (limits.rlim_max / 1024).str()
	}
	for relative in ['lib', 'usr/bin', 'usr/lib/gio/modules', 'usr/lib/gdk-pixbuf-2.0/2.10.0',
		'usr/share/glib-2.0/schemas', 'usr/share/icu/76.1'] {
		os.mkdir_all(os.join_path(runtime, relative))!
	}
	os.write_file(os.join_path(runtime, 'usr/share/icu/76.1/icudt76l.dat'), 'ICU')!
	loader := os.getenv('VINIX_ANDROID_FIXTURE_LOADER')
	assert loader != '', 'build launcherfixture/loader.v and set VINIX_ANDROID_FIXTURE_LOADER'
	target := os.join_path(runtime, 'lib/ld-musl-aarch64.so.1')
	os.cp(loader, target)!
	os.chmod(target, 0o755)!
	for name in ['android-translation-layer', 'glib-compile-schemas', 'gdk-pixbuf-query-loaders',
		'gio-querymodules'] {
		command := os.join_path(runtime, 'usr/bin', name)
		os.write_file(command, '#!/bin/sh\nexit 99\n')!
		os.chmod(command, 0o755)!
	}
	return LauncherFixture{directory, runtime, record, home, apk, sha256.hexhash(os.read_file(apk)!), environment}
}

fn (f LauncherFixture) close() ! { os.rmdir_all(f.directory)! }

fn (f LauncherFixture) launch(arguments []string, extra map[string]string) !LaunchResult {
	root := os.dir(os.dir(os.dir(@FILE)))
	mut process := os.new_process('/bin/sh')
	process.set_args([os.join_path(root, 'build-support/android/run-android'), ...arguments])
	mut environment := f.environment.clone()
	for name, value in extra { environment[name] = value }
	process.set_environment(environment)
	result := capture(mut process)
	assert sha256.hexhash(os.read_file(f.apk)!) == f.apk_digest
	return result
}

fn capture(mut process os.Process) LaunchResult {
	defer { process.close() }
	process.set_redirect_stdio()
	process.run()
	mut stdout := strings.new_builder(1024)
	mut stderr := strings.new_builder(1024)
	for process.is_alive() {
		out := process.stdout_read()
		err := process.stderr_read()
		stdout.write_string(out)
		stderr.write_string(err)
		if out == '' && err == '' { time.sleep(time.millisecond) }
	}
	stdout.write_string(process.stdout_slurp())
	stderr.write_string(process.stderr_slurp())
	process.wait()
	return LaunchResult{process.code, stdout.str(), stderr.str()}
}

fn test_both_output_pipes_drain_beyond_pipe_capacity() {
	mut process := os.new_process('/bin/sh')
	process.set_args(['-c',
		'i=0; while [ "$i" -lt 4096 ]; do printf "stdout fixture record\\n"; printf "stderr fixture record\\n" >&2; i=$((i+1)); done'])
	result := capture(mut process)
	assert result.status == 0
	assert result.stdout == 'stdout fixture record\n'.repeat(4096)
	assert result.stderr == 'stderr fixture record\n'.repeat(4096)
}

fn (f LauncherFixture) executions() ![]Execution {
	if !os.exists(f.record) { return []Execution{} }
	mut records := []Execution{}
	for line in os.read_lines(f.record)! { records << json2.decode[Execution](line)! }
	return records
}

fn (f LauncherFixture) library_path() string {
	return ['lib', 'usr/lib', 'usr/lib/art', 'usr/lib/java/dex/android_translation_layer/natives',
		'usr/lib/libproxy'].map(os.join_path(f.runtime, it)).join(':')
}

fn test_native_helpers_preserve_apk_arguments_and_private_environment() {
	f := fixture('environment')!
	defer { f.close() or { panic(err) } }
	poison := os.join_path(f.directory, 'cpu emulator must not run')
	os.write_file(poison, '#!/bin/sh\nexit 97\n')!
	os.chmod(poison, 0o755)!
	observation := os.join_path(f.directory, 'text observer.so')
	mut hostile := {
		'VINIX_ANDROID_EMULATOR':     poison
		'LD_LIBRARY_PATH':            '/host/libraries'
		'LD_PRELOAD':                 '/host/preload.so'
		'VINIX_ANDROID_TEST_PRELOAD': observation
	}
	for name in removed_environment { hostile[name] = 'inherited-host-value' }
	options := ['-l', 'calculator/Calculator', '-w', '480', '-h', '640', '--test-option',
		'an argument with spaces']
	result := f.launch([f.apk, ...options], hostile)!
	assert result.status == 0, result.stderr
	calls := f.executions()!
	assert calls.map(os.file_name(it.argv[3])) == ['glib-compile-schemas', 'gdk-pixbuf-query-loaders',
		'gio-querymodules', 'android-translation-layer']
	assert calls.last().argv[4..] == ['-X', '-Djavax.net.ssl.trustStore=' + os.join_path(f.runtime,
		'etc/ssl/certs/java/cacerts'), '-X', '-Djavax.net.ssl.trustStoreType=JKS', '-X',
		'-Djavax.net.ssl.trustStorePassword=changeit', f.apk, ...options, '-X', '-Xnoimage-dex2oat',
		'-X', '-Xusejit:false']
	for call in calls {
		assert call.argv[..3] == [os.join_path(f.runtime, 'lib/ld-musl-aarch64.so.1'), '--library-path',
			f.library_path()]
		env := call.environment
		assert env['LD_LIBRARY_PATH'] == f.library_path()
		assert env['LD_PRELOAD'] == os.join_path(f.runtime, 'usr/lib/libvinix-android-compat.so') + ':' + observation
		assert env['VINIX_ALLOW_WX'] == '1'
		assert env['DISPLAY'] == ':1'
		assert env['GDK_BACKEND'] == 'x11'
		assert env['GDK_DISABLE'] == 'glx'
		assert env['GSK_RENDERER'] == 'cairo'
		assert env['ICU_DATA'] == os.join_path(f.runtime, 'usr/share/icu/76.1')
		assert env['ANDROID_APP_DATA_DIR'] == os.join_path(f.home, '.local/share/vinix/android')
		for name in removed_environment {
			assert name !in env
		}
	}
	assert os.stat(os.join_path(f.directory, 'session'))!.mode & 0o777 == 0o700
	assert os.is_dir(os.join_path(f.home, '.local/share/vinix/android'))
}

fn test_explicit_trust_properties_follow_private_defaults() {
	f := fixture('trust')!
	defer { f.close() or { panic(err) } }
	custom := os.join_path(f.directory, 'caller trusted roots.jks')
	properties := ['-X', '-Djavax.net.ssl.trustStore=' + custom, '-X',
		'-Djavax.net.ssl.trustStoreType=PKCS12', '-X',
		'-Djavax.net.ssl.trustStorePassword=caller-password']
	result := f.launch([f.apk, ...properties], {})!
	assert result.status == 0, result.stderr
	arguments := f.executions()!.last().argv[4..]
	assert arguments[..6] == ['-X', '-Djavax.net.ssl.trustStore=' + os.join_path(f.runtime,
		'etc/ssl/certs/java/cacerts'), '-X', '-Djavax.net.ssl.trustStoreType=JKS', '-X',
		'-Djavax.net.ssl.trustStorePassword=changeit']
	assert arguments[6..13] == [f.apk, ...properties]
}

fn test_existing_caches_skip_helpers_and_runtime_exit_propagates() {
	f := fixture('cached')!
	defer { f.close() or { panic(err) } }
	for name in ['usr/share/glib-2.0/schemas/gschemas.compiled',
		'usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache', 'usr/lib/gio/modules/giomodule.cache'] {
		os.write_file(os.join_path(f.runtime, name), 'cached')!
	}
	result := f.launch([f.apk], {
		'LAUNCHER_TEST_EXIT': '31'
	})!
	assert result.status == 31, result.stderr
	calls := f.executions()!
	assert calls.len == 1
	assert os.file_name(calls[0].argv[3]) == 'android-translation-layer'
	assert calls[0].environment['LD_PRELOAD'] == os.join_path(f.runtime, 'usr/lib/libvinix-android-compat.so')
}

fn test_data_namespace_and_caller_display() {
	f := fixture('data')!
	defer { f.close() or { panic(err) } }
	data_home := os.join_path(f.directory, 'custom data home')
	assert f.launch([f.apk], {
		'XDG_DATA_HOME': data_home
	})!.status == 0
	assert f.executions()!.last().environment['ANDROID_APP_DATA_DIR'] == os.join_path(data_home,
		'vinix/android')
	explicit := os.join_path(f.directory, 'application data')
	result := f.launch([f.apk], {
		'ANDROID_APP_DATA_DIR': explicit
		'XDG_DATA_HOME':        data_home
		'DISPLAY':              ':17'
		'XDG_DATA_DIRS':        '/caller/share'
		'GDK_DISABLE':          'dmabuf,threads'
	})!
	assert result.status == 0, result.stderr
	env := f.executions()!.last().environment
	assert env['ANDROID_APP_DATA_DIR'] == explicit
	assert os.is_dir(explicit)
	assert env['DISPLAY'] == ':17'
	assert env['GDK_DISABLE'] == 'dmabuf,threads,glx'
	assert env['XDG_DATA_DIRS'] == os.join_path(f.runtime, 'usr/share') + ':/caller/share'
}

fn test_helper_failure_stops_before_apk_execution() {
	f := fixture('helper')!
	defer { f.close() or { panic(err) } }
	result := f.launch([f.apk], {
		'LAUNCHER_TEST_FAIL_HELPER': 'glib-compile-schemas'
	})!
	assert result.status == 33, result.stderr
	assert f.executions()!.map(os.file_name(it.argv[3])) == ['glib-compile-schemas']
}

fn test_art_stack_limit_when_host_permits() {
	mut limits := C.rlimit{}
	assert C.getrlimit(C.RLIMIT_STACK, &limits) == 0
	if limits.rlim_max != ~u64(0) && limits.rlim_max < 32 * 1024 * 1024 {
		println('SKIP Android stack limit: host hard limit is below 32 MiB')
		return
	}
	f := fixture('stack')!
	defer { f.close() or { panic(err) } }
	result := f.launch([f.apk], {})!
	assert result.status == 0, result.stderr
	assert f.executions()!.last().stack_limit[0] == 32 * 1024 * 1024
}

fn test_help_and_usage_do_not_start_runtime() {
	f := fixture('help')!
	defer { f.close() or { panic(err) } }
	assert f.launch([], {})!.status == 2
	for argument in ['--help', '-h'] {
		result := f.launch([argument], {})!
		assert result.status == 0, result.stderr
		assert result.stdout.contains('usage: run-android APK')
	}
	assert f.executions()! == []Execution{}
}

fn test_missing_runtime_fails_before_execution() {
	f := fixture('missing-runtime')!
	defer { f.close() or { panic(err) } }
	os.rm(os.join_path(f.runtime, 'usr/bin/android-translation-layer'))!
	result := f.launch([f.apk], {})!
	assert result.status == 127
	assert result.stderr.contains('Android runtime is not installed')
	assert f.executions()! == []Execution{}
}

fn test_unreadable_apk_fails_before_execution() {
	f := fixture('missing-apk')!
	defer { f.close() or { panic(err) } }
	result := f.launch([os.join_path(f.directory, 'missing.apk')], {})!
	assert result.status == 2
	assert result.stderr.contains('cannot read APK')
	assert f.executions()! == []Execution{}
}
