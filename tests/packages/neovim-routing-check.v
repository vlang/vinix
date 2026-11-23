// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only native acquisition from a production desktop staging root.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import strconv

const desktop_files = [
	'usr/bin/vinix-desktop',
	'usr/bin/vinix-session',
	'usr/bin/vinix-package',
	'usr/sbin/vinix-account',
	'usr/sbin/vinix-authd',
	'usr/sbin/vinix-session',
	'usr/share/vinix/actions/packages-change',
]
const fixture_password = 'test-only password'
const approved_install = 'HWTEST PASS approved Software generation verified and Neovim launched as uid 1000'
const mixed_catalog_launches = 'HWTEST PASS approved mixed catalog ran native SDK, SQLite, FFmpeg and FFprobe'

fn parse_options(values []string) !map[string]string {
	required := ['--arch', '--kernel', '--staging', '--config', '--deployment', '--bundle', '--out']
	plain := ['--arch', '--approve', '--memory-mib', '--mixed-catalog']
	mut options := map[string]string{}
	for argument in values {
		name := argument.all_before('=')
		value := argument.all_after('=')
		if (name !in required && name !in plain)
			|| !argument.contains('=') || value == '' || name in options {
			return error('expected distinct --arch, --kernel, --staging, --config, --deployment, --bundle, --out and optional --approve, --memory-mib and --mixed-catalog options')
		}
		options[name] = if name in plain { value } else { os.abs_path(value) }
	}
	if !required.all(it in options) || options['--arch'] !in ['aarch64', 'x86_64'] {
		return error('missing inputs or unsupported architecture')
	}
	if (options['--approve'] or { 'false' }) !in ['true', 'false'] {
		return error('--approve must be true or false')
	}
	if (options['--mixed-catalog'] or { 'false' }) !in ['true', 'false'] {
		return error('--mixed-catalog must be true or false')
	}
	if options['--mixed-catalog'] == 'true' && options['--approve'] != 'true' {
		return error('--mixed-catalog requires --approve=true')
	}
	return options
}

fn digest(path string) !string {
	bytes := os.read_file(path)!
	defer { unsafe { bytes.free() } }
	return sha256.hexhash(bytes)
}

fn copy_pinned(source string, target string, mut inputs map[string]string) ! {
	if !os.is_file(source) || os.is_link(source) { return error('expected a regular test input: ' + source) }
	inputs[source] = digest(source)!
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
	if digest(target)! != inputs[source] { return error('test input changed during capture: ' + source) }
}

fn take_picture(marker string, name string, delay int) hwhost.Action {
	return hwhost.Action{
		after: marker
		delay_ms: delay
		qmp: '{"execute":"screendump","arguments":{"filename":"{state}/' + name + '"}}'
		answer_lacks: '"error"'
	}
}

fn approval_action(step string, command string, arguments string) hwhost.Action {
	return hwhost.Action{
		after: 'HWTEST INFO approval ' + step
		qmp: '{"execute":"' + command + '","arguments":' + arguments + '}'
		answer_lacks: '"error"'
	}
}

fn approval_actions() []hwhost.Action {
	// Confirm in the 1024x768 Software proposal. Press and release are
	// separate so both USB and VirtIO HID devices observe the click.
	x := 463 * 32767 / 1024
	y := 612 * 32767 / 768
	mut actions := [
		approval_action('pointer', 'input-send-event', '{"events":[{"type":"abs","data":{"axis":"x","value":${x}}},{"type":"abs","data":{"axis":"y","value":${y}}}]}'),
		approval_action('press', 'input-send-event', '{"events":[{"type":"btn","data":{"button":"left","down":true}}]}'),
		approval_action('release', 'input-send-event', '{"events":[{"type":"btn","data":{"button":"left","down":false}}]}'),
		take_picture('HWTEST INFO approval prompt', 'approval.ppm', 0),
	]
	for index, byte in fixture_password.bytes() {
		key := match byte {
			` ` { 'spc' }
			`-` { 'minus' }
			else { byte.ascii_str() }
		}
		actions << approval_action('key ${index}.', 'human-monitor-command',
			'{"command-line":"sendkey ${key} 100"}')
	}
	actions << take_picture('HWTEST INFO approval masked without activation PASS', 'masked.ppm', 0)
	actions << approval_action('submit', 'human-monitor-command', '{"command-line":"sendkey ret 100"}')
	actions << take_picture('HWTEST INFO approval response', 'response.ppm', 1000)
	return actions
}

