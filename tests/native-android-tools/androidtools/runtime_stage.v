// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import boothost
import cachecli
import crypto.sha256
import hosttest
import json2
import os

pub const runtime_prefix = '/opt/vinix-android-aarch64'
pub const required_runtime_files = ['lib/ld-musl-aarch64.so.1', 'usr/bin/android-translation-layer', 'usr/lib/art/libart.so', 'usr/lib/java/dex/android_translation_layer/api-impl.jar', 'usr/lib/java/dex/android_translation_layer/framework-res.apk', 'usr/lib/java/dex/android_translation_layer/natives/libtranslation_layer_main.so', 'usr/lib/libvinix-android-compat.so', 'art-runtime-manifest.json', 'bionic-runtime-manifest.json', 'atl-runtime-manifest.json', 'runtime-manifest.json', 'architecture']

pub struct StageHooks {
pub:
	context ah.Value = ah.Value(json2.Null{})
	read fn (string, string, ah.Value) !ah.Value = unsafe { nil }
	apply fn (string, string, string, ah.Value, ah.Value) ! = unsafe { nil }
	pair fn (ah.Value, ah.Value, ah.Value) ! = unsafe { nil }
	command fn ([]string, map[string]string, ah.Value) ! = unsafe { nil }
	compiler string
}

pub struct RuntimeOptions {
pub:
	build_dir string
	art_runtime string
	bionic_runtime string
	atl_runtime string
	with_calculator bool
	hooks StageHooks
}

fn (options RuntimeOptions) read(kind string, path string) !ah.Value {
	if options.hooks.read != unsafe { nil } { return options.hooks.read(kind, path, options.hooks.context)! }
	return if kind == 'musl' { read_android_musl(path)! } else { read_runtime(path, kind)! }
}

fn (options RuntimeOptions) pair(art ah.Value, atl ah.Value) ! {
	if options.hooks.pair != unsafe { nil } { options.hooks.pair(art, atl, options.hooks.context)! }
	else { validate_art_pair(art, atl)! }
}

fn (options RuntimeOptions) apply(kind string, overlay string, runtime string, manifest ah.Value) ! {
	if options.hooks.apply != unsafe { nil } { options.hooks.apply(kind, overlay, runtime, manifest, options.hooks.context)! }
	else { apply_runtime(overlay, runtime, manifest, kind)! }
}

fn (options RuntimeOptions) command(argv []string, environment map[string]string) ! {
	cachecli.checkpoint()!
	if options.hooks.command != unsafe { nil } { options.hooks.command(argv, environment, options.hooks.context)! }
	else {
		result := source_run(argv, environment)!
		if result != 0 { return ah.command_failure(argv, result, false, '') }
	}
}

fn canonical(value ah.Value) string {
	if value is []ah.Value { return '[' + value.map(canonical(it)).join(',') + ']' }
	if value is map[string]ah.Value {
		mut keys := value.keys(); keys.sort()
		mut records := []string{}
		for key in keys { records << json2.encode(key) + ':' + canonical(value[key]!) }
		return '{' + records.join(',') + '}'
	}
	return ah.encode(value)
}

fn write_receipt(path string, value ah.Value) ! { os.write_file(path, ah.encode(value) + '\n')! }

