// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the complete sealed dictionary checkpoint; replace only its runtime.
module main

import crypto.sha256
import frozenv
import os

const parent_manifest = 'c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb'

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1048576}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn capture(log string, args []string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	frozenv.configure(mut p, args[0])!
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output)!
	os.write_file(log + '.status.txt', code.str() + '\n')!
	if code != 0 { return error('failed command; see ' + log + '.log') }
	println(os.file_name(log) + ': PASS')
}

fn verify_parent(parent string) ! {
	if digest(parent + '/manifest.sha256')! != parent_manifest { return error('wrong parent checkpoint') }
	mut expected := map[string]string{}
	for line in os.read_lines(parent + '/manifest.sha256')! {
		if line.len < 67 || line[64..66] != '  ' { return error('invalid parent manifest') }
		path := line[66..]
		if path.starts_with('/') || path.split('/').any(it in ['', '.', '..'])
			|| path.contains_any('\\\r\n\t') || path in expected || os.is_link(parent + '/' + path)
			|| digest(parent + '/' + path)! != line[..64] { return error('changed parent: ' + path) }
		expected[path] = line[..64]
	}
	if expected.len == 0 { return error('empty parent manifest') }
}

fn replace_runtime(out string, state string) ! {
	os.mkdir_all(out + '/replacement')!
	// The omission patterns also apply to newly added files. Give the new
	// source a distinct name and rename it only after skipping old members.
	os.cp(out + '/run-ios-gles', out + '/replacement/runtime-new')!
	capture(out + '/replace-runtime', ['/usr/bin/tar', '--format=ustar', '--options', 'gzip:compression-level=1',
		'-czf', state + '/replacement.tar.gz', '-s', ',^opt/ios/run-ios$,,', '-s', ',^[.]/opt/ios/run-ios$,,',
		'-s', ',^runtime-new$,./opt/ios/run-ios,',
		'@' + state + '/initramfs.tar.gz', '-C', out + '/replacement', 'runtime-new'])!
	os.rename(state + '/replacement.tar.gz', state + '/initramfs.tar.gz')!
	preflight := out + '/runtime-preflight'
	os.mkdir_all(preflight)!
	capture(out + '/runtime-preflight', ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz',
		'-C', preflight, '--fast-read', './opt/ios/run-ios'])!
	if digest(preflight + '/opt/ios/run-ios')! != digest(out + '/run-ios-gles')!
		|| !os.is_executable(preflight + '/opt/ios/run-ios') { return error('missing, changed or non-executable guest runtime') }
	capture(out + '/replace-boot-member', ['mcopy', '-o', '-i', state + '/boot.img', state + '/initramfs.tar.gz', '::/boot/initramfs.tar.gz'])!
}

fn replay(out string) ! {
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('VINIX_IOS_VM_CPUS', '1', true)
	state_name := os.file_name(os.read_file(out + '/probe-no-ads-state.txt')!.trim_space())
	if !state_name.starts_with('probe-no-ads-') || state_name.contains('/') { return error('unsafe parent VM state') }
	state := out + '/' + state_name
	os.write_file(out + '/probe-no-ads-state.txt', state + '\n')!
	replace_runtime(out, state)!
	capture(out + '/probe-no-ads', [out + '/notification-vm', 'replay-probe-no-ads', out])!
	log := os.read_file(out + '/probe-no-ads.log')!
	os.write_file(out + '/probe-no-ads.log', log + 'VM probe memory.max: 2147483648 (retained configuration; checked by the full guest-media auditor)\n')!
	capture(out + '/operation-inspect', [out + '/checkpoint', 'inspect', out])!
	println('Fresh runtime probe complete. Run the unchanged checkpoint seal/check and negative-controls before reporting qualification.')
}

fn replacement_selftest(out string) ! {
	if os.exists(out) { return error('selftest requires a fresh directory') }
	for spelling in ['opt/ios/run-ios', './opt/ios/run-ios', 'absent'] {
		path := out + '/' + if spelling == 'absent' { 'absent' } else if spelling.starts_with('.') { 'dot' } else { 'plain' }
		os.mkdir_all(path + '/old/opt/ios')!
		os.write_file(path + '/old/keep', 'unchanged')!
		os.write_file(path + '/old/opt/ios/run-ios', 'old runtime')!
		os.write_file(path + '/run-ios-gles', 'new runtime')!
		os.chmod(path + '/run-ios-gles', 0o755)!
		mut args := ['/usr/bin/tar', '-czf', path + '/initramfs.tar.gz', '-C', path + '/old', 'keep']
		if spelling != 'absent' { args << spelling }
		capture(path + '/input', args)!
		// replace_runtime also embeds the archive in FAT. Use a tiny real
		// filesystem so the regression exercises exactly the production path.
		capture(path + '/disk', ['mkfile', '-n', '16m', path + '/boot.img'])!
		capture(path + '/fat', ['mformat', '-i', path + '/boot.img', '::'])!
		capture(path + '/boot-dir', ['mmd', '-i', path + '/boot.img', '::/boot'])!
		replace_runtime(path, path)!
		listing := os.exec(['/usr/bin/tar', '-tzf', path + '/initramfs.tar.gz'])
		if listing.exit_code != 0 || listing.output.split_into_lines().filter(it == './opt/ios/run-ios' || it == 'opt/ios/run-ios').len != 1 { return error('runtime omitted or duplicated') }
		keep := os.exec(['/usr/bin/tar', '-xOzf', path + '/initramfs.tar.gz', 'keep'])
		if keep.exit_code != 0 || keep.output != 'unchanged' { return error('changed unrelated member') }
	}
	println('Runtime replacement: plain, dot-prefixed and absent prior member; exact bytes, executable permissions, unique member and unchanged content PASS')
}

