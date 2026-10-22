// SPDX-License-Identifier: GPL-2.0-or-later
module normalproof

import crypto.sha256
import json2
import os

pub fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut bytes := []u8{len: 1024 * 1024}
	defer { unsafe { bytes.free() } }
	for {
		count := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		hash.write(bytes[..count])!
	}
	sum := hash.sum([]u8{})
	defer { unsafe { sum.free() } }
	return sum.hex()
}

pub fn inventory(directory string, prefix string, mut paths map[string]string) ! {
	entries := os.ls(directory)!
	defer { unsafe { entries.free() } }
	for name in entries {
		if name == '.git' { continue }
		path := directory + '/' + name
		if os.is_link(path) { paths['@link:' + prefix + name] = path }
		if os.is_dir(path) && !os.is_link(path) {
			inventory(path, prefix + name + '/', mut paths)!
		} else if os.is_file(path) {
			paths[prefix + name] = path
		}
	}
}

fn read_map(path string) !map[string]string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return json2.decode[map[string]string](text)
}

fn verify(path string, expected string, name string) ! {
	actual := digest(path)!
	defer { unsafe { actual.free() } }
	if actual != expected { return error('assembled input digest differs: ' + name) }
}

fn archived_sources(directory string) !map[string]string {
	mut all := map[string]string{}
	inventory(directory, '', mut all)!
	mut result := map[string]string{}
	for name, path in all {
		// The original assembled receipt excluded hidden build caches and
		// directory aliases. Preserve that source scope; the complete archived
		// tree is separately captured and checked before and after this run.
		if name.starts_with('@link:') || name.starts_with('.') || name.contains('/.') { continue }
		result[name] = path
	}
	return result
}

// These are the assembled-source build receipts qualified before this fixture.
// A deliberate replacement build requires a reviewed new fixture snapshot.
// The reused programs were built from a54cd7cf7; the manager is rebuilt here.
pub fn assembled(desktop string, stage string, arch string, compiler string) !map[string]string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported assembled architecture') }
	desktop_hash := if arch == 'aarch64' {
		'c84106c7d21cc84224801d1dddda92d04bb00f4b6dd5c717e3af137a0ac460b4'
	} else { '2b56a3ec6650fda007644d990b8d0fdfa12e1f835a925978c4ec0ccb94450f5e' }
	stage_hash := if arch == 'aarch64' {
		'687011a8471aa12689300e7932ca3f7bc18359817a7c37ae90ac2c5d010ba40e'
	} else { 'a967f7bbd29690cc74e63193545199d1dd7676274de29d2dad91f03c0fdd0762' }
	verify(desktop + '/desktop-build.json', desktop_hash, 'desktop receipt')!
	verify(stage + '/stage-build.json', stage_hash, 'stage receipt')!
	desktop_inputs := read_map(desktop + '/desktop-build.json')!
	stage_inputs := read_map(stage + '/stage-build.json')!
	mut result := {'assembled/desktop/desktop-build.json': desktop + '/desktop-build.json',
		'assembled/stage/stage-build.json': stage + '/stage-build.json'}
	mut expected_sources := map[string]string{}
	for name, hash in desktop_inputs {
		if name == 'repository-head' {
			if hash != 'a54cd7cf7b32d2aebd3df32e236522f3d614a4f0' { return error('unexpected assembled source commit') }
			continue
		}
		path := if name == 'compiler' { compiler }
			else if name.starts_with('app/') || name == 'vinix-desktop' { desktop + '/' + name }
			else { desktop + '/source/' + name }
		verify(path, hash, 'desktop/' + name)!
		result['assembled/desktop/' + name] = path
		if name != 'compiler' && !name.starts_with('app/') && name != 'vinix-desktop' {
			expected_sources[name] = path
		}
	}
	actual_sources := archived_sources(desktop + '/source')!
	if actual_sources != expected_sources { return error('assembled desktop source inventory differs') }
	inventory(desktop + '/source', 'assembled/desktop/captured-source/', mut result)!
	for name, hash in stage_inputs {
		if name == 'repository-head' {
			if hash != 'a54cd7cf7b32d2aebd3df32e236522f3d614a4f0' { return error('unexpected assembled source commit') }
			continue
		}
		path := if name == 'compiler' { compiler }
			else if name == 'driver' { stage + '/cross-shim' }
			else if name.starts_with('usr/') { stage + '/root/' + name }
			else { stage + '/' + name }
		verify(path, hash, 'stage/' + name)!
		result['assembled/stage/' + name] = path
	}
	stage_sources := read_map(stage + '/source.json')!
	mut expected_stage := map[string]string{}
	for name, hash in stage_sources {
		path := stage + '/source/' + name
		verify(path, hash, 'stage/source/' + name)!
		expected_stage[name] = path
		result['assembled/stage/source/' + name] = path
	}
	mut actual_stage := archived_sources(stage + '/source')!
	// The anchored driver inventories git-tracked source, then `v run` leaves
	// these two generated host-stager C files beside it. They were not inputs
	// to that historical source inventory; their current bytes are captured
	// below with the full archive, without historical source attribution.
	for name in ['tools/accounts/stage.c', 'tools/packages/stage.c'] {
		if name in expected_stage { return error('unexpected historical generated source input') }
		actual_stage.delete(name)
	}
	if actual_stage != expected_stage { return error('assembled stage source inventory differs') }
	inventory(stage + '/source', 'assembled/stage/captured-source/', mut result)!
	return result
}

