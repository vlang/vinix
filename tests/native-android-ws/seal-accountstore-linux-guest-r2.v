// SPDX-License-Identifier: GPL-2.0-or-later
// Seal the retained synthetic account-store guest result; never starts QEMU.
module main

import json2
import os
import time
import v.embed_file

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const tool = state + '/seal-accountstore-linux-guest-r2-host'
const output = state + '/accountstore-linux-guest-evidence-2026-10-26-r2'
const fixture = state + '/accountstore-linux-regression-build-2026-10-26-r4'
const old_fixture = state + '/accountstore-linux-regression-build-2026-10-26-r3'
const kernel = state + '/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2'
const runner = state + '/pidfd-wait-native-runner-build-2026-10-26-r1'
const producer = state + '/current-account-build-2026-10-26-r7'
const guest = state + '/accountstore-linux-guest-2026-10-26-r2'
const failed = state + '/accountstore-linux-guest-2026-10-26-r1'
const fixture_pin = '9c989f21bef68a689be5e61a11d756a4cdd9e5f5075b51f1e0609e0fbfc822d9'
const old_fixture_pin = '386821aecbbbdfdb5c7607e0d247236dcf51f67013df4d5e80784207b4b7d9a9'
const kernel_pin = 'a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151'
const source_revision = '8fb04d7762946cb87073c626af5d21e9f88a4dcd'
const compiled_source = carried($embed_file(@FILE))
const markers = [
	'ACCOUNTSTORE-INIT proc-existing',
	'ACCOUNTSTORE-CANONICAL-PASS persistence reopen visibility userdata',
	'ACCOUNTSTORE-PROCFD-REJECTED code=14 extended=1550',
	'ACCOUNTSTORE-REJECTION-PASS symlink-ancestor',
	'ACCOUNTSTORE-REJECTION-PASS directory target-unchanged',
	'ACCOUNTSTORE-REJECTION-PASS symlink target-unchanged',
	'ACCOUNTSTORE-REJECTION-PASS hardlink target-unchanged',
	'ACCOUNTSTORE-REJECTION-PASS journal target-unchanged',
	'ACCOUNTSTORE-LINUX-PASS canonical-persistence procfd-nofollow-rejection unsafe-links',
]

fn carried(data embed_file.EmbedFileData) string {
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('compile sealer with -prod to embed its source')
	}
	return data.to_string()
}

fn require(value bool, message string) ! {
	if !value { return error(message) }
}

fn digest(data string) !string {
	mut context := C.CC_SHA256_CTX{}
	require(C.CC_SHA256_Init(unsafe { &context }) == 1, 'SHA init')!
	require(data.len <= 0xffffffff && C.CC_SHA256_Update(unsafe { &context }, data.str, u32(data.len)) == 1, 'SHA data')!
	mut result := [32]u8{}
	require(C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &context }) == 1, 'SHA final')!
	return result[..].hex()
}

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut context := C.CC_SHA256_CTX{}
	require(C.CC_SHA256_Init(unsafe { &context }) == 1, 'SHA init')!
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		require(C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) == 1, 'SHA update')!
	}
	mut result := [32]u8{}
	require(C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &context }) == 1, 'SHA final')!
	return result[..].hex()
}

fn relative(path string) bool {
	return path != '' && !os.is_abs_path(path) && !path.contains_any('\\\x00\r\n\t')
		&& path.split('/').all(it !in ['', '.', '..'])
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		rel := if prefix == '' { name } else { prefix + '/' + name }
		require(relative(rel), 'unsafe evidence path')!
		path := root + '/' + rel
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, rel, mut pins)! }
			.regular { pins[path] = hash(path)! }
			else { return error('special or symlink evidence: ' + path) }
		}
	}
}

fn tree(root string) !map[string]string {
	require(root == os.real_path(root) && os.lstat(root)!.get_filetype() == .directory, 'canonical evidence root required')!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	return pins
}

