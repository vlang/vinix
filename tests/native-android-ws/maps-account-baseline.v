// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only, streaming inspection of a maintained headless stage. No module or
// APK is extracted; only selected inode metadata and public authority records
// are retained. This reports provisioning, never successful authentication.
module main

import crypto.sha256
import json2
import modulestream
import os
import tarstream
import time

#include <signal.h>
fn C.kill(int, int) int

struct Entry {
	path string
	module_name string
	kind u8
	mode i64
	uid i64
	gid i64
	size i64
	linkname string
	sha256 string
	mentions []string
	registry []Authority
}

struct Authority {
	package_name string
	uid string
	gid string
	apk string
	apk_sha256 string
	certificate_sha256 string
	selectors []string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn normalize(name string) !string {
	if name.starts_with('/') || name.contains_any('\x00\n\r\\') { return error('unsafe tar name') }
	mut clean := name
	for clean.starts_with('./') { clean = clean[2..] }
	clean = clean.trim_right('/')
	if clean in ['', '.'] { return '' }
	if clean.split('/').any(it in ['', '.', '..']) { return error('unsafe tar component') }
	return clean
}

fn selected(path string) bool {
	name := os.base(path).to_lower()
	return path.ends_with('.apk') || name.contains('account') || name.contains('authenticator')
		|| name in ['run-android', 'vinix-android-native', 'libvinix-android-native.so', 'inittab',
		'rc.local', 'profile', 'environment'] || path.starts_with('etc/init.d/')
		|| path.starts_with('etc/profile.d/') || path.starts_with('etc/rc.d/')
		|| path.ends_with('.service') || path.starts_with('opt/vinix-headless-service/')
		|| path.starts_with('usr/share/applications/') || path.starts_with('root/.local/share/applications/')
}

fn text_candidate(path string) bool {
	name := os.base(path).to_lower()
	return (path.starts_with('etc/') && !name.contains('shadow') && !name.contains('password')
		&& !name.contains('secret') && !name.contains('token') && !name.contains('credential'))
		|| path.ends_with('.desktop') || name in ['run-android', 'rc.local']
}

fn authorities(text string) ![]Authority {
	if !text.starts_with('vinix-android-account-authority-v1\n') { return []Authority{} }
	if !text.ends_with('\n') || text.contains_any('\x00\r') || text.len > 65536 {
		return error('invalid account authority framing')
	}
	lines := text.trim_right('\n').split('\n')
	if lines.len < 2 || lines.len > 65 { return error('invalid authority row count') }
	mut result := []Authority{}
	for line in lines[1..] {
		fields := line.split('\t')
		if fields.len != 7 || !pin(fields[4]) || !pin(fields[5]) {
			return error('invalid account authority row')
		}
		result << Authority{fields[0], fields[1], fields[2], fields[3], fields[4], fields[5],
			if fields[6] == '-' { []string{} } else { fields[6].split(',') }}
	}
	return result
}

fn mentions(text string) []string {
	mut result := []string{}
	for needle in ['native-account-broker', 'VINIX_ANDROID_ACCOUNT_REGISTRY',
		'VINIX_ANDROID_ACCOUNT_SOCKET', 'VINIX_ANDROID_AUTHENTICATOR_TYPE',
		'android.accounts.AccountAuthenticator', 'com.google.android.gms',
		'vinix-android-account-authority-v1'] {
		if text.contains(needle) { result << needle }
	}
	return result
}

fn modules(config string) ![]string {
	mut result := []string{}
	mut entries := 0
	for line in config.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('/') || trimmed.starts_with(':') { entries++ }
		if !trimmed.starts_with('module_path:') { continue }
		prefix := 'module_path: boot():/boot/'
		if entries != 1 || !trimmed.starts_with(prefix) { return error('ambiguous Limine module') }
		name := trimmed[prefix.len..]
		if !name.ends_with('.tar') || name in result || name.contains('/')
			|| !name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`)
				|| it in [`-`, `_`, `.`]) { return error('unsafe Limine member') }
		result << name
	}
	if entries != 1 || result.len == 0 { return error('expected one populated Limine entry') }
	return result
}

fn scan(mcopy string, boot string, module_name string, mut effective map[string]Entry) !int {
	mut child := os.new_process(mcopy)
	child.use_pgroup = true
	child.set_args(['-i', boot, '::/boot/' + module_name, '-'])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut archive := tarstream.from_descriptor(i32(child.stdio_fd[1]))!
	defer { archive.close() }
	mut count := 0
	for {
		member := archive.next() or { if err is tarstream.End { break }; return err }
		path := normalize(member.name)!
		if path == '' { continue }
		count++
		mut digest := ''
		mut text := ''
		if selected(path) && member.regular() {
			if member.size <= 65536 && text_candidate(path) {
				mut bytes := []u8{len: int(member.size)}
				mut offset := 0
				for offset < bytes.len {
					n := archive.read(mut bytes[offset..])!
					if n == 0 { return error('truncated selected member') }
					offset += n
				}
				digest = sha256.sum(bytes).hex()
				text = bytes.bytestr()
			} else { digest = archive.digest()! }
		}
		effective[path] = Entry{path, module_name, member.kind, member.mode, member.uid,
			member.gid, member.size, member.linkname, digest, mentions(text), authorities(text)!}
	}
	mut diagnostics := ''
	for {
		child.stdout_read()
		diagnostics += child.stderr_read()
		if diagnostics.len > 65536 { return error('oversized mcopy diagnostic') }
		if !child.is_alive() { break }
		time.sleep(time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		diagnostics += err
		if diagnostics.len > 65536 { return error('oversized mcopy diagnostic') }
	}
	child.wait()
	finished = true
	if child.code != 0 { return error('mcopy failed: ' + diagnostics) }
	return count
}

fn run() ! {
	if os.args.len != 4 { return error('usage: maps-account-baseline STAGE STAGE_JSON_SHA256 FRESH_EXTERNAL_OUTPUT') }
	stage, expected, root := os.args[1], os.args[2], os.args[3]
	if !pin(expected) || os.real_path(stage) != stage || !os.is_dir(stage)
		|| !os.is_abs_path(root) || os.exists(root) || os.is_link(root)
		|| os.real_path(os.dir(root)) != os.dir(root) || !os.is_dir(os.dir(root))
		|| root == stage || root.starts_with(stage + '/') || stage.starts_with(root + '/') {
		return error('expected canonical stage and fresh disjoint output directory')
	}
	if hash(stage + '/stage.json')! != expected { return error('stage receipt pin differs') }
	receipt := json2.decode[map[string]json2.Any](os.read_file(stage + '/stage.json')!)!
	boot := stage + '/boot.img'
	boot_pin := receipt['staged_boot_sha256']!.str()
	if hash(boot)! != boot_pin { return error('boot image differs') }
	mcopy := os.find_abs_path_of_executable('mcopy')!
	mtype := os.find_abs_path_of_executable('mtype')!
	mut child := os.new_process(mtype)
	child.set_args(['-i', boot, '::/boot/limine.conf'])
	child.set_redirect_stdio()
	child.run()
	config := child.stdout_slurp()
	diagnostics := child.stderr_slurp()
	child.wait()
	if child.code != 0 { child.close(); return error('mtype failed: ' + diagnostics) }
	child.close()
	if sha256.sum(config.bytes()).hex() != receipt['limine_after_sha256']!.str() {
		return error('Limine configuration differs')
	}
	module_names := modules(config)!
	mut module_pins := json2.decode[map[string]string](json2.encode(receipt['preserved_modules_sha256']!))!
	if 'headless-service.tar' in module_pins { return error('ambiguous overlay receipt') }
	module_pins['headless-service.tar'] = receipt['overlay_sha256']!.str()
	if module_names.len != module_pins.len || module_names.last() != 'headless-service.tar' {
		return error('module order or count differs')
	}
	os.mkdir(root)!
	os.write_file(root + '/limine.conf', config)!
	mut effective := map[string]Entry{}
	mut counts := map[string]int{}
	for name in module_names {
		if !pin(module_pins[name] or { return error('missing module pin') }) { return error('invalid module pin') }
		result := modulestream.hash_member(boot, name, root + '/' + name + '.hash-command')!
		if result.sha256 != module_pins[name]! { return error('module differs: ' + name) }
		println('BASELINE-SCAN ' + name)
		counts[name] = scan(mcopy, boot, name, mut effective)!
	}
	mut selected_entries := []Entry{}
	mut ancestors := map[string]Entry{}
	mut keys := effective.keys()
	keys.sort()
	for key in keys {
		if !selected(key) { continue }
		selected_entries << effective[key]!
		mut parent := os.dir(key)
		for parent !in ['', '.'] {
			if parent in effective { ancestors[parent] = effective[parent]! }
			parent = os.dir(parent)
		}
	}
	if hash(boot)! != boot_pin || hash(stage + '/stage.json')! != expected {
		return error('stage changed during inspection')
	}
	os.write_file(root + '/selected-entries.json', json2.encode(selected_entries))!
	os.write_file(root + '/ancestor-entries.json', json2.encode(ancestors))!
	os.write_file(root + '/inspection.json', json2.encode({
		'kind': json2.Any('vinix-maps-account-baseline-v1')
		'stage': json2.Any(stage)
		'stage_json_sha256': json2.Any(expected)
		'boot_sha256': json2.Any(boot_pin)
		'modules_sha256': json2.decode[json2.Any](json2.encode(module_pins))!
		'module_entries': json2.decode[json2.Any](json2.encode(counts))!
		'effective_entries': json2.Any(effective.len)
		'selected_entries_sha256': json2.Any(hash(root + '/selected-entries.json')!)
		'ancestor_entries_sha256': json2.Any(hash(root + '/ancestor-entries.json')!)
		'source_sha256': json2.Any(hash(@FILE)!)
	}))!
	println('BASELINE-INSPECTION-PASS ' + root)
}

fn self_test() ! {
	if normalize('./etc/init.d/')! != 'etc/init.d' || !selected('a/native-account-broker')
		|| !selected('a/services.registry.apk') || selected('etc/shadow') || text_candidate('etc/shadow') {
		return error('path selection self-test')
	}
	for value in ['/absolute', '../escape', 'a//b', 'a/../b'] {
		if _ := normalize(value) { return error('accepted unsafe tar name') }
	}
	row := 'vinix-android-account-authority-v1\npkg\t10001\t10001\t/a.apk\t' + 'a'.repeat(64)
		+ '\t' + 'b'.repeat(64) + '\tpkg.Auth@android.accounts.AccountAuthenticator@com.google\n'
	if authorities(row)![0].selectors[0] != 'pkg.Auth@android.accounts.AccountAuthenticator@com.google'
		|| authorities('unrelated text')!.len != 0 {
		return error('public authority parser self-test')
	}
	println('MAPS-ACCOUNT-BASELINE-SELF-TEST-PASS')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	run() or { eprintln(err); exit(1) }
}
