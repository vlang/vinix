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

fn verify_inputs(out string) ! {
	for line in os.read_lines(out + '/reused-inputs.sha256')! {
		if line.len < 67 || line[64..66] != '  ' || !safe_path(line[66..])
			|| digest(out + '/' + line[66..])! != line[..64] { return error('changed reused input') }
	}
}

fn prepare(out string, prior string, optional_lookup bool) ! {
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
	if optional_lookup {
		os.write_file(out + '/probe-kind.txt', 'optional-lookup\n')!
		v := os.real_path(os.getwd()) + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
		capture(out, 'build-notification-vm', [v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2',
			'-path', '@vlib|' + os.getwd() + '/compat/ios|' + os.getwd() + '/tests/ios|@vmodules',
			'-o', out + '/notification-vm', os.getwd() + '/tests/ios/notification-vm.v'])!
	}
}

fn optional_probe(out string) !bool {
	if !os.exists(out + '/probe-kind.txt') { return false }
	if os.read_file(out + '/probe-kind.txt')! != 'optional-lookup\n' { return error('unknown probe kind') }
	return true
}

fn verify_built(out string) ! {
	if !optional_probe(out)! { return }
	if os.read_file(out + '/source.sha256')! != digest(out + '/source.tar')! + '  source.tar\n' {
		return error('changed source snapshot')
	}
	mut expected := []string{}
	for path in built_paths {
		expected << digest(out + '/' + path)! + '  ' + path
	}
	if os.read_file(out + '/built-inputs.sha256')! != expected.join('\n') + '\n' {
		return error('changed or incomplete built inputs')
	}
}

fn inspect(out string) ! {
	verify_inputs(out)!
	verify_built(out)!
	optional_lookup := optional_probe(out)!
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(state) != out || !os.file_name(state).starts_with('probe-no-ads-') { return error('unsafe state') }
	serial := os.read_file(state + '/serial.log')!.replace('\r\n', '\n')
	for fixture in os.read_lines(out + '/fixtures.txt')! {
		if serial.count('IOS-NATIVE: /opt/ios/' + fixture + ' wait status 0') != 1 { return error('fixture failed: ' + fixture) }
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
	launch := os.read_file(out + '/probe-no-ads.log')!
	for marker in ['guest memory: 8192 MiB; virtual CPUs: 1', 'VM probe memory.max: 2147483648', 'VM startup limit: 1800 seconds', 'Serial capture reset before VM launch'] {
		if !launch.contains(marker) { return error('missing launch guard: ' + marker) }
	}
	diagnostic := boundaries[0] + '\n' + lines.join('\n') + '\nserial SHA-256: ' + digest(state + '/serial.log')! + '\nruntime SHA-256: ' + digest(out + '/run-ios-gles')! + '\n'
	if os.exists(out + '/manifest.sha256') {
		if os.read_file(out + '/diagnostic.txt')! != diagnostic { return error('changed diagnostic') }
	} else { os.write_file(out + '/diagnostic.txt', diagnostic)! }
	println(boundaries[0])
	for line in lines { println(line) }
	println(if optional_lookup { 'Swift Optional launch: new lookup fixture and 35 reused guest fixtures PASS; rendering unverified' }
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

fn main() {
	if os.args.len < 3 { panic('usage: swift-type-probe prepare FRESH_OUT PRIOR [--optional-lookup] | build|probe|inspect|seal|check OUT') }
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') || os.is_link(out) { panic('output must be external') }
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	if os.args[1] == 'prepare' {
		if os.args.len !in [4, 5] || (os.args.len == 5 && os.args[4] != '--optional-lookup') { panic('prepare requires PRIOR [--optional-lookup]') }
		prepare(out, os.real_path(os.args[3]), os.args.len == 5)!
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
		'build' {
			if os.exists(out + '/run-ios-gles') { panic('runtime already built') }
			revision := os.read_file(out + '/source-revision.txt')!.trim_space()
			capture(out, 'build-source-check', ['git', 'diff', '--exit-code', revision, '--', 'compat/ios', 'tests/ios'])!
			if optional_probe(out)! {
				capture(out, 'build-init', [out + '/notification-vm', 'build-init', out])!
				capture(out, 'build-optional-fixture', [out + '/notification-vm', 'build-swift-optional-lookup', out])!
			}
			capture(out, 'build-runtime', [out + '/notification-vm', 'build-run-ios-gles', out])!
			capture(out, 'built-source-check', ['git', 'diff', '--exit-code', revision, '--', 'compat/ios', 'tests/ios'])!
			if optional_probe(out)! {
				mut hashes := []string{}
				for path in built_paths {
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
			available := os.disk_usage(out)!.available
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
