// SPDX-License-Identifier: GPL-2.0-or-later
// Stage the pinned Xvfb additions without modifying the Android runtime.
module main

import crypto.sha256
import json2
import net.http
import os
import tarstream
import time

struct Package {
	name          string
	version       string
	filename      string
	url           string
	sha256        string
	archive_bytes u64
}

struct Lock {
	format           int
	architecture     string
	base_lock_sha256 string
	packages         []Package
}

struct BasePackage {
	name     string
	version  string
	filename string
	sha256   string
}

struct BaseLock {
	packages []BasePackage
}

struct GuestHelpers {
	format               int
	architecture         string
	source_module        string
	source_module_sha256 string
	files                map[string]string
}

struct FaultBuild {
	format             int
	shim_sha256        string
	known_fault_sha256 string
	guest_executed     bool
}

// Retain the complete small diagnostic bundle, rejecting links and special
// files so a later guest launch never follows an unrecorded host dependency.
fn copy_fault_tree(source string, target string, relative string, mut pins map[string]string, mut total []u64) ! {
	mut names := os.ls(source)!
	names.sort()
	for name in names {
		path_parts(name)!
		from := source + '/' + name
		to := target + '/' + name
		key := if relative == '' { name } else { relative + '/' + name }
		st := os.lstat(from)!
		match st.get_filetype() {
			.directory {
				os.mkdir(to)!
				copy_fault_tree(from, to, key, mut pins, mut total)!
			}
			.regular {
				if pins.len >= 128 || st.size > 16 * 1024 * 1024 || total[0] + st.size > 32 * 1024 * 1024 {
					return error('fault diagnostic bundle exceeds fixed limits')
				}
				before := hash(from)!
				os.cp(from, to)!
				os.chmod(to, int(st.mode & 0o777))!
				if hash(from)! != before || hash(to)! != before { return error('fault diagnostic changed during copy') }
				pins[key] = before
				total[0] += st.size
			}
			else { return error('fault diagnostic must contain only real directories and regular files') }
		}
	}
}

fn fault_build(root string) !FaultBuild {
	build := json2.decode[FaultBuild](os.read_file(root + '/build.json')!)!
	if build.format != 1 || build.guest_executed || build.shim_sha256.len != 64
		|| build.known_fault_sha256.len != 64
		|| hash(root + '/libx11-fault-probe.so')! != build.shim_sha256
		|| hash(root + '/known-fault')! != build.known_fault_sha256 {
		return error('unqualified fault diagnostic build')
	}
	return build
}

struct Metadata {
	name         string
	version      string
	dependencies []string
	provides     []string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn metadata(path string) !Metadata {
	mut archive := tarstream.open_concatenated(path)!
	defer { archive.close() }
	mut body := ''
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name != '.PKGINFO' { continue }
		if body != '' || !member.regular() || member.size <= 0 || member.size > 1024 * 1024 {
			return error('invalid duplicate or oversized APK metadata: ' + path)
		}
		mut bytes := []u8{len: int(member.size)}
		mut position := 0
		for position < bytes.len {
			mut part := unsafe { bytes[position..] }
			n := archive.read(mut part)!
			if n == 0 { return error('truncated APK metadata') }
			position += n
		}
		body = bytes.bytestr()
	}
	mut fields := map[string][]string{}
	for line in body.split_into_lines() {
		if line.starts_with('#') || line == '' { continue }
		pieces := line.split_nth(' = ', 2)
		if pieces.len != 2 { return error('malformed APK metadata') }
		fields[pieces[0]] << pieces[1]
	}
	if fields['pkgname'].len != 1 || fields['pkgver'].len != 1
		|| (fields['arch'] != ['aarch64'] && fields['arch'] != ['noarch']) {
		return error('APK metadata requires aarch64/noarch identity: ' + path)
	}
	return Metadata{fields['pkgname'][0], fields['pkgver'][0], fields['depend'], fields['provides']}
}

