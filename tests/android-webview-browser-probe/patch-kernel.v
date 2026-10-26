// SPDX-License-Identifier: GPL-2.0-or-later
// Replace only the kernel in a fresh diagnostic stage; never launch a guest.
module main

import crypto.sha256
import json2
import modulestream
import os
import time

#include <signal.h>
#include <CommonCrypto/CommonDigest.h>

fn C.kill(int, int) int
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const baseline_sha = '176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c'
const maps_baseline_sha = '08b0a9c6d0eaf109a5027eac802cb5add897e7612aac85528a08fdba794b3f5e'
const protected_base = '/Users/alex/.local/state/vinix/android/maps-account-r5'
const protected_base_seal = '9a8bf61bd526d7ec020d45920367d45e90a2ef4692c6d8fa8b87de801a14c5ca'
const protected_boot_sha = 'a37afb3aaaaac0261562df47b6f213bf0ef47eaaa9165d721cb4e097ce35ed70'
const protected_framework_seal = '67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938'
const protected_native_seal = '894c9657077cdd913a2c66c1cf78358daaccc4da8b0739ed77bb2a3dbea1b4ee'
const source = $embed_file(@FILE).to_string()

struct Profile {
	name         string
	baseline_sha string
	overlay      string
	modules      []string
}

fn browser_profile() Profile {
	return Profile{'browser-probe', baseline_sha, 'browser-probe.tar', []string{}}
}

fn maps_profile() Profile {
	return Profile{'maps-account', maps_baseline_sha, 'maps-account.tar', [
		'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar',
		'maps350-diagnostics.tar', 'maps372-diagnostics.tar', 'headless-service.tar',
	]}
}

fn protected_maps_profile() Profile {
	mut modules := maps_profile().modules.clone()
	modules << 'maps-account.tar'
	return Profile{'protected-storage-maps', protected_boot_sha,
		'protected-storage-diagnostic.tar', modules}
}

fn protected_modules() map[string]string {
	return {
		'headless-service.tar': 'c3466dcfda28617c91242e54f382da22b5b67187fba6ab93d5926c6481d5175c'
		'initramfs.tar': '863944c8ff791dbf94841cb48bbfa0ad8adbab427589bf76a2d20276f5040efb'
		'maps335-diagnostics.tar': '50c1e8aeef5aab5bc6a1a2d7aeb862ff6f674172eec308b827f654a580cabf56'
		'maps350-diagnostics.tar': '27fab286f1d162a997acef67aaac5670118ef6e6eb83969310c0182123a82ead'
		'maps372-diagnostics.tar': '6ab69d2a2c86ce8c7c51543dd596a789cacb7c0880a5f33b2429cf5008cd74d0'
		'qemu-runtime.tar': '1c6988d1f3d3844425f0e8cbb49a878b3a16f2a270b4eb3852c71dfaa8fe200e'
		'maps-account.tar': 'db724d216208abfb1ae873035fb7cbc21d646ba2ff5e5773dd1f18fd05c2ac81'
	}
}

// This diagnostic producer declares a sealed r5 base instead of a direct
// boot.img input. Its separate profile accepts only that exact producer contract.
fn verify_protected_receipt(receipt map[string]json2.Any, stage Stage) ! {
	for name, expected in {
		'kind': 'vinix-protected-storage-maps-diagnostic-v1'
		'base_root': protected_base
		'base_manifest_sha256': protected_base_seal
		'framework_manifest_sha256': protected_framework_seal
		'native_manifest_sha256': protected_native_seal
		'retained_launch_manifest_sha256': '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
	} {
		actual := receipt[name] or { return error('protected Maps receipt field absent: ' + name) }
		if actual != json2.Any(expected) { return error('protected Maps receipt differs: ' + name) }
	}
	for path, expected in {
		protected_base + '/sha256.json': protected_base_seal
		'/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2/sha256.json': protected_framework_seal
		'/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-protected-r1/sha256.json': protected_native_seal
	} {
		if stage.inputs_sha256[path] or { '' } != expected {
			return error('protected Maps input differs: ' + path)
		}
	}
	if stage.format != 1 || stage.original_modules_sha256 != protected_modules()
		|| stage.preserved_modules_sha256 != protected_modules() {
		return error('protected Maps original seven module pins differ')
	}
}