fn (options RuntimeOptions) cache_key(package_lock ah.Value, art ah.Value, bionic ah.Value, atl ah.Value) !string {
	mut hash := sha256.new()
	hash.write('vinix-native-android-staging-v1\x00'.bytes())!
	for value in [package_lock, ah.Value(options.with_calculator), art, bionic, atl] { hash.write(canonical(value).bytes())!; hash.write([u8(0)])! }
	hash.write(runtime_inputs()!)!
	mut paths := ['build-support/android/run-android', 'build-support/android/art16k.patch', 'build-support/android/build-art.sh', 'build-support/android/bionic16k.patch', 'build-support/android/build-bionic.sh', 'build-support/android/build-atl.sh', 'build-support/android/musl-mallinfo.patch', 'build-support/android/musl-statistics.h', 'build-support/musl/stage', 'build-support/musl/stage.v', 'build-support/musl/malloc-retain.patch', 'build-support/musl/alpine-1.2.6/manifest.json', 'build-support/java-cacerts', 'build-support/java-cacerts.v', 'build-support/run-v-tool.sh']
	for directory in ['build-support/android/androidhost', 'build-support/android/boothost', 'build-support/muslnative', 'build-support/musl/alpine-1.2.6', 'build-support/javacacerts', 'build-support/cachekey', 'build-support/tarstream', 'build-support/tarcore'] { closure(directory, mut paths)! }
	paths.sort()
	for path in paths { hash.write(path.bytes())!; hash.write([u8(0)])!; hash.write(os.read_bytes(root() + '/' + path)!)!; hash.write([u8(0)])! }
	return hash.sum([]u8{}).hex()
}

fn (options RuntimeOptions) cached(runtime string, package_lock ah.Value, art ah.Value, bionic ah.Value, atl ah.Value) !bool {
	actual_art := options.read('art', runtime)!
	actual_bionic := options.read('bionic', runtime)!
	actual_atl := options.read('atl', runtime)!
	musl := options.read('musl', runtime)!
	options.pair(actual_art, actual_atl)!
	if !boothost.receipt_equal(actual_art, art) || !boothost.receipt_equal(actual_bionic, bionic) || !boothost.receipt_equal(actual_atl, atl) { return false }
	manifest := read_value(runtime + '/runtime-manifest.json')!
	if manifest !is map[string]ah.Value { return false }
	row := manifest.object()
	if field_text(row, 'architecture') != 'aarch64' || os.read_file(runtime + '/architecture')!.trim_space() != 'aarch64' || field_text(row, 'execution') != 'native' || !boothost.receipt_equal(ah.field(row, 'page_size'), ah.Value(16384)) || field_text(row, 'runtime_prefix') != runtime_prefix { return false }
	for key, expected in {'packages': ah.field(package_lock.object(), 'packages'), 'art': art, 'bionic': bionic, 'atl': atl, 'musl': musl} { if !boothost.receipt_equal(ah.field(row, key), expected) { return false } }
	return true
}

