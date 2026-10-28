// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh diagnostic launch; the preceding complete checkpoint remains unchanged.
module main

import crypto.sha256
import frozenv
import os
import strconv

const prior_hash = '8b4028c3d90c69e6b4e418820ab287eb93c8fdc4f6f0ecd10ce99346e069df09'
const built_paths = ['notification-vm', 'native-init', 'native-init.c', 'swift-optional-lookup-checks',
	'swift-optional-lookup-checks.c', 'run-ios-gles', 'run-ios-gles.c']

fn required_built_paths(out string) ![]string {
	mut paths := built_paths.clone()
	if session_defaults_probe(out)! { paths << ['session-defaults-checks', 'session-defaults-checks.c'] }
	return paths
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut bytes := []u8{len: 1048576}
	defer { unsafe { bytes.free() } }
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn capture(out string, label string, args []string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	frozenv.configure(mut p, args[0])!
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(out + '/' + label + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output)!
	os.write_file(out + '/' + label + '.status.txt', code.str() + '\n')!
	if code != 0 { return error(label + ' failed; see ' + out + '/' + label + '.log') }
	println(label + ': PASS')
}

fn safe_path(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains('\\') && !path.contains('\n')
		&& !path.contains_any('\r\t')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

fn input_paths(out string, relative string) ![]string {
	mut paths := []string{}
	for name in os.ls(out + '/' + relative)! {
		path := if relative == '' { name } else { relative + '/' + name }
		if !safe_path(path) || os.is_link(out + '/' + path) { return error('unsafe input') }
		if os.is_dir(out + '/' + path) { paths << input_paths(out, path)! }
		else { paths << path }
	}
	return paths
}

fn hash_records(text string) !map[string]string {
	mut records := map[string]string{}
	for line in text.trim_right('\n').split_into_lines() {
		if line.len < 67 || line[64..66] != '  ' || !safe_path(line[66..])
			|| line[..64].bytes().any(!it.is_hex_digit()) || line[66..] in records {
			return error('invalid or duplicate input hash')
		}
		records[line[66..]] = line[..64]
	}
	return records
}

fn reused_records(text string, prior map[string]string, expected []string) !map[string]string {
	listed := hash_records(text)!
	mut paths := listed.keys()
	paths.sort()
	if paths != expected { return error('changed or incomplete reused input list') }
	for path in expected {
		if listed[path] != prior[path] { return error('reused input differs from pinned prior') }
	}
	return listed
}

fn verify_inputs(out string) ! {
	if digest(out + '/prior-manifest.sha256')! != prior_hash { return error('changed prior manifest') }
	prior := hash_records(os.read_file(out + '/prior-manifest.sha256')!)!
	mut fixtures := []string{}
	mut expected := ['vinix']
	for path in prior.keys() {
		if !path.contains('/') && path.ends_with('-checks') && path != 'notification-checks' {
			fixtures << path
			expected << [path, path + '.c']
		}
		if path.starts_with('application/') || path.starts_with('resources/') { expected << path }
	}
	fixtures.sort()
	if fixtures.len != 35 || os.read_file(out + '/fixtures.txt')! != fixtures.join('\n') + '\n' {
		return error('changed or incomplete fixture list')
	}
	if !optional_probe(out)! { expected << ['native-init', 'native-init.c', 'notification-vm'] }
	expected.sort()
	listed := reused_records(os.read_file(out + '/reused-inputs.sha256')!, prior, expected)!
	mut resources := input_paths(out, 'application')!
	resources << input_paths(out, 'resources')!
	resources.sort()
	if resources != expected.filter(it.starts_with('application/') || it.starts_with('resources/')) {
		return error('changed resource list')
	}
	for path in expected {
		if digest(out + '/' + path)! != listed[path] {
			return error('changed reused input: ' + path)
		}
	}
}

fn prepare(out string, prior string, optional_lookup bool, session_defaults bool) ! {
	if os.exists(out) || os.is_link(out) { return error('prepare needs a fresh directory') }
	if digest(prior + '/manifest.sha256')! != prior_hash { return error('unexpected prior checkpoint') }
	os.mkdir_all(out)!
	os.mkdir_all(out + '/tmp')!
	os.setenv('VINIX_IOS_AUDIT_TMPDIR', out + '/tmp', true)
	capture(out, 'prior-check', [prior + '/error-description', 'check', prior])!
	os.cp(prior + '/manifest.sha256', out + '/prior-manifest.sha256')!
	os.write_file(out + '/prior-bundle.txt', prior + '\n')!
	mut paths := ['vinix']
	if !optional_lookup { paths << ['native-init', 'native-init.c', 'notification-vm'] }
	mut fixtures := []string{}
	for name in os.ls(prior)! {
		if name.ends_with('-checks') && os.is_file(prior + '/' + name) && name != 'notification-checks' {
			fixtures << name
			paths << name
			paths << name + '.c'
		}
	}
	fixtures.sort()
	if fixtures.len != 35 { return error('expected 35 prior guest fixtures') }
	for path in paths { os.cp(prior + '/' + path, out + '/' + path)! }
	for directory in ['application', 'resources'] {
		capture(out, 'copy-' + directory, ['/bin/cp', '-Rp', prior + '/' + directory, out + '/' + directory])!
		paths << input_paths(out, directory)!
	}
	os.write_file(out + '/fixtures.txt', fixtures.join('\n') + '\n')!
	mut hashes := []string{}
	paths.sort()
	for path in paths {
		if digest(out + '/' + path)! != digest(prior + '/' + path)! { return error('copy mismatch: ' + path) }
		hashes << digest(out + '/' + path)! + '  ' + path
	}
	os.write_file(out + '/reused-inputs.sha256', hashes.join('\n') + '\n')!
	revision := os.exec(['git', 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { return error(revision.output) }
	os.write_file(out + '/source-revision.txt', revision.output)!
	capture(out, 'source-check', ['git', 'diff', '--exit-code', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
	capture(out, 'source-snapshot', ['git', 'archive', '--format=tar', '--output=' + out + '/source.tar', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
	os.write_file(out + '/source.sha256', digest(out + '/source.tar')! + '  source.tar\n')!
	os.cp(os.executable(), out + '/checkpoint')!
	os.cp(os.getwd() + '/tests/ios/swift-type-probe.v', out + '/checkpoint.v')!
	os.write_file(out + '/checkpoint-revision.txt', revision.output)!
	if optional_lookup {
		os.write_file(out + '/probe-kind.txt', if session_defaults { 'session-defaults\n' } else { 'optional-lookup\n' })!
		v := os.real_path(os.getwd()) + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
		capture(out, 'build-notification-vm', [v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2',
			'-path', '@vlib|' + os.getwd() + '/compat/ios|' + os.getwd() + '/tests/ios|@vmodules',
			'-o', out + '/notification-vm', os.getwd() + '/tests/ios/notification-vm.v'])!
	}
}

fn optional_probe(out string) !bool {
	if !os.exists(out + '/probe-kind.txt') { return false }
	if os.read_file(out + '/probe-kind.txt')! !in ['optional-lookup\n', 'session-defaults\n'] { return error('unknown probe kind') }
	return true
}

fn session_defaults_probe(out string) !bool {
	if !optional_probe(out)! { return false }
	return os.read_file(out + '/probe-kind.txt')! == 'session-defaults\n'
}

fn verify_built(out string) ! {
	if !optional_probe(out)! { return }
	if os.read_file(out + '/source.sha256')! != digest(out + '/source.tar')! + '  source.tar\n' {
		return error('changed source snapshot')
	}
	mut expected := []string{}
	for path in required_built_paths(out)! {
		expected << digest(out + '/' + path)! + '  ' + path
	}
	if os.read_file(out + '/built-inputs.sha256')! != expected.join('\n') + '\n' {
		return error('changed or incomplete built inputs')
	}
}

fn validate_serial(serial string, fixtures []string, optional_lookup bool) !(string, []string) {
	for fixture in fixtures {
		if serial.count('IOS-NATIVE: /opt/ios/' + fixture + ' wait status 0\n') != 1 { return error('fixture failed: ' + fixture) }
	}
	if optional_lookup {
		for marker in ['IOS-NATIVE: /opt/ios/swift-optional-lookup-checks wait status 0',
			'IOS-SWIFT-OPTIONAL-LOOKUP: canonical Optional/Array order, four lookup entries, TaskPriority byte witnesses, guarded spans, bounded nesting, rejection before allocation, eight publishers and two drained runtimes PASS'] {
			if serial.count(marker) != 1 { return error('missing or duplicated Optional fixture: ' + marker) }
		}
	} else if serial.count('V panic: iOS: unsupported Swift mangled type suffix\n') != 1 {
		return error('missing original diagnostic boundary')
	}
	for marker in ['iOS startup: application entry', 'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS',
		'IOS-PROBE-FAULT: signal context and restoration PASS', 'IOS-PROBE-DESKTOP: UIKit window fixture PASS',
		'V panic:',
		'FORTNITE PROBE: process exit status 1\n', 'FORTNITE PROBE COMPLETE'] {
		if serial.count(marker) != 1 { return error('missing or duplicated marker: ' + marker) }
	}
	app := serial.all_after('iOS startup: application entry')
	stops := app.split_into_lines().filter(it.starts_with('IOS-PROBE-DESKTOP: stop='))
	if app.count('IOS-PROBE-DESKTOP: handshake version=10\n') != 1
		|| app.count('IOS-PROBE-DESKTOP: tree build=1 nodes=1 images=0 bytes=336\n') != 1
		|| stops.len != 1 || !stops[0].contains(' handshake=true builds=')
		|| !stops[0].ends_with(' closed=false supervisor_kill=false wait=256') {
		return error('missing application desktop guard')
	}
	finals := app.split_into_lines().filter(it.starts_with('IOS-PROBE-BUDGET: final '))
	if finals.len != 1 || !finals[0].ends_with(' events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;') {
		return error('missing clean application budget result')
	}
	for bad in ['IOS-PROBE-FAULT:', 'IOS-PROBE-REGS:', 'supervisor_kill=true', 'KERNEL PANIC', 'FATAL EXCEPTION', '> assert ', 'runtime error:'] {
		if app.contains(bad) { return error('unexpected application failure: ' + bad) }
	}
	boundaries := app.split_into_lines().filter(it.starts_with('V panic: '))
	if boundaries.len != 1 { return error('expected one explicit startup boundary') }
	lines := app.split_into_lines().filter(it.starts_with('IOS-PROBE-SWIFT-TYPE: '))
	if lines.len > 1 || (!optional_lookup && lines.len != 1) { return error('unexpected rejected type count') }
	for line in lines {
		length := strconv.parse_uint(line.all_after(' length=').all_before(' '), 10, 64)!
		copied := strconv.parse_uint(line.all_after(' copied=').all_before(' '), 10, 64)!
		bytes := line.all_after(' bytes=')
		if length == 0 || length > 1048576 || copied != if length < 64 { length } else { u64(64) }
			|| bytes.len != int(copied * 2) || bytes.bytes().any(!it.is_hex_digit()) { return error('invalid bounded diagnostic') }
		if optional_lookup && bytes == '5363505367' { return error('Optional TaskPriority remains unresolved') }
	}
	return boundaries[0], lines
}

fn validate_launch(launch string) ! {
	for marker in ['guest memory: 8192 MiB; virtual CPUs: 1', 'VM probe memory.max: 2147483648', 'VM startup limit: 1800 seconds', 'Serial capture reset before VM launch'] {
		if !launch.contains(marker) { return error('missing launch guard: ' + marker) }
	}
}

fn host_markers(defaults bool) map[string][]string {
	mut markers := {
		'swift-optional-lookup-host': ['IOS-SWIFT-OPTIONAL-LOOKUP-NATIVE:', 'IOS-SWIFT-OPTIONAL-LOOKUP:']
		'swift-mangled-optional-regression': ['IOS-SWIFT-MANGLED-NATIVE:', 'IOS-SWIFT-MANGLED:']
		'swift-context2-optional-regression': ['NATIVE-CONTEXT2:', 'IOS-CONTEXT2:']
		'swift-mangled-state-optional-regression': ['IOS-MANGLED-STATE-NATIVE:', 'IOS-MANGLED-STATE:']
		'swift-mangled-state2-optional-regression': ['NATIVE-MANGLED-STATE2:', 'IOS-MANGLED-STATE2:']
		'swift-optional-metadata-regression': ['NATIVE-OPTIONAL-METADATA:', 'IOS-OPTIONAL-METADATA:']
		'swift-task-priority-optional-regression-fixed': ['IOS-SWIFT-TASK-PRIORITY-NATIVE:', 'IOS-SWIFT-TASK-PRIORITY:']
	}
	if defaults {
		markers['session-defaults-host'] = ['IOS-SESSION-CONFIGURATION-NATIVE:',
			'IOS-SESSION-DEFAULTS-NATIVE:', 'IOS-SESSION-CONFIGURATION:',
			'IOS-SESSION-DEFAULTS:', 'IOS-SESSION-CONFIGURATION-REJECT:31']
	}
	return markers
}

fn validate_host_log(log string, markers []string) ! {
	if !log.starts_with('COMMAND: ') { return error('missing host command') }
	for marker in markers {
		if log.count(marker) != 1 { return error('missing or duplicated host marker') }
	}
	for bad in ['runtime error:', 'ERROR: AddressSanitizer', 'V panic:', '> assert '] {
		if log.contains(bad) { return error('failed sanitized host run') }
	}
}

fn verify_host(out string) ! {
	for directory, markers in host_markers(session_defaults_probe(out)!) {
		for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
			base := out + '/host/' + directory + '/' + label
			if os.read_file(base + '.status.txt')! != '0\n' { return error('failed host step: ' + base) }
			log := os.read_file(base + '.log')!
			if !log.starts_with('COMMAND: ') { return error('missing host command') }
			if label in ['host', 'host-deterministic'] { validate_host_log(log, markers)! }
		}
	}
}

fn inspect(out string) ! {
	verify_inputs(out)!
	verify_built(out)!
	optional_lookup := optional_probe(out)!
	if optional_lookup { verify_host(out)! }
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(state) != out || !os.file_name(state).starts_with('probe-no-ads-') { return error('unsafe state') }
	serial := os.read_file(state + '/serial.log')!.replace('\r\n', '\n')
	boundary, lines := validate_serial(serial, os.read_lines(out + '/fixtures.txt')!, optional_lookup)!
	if session_defaults_probe(out)! { validate_session_defaults(serial)! }
	validate_launch(os.read_file(out + '/probe-no-ads.log')!)!
	diagnostic := boundary + '\n' + lines.join('\n') + '\nserial SHA-256: ' + digest(state + '/serial.log')! + '\nruntime SHA-256: ' + digest(out + '/run-ios-gles')! + '\n'
	if os.exists(out + '/manifest.sha256') {
		if os.read_file(out + '/diagnostic.txt')! != diagnostic { return error('changed diagnostic') }
	} else { os.write_file(out + '/diagnostic.txt', diagnostic)! }
	println(boundary)
	for line in lines { println(line) }
	println(if session_defaults_probe(out)! { 'Default session launch: two new fixtures and 35 reused guest fixtures PASS; rendering unverified' }
		else if optional_lookup { 'Swift Optional launch: new lookup fixture and 35 reused guest fixtures PASS; rendering unverified' }
		else { 'Swift diagnostic launch: 35 reused guest fixtures PASS; rendering unverified' })
}

fn guest_media(out string) ! {
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(state) != out || !os.file_name(state).starts_with('probe-no-ads-') { return error('unsafe state') }
	temporary := os.getenv('TMPDIR') + '/swift-probe-media-' + os.getpid().str()
	if os.exists(temporary) { return error('scratch already exists') }
	os.mkdir_all(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	// Verify that the boot image contains the recorded kernel and initramfs.
	for name in ['vinix', 'initramfs.tar.gz', 'limine.conf'] {
		result := os.exec(['mcopy', '-i', state + '/boot.img', '::/boot/' + name, temporary + '/' + name])
		expected := if name == 'vinix' { out + '/vinix' } else { state + '/' + name }
		if result.exit_code != 0 || digest(temporary + '/' + name)! != digest(expected)! {
			return error('changed boot member: ' + name)
		}
		os.rm(temporary + '/' + name)!
	}
	mut pairs := [['native-init', 'sbin/init'], ['run-ios-gles', 'opt/ios/run-ios']]
	for name in os.read_lines(out + '/fixtures.txt')! { pairs << [name, 'opt/ios/' + name] }
	if optional_probe(out)! { pairs << ['swift-optional-lookup-checks', 'opt/ios/swift-optional-lookup-checks'] }
	if session_defaults_probe(out)! { pairs << ['session-defaults-checks', 'opt/ios/session-defaults-checks'] }
	for path in input_paths(out, 'application')! { pairs << [path, 'opt/ios/' + path['application/'.len..]] }
	for path in input_paths(out, 'resources')! { pairs << [path, 'opt/ios/' + path['resources/'.len..]] }
	mut args := ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz', '-C', temporary, '--']
	for pair in pairs { args << './' + pair[1] }
	for name in ['probe-desktop', 'probe-memory-max', 'check-mode'] { args << './opt/ios/' + name }
	result := os.exec(args)
	if result.exit_code != 0 { return error('cannot extract guest inputs: ' + result.output) }
	for pair in pairs {
		if digest(out + '/' + pair[0])! != digest(temporary + '/' + pair[1])! { return error('changed guest input: ' + pair[0]) }
	}
	if os.read_file(temporary + '/opt/ios/probe-desktop')! != '1'
		|| os.read_file(temporary + '/opt/ios/probe-memory-max')! != '2147483648'
		|| os.read_file(temporary + '/opt/ios/check-mode')! != 'probe-no-ads' { return error('changed guest configuration') }
}

// Resume only an interrupted compression, before any guest has run. Keep the
// partial archive and use the frozen VM launcher; the normal full media audit
// still verifies the recovered image against every recorded input afterwards.
fn resume_staging(root string, out string) ! {
	verify_built(out)!
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(state) != out || !os.file_name(state).starts_with('probe-no-ads-')
		|| os.is_link(state) || os.exists(out + '/probe-no-ads.status.txt') {
		return error('unsafe or completed staging state')
	}
	for name in ['boot.img', 'serial.log', 'initramfs-interrupted.tar.gz', 'initramfs-resumed.tar.gz'] {
		if os.exists(state + '/' + name) { return error('recovery already started or guest already launched') }
	}
	fs := state + '/rootfs'
	if !os.is_dir(fs) || os.is_link(fs) { return error('missing staging directory') }
	mut pairs := [['native-init', 'sbin/init'], ['run-ios-gles', 'opt/ios/run-ios']]
	for name in os.read_lines(out + '/fixtures.txt')! { pairs << [name, 'opt/ios/' + name] }
	if optional_probe(out)! { pairs << ['swift-optional-lookup-checks', 'opt/ios/swift-optional-lookup-checks'] }
	if session_defaults_probe(out)! { pairs << ['session-defaults-checks', 'opt/ios/session-defaults-checks'] }
	// The executable is supplied by the preserved base tar, not the overlay.
	for path in input_paths(out, 'application')! {
		if path != 'application/FortniteClient-IOS-Shipping' {
			pairs << [path, 'opt/ios/' + path['application/'.len..]]
		}
	}
	for path in input_paths(out, 'resources')! { pairs << [path, 'opt/ios/' + path['resources/'.len..]] }
	mut staged := u64(0)
	for pair in pairs {
		path := fs + '/' + pair[1]
		if os.is_link(path) || digest(out + '/' + pair[0])! != digest(path)! {
			return error('changed staged input: ' + pair[0])
		}
		staged += os.file_size(path)
	}
	for name, value in {'probe-desktop': '1', 'probe-memory-max': '2147483648', 'check-mode': 'probe-no-ads'} {
		if os.read_file(fs + '/opt/ios/' + name)! != value { return error('changed staged guard') }
	}
	// The initial launch already required 8 GiB before staging. Account only
	// for validated staged files and the incomplete archive against that same
	// headroom requirement, rather than charging for their storage twice.
	archive := state + '/initramfs.tar.gz'
	available := os.disk_usage(out.clone())!.available
	if available + staged + os.file_size(archive) < u64(8) * 1024 * 1024 * 1024 {
		return error('insufficient headroom to resume compression')
	}
	new_archive := state + '/initramfs-resumed.tar.gz'
	capture(out, 'resume-compress', ['tar', '--format=ustar', '--options', 'gzip:compression-level=1',
		'-czf', new_archive, '-s', ',^opt/ios/run-ios$,,',
		'@' + root + '/build/ios/fortnite/probe-initramfs.tar.gz', '-C', fs, '.'])!
	capture(out, 'resume-archive-check', ['tar', '-tzf', new_archive])!
	os.rename(archive, state + '/initramfs-interrupted.tar.gz')!
	os.rename(new_archive, archive)!
	os.rmdir_all(fs)!
	archive_mb := (os.file_size(archive) + 1024 * 1024 - 1) / (1024 * 1024)
	boot_mb := if archive_mb + 128 > 384 { ((archive_mb + 128 + 63) / 64) * 64 } else { u64(384) }
	if os.disk_usage(out.clone())!.available < (boot_mb + 2048) * 1024 * 1024 {
		return error('insufficient headroom for boot media and audit')
	}
	disk := state + '/boot.img'
	capture(out, 'resume-boot-create', ['mkfile', '-n', boot_mb.str() + 'm', disk])!
	capture(out, 'resume-boot-format', ['mformat', '-F', '-i', disk, '::'])!
	for i, path in ['::/EFI', '::/EFI/BOOT', '::/boot'] {
		capture(out, 'resume-boot-dir-' + i.str(), ['mmd', '-i', disk, path])!
	}
	conf := state + '/limine.conf'
	os.write_file(conf, 'timeout: 0\nverbose: yes\n/Vinix\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: $boot():/boot/initramfs.tar.gz\n    resolution: 1024x768x32\n    kbacktracer: no\n')!
	for source, target in {root + '/boot-image/limine-bin/BOOTAA64.EFI': '::/EFI/BOOT/BOOTAA64.EFI',
		conf: '::/boot/limine.conf', out + '/vinix': '::/boot/vinix', archive: '::/boot/initramfs.tar.gz'} {
		capture(out, 'resume-copy-' + os.file_name(source), ['mcopy', '-i', disk, source, target])!
	}
	os.setenv('VINIX_IOS_VM_CPUS', '1', true)
	// The replay path uses exactly the guarded configuration checked above.
	capture(out, 'probe-no-ads', [out + '/notification-vm', 'replay-probe-no-ads', out])!
	log := os.read_file(out + '/probe-no-ads.log')!
	os.write_file(out + '/probe-no-ads.log', log + 'Recovered staged VM probe memory.max: 2147483648\n')!
	inspect(out)!
}

fn bundle_manifest(out string) !string {
	mut paths := input_paths(out, '')!.filter(it != 'manifest.sha256')
	paths.sort()
	mut hashes := []string{}
	for path in paths { hashes << digest(out + '/' + path)! + '  ' + path }
	return hashes.join('\n') + '\n'
}

fn checkpoint(out string, seal bool) ! {
	if seal {
		if os.exists(out + '/manifest.sha256') { return error('already sealed') }
	} else if bundle_manifest(out)! != os.read_file(out + '/manifest.sha256')! {
		return error('changed or incomplete evidence bundle')
	}
	inspect(out)!
	guest_media(out)!
	if seal { os.write_file(out + '/manifest.sha256', bundle_manifest(out)!)! }
	println('Complete Swift probe checkpoint: PASS (game rendering unverified)')
}

fn reject_serial(serial string, fixtures []string, optional_lookup bool) ! {
	if _ , _ := validate_serial(serial, fixtures, optional_lookup) { return error('accepted changed guest log') }
}

fn validate_session_defaults(serial string) ! {
	for marker in ['IOS-NATIVE: /opt/ios/session-defaults-checks wait status 0\n',
		'IOS-SESSION-CONFIGURATION:', 'IOS-SESSION-CONFIGURATION-REJECT:31',
		'IOS-SESSION-DEFAULTS: fresh settings, explicit protocol replacement, copies across pool drainage, nil constructor, eight workers and two drained runtimes PASS\n'] {
		if serial.count(marker) != 1 { return error('missing or duplicated default session fixture: ' + marker) }
	}
}

fn negative_controls(out string, scratch string) ! {
	if os.exists(scratch) || os.is_link(scratch) || scratch.starts_with(out + '/') {
		return error('negative controls need fresh external scratch')
	}
	os.mkdir_all(scratch)!
	optional_lookup := optional_probe(out)!
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	serial := os.read_file(state + '/serial.log')!.replace('\r\n', '\n')
	fixtures := os.read_lines(out + '/fixtures.txt')!
	_, _ := validate_serial(serial, fixtures, optional_lookup)!
	mut markers := []string{}
	for fixture in fixtures { markers << 'IOS-NATIVE: /opt/ios/' + fixture + ' wait status 0' }
	markers << serial.split_into_lines().filter(it.starts_with('IOS-SWIFT-OPTIONAL-LOOKUP:')
		|| it.starts_with('IOS-NATIVE: /opt/ios/swift-optional-lookup-checks wait status '))
	markers << ['iOS startup: application entry', 'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS',
		'IOS-PROBE-FAULT: signal context and restoration PASS', 'IOS-PROBE-DESKTOP: UIKit window fixture PASS',
		'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE']
	app := serial.all_after('iOS startup: application entry')
	markers << app.split_into_lines().filter(it.starts_with('V panic:')
		|| it.starts_with('IOS-PROBE-DESKTOP: handshake ')
		|| it.starts_with('IOS-PROBE-DESKTOP: tree build=1 ')
		|| it.starts_with('IOS-PROBE-DESKTOP: stop=')
		|| it.starts_with('IOS-PROBE-BUDGET: final '))
	mut count := 0
	prior := {'a': '0'.repeat(64), 'b': '1'.repeat(64)}
	valid := prior['a'] + '  a\n' + prior['b'] + '  b\n'
	reused_records(valid, prior, ['a', 'b'])!
	for changed in ['', prior['a'] + '  a\n', valid + prior['a'] + '  a\n', valid + prior['a'] + '  c\n',
		valid.replace(prior['a'], '2'.repeat(64)), valid.replace('  a', '  ../a'),
		valid.replace(prior['a'], 'z'.repeat(64)), valid.replace('  b', '  /b')] {
		reused_records(changed, prior, ['a', 'b']) or { count++; continue }
		return error('accepted changed, incomplete or unsafe reused records')
	}
	for marker in markers {
		reject_serial(serial.replace(marker + '\n', ''), fixtures, optional_lookup)!
		reject_serial(serial + '\n' + marker + '\n', fixtures, optional_lookup)!
		count += 2
	}
	for bad in ['IOS-PROBE-FAULT: signal=11', 'IOS-PROBE-REGS: pc=0', 'supervisor_kill=true',
		'KERNEL PANIC', 'FATAL EXCEPTION', '> assert failed', 'runtime error: alignment'] {
		reject_serial(serial.replace('iOS startup: application entry', 'iOS startup: application entry\n' + bad), fixtures, optional_lookup)!
		count++
	}
	for event in ['low', 'high', 'max', 'oom', 'oom_kill', 'oom_group_kill'] {
		reject_serial(serial.all_before('iOS startup: application entry') + 'iOS startup: application entry'
			+ app.replace(event + ' 0;', event + ' 1;'), fixtures, optional_lookup)!
		count++
	}
	launch := os.read_file(out + '/probe-no-ads.log')!
	validate_launch(launch)!
	for marker in ['guest memory: 8192 MiB; virtual CPUs: 1', 'VM probe memory.max: 2147483648',
		'VM startup limit: 1800 seconds', 'Serial capture reset before VM launch'] {
		validate_launch(launch.replace(marker, '')) or { count++; continue }
		return error('accepted missing launch guard')
	}
	if optional_lookup {
		for directory, host_checks in host_markers(session_defaults_probe(out)!) {
			log := os.read_file(out + '/host/' + directory + '/host.log')!
			validate_host_log(log, host_checks)!
			for marker in host_checks {
				mut rejected := 0
				validate_host_log(log.replace(marker, ''), host_checks) or { rejected++ }
				validate_host_log(log + marker, host_checks) or { rejected++ }
				if rejected != 2 { return error('accepted missing or duplicate host marker') }
				count += rejected
			}
			for bad in ['runtime error:', 'ERROR: AddressSanitizer', 'V panic:', '> assert '] {
				validate_host_log(log + bad, host_checks) or { count++; continue }
				return error('accepted failed host log')
			}
		}
		built := scratch + '/built'
		os.mkdir_all(built)!
		os.write_file(built + '/probe-kind.txt', 'optional-lookup\n')!
		os.write_file(built + '/source.tar', 'synthetic source snapshot')!
		os.write_file(built + '/source.sha256', digest(built + '/source.tar')! + '  source.tar\n')!
		mut hashes := []string{}
		for path in built_paths {
			os.write_file(built + '/' + path, path)!
			hashes << digest(built + '/' + path)! + '  ' + path
		}
		original := hashes.join('\n') + '\n'
		os.write_file(built + '/built-inputs.sha256', original)!
		verify_built(built)!
		for changed in ['', hashes[..6].join('\n') + '\n', original + hashes[0] + '\n', original.replace(hashes[0][..64], '0'.repeat(64))] {
			os.write_file(built + '/built-inputs.sha256', changed)!
			verify_built(built) or { count++; continue }
			return error('accepted incomplete or changed built input list')
		}
		os.write_file(built + '/built-inputs.sha256', original)!
		os.write_file(built + '/source.tar', 'changed snapshot')!
		mut rejected := false
		verify_built(built) or { rejected = true }
		if !rejected { return error('accepted changed source snapshot') }
		count++
	}
	if session_defaults_probe(out)! {
		validate_session_defaults(serial)!
		for marker in serial.split_into_lines().filter(it.starts_with('IOS-NATIVE: /opt/ios/session-defaults-checks ')
			|| it.starts_with('IOS-SESSION-CONFIGURATION:') || it.starts_with('IOS-SESSION-CONFIGURATION-REJECT:')
			|| it.starts_with('IOS-SESSION-DEFAULTS:')) {
			mut rejected := 0
			validate_session_defaults(serial.replace(marker + '\n', '')) or { rejected++ }
			validate_session_defaults(serial + marker + '\n') or { rejected++ }
			if rejected != 2 { return error('accepted missing or duplicate configuration marker') }
			count += rejected
		}
		built := scratch + '/default-built'
		os.mkdir_all(built)!
		os.write_file(built + '/probe-kind.txt', 'session-defaults\n')!
		os.write_file(built + '/source.tar', 'synthetic source snapshot')!
		os.write_file(built + '/source.sha256', digest(built + '/source.tar')! + '  source.tar\n')!
		mut hashes := []string{}
		for path in required_built_paths(built)! {
			os.write_file(built + '/' + path, path)!
			hashes << digest(built + '/' + path)! + '  ' + path
		}
		original := hashes.join('\n') + '\n'
		os.write_file(built + '/built-inputs.sha256', original)!
		verify_built(built)!
		for changed in [hashes[..7].join('\n') + '\n', original.replace(hashes[7][..64], '0'.repeat(64)), original.replace(hashes[8][..64], '0'.repeat(64))] {
			os.write_file(built + '/built-inputs.sha256', changed)!
			verify_built(built) or { count++; continue }
			return error('accepted incomplete or changed configuration built inputs')
		}
	}
	os.write_file(scratch + '/negative-controls.txt', count.str() + ' corruptions rejected; baseline guest and host logs pass\n')!
	println(count.str() + ' Swift checkpoint negative controls PASS')
}

fn main() {
	if os.args.len < 3 { panic('usage: swift-type-probe prepare FRESH_OUT PRIOR [--optional-lookup|--session-defaults] | build|probe|resume-staging|inspect|seal|check OUT | negative-controls OUT FRESH_SCRATCH') }
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') || os.is_link(out) { panic('output must be external') }
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	if os.args[1] == 'negative-controls' {
		if os.args.len != 4 { panic('negative-controls requires OUT FRESH_SCRATCH') }
		scratch := os.abs_path(os.args[3])
		if scratch == root || scratch.starts_with(root + '/') { panic('scratch must be external') }
		negative_controls(out, scratch)!
		return
	}
	if os.args[1] == 'prepare' {
		if os.args.len !in [4, 5] || (os.args.len == 5 && os.args[4] !in ['--optional-lookup', '--session-defaults']) { panic('prepare requires PRIOR [--optional-lookup|--session-defaults]') }
		prepare(out, os.real_path(os.args[3]), os.args.len == 5, os.args.len == 5 && os.args[4] == '--session-defaults')!
		return
	}
	if os.args.len != 3 { panic('unexpected arguments') }
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	if os.args[1] in ['seal', 'check'] {
		checkpoint(out, os.args[1] == 'seal')!
		return
	}
	if os.exists(out + '/manifest.sha256') && os.args[1] != 'inspect' { panic('bundle is sealed') }
	verify_inputs(out)!
	match os.args[1] {
		'resume-staging' { resume_staging(root, out)! }
		'build' {
			if os.exists(out + '/run-ios-gles') { panic('runtime already built') }
			revision := os.read_file(out + '/source-revision.txt')!.trim_space()
			capture(out, 'build-source-check', ['git', 'diff', '--exit-code', revision, '--', 'compat/ios', 'tests/ios'])!
			if optional_probe(out)! {
				capture(out, 'build-init', [out + '/notification-vm', 'build-init', out])!
				capture(out, 'build-optional-fixture', [out + '/notification-vm', 'build-swift-optional-lookup', out])!
				if session_defaults_probe(out)! { capture(out, 'build-default-session-fixture', [out + '/notification-vm', 'build-session-defaults', out])! }
			}
			capture(out, 'build-runtime', [out + '/notification-vm', 'build-run-ios-gles', out])!
			capture(out, 'built-source-check', ['git', 'diff', '--exit-code', revision, '--', 'compat/ios', 'tests/ios'])!
			if optional_probe(out)! {
				mut hashes := []string{}
				for path in required_built_paths(out)! {
					hashes << digest(out + '/' + path)! + '  ' + path
				}
				os.write_file(out + '/built-inputs.sha256', hashes.join('\n') + '\n')!
			}
		}
		'probe' {
			if os.exists(out + '/probe-no-ads-state.txt') { panic('probe already recorded') }
			verify_built(out)!
			// Staging briefly retains both cooked resources and their archive.
			// Keep headroom for the boot image and failure logs as well.
			// The frozen V os.disk_usage implementation frees its path argument.
			// Give it an owned copy so later process arguments keep their bytes.
			available := os.disk_usage(out.clone())!.available
			if available < u64(8) * 1024 * 1024 * 1024 {
				panic('Swift probe needs at least 8 GiB free before staging; available bytes: ' + available.str())
			}
			for key, value in {'VINIX_IOS_VM_CPUS': '1', 'VINIX_IOS_KERNEL': out + '/vinix',
				'VINIX_IOS_PROBE_MEMORY_MAX': '2147483648', 'VINIX_IOS_VM_GZIP_LEVEL': '1',
				'VINIX_IOS_PROBE_DESKTOP': '1', 'VINIX_IOS_STORYBOARD_BUNDLE': out + '/application',
				'VINIX_IOS_COOKED_BUNDLE': out + '/resources'} { os.setenv(key, value, true) }
			capture(out, 'probe-no-ads', [out + '/notification-vm', 'probe-no-ads', out])!
			inspect(out)!
		}
		'inspect' { inspect(out)! }
		else { panic('unknown mode') }
	}
}
