// SPDX-License-Identifier: GPL-2.0-or-later
// Verify and retain one completed ordinary-seat graphical run.
module main

import crypto.sha256
import json2
import os
import stbi
import tools.packages.pkgcore
import tools.packages.pkgprotocol

struct Receipt {
	architecture string
	platform string
	artifacts map[string]string
	artifact_paths map[string]string
}

const targeted_platform = 'qemu-framebuffer-production-login-targeted-refresh-installed-root-two-boots'
const targeted_shots = ['targeted-01-repositories', 'targeted-02-selected', 'targeted-03-policy',
	'targeted-04-offline', 'targeted-05-administrator', 'targeted-06-password-mask',
	'targeted-07-complete', 'targeted-08-catalog']!

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

fn admit_first_run_serial(transcript string, boot int, arch string, release_routing bool, refresh bool, staged bool) ! {
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
		if refresh && transcript.contains('SOFTWARE FIRST RUN REFRESH ') {
			return error('first-run refresh repeated on boot 2')
		}
		return
	}
	identity := 'SOFTWARE FIRST RUN pre-ready compositor uid=1000 home=/home/alex runtime=0700 PASS'
	unchanged := if refresh { 'SOFTWARE FIRST RUN REFRESH authenticated catalog and read-only proposal before activation PASS' }
		else { 'SOFTWARE FIRST RUN review handed to Software without activation or approval PASS' }
	exact_marker(transcript, identity)!
	exact_marker(transcript, unchanged)!
	proposals := transcript.split_into_lines().filter(it.starts_with('SOFTWARE FIRST RUN PROPOSAL '))
	if proposals.len != 1 { return error('missing or duplicated complete first-run proposal') }
	review := json2.decode[json2.Any](proposals[0].all_after('SOFTWARE FIRST RUN PROPOSAL '))!.as_map()
	expected := if staged { ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello'] }
		else { ['org.vinix.counter'] }
	rows := review['rows']!.as_array()
	if review['operation']!.str() != 'deploy' || review['architecture']!.str() != arch ||
		review['generation']!.f64() != 0 || review['fingerprint']!.str().len != 64 ||
		review['names']!.as_array().map(it.str()) != expected ||
		review['requested']!.as_array().map(it.str()) != expected || rows.len != expected.len {
		if staged { return error('first-run proposal differs from the complete staged catalog') }
		return error('first-run proposal differs from the complete declared Counter set')
	}
	for i, row_value in rows {
		row := row_value.as_map()
		permissions := if expected[i] == 'org.vinix.package-hello' { ['files'] } else { ['display'] }
		if row['id']!.str() != expected[i] || row['version']!.str() != '1.0.0' ||
			row['installed_version']!.str() != '' || row['architecture']!.str() != arch ||
			row['kind']!.str() != 'native' || row['repository']!.str() != 'native' ||
			row['license']!.str() != 'MIT' || row['public_key']!.str().len != 64 ||
			row['permissions']!.as_array().map(it.str()) != permissions ||
			row['requested']! != json2.Any(true) || row['action']!.str() != 'install' {
			return error('first-run proposal has incomplete publisher, permission or install details')
		}
	}
	ready := transcript.index('SOFTWARE GRAPHICAL ordinary-compositor') or { return error('missing first-run ordinary ready identity') }
	approved := transcript.index('SOFTWARE GRAPHICAL INSTALLED reviewed-password-approved') or { return error('missing first-run approval result') }
	before := transcript.index(identity) or { return error('missing first-run pre-ready identity') }
	proposal := transcript.index(proposals[0]) or { return error('missing first-run proposal') }
	after := transcript.index(unchanged) or { return error('missing first-run unchanged-state gate') }
	if before >= ready || ready >= proposal || proposal >= after || after >= approved {
		return error('first-run identity, proposal and approval order differs')
	}
	if refresh {
		cold := 'SOFTWARE FIRST RUN REFRESH no cached catalog or prior package approval PASS'
		separate := 'SOFTWARE FIRST RUN REFRESH separate catalog and installation approvals PASS'
		exact_marker(transcript, cold)!
		exact_marker(transcript, separate)!
		cold_at := transcript.index(cold) or { return error('missing first-run cold catalog marker') }
		separate_at := transcript.index(separate) or { return error('missing separate approval marker') }
		if cold_at <= ready || cold_at >= proposal || separate_at <= after || separate_at >= approved {
			return error('first-run catalog refresh and installation approval order differs')
		}
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

fn admit_serial(path string, installed bool, first_run bool, release_routing bool, refresh bool, staged bool, boot int, arch string) ! {
	transcript := os.read_file(path)!
	mut forbidden := ['SOFTWARE GRAPHICAL FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION']
	if installed { forbidden << ['sysdisk: running from memory', 'sysdisk: updating the system on'] }
	for marker in forbidden {
		if transcript.contains(marker) { return error('forbidden serial marker: ' + marker) }
	}
	exact_marker(transcript, 'SOFTWARE GRAPHICAL ordinary-compositor uid=1000 home=/home/alex PASS')!
	if first_run { admit_first_run_serial(transcript, boot, arch, release_routing, refresh, staged)! }
	if installed { exact_marker(transcript, 'SOFTWARE GRAPHICAL native Counter launch child closed PASS')! }
	if installed && arch == 'aarch64' { exact_marker(transcript, 'syspower: power off: stopping devices')! }
	if boot == 1 {
		exact_marker(transcript, 'SOFTWARE GRAPHICAL ordinary-counter two-pointer-events persisted uid=1000 PASS')!
		if installed {
			exact_marker(transcript, if staged { 'SOFTWARE GRAPHICAL INSTALLED reviewed-password-approved exact staged apps install PASS' }
				else { 'SOFTWARE GRAPHICAL INSTALLED reviewed-password-approved exact Counter install PASS' })!
			exact_marker(transcript, 'SOFTWARE GRAPHICAL INSTALLED BOOT 1 acquired pointer-saved cold-boot checkpoint PASS')!
		}
	} else {
		exact_marker(transcript, 'SOFTWARE GRAPHICAL INSTALLED BOOT 2 retained Counter reopened and pointer-saved PASS')!
	}
}

fn admit_staged_audit(transcript string, arch string, lock_digest string, expected []string) !u64 {
	prefix := 'SOFTWARE FIRST RUN STAGED AUDIT '
	lines := transcript.split_into_lines().filter(it.starts_with(prefix))
	if lines.len != 1 { return error('missing or duplicated exact staged deployment audit') }
	mut audit := pkgprotocol.decode_deployment_audit(lines[0].all_after(prefix).trim_right('\r'))!
	defer { audit.close() }
	if audit.architecture != arch || audit.generation == 0 || audit.deployment_sha256 != lock_digest ||
		!audit.matches || audit.rows.map(it.id) != expected ||
		audit.rows.any(it.status != 'match' || it.installed_version != '1.0.0') {
		return error('staged deployment audit differs from the retained image lock')
	}
	return audit.generation
}

fn admit_staged_catalog(run string, receipt Receipt, mut paths map[string]string) ! {
	lock_digest := receipt.artifacts['release-declaration'] or { return error('missing staged lock receipt') }
	mode := '/etc/software-graphical-staged-catalog'
	paths['staged-catalog-mode'] = run + '/rootfs' + mode
	proof := json2.decode[map[string]string](os.read_file(paths['installed-declaration'])!)!
	original := receipt.artifact_paths['staged-lock-original'] or { return error('missing original staged lock path') }
	if lock_digest != receipt.artifacts['staged-lock-original'] || original == os.real_path(paths['release-declaration']) ||
		proof[pkgprotocol.image_applications_path] != lock_digest ||
		proof[mode] != receipt.artifacts['staged-catalog-mode'] ||
		os.read_file(paths['staged-catalog-mode'])! != '1\n' {
		return error('staged application lock differs from the admitted image bytes')
	}
	mut document := pkgprotocol.decode_deployment_document(os.read_file(paths['release-declaration'])!)!
	defer { document.close() }
	expected := ['org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']
	if document.format != 2 || document.architecture != receipt.architecture || document.packages != expected ||
		document.locked.map(it.id) != expected {
		return error('staged catalog does not declare the complete native SDK set')
	}
	config := pkgcore.load_config(run + '/rootfs')!
	if config.repositories.len != (if receipt.platform == targeted_platform { 2 } else { 1 }) ||
		config.repositories[0].id != 'native' {
		return error('staged catalog requires the native publisher')
	}
	repository := config.repositories[0]
	base := run + '/rootfs' + pkgcore.image_repositories_path + '/native'
	// Runtime expiry was checked during refresh. Retained signed bytes can be
	// independently verified after expiry.
	index := pkgcore.verify_index(repository, os.read_file(base + '/index.json')!,
		os.read_file(base + '/index.sig')!, 0)!
	serial := os.read_file(run + '/serial.log')!
	prefix := 'SOFTWARE FIRST RUN PROPOSAL '
	proposal := serial.split_into_lines().filter(it.starts_with(prefix))[0]
	review := json2.decode[json2.Any](proposal.all_after(prefix))!.as_map()
	rows := review['rows']!.as_array()
	for i, pin in document.locked {
		if pin.architecture != receipt.architecture || pin.version != '1.0.0' ||
			pin.repository != repository.id || pin.minimum_sequence != index.sequence ||
			pin.public_key != repository.public_key || rows[i].as_map()['public_key']!.str() != pin.public_key {
			return error('staged catalog publisher or release identity differs from the bundled index')
		}
		matches := index.packages.filter(it.id == pin.id && it.architecture == pin.architecture && it.version == pin.version)
		if matches.len != 1 || pkgcore.package_metadata_digest(matches[0])! != pin.metadata_sha256 {
			return error('staged catalog pin differs from the bundled package metadata')
		}
	}
	generation := admit_staged_audit(serial, receipt.architecture, lock_digest, expected)!
	reopened := admit_staged_audit(os.read_file(run + '/serial-2.log')!, receipt.architecture, lock_digest, expected)!
	if generation != reopened { return error('staged catalog generation changed across cold boot') }
}

fn targeted_trace(serial string, prefix string) !map[string]string {
	lines := serial.split_into_lines().filter(it.starts_with(prefix))
	if lines.len != 1 { return error('missing or duplicated targeted refresh observation: ' + prefix.trim_space()) }
	observed := json2.decode[map[string]string](lines[0].all_after(prefix).trim_right('\r'))!
	if observed.len != 10 { return error('targeted refresh observation has the wrong fields') }
	for name in ['config', 'lock', 'state', 'catalog', 'history', 'native-index', 'native-signature',
		'field-index', 'field-signature']! {
		value := observed[name]!
		if value.len != 64 || !value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
			return error('targeted refresh observation has an invalid digest: ' + name)
		}
	}
	if (observed['current']!).len == 0 { return error('targeted refresh observation has no active generation') }
	return observed
}

fn admit_targeted_refresh(run string, receipt Receipt, mut paths map[string]string) ! {
	mode := '/etc/software-graphical-targeted-refresh'
	paths['targeted-refresh-mode'] = run + '/rootfs' + mode
	proof := json2.decode[map[string]string](os.read_file(paths['installed-declaration'])!)!
	if os.read_file(paths['targeted-refresh-mode'])! != '1\n' ||
		proof[mode] != receipt.artifacts['targeted-refresh-mode'] {
		return error('targeted refresh mode differs from the admitted image')
	}
	config := pkgcore.load_config(run + '/rootfs')!
	field := config.repositories[1]
	if field.id != 'field' || field.url != 'file://' + pkgcore.image_repositories_path + '/field' {
		return error('targeted refresh requires the enrolled local field repository')
	}
	serial := os.read_file(run + '/serial.log')!
	cold := os.read_file(run + '/serial-2.log')!
	ready := 'SOFTWARE TARGETED REFRESH isolated field release READY'
	done := 'SOFTWARE TARGETED REFRESH single approval kept HTTPS snapshot and generation PASS'
	retained := 'SOFTWARE TARGETED REFRESH new field catalog and trust survived cold boot PASS'
	exact_marker(serial, ready)!
	exact_marker(serial, done)!
	exact_marker(cold, retained)!
	mut previous := -1
	for marker in ['SOFTWARE GRAPHICAL INSTALLED reviewed-password-approved exact staged apps install PASS',
		ready, 'SOFTWARE TARGETED BEFORE ', 'SOFTWARE TARGETED AFTER ', done, 'SOFTWARE GRAPHICAL ordinary-counter']! {
		position := serial.index(marker) or { return error('missing targeted refresh marker: ' + marker) }
		if position <= previous { return error('targeted refresh markers are out of order') }
		previous = position
	}
	if cold.contains(ready) || cold.contains(done) || serial.contains(retained) ||
		(cold.index(retained) or { -1 }) >= (cold.index('SOFTWARE GRAPHICAL INSTALLED BOOT 2 retained Counter reopened') or { -1 }) {
		return error('targeted refresh repeat or cold-boot order differs')
	}
	before := targeted_trace(serial, 'SOFTWARE TARGETED BEFORE ')!
	after := targeted_trace(serial, 'SOFTWARE TARGETED AFTER ')!
	if after != targeted_trace(cold, 'SOFTWARE TARGETED REBOOT ')! {
		return error('targeted refresh state differs after cold boot')
	}
	for name in ['config', 'lock', 'state', 'current', 'native-index', 'native-signature']! {
		if before[name]! != after[name]! { return error('targeted refresh changed retained ' + name) }
	}
	for name in ['catalog', 'history', 'field-index', 'field-signature']! {
		if before[name]! == after[name]! { return error('targeted refresh did not advance ' + name) }
	}
	if before['config']! != receipt.artifacts['config'] ||
		before['lock']! != receipt.artifacts['release-declaration'] ||
		before['native-index']! != receipt.artifacts['repository/index.json'] ||
		before['native-signature']! != sha256.hexhash(os.read_file(run + '/rootfs' +
			pkgcore.image_repositories_path + '/native/index.sig')!.trim_space()) {
		return error('targeted refresh observation differs from enrolled HTTPS inputs')
	}
	for i, directory in [run + '/rootfs' + pkgcore.image_repositories_path + '/field',
		run + '/rootfs/usr/share/native-catalog/releases/field-next']! {
		name := if i == 0 { 'field-baseline' } else { 'field-next' }
		paths[name + '/index.json'] = directory + '/index.json'
		paths[name + '/index.sig'] = directory + '/index.sig'
		text := os.read_file(paths[name + '/index.json'])!
		signature := os.read_file(paths[name + '/index.sig'])!.trim_space()
		index := pkgcore.verify_index(field, text, signature, 0)!
		observation := if i == 0 { before } else { after }
		if index.sequence != u64(i + 1) || index.packages.len != 0 ||
			observation['field-index']! != sha256.hexhash(text) ||
			observation['field-signature']! != sha256.hexhash(signature) {
			return error('targeted refresh observation differs from the signed field inputs')
		}
	}
}

fn targeted_pixel_changes(run string, first string, second string, x int, y int, width int, height int) !int {
	before := stbi.load(run + '/' + first + '.png', desired_channels: 3)!
	defer { before.free() }
	after := stbi.load(run + '/' + second + '.png', desired_channels: 3)!
	defer { after.free() }
	if before.width != 1024 || before.height != 768 || after.width != 1024 || after.height != 768 {
		return error('targeted refresh framebuffer dimensions differ')
	}
	mut changed := 0
	for row in y .. y + height {
		for col in x .. x + width {
			at := (row * 1024 + col) * 3
			if unsafe { before.data[at] != after.data[at] || before.data[at + 1] != after.data[at + 1] ||
				before.data[at + 2] != after.data[at + 2] } { changed++ }
		}
	}
	return changed
}

fn admit_targeted_pixels(run string) ! {
	if targeted_pixel_changes(run, targeted_shots[0], targeted_shots[1], 338, 68, 174, 28)! <= 8 ||
		targeted_pixel_changes(run, targeted_shots[1], targeted_shots[2], 524, 68, 102, 28)! <= 8 ||
		targeted_pixel_changes(run, targeted_shots[1], targeted_shots[3], 524, 68, 102, 28)! != 0 ||
		targeted_pixel_changes(run, targeted_shots[3], targeted_shots[4], 14, 154, 500, 30)! <= 8 ||
		targeted_pixel_changes(run, targeted_shots[4], targeted_shots[5], 22, 156, 350, 26)! <= 8 ||
		targeted_pixel_changes(run, targeted_shots[1], targeted_shots[6], 338, 68, 174, 28)! != 0 ||
		targeted_pixel_changes(run, targeted_shots[3], targeted_shots[6], 14, 644, 820, 27)! <= 8 ||
		targeted_pixel_changes(run, targeted_shots[1], targeted_shots[7], 14, 112, 236, 88)! <= 8 {
		return error('targeted refresh framebuffer transitions differ')
	}
}

fn admit_production_serial(path string, boot int) ! {
	transcript := os.read_file(path)!
	registration := 'SOFTWARE GRAPHICAL PRODUCTION root registration READY'
	mut markers := ['SOFTWARE GRAPHICAL PRODUCTION PID1 installed inputs and observer parent PASS',
		'SOFTWARE GRAPHICAL PRODUCTION direct-child graphical manager PASS']
	if boot == 1 {
		markers << registration
	} else if transcript.contains(registration) {
		return error('production registration repeated on boot 2')
	}
	markers << 'SOFTWARE GRAPHICAL PRODUCTION ordinary greeter uid=101 READY'
	if boot == 1 { markers << 'SOFTWARE FIRST RUN pre-ready compositor uid=1000 home=/home/alex runtime=0700 PASS' }
	markers << ['SOFTWARE GRAPHICAL ordinary-compositor uid=1000 home=/home/alex PASS',
		'SOFTWARE GRAPHICAL PRODUCTION authenticated ordinary seat uid=1000 PASS']
	mut previous := -1
	for marker in markers {
		exact_marker(transcript, marker)!
		position := transcript.index(marker) or { return error('missing production graphical marker') }
		if position <= previous { return error('production login markers are out of order') }
		previous = position
	}
	if transcript.contains('SOFTWARE GRAPHICAL requesting guest poweroff') {
		return error('production shutdown must use the desktop power action')
	}
}

fn admit_production_inputs(run string, receipt Receipt, mut paths map[string]string) ! {
	proof := json2.decode[map[string]string](os.read_file(paths['installed-declaration'])!)!
	for path in ['/sbin/init', '/bin/busybox', '/lib/ld-musl-' + receipt.architecture + '.so.1',
		'/usr/sbin/vinix-volume', '/usr/sbin/vinix-system', '/usr/share/vinix/actions/power-off'] {
		image := receipt.artifacts['production-image' + path] or { return error('missing production image input: ' + path) }
		if receipt.artifacts['production-stage' + path] != image || proof[path] != image {
			return error('production stage and installed input do not match: ' + path)
		}
		paths['production-image' + path] = run + '/rootfs' + path
	}
	for applet in ['sh', 'mkdir', 'chmod', 'rm', 'ln', 'sleep', 'kill', 'mount', 'cat', 'sync', 'zsh'] {
		path := '/bin/' + applet
		if proof['@link:' + path] != 'busybox' || os.readlink(run + '/rootfs' + path)! != 'busybox' {
			return error('production BusyBox alias differs: ' + path)
		}
	}
	observer := '/usr/libexec/vinix-version-check'
	guest := receipt.artifacts['guest'] or { return error('missing production observer build') }
	if proof[observer] != guest || receipt.artifacts['production-observer'] != guest ||
		proof['/sbin/init'] == guest {
		return error('production init and read-only observer identities differ')
	}
	paths['production-observer'] = run + '/rootfs' + observer
	paths['qemu-arguments'] = run + '/qemu-arguments.json'
	arguments := json2.decode[[]string](os.read_file(paths['qemu-arguments'])!)!
	net := arguments.index('-nic')
	if net < 0 || net + 1 >= arguments.len || arguments[net + 1] != 'none' ||
		arguments.filter(it in ['-nic', '-netdev', '-net']!).len != 1 {
		return error('production graphical run does not disable QEMU networking')
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
		'qemu-framebuffer-ordinary-seat-first-run-refresh-installed-root-two-boots',
		'qemu-framebuffer-production-login-first-run-refresh-installed-root-two-boots',
		'qemu-framebuffer-production-login-staged-catalog-installed-root-two-boots', targeted_platform,
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
	targeted := receipt.platform == targeted_platform
	staged := targeted || receipt.platform == 'qemu-framebuffer-production-login-staged-catalog-installed-root-two-boots'
	production := staged || receipt.platform == 'qemu-framebuffer-production-login-first-run-refresh-installed-root-two-boots'
	refresh := production || receipt.platform == 'qemu-framebuffer-ordinary-seat-first-run-refresh-installed-root-two-boots'
	first_run := refresh || release_routing || receipt.platform == 'qemu-framebuffer-ordinary-seat-first-run-installed-root-two-boots'
	if release_routing && digest(run + '/source/guest/release_routing.v')! !=
		sha256.sum($embed_file('software-graphical-guest/release_routing.v').to_string().bytes()).hex() {
		return error('qualified graphical fixture differs from the embedded source: guest/release_routing.v')
	}
	if targeted && digest(run + '/source/guest/targeted_refresh.v')! !=
		sha256.sum($embed_file('software-graphical-guest/targeted_refresh.v').to_string().bytes()).hex() {
		return error('qualified targeted refresh observer differs from the embedded source')
	}
	admit_serial(run + '/serial.log', installed, first_run, release_routing, refresh, staged, 1, arch)!
	if installed {
		admit_serial(run + '/serial-2.log', true, first_run, release_routing, refresh, staged, 2, arch)!
		admit_shutdown(run + '/shutdown-1.jsonl', 1)!
		admit_shutdown(run + '/shutdown-2.jsonl', 2)!
	}
	if production {
		if digest(run + '/source/guest/production.v')! !=
			sha256.sum($embed_file('software-graphical-guest/production.v').to_string().bytes()).hex() {
			return error('qualified production observer differs from the embedded source')
		}
		admit_production_serial(run + '/serial.log', 1)!
		admit_production_serial(run + '/serial-2.log', 2)!
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
	if production { admit_production_inputs(run, receipt, mut paths)! }
	if first_run {
		paths['release-declaration'] = run + '/rootfs/usr/share/vinix-packages/applications.json'
		declaration := json2.decode[json2.Any](os.read_file(paths['release-declaration'])!)!.as_map()
		if staged {
			admit_staged_catalog(run, receipt, mut paths)!
		} else if release_routing {
			admit_release_routing_declaration(declaration, arch, os.read_file(run + '/serial.log')!)!
		} else if declaration.len != 3 || declaration['format']! != json2.Any(f64(1)) ||
			declaration['architecture']!.str() != arch ||
			declaration['packages']!.as_array().map(it.str()) != ['org.vinix.counter'] {
			return error('first-run declaration differs from the complete architecture-matched Counter set')
		}
	}
	if release_routing { paths['release-routing-controls'] = run + '/release-routing-controls.json' }
	if refresh {
		paths['first-run-refresh-mode'] = run + '/rootfs/etc/software-graphical-first-run-refresh'
		config := pkgcore.load_config(run + '/rootfs')!
		if os.read_file(paths['first-run-refresh-mode'])! != '1\n' || config.policy.offline ||
			config.repositories.len != (if targeted { 2 } else { 1 }) || config.repositories[0].id != 'native' ||
			!config.repositories[0].url.starts_with('https://') {
			return error('first-run refresh receipt lacks the HTTPS image configuration')
		}
	}
	if targeted { admit_targeted_refresh(run, receipt, mut paths)! }
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
	if refresh {
		required_shots << ['first-run-refresh-01-catalog', 'first-run-refresh-02-administrator', 'first-run-refresh-03-password-mask']
	}
	if production {
		required_shots << ['production-01-registration', 'production-02-greeter', 'production-03-shutdown-menu',
			'production-04-reboot-greeter', 'production-05-shutdown-menu']
	}
	if targeted { for name in targeted_shots { required_shots << name } }
	if release_routing {
		required_shots << ['release-routing-01-desktop', 'release-routing-02-extra-refused',
			'release-routing-03-action-refused', 'release-routing-02-extra-barrier',
			'release-routing-03-action-barrier']
	}
	shots.sort()
	required_shots.sort()
	if shots != required_shots { return error('graphical run lacks the exact required screenshot set') }
	if targeted { admit_targeted_pixels(run)! }
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
	if targeted {
		source_names << ['software_repositories.v', 'software_package_navigation.v', 'software_admin.v', 'software_progress.v']
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
	prefix := out + if targeted { '/software-targeted-refresh-graphical-' + arch
	} else if staged { '/software-first-run-production-staged-' + arch
	} else if production { '/software-first-run-production-native-' + arch
	} else if release_routing { '/software-release-routing-native-' + arch } else if refresh {
		'/software-first-run-refresh-native-' + arch
	} else if first_run {
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
