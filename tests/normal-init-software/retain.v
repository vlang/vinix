// SPDX-License-Identifier: GPL-2.0-or-later
// Admit the production-init workflow independently before copying evidence.
module main

import crypto.sha256
import hwhost
import json2
import normalproof
import os
import plainiso
import screenshotcore
import tools.packages.pkgprotocol

struct Qualification {
	architecture   string
	platform       string
	artifacts      map[string]string
	artifact_paths map[string]string
}

const screenshots = ['01-registration.png', '02-greeter.png', '03-ordinary-desktop.png',
	'04-start-software.png', '05-software.png', 'refresh-administrator.png', 'refresh-password-mask.png',
	'refresh-submitted.png', 'install-review.png', 'install-administrator.png',
	'install-password-mask.png', 'install-submitted.png', '06-counter-zero.png', '07-counter-two.png',
	'08-shutdown-menu.png', '10-reboot-greeter.png', '11-reboot-desktop.png', '12-start-software.png',
	'13-software-retained.png', 'uninstall-review.png', 'uninstall-administrator.png',
	'uninstall-password-mask.png', 'uninstall-submitted.png', 'reinstall-review.png',
	'reinstall-administrator.png', 'reinstall-password-mask.png', 'reinstall-submitted.png',
	'14-counter-retained-two.png', '15-counter-three.png', '16-shutdown-menu.png']

fn strings(path string) !map[string]string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return json2.decode[map[string]string](text)
}

fn read_arguments(path string) ![]string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return json2.decode[[]string](text)
}

fn exact_marker(text string, marker string) !int {
	mut count := 0
	mut at := -1
	mut offset := 0
	for line in text.split_into_lines() {
		if line == marker {
			count++
			at = offset
		}
		offset += line.len + 1
	}
	if count != 1 { return error('missing or duplicated exact marker: ' + marker) }
	return at
}

fn serial(text string, boot int, arch string, public_key string) ! {
	for forbidden in ['NORMAL INIT SOFTWARE FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION',
		'crashed with', 'sysdisk: running from memory', 'sysdisk: updating the system on', 'loginpass'] {
		if text.contains(forbidden) { return error('forbidden serial marker: ' + forbidden) }
	}
	mut markers := ['START optional-helper observer']
	if boot == 2 { markers << 'BOOT 2 exact accounts trust state private-data retained PASS' }
	markers << ['production PID1 installed disk inputs boot-restore-present PASS',
		'production init direct-child graphical manager root-private-lock PASS']
	if boot == 1 { markers << 'exclusive root registration READY' }
	markers << ['ordinary greeter uid=101 READY',
		'authenticated ordinary compositor uid=1000 private-home-runtime PASS']
	markers << if boot == 1 {
		['signed catalog refreshed approvals=1 PASS', 'review=install unchanged-state approvals=1 PASS',
			'installed signed=1.1.0 approvals=2 PASS']
	} else {
		['review=remove unchanged-state approvals=2 PASS',
			'uninstalled approvals=3 private=2 launcher-absent PASS',
			'review=install unchanged-state approvals=3 PASS',
			'reinstalled signed=1.1.0 approvals=4 private=2 PASS']
	}
	markers << ['native Counter and package launch child reaped uid=1000 PASS', if boot == 1 {
		'BOOT 1 signed acquisition private=2 exact checkpoint ready for UI shutdown PASS'
	} else {
		'BOOT 2 exact retention uninstall reinstall private=3 ready for UI shutdown PASS'
	}]
	mut previous := -1
	for marker in markers {
		at := exact_marker(text, 'NORMAL INIT SOFTWARE ' + marker)!
		if at <= previous { return error('serial workflow marker order differs') }
		previous = at
	}
	mut operations := []string{}
	for line in text.split_into_lines() {
		if !line.starts_with('NORMAL INIT SOFTWARE PROPOSAL ') { continue }
		review := json2.decode[pkgprotocol.Review](line.all_after('NORMAL INIT SOFTWARE PROPOSAL '))!
		review.validate()!
		if review.architecture != arch || review.names != ['org.vinix.counter'] || review.rows.len != 1 {
			return error('read-only proposal identity differs')
		}
		row := review.rows[0]
		if row.id != 'org.vinix.counter' || row.version != '1.1.0' || row.architecture != arch
			|| row.repository != 'native' || row.public_key != public_key || row.kind != 'native'
			|| row.license != 'MIT' || row.permissions != ['display'] || row.proprietary || row.firmware
			|| row.action != review.operation {
			return error('complete signed proposal row differs')
		}
		if review.requested != (if review.operation == 'remove' {
			[]string{}
		} else {
			['org.vinix.counter']
		}) {
			return error('proposal requested closure differs')
		}
		before := if boot == 1 {
			'signed catalog refreshed approvals=1 PASS'
		} else if review.operation == 'remove' {
			'authenticated ordinary compositor uid=1000 private-home-runtime PASS'
		} else {
			'uninstalled approvals=3 private=2 launcher-absent PASS'
		}
		after := if boot == 1 {
			'review=install unchanged-state approvals=1 PASS'
		} else if review.operation == 'remove' {
			'review=remove unchanged-state approvals=2 PASS'
		} else {
			'review=install unchanged-state approvals=3 PASS'
		}
		at := exact_marker(text, line)!
		if at <= exact_marker(text, 'NORMAL INIT SOFTWARE ' + before)!
			|| at >= exact_marker(text, 'NORMAL INIT SOFTWARE ' + after)! {
			return error('proposal order differs from read-only review')
		}
		operations << review.operation
	}
	if operations != (if boot == 1 { ['install'] } else { ['remove', 'install'] }) {
		return error('proposal operation inventory differs')
	}
}

