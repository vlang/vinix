// SPDX-License-Identifier: GPL-2.0-or-later
// Real upstream FFmpeg lifecycle through signed app/runtime packages.
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct InputArtifact {
	path string
	bytes u64
	sha256 string
}

struct InputRecord {
	format int
	version string
	artifacts []InputArtifact
}

struct Artifact {
	role string
	bytes u64
	sha256 string
}

struct Receipt {
	format int = 1
	architecture string
	completed_at i64
	platform string = 'qemu-tcg'
	scenario string = 'packages-ffmpeg'
	seconds f64
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	data := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(data.len), sha256: sha256.sum(data).hex() }
}

fn suite(sandbox string) hwhost.Suite {
	return hwhost.Suite{
		name: 'package-ffmpeg-runtime'
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
			name: 'packages-ffmpeg'
			arches: ['aarch64', 'x86_64']
			about: 'real FFmpeg encode/decode/probe, separate file grants, shared runtime removal, rollback and offline reinstall'
			required: ['HWTEST START packages-ffmpeg',
				'PACKAGE FFMPEG real-video-encode decode probe audio-pcm literal-arguments terminal-arguments ordinary-owner explicit-file-grant outside-path-refusal PASS',
				'PACKAGE FFMPEG signed-canonical-catalog shared-runtime removal rollback offline-cache-reinstall retained-media PASS',
				'HWTEST PASS packages-ffmpeg']
			ending: .poweroff
			forbidden: ['V panic:', 'FAIL: fn main.qualify_package_ffmpeg']
			timeout: 600
		}]
	}
}

// Both targets are publisher inputs, including the foreign ELF files. These
// are data, never suite executables; only the selected host's closure is run.
fn stage_inputs(inputs string, root string) ![]Artifact {
	text := os.read_file(inputs + '/build.json')!
	record := json2.decode[InputRecord](text)!
	if record.format != 1 || record.version != '8.0.1' || record.artifacts.len != 42 {
		return error('expected the complete pinned FFmpeg build record')
	}
	mut expected := []string{}
	for arch in ['aarch64', 'x86_64'] {
		for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so',
			'lib/libavcodec.so.62', 'lib/libavdevice.so.62', 'lib/libavfilter.so.11', 'lib/libavformat.so.62',
			'lib/libavutil.so.60', 'lib/libswresample.so.6', 'lib/libswscale.so.9',
			'licenses/ffmpeg-LICENSE.md', 'licenses/ffmpeg-COPYING.LGPLv2.1', 'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING', 'licenses/v-COPYRIGHT',
			'sources/ffmpeg.tar.xz', 'sources/build.json', 'sources/linux-runner.v', 'sources/ffmpeg-build.v', 'sources/ffmpeg-source.json'] { expected << 'roots/' + arch + '/' + path }
	}
	mut artifacts := [artifact('input-build-record', inputs + '/build.json')!]
	for item in record.artifacts {
		if !item.path.starts_with(inputs + '/') { return error('build artifact is outside the input directory') }
		relative := item.path[inputs.len + 1..]
		if relative !in expected || os.is_link(item.path) || !os.is_file(item.path) { return error('unexpected FFmpeg input: ${item.path}') }
		expected.delete(expected.index(relative))
		bytes := os.read_bytes(item.path)!
		if u64(bytes.len) != item.bytes || sha256.sum(bytes).hex() != item.sha256 { return error('changed FFmpeg input: ${relative}') }
		destination := root + '/usr/share/ffmpeg-fixtures/' + relative.all_after('roots/')
		os.mkdir_all(os.dir(destination))!
		os.write_file_array(destination, bytes)!
		os.chmod(destination, if relative.contains('/licenses/') || relative.contains('/sources/') { 0o644 } else { 0o755 })!
		artifacts << Artifact{ role: 'input/' + relative, bytes: item.bytes, sha256: item.sha256 }
	}
	assert expected.len == 0
	return artifacts
}

fn check() !int {
	options := hwhost.parse_options(os.args[1..])!
	definition := suite(os.getenv('VINIX_FFMPEG_SANDBOX'))
	if options.help || options.list { return hwhost.run_suite(definition, os.args[1..], @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir)
		|| os.is_link(options.state_dir) { return error('provide --kernel and a new --state-dir') }
	if os.getenv('VINIX_HWTEST_TCG') != '1' { return error('this qualification requires VINIX_HWTEST_TCG=1') }
	hwhost.validate_scenarios(definition.scenarios)!
	selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select the packages-ffmpeg scenario') }
	inputs := os.abs_path(os.getenv('VINIX_FFMPEG_INPUTS'))
	if !os.is_dir(inputs) || os.is_link(inputs) { return error('VINIX_FFMPEG_INPUTS must name the built inputs directory') }
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
	mut artifacts := stage_inputs(inputs, root)!
	for role, path in {'kernel': kernel, 'sandbox': root + '/usr/bin/vinix-sandbox',
		'guest-init': guest, 'package-service': root + '/usr/bin/vinix-package',
		'account-manager': root + '/usr/sbin/vinix-account', 'session-runner': root + '/usr/sbin/vinix-session'} {
		artifacts << artifact(role, path)!
	}
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: kernel, guest: guest, extras: root,
		state: work + '/packages-ffmpeg', timeout: if options.timeout > 600 { options.timeout } else { 600 },
		keep: true, failures_only: options.failures_only })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-ffmpeg/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check() or { eprintln(err); 2 }) }
