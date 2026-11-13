// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic against one immutable retained image, not package qualification.
module main

import hwhost
import json2
import os
import tests.packages.wineoverlay
import tests.packages.winesource
import crypto.sha256

// Pins from the workspace inventory recorded in wine-shared-user-check.md:
// 66e7a8785e1d6885e20db49e3b5d598ed6e1fda29bff201379d6fda1b4641200.
const baseline = '/Users/alex/.cache/vinix-wine-shared-user-20261112/native-x86-09/boot/test.iso'
const baseline_hash = '7997c94adeb32345401de0aaba546bfffd1e8826791bbd2ef9008c94b7b28179'
const original_init_hash = '49675c561bd22b2474e3d8da56b712dea3fb1ce2daafd3920cf4b567d10969a9'
const kernel = '/Users/alex/.cache/vinix-wine-pledge/vinix-x86_64'
const kernel_hash = '3ab99a5aebbc64efadd678f3de2ab6ec4ba4ade06bd76012ccdf4bc2635c36f6'
const tar_extent = wineoverlay.Span{1571 * 2048, 438748672}

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}
fn build_requested() bool { return os.getenv('VINIX_WINE_OWNED_BUILDER') == '1' && os.getenv('VINIX_AMD64_ISO') != '' }
fn build_overlay() ! {
	output := os.getenv('VINIX_AMD64_ISO')
	guest := os.getenv('VINIX_WINE_OWNED_GUEST')
	if os.getenv('VINIX_AMD64_KERNEL') != kernel || wineoverlay.digest(kernel)! != kernel_hash
		|| wineoverlay.digest(baseline)! != baseline_hash || wineoverlay.digest(guest)! != os.getenv('VINIX_WINE_OWNED_GUEST_SHA256') {
		return error('owned Wine overlay inputs differ')
	}
	wineoverlay.clone_fresh(baseline, output)!
	span := wineoverlay.patch_init(baseline, output, guest, tar_extent, original_init_hash)!
	os.write_file(os.dir(output) + '/overlay.json', json2.encode({
		'original': baseline, 'original_sha256': baseline_hash, 'guest': guest, 'guest_sha256': wineoverlay.digest(guest)!,
		'output_sha256': wineoverlay.digest(output)!, 'init_offset': span.offset.str(), 'init_size': span.size.str(),
		'new_init_payload_sha256': wineoverlay.range_digest(output, span.offset, span.size)!
	}))!
	if wineoverlay.digest(baseline)! != baseline_hash { return error('original image changed during overlay') }
}
fn run() ! {
	if os.args.len != 6 { return error('usage: CHECK FRESH_OUTPUT SYSROOT GCC_INSTALL CLANG V') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.abs_path(os.args[1]); cc := os.args[4]; v := os.args[5]
	if os.exists(work) || os.is_link(work) { return error('fresh diagnostic output required') }
	probe := root + '/tests/packages/wine-owned-probe.v'
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-owned-check.v').to_string())
		|| winesource.file_digest(probe)! != sha256.hexhash($embed_file('wine-owned-probe.v').to_string()) { return error('compiled diagnostic sources differ') }
	if wineoverlay.digest(baseline)! != baseline_hash || wineoverlay.digest(kernel)! != kernel_hash { return error('retained baseline differs') }
	host := hwhost.find_host(root, 'x86_64', '')!
	mut inputs := map[string]string{}
	for path in [@FILE, probe, os.executable(), v, cc, host.qemu, host.firmware] { inputs[path] = winesource.file_digest(path)! }
	inputs[baseline] = baseline_hash; inputs[kernel] = kernel_hash
	for directory in [root + '/tests/packages/wineoverlay', root + '/tests/hardware-platform/hwhost'] {
		for path in os.walk_ext(directory, '.v') { inputs[path] = winesource.file_digest(path)! }
	}
	os.mkdir_all(work)!
	mut command := [v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64', '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|' + root + '|@vmodules', '-o', work + '/guest.c', probe]
	mut discovery := command.clone(); discovery.insert(1, ['-print-watched-files', '-dump-files', work + '/sources-before.txt'])
	invoke(discovery, work + '/discover.log')!
	winesource.capture(work + '/sources-before.txt', mut inputs)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	command.insert(1, ['-dump-files', work + '/sources-built.txt']); invoke(command, work + '/v.log')!
	winesource.admit(work + '/sources-before.txt', work + '/sources-built.txt', inputs)!
	invoke([cc, '--target=x86_64-linux-musl', '--sysroot=' + os.args[2], '--gcc-install-dir=' + os.args[3], '-fuse-ld=lld', '-static',
		'-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', work + '/guest.c', '-lm', '-lpthread', '-o', work + '/guest'], work + '/cc.log')!
	guest_hash := wineoverlay.digest(work + '/guest')!
	os.mkdir_all(work + '/builder/build-support')!
	os.symlink(os.executable(), work + '/builder/build-support/build-amd64-iso.sh')!
	os.setenv('VINIX_WINE_OWNED_BUILDER', '1', true)
	os.setenv('VINIX_WINE_OWNED_GUEST', work + '/guest', true)
	os.setenv('VINIX_WINE_OWNED_GUEST_SHA256', guest_hash, true)
	boot_host := hwhost.Host{...host, root: work + '/builder'}
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'owned-Wine-diagnostic', arches: ['x86_64'], ending: .running,
		required: ['WINE OWNED SERVER CONNECT PASS', 'VINIX SIGNED REAL WIN64 PASS', 'WINE OWNED CLIENT EXEC PASS', 'HWTEST PASS owned Wine diagnostic'],
		forbidden: ['HWTEST FAIL', 'Kernel panic']}, hwhost.Run{kernel: kernel, guest: work + '/guest', state: work + '/boot', timeout: 180, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, expected in inputs { if wineoverlay.digest(path)! != expected { return error('diagnostic input changed: ' + path) } }
	if wineoverlay.digest(work + '/guest')! != guest_hash { return error('guest changed') }
	wineoverlay.verify_delta(baseline, work + '/boot/test.iso', work + '/guest', wineoverlay.init_span(baseline, tar_extent)!)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if outcome.interrupted || !outcome.passed { return error('owned Wine diagnostic failed: ' + outcome.reason) }
	println('WINE OWNED DIAGNOSTIC PASS reused immutable baseline; no new signed-package qualification')
}
fn main() {
	if build_requested() { build_overlay() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