fn shutdown(path string, boot int) ! {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	lines := text.split_into_lines()
	if lines.len < 4 { return error('missing exact guest SHUTDOWN event') }
	header := json2.decode[json2.Any](lines[0])!.as_map()
	value := header['graphical_boot'] or { return error('missing QMP boot binding') }
	if value !is f64 { return error('QMP shutdown boot binding differs') }
	if value != f64(boot) { return error('QMP shutdown boot binding differs') }
	if 'QMP' !in json2.decode[json2.Any](lines[1])!.as_map()
		|| 'return' !in json2.decode[json2.Any](lines[2])!.as_map() {
		return error('missing QMP greeting or capability admission')
	}
	mut count := 0
	for line in lines[3..] {
		record := json2.decode[json2.Any](line)!.as_map()
		event := (record['event'] or { json2.Any('') }).str()
		if event in ['RESET', 'GUEST_PANICKED'] {
			return error('forbidden QMP power event: ' + event)
		}
		if event != 'SHUTDOWN' { continue }
		count++
		data := (record['data'] or { return error('QMP shutdown has no data') }).as_map()
		if (data['guest'] or { json2.Any(false) }) != json2.Any(true)
			|| (data['reason'] or { json2.Any('') }) != json2.Any('guest-shutdown') {
			return error('QMP did not report guest-initiated shutdown')
		}
	}
	if count != 1 { return error('missing or duplicated exact guest SHUTDOWN event') }
}