fn protected_baseline(receipt map[string]json2.Any, stage Stage) !string {
	verify_protected_receipt(receipt, stage)!
	path := protected_base + '/sha256.json'
	regular(path)!
	if os.lstat(path)!.size > 8 * 1024 * 1024 || hash(path)! != protected_base_seal {
		return error('protected Maps original r5 manifest differs')
	}
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	if pins['boot.img'] or { '' } != protected_boot_sha {
		return error('protected Maps original boot inventory differs')
	}
	return protected_base + '/boot.img'
}

struct Stage {
	format                   int
	inputs_sha256            map[string]string
	original_modules_sha256  map[string]string
	preserved_modules_sha256 map[string]string
	overlay_sha256           string
	limine_before_sha256     string
	limine_after_sha256      string
	staged_boot_sha256       string
	staged_efivars_sha256    string
}

struct Build {
	format                    int
	source_revision           string
	architecture              string
	kernel_path               string
	kernel_sha256             string
	kernel_unix_source_sha256 string
	generated_c_sha256        string
	compiler_sha256           string
	guest_executed            bool
	link_seed                 int
}

struct Inventory {
	files map[string]string
	links map[string]string
}

struct Config {
	kernel  string
	modules []string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := C.CC_SHA256_CTX{}
	if C.CC_SHA256_Init(unsafe { &digest }) != 1 { return error('SHA256 initialization') }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) != 1 {
			return error('SHA256 update')
		}
	}
	mut result := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) != 1 {
		return error('SHA256 finalization')
	}
	return result[..].hex()
}

fn hash_self_test(root string) ! {
	path := root + '/sha256-input'
	defer { os.rm(path) or {} }
	for input, expected in {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
	} {
		os.write_file(path, input)!
		assert hash(path)! == expected
	}
	mut bytes := []u8{len: 2 * 1024 * 1024 + 65}
	for i in 0 .. bytes.len { bytes[i] = u8((i * 29 + 11) % 251) }
	for size in [55, 56, 63, 64, 65, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1, bytes.len] {
		os.write_file_array(path, bytes[..size])!
		assert hash(path)! == sha256.sum(bytes[..size]).hex()
	}
	println('HOST-SHA256 SELF-TEST PASS known-vectors block-padding streaming-boundaries V-reference')
}

