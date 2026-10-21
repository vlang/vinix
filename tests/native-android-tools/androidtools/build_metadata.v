// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import boothost
import crypto.sha256
import crypto.sha512
import encoding.binary
import hosttest
import json2
import os

fn builder_elf(data []u8, path string, kind string) ! {
	label := 'build-' + kind
	if data.len < 64 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || binary.little_endian_u16(data[18..20]) != 183 { return error(label + ': output is not an ARM64 ELF: ' + path) }
	offset := binary.little_endian_u64(data[32..40])
	entry_size := u64(binary.little_endian_u16(data[54..56])); count := u64(binary.little_endian_u16(data[56..58]))
	if entry_size != 56 || count == 0 || offset > u64(data.len) || count * entry_size > u64(data.len) - offset { return error(label + ': invalid ELF program headers: ' + path) }
	mut loads := 0
	for index := u64(0); index < count; index++ {
		at := int(offset + index * entry_size)
		if binary.little_endian_u32(data[at..at + 4]) != 1 { continue }
		loads++
		file_offset := binary.little_endian_u64(data[at + 8..at + 16]); address := binary.little_endian_u64(data[at + 16..at + 24])
		file_size := binary.little_endian_u64(data[at + 32..at + 40]); memory_size := binary.little_endian_u64(data[at + 40..at + 48])
		if file_size > memory_size || file_offset > u64(data.len) || file_size > u64(data.len) - file_offset || memory_size > u64(0xffffffffffffffff) - address || address % 16384 != file_offset % 16384 { return error(label + ': output cannot load with 16 KiB pages: ' + path) }
	}
	if loads == 0 { return error(label + ': output has no loadable segments: ' + path) }
}

pub fn build_source_key(seed string, directory string, inputs []string) !string {
	mut hash := sha256.new(); hash.write(seed.bytes())!
	if directory != '' { hash.write(directory.bytes())! }
	for path in inputs { hash.write(os.read_bytes(path)!)! }
	// Changes to native helper behavior invalidate saved source/configuration.
	hash.write(ah.dex_adapter_digest(root() + '/build-support/android')!.bytes())!
	return hash.sum([]u8{}).hex()
}

fn builder_dex_counts(data []u8, path string) !(u64, u64) {
	if data.len < 112 || data[..4].bytestr() != 'dex\n' { return error('build-atl: invalid framework DEX: ' + path) }
	classes := u64(binary.little_endian_u32(data[96..100]))
	offset := u64(binary.little_endian_u32(data[52..56]))
	if offset > u64(data.len) - 4 { return error('build-atl: invalid DEX map: ' + path) }
	count := u64(binary.little_endian_u32(data[int(offset)..int(offset) + 4]))
	if count * 12 > u64(data.len) - offset - 4 { return error('build-atl: truncated DEX map: ' + path) }
	mut callsites := u64(0)
	for index := u64(0); index < count; index++ {
		at := int(offset + 4 + index * 12)
		if binary.little_endian_u16(data[at..at + 2]) == 7 { callsites += binary.little_endian_u32(data[at + 4..at + 8]) }
	}
	return classes, callsites
}