fn main() {
	if os.args.len == 3 && os.args[1] == 'selftest' { replacement_selftest(os.abs_path(os.args[2]))!; return }
	if os.args.len == 4 && os.args[1] == 'recover' {
		failed := os.real_path(os.args[2])
		out := os.abs_path(os.args[3])
		root := os.real_path(os.getwd())
		if failed == root || out == root || failed.starts_with(root + '/') || out.starts_with(root + '/')
			|| os.exists(out) || out.starts_with(failed + '/') { panic('recovery needs a fresh external copy') }
		if os.read_file(failed + '/operation-inspect.status.txt')! != '1\n' { panic('expected failed staging probe') }
		if os.disk_usage(os.dir(out).clone())!.available < u64(12) * 1024 * 1024 * 1024 { panic('recovery and full media audit need 12 GiB free') }
		capture(out + '-copy', ['/bin/cp', '-Rp', failed, out])!
		os.write_file(out + '/failed-staging-bundle.txt', failed + '\n')!
		os.cp(os.executable(), out + '/storekit-operation-probe')!
		os.cp(root + '/tests/ios/storekit-operation-probe.v', out + '/storekit-operation-probe.v')!
		revision := os.exec(['git', 'rev-parse', 'HEAD'])
		if revision.exit_code != 0 { panic(revision.output) }
		os.write_file(out + '/staging-revision.txt', revision.output)!
		capture(out + '/staging-source-check', ['git', 'diff', '--exit-code', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
		capture(out + '/staging-source-snapshot', ['git', 'archive', '--format=tar', '--output=' + out + '/staging-source.tar', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
		replay(out)!
		return
	}
	if os.args.len != 4 { panic('usage: storekit-operation-probe COMPLETE_PARENT FRESH_EXTERNAL_OUT FRESH_STOREKIT_HOST') }
	root := os.real_path(os.getwd())
	parent := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	host := os.real_path(os.args[3])
	if [parent, out, host].any(it == root || it.starts_with(root + '/'))
		|| os.exists(out) || os.is_link(out) || out.starts_with(parent + '/') || out.starts_with(host + '/') {
		panic('requires external evidence and a fresh independent output directory')
	}
	verify_parent(parent)!
	// An APFS clone preserves the entire parent while sharing unchanged extents.
	// Fail rather than silently making a space-consuming ordinary copy.
	if os.disk_usage(os.dir(out).clone())!.available < u64(8) * 1024 * 1024 * 1024 {
		panic('runtime replacement and its full media audit need at least 8 GiB free')
	}
	capture(out + '-clone', ['/bin/cp', '-cRp', parent, out])!
	os.rename(out + '/manifest.sha256', out + '/parent-manifest.sha256')!
	os.write_file(out + '/parent-bundle.txt', parent + '\n' + parent_manifest + '\n')!
	os.cp(os.executable(), out + '/storekit-operation-probe')!
	os.cp(root + '/tests/ios/storekit-operation-probe.v', out + '/storekit-operation-probe.v')!
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
		if os.read_file(host + '/' + label + '.status.txt')! != '0\n' { panic('failed fresh StoreKit host step') }
	}
	capture(out + '/copy-storekit-host', ['/bin/cp', '-Rp', host, out + '/host/storekit-operation-host'])!
	previous := os.read_file(out + '/source-revision.txt')!
	os.write_file(out + '/reused-fixture-revision.txt', previous)!
	revision := os.exec(['git', 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { panic(revision.output) }
	os.write_file(out + '/source-revision.txt', revision.output)!
	os.write_file(out + '/checkpoint-revision.txt', revision.output)!
	capture(out + '/source-check', ['git', 'diff', '--exit-code', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
	capture(out + '/source-snapshot', ['git', 'archive', '--format=tar', '--output=' + out + '/source.tar', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
	os.write_file(out + '/source.sha256', digest(out + '/source.tar')! + '  source.tar\n')!
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	os.setenv('VINIX_IOS_VM_CPUS', '1', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	capture(out + '/build-runtime', [out + '/notification-vm', 'build-run-ios-gles', out])!
	capture(out + '/built-source-check', ['git', 'diff', '--exit-code', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
	mut hashes := []string{}
	for line in os.read_lines(out + '/built-inputs.sha256')! {
		path := line[66..]
		if path !in ['run-ios-gles', 'run-ios-gles.c'] && digest(out + '/' + path)! != line[..64] {
			panic('changed reused fixture or driver: ' + path)
		}
		hashes << digest(out + '/' + path)! + '  ' + path
	}
	os.write_file(out + '/built-inputs.sha256', hashes.join('\n') + '\n')!
	replay(out)!
}