fn changed_pixels(before hwhost.Picture, next hwhost.Picture) !int {
	if before.width != 1024 || before.height != 768 || before.width != next.width || before.height != next.height {
		return error('requires the expected 1024 by 768 desktop framebuffer')
	}
	mut count := 0
	// The title bar and review body lie in the desktop work area. Exclude the
	// clock and task bar from the comparison.
	for y in 70 .. 690 {
		for x in 0 .. before.width {
			at := (y * before.width + x) * 3
			if before.pixels[at..at + 3] != next.pixels[at..at + 3] { count++ }
		}
	}
	return count
}

fn check() ! {
	$if prod {} $else { return error('build the routing controller with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('neovim-routing-check.v').to_string()) {
		return error('routing controller source changed after compilation')
	}
	options := parse_options(os.args[1..])!
	arch := options['--arch']
	approve := options['--approve'] == 'true'
	mixed_catalog := options['--mixed-catalog'] == 'true'
	memory_option := options['--memory-mib'] or { if approve { '2048' } else { '1024' } }
	memory_mib := strconv.atoi(memory_option) or { return error('--memory-mib must be a positive integer') }
	if memory_mib < 1 { return error('--memory-mib must be a positive integer') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	work := options['--out']
	if os.exists(work) { return error('output directory must be new') }
	os.mkdir_all(work)!
	os.setenv('VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)

	boot := work + '/boot'
	target := boot + '/rootfs'
	mut inputs := map[string]string{}
	for path in [os.executable(), @FILE, options['--kernel'], host.qemu, host.v, host.firmware] { inputs[path] = digest(path)! }
	cross_compiler := if arch == 'aarch64' { os.getenv_opt('CC_AARCH64') or { 'clang' } }
		else { os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' } }
	for tool in [cross_compiler, 'tar'] {
		path := os.find_abs_path_of_executable(tool)!
		inputs[path] = digest(path)!
	}
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	if arch == 'x86_64' {
		for _, path in plainiso.inputs(root)! { inputs[path] = digest(path)! }
	} else {
		loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') }
		for path in [loader, root + '/build-support/limine.conf'] { inputs[path] = digest(path)! }
		for tool in ['mformat', 'mmd', 'mcopy'] {
			path := os.find_abs_path_of_executable(tool)!
			inputs[path] = digest(path)!
		}
	}
	guest_source := work + '/source/main.v'
	copy_pinned(root + '/tests/packages/neovim-routing-guest/main.v', guest_source, mut inputs)!
	guest := hwhost.build_program_with_flags(host, guest_source, work + '/guest-build', 'init', ['.'],
		['-backend', 'c', '-prod', '-manualfree', '-enable-globals'])!

	for name in desktop_files { copy_pinned(options['--staging'] + '/' + name, target + '/' + name, mut inputs)! }
	software := options['--staging'] + '/usr/bin/vinix-software'
	software_target := os.readlink(software)!
	if software_target != '/usr/bin/vinix-desktop' { return error('expected the released Software launcher alias') }
	os.symlink(software_target, target + '/usr/bin/vinix-software')!
	copy_pinned(options['--config'], target + '/etc/vinix-packages/config.json', mut inputs)!
	copy_pinned(options['--deployment'], target + '/usr/share/vinix-packages/applications.json', mut inputs)!
	config := json2.decode[json2.Any](os.read_file(options['--config'])!)!.as_map()
	repositories := config['repositories']!.as_array()
	if config['architecture']!.str() != arch || config['launch_user']!.str() != 'alex' || repositories.len != 1
		|| config['policy']!.as_map()['offline']! != json2.Any(true) {
		return error('expected a reviewed offline image configuration for the target and account')
	}
	repository := repositories[0].as_map()['id']!.str()
	if repository == '' || !repository.replace('-', '').replace('_', '').bytes().all(it.is_alnum()) {
		return error('invalid fixture repository identifier')
	}
	destination := target + '/usr/share/vinix-packages/repositories/' + repository
	bundle := options['--bundle']
	for name in ['index.json', 'index.sig'] { copy_pinned(bundle + '/' + name, destination + '/' + name, mut inputs)! }
	for object in os.ls(bundle + '/objects')! {
		if object.len != 64 || !object.bytes().all(it in '0123456789abcdef'.bytes()) { return error('invalid fixture object name') }
		copy_pinned(bundle + '/objects/' + object, destination + '/objects/' + object, mut inputs)!
	}
	os.chmod(target + '/usr/share/vinix-packages/applications.json', 0o644)!
	os.mkdir_all(target + '/etc/vinix')!
	os.write_file(target + '/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
	os.write_file(target + '/etc/group', 'root:x:0:\n')!
	os.write_file(target + '/etc/shadow', 'root:!:0:0:99999:7:::\n')!
	os.chmod(target + '/etc/shadow', 0o600)!
	os.write_file(target + '/etc/vinix/auth.conf', 'scrypt_ln = 10\nscrypt_p = 1\n')!
	if approve {
		copy_pinned(options['--staging'] + '/usr/bin/vinix-sandbox',
			target + '/usr/bin/vinix-sandbox', mut inputs)!
		os.write_file(target + '/etc/neovim-routing-approval', fixture_password)!
	}
	if mixed_catalog { os.write_file(target + '/etc/neovim-routing-mixed-catalog', '')! }

	os.cp(guest, target + '/usr/bin/pkg')!
	os.chmod(target + '/usr/bin/pkg', 0o755)!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!

	before := 'HWTEST INFO ordinary desktop before Neovim setup'
	invalid := 'HWTEST INFO invalid declaration refused without fallback PASS'
	review := 'HWTEST INFO exact setup command requested signed Neovim review PASS'
	mut required := ['HWTEST INFO absent declaration called legacy installer as uid 1000 PASS', before, invalid, review,
		'HWTEST PASS Neovim graphical routing without activation or approval']
	mut actions := [take_picture(before, 'desktop.ppm', 0), take_picture(invalid, 'invalid.ppm', 0),
		take_picture(review, 'proposal.ppm', 3000)]
	mut screens := [hwhost.Screen{file: 'desktop.ppm'}, hwhost.Screen{file: 'invalid.ppm', like: 'desktop.ppm'},
		hwhost.Screen{file: 'proposal.ppm', like: 'desktop.ppm'}]
	if approve {
		required << approved_install
		actions << approval_actions()
		for file in ['approval.ppm', 'masked.ppm', 'response.ppm'] {
			screens << hwhost.Screen{file: file, like: 'proposal.ppm'}
		}
	}
	if mixed_catalog { required << mixed_catalog_launches }
	scenario := hwhost.Scenario{
		name: 'Neovim graphical routing'
		arches: [arch]
		qemu: ['-nic', 'none']
		qemu_x86_64: ['-vga', 'std', '-device', 'qemu-xhci,id=gui-input', '-device', 'usb-kbd,bus=gui-input.0',
			'-device', 'usb-tablet,bus=gui-input.0']
		required: required
		forbidden: ['HWTEST FAIL', 'Kernel panic', 'cannot start Software']
		actions: actions
		screens: screens
		ending: .running
	}
	runtime_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{kernel: options['--kernel'], guest: guest,
		state: boot, timeout: 300, memory_mib: memory_mib, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' { return error(outcome.reason) }
	for path, expected in inputs {
		if digest(path)! != expected { return error('test input changed: ' + path) }
	}
	if os.readlink(software)! != software_target { return error('Software launcher changed during qualification') }
	desktop := hwhost.read_picture(os.read_bytes(boot + '/desktop.ppm')!)!
	refused := hwhost.read_picture(os.read_bytes(boot + '/invalid.ppm')!)!
	proposal := hwhost.read_picture(os.read_bytes(boot + '/proposal.ppm')!)!
	refused_changes := changed_pixels(desktop, refused)!
	proposal_changes := changed_pixels(refused, proposal)!
	if refused_changes > 1000 || proposal_changes < 5000 {
		return error('unexpected desktop change after refusal or review: ${refused_changes} / ${proposal_changes} pixels')
	}
	os.write_file(work + '/pixels.json', json2.encode({'invalid_changed': refused_changes,
		'proposal_changed': proposal_changes}) + '\n')!
	println(if approve { 'NEOVIM GRAPHICAL APPROVAL PASS ' + arch } else { 'NEOVIM GRAPHICAL ROUTING PASS ' + arch })
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