pub fn stage_runtime(options RuntimeOptions, package_lock ah.Value, downloads string) !string {
	for kind, path in {'ART': options.art_runtime, 'Bionic': options.bionic_runtime, 'ATL': options.atl_runtime} {
		if !os.is_dir(path) { return error('missing native ' + kind + ' overlay: ' + path) }
	}
	art := options.read('art', options.art_runtime)!
	if ah.field(art.object(), 'bootclasspath') is json2.Null || ah.field(art.object(), 'bootclasspath').object().len == 0 { return error("ART's Java boot libraries must be desugared first; run build-support/android/art-bootclasspath --build-dir " + options.build_dir + '/java-build --art-runtime ' + options.art_runtime) }
	bionic := options.read('bionic', options.bionic_runtime)!
	atl := options.read('atl', options.atl_runtime)!
	options.pair(art, atl)!
	staging := options.build_dir + '/staging'
	runtime := staging + runtime_prefix
	key := options.cache_key(package_lock, art, bionic, atl)!
	cache := options.build_dir + '/.staging-cache-key'
	mut files_match := os.exists(cache) && os.read_file(cache)!.trim_space() == key
	if files_match {
		for name in required_runtime_files { if !os.is_file(runtime + '/' + name) { files_match = false } }
		if !os.is_file(staging + '/usr/bin/run-android') || (options.with_calculator && !os.is_file(staging + '/usr/bin/run-android-calculator')) { files_match = false }
	}
	if files_match && (options.cached(runtime, package_lock, art, bionic, atl) or { false }) {
		println('Reusing pinned native Android runtime in ' + staging); flush_stdout()
		return staging
	}
	compiler := if options.hooks.compiler != '' { options.hooks.compiler } else { os.find_abs_path_of_executable('aarch64-linux-musl-gcc') or { return error('aarch64-linux-musl-gcc is required to build the Android compatibility library') } }
	if os.exists(cache) { os.rm(cache)! }
	if os.exists(staging) { hosttest.remove_work_dir(staging)! }
	posix_parents(runtime)!
	archives := fetch_packages(package_lock, downloads)!
	for archive in archives { extract_apk(archive, runtime)! }
	materialize_library_links(runtime)!
	mut environment := os.environ()
	environment['VINIX_OPTIMIZED_MUSL'] = '1'; environment['VINIX_MUSL_RETAIN'] = '1'
	options.command([root() + '/build-support/musl/stage', '--arch', 'aarch64', '--staging', runtime, '--build-dir', options.build_dir + '/musl-build', '--cc', compiler, '--extra-patch', root() + '/build-support/android/musl-mallinfo.patch', '--max-page-size', '65536', '--require-export', '__vinix_malloc_stats'], environment)!
	materialize_library_links(runtime)!
	musl := options.read('musl', runtime)!
	for kind, input in {'art': options.art_runtime, 'bionic': options.bionic_runtime, 'atl': options.atl_runtime} {
		manifest := match kind { 'art' { art } 'bionic' { bionic } else { atl } }
		options.apply(kind, input, runtime, manifest)!
		write_receipt(runtime + '/' + kind + '-runtime-manifest.json', manifest)!
	}
	relocate_configuration(runtime)!
	options.command([root() + '/build-support/android/compile-v-runtime', runtime + '/usr/lib/libvinix-android-compat.so', '--cc', compiler, '--generated-dir', options.build_dir + '/runtime-generated'], os.environ())!
	options.command([root() + '/build-support/java-cacerts', runtime + '/usr/share/ca-certificates/mozilla', runtime + '/etc/ssl/certs/java/cacerts'], os.environ())!
	if os.exists(runtime + '/usr/share/atl') { copy_tree(runtime + '/usr/share/atl', staging + '/usr/share/atl', true)! }
	commands := staging + '/usr/bin'; posix_parents(commands)!
	os.cp(runtime + '/usr/bin/run-android-native',commands + '/run-android')!
	os.chmod(commands + '/run-android', 0o755)!
	mut manifest := json2.decode[ah.Value](ah.encode(package_lock), strict: true)!.object()
	for name, value in {'runtime_prefix': ah.Value(runtime_prefix), 'execution': ah.Value('native'), 'page_size': ah.Value(16384), 'art': art, 'bionic': bionic, 'atl': atl, 'musl': musl, 'upstream': ah.Value('https://gitlab.com/android_translation_layer/android_translation_layer')} { manifest[name] = value }
	if options.with_calculator {
		apk := calculator_apk(downloads)!
		samples := staging + '/usr/share/vinix/android'; posix_parents(samples)!
		os.cp(apk, samples + '/' + os.file_name(apk))!
		os.write_file(commands + '/run-android-calculator', '#!/bin/sh\nexec /usr/bin/run-android /usr/share/vinix/android/Arity-1.1.apk -l calculator/Calculator -w 480 -h 640 "\$@"\n')!
		os.chmod(commands + '/run-android-calculator', 0o755)!
		manifest['calculator'] = calculator_metadata()
	}
	write_receipt(runtime + '/runtime-manifest.json', ah.Value(manifest))!
	os.write_file(runtime + '/architecture', field_text(package_lock.object(), 'architecture') + '\n')!
	for name in required_runtime_files { if !os.is_file(runtime + '/' + name) { return error('missing staged Android runtime file: ' + name) } }
	os.write_file(cache, key + '\n')!
	println('Staged ' + ah.field(package_lock.object(), 'packages').items().len.str() + ' pinned packages in ' + staging); flush_stdout()
	return staging
}