fn spec(value string) !(string, string) {
	if value == '' || value.contains_any('!<>~') {
		return error('unsupported dependency constraint: ' + value)
	}
	parts := value.split('=')
	if parts.len > 2 || parts[0] == '' || (parts.len == 2 && parts[1] == '') {
		return error('malformed dependency: ' + value)
	}
	return parts[0], if parts.len == 2 { parts[1] } else { '' }
}

fn dependencies(all []Metadata, additions []Metadata) ! {
	mut providers := map[string][]string{}
	for package in all {
		providers[package.name] << package.version
		for value in package.provides {
			name, version := spec(value)!
			providers[name] << version
		}
	}
	for package in additions {
		for value in package.dependencies {
			name, version := spec(value)!
			if name !in providers || (version != '' && version !in providers[name]) {
				return error(package.name + ': unresolved declared dependency ' + value)
			}
		}
	}
}

fn path_parts(name string) ![]string {
	if name.starts_with('/') || name.contains_any('\x00\n\r\\') {
		return error('unsafe archive path')
	}
	parts := name.trim_right('/').split('/')
	if parts.len == 0 || parts.any(it in ['', '.', '..']) {
		return error('unsafe archive path: ' + name)
	}
	return parts
}

fn link_target(name string, target string) !string {
	if target == '' || target.contains_any('\x00\n\r\\') { return error('unsafe symlink') }
	name_parts := path_parts(name)!
	parent := name_parts[..name_parts.len - 1]
	mut parts := if target.starts_with('/') { []string{} } else { parent.clone() }
	for part in target.split('/') {
		if part in ['', '.'] { continue }
		if part == '..' {
			if parts.len == 0 { return error('symlink escapes runtime') }
			parts.delete_last()
		} else {
			parts << part
		}
	}
	mut common := 0
	for common < parent.len && common < parts.len && parent[common] == parts[common] { common++ }
	mut relative := []string{}
	for _ in common .. parent.len { relative << '..' }
	relative << parts[common..]
	return if relative.len == 0 { '.' } else { relative.join('/') }
}

fn extract(path string, root string, mut inventory map[string]string) ! {
	mut archive := tarstream.open_concatenated(path)!
	defer { archive.close() }
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		parts := path_parts(member.name)!
		// Top-level signature/control files and package scripts stay in the APK.
		// Validate their paths as well; traversal must never be treated as metadata.
		if parts.len == 1 && parts[0].starts_with('.') { continue }
		name := parts.join('/')
		destination := root + '/' + name
		mut parent := root
		for component in parts[..parts.len - 1] {
			parent += '/' + component
			if os.is_link(parent) { return error('archive parent is a symlink: ' + name) }
			os.mkdir_all(parent)!
		}
		if member.kind == `5` {
			if os.is_link(destination) || os.is_file(destination) {
				return error('directory collision')
			}
			os.mkdir_all(destination)!
			continue
		}
		if name in inventory || os.exists(destination) || os.is_link(destination) {
			return error('payload collision: ' + name)
		}
		if member.regular() {
			if member.size < 0 || member.size > 16 * 1024 * 1024 {
				return error('unexpected payload size')
			}
			mut file := os.create(destination)!
			mut buffer := []u8{len: 64 * 1024}
			mut written := i64(0)
			for {
				n := archive.read(mut buffer)!
				if n == 0 { break }
				if file.write(buffer[..n])! != n { return error('short payload write') }
				written += n
			}
			file.close()
			if written != member.size { return error('truncated payload') }
			os.chmod(destination, int(member.mode & 0o777))!
			inventory[name] = hash(destination)!
		} else if member.kind == `2` {
			target := link_target(name, member.linkname)!
			os.symlink(target, destination)!
			inventory[name] = 'symlink:' + target
		} else {
			return error('unsupported APK payload kind')
		}
	}
}