fn selected_inputs(host hwhost.Host, image string, stage string, desktop string, kernel string,
	publisher string, cc string, sysroot string) !map[string]string {
	mut paths := normalproof.build_inputs(host.root, host.arch, host.v, cc, sysroot)!
	for name, path in normalproof.assembled(desktop, stage, host.arch, host.v)! {
		paths[name] = path
	}
	normalproof.inventory(image, 'image-root/', mut paths)!
	normalproof.inventory(publisher + '/workspace-1.1.0', 'publisher/workspace/', mut paths)!
	for name, path in {
		'publisher/image-config': publisher + '/image-config.json'
		'publisher/seed':         publisher + '/seed'
		'runtime/kernel':         kernel
		'runtime/qemu':           host.qemu
		'runtime/firmware':       host.firmware
		'runtime/busybox':        hwhost.shared_path(host.root, if host.arch == 'aarch64' {
			'build-aarch64-userland/staging/bin/busybox'
		} else {
			'build-amd64-userland/staging/bin/busybox'
		})
	} {
		paths[name] = path
	}
	if host.firmware_vars != '' { paths['runtime/firmware-vars'] = host.firmware_vars }
	if host.arch == 'aarch64' {
		paths['runtime/volume'] = hwhost.shared_path(host.root, 'build-aarch64-userland/staging/usr/sbin/vinix-volume')
		paths['runtime/loader'] = hwhost.shared_path(host.root, 'boot-image/limine-bin/BOOTAA64.EFI')
	} else {
		for name, path in plainiso.inputs(host.root)! { paths['media/' + name] = path }
	}
	return paths
}

fn generated_inventory(run string, arch string) !map[string]string {
	mut result := map[string]string{}
	for directory in ['source', 'session-build', 'init-build', 'observer-build', 'volume-build'] {
		if os.is_dir(run + '/' + directory) {
			normalproof.inventory(run + '/' + directory, directory + '/', mut result)!
		}
	}
	for path in ['/sbin/init', '/bin/busybox', '/usr/bin/vinix-desktop', '/usr/bin/vinix-package',
		'/usr/bin/vinix-sandbox', '/usr/sbin/vinix-account', '/usr/sbin/vinix-authd',
		'/usr/sbin/vinix-session', '/usr/sbin/vinix-system', '/usr/sbin/vinix-volume',
		'/usr/libexec/vinix-version-check', '/etc/vinix-packages/config.json',
		'/usr/share/vinix/actions/packages-change', '/usr/share/vinix/actions/packages-launch',
		'/usr/share/vinix/actions/power-off', '/usr/share/normal-init-software.json'] {
		result['rootfs' + path] = run + '/rootfs' + path
	}
	result['@link:rootfs/usr/bin/vinix-software'] = run + '/rootfs/usr/bin/vinix-software'
	result['initramfs'] = run + '/initramfs.tar'
	normalproof.inventory(run + '/rootfs/usr/share/vinix-packages/repositories/native', 'repository/', mut result)!
	for name in if arch == 'aarch64' {
		['boot.img']
	} else {
		['test.iso', 'image-commands.json', 'iso/iso-root/boot/limine.conf']
	} {
		result[name] = run + '/' + name
	}
	mut required := ['source/check.v', 'source/observer/main.v', 'source/normalproof/admit.v',
		'session-build/session.c', 'session-build/vinix-session', 'observer-build/observer.c',
		'observer-build/observer']
	for directory in ['session-build', 'observer-build'] {
		for producer in ['v', 'c'] {
			required << [directory + '/' + producer + '.log',
				directory + '/' + producer + '.log.argv.json']
		}
	}
	if arch == 'aarch64' {
		required << ['init-build/init.c', 'init-build/init.o', 'init-build/abi.o', 'init-build/init']
		for producer in ['v', 'c', 'abi', 'link'] {
			required << ['init-build/' + producer + '.log',
				'init-build/' + producer + '.log.argv.json']
		}
	} else {
		required << ['volume-build/volume.c', 'volume-build/vinix-volume']
		for producer in ['v', 'c'] {
			required << ['volume-build/' + producer + '.log',
				'volume-build/' + producer + '.log.argv.json']
		}
	}
	for name in required {
		if name !in result { return error('missing required generated artifact: ' + name) }
	}
	return result
}

fn same(hashes map[string]string, left string, right string) ! {
	if left !in hashes || right !in hashes || hashes[left] != hashes[right] {
		return error('staged output does not bind its build input: ' + left + ' / ' + right)
	}
}

fn require_args(run string, name string, program string, required []string) ! {
	argv := read_arguments(run + '/' + name)!
	if argv.len < 2 || argv[0] != program {
		return error('build arguments do not bind admitted compiler: ' + name)
	}
	for argument in required {
		if argument !in argv {
			return error('missing required build argument: ' + name + ' / ' + argument)
		}
	}
}

