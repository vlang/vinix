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
const lease_kernel = '/Users/alex/.cache/vpr-20261113-01/x86-production-01'
const lease_kernel_hash = 'ed5a26544945c8c599c0adc05efcbace8dae10e058f8fb66131f04caa8292fa7'
const tar_extent = wineoverlay.Span{1571 * 2048, 438748672}

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}
fn build_requested() bool { return os.getenv('VINIX_WINE_OWNED_BUILDER') == '1' && os.getenv('VINIX_AMD64_ISO') != '' }

// This diagnostic boots UEFI. Replaying the old boot layout may regenerate
// the BIOS boot-info table (bytes 8..63), but no other boot-file bytes may vary.
fn image_files(image string, log string) !map[string]wineoverlay.Span {
	invoke(['/opt/homebrew/bin/xorriso', '-indev', image, '-find', '/', '-type', 'f', '-exec', 'report_lba', '--'], log)!
	mut files := map[string]wineoverlay.Span{}
	for line in os.read_lines(log)! {
		if !line.starts_with('File data lba:') { continue }
		parts := line.split(',')
		if parts.len != 5 { return error('unexpected diagnostic ISO extent') }
		name := parts[4].trim_space()
		if !name.starts_with("'/") || !name.ends_with("'") || files.len >= 32 { return error('unsupported diagnostic ISO name') }
		path := name[1..name.len - 1]
		if path in files { return error('duplicate diagnostic ISO file') }
		for number in [parts[1].trim_space(), parts[3].trim_space()] {
			if number == '' { return error('missing diagnostic ISO extent number') }
			for byte in number { if byte < `0` || byte > `9` { return error('invalid diagnostic ISO extent number') } }
		}
		files[path] = wineoverlay.Span{parts[1].trim_space().u64() * 2048, parts[3].trim_space().u64()}
	}
	if files.len == 0 { return error('empty diagnostic ISO file inventory') }
	return files
}