fn sealed(root string, seal string) !map[string]string {
	require(hash(root + '/sha256.json')! == seal, 'producer manifest pin: ' + root)!
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	actual := tree(root)!
	require(actual.len == expected.len + 1, 'complete producer membership: ' + root)!
	for name, pin in expected {
		require(relative(name) && name != 'sha256.json' && pin.len == 64
			&& pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)), 'invalid producer entry')!
		require(actual[root + '/' + name] or { '' } == pin, 'producer membership/digest: ' + name)!
	}
	return actual
}

struct TypedInventory {
	files map[string]string
	links map[string]string
}

fn typed_inventory(root string, prefix string, mut files map[string]string, mut links map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		rel := if prefix == '' { name } else { prefix + '/' + name }
		require(relative(rel), 'unsafe typed evidence path')!
		path := root + '/' + rel
		match os.lstat(path)!.get_filetype() {
			.directory { typed_inventory(root, rel, mut files, mut links)! }
			.regular { files[path] = hash(path)! }
			.symbolic_link { links[path] = os.readlink(path)! }
			else { return error('special typed evidence: ' + path) }
		}
	}
}

fn typed_tree(root string) !TypedInventory {
	require(root == os.real_path(root) && os.lstat(root)!.get_filetype() == .directory, 'canonical typed root required')!
	mut files, mut links := map[string]string{}, map[string]string{}
	typed_inventory(root, '', mut files, mut links)!
	return TypedInventory{files, links}
}

fn sealed_kernel(seal string) !TypedInventory {
	require(hash(kernel + '/sha256.json')! == seal, 'kernel manifest pin')!
	expected := json2.decode[TypedInventory](os.read_file(kernel + '/sha256.json')!)!
	actual := typed_tree(kernel)!
	require(actual.files.len == expected.files.len + 1 && actual.links.len == expected.links.len, 'complete typed kernel membership')!
	for name, pin in expected.files {
		require(relative(name) && name != 'sha256.json' && pin.len == 64
			&& pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)), 'invalid kernel file entry')!
		require(actual.files[kernel + '/' + name] or { '' } == pin, 'kernel file membership/digest: ' + name)!
	}
	for name, target in expected.links {
		require(relative(name) && name != 'sha256.json' && name !in expected.files
			&& actual.links[kernel + '/' + name] or { '' } == target, 'kernel symlink membership/target: ' + name)!
	}
	return actual
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn normalized(path string) ![]string {
	return os.read_file(path)!.replace('\r', '').split_into_lines()
}

fn verdict(path string, terminated bool) ! {
	lines := normalized(path)!
	mut observed := []string{}
	for line in lines {
		require(!line.contains('ACCOUNTSTORE-FAIL') && !line.contains('KERNEL PANIC')
			&& !line.contains('FATAL EXCEPTION'), 'failure in successful run: ' + path)!
		if line.starts_with('ACCOUNTSTORE-') { observed << line }
	}
	require(observed == markers, 'exact ordered account store verdicts: ' + path)!
	if terminated {
		require(lines.filter(it == 'QEMU: Terminated').len == 1
			&& lines.filter(it == 'All requested guest verdicts passed.').len == 1
			&& lines.index('QEMU: Terminated') > lines.index(markers.last())
			&& lines.index('All requested guest verdicts passed.') > lines.index('QEMU: Terminated'), 'runner completion ordering')!
	}
}

// Binary stdout is hashed by length; it is never sent to the terminal.
fn capture(label string, argv []string, mut tools map[string]string) !string {
	executable := os.real_path(argv[0])
	pin := hash(executable)!
	tools[executable] = pin
	started := time.utc().str()
	result := os.exec(argv)
	write_json(output + '/' + label + '.json', {
		'argv': json2.Any(argv), 'executable_path': json2.Any(executable),
		'executable_sha256': json2.Any(pin), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(result.exit_code),
		'stdout_bytes': json2.Any(result.output.len), 'stdout_sha256': json2.Any(digest(result.output)!),
	})!
	require(result.exit_code == 0 && hash(executable)! == pin, 'inspection command failed: ' + label)!
	return result.output
}