fn recorded_path(path string, original string, copy string) string {
	if path.starts_with(original + '/') { return copy + path[original.len..] }
	return path
}

fn retain() ! {
	$if prod {
	} $else {
		return error('compile validator with -prod to freeze embedded inputs')
	}
	if normalproof.digest(@FILE)! != sha256.hexhash($embed_file('retain.v').to_string()) {
		return error('retainer source differs from executable')
	}
	if os.args.len != 10 {
		return error('use RUN INPUT_ROOTFS STAGE DESKTOP KERNEL PUBLISHER CONTROLLER OUTPUT ARCH')
	}
	run := os.abs_path(os.args[1])
	image := os.abs_path(os.args[2])
	stage := os.abs_path(os.args[3])
	desktop := os.abs_path(os.args[4])
	kernel := os.abs_path(os.args[5])
	publisher := os.abs_path(os.args[6])
	controller := os.abs_path(os.args[7])
	output := os.abs_path(os.args[8])
	arch := os.args[9]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	if os.exists(output) || os.is_link(output) { return error('output must be new') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	cc := if arch == 'aarch64' {
		os.getenv('CC_AARCH64')
	} else {
		os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }
	}
	sysroot := if arch == 'aarch64' { os.getenv('VINIX_AARCH64_SYSROOT') } else { '' }
	if arch == 'aarch64' && (cc == '' || sysroot == '') {
		return error('explicit ARM observer toolchain required')
	}
	paths := strings(run + '/source-paths.json')!
	inputs := strings(run + '/source-inputs.json')!
	if inputs != strings(run + '/verified-source-inputs.json')! {
		return error('completed source input verification differs')
	}
	if paths != selected_inputs(host, image, stage, desktop, kernel, publisher, cc, sysroot)! {
		return error('source input inventory differs from selected qualification')
	}
	normalproof.unchanged(inputs, paths)!
	for name, text in {
		'check.v':             $embed_file('check.v').to_string()
		'observer/main.v':     $embed_file('observer/main.v').to_string()
		'normalproof/admit.v': $embed_file('normalproof/admit.v').to_string()
	} {
		key := 'source/tests/normal-init-software/' + name
		if inputs[key] != sha256.hexhash(text) {
			return error('fixture differs from embedded source: ' + name)
		}
	}
	generated := strings(run + '/generated-inputs.json')!
	generated_paths := strings(run + '/generated-paths.json')!
	anchor := generated_paths['source/check.v'] or { return error('missing recorded build namespace') }
	if !anchor.ends_with('/source/check.v') { return error('invalid recorded build namespace') }
	recorded_run := anchor[..anchor.len - '/source/check.v'.len]
	if !recorded_run.starts_with('/') || os.abs_path(recorded_run) != recorded_run {
		return error('invalid recorded build namespace')
	}
	if generated != strings(run + '/verified-generated-inputs.json')! {
		return error('completed generated input verification differs')
	}
	effective_paths := generated_inventory(run, arch)!
	mut recorded_paths := map[string]string{}
	for name, path in effective_paths {
		recorded_paths[name] = recorded_path(path, run, recorded_run)
	}
	if generated_paths != recorded_paths { return error('generated input inventory differs') }
	normalproof.unchanged(generated, effective_paths)!
	for name in ['source/check.v', 'source/observer/main.v', 'source/normalproof/admit.v'] {
		if generated[name] != inputs['source/tests/normal-init-software/' + name.all_after('source/')] {
			return error('frozen source does not bind admitted input: ' + name)
		}
	}
	same(generated, 'rootfs/usr/sbin/vinix-session', 'session-build/vinix-session')!
	same(generated, 'rootfs/usr/libexec/vinix-version-check', 'observer-build/observer')!
	if arch == 'aarch64' {
		same(generated, 'rootfs/sbin/init', 'init-build/init')!
	} else {
		same(generated, 'rootfs/usr/sbin/vinix-volume', 'volume-build/vinix-volume')!
	}
	for name, source in {
		'rootfs/usr/bin/vinix-desktop':          'assembled/desktop/vinix-desktop'
		'rootfs/bin/busybox':                    'runtime/busybox'
		'rootfs/etc/vinix-packages/config.json': 'publisher/image-config'
		'rootfs/usr/bin/vinix-package':          'assembled/stage/usr/bin/vinix-package'
		'rootfs/usr/bin/vinix-sandbox':          'image-root/usr/bin/vinix-sandbox'
		'rootfs/usr/sbin/vinix-account':         'assembled/stage/usr/sbin/vinix-account'
		'rootfs/usr/sbin/vinix-authd':           'assembled/stage/usr/sbin/vinix-authd'
		'rootfs/usr/sbin/vinix-system':          'assembled/stage/usr/sbin/vinix-system'
	} {
		if generated[name] != inputs[source] {
			return error('staged program differs from admitted input: ' + name)
		}
	}
	for name in ['packages-change', 'packages-launch', 'power-off'] {
		if generated['rootfs/usr/share/vinix/actions/' + name] != inputs['assembled/stage/source/tools/accounts/actions/' + name] {
			return error('staged account action differs from admitted source: ' + name)
		}
	}
	if generated['@link:rootfs/usr/bin/vinix-software'] != sha256.hexhash('/usr/bin/vinix-desktop') {
		return error('Software entry alias differs')
	}
	mut declared := map[string]string{}
	for name, hash in generated {
		if name.starts_with('rootfs/') && name != 'rootfs/usr/share/normal-init-software.json' {
			declared[name['rootfs'.len..]] = hash
		}
	}
	declared['@link:/usr/bin/vinix-software'] = '/usr/bin/vinix-desktop'
	if strings(run + '/rootfs/usr/share/normal-init-software.json')! != declared {
		return error('boot observer declaration differs from independently admitted programs')
	}
	if arch == 'aarch64' {
		if generated['rootfs/usr/sbin/vinix-volume'] != inputs['runtime/volume'] {
			return error('ARM boot-restore helper differs')
		}
	} else if generated['rootfs/sbin/init'] != inputs['source/build-support/init-amd64/desktop-init'] {
		return error('x86 production init script differs')
	}
	require_args(run, 'session-build/v.log.argv.json', host.v, ['-new-compiler', '-manualfree',
		'-o', recorded_run + '/session-build/session.c', root + '/tools/accounts/session.v'])!
	require_args(run, 'session-build/c.log.argv.json', '/opt/homebrew/bin/' + arch + '-linux-musl-gcc',
		['-static', recorded_run + '/session-build/session.c', '-o',
			recorded_run + '/session-build/vinix-session'])!
	require_args(run, 'observer-build/v.log.argv.json', host.v,
		['-manualfree', recorded_run + '/observer-build/observer.c', recorded_run + '/source/observer'])!
	require_args(run, 'observer-build/c.log.argv.json', cc, ['-static',
		recorded_run + '/observer-build/observer.c', recorded_run + '/observer-build/observer'])!
	if arch == 'aarch64' {
		require_args(run, 'init-build/v.log.argv.json', 'sh', [
			root + '/build-support/init-aarch64/compile-init',
			'desktop',
			recorded_run + '/init-build/init.c',
		])!
		require_args(run, 'init-build/c.log.argv.json', '/opt/homebrew/opt/llvm/bin/clang',
			['--target=aarch64-linux-none', '-ffreestanding', '-nostdlib', '-c',
				recorded_run + '/init-build/init.c', recorded_run + '/init-build/init.o'])!
		require_args(run, 'init-build/abi.log.argv.json', '/opt/homebrew/opt/llvm/bin/clang',
			['--target=aarch64-linux-none', '-c', root + '/build-support/init-aarch64/syscall_abi.S',
				recorded_run + '/init-build/abi.o'])!
		require_args(run, 'init-build/link.log.argv.json', '/opt/homebrew/bin/ld.lld',
			['aarch64elf', '--nostdlib', '-static', recorded_run + '/init-build/init.o',
				recorded_run + '/init-build/abi.o', recorded_run + '/init-build/init'])!
	} else {
		require_args(run, 'volume-build/v.log.argv.json', root + '/build-support/compile-v-module',
			[root + '/tools/volumes/volumecli', recorded_run + '/volume-build/volume.c', '--arch',
				'amd64'])!
		require_args(run, 'volume-build/c.log.argv.json', '/opt/homebrew/bin/x86_64-linux-musl-gcc',
			['-static', '-Werror', '-DVINIX_V_RUNTIME', root + '/tools/volumes/volumecli',
				recorded_run + '/volume-build/volume.c', recorded_run + '/volume-build/vinix-volume'])!
	}
	qualification := json2.decode[Qualification](os.read_file(run + '/qualification.json')!)!
	if qualification.architecture != arch || qualification.platform != 'production-init-installed-ordinary-software-two-boots'
		|| qualification.artifacts.len != qualification.artifact_paths.len {
		return error('requires matching passing qualification')
	}
	for name, path in qualification.artifact_paths {
		if name !in qualification.artifacts || normalproof.digest(recorded_path(path, recorded_run, run))! != qualification.artifacts[name] {
			return error('artifact digest differs: ' + name)
		}
	}
	for name, path in {
		'kernel':      kernel
		'controller':  controller
		'desktop':     desktop + '/vinix-desktop'
		'compiler':    host.v
		'qemu':        host.qemu
		'firmware':    host.firmware
		'initramfs':   run + '/initramfs.tar'
		'system-disk': run + '/system.vjfs'
		'declaration': run + '/rootfs/usr/share/normal-init-software.json'
		'qemu-argv':   run + '/qemu-argv.json'
	} {
		if qualification.artifact_paths[name] != os.real_path(recorded_path(path, run, recorded_run)) || qualification.artifacts[name] != normalproof.digest(path)! {
			return error('selected qualification artifact differs: ' + name)
		}
	}
	// An output-only rewrite plus a resealed qualification is insufficient:
	// every generated output must equal its independently recorded preboot input.
	for name, hash in generated {
		if name.starts_with('@link:') || name.starts_with('rootfs/') || name in [
			'initramfs',
			'boot.img',
		] {
			continue
		}
		key := if name.starts_with('repository/') {
			'rootfs/usr/share/vinix-packages/repositories/native/' + name.all_after('repository/')
		} else {
			name
		}
		if qualification.artifacts[key] != hash || qualification.artifact_paths[key] != os.real_path(generated_paths[name]) {
			return error('output differs from preboot generated input: ' + name)
		}
	}
	configuration := json2.decode[json2.Any](os.read_file(publisher + '/image-config.json')!)!.as_map()
	public_key := configuration['repositories']!.as_array()[0].as_map()['public_key']!.str()
	for boot in 1 .. 3 {
		serial_name := 'serial-' + boot.str() + '.log'
		shutdown_name := 'shutdown-' + boot.str() + '.jsonl'
		for name in [serial_name, shutdown_name] {
			if qualification.artifact_paths[name] != recorded_run + '/' + name {
				return error('missing required artifact: ' + name)
			}
		}
		serial(os.read_file(run + '/' + serial_name)!, boot, arch, public_key)!
		shutdown(run + '/' + shutdown_name, boot)!
	}
	mut actual_shots := os.ls(run)!.filter(it.ends_with('.png'))
	mut expected_shots := screenshots.clone()
	actual_shots.sort()
	expected_shots.sort()
	if actual_shots != expected_shots { return error('required screenshot inventory differs') }
	for name in screenshots {
		if qualification.artifact_paths[name] != recorded_run + '/' + name {
			return error('missing required screenshot digest: ' + name)
		}
		image_data := screenshotcore.read(run + '/' + name)!
		if image_data.width != 1024 || image_data.height != 768 {
			return error('screenshot dimensions differ: ' + name)
		}
		unsafe { image_data.pixels.free() }
	}
	qemu_args := read_arguments(run + '/qemu-argv.json')!
	if qemu_args.len < 2 || qemu_args[0] != host.qemu || '-nic' !in qemu_args || 'none' !in qemu_args {
		return error('QEMU arguments differ from admitted executable or offline scope')
	}
	mut expected_qemu := [host.qemu]
	expected_qemu << if arch == 'aarch64' {
		['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-device', 'ramfb',
			'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-m', '2048',
			'-smp', '2', '-drive', 'if=pflash,format=raw,readonly=on,file=' + host.firmware, '-drive',
			'if=pflash,format=raw,file=' + recorded_run + '/vars.fd', '-drive',
			'format=raw,file=' + recorded_run + '/boot.img']
	} else {
		['-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-vga', 'std', '-device',
			'qemu-xhci,id=gui-input', '-device', 'usb-kbd,bus=gui-input.0', '-device',
			'usb-tablet,bus=gui-input.0', '-m', '1024', '-smp', '2', '-drive',
			'if=pflash,format=raw,unit=0,readonly=on,file=' + host.firmware, '-cdrom',
			recorded_run + '/test.iso']
	}
	// The unique control socket name is runtime-specific; admit only its fixed
	// absolute prefix and exact matching dedicated power-observer endpoint.
	qmp_at := expected_qemu.len + 3
	if qemu_args.len <= qmp_at || !qemu_args[qmp_at].starts_with('unix:/tmp/vinix-normal-init-software-')
		|| !qemu_args[qmp_at].ends_with('.qmp,server=on,wait=off') {
		return error('QEMU control socket differs')
	}
	qmp := qemu_args[qmp_at]
	expected_qemu << ['-display', 'none', '-qmp', qmp, '-qmp', qmp.replace('.qmp,', '.qmp.power,'),
		'-no-reboot', '-nic', 'none']
	expected_qemu << if arch == 'aarch64' {
		['-drive',
			'if=none,id=system,format=raw,cache=writeback,file=' + recorded_run + '/system.vjfs',
			'-device', 'virtio-blk-device,drive=system']
	} else {
		['-drive', 'if=ide,format=raw,cache=writeback,file=' + recorded_run + '/system.vjfs']
	}
	if qemu_args != expected_qemu {
		return error('QEMU arguments differ from frozen production-init workflow')
	}
	// All refusal paths precede evidence directory creation.
	os.mkdir(output, mode: 0o700)!
	mut retained := map[string]string{}
	for name in ['qualification.json', 'source-inputs.json', 'source-paths.json',
		'verified-source-inputs.json', 'generated-inputs.json', 'generated-paths.json',
		'verified-generated-inputs.json', 'qemu-argv.json', 'serial-1.log', 'serial-2.log',
		'shutdown-1.jsonl', 'shutdown-2.jsonl', ...screenshots] {
		os.cp(run + '/' + name, output + '/' + name)!
		retained[name] = normalproof.digest(output + '/' + name)!
	}
	for name, path in effective_paths {
		if !(name.starts_with('source/') || name.starts_with('session-build/') || name.starts_with('observer-build/')
			|| name.starts_with('init-build/') || name.starts_with('volume-build/')) {
			continue
		}
		os.mkdir_all(os.dir(output + '/' + name))!
		os.cp(path, output + '/' + name)!
		retained[name] = normalproof.digest(output + '/' + name)!
	}
	retained['retainer-source'] = normalproof.digest(@FILE)!
	retained['retainer'] = normalproof.digest(os.executable())!
	os.write_file(output + '/retained.json', json2.encode(retained))!
	println('PASS ' + arch + ' production init installed Software retained ' + retained.len.str() + ' artifacts')
}

fn main() {
	retain() or {
		eprintln(err.msg())
		exit(1)
	}
}