pub fn hashes(paths map[string]string) !map[string]string {
	mut result := map[string]string{}
	for name, path in paths { result[name] = input_digest(name, path)! }
	return result
}

pub fn input_digest(name string, path string) !string {
	if name.starts_with('@link:') {
		if !os.is_link(path) { return error('input symbolic link disappeared: ' + name) }
		target := os.readlink(path)!
		defer { unsafe { target.free() } }
		return sha256.hexhash(target)
	}
	return digest(path)
}

pub fn unchanged(before map[string]string, paths map[string]string) ! {
	if before.len != paths.len { return error('build input inventory differs') }
	for name, path in paths {
		expected := before[name] or { return error('missing build input: ' + name) }
		actual := input_digest(name, path)!
		defer { unsafe { actual.free() } }
		if actual != expected { return error('build input changed: ' + name) }
	}
}

// Capture complete directory inventories before any producer runs. Rebuilding
// this map afterward also detects newly introduced imports, headers and libs.
pub fn build_inputs(root string, arch string, compiler string, observer_cc string, sysroot string) !map[string]string {
	mut paths := map[string]string{}
	for directory in ['tools', 'build-support', 'tests/normal-init-software/observer',
		'tests/normal-init-software/normalproof', 'tests/hardware-platform/hwhost',
		'tests/hardware-platform/plainiso', 'tests/linuxkpi'] {
		inventory(root + '/' + directory, 'source/' + directory + '/', mut paths)!
	}
	if os.is_file(root + '/v.mod') { paths['source/v.mod'] = root + '/v.mod' }
	paths['source/tests/normal-init-software/check.v'] = root + '/tests/normal-init-software/check.v'
	compiler_root := os.dir(compiler)
	paths['compiler/v'] = compiler
	paths['compiler/v.mod'] = compiler_root + '/v.mod'
	for directory in ['vlib', 'thirdparty'] {
		inventory(compiler_root + '/' + directory, 'compiler/' + directory + '/', mut paths)!
	}
	cross := '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec'
	for directory in [arch + '-linux-musl', 'lib/gcc/' + arch + '-linux-musl', 'libexec/gcc/' + arch + '-linux-musl'] {
		inventory(cross + '/' + directory, 'cross/' + directory + '/', mut paths)!
	}
	cross_binaries := os.ls(cross + '/bin')!
	defer { unsafe { cross_binaries.free() } }
	for name in cross_binaries {
		if name.starts_with(arch + '-linux-musl-') { paths['cross/bin/' + name] = cross + '/bin/' + name }
	}
	if arch == 'aarch64' {
		inventory(sysroot, 'observer-sysroot/', mut paths)!
	}
	for name, path in {'observer-cc':os.find_abs_path_of_executable(observer_cc)!,
		'cross-cc':'/opt/homebrew/bin/' + arch + '-linux-musl-gcc',
		'clang':'/opt/homebrew/opt/llvm/bin/clang', 'linker':'/opt/homebrew/bin/ld.lld',
		'host-cc':os.find_abs_path_of_executable('cc')!} {
		paths['tools/' + name] = path
	}
	for name in ['libLLVM.dylib', 'libclang-cpp.dylib', 'libLTO.dylib'] {
		paths['tools/' + name] = '/opt/homebrew/opt/llvm/lib/' + name
	}
	if os.is_file(os.dir(observer_cc) + '/clang-driver.v') {
		paths['tools/observer-cc-source'] = os.dir(observer_cc) + '/clang-driver.v'
	}
	inventory('/opt/homebrew/opt/llvm/lib/clang/23/include', 'clang-headers/', mut paths)!
	return paths
}
