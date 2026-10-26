// SPDX-License-Identifier: GPL-2.0-or-later
// Historical, credential-free r3 desktop UI evidence. Never starts a guest.
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
const repo = '/Users/alex/code/vinix'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const build_log = state + '/seal-account-ui-run-r3-host.build.log'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const compiled_source = carried($embed_file(@FILE))
const original = state + '/account-ui-stage-2026-10-26-r3'
const vm = state + '/account-ui-vm-r3'
const collected = state + '/account-ui-collected-2026-10-26-r3'
const output = state + '/account-ui-run-evidence-2026-10-26-r3-r2'
const stage_seal = 'bcb7656ee29c66d2d54fad120aff2d09f078e3a7684ce59c3ac1dd88aa16d394'
const stage_receipt = 'ade6f5f89f73632ee6ef1cc36b95d17b8a3b70e25dbeb3660ba5c3401e894b20'
const archive_pin = 'a78b2697680c094b8967d816332996734bc5893456da3f4b489c657516bad1fe'
const controller_pin = '5c5d6415f3e97cb2369187a7aa373aca019ae1e085298daf4551789739851f18'
const helper_pin = 'eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989'
const revision = 'c5fc9065af1e624002eaff6e2f927ce79858a06e'
const collector = state + '/account-ui-collect-check'
const collector_pin = '357edf19436ac0f905b2fab4ceb000937e821447fbc48cba7ddcb16660771578'
const producer = state + '/current-ui-controller-build-2026-10-26-r1'
const producer_seal = '503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a'

fn carried(data embed_file.EmbedFileData) string {
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('sealer requires embedded source bytes; compile with -prod')
	}
	return data.to_string()
}

struct GuestController {
	argv []string
	executable_sha256 string
	status string
	exit_code int
	timed_out bool
	error string
	descendants int
	cleanup_survivors int
}

struct Guest {
	started_utc string
	finished_utc string
	guest_sha256 string
	controller GuestController
	status string
	error string
}

struct Controller {
	kind string
	source_revision string
	helper_path string
	helper_sha256 string
	desktop_uid int
	desktop_gid int
	checks []string
}

fn require(value bool, message string) ! {
	if !value { return error(message) }
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
	mut digest := [32]u8{}
	require(C.CC_SHA256_Final(unsafe { &digest[0] }, unsafe { &context }) == 1, 'SHA final')!
	return digest[..].hex()
}

fn doc(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path), mode: 0o700)!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		rel := if prefix == '' { name } else { prefix + '/' + name }
		require(rel.split('/').all(it !in ['', '.', '..']) && !rel.contains_any('\\\x00\r\n\t'), 'unsafe path')!
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

fn relative(path string) bool {
	return path != '' && !os.is_abs_path(path) && !path.contains_any('\\\x00\r\n\t')
		&& path.split('/').all(it !in ['', '.', '..'])
}

fn exact_inventory(root string, expected map[string]string, manifest bool) !map[string]string {
	actual := tree(root)!
	require(actual.len == expected.len + int(manifest), 'inventory membership count: ' + root)!
	for name, pin in expected {
		require(relative(name) && (!manifest || name != 'sha256.json') && pin.len == 64
			&& pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)), 'invalid inventory entry')!
		require(actual[root + '/' + name] or { '' } == pin, 'inventory membership/digest: ' + name)!
	}
	return actual
}

fn sealed_inventory(root string, seal string) !map[string]string {
	require(hash(root + '/sha256.json')! == seal, 'manifest seal: ' + root)!
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	return exact_inventory(root, pins, true)
}

fn command(label string, argv []string) ! {
	pin := hash(argv[0])!
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(output + '/' + label + '.log', result.output)!
	write_json(output + '/' + label + '.json', {
		'argv': json2.Any(argv), 'executable_sha256': json2.Any(pin),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(result.exit_code),
	})!
	require(result.exit_code == 0 && hash(argv[0])! == pin, label + ' failed: ' + result.output)!
}

