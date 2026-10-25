// SPDX-License-Identifier: GPL-2.0-or-later
// Verify and retain one completed ordinary-seat graphical run.
module main

import crypto.sha256
import json2
import os
import stbi
import tools.packages.pkgcore

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

fn release_routing_markers() []string {
	return ['SOFTWARE RELEASE ROUTING ordinary client uid=1000 home=/home/alex PASS',
		'SOFTWARE RELEASE ROUTING malformed extra-token enqueued PASS',
		'SOFTWARE RELEASE ROUTING malformed extra-token drained PASS',
		'SOFTWARE RELEASE ROUTING malformed action enqueued PASS',
		'SOFTWARE RELEASE ROUTING malformed action drained PASS',
		'SOFTWARE RELEASE ROUTING exact software.release-review acknowledged PASS']
}

fn admit_first_run_serial(transcript string, boot int, arch string, release_routing bool) ! {
	value := if release_routing { 'skip' } else { 'review' }
	decision := 'SOFTWARE FIRST RUN private decision owner=1000 mode=0600 value=' + value + ' PASS'
	exact_marker(transcript, decision)!
	if boot == 2 {
		exact_marker(transcript, 'SOFTWARE FIRST RUN BOOT 2 retained ' + value + ' decision no repeated prompt PASS')!
		if transcript.contains('SOFTWARE FIRST RUN pre-ready') || transcript.contains('SOFTWARE FIRST RUN PROPOSAL ') {
			return error('first-run prompt or proposal repeated on boot 2')
		}
		if release_routing && transcript.contains('SOFTWARE RELEASE ROUTING ') {
			return error('release-routing operation repeated on boot 2')
		}
		return
	}
	identity := 'SOFTWARE FIRST RUN pre-ready compositor uid=1000 home=/home/alex runtime=0700 PASS'
	unchanged := 'SOFTWARE FIRST RUN review handed to Software without activation or approval PASS'
	exact_marker(transcript, identity)!
	exact_marker(transcript, unchanged)!
	proposals := transcript.split_into_lines().filter(it.starts_with('SOFTWARE FIRST RUN PROPOSAL '))
	if proposals.len != 1 { return error('missing or duplicated complete first-run proposal') }
	review := json2.decode[json2.Any](proposals[0].all_after('SOFTWARE FIRST RUN PROPOSAL '))!.as_map()
	if review['operation']!.str() != 'deploy' || review['architecture']!.str() != arch ||
		review['generation']!.f64() != 0 || review['fingerprint']!.str().len != 64 ||
		review['names']!.as_array().map(it.str()) != ['org.vinix.counter'] ||
		review['requested']!.as_array().map(it.str()) != ['org.vinix.counter'] ||
		review['rows']!.as_array().len != 1 {
		return error('first-run proposal differs from the complete declared Counter set')
	}
	row := review['rows']!.as_array()[0].as_map()
	if row['id']!.str() != 'org.vinix.counter' || row['version']!.str() != '1.0.0' ||
		row['installed_version']!.str() != '' || row['architecture']!.str() != arch ||
		row['kind']!.str() != 'native' || row['repository']!.str() != 'native' ||
		row['license']!.str() != 'MIT' || row['public_key']!.str().len != 64 ||
		row['permissions']!.as_array().map(it.str()) != ['display'] ||
		row['requested']! != json2.Any(true) || row['action']!.str() != 'install' {
		return error('first-run proposal has incomplete publisher, permission or install details')
	}
	ready := transcript.index('SOFTWARE GRAPHICAL ordinary-compositor') or { return error('missing first-run ordinary ready identity') }
	approved := transcript.index('SOFTWARE GRAPHICAL INSTALLED reviewed-password-approved') or { return error('missing first-run approval result') }
	before := transcript.index(identity) or { return error('missing first-run pre-ready identity') }
	proposal := transcript.index(proposals[0]) or { return error('missing first-run proposal') }
	after := transcript.index(unchanged) or { return error('missing first-run unchanged-state gate') }
	if before >= ready || ready >= proposal || proposal >= after || after >= approved {
		return error('first-run identity, proposal and approval order differs')
	}
	if release_routing {
		mut previous := ready
		for marker in release_routing_markers() {
			exact_marker(transcript, marker)!
			position := transcript.index(marker) or { return error('missing release-routing marker') }
			if position <= previous || position >= proposal {
				return error('release-routing client, refusal and proposal order differs')
			}
			previous = position
		}
	}
}

