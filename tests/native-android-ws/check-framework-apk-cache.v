// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production cache with real pthreads and controlled file stamps.
module main

import os
import crypto.sha256
import json2

fn main() {
	if os.args.len != 2 { panic('usage: check-framework-apk-cache FRESH_EXTERNAL_OUTPUT') }
	root := os.abs_path(os.args[1])
	if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external output required')
	}
	os.mkdir_all(root)!
	source := os.read_file('build-support/android/nativews/framework_apk_cache.v')!
	memory := os.read_file('build-support/android/nativews/ndk_memory.v')!
	resources := os.read_file('build-support/android/nativews/resources.v')!
	assert resources.contains('ws_load_apk_file(text)')
	declarations := memory.all_after('module atlframework').all_before('fn C.memfd_create')
	code := source.all_after('module atlframework')
		.replace('C.stat(path, &info)', 'probe_stat(path, &info)')
		.replace('C.statvfs(path, &mount)', 'probe_mount(path, &mount)')
		.replace('C.ApkAssets_load(path, false)', 'probe_load(path)')
		.replace('C.write(2, message, C.strlen(message))', 'probe_write(2, message, C.strlen(message))')
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { '/Users/alex/code/v/v' }
	os.write_file(root + '/source.v.input', source)!
	os.write_file(root + '/memory.v.input', memory)!
	os.write_file(root + '/resources.v.input', resources)!
	os.write_file(root + '/checker.v.input', os.read_file(@FILE)!)!
	variants := [code,
		code.replace('if !ws_framework_apk_selected(path)', 'if false'),
		code.replace('mount.f_flag & u64(C.ST_RDONLY) == 0', 'false'),
		code.replace('ws_framework_apk_stamp == before', 'true'),
		code.replace('before == after', 'true'),
		code.replace('ws_framework_apk_handle != nil && ws_framework_apk_stamp == before', 'ws_framework_apk_stamp == before'),
	]
	for index, variant in variants {
		path := root + '/case-' + index.str()
		os.mkdir(path)!
		os.write_file(path + '/main.v', model + declarations + variant + cases)!
		argv := [compiler, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'boehm', '-enable-globals', '-cc', 'cc', '-o', path + '/probe', path + '/main.v']
		os.write_file(path + '/argv.json', json2.encode(argv))!
		build := os.exec(argv)
		os.write_file(path + '/build.log', build.output)!
		assert build.exit_code == 0, build.output
		run := os.exec([path + '/probe'])
		os.write_file(path + '/run.log', run.output)!
		if index == 0 { assert run.exit_code == 0, run.output }
		else { assert run.exit_code != 0 && run.output.contains('assert'), 'mutation survived: ${index}' }
	}
	os.write_file(root + '/inputs.sha256', sha256.hexhash(source) + ' framework_apk_cache.v\n'
		+ sha256.hexhash(memory) + ' ndk_memory.v\n' + sha256.hexhash(resources) + ' resources.v\n'
		+ sha256.sum(os.read_bytes(compiler)!).hex() + ' compiler\n')!
	println('FRAMEWORK-APK-CACHE-PASS production pthreads readonly identity race failed-load mutable-path five-negative-mutations')
}

const model = r'
module main
import time
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
struct C.pthread_mutex_t {}
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.abort()
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.write(i32, voidptr, usize) isize
struct WsState { mut: root &char }
__global ws WsState
__global loads int
__global read_only bool
__global stat_bad bool
__global mount_bad bool
__global owner u32
__global kind u32
__global fail_load bool
__global change_during_load bool
__global stamp WsFrameworkApkStamp
__global reports int

fn probe_write(fd i32, buffer voidptr, length usize) isize {
 message := unsafe { cstring_to_vstring(&char(buffer)) }
 assert fd == 2 && message == "ANDROID-FRAMEWORK-APK-CACHE-HIT\n" && length == usize(message.len)
 reports++
 return isize(length)
}