fn digest_valid(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn regular(path string) ! {
	if os.lstat(path)!.get_filetype() != .regular {
		return error('regular non-symlink file required: ' + path)
	}
}

fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\r\n\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn member(line string, key string) !string {
	prefix := key + ': boot():/boot/'
	if !line.starts_with(prefix) { return error('unsupported Limine path: ' + line) }
	name := line[prefix.len..]
	if name == '' || name in ['.', '..'] || name.len > 255
		|| !name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`]) {
		return error('literal FAT basename required')
	}
	return name
}

fn configure(text string) !Config {
	if text == '' || text.contains_any('\x00\r') {
		return error('expected LF-delimited Limine configuration')
	}
	mut entries := 0
	mut kernel := ''
	mut modules := []string{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('/') || line.starts_with(':') { entries++ }
		if line.starts_with('kernel_path:') {
			if entries != 1 || kernel != '' { return error('ambiguous kernel entry') }
			kernel = member(line, 'kernel_path')!
		}
		if line.starts_with('module_path:') {
			if entries != 1 { return error('ambiguous module entry') }
			name := member(line, 'module_path')!
			if name in modules || !name.ends_with('.tar') {
				return error('duplicate or non-tar module')
			}
			modules << name
		}
	}
	if entries != 1 || kernel != 'vinix' || modules.len == 0 {
		return error('one Vinix kernel entry required')
	}
	return Config{kernel, modules}
}

fn execute(root string, label string, argv []string) !string {
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
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
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if stdout.len + stderr.len > 1024 * 1024 { return error('oversized command output') }
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline { return error('command deadline: ' + label) }
		time.sleep(10 * time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 1024 * 1024 { return error('oversized command output') }
	}
	child.wait()
	finished = true
	os.write_file(root + '/kernel-patch-commands/' + label + '.json', json2.encode({
		'argv':      json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(child.code)
		'stdout':    json2.Any(stdout)
		'stderr':    json2.Any(stderr)
	},
		prettify: true
	))!
	if child.code != 0 { return error(label + ' failed: ' + stderr) }
	return stdout
}

fn fat_hash(root string, label string, image string, name string) !string {
	result := modulestream.hash_member(image, name, root + '/kernel-patch-commands/' + label + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 || !digest_valid(result.sha256) {
		return error('FAT hash stream failed: ' + name)
	}
	return result.sha256
}

fn unlaunched(root string) ! {
	for name in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock',
		'serial.log', 'network.pcap', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('fresh unlaunched diagnostic stage required: ' + name)
		}
	}
}

fn verify_inventory(root string, inventory Inventory) ! {
	if inventory.files.len == 0 { return error('empty frozen build inventory') }
	for name, expected in inventory.files {
		if !relative(name) || !digest_valid(expected) {
			return error('unsafe frozen build inventory member')
		}
		path := root + '/' + name
		regular(path)!
		if !os.real_path(path).starts_with(root + '/') || hash(path)! != expected {
			return error('frozen build file differs: ' + name)
		}
	}
	for name, target in inventory.links {
		if !relative(name) || target == '' || target.contains_any('\x00\r\n')
			|| !os.is_link(root + '/' + name) || os.readlink(root + '/' + name)! != target {
			return error('frozen build symlink differs: ' + name)
		}
	}
}

fn validate_build(root string, receipt_sha string) !Build {
	for name in ['build.json', 'input-pins.json', 'sha256.json'] { regular(root + '/' + name)! }
	if !digest_valid(receipt_sha) || hash(root + '/build.json')! != receipt_sha {
		return error('kernel build receipt pin differs')
	}
	build := json2.decode[Build](os.read_file(root + '/build.json')!)!
	if build.format != 1 || build.architecture != 'aarch64' || build.guest_executed
		|| build.source_revision.len != 40 || !build.source_revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| !digest_valid(build.kernel_sha256) || !digest_valid(build.kernel_unix_source_sha256)
		|| !digest_valid(build.generated_c_sha256) || !digest_valid(build.compiler_sha256)
		|| build.link_seed != 20261026 || !os.is_abs_path(build.kernel_path)
		|| !os.real_path(build.kernel_path).starts_with(root + '/') {
		return error('unsupported or incomplete frozen kernel build receipt')
	}
	regular(build.kernel_path)!
	if hash(build.kernel_path)! != build.kernel_sha256 {
		return error('frozen kernel hash differs')
	}
	mut file := os.open(build.kernel_path)!
	mut header := []u8{len: 20}
	n := file.read(mut header)!
	file.close()
	if n != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| header[16..20] != [u8(2), 0, 183, 0] {
		return error('AArch64 ELF64 executable kernel required')
	}
	inventory := json2.decode[Inventory](os.read_file(root + '/sha256.json')!)!
	verify_inventory(root, inventory)!
	kernel_relative := os.real_path(build.kernel_path)[root.len + 1..]
	if inventory.files[kernel_relative] or { '' } != build.kernel_sha256 {
		return error('frozen kernel is absent from build inventory')
	}
	pins := json2.decode[map[string]json2.Any](os.read_file(root + '/input-pins.json')!)!
	kernel_pins := json2.decode[map[string]string](json2.encode(pins['kernel']!))!
	if kernel_pins['kernel/socket/unix/unix.v'] or { '' } != build.kernel_unix_source_sha256 {
		return error('Unix socket source pin differs from kernel inputs')
	}
	mut unix_source_present := false
	for name, expected in inventory.files {
		if (name == 'kernel/socket/unix/unix.v' || name.ends_with('/kernel/socket/unix/unix.v'))
			&& expected == build.kernel_unix_source_sha256 {
			unix_source_present = true
		}
	}
	if !unix_source_present {
		return error('frozen Unix socket source is absent from build inventory')
	}
	return build
}

fn verify_modules(profile Profile, before Config, after Config) ! {
	mut expected := before.modules.clone()
	expected << profile.overlay
	if (profile.modules.len > 0 && before.modules != profile.modules)
		|| after.kernel != before.kernel || after.modules != expected {
		return error('stage modules differ from audited ' + profile.name + ' profile')
	}
}

fn patch(root string, build_root string, receipt_sha string, profile Profile) ! {
	baseline_pin := profile.baseline_sha
	unlaunched(root)!
	for name in ['kernel-patch.json', 'kernel-patch-request.json', 'kernel-patch-commands',
		'kernel-patch-build', 'stage-before-kernel.json', 'kernel-patch-source.v', 'kernel-patch-tool'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('kernel patch is once-only: ' + name)
		}
	}
	for name in ['stage.json', 'boot.img', 'efivars.fd', 'limine-before.conf', 'limine-after.conf'] {
		regular(root + '/' + name)!
	}
	stage_text := os.read_file(root + '/stage.json')!
	stage := json2.decode[Stage](stage_text)!
	mut stage_map := json2.decode[map[string]json2.Any](stage_text)!
	if 'kernel_patch' in stage_map { return error('stage already declares a kernel patch') }
	if stage.format != 1 || hash(root + '/boot.img')! != stage.staged_boot_sha256
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256
		|| hash(root + '/limine-before.conf')! != stage.limine_before_sha256
		|| hash(root + '/limine-after.conf')! != stage.limine_after_sha256 {
		return error('fresh stage media or configuration pin differs')
	}
	mut baseline := ''
	if profile.name == 'protected-storage-maps' {
		baseline = protected_baseline(stage_map, stage)!
	} else {
		for path, expected in stage.inputs_sha256 {
			if os.file_name(path) == 'boot.img' && expected == baseline_pin {
				if baseline != '' { return error('ambiguous baseline boot input') }
				baseline = path
			}
		}
	}
	if baseline == '' || baseline == root + '/boot.img' {
		return error('audited original baseline boot input required')
	}
	regular(baseline)!
	if hash(baseline)! != baseline_pin { return error('baseline boot bytes differ') }
	build := validate_build(build_root, receipt_sha)!
	before_text := os.read_file(root + '/limine-before.conf')!
	after_text := os.read_file(root + '/limine-after.conf')!
	before := configure(before_text)!
	after := configure(after_text)!
	verify_modules(profile, before, after)!
	if stage.original_modules_sha256.len != before.modules.len
		|| stage.original_modules_sha256 != stage.preserved_modules_sha256
		|| !digest_valid(stage.overlay_sha256) {
		return error('stage baseline/module manifest differs')
	}
	for name in before.modules {
		if !digest_valid(stage.original_modules_sha256[name] or { '' }) {
			return error('module manifest member absent')
		}
	}
	mcopy := os.find_abs_path_of_executable('mcopy')!
	mtype := os.find_abs_path_of_executable('mtype')!
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	os.mkdir(root + '/kernel-patch-commands')!
	for line in execute(root, 'process-check', ['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains('qemu-system-') && line.contains(root + '/') {
			return error('QEMU references this stage; refusing kernel replacement')
		}
	}
	if execute(root, 'baseline-limine', [mtype, '-i', baseline, '::/boot/limine.conf'])! != before_text
		|| execute(root, 'stage-limine-before', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != after_text {
		return error('FAT Limine configuration differs')
	}
	old_kernel := fat_hash(root, 'baseline-kernel', baseline, before.kernel)!
	if fat_hash(root, 'staged-kernel-before', root + '/boot.img', after.kernel)! != old_kernel {
		return error('fresh staged kernel differs from original baseline')
	}
	if old_kernel == build.kernel_sha256 {
		return error('replacement kernel equals baseline kernel')
	}
	mut preserved := map[string]string{}
	for name in before.modules {
		expected := stage.original_modules_sha256[name]!
		if fat_hash(root, 'baseline-' + name, baseline, name)! != expected
			|| fat_hash(root, 'before-' + name, root + '/boot.img', name)! != expected {
			return error('original module differs before patch: ' + name)
		}
		preserved[name] = expected
	}
	if fat_hash(root, 'before-' + profile.overlay, root + '/boot.img', profile.overlay)! != stage.overlay_sha256 {
		return error('diagnostic payload differs before patch')
	}
	preserved[profile.overlay] = stage.overlay_sha256
	os.mkdir(root + '/kernel-patch-build')!
	mut build_receipts := map[string]string{}
	for name in ['build.json', 'input-pins.json', 'sha256.json'] {
		os.cp(build_root + '/' + name, root + '/kernel-patch-build/' + name)!
		build_receipts[name] = hash(root + '/kernel-patch-build/' + name)!
	}
	os.write_file(root + '/stage-before-kernel.json', stage_text)!
	os.write_file(root + '/kernel-patch-source.v', source)!
	os.cp(os.executable(), root + '/kernel-patch-tool')!
	os.write_file(root + '/kernel-patch-request.json', json2.encode({
		'profile':                     json2.Any(profile.name)
		'created_utc':                 json2.Any(time.utc().str())
		'original_stage_sha256':       json2.Any(sha256.sum(stage_text.bytes()).hex())
		'baseline_boot_sha256':        json2.Any(baseline_pin)
		'kernel_build_receipt_sha256': json2.Any(receipt_sha)
		'original_kernel_sha256':      json2.Any(old_kernel)
		'replacement_kernel_sha256':   json2.Any(build.kernel_sha256)
	}, prettify: true))!
	unlaunched(root)!
	if hash(build_root + '/build.json')! != receipt_sha || hash(build.kernel_path)! != build.kernel_sha256 {
		return error('kernel build changed before installation')
	}
	execute(root, 'install-kernel', [mcopy, '-o', '-i', root + '/boot.img', build.kernel_path,
		'::/boot/' + after.kernel])!
	if fat_hash(root, 'staged-kernel-after', root + '/boot.img', after.kernel)! != build.kernel_sha256 {
		return error('installed kernel readback differs')
	}
	for name, expected in preserved {
		if fat_hash(root, 'after-' + name, root + '/boot.img', name)! != expected {
			return error('module changed during kernel replacement: ' + name)
		}
	}
	if execute(root, 'stage-limine-after', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != after_text
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256
		|| hash(baseline)! != baseline_pin || hash(build.kernel_path)! != build.kernel_sha256
		|| os.read_file(root + '/stage.json')! != stage_text {
		return error('preserved input changed during replacement')
	}
	for name, expected in build_receipts {
		if hash(build_root + '/' + name)! != expected {
			return error('frozen build receipt changed')
		}
	}
	unlaunched(root)!
	provenance := json2.decode[json2.Any](json2.encode({
		'format':                       json2.Any(1)
		'scope':                        json2.Any('Fresh diagnostic stage only; prepared payload preserved byte-for-byte; no guest execution or Google login evidence.')
		'profile':                      json2.Any(profile.name)
		'created_utc':                  json2.Any(time.utc().str())
		'baseline_boot_path':           json2.Any(baseline)
		'baseline_boot_sha256':         json2.Any(baseline_pin)
		'original_stage_sha256':        json2.Any(sha256.sum(stage_text.bytes()).hex())
		'original_kernel_sha256':       json2.Any(old_kernel)
		'kernel_member':                json2.Any(after.kernel)
		'kernel_sha256':                json2.Any(build.kernel_sha256)
		'kernel_build_root':            json2.Any(build_root)
		'kernel_build_receipt_sha256':  json2.Any(receipt_sha)
		'kernel_build_receipts_sha256': json2.decode[json2.Any](json2.encode(build_receipts))!
		'kernel_source_revision':       json2.Any(build.source_revision)
		'kernel_unix_source_sha256':    json2.Any(build.kernel_unix_source_sha256)
		'preserved_modules_sha256':     json2.decode[json2.Any](json2.encode(preserved))!
		'limine_sha256':                json2.Any(stage.limine_after_sha256)
		'efivars_sha256':               json2.Any(stage.staged_efivars_sha256)
		'staged_boot_sha256':           json2.Any(hash(root + '/boot.img')!)
		'tool_sha256':                  json2.Any(hash(root + '/kernel-patch-tool')!)
		'tool_source_sha256':           json2.Any(hash(root + '/kernel-patch-source.v')!)
		'mcopy_sha256':                 json2.Any(hash(mcopy)!)
		'mtype_sha256':                 json2.Any(hash(mtype)!)
	}, prettify: true))!
	os.write_file(root + '/kernel-patch.json', json2.encode(provenance, prettify: true) + '\n')!
	stage_map['kernel_patch'] = provenance
	stage_map['kernel_patch_receipt_sha256'] = json2.Any(hash(root + '/kernel-patch.json')!)
	stage_map['staged_boot_sha256'] = json2.Any(hash(root + '/boot.img')!)
	os.write_file(root + '/stage.json', json2.encode(stage_map, prettify: true) + '\n')!
	println('BROWSER-KERNEL-PATCH PASS ' + root + '/kernel-patch.json')
}

fn external(path string) !string {
	abs := os.abs_path(path)
	root := os.real_path(path)
	repo := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	if abs != root || !os.is_dir(root) || root == repo || root.starts_with(repo + '/')
		|| root.contains_any('\x00\r\n') {
		return error('canonical external stage/build directory required')
	}
	return root
}

fn fat_self_test(root string, overlay string, module_names []string) ! {
	os.mkdir(root)!
	os.mkdir(root + '/kernel-patch-commands')!
	os.mkdir(root + '/baseline')!
	os.mkdir(root + '/stage')!
	os.mkdir_all(root + '/build/kernel/socket/unix')!
	baseline := root + '/baseline/boot.img'
	mut config := '/Vinix\n kernel_path: boot():/boot/vinix\n'
	for name in module_names { config += ' module_path: boot():/boot/' + name + '\n' }
	updated := config + ' module_path: boot():/boot/' + overlay + '\n'
	os.write_file(root + '/config', config)!
	os.write_file(root + '/old-kernel', 'old baseline kernel')!
	os.write_file(root + '/runtime', 'original module\x00exact bytes')!
	os.write_file(root + '/overlay', 'unchanged r8 browser overlay\x00exact bytes')!
	mcopy := os.find_abs_path_of_executable('mcopy')!
	execute(root, 'fixture-format', [os.find_abs_path_of_executable('mformat')!, '-i', baseline,
		'-C', '-f', '1440', '::'])!
	execute(root, 'fixture-mkdir', [os.find_abs_path_of_executable('mmd')!, '-i', baseline, '::/boot'])!
	for pair in [['config', 'limine.conf'], ['old-kernel', 'vinix']] {
		execute(root, 'fixture-install-' + pair[0], [mcopy, '-i', baseline, root + '/' + pair[0],
			'::/boot/' + pair[1]])!
	}
	for name in module_names {
		execute(root, 'fixture-install-' + name, [mcopy, '-i', baseline, root + '/runtime',
			'::/boot/' + name])!
	}
	os.cp(baseline, root + '/stage/boot.img')!
	os.write_file(root + '/config-after', updated)!
	execute(root, 'fixture-update-limine', [mcopy, '-o', '-i', root + '/stage/boot.img',
		root + '/config-after', '::/boot/limine.conf'])!
	execute(root, 'fixture-install-overlay', [mcopy, '-i', root + '/stage/boot.img', root + '/overlay',
		'::/boot/' + overlay])!
	os.write_file(root + '/stage/efivars.fd', 'unchanged firmware state')!
	os.write_file(root + '/stage/limine-before.conf', config)!
	os.write_file(root + '/stage/limine-after.conf', updated)!
	mut original_modules := map[string]string{}
	for name in module_names { original_modules[name] = hash(root + '/runtime')! }
	stage := Stage{
		format:                   1
		inputs_sha256:            {
			baseline: hash(baseline)!
		}
		original_modules_sha256:  original_modules
		preserved_modules_sha256: original_modules
		overlay_sha256:           hash(root + '/overlay')!
		limine_before_sha256:     hash(root + '/stage/limine-before.conf')!
		limine_after_sha256:      hash(root + '/stage/limine-after.conf')!
		staged_boot_sha256:       hash(root + '/stage/boot.img')!
		staged_efivars_sha256:    hash(root + '/stage/efivars.fd')!
	}
	stage_text := json2.encode(stage, prettify: true)
	os.write_file(root + '/stage/stage.json', stage_text)!
	mut kernel := []u8{len: 64}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { kernel[index] = value }
	kernel[16] = 2
	kernel[18] = 183
	os.write_file_array(root + '/build/vinix', kernel)!
	os.write_file(root + '/build/kernel/socket/unix/unix.v', 'frozen Unix socket source')!
	kernel_hash := hash(root + '/build/vinix')!
	unix_hash := hash(root + '/build/kernel/socket/unix/unix.v')!
	os.write_file(root + '/build/build.json', json2.encode(Build{
		format:                    1
		source_revision:           'a'.repeat(40)
		architecture:              'aarch64'
		kernel_path:               root + '/build/vinix'
		kernel_sha256:             kernel_hash
		kernel_unix_source_sha256: unix_hash
		generated_c_sha256:        'b'.repeat(64)
		compiler_sha256:           'c'.repeat(64)
		link_seed:                 20261026
	}))!
	os.write_file(root + '/build/input-pins.json', json2.encode({
		'kernel': {
			'kernel/socket/unix/unix.v': unix_hash
		}
	}))!
	os.write_file(root + '/build/sha256.json', json2.encode(Inventory{
		files: {
			'vinix':                     kernel_hash
			'kernel/socket/unix/unix.v': unix_hash
		}
	}))!
	receipt_sha := hash(root + '/build/build.json')!
	profile := Profile{'fixture', hash(baseline)!, overlay, module_names}
	if _ := patch(root + '/stage', root + '/build', '0'.repeat(64), profile) {
		return error('wrong build receipt pin accepted')
	}
	assert os.read_file(root + '/stage/stage.json')! == stage_text
	assert hash(root + '/stage/boot.img')! == stage.staged_boot_sha256
	patch(root + '/stage', root + '/build', receipt_sha, profile)!
	updated_stage := json2.decode[Stage](os.read_file(root + '/stage/stage.json')!)!
	assert updated_stage.staged_boot_sha256 != stage.staged_boot_sha256
	assert updated_stage.inputs_sha256 == stage.inputs_sha256
	assert updated_stage.original_modules_sha256 == stage.original_modules_sha256
	assert updated_stage.preserved_modules_sha256 == stage.preserved_modules_sha256
	assert updated_stage.overlay_sha256 == stage.overlay_sha256
	assert updated_stage.staged_efivars_sha256 == stage.staged_efivars_sha256
	assert os.read_file(root + '/stage/stage-before-kernel.json')! == stage_text
	assert os.is_file(root + '/stage/kernel-patch.json')
	if _ := patch(root + '/stage', root + '/build', receipt_sha, profile) {
		return error('second patch of same stage accepted')
	}
	println('BROWSER-KERNEL-PATCH FAT-SELF-TEST PASS pinned build rejection exact kernel readback baseline modules overlay firmware receipts once-only')
}

fn protected_receipt_fixture() map[string]json2.Any {
	return {
		'kind': json2.Any('vinix-protected-storage-maps-diagnostic-v1')
		'base_root': json2.Any(protected_base)
		'base_manifest_sha256': json2.Any(protected_base_seal)
		'framework_manifest_sha256': json2.Any(protected_framework_seal)
		'native_manifest_sha256': json2.Any(protected_native_seal)
		'retained_launch_manifest_sha256': json2.Any('920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be')
	}
}

fn protected_profile_self_test() ! {
	profile := protected_maps_profile()
	assert profile.baseline_sha == protected_boot_sha
	assert profile.modules.len == 7 && profile.modules.last() == 'maps-account.tar'
	before := Config{'vinix', profile.modules}
	mut modules := profile.modules.clone()
	modules << profile.overlay
	verify_modules(profile, before, Config{'vinix', modules})!
	for bad in [Config{'vinix', profile.modules}, Config{'vinix', modules.reverse()},
		Config{'vinix', modules[..7].clone()}, Config{'other', modules}] {
		if _ := verify_modules(profile, before, bad) { return error('unsafe protected Maps modules accepted') }
	}
	if _ := verify_modules(profile, Config{'vinix', maps_profile().modules},
		Config{'vinix', modules}) { return error('six-module protected Maps baseline accepted') }
	stage := Stage{
		format: 1
		inputs_sha256: {
			protected_base + '/sha256.json': protected_base_seal
			'/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2/sha256.json': protected_framework_seal
			'/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-protected-r1/sha256.json': protected_native_seal
		}
		original_modules_sha256: protected_modules()
		preserved_modules_sha256: protected_modules()
	}
	receipt := protected_receipt_fixture()
	verify_protected_receipt(receipt, stage)!
	for name in receipt.keys() {
		mut bad := protected_receipt_fixture()
		bad[name] = json2.Any('wrong')
		if _ := verify_protected_receipt(bad, stage) { return error('changed protected receipt accepted: ' + name) }
		bad.delete(name)
		if _ := verify_protected_receipt(bad, stage) { return error('missing protected receipt accepted: ' + name) }
	}
	for path in stage.inputs_sha256.keys() {
		mut bad_inputs := stage.inputs_sha256.clone()
		bad_inputs[path] = '0'.repeat(64)
		if _ := verify_protected_receipt(receipt, Stage{...stage, inputs_sha256: bad_inputs}) {
			return error('changed protected input pin accepted')
		}
	}
	mut bad_modules := protected_modules()
	bad_modules['maps-account.tar'] = '0'.repeat(64)
	for bad in [Stage{...stage, format: 2}, Stage{...stage, original_modules_sha256: bad_modules},
		Stage{...stage, preserved_modules_sha256: map[string]string{}}] {
		if _ := verify_protected_receipt(receipt, bad) { return error('changed protected module contract accepted') }
	}
	println('PROTECTED-STORAGE-MAPS KERNEL-PROFILE-SELF-TEST PASS exact receipt base framework native launch inputs seven modules')
}

fn self_test() ! {
	protected_profile_self_test()!
	maps := maps_profile()
	before := Config{'vinix', maps.modules}
	mut modules := maps.modules.clone()
	modules << maps.overlay
	verify_modules(maps, before, Config{'vinix', modules})!
	mut wrong_overlay := maps.modules.clone()
	wrong_overlay << 'browser-probe.tar'
	for bad in [Config{'vinix', maps.modules},
		Config{'vinix', modules.reverse()},
		Config{'vinix', wrong_overlay},
		Config{'other', modules}] {
		if _ := verify_modules(maps, before, bad) {
			return error('altered Maps module profile accepted')
		}
	}
	if _ := verify_modules(maps, Config{'vinix', ['runtime.tar']},
		Config{'vinix', ['runtime.tar', maps.overlay]}) {
		return error('unaudited Maps baseline modules accepted')
	}
	config := '/Vinix\n kernel_path: boot():/boot/vinix\n module_path: boot():/boot/runtime.tar\n'
	assert configure(config)!.modules == ['runtime.tar']
	for bad in [config + '/Other\n', config + ' kernel_path: boot():/boot/vinix\n',
		config + ' module_path: boot():/boot/runtime.tar\n', config.replace('/vinix', '/../vinix'),
		config.replace('/runtime.tar', '/runtime')] {
		if _ := configure(bad) { return error('ambiguous or unsafe configuration accepted') }
	}
	assert !relative('../escape') && !relative('a//b') && !digest_valid('a'.repeat(63))
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-browser-kernel-patch-' + os.getpid().str())
	if os.exists(root) { return error('self-test path exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	hash_self_test(root)!
	os.write_file(root + '/payload', 'exact frozen input\x00bytes')!
	verify_inventory(root, Inventory{ files: {
		'payload': hash(root + '/payload')!
	} })!
	for bad in [Inventory{}, Inventory{ files: {
		'../escape': hash(root + '/payload')!
	} }, Inventory{ files: {
		'payload': '0'.repeat(64)
	} }] {
		if _ := verify_inventory(root, bad) { return error('invalid frozen inventory accepted') }
	}
	os.symlink('payload', root + '/link')!
	if _ := verify_inventory(root, Inventory{ files: {
		'link': hash(root + '/payload')!
	} }) {
		return error('symlink substituted for regular frozen input')
	}
	unlaunched(root)!
	os.write_file(root + '/launch.json', '{}')!
	if _ := unlaunched(root) { return error('historical launched stage accepted') }
	fat_self_test(root + '/browser', 'browser-probe.tar', ['runtime.tar'])!
	fat_self_test(root + '/maps', 'maps-account.tar', ['runtime.tar'])!
	fat_self_test(root + '/protected-maps', 'protected-storage-diagnostic.tar', protected_maps_profile().modules)!
	println('BROWSER-KERNEL-PATCH SELF-TEST PASS configuration inventory digest symlink launched-stage guards')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	is_maps := os.args.len == 5 && os.args[1] == '--maps-account'
	is_protected := os.args.len == 5 && os.args[1] == '--protected-storage-maps'
	if os.args.len != 4 && !is_maps && !is_protected {
		eprintln('usage: patch-kernel [--maps-account|--protected-storage-maps] FRESH_STAGE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256')
		exit(2)
	}
	offset := if is_maps || is_protected { 1 } else { 0 }
	root := external(os.args[1 + offset]) or {
		eprintln(err)
		exit(1)
	}
	build_root := external(os.args[2 + offset]) or {
		eprintln(err)
		exit(1)
	}
	profile := if is_protected { protected_maps_profile() } else if is_maps { maps_profile() } else { browser_profile() }
	patch(root, build_root, os.args[3 + offset], profile) or {
		eprintln(err)
		exit(1)
	}
}
