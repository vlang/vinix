// SPDX-License-Identifier: GPL-2.0-or-later
// Reconstruct the protected browser deployment from sealed package/build inputs.
module main

import browserclosure
import crypto.sha256
import json2
import fontindex
import mapsaccountstage
import muslabi
import os

const guest_root = '/opt/vinix-google-browser'
const bundle_path = 'usr/lib/webkitgtk-6.0/injected-bundle/libwebkitgtkinjectedbundle.so'
const helpers = ['lib/ld-musl-aarch64.so.1', 'usr/bin/xkbcomp', 'usr/bin/bwrap',
	'usr/libexec/webkitgtk-6.0/WebKitWebProcess', 'usr/libexec/webkitgtk-6.0/WebKitNetworkProcess',
	'usr/libexec/webkitgtk-6.0/WebKitGPUProcess']
const trust = 'etc/ssl/certs/ca-certificates.crt'
const library_directories = ['usr/lib', 'lib', 'usr/lib/libproxy']

struct Package {
	name     string
	version  string
	filename string
	sha256   string
}

struct Packages {
	format       int
	architecture string
	packages     []Package
}

struct AddonBuild {
	runtime_manifest_sha256 string
	addon_lock_sha256       string
	base_lock_sha256        string
	runtime_references      map[string]string
}

struct EngineBuild {
	format         int
	engine_sha256  string
	guest_executed bool
}

struct Entry {
	path   string
	sha256 string
	size   u64
	mode   u32
	uid    u32
	gid    u32
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn pin(path string, expected string) ! {
	if expected.len != 64 || !expected.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| digest(path)! != expected {
		return error('input checksum mismatch: ' + path)
	}
}

fn relative(path string) bool {
	return path.len > 0 && !path.starts_with('/') && !path.contains_any('\\:\x00\t\n\r')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

fn sealed_engine(root string, seal string) !EngineBuild {
	file := root + '/build-sha256.json'
	pin(file, seal)!
	items := json2.decode[map[string]string](os.read_file(file)!)!
	if 'build.json' !in items || 'webview-engine' !in items || items.len < 10 {
		return error('incomplete engine build inventory')
	}
	for name, expected in items {
		if !relative(name) || os.lstat(root + '/' + name)!.get_filetype() != .regular {
			return error('engine artifact must be a regular file')
		}
		pin(root + '/' + name, expected)!
	}
	build := json2.decode[EngineBuild](os.read_file(root + '/build.json')!)!
	if build.format != 1 || build.guest_executed || build.engine_sha256 != items['webview-engine'] {
		return error('unsupported engine build')
	}
	return build
}

fn packages(path string, cache string, mut archive_pins map[string]string, mut package_paths map[string]string) ![]string {
	package_set := json2.decode[Packages](os.read_file(path)!)!
	if package_set.format != 1 || package_set.architecture != 'aarch64' || package_set.packages.len == 0 || package_set.packages.len > 1000 {
		return error('invalid AArch64 package inventory')
	}
	mut names := []string{}
	for package in package_set.packages {
		if os.base(package.filename) != package.filename || package.filename != package.name + '-' + package.version + '.apk' {
			return error('invalid locked archive filename')
		}
		archive := cache + '/' + package.filename
		pin(archive, package.sha256)!
		if package.name in package_paths && archive_pins[package_paths[package.name]] != package.sha256 {
			return error('conflicting locked package version: ' + package.name)
		}
		archive_pins[archive] = package.sha256
		package_paths[package.name] = archive
		names << package.name
	}
	return names
}

fn collect(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + if prefix == '' { '' } else { '/' + prefix })!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { collect(root, key, mut pins)! }
			.regular { pins[key] = digest(path)! }
			else { return error('deployment contains a link or special file: ' + key) }
		}
	}
}

fn retain_sources(repo string, output string, directory string, mut pins map[string]string) ! {
	mut names := os.ls(repo + '/' + directory)!
	names.sort()
	for name in names {
		path := directory + '/' + name
		kind := os.lstat(repo + '/' + path)!.get_filetype()
		if kind == .directory { retain_sources(repo, output, path, mut pins)! }
		if kind != .regular || !(name.ends_with('.v') || name.ends_with('.h')) { continue }
		expected := digest(repo + '/' + path)!
		to := output + '/sources/' + path
		os.mkdir_all(os.dir(to))!
		os.cp(repo + '/' + path, to)!
		os.chmod(to, 0o444)!
		pin(to, expected)!
		pins[path] = expected
	}
}