pub fn write_build_manifest(kind string, arguments []string) ! {
	if (kind in ['art', 'bionic'] && arguments.len != 6) || (kind == 'atl' && arguments.len != 13) { return error('invalid native overlay metadata arguments') }
	output := arguments[0]; commit := arguments[1]; url := arguments[2]; archive := arguments[3]
	patch := if kind == 'atl' { arguments[9] } else { arguments[4] }
	cache := if kind == 'atl' { arguments[8] } else { arguments[5] }
	mut framework := ah.Value(json2.Null{})
	if kind == 'atl' {
		work := os.dir(output) + '/framework-extension'
		jar := output + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
		framework = extend_framework(jar, jar, work, work + '/tools', os.getenv('VINIX_ATL_JAVA_D8'))!
		build_framework_library(output + '/usr/lib/art/libvinix-android-framework.so', 'gcc', work + '/generated', 'arm64')!
		build_native_ws(work + '/smali',arguments[11],work + '/native-ws','gcc','arm64')!
		os.mkdir_all(output + '/usr/lib/art/native-ws')!
		os.mkdir_all(output + '/usr/bin')!
		os.cp(work + '/native-ws/libvinix-android-native.so',output + '/usr/lib/art/libvinix-android-native.so')!
		os.cp(work + '/native-ws/libdl_bio.so.0',output + '/usr/lib/art/native-ws/libdl_bio.so.0')!
		os.cp(work + '/native-ws/libvinix-android-compat.so',output + '/usr/lib/libvinix-android-compat.so')!
		os.cp(work + '/native-ws/vinix-android-native',output + '/usr/bin/vinix-android-native')!
		os.cp(work + '/native-ws/run-android',output + '/usr/bin/run-android-native')!
		os.mkdir_all(output + '/usr/share/licenses/bionic-ws')!
		os.cp(work + '/native-ws/bionic-ws-NOTICE', output + '/usr/share/licenses/bionic-ws/NOTICE')!
		os.cp(work + '/native-ws/bionic-ws-manifest.json', output + '/usr/share/licenses/bionic-ws/build.json')!
		os.mkdir_all(output + '/usr/share/vinix-android-ws/bionic_translation/cfg.d')!
		os.cp(work + '/native-ws/bionic-ws.cfg', output + '/usr/share/vinix-android-ws/bionic_translation/cfg.d/native.cfg')!
		for name in ['libglapi.so.0', 'libvinix-ws-GLESv1_CM.so', 'libvinix-ws-GLESv2.so'] {
			os.cp(work + '/native-ws/' + name, output + '/usr/lib/art/native-ws/' + name)!
		}
		os.mkdir_all(output + '/usr/share/licenses/mesa-ws')!
		for name in ['mesa-ws-NOTICE', 'mesa-ws-manifest.json', 'mesa-ws-sources.tar.gz'] {
			os.cp(work + '/native-ws/' + name, output + '/usr/share/licenses/mesa-ws/' + name)!
		}
	}
	mut paths := []string{}; descendants(output + '/usr', mut paths)!; paths.sort()
	mut files := []ah.Value{}
	for path in paths {
		if !os.is_file(path) { continue }
		mut data := os.read_bytes(path)!
		name := path[output.trim_right('/').len + 1..]
		mut file_kind := 'data'
		if kind == 'atl' {
			if data.len >= 4 && data[..4] == [u8(0x7f), `E`, `L`, `F`] {
				probe_command(['strip', '--strip-unneeded', path], false, '')!
				data = os.read_bytes(path)!
				file_kind = 'elf'; builder_elf(data, path, kind)!
			}
		} else if !(kind == 'art' && name == 'usr/include/androidfw/androidfw_c_api.h') { builder_elf(data, path, kind)! }
		mut record := map[string]ah.Value{'path': ah.Value(name), 'size': ah.Value(data.len), 'sha256': ah.Value(sha256.sum(data).hex())}
		if kind == 'atl' {
			record['kind'] = file_kind
			if name.ends_with('.jar') {
				record['kind'] = 'dex'
				jar := ah.open_archive(path)!
				mut classes := u64(0); mut callsites := u64(0)
				for member in jar.names() {
					if !member.ends_with('.dex') { continue }
					class_count, bootstrap_count := builder_dex_counts(jar.read(member)!, path)!
					classes += class_count; callsites += bootstrap_count
				}
				if classes == 0 || callsites > 0 { return error('build-atl: framework has missing classes or Java bootstrap calls: ' + path) }
				record['class_count'] = classes; record['bootstrap_callsites'] = callsites
			}
		}
		files << ah.Value(record)
	}
	mut dependency_archives := []ah.Value{}
	mut cached_paths := []string{}
	if os.is_dir(cache) { for name in os.ls(cache)! { if name.ends_with('.apk') { cached_paths << cache + '/' + name } } }
	cached_paths.sort()
	for path in cached_paths { dependency_archives << ah.Value({'filename': ah.Value(os.file_name(path)), 'sha256': ah.Value(ah.digest(path)!)}) }
	packages := probe_command(['apk', 'list', '--installed'], true, '') or { if kind != 'art' { return err }; '' }
	source := os.read_bytes(archive)!
	compiler := probe_command(['gcc', '--version'], true, '')!
	compiler_lines := compiler.split_into_lines()
	if compiler_lines.len == 0 { return error('compiler did not report its version') }
	mut manifest := map[string]ah.Value{'format': ah.Value(1), 'architecture': ah.Value('aarch64'), 'page_size': ah.Value(16384), 'source_commit': ah.Value(commit), 'source_url': ah.Value(url), 'source_sha512': ah.Value(sha512.sum512(source).hex()), 'source_sha256': ah.Value(sha256.sum(source).hex()), 'patch_sha256': ah.Value(ah.digest(patch)!), 'compiler': ah.Value(compiler_lines[0]), 'compiler_target': ah.Value(boothost.unicode_strip(probe_command(['gcc', '-dumpmachine'], true, '')!)), 'build_packages': ah.Value(packages.split_into_lines().map(ah.Value(it))), 'dependency_archives': ah.Value(dependency_archives), 'files': ah.Value(files)}
	if kind == 'art' { manifest['androidfw_configuration_api'] = 1; manifest['build_flags'] = ah.Value(['-DART_PAGE_SIZE=16384', 'ART_BUILD_HOST_DEBUG=false'].map(ah.Value(it))); manifest['source_date_epoch'] = 1759985629 }
	else if kind == 'bionic' { manifest['build_flags'] = ah.Value(['-DBIONIC_PAGE_SIZE=16384', '-Wl,-z,max-page-size=65536'].map(ah.Value(it))); manifest['source_date_epoch'] = 1773705600 }
	else {
		art := arguments[11]
		manifest['framework_extension'] = framework
		for key, value in {'androidfw_patch_sha256': ah.Value(ah.digest(arguments[10])!), 'androidfw_configuration_api': ah.Value(1), 'androidfw_header_sha256': ah.Value(ah.digest(art + '/usr/include/androidfw/androidfw_c_api.h')!), 'androidfw_library_sha256': ah.Value(ah.digest(art + '/usr/lib/art/libandroidfw.so')!), 'configuration_probe_sha256': ah.Value(arguments[12]), 'build_flags': ah.Value(['--buildtype=release', '-Wl,-z,max-page-size=65536'].map(ah.Value(it))), 'builder_sha256': ah.Value(ah.digest(arguments[7])!), 'dex_adapter_sha256': ah.Value(ah.dex_adapter_digest(root() + '/build-support/android')!), 'dex_compiler_sha256': ah.Value(ah.digest(arguments[4])!), 'java_core_classes_sha256': ah.Value(ah.digest(arguments[5])!), 'dex_compiler_arguments': ah.Value(dex_arguments.map(ah.Value(it))), 'dex_compiler': ah.Value(boothost.unicode_strip(probe_command([os.getenv('VINIX_ATL_JAVA_D8'), '-cp', arguments[4], 'com.android.tools.r8.D8', '--version'], true, '')!)), 'source_date_epoch': ah.Value(1790718764)} { manifest[key] = value }
	}
	write_receipt(output + '/' + kind + '-runtime-manifest.json', ah.Value(manifest))!
	println('Verified ' + files.len.str() + ' native ARM64 ' + kind.to_upper() + ' outputs')
}

