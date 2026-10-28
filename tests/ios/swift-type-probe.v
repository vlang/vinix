// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh diagnostic launch; the preceding complete checkpoint remains unchanged.
module main

import crypto.sha256
import frozenv
import os
import strconv

const prior_hash = '8b4028c3d90c69e6b4e418820ab287eb93c8fdc4f6f0ecd10ce99346e069df09'

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

fn prepare(out string, prior string) ! {
	if os.exists(out) || os.is_link(out) { return error('prepare needs a fresh directory') }
	if digest(prior + '/manifest.sha256')! != prior_hash { return error('unexpected prior checkpoint') }
	os.mkdir_all(out)!
	os.mkdir_all(out + '/tmp')!
	os.setenv('VINIX_IOS_AUDIT_TMPDIR', out + '/tmp', true)
	capture(out, 'prior-check', [prior + '/error-description', 'check', prior])!
	os.cp(prior + '/manifest.sha256', out + '/prior-manifest.sha256')!
	os.write_file(out + '/prior-bundle.txt', prior + '\n')!
	mut paths := ['vinix', 'native-init', 'native-init.c', 'notification-vm']
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
}

fn inspect(out string) ! {
	verify_inputs(out)!
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(state) != out || !os.file_name(state).starts_with('probe-no-ads-') { return error('unsafe state') }
	serial := os.read_file(state + '/serial.log')!.replace('\r\n', '\n')
	for fixture in os.read_lines(out + '/fixtures.txt')! {
		if serial.count('IOS-NATIVE: /opt/ios/' + fixture + ' wait status 0') != 1 { return error('fixture failed: ' + fixture) }
	}
	for marker in ['iOS startup: application entry', 'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS',
		'IOS-PROBE-FAULT: signal context and restoration PASS', 'IOS-PROBE-DESKTOP: UIKit window fixture PASS',
		'V panic: iOS: unsupported Swift mangled type suffix\n', 'V panic:',
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
	lines := app.split_into_lines().filter(it.starts_with('IOS-PROBE-SWIFT-TYPE: '))
	if lines.len != 1 { return error('expected exactly one rejected type') }
	line := lines[0]
	length := strconv.parse_uint(line.all_after(' length=').all_before(' '), 10, 64)!
	copied := strconv.parse_uint(line.all_after(' copied=').all_before(' '), 10, 64)!
	bytes := line.all_after(' bytes=')
	if length == 0 || length > 1048576 || copied != if length < 64 { length } else { u64(64) }
		|| bytes.len != int(copied * 2) || bytes.bytes().any(!it.is_hex_digit()) { return error('invalid bounded diagnostic') }
	launch := os.read_file(out + '/probe-no-ads.log')!
	for marker in ['guest memory: 8192 MiB; virtual CPUs: 1', 'VM probe memory.max: 2147483648', 'VM startup limit: 1800 seconds', 'Serial capture reset before VM launch'] {
		if !launch.contains(marker) { return error('missing launch guard: ' + marker) }
	}
	os.write_file(out + '/diagnostic.txt', line + '\nserial SHA-256: ' + digest(state + '/serial.log')! + '\nruntime SHA-256: ' + digest(out + '/run-ios-gles')! + '\n')!
	println(line)
	println('Swift diagnostic launch: 35 reused guest fixtures PASS; rendering unverified')
}

fn main() {
	if os.args.len < 3 { panic('usage: swift-type-probe prepare FRESH_OUT PRIOR | build|probe|inspect OUT') }
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') || os.is_link(out) { panic('output must be external') }
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	if os.args[1] == 'prepare' {
		if os.args.len != 4 { panic('prepare requires PRIOR') }
		prepare(out, os.real_path(os.args[3]))!
		return
	}
	if os.args.len != 3 { panic('unexpected arguments') }
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	verify_inputs(out)!
	match os.args[1] {
		'build' {
			if os.exists(out + '/run-ios-gles') { panic('runtime already built') }
			revision := os.read_file(out + '/source-revision.txt')!.trim_space()
			capture(out, 'build-source-check', ['git', 'diff', '--exit-code', revision, '--', 'compat/ios', 'tests/ios'])!
			capture(out, 'build-runtime', [out + '/notification-vm', 'build-run-ios-gles', out])!
			capture(out, 'built-source-check', ['git', 'diff', '--exit-code', revision, '--', 'compat/ios', 'tests/ios'])!
		}
		'probe' {
			if os.exists(out + '/probe-no-ads-state.txt') { panic('probe already recorded') }
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