fn check(seal string, receipt string) ! {
	require(seal.len == 64 && seal.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)), 'explicit SHA256 seal required')!
	require(os.is_abs_path(receipt) && !os.exists(receipt) && !os.is_link(receipt)
		&& os.dir(receipt) == os.real_path(os.dir(receipt)) && !receipt.starts_with(output + '/'), 'fresh external check receipt required')!
	started := time.utc().str()
	own := sealed(output, seal)!
	require(hash(output + '/sealer')! == hash(os.executable())!
		&& hash(output + '/sealer-source.v')! == digest(compiled_source)!, 'executing checker differs from sealed sealer')!
	external := json2.decode[map[string]string](os.read_file(output + '/external-sha256.json')!)!
	links := json2.decode[map[string]string](os.read_file(output + '/external-symlinks.json')!)!
	roots := json2.decode[[]string](os.read_file(output + '/roots.json')!)!
	for root in roots {
		require(!receipt.starts_with(root + '/'), 'check receipt inside original evidence')!
		mut expected_files, mut expected_links := map[string]string{}, map[string]string{}
		for path, pin in external { if path.starts_with(root + '/') { expected_files[path] = pin } }
		for path, target in links { if path.starts_with(root + '/') { expected_links[path] = target } }
		if root == kernel {
			actual := typed_tree(root)!
			require(actual.files == expected_files && actual.links == expected_links, 'changed complete typed root: ' + root)!
		} else {
			require(expected_links.len == 0 && tree(root)! == expected_files, 'changed complete root: ' + root)!
		}
	}
	for path, pin in external {
		require(os.lstat(path)!.get_filetype() == .regular && hash(path)! == pin, 'external file changed: ' + path)!
	}
	for path, target in links {
		require(os.lstat(path)!.get_filetype() == .symbolic_link && os.readlink(path)! == target, 'external symlink changed: ' + path)!
	}
	verdict(guest + '/serial.log', false)!
	verdict(guest + '-run.log', true)!
	require(sealed(output, seal)! == own, 'sealed evidence changed during check')!
	write_json(receipt, {
		'kind': json2.Any('vinix-accountstore-linux-guest-recheck-v1'), 'manifest_sha256': json2.Any(seal),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'checker_sha256': json2.Any(hash(os.executable())!), 'complete_external_files': json2.Any(external.len),
		'complete_kernel_symlinks': json2.Any(links.len), 'passed': json2.Any(true),
	})!
	println('ACCOUNTSTORE-LINUX-GUEST-CHECK-PASS files=' + external.len.str() + ' symlinks=' + links.len.str())
}

