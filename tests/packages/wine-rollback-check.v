// SPDX-License-Identifier: GPL-2.0-or-later
// Local rollback diagnostic against an immutable signed image. This does not
// replace fresh signing/install qualification or admit another Wine version.
module main

import crypto.sha256
import hwhost
import json2
import os
import tests.packages.wineoverlay
import tests.packages.winesource

struct RollbackOverlay {
	baseline string
	baseline_sha256 string
	kernel string
	kernel_sha256 string
	guest string
	guest_sha256 string
	tar wineoverlay.Span
	old_init_sha256 string
}

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		if wineoverlay.digest(path)! != expected { return error('rollback diagnostic input changed: ' + path) }
	}
}

fn pin(value string) bool {
	if value.len != 64 { return false }
	for byte in value { if !(byte >= `0` && byte <= `9`) && !(byte >= `a` && byte <= `f`) { return false } }
	return true
}

fn ordinary(path string) ! {
	if os.lstat(path)!.get_filetype() != .regular { return error('rollback diagnostic requires ordinary input files') }
}

fn iso_files(image string, log string) !map[string]wineoverlay.Span {
	invoke(['/opt/homebrew/bin/xorriso', '-indev', image, '-find', '/', '-type', 'f', '-exec', 'report_lba', '--'], log)!
	mut files := map[string]wineoverlay.Span{}
	length := os.file_size(image)
	for line in os.read_lines(log)! {
		if !line.starts_with('File data lba:') { continue }
		parts := line.split(',')
		if parts.len != 5 { return error('unexpected rollback ISO extent') }
		name := parts[4].trim_space()
		if !name.starts_with("'/") || !name.ends_with("'") || files.len >= 32 { return error('unsupported rollback ISO file') }
		path := name[1..name.len - 1]
		if path in files { return error('duplicate rollback ISO file') }
		for number in [parts[1].trim_space(), parts[3].trim_space()] {
			if number.len == 0 || number.len > 19 { return error('invalid rollback ISO extent number') }
			for byte in number { if byte < `0` || byte > `9` { return error('invalid rollback ISO extent number') } }
		}
		sector := parts[1].trim_space().u64()
		size := parts[3].trim_space().u64()
		if sector > length / 2048 || size > length - sector * 2048 { return error('rollback ISO extent outside image') }
		files[path] = wineoverlay.Span{sector * 2048, size}
	}
	return files
}

fn build_overlay() ! {
	path := os.getenv('VINIX_WINE_ROLLBACK_MANIFEST')
	if wineoverlay.digest(path)! != os.getenv('VINIX_WINE_ROLLBACK_MANIFEST_SHA256') { return error('rollback overlay manifest changed') }
	m := json2.decode[RollbackOverlay](os.read_file(path)!)!
	if os.getenv('VINIX_AMD64_KERNEL') != m.kernel || wineoverlay.digest(m.kernel)! != m.kernel_sha256
		|| wineoverlay.digest(m.baseline)! != m.baseline_sha256 || wineoverlay.digest(m.guest)! != m.guest_sha256 { return error('rollback overlay input differs') }
	output := os.getenv('VINIX_AMD64_ISO')
	wineoverlay.clone_fresh(m.baseline, output)!
	span := wineoverlay.patch_init(m.baseline, output, m.guest, m.tar, m.old_init_sha256)!
	os.write_file(os.dir(output) + '/overlay.json', json2.encode({
		'baseline_sha256': m.baseline_sha256, 'guest_sha256': m.guest_sha256,
		'output_sha256': wineoverlay.digest(output)!, 'init_offset': span.offset.str(), 'init_size': span.size.str()
	}))!
	if wineoverlay.digest(m.baseline)! != m.baseline_sha256 { return error('rollback baseline changed') }
}

