// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import androidtools
import boothost
import hosttest
import json2
import os

#include <stdio.h>

fn C.rename(&char, &char) int
fn C.mkdtemp(&char) &char

pub const roblox_prefix = 'opt/vinix-android-aarch64'
pub const roblox_receipt = 'usr/share/vinix/roblox/runtime-manifest.json'
pub const roblox_commands = ['run-roblox', 'run-roblox-client']

pub struct RobloxHooks {
pub:
	context ah.Value = ah.Value(json2.Null{})
	read    fn (string, string, ah.Value) !ah.Value = unsafe { nil }
	pair    fn (ah.Value, ah.Value, ah.Value) !     = unsafe { nil }
	publish fn (string, string, ah.Value) !         = unsafe { nil }
}

fn (hooks RobloxHooks) load(kind string, runtime string) !ah.Value {
	if hooks.read != unsafe { nil } { return hooks.read(kind, runtime, hooks.context) }
	return if kind == 'musl' {
		androidtools.read_android_musl(runtime)!
	} else {
		androidtools.read_runtime(runtime, kind)!
	}
}

pub fn roblox_provenance(root string, stage string) !ah.Value {
	return roblox_provenance_with(root, stage, RobloxHooks{})
}

pub fn roblox_provenance_with(root string, stage string, hooks RobloxHooks) !ah.Value {
	runtime := join([stage, roblox_prefix])
	launcher := join([stage, 'usr/bin/run-android'])
	if !os.is_file(launcher) || !os.is_executable(launcher) {
		return error('Build the native Android runtime with ./scripts/build-android-aarch64.sh first')
	}
	if ah.digest(launcher)! != ah.digest(root + '/build-support/android/run-android')! {
		return error('Android runtime has a stale launcher; rebuild the Android layer')
	}
	art := hooks.load('art', runtime)!
	bionic := hooks.load('bionic', runtime)!
	atl := hooks.load('atl', runtime)!
	musl := hooks.load('musl', runtime)!
	if hooks.pair != unsafe { nil } {
		hooks.pair(art, atl, hooks.context)!
	} else {
		androidtools.validate_art_pair(art, atl)!
	}
	manifest_path := runtime + '/runtime-manifest.json'
	manifest := json2.decode[ah.Value](read_text(manifest_path)!, strict: true)!
	row := manifest.object()
	mut valid := manifest is map[string]ah.Value
	for key, value in {
		'architecture':   ah.Value('aarch64')
		'execution':      ah.Value('native')
		'page_size':      ah.Value(16384)
		'runtime_prefix': ah.Value('/' + roblox_prefix)
		'art':            art
		'bionic':         bionic
		'atl':            atl
		'musl':           musl
	} {
		if !boothost.receipt_equal(ah.field(row, key), value) { valid = false }
	}
	if boothost.unicode_strip(read_text(runtime + '/architecture')!) != 'aarch64' || !truth(ah.field(art.object(), 'bootclasspath')) {
		valid = false
	}
	if !valid { return error('Roblox requires the verified native ARM64 Android runtime') }
	compatibility := runtime + '/usr/lib/libvinix-android-compat.so'
	if !os.is_file(compatibility) {
		return error('Android runtime is missing its native compatibility library')
	}
	ah.check_elf(runtime + '/lib/ld-musl-aarch64.so.1', true)!
	ah.check_elf(compatibility, true)!
	mut files := map[string]ah.Value{}
	for name in roblox_commands {
		files['usr/bin/' + name] = ah.Value(ah.digest(root + '/build-support/roblox/' + name)!)
	}
	return ah.Value({
		'format':                          ah.Value(1)
		'architecture':                    ah.Value('aarch64')
		'execution':                       ah.Value('native')
		'page_size':                       ah.Value(16384)
		'runtime':                         ah.Value('Android Translation Layer / ART')
		'runtime_prefix':                  ah.Value('/' + roblox_prefix)
		'android_runtime_manifest_sha256': ah.Value(ah.digest(manifest_path)!)
		'android_launcher_sha256':         ah.Value(ah.digest(launcher)!)
		'android_compatibility_sha256':    ah.Value(ah.digest(compatibility)!)
		'android_libc_sha256':             ah.field(musl.object(), 'libc_so_sha256')
		'art_source_commit':               ah.field(art.object(), 'source_commit')
		'art_patch_sha256':                ah.field(art.object(), 'patch_sha256')
		'bionic_source_commit':            ah.field(bionic.object(), 'source_commit')
		'bionic_patch_sha256':             ah.field(bionic.object(), 'patch_sha256')
		'atl_source_commit':               ah.field(atl.object(), 'source_commit')
		'atl_builder_sha256':              ah.field(atl.object(), 'builder_sha256')
		'files':                           ah.Value(files)
		'apk_bundled':                     ah.Value(false)
	})
}