fn admit_serial(path string, installed bool, first_run bool, release_routing bool, boot int, arch string) ! {
	transcript := os.read_file(path)!
	mut forbidden := ['SOFTWARE GRAPHICAL FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION']
	if installed { forbidden << ['sysdisk: running from memory', 'sysdisk: updating the system on'] }
	for marker in forbidden {
		if transcript.contains(marker) { return error('forbidden serial marker: ' + marker) }
	}
	exact_marker(transcript, 'SOFTWARE GRAPHICAL ordinary-compositor uid=1000 home=/home/alex PASS')!
	if first_run { admit_first_run_serial(transcript, boot, arch, release_routing)! }
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

fn hex_digest(value json2.Any) bool {
	if value !is string || value.str().len != 64 { return false }
	for byte in value.str().bytes() {
		if (byte < `0` || byte > `9`) && (byte < `a` || byte > `f`) { return false }
	}
	return true
}

fn admit_release_routing_declaration(declaration map[string]json2.Any, arch string, transcript string) ! {
	message := 'release-routing declaration differs from the exact architecture-matched Counter lock'
	if declaration.len != 4 || (declaration['format'] or { json2.Any(0) }) != json2.Any(f64(2)) ||
		(declaration['architecture'] or { json2.Any('') }) != json2.Any(arch) ||
		(declaration['packages'] or { json2.Any([]json2.Any{}) }) != json2.Any([json2.Any('org.vinix.counter')]) {
		return error(message)
	}
	locked := declaration['locked'] or { return error(message) }
	if locked !is []json2.Any || locked.as_array().len != 1 { return error(message) }
	entry := locked.as_array()[0]
	if entry !is map[string]json2.Any { return error(message) }
	pin := entry.as_map()
	sequence := pin['minimum_sequence'] or { return error(message) }
	key := pin['public_key'] or { return error(message) }
	metadata := pin['metadata_sha256'] or { return error(message) }
	if pin.len != 7 || (pin['id'] or { json2.Any('') }) != json2.Any('org.vinix.counter') ||
		(pin['version'] or { json2.Any('') }) != json2.Any('1.0.0') ||
		(pin['architecture'] or { json2.Any('') }) != json2.Any(arch) ||
		(pin['repository'] or { json2.Any('') }) != json2.Any('native') ||
		!hex_digest(key) || !hex_digest(metadata) || sequence !is f64 ||
		sequence.f64() <= 0 || sequence.f64() > 9007199254740991.0 ||
		sequence.f64() != f64(u64(sequence.f64())) {
		return error(message)
	}
	proposal := transcript.split_into_lines().filter(it.starts_with('SOFTWARE FIRST RUN PROPOSAL '))[0]
	review := json2.decode[json2.Any](proposal.all_after('SOFTWARE FIRST RUN PROPOSAL '))!.as_map()
	row := review['rows']!.as_array()[0].as_map()
	if key != row['public_key']! { return error(message) }
}

fn admit_release_routing_repository(run string, arch string) ! {
	message := 'release-routing declaration differs from the exact architecture-matched Counter lock'
	declaration := json2.decode[json2.Any](os.read_file(run + '/rootfs/usr/share/vinix-packages/applications.json')!)!.as_map()
	pin := declaration['locked']!.as_array()[0].as_map()
	config := pkgcore.load_config(run + '/rootfs')!
	repositories := config.repositories.filter(it.id == 'native')
	if config.architecture != arch || repositories.len != 1 ||
		repositories[0].public_key != pin['public_key']!.str() { return error(message) }
	repository := run + '/rootfs/usr/share/vinix-packages/repositories/native'
	// Runtime expiry was enforced by the qualified refresh. Verify archived
	// signed bytes at epoch zero so the retained proof survives later expiry.
	index := pkgcore.verify_index(repositories[0], os.read_file(repository + '/index.json')!,
		os.read_file(repository + '/index.sig')!, 0)!
	packages := index.packages.filter(it.id == 'org.vinix.counter' && it.architecture == arch)
	if index.sequence != u64(pin['minimum_sequence']!.f64()) || packages.len != 1 ||
		packages[0].version != '1.0.0' ||
		pkgcore.package_metadata_digest(packages[0])! != pin['metadata_sha256']!.str() {
		return error(message)
	}
}

fn admit_release_routing_controls(run string) ! {
	message := 'release-routing malformed-action controls differ'
	controls := json2.decode[json2.Any](os.read_file(run + '/release-routing-controls.json')!)!.as_map()
	if controls.len != 4 || (controls['format'] or { json2.Any(0) }) != json2.Any(f64(1)) ||
		(controls['malformed_extra_token'] or { json2.Any('') }) != json2.Any('no Software window') ||
		(controls['malformed_action'] or { json2.Any('') }) != json2.Any('no Software window') ||
		(controls['unchanged_region'] or { json2.Any([]json2.Any{}) }) !=
		json2.Any([json2.Any(f64(0)), json2.Any(f64(70)), json2.Any(f64(1024)), json2.Any(f64(620))]) {
		return error(message)
	}
	before := stbi.load(run + '/release-routing-01-desktop.png', desired_channels: 3)!
	defer { before.free() }
	if before.width != 1024 || before.height != 768 { return error('release-routing framebuffer dimensions differ') }
	for name in ['release-routing-02-extra-refused', 'release-routing-03-action-refused'] {
		after := stbi.load(run + '/' + name + '.png', desired_channels: 3)!
		defer { after.free() }
		if after.width != 1024 || after.height != 768 { return error('release-routing framebuffer dimensions differ') }
		for y in 70 .. 690 {
			for x in 0 .. 1024 {
				position := (y * 1024 + x) * 3
				for channel in 0 .. 3 {
					if unsafe { before.data[position + channel] != after.data[position + channel] } {
						return error('release-routing malformed action changed the desktop: ' + name)
					}
				}
			}
		}
	}
	for name in ['release-routing-02-extra-barrier', 'release-routing-03-action-barrier'] {
		barrier := stbi.load(run + '/' + name + '.png', desired_channels: 3)!
		defer { barrier.free() }
		if barrier.width != 1024 || barrier.height != 768 { return error('release-routing framebuffer dimensions differ') }
		mut changed := 0
		for y in 90 .. 540 {
			for x in 140 .. 790 {
				position := (y * 1024 + x) * 3
				if unsafe { before.data[position] != barrier.data[position] ||
					before.data[position + 1] != barrier.data[position + 1] ||
					before.data[position + 2] != barrier.data[position + 2] } { changed++ }
			}
		}
		if changed <= 100 { return error('release-routing FIFO barrier dialog is not visible: ' + name) }
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
		'qemu-framebuffer-ordinary-seat-installed-root-two-boots',
		'qemu-framebuffer-ordinary-seat-first-run-installed-root-two-boots',
		'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots'] {
		return error('requires the selected architecture ordinary-seat receipt')
	}
	for name, expected in {
		'software-graphical-check.v': $embed_file('software-graphical-check.v').to_string()
		'software-graphical-build.v': $embed_file('software-graphical-build.v').to_string()
		'guest/main.v': $embed_file('software-graphical-guest/main.v').to_string()
		'guest/installed.v': $embed_file('software-graphical-guest/installed.v').to_string()
		'guest/first_run.v': $embed_file('software-graphical-guest/first_run.v').to_string()
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
	release_routing := receipt.platform == 'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots'
	first_run := release_routing || receipt.platform == 'qemu-framebuffer-ordinary-seat-first-run-installed-root-two-boots'
	if release_routing && digest(run + '/source/guest/release_routing.v')! !=
		sha256.sum($embed_file('software-graphical-guest/release_routing.v').to_string().bytes()).hex() {
		return error('qualified graphical fixture differs from the embedded source: guest/release_routing.v')
	}
	admit_serial(run + '/serial.log', installed, first_run, release_routing, 1, arch)!
	if installed {
		admit_serial(run + '/serial-2.log', true, first_run, release_routing, 2, arch)!
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
	if first_run {
		paths['release-declaration'] = run + '/rootfs/usr/share/vinix-packages/applications.json'
		declaration := json2.decode[json2.Any](os.read_file(paths['release-declaration'])!)!.as_map()
		if release_routing {
			admit_release_routing_declaration(declaration, arch, os.read_file(run + '/serial.log')!)!
		} else if declaration.len != 3 || declaration['format']! != json2.Any(f64(1)) ||
			declaration['architecture']!.str() != arch ||
			declaration['packages']!.as_array().map(it.str()) != ['org.vinix.counter'] {
			return error('first-run declaration differs from the complete architecture-matched Counter set')
		}
	}
	if release_routing { paths['release-routing-controls'] = run + '/release-routing-controls.json' }
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
	if first_run { required_shots << ['first-run-01-card', 'first-run-02-proposal', 'first-run-03-reboot-desktop'] }
	if release_routing {
		required_shots << ['release-routing-01-desktop', 'release-routing-02-extra-refused',
			'release-routing-03-action-refused', 'release-routing-02-extra-barrier',
			'release-routing-03-action-barrier']
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
	if release_routing {
		admit_release_routing_repository(run, arch)!
		admit_release_routing_controls(run)!
	}
	if receipt.artifacts['desktop-build-original'] != receipt.artifacts['desktop-build'] {
		return error('original desktop build manifest differs from run copy')
	}
	manifest := json2.decode[map[string]string](os.read_file(build + '/desktop-build.json')!)!
	if manifest['vinix-desktop'] != receipt.artifacts['desktop'] {
		return error('desktop receipt does not bind the qualified executable')
	}
	mut source_names := ['main.v', 'terminal.v', 'platform.c.v', 'registration.v', 'registration_store.v', 'gpucore/core.v',
		'sessionruntime/runtime.c.v', 'sessionipc/client.c.v', 'windowfb/transport.c.v']
	if first_run {
		source_names << ['app_selection.v', 'app_selection_release.v', 'software_release.v', 'software_app.v']
	}
	if release_routing {
		source_names << ['app_selection_migration.v', 'session_hub.v', 'packagecore/release.c.v',
			'session_dialog.v', 'sessiondaemon/dispatch.v', 'sessiondaemon/broker.c.v',
			'sessioncore/selectors.v']
	}
	for name in source_names {
		if digest('desktop/' + name)! != manifest['desktop/' + name] ||
			digest(build + '/source/desktop/' + name)! != manifest['desktop/' + name] {
			return error('qualified desktop identity source differs: ' + name)
		}
	}
	os.mkdir_all(out)!
	prefix := out + if release_routing { '/software-release-routing-native-' + arch } else if first_run {
		'/software-first-run-native-' + arch
	} else { '/software-graphical-' + arch }
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
	if release_routing {
		os.cp(run + '/release-routing-controls.json', prefix + '.release-routing-controls.json')!
	}
	for name in shots { os.cp(run + '/' + name + '.png', prefix + '.' + name + '.png')! }
	println('SOFTWARE GRAPHICAL RETAIN PASS ' + arch + ': ' + receipt.artifacts.len.str() +
		' artifact digests and ' + source_names.len.str() + ' current desktop identity/seat/runtime/release sources match')
}