fn manifest(uid int, files map[string]string, external map[string]string) string {
	mut lines := ['vinix-android-browser-launch-v1',
		'exclusive-principal\t${uid}\t${uid}\t/var/lib/vinix/apps/${uid}/data', 'root\t' + guest_root,
		'loader\tlib/ld-musl-aarch64.so.1', 'engine\tbin/webview-engine', 'xvfb\tusr/bin/Xvfb',
		'libraries\t' + library_directories.join(':'), 'xkb\tusr/share/X11/xkb',
		'fonts\tusr/share/fonts/misc', 'fontconfig\tetc/fonts/browser.conf']
	mut keys := files.keys()
	keys.sort()
	for key in keys { lines << 'file\t' + files[key] + '\t' + key }
	keys = external.keys()
	keys.sort()
	for key in keys { lines << 'external\t' + external[key] + '\t' + key }
	return lines.join('\n') + '\n'
}

fn check_elf(root string, files map[string]string) ! {
	for name, _ in files {
		path := root + '/' + name
		mut file := os.open(path)!
		mut magic := []u8{len: 4}
		n := file.read(mut magic) or { 0 }
		file.close()
		if n != 4 || magic != [u8(0x7f), `E`, `L`, `F`] { continue }
		elf := mapsaccountstage.inspect_elf(os.read_bytes(path)!)!
		if !allowed_runpath(name, files[name], elf.runpath) {
			return error('browser ELF contains a search-path override: ' + name)
		}
		for needed in elf.needed {
			mut found := false
			for directory in library_directories {
				if directory + '/' + needed in files {
					found = true
					break
				}
			}
			if !found {
				return error('browser ELF dependency missing: ' + name + ' -> ' + needed)
			}
		}
	}
}

fn musl_alias(root string, toolchain string, mut files map[string]string) ![]string {
	loader := 'lib/ld-musl-aarch64.so.1'
	libc := 'lib/libc.musl-aarch64.so.1'
	alias := 'lib/libc.so'
	if loader !in files || libc !in files || files[loader] != files[libc]
		|| alias in files || os.exists(root + '/' + alias) || os.is_link(root + '/' + alias) {
		return error('independent musl alias requires identical pinned loader and libc')
	}
	engine_bytes := os.read_bytes(root + '/bin/webview-engine')!
	runtime_bytes := os.read_bytes(root + '/' + libc)!
	toolchain_bytes := os.read_bytes(toolchain)!
	engine := mapsaccountstage.inspect_elf(engine_bytes)!
	runtime := mapsaccountstage.inspect_elf(runtime_bytes)!
	compiler := mapsaccountstage.inspect_elf(toolchain_bytes)!
	if engine.needed != ['libc.so'] || engine.interpreter != '/lib/ld-musl-aarch64.so.1'
		|| runtime.soname != 'libc.musl-aarch64.so.1' || runtime.needed.len != 0
		|| runtime.interpreter != '' || runtime.runpath != '' || compiler.needed.len != 0
		|| compiler.interpreter != '' || compiler.runpath != '' || compiler.soname != '' {
		return error('unexpected musl engine or libc dynamic contract')
	}
	verified := muslabi.verify(muslabi.inspect(engine_bytes)!, muslabi.inspect(toolchain_bytes)!,
		muslabi.inspect(runtime_bytes)!)!
	os.cp(root + '/' + libc, root + '/' + alias)!
	os.chmod(root + '/' + alias, 0o555)!
	pin(root + '/' + alias, files[libc])!
	files[alias] = files[libc]
	return verified
}

fn allowed_runpath(name string, checksum string, runpath string) bool {
	if runpath == '' { return true }
	// These pinned releases carry fallback paths. The launcher's private
	// LD_LIBRARY_PATH takes precedence, and check_elf requires every dependency
	// in that protected tree. No other search-path override is accepted.
	match name {
		'usr/lib/libsqlite3.so.0', 'usr/lib/libsqlite3.so.3.53.4' {
			return checksum == '5a228127ca3ffa0c88bcae0aa5f7ab10e15b383dfb46822c573013105628bbaa'
				&& runpath == '/usr/lib'
		}
		'usr/lib/libLLVM-23.so', 'usr/lib/libLLVM.so.23.1' {
			return checksum == '9ae7d1082a730f4214dfe67be55eadd64f2a907afb17a140a3299c8ae7c17a78'
				&& runpath == '/usr/lib/llvm23'
		}
		'usr/lib/libproxy.so.1', 'usr/lib/libproxy.so.0.5.12' {
			return checksum == '3a1304f3d8575a64f2b0059f56e77bda3a2ee95bfe69bac5d8047264f25b3666'
				&& runpath == '/usr/lib/libproxy'
		}
		'usr/lib/libproxy/libpxbackend-1.0.so' {
			return checksum == '5b8028197a47c1e72654bdf65201294a11c94c2517b4c5ca0f8194e97751d825'
				&& runpath == '/usr/lib/libproxy'
		}
		else { return false }
	}
}