fn probe_stat(path &char, info &C.stat) i32 {
 if stat_bad { return -1 }
 unsafe {
  info.st_uid = owner; info.st_mode = kind
  info.st_dev = stamp.device; info.st_ino = stamp.inode; info.st_size = stamp.size
  $if macos {
   info.st_mtimespec.tv_sec = stamp.modified; info.st_mtimespec.tv_nsec = stamp.modified_ns
   info.st_ctimespec.tv_sec = stamp.changed; info.st_ctimespec.tv_nsec = stamp.changed_ns
  } $else {
   info.st_mtim.tv_sec = stamp.modified; info.st_mtim.tv_nsec = stamp.modified_ns
   info.st_ctim.tv_sec = stamp.changed; info.st_ctim.tv_nsec = stamp.changed_ns
  }
 }
 return 0
}
fn probe_mount(path &char, mount &C.statvfs) i32 {
 if mount_bad { return -1 }
 unsafe { mount.f_flag = if read_only { u64(C.ST_RDONLY) } else { u64(0) } }
 return 0
}
fn probe_load(path &char) voidptr {
 loads++
 if change_during_load { stamp = WsFrameworkApkStamp{...stamp, modified_ns: stamp.modified_ns + 1} }
 time.sleep(time.millisecond)
 if fail_load { return unsafe { nil } }
 return voidptr(100 + loads)
}
fn reset() {
 ws.root = c"/runtime"; loads = 0; read_only = true; stat_bad = false; mount_bad = false
 owner = 0; kind = 0o100444; fail_load = false; change_during_load = false
 ws_framework_apk_handle = unsafe { nil }
 ws_framework_apk_reported = false
 reports = 0
 stamp = WsFrameworkApkStamp{device: 1, inode: 2, size: 100, modified: 10, modified_ns: 20, changed: 30, changed_ns: 40}
}
fn repeated() { for _ in 0 .. 100 { assert ws_load_apk_file(c"/runtime/usr/lib/java/dex/android_translation_layer/framework-res.apk") != unsafe { nil } } }
'

const cases = r'
fn main() {
 path := c"/runtime/usr/lib/java/dex/android_translation_layer/framework-res.apk"
 reset()
 mut threads := []thread{}
 for _ in 0 .. 8 { threads << spawn repeated() }
 threads.wait()
 assert loads == 1 && reports == 1
 for other in [c"/data/framework-res.apk", c"/runtime-other/usr/lib/java/dex/android_translation_layer/framework-res.apk", c"/runtime/usr/lib/java/dex/android_translation_layer/framework-res.apk.other"] {
  reset(); ws_load_apk_file(other); ws_load_apk_file(other); assert loads == 2 && reports == 0
 }
 for variant in 0 .. 6 {
  reset()
  match variant { 0 { read_only = false } 1 { stat_bad = true } 2 { mount_bad = true }
    3 { owner = 10012 } 4 { kind = 0o040755 } else { stamp = WsFrameworkApkStamp{...stamp, size: 0} } }
  ws_load_apk_file(path); ws_load_apk_file(path); assert loads == 2 && reports == 0
 }
 for variant in 0 .. 7 {
  reset(); first := ws_load_apk_file(path)
  stamp = match variant {
   0 { WsFrameworkApkStamp{...stamp, device: 9} } 1 { WsFrameworkApkStamp{...stamp, inode: 9} }
   2 { WsFrameworkApkStamp{...stamp, size: 9} } 3 { WsFrameworkApkStamp{...stamp, modified: 9} }
   4 { WsFrameworkApkStamp{...stamp, modified_ns: 9} } 5 { WsFrameworkApkStamp{...stamp, changed: 9} }
   else { WsFrameworkApkStamp{...stamp, changed_ns: 9} }
  }
  second := ws_load_apk_file(path); assert loads == 2 && second != first
  assert ws_load_apk_file(path) == second && loads == 2
 }
 reset(); change_during_load = true
 ws_load_apk_file(path); ws_load_apk_file(path); assert loads == 2
 assert ws_framework_apk_handle == unsafe { nil }
 reset(); fail_load = true
 assert ws_load_apk_file(path) == unsafe { nil } && ws_framework_apk_handle == unsafe { nil }
 fail_load = false; assert ws_load_apk_file(path) != unsafe { nil } && loads == 2
 assert ws_load_apk_file(path) != unsafe { nil } && loads == 2
 println("FRAMEWORK-APK-CACHE-PROBE-PASS")
}
'