pub fn build_metadata_cli(command string, argv []string) !int {
	match command {
		'resolve' { if argv.len != 1 { return error('resolve requires one path') }; println(hosttest.module_resolve(argv[0])!) }
		'verify-source' {
			if argv.len != 3 { return error('verify-source needs kind, archive and SHA512') }
			if sha512.sum512(os.read_bytes(argv[1])!).hex() != argv[2] { return error('build-' + argv[0] + ': pinned source checksum mismatch: ' + argv[1]) }
		}
		'verify-atl-inputs' { if argv.len != 3 { return error('verify-atl-inputs needs ART, R8 and classfiles') }; read_runtime(argv[0], 'art')!; check_hash(argv[1], r8_sha256)!; check_hash(argv[2], core_sha256)! }
		'source-key' { if argv.len < 2 { return error('source-key needs seed, directory and inputs') }; println(build_source_key(argv[0], argv[1], argv[2..])!) }
		'compile-args', 'link-args' {
			if argv.len != 1 { return error('Meson argument generation needs ART root') }
			println(json2.encode(if command == 'compile-args' { ['-I' + argv[0] + '/usr/include'] } else { ['-Wl,-z,max-page-size=65536', '-L' + argv[0] + '/usr/lib/art', '-Wl,-rpath-link,' + argv[0] + '/usr/lib/art', '-landroidfw'] }))
		}
		'copy-installed' {
			if argv.len != 2 { return error('copy-installed needs source and destination') }
			mut paths := []string{}; descendants(argv[0] + '/usr', mut paths)!; paths.sort()
			for path in paths { if os.is_file(path) { copy_tree(path, argv[1] + path[argv[0].trim_right('/').len..], false)! } }
		}
		'configuration-probe-key' { if argv.len != 0 { return error('configuration-probe-key accepts no arguments') }; println(ah.configuration_probe_digest(root() + '/build-support/android')!) }
		'art-build-manifest', 'bionic-build-manifest', 'atl-build-manifest' { write_build_manifest(command.all_before('-build-manifest'), argv)! }
		else { return error('unknown native Android metadata command') }
	}
	return 0
}