fn run() ! {
	require(os.args.len == 1 && os.executable() == tool && !os.exists(output) && !os.is_link(output), 'fresh fixed evidence output required')!
	require(hash(compiler)! == compiler_pin, 'compiler pin')!
	roots := [fixture, old_fixture, kernel, runner, producer, guest, failed]
	seals := [
		'efa7bd437e33ec2abd7a0202e4ff58ba4a6860cd0283032e6a393d17a5829d5d',
		'e1bcff85fd35e78c5c5e6cd069696cfe82db08f08089907d04b350acd671efbb',
		'32a134cc1ee3d02bfb56d91ee429ac3f5fb9895ba525021eb7aa84a7ec64f6ee',
		'20719168a89db758e28b65078454da563def0222175293cd2fa7f31f8cb43475',
		'1c761aa0e437bab4f1f2219837c11c78697b31444f0f11b5eea671f09932ce4a',
	]
	mut trees := []map[string]string{}
	mut external := map[string]string{}
	mut kernel_links := map[string]string{}
	for i, root in roots {
		mut pins := map[string]string{}
		if root == kernel {
			typed := sealed_kernel(seals[i])!
			pins = typed.files
			kernel_links = typed.links
		} else {
			pins = if i < seals.len { sealed(root, seals[i])! } else { tree(root)! }
		}
		trees << pins
		for path, pin in pins { external[path] = pin }
		println('COMPLETE-ROOT-PASS files=' + pins.len.str() + ' root=' + root)
	}
	require(hash(guest + '/serial.log')! == '330277a4204cbf2d38a987f33afaaa555c73a7d1a69a1ec73b425f037dd29e1c'
		&& hash(guest + '-run.log')! == 'b04f3b8344d0bbd72a6f17b30d73e2d91cc210b5d849e649bc2a836d4912fda8', 'successful original logs')!
	verdict(guest + '/serial.log', false)!
	verdict(guest + '-run.log', true)!
	require(hash(failed + '/serial.log')! == '8bfe16e7b713e9d04a372151511bde7165fc8e8def76c9fbba44eadf1a76c5e2'
		&& hash(failed + '-run.log')! == 'f4ea4b287a8beee24f984668251943359f5fbbfd919643a1e16db5f8b0ed50f3', 'preserved original failure')!
	for root in [guest, failed] {
		pin := if root == guest { fixture_pin } else { old_fixture_pin }
		require(hash(root + '/init')! == pin && hash(root + '/rootfs/sbin/init')! == pin, 'guest fixture copies')!
	}
	require(hash(kernel + '/source/kernel/bin/vinix')! == kernel_pin, 'kernel ELF pin')!
	os.mkdir(output, mode: 0o700)!
	os.cp(tool, output + '/sealer')!
	os.write_file(output + '/sealer-source.v', compiled_source)!
	os.cp(tool + '.build.log', output + '/sealer-build.log')!
	mut inspection_tools := map[string]string{}
	iso_list := capture('iso-list', ['/usr/bin/tar', '-tf', guest + '/test.iso'], mut inspection_tools)!
	require(iso_list.split_into_lines() == ['.', 'boot', 'EFI', 'EFI/BOOT', 'boot/limine-uefi-cd.bin',
		'boot.catalog', 'boot/initramfs.tar.gz', 'boot/limine.conf', 'boot/vinix', 'EFI/BOOT/BOOTAA64.EFI'], 'ISO complete membership')!
	boot_config := capture('iso-boot-config', ['/usr/bin/tar', '-xOf', guest + '/test.iso', 'boot/limine.conf'], mut inspection_tools)!
	os.write_file(output + '/iso-limine.conf', boot_config)!
	config_lines := boot_config.split_into_lines().map(it.trim_space())
	require(config_lines.filter(it.starts_with('kernel_path:')).len == 1
		&& config_lines.filter(it.starts_with('module_path:')).len == 1
		&& 'kernel_path: boot():/boot/vinix' in config_lines
		&& 'module_path: boot():/boot/initramfs.tar.gz' in config_lines, 'ISO boot selection')!
	iso_kernel := capture('iso-kernel', ['/usr/bin/tar', '-xOf', guest + '/test.iso', 'boot/vinix'], mut inspection_tools)!
	require(digest(iso_kernel)! == kernel_pin, 'actual ISO kernel differs')!
	iso_gzip := capture('iso-initramfs-gzip', ['/usr/bin/tar', '-xOf', guest + '/test.iso', 'boot/initramfs.tar.gz'], mut inspection_tools)!
	os.write_file(output + '/iso-initramfs.tar.gz', iso_gzip)!
	iso_tar := capture('iso-initramfs-inflate', ['/usr/bin/gzip', '-dc', output + '/iso-initramfs.tar.gz'], mut inspection_tools)!
	os.write_file(output + '/iso-initramfs.tar', iso_tar)!
	iso_init := capture('iso-init', ['/usr/bin/tar', '-xOf', output + '/iso-initramfs.tar', './sbin/init'], mut inspection_tools)!
	require(digest(iso_init)! == fixture_pin, 'actual ISO init differs')!
	for root in [guest, failed] {
		label := if root == guest { 'passed' } else { 'failed' }
		init := capture(label + '-initramfs-init', ['/usr/bin/tar', '-xOf', root + '/initramfs.tar', './sbin/init'], mut inspection_tools)!
		require(digest(init)! == if root == guest { fixture_pin } else { old_fixture_pin }, 'retained initramfs init differs')!
	}
	processes := capture('process-snapshot', ['/bin/ps', '-axo', 'pid=,command='], mut inspection_tools)!
	os.write_file(output + '/process-snapshot.log', processes)!
	for line in processes.split_into_lines() {
		require(!(line.contains('qemu-system-aarch64') && (line.contains(guest + '/') || line.contains(failed + '/'))), 'owned guest still running')!
	}
	for path in [guest + '-run.log', failed + '-run.log', compiler] { external[path] = hash(path)! }
	for path, pin in inspection_tools { external[path] = pin }
	write_json(output + '/external-sha256.json', external)!
	write_json(output + '/external-symlinks.json', kernel_links)!
	write_json(output + '/roots.json', roots)!
	write_json(output + '/receipt.json', {
		'kind': json2.Any('vinix-accountstore-linux-guest-evidence-v1'),
		'sealed_utc': json2.Any(time.utc().str()), 'fixture_source_revision': json2.Any(source_revision),
		'guest': json2.Any(guest), 'preserved_failed_guest': json2.Any(failed),
		'complete_external_files': json2.Any(external.len), 'expected_markers': json2.Any(markers),
		'complete_kernel_symlinks': json2.Any(kernel_links.len),
		'fixture_sha256': json2.Any(fixture_pin), 'kernel_sha256': json2.Any(kernel_pin),
		'compiler_sha256': json2.Any(compiler_pin), 'sealer_sha256': json2.Any(hash(output + '/sealer')!),
		'sealer_source_sha256': json2.Any(hash(output + '/sealer-source.v')!),
		'documented_runner_argv': json2.Any([runner + '/generic-run', '--arch', 'aarch64',
			'--kernel-dir', kernel + '/source/kernel', '--state-dir', guest, '--prebuilt-init',
			fixture + '/bin/accountstore-linux-regression', '--expect', 'ACCOUNTSTORE-LINUX-PASS',
			'--fail', 'ACCOUNTSTORE-FAIL', '--no-network', '--timeout', '120']),
		'documented_runner_env': json2.Any({
			'V': json2.Any(state + '/procfs-overflow-2026-10-26-r1/kernel-aarch64/compiler/v'),
			'VINIX_V_COMPILER': json2.Any(state + '/procfs-overflow-2026-10-26-r1/kernel-aarch64/compiler/v'),
		}),
		'invocation_provenance': json2.Any('Runner argv/env reconstructed from the executing agent tool call. No per-run launch receipt was produced; other inherited environment and QEMU executable/firmware were not captured at launch. ISO kernel/init bytes independently match the pinned complete producers.'),
		'scope': json2.Any('Actual synthetic account-store execution in the Vinix Linux ABI guest: canonical persistence, reopen, visibility, userdata, old procfd NOFOLLOW rejection and unsafe links. Complete fixture, kernel, runner, account producer and both guest trees remain in place. Host SDK and boot assembly environment are not hermetic. No Maps/GMS/network/Google sign-in proof.'),
	})!
	for i, root in roots {
		if root == kernel {
			typed := typed_tree(root)!
			require(typed.files == trees[i] && typed.links == kernel_links, 'kernel typed membership changed during sealing')!
		} else {
			require(tree(root)! == trees[i], 'evidence membership changed during sealing: ' + root)!
		}
	}
	for path, pin in external { require(hash(path)! == pin, 'evidence changed during sealing: ' + path)! }
	mut own := map[string]string{}
	for path, pin in tree(output)! { own[path.all_after(output + '/')] = pin }
	write_json(output + '/sha256.json', own)!
	println('ACCOUNTSTORE-LINUX-GUEST-SEALED files=' + external.len.str() + ' seal=' + hash(output + '/sha256.json')!)
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--check' {
		check(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	run() or { eprintln(err); exit(1) }
}