fn command(root string, label string, argv []string) ! {
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '.json', json2.encode({
		'argv':          json2.Any(argv)
		'exit_code':     json2.Any(result.exit_code)
		'completed_utc': json2.Any(time.utc().str())
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
}

fn prepare() ! {
	if os.args.len !in [6, 7] {
		return error('usage: prepare OUTPUT BASE_RUNTIME BASE_APK_CACHE ADDON_APK_CACHE COMPILER [FAULT_BUILD_DIR]')
	}
	root, runtime, base_cache, cache, compiler := os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]
	if os.exists(root) || os.is_link(root) { return error('fresh output directory required') }
	sources := os.dir(os.real_path(@FILE))
	repo := os.dir(os.dir(sources))
	lock_path := sources + '/packages.lock.json'
	base_lock := repo + '/build-support/android/packages.lock.json'
	pins := json2.decode[Lock](os.read_file(lock_path)!)!
	helpers := json2.decode[GuestHelpers](os.read_file(sources + '/guest-helpers.lock.json')!)!
	if helpers.format != 1 || helpers.architecture != 'aarch64'
		|| helpers.source_module != 'initramfs.tar' || helpers.source_module_sha256.len != 64
		|| helpers.files.len != 2 || helpers.files['/usr/bin/xkbcomp'].len != 64
		|| helpers.files['/lib/ld-musl-aarch64.so.1'].len != 64 {
		return error('unexpected existing guest helper lock')
	}
	if pins.format != 1 || pins.architecture != 'aarch64' || pins.packages.len != 15 || hash(base_lock)! != pins.base_lock_sha256 {
		return error('unexpected package lock/base lock')
	}
	base := json2.decode[BaseLock](os.read_file(base_lock)!)!
	runtime_manifest := runtime + '/runtime-manifest.json'
	installed := json2.decode[BaseLock](os.read_file(runtime_manifest)!)!
	if installed.packages != base.packages {
		return error('runtime package manifest differs from base lock')
	}
	mut all := []Metadata{}
	mut refs := map[string]string{}
	for package in base.packages {
		path := base_cache + '/' + package.filename
		if hash(path)! != package.sha256 { return error('base archive checksum mismatch: ' + path) }
		item := metadata(path)!
		if item.name != package.name || item.version != package.version {
			return error('base APK identity mismatch')
		}
		all << item
		refs[path] = package.sha256
	}
	mut added := []Metadata{}
	mut archive_bytes := u64(0)
	os.mkdir_all(cache)!
	for package in pins.packages {
		if os.base(package.filename) != package.filename || package.filename != package.name + '-' + package.version + '.apk'
			|| !package.url.starts_with('https://dl-cdn.alpinelinux.org/alpine/edge/') || !package.url.ends_with('/aarch64/' + package.filename) {
			return error('invalid locked package')
		}
		archive_bytes += package.archive_bytes
		if archive_bytes > 5_600_000 { return error('supplement exceeds fixed download budget') }
		path := cache + '/' + package.filename
		if !os.exists(path) {
			response := http.get(package.url)!
			if response.status_code != 200 || u64(response.body.len) != package.archive_bytes
				|| sha256.sum(response.body.bytes()).hex() != package.sha256 {
				return error('download checksum/size mismatch: ' + package.filename)
			}
			os.write_file(path, response.body)!
		}
		if os.file_size(path) != package.archive_bytes || hash(path)! != package.sha256 {
			return error('addon archive checksum/size mismatch')
		}
		item := metadata(path)!
		if item.name != package.name || item.version != package.version {
			return error('addon APK identity mismatch')
		}
		added << item
		refs[path] = package.sha256
	}
	all << added
	dependencies(all, added)!
	os.mkdir_all(root + '/runtime')!
	os.mkdir_all(root + '/bin')!
	os.mkdir_all(root + '/sources')!
	mut fault_pins := map[string]string{}
	mut fault_build_hash := ''
	mut fault_shim_hash := ''
	mut fault_fixture_hash := ''
	if os.args.len == 7 {
		fault_root := os.real_path(os.args[6])
		fault := fault_build(fault_root)!
		os.mkdir(root + '/fault-probe')!
		mut total := [u64(0)]
		copy_fault_tree(fault_root, root + '/fault-probe', '', mut fault_pins, mut total)!
		fault_build(root + '/fault-probe')!
		fault_build_hash = fault_pins['build.json']
		fault_shim_hash = fault.shim_sha256
		fault_fixture_hash = fault.known_fault_sha256
	}
	mut files := map[string]string{}
	for package in pins.packages {
		extract(cache + '/' + package.filename, root + '/runtime', mut files)!
	}
	os.write_file(root + '/addon-files.json', json2.encode(files, prettify: true) + '\n')!
	for name in ['probe.v', 'session.v', 'guest.v', 'collect.v', 'prepare.v', 'packages.lock.json', 'guest-helpers.lock.json', 'inspect-helper.v'] {
		os.cp(sources + '/' + name, root + '/sources/' + name)!
	}
	mut source_pins := map[string]string{}
	for name in ['probe.v', 'session.v', 'guest.v', 'collect.v', 'prepare.v', 'packages.lock.json', 'guest-helpers.lock.json', 'inspect-helper.v'] {
		source_pins[name] = hash(root + '/sources/' + name)!
	}
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { return error('cannot record source base revision') }
	compiler_pin := hash(compiler)!
	cross_compiler := '/opt/homebrew/bin/aarch64-linux-musl-gcc'
	cross_compiler_pin := hash(cross_compiler)!
	for name in ['probe', 'session', 'guest'] {
		mut argv := [compiler, '-os', 'linux', '-arch', 'arm64', '-cc',
			cross_compiler, '-gc', 'none', '-prod']
		// Xvfb invokes its compiled-in xkbcomp path without our musl loader.
		// The session trampoline and directly launched guest runner are static.
		if name in ['session', 'guest'] {
			argv << '-cflags'
			argv << '-static'
		}
		argv << ['-o', root + '/bin/browser-' + name,
			root + '/sources/' + name + '.v']
		command(root, 'build-' + name, argv)!
	}
	if hash(compiler)! != compiler_pin || hash(cross_compiler)! != cross_compiler_pin {
		return error('compiler changed during build')
	}
	mut runtime_pins := map[string]string{}
	for name in ['lib/ld-musl-aarch64.so.1', 'usr/bin/mkfontscale', 'usr/lib/libwebkitgtk-6.0.so.4',
		'usr/lib/libjavascriptcoregtk-6.0.so.1', 'usr/lib/libgtk-4.so.1',
		'usr/libexec/webkitgtk-6.0/WebKitWebProcess', 'usr/libexec/webkitgtk-6.0/WebKitNetworkProcess',
		'usr/libexec/webkitgtk-6.0/WebKitGPUProcess',
		'usr/lib/libproxy/libpxbackend-1.0.so',
		'usr/lib/webkitgtk-6.0/injected-bundle/libwebkitgtkinjectedbundle.so'] {
		runtime_pins[name] = hash(runtime + '/' + name)!
	}
	os.write_file(root + '/build.json', json2.encode({
		'completed_utc':           json2.Any(time.utc().str())
		'source_base_revision':    json2.Any(revision.output.trim_space())
		'source_files_sha256':     json2.decode[json2.Any](json2.encode(source_pins))!
		'base_runtime':            json2.Any(runtime)
		'base_lock_sha256':        json2.Any(pins.base_lock_sha256)
		'runtime_manifest_sha256': json2.Any(hash(runtime_manifest)!)
		'addon_lock_sha256':       json2.Any(hash(lock_path)!)
		'archive_bytes':           json2.Any(archive_bytes)
		'archive_references':      json2.decode[json2.Any](json2.encode(refs))!
		'runtime_references':      json2.decode[json2.Any](json2.encode(runtime_pins))!
		'guest_helper_references': json2.decode[json2.Any](json2.encode(helpers.files))!
		'compiler_sha256':         json2.Any(compiler_pin)
		'cross_compiler_sha256':   json2.Any(cross_compiler_pin)
		'probe_sha256':            json2.Any(hash(root + '/bin/browser-probe')!)
		'session_sha256':          json2.Any(hash(root + '/bin/browser-session')!)
		'guest_sha256':            json2.Any(hash(root + '/bin/browser-guest')!)
		'fault_probe_build_sha256': json2.Any(fault_build_hash)
		'fault_probe_shim_sha256': json2.Any(fault_shim_hash)
		'fault_probe_fixture_sha256': json2.Any(fault_fixture_hash)
		'fault_probe_files_sha256': json2.decode[json2.Any](json2.encode(fault_pins))!
		'scope':                   json2.Any('Pinned APK hashes and declared name/SONAME/exact-version dependency closure checked; original APK signatures not cryptographically verified. Separate real-engine diagnostic only, no Android integration or Google authentication proof.')
	}, prettify: true) + '\n')!
	println('BROWSER-PREPARE PASS packages=' + added.len.str() + ' archive-bytes=' + archive_bytes.str() + ' payload-files=' + files.len.str())
}

fn self_test() ! {
	for value in ['/etc/passwd', '../escape', 'usr/../escape', 'usr//bin', 'usr/./bin', 'usr\\bin'] {
		mut rejected := false
		path_parts(value) or {
			rejected = true
			[]string{}
		}
		if !rejected { return error('accepted unsafe path: ' + value) }
	}
	mut rejected := false
	link_target('lib/file', '../../escape') or {
		rejected = true
		''
	}
	if !rejected { return error('accepted escaping symlink') }
	if link_target('usr/bin/sh', '/bin/osh')! != '../../bin/osh' {
		return error('absolute symlink relocation')
	}
	p := Metadata{'provider', '1-r0', [], ['pkgconfig=2-r0', 'so:libexample.so.1=1']}
	ok := Metadata{'client', '1', ['provider=1-r0', 'pkgconfig', 'so:libexample.so.1'], []}
	dependencies([p, ok], [ok])!
	for value in ['provider=2-r0', 'provider=', 'missing', 'so:libabsent.so.1', 'provider>=1'] {
		bad := Metadata{'client', '1', [value], []}
		rejected = false
		dependencies([p, bad], [bad]) or { rejected = true }
		if !rejected { return error('accepted unresolved dependency: ' + value) }
	}
	root := os.join_path(os.temp_dir(), 'vinix-browser-fault-copy-' + os.getpid().str())
	if os.exists(root) || os.is_link(root) { return error('selftest root already exists') }
	os.mkdir_all(root + '/source/sources')!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/target')!
	os.write_file(root + '/source/libx11-fault-probe.so', 'fixture-shim')!
	os.write_file(root + '/source/known-fault', 'fixture-executable')!
	os.write_file(root + '/source/sources/source.v', 'fixture-source')!
	os.chmod(root + '/source/known-fault', 0o751)!
	os.write_file(root + '/source/build.json', json2.encode(FaultBuild{
		format: 1
		shim_sha256: hash(root + '/source/libx11-fault-probe.so')!
		known_fault_sha256: hash(root + '/source/known-fault')!
	}))!
	fault_build(root + '/source')!
	mut copied := map[string]string{}
	mut total := [u64(0)]
	copy_fault_tree(root + '/source', root + '/target', '', mut copied, mut total)!
	assert copied.len == 4 && copied['sources/source.v'] == hash(root + '/target/sources/source.v')!
	assert os.lstat(root + '/target/known-fault')!.mode & 0o777 == 0o751
	fault_build(root + '/target')!
	os.write_file(root + '/target/known-fault', 'changed')!
	if _ := fault_build(root + '/target') { return error('changed fault executable accepted') }
	os.symlink('../known-fault', root + '/source/sources/link')!
	os.mkdir(root + '/rejected')!
	if _ := copy_fault_tree(root + '/source', root + '/rejected', '', mut copied, mut total) {
		return error('linked fault diagnostic source accepted')
	}
	println('BROWSER-PREPARE-CHECK PASS paths symlink providers soname exact-version unsupported-constraint fault-copy pins modes tamper symlink')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
	} else {
		prepare() or {
			eprintln(err)
			exit(1)
		}
	}
}