fn rebase_kernel(work string) !(string, wineoverlay.Span) {
	image := work + '/kernel-baseline.iso'
	invoke(['/opt/homebrew/bin/xorriso', '-indev', baseline, '-outdev', image, '-boot_image', 'any', 'replay', '-map', lease_kernel, '/boot/vinix'], work + '/rebase.log')!
	old := image_files(baseline, work + '/original-files.log')!
	new := image_files(image, work + '/rebased-files.log')!
	if old.len != new.len { return error('rebased ISO file inventory differs') }
	for path, span in old {
		other := new[path] or { return error('rebased ISO lost file') }
		if path == '/boot/vinix' {
			if wineoverlay.range_digest(image, other.offset, other.size)! != lease_kernel_hash { return error('embedded production kernel differs') }
			continue
		}
		if span.size != other.size { return error('rebased ISO changed file size') }
		if path == '/boot/limine-bios-cd.bin' {
			if span.size < 64 || wineoverlay.range_digest(baseline, span.offset, 8)! != wineoverlay.range_digest(image, other.offset, 8)!
				|| wineoverlay.range_digest(baseline, span.offset + 64, span.size - 64)! != wineoverlay.range_digest(image, other.offset + 64, other.size - 64)! { return error('rebased BIOS file changed beyond boot-info table') }
		} else if wineoverlay.range_digest(baseline, span.offset, span.size)! != wineoverlay.range_digest(image, other.offset, other.size)! { return error('rebased ISO changed retained file: ' + path) }
	}
	if '/boot/vinix' !in old { return error('original ISO kernel missing') }
	span := new['/boot/initramfs.tar'] or { return error('rebased ISO initramfs missing') }
	return image, span
}
fn build_overlay() ! {
	output := os.getenv('VINIX_AMD64_ISO')
	guest := os.getenv('VINIX_WINE_OWNED_GUEST')
	selected_kernel := if os.getenv('VINIX_WINE_OWNED_LEASE') == '1' { lease_kernel } else { kernel }
	selected_hash := if selected_kernel == lease_kernel { lease_kernel_hash } else { kernel_hash }
	image := if selected_kernel == lease_kernel { os.getenv('VINIX_WINE_OWNED_BASELINE') } else { baseline }
	image_hash := if selected_kernel == lease_kernel { os.getenv('VINIX_WINE_OWNED_BASELINE_SHA256') } else { baseline_hash }
	tar := if selected_kernel == lease_kernel { wineoverlay.Span{os.getenv('VINIX_WINE_OWNED_TAR_OFFSET').u64(), tar_extent.size} } else { tar_extent }
	if os.getenv('VINIX_AMD64_KERNEL') != selected_kernel || wineoverlay.digest(selected_kernel)! != selected_hash
		|| wineoverlay.digest(baseline)! != baseline_hash || wineoverlay.digest(image)! != image_hash || wineoverlay.digest(guest)! != os.getenv('VINIX_WINE_OWNED_GUEST_SHA256') {
		return error('owned Wine overlay inputs differ')
	}
	wineoverlay.clone_fresh(image, output)!
	span := wineoverlay.patch_init(image, output, guest, tar, original_init_hash)!
	os.write_file(os.dir(output) + '/overlay.json', json2.encode({
		'original': image, 'original_sha256': image_hash, 'guest': guest, 'guest_sha256': wineoverlay.digest(guest)!,
		'output_sha256': wineoverlay.digest(output)!, 'init_offset': span.offset.str(), 'init_size': span.size.str(),
		'new_init_payload_sha256': wineoverlay.range_digest(output, span.offset, span.size)!
	}))!
	if wineoverlay.digest(baseline)! != baseline_hash { return error('original image changed during overlay') }
}
fn run() ! {
	if os.args.len !in [6, 7, 8] { return error('usage: CHECK FRESH_OUTPUT SYSROOT GCC_INSTALL CLANG V [owned|lease|lease-caller-death|lease-unheld|cwd|cwd-wrong|sandbox|sandbox-cwd] [CWD_PE]') }
	mode := if os.args.len >= 7 { os.args[6] } else { 'owned' }
	if mode !in ['owned', 'lease', 'lease-caller-death', 'lease-unheld', 'cwd', 'cwd-wrong', 'sandbox', 'sandbox-cwd'] { return error('unknown Wine diagnostic mode') }
	cwd := mode in ['cwd', 'cwd-wrong', 'sandbox-cwd']
	sandbox := mode in ['sandbox', 'sandbox-cwd']
	if (cwd && os.args.len != 8) || (!cwd && os.args.len == 8) { return error('only cwd diagnostics require an explicit Win64 payload') }
	leasing := mode in ['lease', 'lease-caller-death', 'lease-unheld']
	rebasing := mode != 'owned'
	selected_kernel := if rebasing { lease_kernel } else { kernel }
	selected_hash := if rebasing { lease_kernel_hash } else { kernel_hash }
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.abs_path(os.args[1]); cc := os.args[4]; v := os.args[5]
	if os.exists(work) || os.is_link(work) { return error('fresh diagnostic output required') }
	probe := root + '/tests/packages/wine-owned-probe.v'
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-owned-check.v').to_string())
		|| winesource.file_digest(probe)! != sha256.hexhash($embed_file('wine-owned-probe.v').to_string()) { return error('compiled diagnostic sources differ') }
	if wineoverlay.digest(baseline)! != baseline_hash || wineoverlay.digest(selected_kernel)! != selected_hash { return error('retained baseline differs') }
	host := hwhost.find_host(root, 'x86_64', '')!
	mut inputs := map[string]string{}
	for path in [@FILE, probe, os.executable(), v, cc, host.qemu, host.firmware] { inputs[path] = winesource.file_digest(path)! }
	inputs[baseline] = baseline_hash; inputs[selected_kernel] = selected_hash
	if sandbox { inputs[root + '/tools/packages/pkgcore/launch.v'] = wineoverlay.digest(root + '/tools/packages/pkgcore/launch.v')! }
	if rebasing { inputs['/opt/homebrew/bin/xorriso'] = wineoverlay.digest('/opt/homebrew/bin/xorriso')! }
	for directory in [root + '/tests/packages/wineoverlay', root + '/tests/hardware-platform/hwhost'] {
		for path in os.walk_ext(directory, '.v') { inputs[path] = winesource.file_digest(path)! }
	}
	os.mkdir_all(work)!
	mut image := baseline
	mut tar := tar_extent
	if rebasing { image, tar = rebase_kernel(work)! }
	image_hash := wineoverlay.digest(image)!
	mut compiled_probe := probe
	if cwd {
		pe := os.real_path(os.args[7])
		inputs[pe] = wineoverlay.digest(pe)!
		inputs[root + '/tests/packages/wine-cwd-program.v'] = wineoverlay.digest(root + '/tests/packages/wine-cwd-program.v')!
		os.cp(pe, work + '/cwd.exe')!
		compiled_probe = work + '/guest.v'
		os.write_file(compiled_probe, os.read_file(probe)! + '\nconst cwd_program = $embed_file("cwd.exe")\n')!
		inputs[compiled_probe] = wineoverlay.digest(compiled_probe)!
		inputs[work + '/cwd.exe'] = inputs[pe]
	}
	mut command := [v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64', '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|' + root + '|@vmodules', '-o', work + '/guest.c', compiled_probe]
	if leasing { command.insert(1, ['-d', 'wine_owned_lease']) }
	if mode == 'lease-unheld' { command.insert(1, ['-d', 'wine_owned_lease_unheld']) }
	if mode == 'lease-caller-death' { command.insert(1, ['-d', 'wine_owned_lease_caller_death']) }
	if cwd { command.insert(1, ['-d', 'wine_owned_cwd']) }
	if mode == 'cwd-wrong' { command.insert(1, ['-d', 'wine_owned_cwd_wrong']) }
	if sandbox { command.insert(1, ['-d', 'wine_owned_sandbox']) }
	mut discovery := command.clone(); discovery.insert(1, ['-print-watched-files', '-dump-files', work + '/sources-before.txt'])
	invoke(discovery, work + '/discover.log')!
	winesource.capture(work + '/sources-before.txt', mut inputs)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	command.insert(1, ['-dump-files', work + '/sources-built.txt']); invoke(command, work + '/v.log')!
	winesource.admit(work + '/sources-before.txt', work + '/sources-built.txt', inputs)!
	mut cc_command := [cc, '--target=x86_64-linux-musl', '--sysroot=' + os.args[2], '--gcc-install-dir=' + os.args[3], '-fuse-ld=lld', '-static',
		'-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', work + '/guest.c', '-lm', '-lpthread', '-o', work + '/guest']
	// Preserve generated C; strip only the embedded-payload diagnostic's ELF
	// symbols so it fits the fixed historical init slot without changing TAR.
	if cwd { cc_command.insert(1, '-s') }
	invoke(cc_command, work + '/cc.log')!
	guest_hash := wineoverlay.digest(work + '/guest')!
	os.mkdir_all(work + '/builder/build-support')!
	os.symlink(os.executable(), work + '/builder/build-support/build-amd64-iso.sh')!
	os.setenv('VINIX_WINE_OWNED_BUILDER', '1', true)
	os.setenv('VINIX_WINE_OWNED_LEASE', if rebasing { '1' } else { '0' }, true)
	os.setenv('VINIX_WINE_OWNED_BASELINE', image, true)
	os.setenv('VINIX_WINE_OWNED_BASELINE_SHA256', image_hash, true)
	os.setenv('VINIX_WINE_OWNED_TAR_OFFSET', tar.offset.str(), true)
	os.setenv('VINIX_WINE_OWNED_GUEST', work + '/guest', true)
	os.setenv('VINIX_WINE_OWNED_GUEST_SHA256', guest_hash, true)
	boot_host := hwhost.Host{...host, root: work + '/builder'}
	mut required := if leasing { ['WINE OWNED SERVER CONNECT PASS', 'VINIX SIGNED REAL WIN64 PASS', 'WINE OWNED LEASE MANAGER PASS', 'WINE OWNED LEASE BUSY PASS', 'WINE OWNED LEASE PASS manager=37; descendants retired; lease free', 'HWTEST PASS owned Wine diagnostic'] }
		else { ['WINE OWNED SERVER CONNECT PASS', 'VINIX SIGNED REAL WIN64 PASS', 'WINE OWNED CLIENT EXEC PASS', 'WINE OWNED RELATIVE APPLICATION PASS', 'HWTEST PASS owned Wine diagnostic'] }
	if mode == 'lease-caller-death' { required << 'WINE OWNED LEASE CALLER DEATH PASS lease remains busy' }
	if cwd {
		required = ['WINE OWNED SERVER CONNECT PASS', 'WINE OWNED CLIENT EXEC PASS', 'WINE WINDOWS CWD HOST CHECK PASS', 'HWTEST PASS owned Wine diagnostic']
		required << if mode != 'cwd-wrong' { 'WINE WINDOWS CWD PASS current directory; relative read/write; child inheritance' } else { 'WINE WINDOWS CWD CONTROL PASS incorrect expected directory detected' }
	}
	if sandbox {
		required << 'WINE OWNED SANDBOX DENIAL PASS outside file inaccessible'
		required << 'WINE OWNED SANDBOX PLEDGE PASS internet socket killed with SIGABRT'
	}
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'owned-Wine-diagnostic', arches: ['x86_64'], ending: .running,
		required: required,
		forbidden: ['HWTEST FAIL', 'Kernel panic']}, hwhost.Run{kernel: selected_kernel, guest: work + '/guest', state: work + '/boot', timeout: 180, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, expected in inputs { if wineoverlay.digest(path)! != expected { return error('diagnostic input changed: ' + path) } }
	if wineoverlay.digest(work + '/guest')! != guest_hash { return error('guest changed') }
	if wineoverlay.digest(image)! != image_hash { return error('diagnostic boot baseline changed') }
	wineoverlay.verify_delta(image, work + '/boot/test.iso', work + '/guest', wineoverlay.init_span(image, tar)!)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if outcome.interrupted { return error('owned Wine diagnostic interrupted') }
	if mode == 'lease-unheld' {
		if outcome.passed || !outcome.reason.contains('HWTEST FAIL owned Wine lease: live Wine lease was not busy') { return error('unheld Wine control failed at wrong gate: ' + outcome.reason) }
		println('WINE OWNED LEASE CONTROL PASS unheld lease detected')
		return
	}
	if !outcome.passed { return error('owned Wine diagnostic failed: ' + outcome.reason) }
	println('WINE OWNED DIAGNOSTIC PASS reused immutable baseline; no new signed-package qualification')
}
fn main() {
	if build_requested() { build_overlay() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