fn run() ! {
	require(os.args.len == 1 && !os.exists(output) && !os.is_link(output), 'fresh fixed evidence output required')!
	require(hash(original + '/sha256.json')! == stage_seal && hash(original + '/stage.json')! == stage_receipt, 'original stage pins')!
	original_tree := sealed_inventory(original, stage_seal)!
	producer_tree := sealed_inventory(producer, producer_seal)!
	vm_tree := tree(vm)!
	collected_tree := tree(collected)!
	original_pins := json2.decode[map[string]string](os.read_file(original + '/sha256.json')!)!
	for name, pin in original_pins {
		if name != 'efivars.fd' { require(hash(vm + '/' + name)! == pin, 'clone immutable stage changed: ' + name)! }
	}
	require(hash(vm + '/sha256.json')! == stage_seal, 'cloned original inventory')!
	clone := doc(vm + '-clone.json')!
	require(clone['kind']!.str() == 'vinix-maps-account-exact-stage-clone-v1'
		&& clone['source']!.str() == original && clone['output']!.str() == vm
		&& clone['manifest_sha256']!.str() == stage_seal
		&& clone['source_closure']!.str() == vm + '-clone-sources'
		&& clone['tool_sha256']!.str() == hash(vm + '-clone-tool')!
		&& clone['source_sha256']!.str() == hash(vm + '-clone-source.v')!, 'clone provenance')!
	clone_sources := json2.decode[map[string]string](json2.encode(clone['source_closure_sha256']!))!
	clone_source_tree := exact_inventory(vm + '-clone-sources', clone_sources, false)!
	launch := doc(vm + '/launch.json')!
	require(launch['stage_sha256']!.str() == stage_receipt
		&& launch['runner_sha256']!.str() == hash(vm + '/runner')!
		&& launch['runner_source_sha256']!.str() == hash(vm + '/run-source.v')!
		&& launch['qemu_sha256']!.str() == hash(qemu)!
		&& launch['firmware_sha256']!.str() == hash(firmware)!, 'runner provenance')!
	launch_argv := json2.decode[[]string](json2.encode(launch['argv']!))!
	require(launch_argv.len > 0 && launch_argv[0] == qemu
		&& 'if=pflash,format=raw,readonly=on,file=' + firmware in launch_argv
		&& 'format=raw,file=' + vm + '/boot.img' in launch_argv, 'launch executable/media binding')!
	launch_result := doc(vm + '/launch-result.json')!
	require(json2.decode[[]string](json2.encode(launch_result['argv']!))! == launch_argv
		&& launch_result['code']!.str() == '0' && launch_result['stdout']!.str() == ''
		&& launch_result['stderr']!.str() == '', 'successful launch result binding')!
	stop, gone := doc(vm + '/stop.json')!, doc(vm + '/gone.json')!
	owner := doc(vm + '/ownership.json')!
	require(stop['pid']!.str() == owner['pid']!.str() && gone['pid']!.str() == owner['pid']!.str()
		&& owner['command']!.str() == launch_argv.join(' ')
		&& gone['ownership_sha256']!.str() == hash(vm + '/ownership.json')!
		&& gone['stop_sha256']!.str() == hash(vm + '/stop.json')!
		&& !os.exists(vm + '/qemu.pid') && !os.exists(vm + '/qmp.sock'), 'stopped ownership binding')!
	imported := doc(collected + '/import.json')!
	require(hash(collected + '/archive.json')! == archive_pin && imported['archive_sha256']!.str() == archive_pin
		&& imported['serial_path']!.str() == vm + '/serial.log'
		&& imported['serial_sha256']!.str() == hash(vm + '/serial.log')!
		&& imported['entries']!.str() == '17', 'strict collection binding')!
	guest := json2.decode[Guest](os.read_file(collected + '/results/guest.json')!)!
	require(guest.status == 'passed' && guest.error == '' && guest.controller.status == 'passed'
		&& guest.controller.error == '' && guest.controller.exit_code == 0 && !guest.controller.timed_out
		&& guest.controller.descendants == 1 && guest.controller.cleanup_survivors == 0
		&& guest.controller.executable_sha256 == controller_pin
		&& guest.guest_sha256 == hash(vm + '/payload/bin/account-ui-guest')!, 'guest execution result')!
	require(guest.controller.argv == ['/opt/vinix-account-ui/bin/account-ui-controller', '0', '0',
		'/opt/vinix-account-ui/bin/vinix-android-account-ui', '/run/vinix-session.0/windows',
		'/opt/vinix-account-ui/results/controller.json', revision], 'controller argv')!
	control := json2.decode[Controller](os.read_file(collected + '/results/controller.json')!)!
	require(control.kind == 'vinix-account-ui-controller-v1' && control.source_revision == revision
		&& control.helper_path == '/opt/vinix-account-ui/bin/vinix-android-account-ui'
		&& control.helper_sha256 == helper_pin && control.desktop_uid == 0 && control.desktop_gid == 0
		&& control.checks == ['real-helper-window-ready', 'WSUI64-session-capability', 'SCM_RIGHTS-two-fds',
		'CLOEXEC', 'sealed-size-VSF1', 'read-only-input-FIFO', 'diagnostic-frame-published',
		'helper-lifetime-EOF-input-close', 'single-use-attachment'], 'controller checks')!
	require(hash(collector)! == collector_pin, 'historical strict collector pin')!
	require(hash(compiler)! == compiler_pin, 'sealer compiler pin')!
	os.mkdir(output, mode: 0o700)!
	os.cp(os.executable(), output + '/sealer')!
	os.write_file(output + '/sealer-source.v', compiled_source)!
	os.cp(build_log, output + '/sealer-build.log')!
	os.cp(collector, output + '/collector')!
	command('collector-self-test', [output + '/collector', '--self-test'])!
	command('strict-replay', [output + '/collector', '--account-ui', vm + '/serial.log', output + '/replay'])!
	require(hash(output + '/replay/archive.json')! == archive_pin, 'replayed archive differs')!
	mut a, mut b := tree(collected + '/results')!, tree(output + '/replay/results')!
	mut normalized_a, mut normalized_b := map[string]string{}, map[string]string{}
	for name, pin in a { normalized_a[name.all_after(collected + '/results/')] = pin }
	for name, pin in b { normalized_b[name.all_after(output + '/replay/results/')] = pin }
	require(normalized_a == normalized_b, 'replayed complete results differ')!
	mut external := map[string]string{}
	for pins in [original_tree, producer_tree, clone_source_tree, vm_tree, collected_tree] {
		for path, pin in pins { external[path] = pin }
	}
	for path in [vm + '-clone.json', vm + '-clone-tool', vm + '-clone-source.v',
		state + '/account-ui-r3-clone.log', state + '/account-ui-r3-run-start.log',
		state + '/account-ui-r3-stop-reconcile.log', collector, qemu, firmware, compiler] { external[path] = hash(path)! }
	write_json(output + '/external-sha256.json', external)!
	write_json(output + '/receipt.json', {
		'kind': json2.Any('vinix-account-ui-run-evidence-v1'), 'sealed_utc': json2.Any(time.utc().str()),
		'started_utc': json2.Any(guest.started_utc), 'finished_utc': json2.Any(guest.finished_utc),
		'original_stage': json2.Any(original), 'stage_inventory_sha256': json2.Any(stage_seal),
		'clone': json2.Any(vm), 'collected': json2.Any(collected), 'archive_sha256': json2.Any(archive_pin),
		'external_files': json2.Any(external.len), 'collector_sha256': json2.Any(collector_pin),
		'compiler_sha256': json2.Any(compiler_pin),
		'documented_build_argv': json2.Any([compiler, '-new-compiler', '-prod', '-gc', 'none', '-nocache', '-path', '@vlib', '-cc', 'cc',
			'-o', state + '/seal-account-ui-run-r3-host', repo + '/tests/native-android-ws/seal-account-ui-run-r3.v']),
		'sealer_sha256': json2.Any(hash(output + '/sealer')!),
		'sealer_source_sha256': json2.Any(hash(output + '/sealer-source.v')!),
		'scope': json2.Any('Real desktop helper/controller only; no Android Activity, Google account or sign-in proof. Original stage, stopped clone and original collection remain complete at their pinned external paths.'),
	})!
	for path, pin in external { require(hash(path)! == pin, 'external evidence changed while sealing')! }
	for i, root in [original, producer, vm + '-clone-sources', vm, collected] {
		before := [original_tree, producer_tree, clone_source_tree, vm_tree, collected_tree][i]
		require(tree(root)! == before, 'external tree membership changed while sealing: ' + root)!
	}
	mut own := map[string]string{}
	for path, pin in tree(output)! { own[path.all_after(output + '/')] = pin }
	write_json(output + '/sha256.json', own)!
	println('ACCOUNT-UI-RUN-SEALED files=' + external.len.str() + ' seal=' + hash(output + '/sha256.json')!)
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
