// SPDX-License-Identifier: GPL-2.0-or-later
// Real SQLite and FFmpeg closures in one composed publisher release.
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct InputArtifact { path string bytes u64 sha256 string }
struct InputRecord { format int version string artifacts []InputArtifact }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt {
	format int = 1
	architecture string
	completed_at i64
	platform string = 'qemu-tcg'
	scenario string = 'packages-composition'
	seconds f64
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	data := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(data.len), sha256: sha256.sum(data).hex() }
}

fn suite(sandbox string) hwhost.Suite {
	return hwhost.Suite{
		name: 'package-composition'
		guest: 'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
		]
		binaries: [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
		files: [
			hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
		]
		directories: ['run', 'home', 'var/log', 'tmp:1777']
		scenarios: [hwhost.Scenario{
			name: 'packages-composition'
			arches: ['aarch64', 'x86_64']
			about: 'composed SQLite/FFmpeg catalog, runtime-only update, rollback and offline cache reinstall'
			required: ['HWTEST START packages-composition',
				'PACKAGE COMPOSITION canonical-order scoped-roots pinned-two-target-catalog single-signed-publisher PASS',
				'PACKAGE COMPOSITION real-sqlite-wal ffmpeg-audio ffprobe explicit-grants ordinary-owner distinct-runtimes PASS',
				'PACKAGE COMPOSITION reviewed-runtime-only-upgrade unchanged-media rollback offline-cache-reinstall clean-uninstall retained-data PASS',
				'HWTEST PASS packages-composition']
			ending: .poweroff
			forbidden: ['V panic:', 'FAIL: fn main.qualify_package_composition']
			timeout: 600
		}]
	}
}

fn stage_profile(profile string, inputs string, root string) ![]Artifact {
	if !os.is_dir(inputs) || os.is_link(inputs) { return error('profile inputs must be an ordinary directory: ${profile}') }
	text := os.read_file(inputs + '/build.json')!
	record := json2.decode[InputRecord](text)!
	if record.format != 1 || record.version != if profile == 'sqlite' { '3.53.4' } else { '8.0.1' }
		|| record.artifacts.len != if profile == 'sqlite' { 28 } else { 42 } { return error('expected the complete pinned ${profile} build record') }
	mut expected := []string{}
	for arch in ['aarch64', 'x86_64'] {
		if profile == 'sqlite' {
			for variant in ['base', 'math'] {
				for path in ['bin/sqlite3', 'bin/vinix-linux-runner', 'lib/libc.so', 'lib/libsqlite3.so.0',
					'licenses/sqlite-COPYRIGHT', 'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING'] { expected << variant + '/' + arch + '/' + path }
			}
		} else {
			for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so',
				'lib/libavcodec.so.62', 'lib/libavdevice.so.62', 'lib/libavfilter.so.11', 'lib/libavformat.so.62',
				'lib/libavutil.so.60', 'lib/libswresample.so.6', 'lib/libswscale.so.9',
				'licenses/ffmpeg-LICENSE.md', 'licenses/ffmpeg-COPYING.LGPLv2.1', 'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING', 'licenses/v-COPYRIGHT',
				'sources/ffmpeg.tar.xz', 'sources/build.json', 'sources/linux-runner.v', 'sources/ffmpeg-build.v', 'sources/ffmpeg-source.json'] { expected << 'roots/' + arch + '/' + path }
		}
	}
	base := root + '/usr/share/composition-fixtures'
	os.mkdir_all(base)!
	os.write_file(base + '/build-' + profile + '.json', text)!
	mut artifacts := [artifact('input-build-' + profile, inputs + '/build.json')!]
	for item in record.artifacts {
		if !item.path.starts_with(inputs + '/') { return error('build artifact is outside the ${profile} inputs') }
		relative := item.path[inputs.len + 1..]
		if relative !in expected || os.is_link(item.path) || !os.is_file(item.path) { return error('unexpected ${profile} input: ${item.path}') }
		expected.delete(expected.index(relative))
		bytes := os.read_bytes(item.path)!
		if u64(bytes.len) != item.bytes || sha256.sum(bytes).hex() != item.sha256 { return error('changed ${profile} input: ${relative}') }
		staged := if profile == 'sqlite' { relative } else { relative.all_after('roots/') }
		destination := base + '/' + profile + '/' + staged
		os.mkdir_all(os.dir(destination))!
		os.write_file_array(destination, bytes)!
		os.chmod(destination, if relative.contains('/licenses/') || relative.contains('/sources/') { 0o644 } else { 0o755 })!
		artifacts << Artifact{ role: 'input/' + profile + '/' + staged, bytes: item.bytes, sha256: item.sha256 }
	}
	assert expected.len == 0
	return artifacts
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	definition := suite(os.getenv('VINIX_COMPOSITION_SANDBOX'))
	if options.help || options.list { return hwhost.run_suite(definition, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir)
		|| os.is_link(options.state_dir) { return error('provide --kernel and a new --state-dir') }
	if os.getenv('VINIX_HWTEST_TCG') != '1' { return error('this qualification requires VINIX_HWTEST_TCG=1') }
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select the packages-composition scenario') }
	for variable in ['VINIX_SQLITE_INPUTS', 'VINIX_FFMPEG_INPUTS'] {
		if os.getenv(variable) == '' { return error('${variable} is required') }
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	kernel := work + '/kernel'
	os.cp(options.kernel, kernel)!
	hwhost.watch_interrupts()
	guest_dir := work + '/guest'
	guest := hwhost.build_program(host, repository + '/' + definition.guest, guest_dir, 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, guest_dir)!
	mut artifacts := stage_profile('sqlite', os.abs_path(os.getenv('VINIX_SQLITE_INPUTS')), root)!
	artifacts << stage_profile('media', os.abs_path(os.getenv('VINIX_FFMPEG_INPUTS')), root)!
	for role, path in {'kernel': kernel, 'sandbox': root + '/usr/bin/vinix-sandbox',
		'guest-init': guest, 'package-service': root + '/usr/bin/vinix-package',
		'account-manager': root + '/usr/sbin/vinix-account', 'session-runner': root + '/usr/sbin/vinix-session'} { artifacts << artifact(role, path)! }
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: kernel, guest: guest, extras: root,
		state: work + '/packages-composition', timeout: if options.timeout > 600 { options.timeout } else { 600 },
		keep: true, failures_only: options.failures_only })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-composition/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
