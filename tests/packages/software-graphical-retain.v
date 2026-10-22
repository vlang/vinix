// SPDX-License-Identifier: GPL-2.0-or-later
// Verify and retain one completed ordinary-seat graphical run.
module main

import crypto.sha256
import json2
import os

struct Receipt {
	architecture string
	platform string
	artifacts map[string]string
	artifact_paths map[string]string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn main() {
	retain() or { eprintln(err); exit(1) }
}

fn exact_marker(transcript string, marker string) ! {
	if transcript.split_into_lines().filter(it.trim_right('\r') == marker).len != 1 {
		return error('missing or duplicated exact marker: ' + marker)
	}
}

fn admit_serial(path string, installed bool, boot int, arch string) ! {
	transcript := os.read_file(path)!
	mut forbidden := ['SOFTWARE GRAPHICAL FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION']
	if installed { forbidden << ['sysdisk: running from memory', 'sysdisk: updating the system on'] }
	for marker in forbidden {
		if transcript.contains(marker) { return error('forbidden serial marker: ' + marker) }
	}
	exact_marker(transcript, 'SOFTWARE GRAPHICAL ordinary-compositor uid=1000 home=/home/alex PASS')!
	if installed { exact_marker(transcript, 'SOFTWARE GRAPHICAL native Counter launch child closed PASS')! }
	if installed && arch == 'aarch64' { exact_marker(transcript, 'syspower: power off: stopping devices')! }
	if boot == 1 {
		exact_marker(transcript, 'SOFTWARE GRAPHICAL ordinary-counter two-pointer-events persisted uid=1000 PASS')!
		if installed {
			exact_marker(transcript, 'SOFTWARE GRAPHICAL INSTALLED reviewed-password-approved exact Counter install PASS')!
			exact_marker(transcript, 'SOFTWARE GRAPHICAL INSTALLED BOOT 1 acquired pointer-saved cold-boot checkpoint PASS')!
		}
	} else {
		exact_marker(transcript, 'SOFTWARE GRAPHICAL INSTALLED BOOT 2 retained Counter reopened and pointer-saved PASS')!
	}
}

fn admit_shutdown(path string, boot int) ! {
	if (os.stat(path)!).size > 1024 * 1024 { return error('QMP shutdown transcript exceeds limit') }
	lines := os.read_file(path)!.split_into_lines()
	if lines.len < 4 { return error('missing exact guest SHUTDOWN event') }
	mut count := 0
	for index, line in lines {
		object := json2.decode[json2.Any](line)!.as_map()
		if index == 0 {
			binding := object['graphical_boot'] or { return error('QMP shutdown boot binding differs') }
			if binding !is f64 || binding.f64() != f64(boot) {
				return error('QMP shutdown boot binding differs')
			}
		}
		if index == 1 && 'QMP' !in object { return error('invalid shutdown QMP greeting') }
		if index == 2 && 'return' !in object { return error('shutdown QMP capabilities refused') }
		event := (object['event'] or { json2.Any('') }).str()
		if event in ['RESET', 'GUEST_PANICKED'] { return error('forbidden QMP power event: ' + event) }
		if event == 'SHUTDOWN' {
			data := (object['data'] or { return error('QMP shutdown has no data') }).as_map()
			if (data['guest'] or { json2.Any(false) }) != json2.Any(true) ||
				(data['reason'] or { json2.Any('') }) != json2.Any('guest-shutdown') {
				return error('QMP did not report guest-initiated shutdown')
			}
			count++
		}
	}
	if count != 1 { return error('missing or duplicated exact guest SHUTDOWN event') }
}

fn retain() ! {
	$if prod {} $else { return error('compile the graphical retainer with -prod to freeze its embedded source') }
	embedded_source := $embed_file('software-graphical-retain.v').to_string()
	if sha256.sum(embedded_source.bytes()).hex() != digest(@FILE)! {
		return error('retainer source changed after retainer compilation')
	}
	if os.args.len != 7 {
		return error('use RUN_DIRECTORY DESKTOP_BUILD_DIRECTORY KERNEL_ELF CONTROLLER_ELF OUTPUT_DIRECTORY ARCH')
	}
	run := os.abs_path(os.args[1])
	build := os.abs_path(os.args[2])
	out := os.abs_path(os.args[5])
	arch := os.args[6]
	receipt := json2.decode[Receipt](os.read_file(run + '/qualification.json')!)!
	if receipt.architecture != arch || receipt.platform !in ['qemu-framebuffer-ordinary-seat',
		'qemu-framebuffer-ordinary-seat-installed-root-two-boots'] {
		return error('requires the selected architecture ordinary-seat receipt')
	}
	for name, expected in {
		'software-graphical-check.v': $embed_file('software-graphical-check.v').to_string()
		'software-graphical-build.v': $embed_file('software-graphical-build.v').to_string()
		'guest/main.v': $embed_file('software-graphical-guest/main.v').to_string()
		'guest/installed.v': $embed_file('software-graphical-guest/installed.v').to_string()
	} {
		if digest(run + '/source/' + name)! != sha256.sum(expected.bytes()).hex() {
			return error('qualified graphical fixture differs from the embedded source: ' + name)
		}
	}
	if arch == 'x86_64' && digest(run + '/source/plainiso.v')! !=
		sha256.sum($embed_file('../hardware-platform/plainiso/iso.v').to_string().bytes()).hex() {
		return error('qualified graphical fixture differs from the embedded source: plainiso.v')
	}
	installed := receipt.platform.ends_with('installed-root-two-boots')
	admit_serial(run + '/serial.log', installed, 1, arch)!
	if installed {
		admit_serial(run + '/serial-2.log', true, 2, arch)!
		admit_shutdown(run + '/shutdown-1.jsonl', 1)!
		admit_shutdown(run + '/shutdown-2.jsonl', 2)!
	}
	mut paths := {
		'controller': os.abs_path(os.args[4])
		'desktop': build + '/vinix-desktop'
		'desktop-build': run + '/desktop-build.json'
		'desktop-build-original': build + '/desktop-build.json'
		'kernel': os.abs_path(os.args[3])
		'config': run + '/rootfs/etc/vinix-packages/config.json'
		'initramfs': run + '/initramfs.tar'
		'serial': run + '/serial.log'
		'guest': run + '/guest-build/init'
		'guest-c': run + '/guest-build/init.c'
		'shutdown-1': run + '/shutdown-1.jsonl'
	}
	if arch == 'x86_64' {
		paths['source/plainiso.v'] = run + '/source/plainiso.v'
		paths['boot-iso'] = run + '/test.iso'
		paths['boot-configuration'] = run + '/iso/iso-root/boot/limine.conf'
		paths['boot-image-commands'] = run + '/image-commands.json'
	}
	for name in ['software-graphical-check.v', 'software-graphical-build.v'] {
		paths['source/' + name] = run + '/source/' + name
	}
	for path in os.walk_ext(run + '/source/guest', '.v') {
		paths['source/guest/' + os.file_name(path)] = path
	}
	if receipt.platform.ends_with('installed-root-two-boots') {
		paths['system-disk'] = run + '/system.vjfs'
		paths['serial-2'] = run + '/serial-2.log'
		paths['shutdown-2'] = run + '/shutdown-2.jsonl'
		paths['installed-declaration'] = run + '/rootfs/usr/share/software-graphical-installed.json'
	}
	repository := run + '/rootfs/usr/share/vinix-packages/repositories/native'
	for path in os.walk_ext(repository, '') {
		if os.is_file(path) { paths['repository/' + path[repository.len + 1..]] = path }
	}
	mut shots := []string{}
	for path in os.walk_ext(run, '.png') {
		if os.dir(path) != run { continue }
		name := os.file_name(path).all_before_last('.')
		shots << name
		paths[name] = path
	}
	mut required_shots := ['01-catalog', '02-maximized', '03-counter-zero', '04-counter-two',
		'05-persisted', '06-catalog-return', '07-counter-reopened']
	if receipt.platform.ends_with('installed-root-two-boots') {
		required_shots << ['08-counter-three', '09-reboot-catalog', '10-reboot-counter-retained',
			'11-reboot-counter-four', 'install-01-review', 'install-02-administrator',
			'install-03-password-mask', 'install-04-acquired']
	}
	shots.sort()
	required_shots.sort()
	if shots != required_shots { return error('graphical run lacks the exact required screenshot set') }
	for name, path in paths {
		if name !in receipt.artifacts { return error('missing required artifact digest: ' + name) }
		if os.real_path(path) != receipt.artifact_paths[name] {
			return error('receipt input path mismatch: ' + name)
		}
	}
	if receipt.artifact_paths.len != receipt.artifacts.len {
		return error('receipt artifact paths do not cover every recorded digest')
	}
	for name, _ in receipt.artifact_paths {
		if name !in receipt.artifacts { return error('missing artifact digest: ' + name) }
	}
	for name, expected in receipt.artifacts {
		path := receipt.artifact_paths[name] or { return error('missing artifact path: ' + name) }
		if digest(path)! != expected { return error('receipt mismatch: ' + name) }
	}
	if receipt.artifacts['desktop-build-original'] != receipt.artifacts['desktop-build'] {
		return error('original desktop build manifest differs from run copy')
	}
	manifest := json2.decode[map[string]string](os.read_file(build + '/desktop-build.json')!)!
	if manifest['vinix-desktop'] != receipt.artifacts['desktop'] {
		return error('desktop receipt does not bind the qualified executable')
	}
	for name in ['main.v', 'terminal.v', 'platform.c.v', 'registration.v', 'registration_store.v', 'gpucore/core.v',
		'sessionruntime/runtime.c.v', 'sessionipc/client.c.v', 'windowfb/transport.c.v'] {
		if digest('desktop/' + name)! != manifest['desktop/' + name] ||
			digest(build + '/source/desktop/' + name)! != manifest['desktop/' + name] {
			return error('qualified desktop identity source differs: ' + name)
		}
	}
	os.mkdir_all(out)!
	prefix := out + '/software-graphical-' + arch
	for name, suffix in {
		'qualification.json': '.json'
		'desktop-build.json': '.desktop-build.json'
		'serial.log': '.serial.txt'
		'shutdown-1.jsonl': '.shutdown-1.jsonl'
	} { os.cp(run + '/' + name, prefix + suffix)! }
	if receipt.platform.ends_with('installed-root-two-boots') {
		os.cp(run + '/serial-2.log', prefix + '.serial-2.txt')!
		os.cp(run + '/shutdown-2.jsonl', prefix + '.shutdown-2.jsonl')!
	}
	for name in shots { os.cp(run + '/' + name + '.png', prefix + '.' + name + '.png')! }
	println('SOFTWARE GRAPHICAL RETAIN PASS ' + arch + ': ' + receipt.artifacts.len.str() +
		' artifact digests and all nine current desktop identity/seat/runtime sources match')
}