fn run() ! {
	if os.args.len != 8 { return error('usage: CHECK FRESH_WORK BASELINE_ISO ISO_SHA256 KERNEL KERNEL_SHA256 SYSROOT GCC_INSTALL') }
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('fresh rollback diagnostic output required') }
	if !pin(os.args[3]) || !pin(os.args[5]) { return error('rollback diagnostic requires explicit lowercase SHA256 pins') }
	image := os.abs_path(os.args[2]); kernel := os.abs_path(os.args[4])
	ordinary(image)!; ordinary(kernel)!
	if wineoverlay.digest(image)! != os.args[3] { return error('rollback baseline pin differs') }
	if wineoverlay.digest(kernel)! != os.args[5] { return error('rollback kernel pin differs') }
	root := hwhost.find_root(@FILE)!
	probe := root + '/tests/packages/wine-native/main.v'
	if wineoverlay.digest(@FILE)! != sha256.hexhash($embed_file('wine-rollback-check.v').to_string())
		|| wineoverlay.digest(probe)! != sha256.hexhash($embed_file('wine-native/main.v').to_string()) { return error('compiled rollback diagnostic source differs') }
	host := hwhost.find_host(root, 'x86_64', '')!
	cc := '/opt/homebrew/opt/llvm/bin/clang'
	mut inputs := map[string]string{}
	for path in [@FILE, probe, os.executable(), image, kernel, host.v, cc, host.qemu, host.firmware, '/opt/homebrew/bin/xorriso'] {
		inputs[path] = wineoverlay.digest(path)!
	}
	os.mkdir_all(work)!
	files := iso_files(image, work + '/iso-files.log')!
	tar := files['/boot/initramfs.tar'] or { return error('rollback baseline initramfs missing') }
	kernel_span := files['/boot/vinix'] or { return error('rollback baseline kernel missing') }
	if wineoverlay.range_digest(image, kernel_span.offset, kernel_span.size)! != os.args[5] { return error('rollback embedded kernel pin differs') }
	init := wineoverlay.init_span(image, tar)!
	old_init := wineoverlay.range_digest(image, init.offset, init.size)!
	vlib := os.dir(host.v) + '/vlib'
	for directory in [root + '/tests/packages/wineoverlay', root + '/tests/packages/winesource',
		root + '/tests/hardware-platform/hwhost', os.args[6] + '/usr/include', os.args[7]] {
		for path in os.walk_ext(directory, '', hidden: true) { if os.is_file(path) { inputs[path] = wineoverlay.digest(path)! } }
	}
	for path in [vlib + '/os/execute_capture_nix.h', vlib + '/sync/thread_helper.h'] { inputs[path] = wineoverlay.digest(path)! }
	mut command := [host.v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64', '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules', '-o', work + '/guest.c', probe]
	for mode in ['wine_owned_manager', 'wine_collection_probe', 'wine_caller_death_probe', 'wine_manager_death_probe', 'wine_relaunch_probe', 'wine_migration_probe', 'wine_rollback_probe'] { command.insert(1, ['-d', mode]) }
	mut discovery := command.clone()
	discovery.insert(1, ['-print-watched-files', '-dump-files', work + '/sources-before.txt'])
	invoke(discovery, work + '/discover.log')!
	winesource.capture(work + '/sources-before.txt', mut inputs)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	command.insert(1, ['-dump-files', work + '/sources-built.txt'])
	invoke(command, work + '/v.log')!
	winesource.admit(work + '/sources-before.txt', work + '/sources-built.txt', inputs)!
	os.write_file(work + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' + vlib + '/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vlib + '/sync/thread_helper.h"\n')!
	invoke([cc, '--target=x86_64-linux-musl', '--sysroot=' + os.args[6], '--gcc-install-dir=' + os.args[7], '-fuse-ld=lld',
		'-static', '-s', '-O1', '-w', '-Wno-error=incompatible-pointer-types', '-D_GNU_SOURCE', '-fno-stack-protector',
		work + '/guest.c', work + '/runtime.c', '-lm', '-lpthread', '-o', work + '/guest'], work + '/cc.log')!
	manifest := work + '/overlay-inputs.json'
	os.write_file(manifest, json2.encode(RollbackOverlay{image, os.args[3], kernel, os.args[5], work + '/guest', wineoverlay.digest(work + '/guest')!, tar, old_init}))!
	for path in [work + '/guest', work + '/guest.c', work + '/runtime.c', manifest] { inputs[path] = wineoverlay.digest(path)! }
	verify(inputs)!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	os.mkdir_all(work + '/builder/build-support')!
	os.symlink(os.executable(), work + '/builder/build-support/build-amd64-iso.sh')!
	os.setenv('VINIX_WINE_ROLLBACK_BUILDER', '1', true)
	os.setenv('VINIX_WINE_ROLLBACK_MANIFEST', manifest, true)
	os.setenv('VINIX_WINE_ROLLBACK_MANIFEST_SHA256', inputs[manifest], true)
	outcome := hwhost.run_scenario(hwhost.Host{...host, root: work + '/builder'},
		hwhost.Scenario{name: 'Wine-rollback-diagnostic', arches: ['x86_64'], ending: .running, qemu_x86_64: ['-cpu', 'max'],
			required: ['Wine ordinary-caller-SIGKILL outer-status137 holder-alive PASS',
				'Wine manager-SIGKILL adopted-server foreign-refusal126 lease-busy PASS',
				'Wine public signed-generation migration complete links=',
				'Wine rollback prefix migrated and real Win64 relaunched status37 PASS',
				'Wine rolled-back prefix relaunch status37 private-data lease-free collected PASS', 'HWTEST PASS packaged-Wine'],
			forbidden: ['HWTEST FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION']},
		hwhost.Run{kernel: kernel, guest: work + '/guest', state: work + '/boot', timeout: 600, keep: true, memory_mib: 3072})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	verify(inputs)!
	wineoverlay.verify_delta(image, work + '/boot/test.iso', work + '/guest', init)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if !outcome.passed || outcome.interrupted { return error('Wine rollback diagnostic failed: ' + outcome.reason) }
	println('WINE ROLLBACK DIAGNOSTIC PASS immutable signed baseline; no fresh package qualification')
}

fn main() {
	if os.getenv('VINIX_WINE_ROLLBACK_BUILDER') == '1' && os.getenv('VINIX_AMD64_ISO') != '' {
		build_overlay() or { eprintln(err); exit(1) }; return
	}
	run() or { eprintln(err); exit(1) }
}