pub fn validate_roblox_stage(root string, stage string, android_stage string) !ah.Value {
	return validate_roblox_with(root, stage, android_stage, RobloxHooks{})
}

pub fn validate_roblox_with(root string, stage string, android_stage string, hooks RobloxHooks) !ah.Value {
	if os.is_link(stage) || !os.is_dir(stage) {
		return error('Roblox staging must be a directory: ' + stage)
	}
	expected := roblox_provenance_with(root, android_stage, hooks)!
	files := ah.field(expected.object(), 'files').object()
	mut required := files.keys()
	required << roblox_receipt
	required.sort()
	mut actual := []string{}
	for path in paths(stage, true)! {
		if os.is_link(path) { return error('Roblox staging contains a symlink: ' + path) }
		if os.is_file(path) { actual << path[stage.trim_right('/').len + 1..] }
	}
	actual.sort()
	if actual != required {
		return error('Roblox staging must contain only its native APK launchers and manifest')
	}
	manifest := load_roblox_receipt(stage + '/' + roblox_receipt) or { return error('Roblox staging has an invalid manifest') }
	if !boothost.receipt_equal(manifest, expected) {
		return error('Roblox staging does not match its native Android runtime; rebuild the Roblox layer')
	}
	for name, checksum in files {
		path := stage + '/' + name
		if os.stat(path)!.get_filetype() != .regular || !os.is_executable(path) || ah.digest(path)! != checksum.text() {
			return error('Roblox launcher is stale or not executable: ' + path)
		}
	}
	return manifest
}

fn (context &Context) validate_roblox(stage string, android_stage string) !ah.Value {
	return validate_roblox_stage(context.root, stage, android_stage)
}

pub fn stage_roblox(root string, build_directory string, android_directory string) !string {
	return stage_roblox_with(root, build_directory, android_directory, RobloxHooks{})
}

pub fn stage_roblox_with(root string, build_directory string, android_directory string, hooks RobloxHooks) !string {
	manifest := roblox_provenance_with(root, android_directory, hooks)!
	build := hosttest.module_resolve(build_directory)!
	android := hosttest.module_resolve(android_directory)!
	stage := build + '/staging'
	if stage == android || android.starts_with(stage + '/') || stage.starts_with(android + '/') {
		return error('Roblox launcher staging must be separate from the shared Android runtime')
	}
	parents(build)!
	mut temporary := (build + '/roblox-stage-XXXXXX\x00').bytes()
	if C.mkdtemp(temporary.data) == unsafe { nil } { return os.error_posix() }
	directory := temporary.bytestr().all_before('\x00')
	defer { hosttest.remove_work_dir(directory) or {} }
	output := directory + '/staging'
	parents(output + '/usr/bin')!
	for name in roblox_commands {
		target := output + '/usr/bin/' + name
		hosttest.module_copy_file_preserving_stat(root + '/build-support/roblox/' + name, target)!
		os.chmod(target, 0o755)!
	}
	parents(parent(output + '/' + roblox_receipt))!
	write_text(output + '/' + roblox_receipt, ah.encode(manifest) + '\n')!
	validate_roblox_with(root, output, android, hooks)!
	previous := directory + '/previous'
	if os.exists(stage) || os.is_link(stage) {
		if C.rename(stage.str, previous.str) != 0 { return os.error_posix() }
	}
	publish_roblox(output, stage, hooks) or {
		failure := err
		if os.exists(previous) || os.is_link(previous) {
			if C.rename(previous.str, stage.str) != 0 {
				return error(failure.msg() + '; rollback failed: ' + os.error_posix().msg())
			}
		}
		return failure
	}
	return stage
}

fn publish_roblox(source string, destination string, hooks RobloxHooks) ! {
	if hooks.publish != unsafe { nil } {
		hooks.publish(source, destination, hooks.context)!
		return
	}
	if C.rename(source.str, destination.str) != 0 { return os.error_posix() }
}

fn load_roblox_receipt(path string) !ah.Value {
	return json2.decode[ah.Value](read_text(path)!, strict: true)!
}
