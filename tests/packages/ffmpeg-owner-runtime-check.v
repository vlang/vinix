// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-ffmpeg-owner' seconds f64 artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	mut required := ['HWTEST START packages-ffmpeg-owner', 'HWTEST PASS packages-ffmpeg-owner',
		'FFMPEG METADATA 1152 cycles retire templates, partial inventories, canonicalization, replies and late refusals PASS',
		'FFMPEG METADATA independent replies survive caller retirement and close idempotently PASS',
		'FFMPEG OWNER PROCESS metadata  PASS', 'FFMPEG OWNER PROCESS profile  PASS']
	for mode in ['complete', 'packed-3', 'packed-6', 'import-elf', 'import-source', 'changed-lock', 'flush', 'cleanup']! {
		required << 'FFMPEG OWNER case=' + mode + ' retained=0 allocations=0'
		required << 'FFMPEG OWNER PROCESS builder case ' + mode + ' PASS'
		required << 'FFMPEG OWNER ' + mode + ' canonical retry, saved output, source and descriptor preservation PASS'
	}
	mut programs := []hwhost.Program{}
	for pair in [['builder', 'ffmpeg_builder_ownership'], ['metadata', 'ffmpeg_profile_ownership'], ['profile', 'ffmpeg_profile']] {
		programs << hwhost.Program{ source: 'tools/packages/pkgcore/' + pair[1] + '_test.v', path: 'usr/share/package-fixtures/' + pair[0],
			flags: if pair[0] != 'profile' { ['-manualfree', '-d', 'track_heap'] } else { ['-manualfree'] } }
	}
	return hwhost.Suite{ name: 'package-ffmpeg-owner', guest: 'tests/packages/ffmpeg-owner-guest', module_paths: ['.', 'tools/accounts'],
		directories: ['tmp:1777'], programs: programs, scenarios: [hwhost.Scenario{ name: 'packages-ffmpeg-owner',
			arches: ['aarch64', 'x86_64'], about: '1152 FFmpeg metadata cycles and selected eight complete-call cases using the reviewed full source archive',
			required: required, forbidden: ['Out of memory', 'V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 900 }] }
}

fn qualify() !int {
	options := hwhost.parse_options(os.args[1..])!; base := suite()
	if options.help || options.list { return hwhost.run_suite(base, os.args[1..], @FILE) }
	archive := os.getenv('VINIX_PROFILE_EXPORT_SOURCE')
	if !os.is_file(archive) || os.file_size(archive) != 11388848 || sha256.sum(os.read_bytes(archive)!).hex() != '05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41' {
		return error('provide VINIX_PROFILE_EXPORT_SOURCE with the reviewed FFmpeg 8.0.1 source archive')
	}
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	definition := hwhost.Suite{ ...base, files: [hwhost.RootFile{ path: 'usr/share/package-fixtures/ffmpeg.tar.xz', text: os.read_file(archive)! }] }
	repository := hwhost.find_root(@FILE)!; host := hwhost.find_host(repository, options.arch, options.qemu)!
	hwhost.validate_scenarios(definition.scenarios)!; selection := hwhost.select_scenarios(definition.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-ffmpeg-owner') }
	os.mkdir_all(options.state_dir)!; work := os.real_path(options.state_dir); os.cp(options.kernel, work + '/kernel')!; hwhost.watch_interrupts()
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	mut artifacts := [artifact('kernel', work + '/kernel')!, artifact('guest-init', guest)!]
	for name in ['builder', 'metadata', 'profile']! { artifacts << artifact(name, root + '/usr/share/package-fixtures/' + name)! }
	artifacts << artifact('source-archive', root + '/usr/share/package-fixtures/ffmpeg.tar.xz')!
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-ffmpeg-owner', timeout: if options.timeout > 900 { options.timeout } else { 900 }, keep: true })
	println(hwhost.report(options.arch, outcome)); if outcome.interrupted { return 130 }; if !outcome.passed { return 1 }
	artifacts << artifact('serial-log', work + '/packages-ffmpeg-owner/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(qualify() or { eprintln(err); 2 }) }