fn run() ! {
	if os.args.len != 13 {
		return error('usage: build REPO BASE_RUNTIME BASE_MANIFEST_SHA BASE_APK_CACHE ADDON_BUILD ADDON_BUILD_SHA ADDON_APK_CACHE ENGINE_BUILD ENGINE_INVENTORY_SHA TOOLCHAIN_LIBC TOOLCHAIN_LIBC_SHA FRESH_OUTPUT')
	}
	repo := os.real_path(os.args[1])
	base, base_seal, base_cache := os.real_path(os.args[2]), os.args[3], os.real_path(os.args[4])
	addon, addon_seal, addon_cache := os.real_path(os.args[5]), os.args[6], os.real_path(os.args[7])
	engine, engine_seal := os.real_path(os.args[8]), os.args[9]
	toolchain, toolchain_seal := os.real_path(os.args[10]), os.args[11]
	output := os.abs_path(os.args[12])
	if os.exists(output) || os.is_link(output) || output == repo || output.starts_with(repo + '/') {
		return error('fresh external deployment output required')
	}
	pin(base + '/runtime-manifest.json', base_seal)!
	pin(addon + '/build.json', addon_seal)!
	addon_build := json2.decode[AddonBuild](os.read_file(addon + '/build.json')!)!
	if addon_build.runtime_manifest_sha256 != base_seal {
		return error('addon belongs to a different base runtime')
	}
	addon_lock := addon + '/sources/packages.lock.json'
	pin(addon_lock, addon_build.addon_lock_sha256)!
	engine_build := sealed_engine(engine, engine_seal)!
	if os.lstat(toolchain)!.get_filetype() != .regular { return error('regular toolchain libc required') }
	pin(toolchain, toolchain_seal)!
	os.mkdir_all(output)!
	if os.real_path(output) != output { return error('canonical external output required') }
	mut source_pins := map[string]string{}
	for directory in ['tests/android-browser-deployment', 'tests/native-android-ws/mapsaccountstage',
		'build-support/tarstream', 'build-support/tarcore', 'build-support/android/modulestream'] {
		retain_sources(repo, output, directory, mut source_pins)!
	}
	os.mkdir(output + '/inputs')!
	for name, path in {
		'base-runtime.json':     base + '/runtime-manifest.json'
		'addon-build.json':      addon + '/build.json'
		'addon-packages.json':   addon_lock
		'engine-build.json':     engine + '/build.json'
		'engine-inventory.json': engine + '/build-sha256.json'
		'toolchain-libc.so':     toolchain
	} {
		os.cp(path, output + '/inputs/' + name)!
	}
	os.cp(os.executable(), output + '/builder')!
	os.chmod(output + '/builder', 0o555)!
	scratch := output + '/package-runtime'
	os.mkdir(scratch)!
	mut archives := map[string]string{}
	mut extracted := map[string]string{}
	mut package_paths := map[string]string{}
	packages(base + '/runtime-manifest.json', base_cache, mut archives, mut package_paths)!
	mut roots := ['webkit2gtk-6.0', 'gtk4.0', 'glib-networking', 'bubblewrap', 'font-dejavu',
		'font-noto', 'ca-certificates-bundle']
	roots << packages(addon_lock, addon_cache, mut archives, mut package_paths)!
	selected := browserclosure.select_packages(package_paths, roots)!
	println('BROWSER-DEPLOYMENT packages=' + selected.len.str())
	for package_name in selected {
		browserclosure.extract(package_paths[package_name], scratch, mut extracted)!
	}
	for name, expected in addon_build.runtime_references {
		if name in extracted { pin(scratch + '/' + name, expected)! }
	}
	closure_root := output + '/payload' + guest_root
	os.mkdir_all(os.dir(closure_root))!
	mut files := browserclosure.materialize(scratch, closure_root)!
	println('BROWSER-DEPLOYMENT materialized=' + files.len.str())
	os.mkdir_all(closure_root + '/bin')!
	os.cp(engine + '/webview-engine', closure_root + '/bin/webview-engine')!
	os.chmod(closure_root + '/bin/webview-engine', 0o555)!
	pin(closure_root + '/bin/webview-engine', engine_build.engine_sha256)!
	files['bin/webview-engine'] = engine_build.engine_sha256
	verified_symbols := musl_alias(closure_root, output + '/inputs/toolchain-libc.so', mut files)!
	os.mkdir_all(closure_root + '/etc/fonts')!
	fontconfig := '<?xml version="1.0"?>\n<fontconfig><dir>' + guest_root + '/usr/share/fonts</dir><cachedir prefix="xdg">fontconfig</cachedir></fontconfig>\n'
	os.write_file(closure_root + '/etc/fonts/browser.conf', fontconfig)!
	os.chmod(closure_root + '/etc/fonts/browser.conf', 0o444)!
	files['etc/fonts/browser.conf'] = digest(closure_root + '/etc/fonts/browser.conf')!
	fontindex.write_index(closure_root + '/usr/share/fonts/misc')!
	files['usr/share/fonts/misc/fonts.dir'] = digest(closure_root + '/usr/share/fonts/misc/fonts.dir')!
	if bundle_path !in files { return error('WebKit injected bundle missing') }
	check_elf(closure_root, files)!
	println('BROWSER-DEPLOYMENT elf-closure-verified')
	mut external := map[string]string{}
	mut external_paths := helpers.clone()
	external_paths << trust
	for name in external_paths {
		if name !in files { return error('fixed-path browser helper missing: ' + name) }
		to := output + '/payload/' + name
		os.mkdir_all(os.dir(to))!
		os.cp(closure_root + '/' + name, to)!
		os.chmod(to, if name == trust { 0o444 } else { 0o555 })!
		pin(to, files[name])!
		external['/' + name] = files[name]
	}
	os.mkdir(output + '/manifests')!
	for name, uid in {
		'maps': 10012
		'gms':  10013
	} {
		os.write_file(output + '/manifests/' + name + '.manifest', manifest(uid, files, external))!
		os.chmod(output + '/manifests/' + name + '.manifest', 0o444)!
	}
	mut payload := map[string]string{}
	collect(output + '/payload', '', mut payload)!
	mut entries := []Entry{}
	mut paths := payload.keys()
	paths.sort()
	for path in paths {
		st := os.lstat(output + '/payload/' + path)!
		entries << Entry{path, payload[path], st.size, u32(st.mode & 0o7777), 0, 0}
	}
	for archive_path, archive_pin in archives { pin(archive_path, archive_pin)! }
	pin(base + '/runtime-manifest.json', base_seal)!
	pin(addon + '/build.json', addon_seal)!
	pin(addon_lock, addon_build.addon_lock_sha256)!
	sealed_engine(engine, engine_seal)!
	pin(toolchain, toolchain_seal)!
	pin(output + '/inputs/toolchain-libc.so', toolchain_seal)!
	for source_path, source_pin in source_pins {
		pin(repo + '/' + source_path, source_pin)!
		pin(output + '/sources/' + source_path, source_pin)!
	}
	os.rmdir_all(scratch)!
	os.write_file(output + '/package-files.json', json2.encode(extracted, prettify: true) + '\n')!
	os.write_file(output + '/archive-inputs.json', json2.encode(archives, prettify: true) + '\n')!
	os.write_file(output + '/selected-packages.json', json2.encode(selected, prettify: true) + '\n')!
	os.write_file(output + '/source-inputs.json', json2.encode(source_pins, prettify: true) + '\n')!
	os.write_file(output + '/payload-files.json', json2.encode(entries, prettify: true) + '\n')!
	os.write_file(output + '/musl-abi.json', json2.encode({
		'toolchain_libc_sha256': json2.Any(toolchain_seal)
		'runtime_libc_sha256': json2.Any(files['lib/libc.so'])
		'engine_sha256': json2.Any(engine_build.engine_sha256)
		'alias': json2.Any('lib/libc.so')
		'source': json2.Any('lib/libc.musl-aarch64.so.1')
		'version_requirements': json2.Any(false)
		'verified_symbols': json2.Any(verified_symbols)
	}, prettify: true) + '\n')!
	os.write_file(output + '/build.json', json2.encode({
		'format':                  json2.Any(1)
		'source_revision':         json2.Any(os.exec(['git', '-C', repo, 'rev-parse', 'HEAD']).output.trim_space())
		'base_manifest_sha256':    json2.Any(base_seal)
		'addon_build_sha256':      json2.Any(addon_seal)
		'engine_inventory_sha256': json2.Any(engine_seal)
		'engine_sha256':           json2.Any(engine_build.engine_sha256)
		'toolchain_libc_sha256':   json2.Any(toolchain_seal)
		'builder_sha256':          json2.Any(digest(output + '/builder')!)
		'argv':                    json2.Any(os.args)
		'closure_root':            json2.Any(guest_root)
		'guest_executed':          json2.Any(false)
		'login_verified':          json2.Any(false)
		'sandbox_qualified':       json2.Any(false)
		'maps_manifest_sha256':    json2.Any(digest(output + '/manifests/maps.manifest')!)
		'gms_manifest_sha256':     json2.Any(digest(output + '/manifests/gms.manifest')!)
	}, prettify: true) + '\n')!
	mut artifacts := map[string]string{}
	collect(output, '', mut artifacts)!
	os.write_file(output + '/sha256.json', json2.encode(artifacts, prettify: true) + '\n')!
	println('BROWSER-DEPLOYMENT-PREPARED root=' + output + ' seal=' + digest(output + '/sha256.json')!)
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
