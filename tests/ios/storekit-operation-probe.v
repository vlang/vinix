// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the complete sealed dictionary checkpoint with a fresh runtime.
// Queue mode replaces init and StoreKit; data-task mode adds its fresh fixture
// and rebuilds the VM driver so the new build target has recorded provenance.
// Resource-values mode adds a separate fixture and preserves the pinned setter fixture.
// Number mode adds the signed getter fixture without replacing unsigned coverage.
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

// Avoid copyfile's sparse-extent seeking on cross-volume APFS copies. Evidence
// needs exact bytes and permissions; regular buffered reads also bound memory.
fn stream_copy(source string, target string) ! {
	if os.exists(target) || os.is_link(target) || os.is_link(source) {
		return error('stream copy requires an absent target and no symbolic links')
	}
	mode := int(os.stat(source)!.mode) & 0o7777
	if os.is_dir(source) {
		os.mkdir(target)!
		for name in os.ls(source)! { stream_copy(source + '/' + name, target + '/' + name)! }
		os.chmod(target, mode)!
		return
	}
	if !os.is_file(source) { return error('non-regular evidence: ' + source) }
	size := os.file_size(source)
	mut input := os.open(source)!
	defer { input.close() }
	mut output := os.create(target)!
	defer { output.close() }
	mut buffer := []u8{len: 1048576}
	defer { unsafe { buffer.free() } }
	mut remaining := size
	for remaining > 0 {
		limit := int(if remaining < u64(buffer.len) { remaining } else { u64(buffer.len) })
		n := input.read(mut buffer[..limit])!
		if n == 0 { return error('source ended during stream copy') }
		mut written := 0
		for written < n {
			count := output.write(buffer[written..n])!
			if count == 0 { return error('stream copy made no write progress') }
			written += count
		}
		remaining -= u64(n)
	}
	output.close()
	if os.file_size(source) != size || os.file_size(target) != size || digest(source)! != digest(target)! {
		return error('stream copy changed evidence: ' + source)
	}
	os.chmod(target, mode)!
	if size >= 1024 * 1024 * 1024 { println('Stream copy verified: ' + os.file_name(source)) }
}

fn stream_copy_selftest(out string) ! {
	os.mkdir_all(out + '/source/nested/empty')!
	os.write_file(out + '/source/nested/small', 'exact bytes\x00\xff')!
	os.chmod(out + '/source/nested/small', 0o640)!
	os.chmod(out + '/source/nested/empty', 0o750)!
	large := out + '/source/sparse'
	mut file := os.create(large)!
	file.write_string('head')!
	file.seek(i64(2) * 1024 * 1024 * 1024 + 17, .start)!
	file.write_string('tail')!
	file.close()
	stream_copy(out + '/source', out + '/copy')!
	assert digest(large)! == digest(out + '/copy/sparse')!
	assert os.file_size(out + '/copy/sparse') == u64(2) * 1024 * 1024 * 1024 + 21
	assert os.is_dir(out + '/copy/nested/empty')
	assert int(os.stat(out + '/copy/nested/empty')!.mode) & 0o7777 == 0o750
	assert int(os.stat(out + '/copy/nested/small')!.mode) & 0o7777 == 0o640
	mut rejected := false
	stream_copy(out + '/source', out + '/copy') or { rejected = true }
	assert rejected
	os.symlink('small', out + '/source/nested/link')!
	rejected = false
	stream_copy(out + '/source/nested/link', out + '/link-copy') or { rejected = true }
	assert rejected && !os.exists(out + '/link-copy')
	// Keep the small evidence; the generated multi-GiB copy is scratch only.
	os.rm(large)!
	os.rm(out + '/copy/sparse')!
	os.rm(out + '/source/nested/link')!
	println('Stream copy: nested and empty directories, exact bytes and modes, sparse input above 2 GiB, existing target and symlink rejection PASS')
}

fn replace_runtime(out string, state string) ! {
	os.mkdir_all(out + '/replacement')!
	// The omission patterns also apply to newly added files. Give the new
	// source a distinct name and rename it only after skipping old members.
	os.cp(out + '/run-ios-gles', out + '/replacement/runtime-new')!
	mut args := ['/usr/bin/tar', '--format=ustar', '--options', 'gzip:compression-level=1',
		'-czf', state + '/replacement.tar.gz', '-s', ',^opt/ios/run-ios$,,', '-s', ',^[.]/opt/ios/run-ios$,,',
		'-s', ',^runtime-new$,./opt/ios/run-ios,']
	queue := os.exists(out + '/queue-probe.txt')
	if queue {
		for pair in [['native-init', 'init-new'], ['storekit-purchase-checks', 'storekit-new']] {
			os.cp(out + '/' + pair[0], out + '/replacement/' + pair[1])!
		}
		args << ['-s', ',^sbin/init$,,', '-s', ',^[.]/sbin/init$,,',
			'-s', ',^opt/ios/storekit-purchase-checks$,,', '-s', ',^[.]/opt/ios/storekit-purchase-checks$,,',
			'-s', ',^init-new$,./sbin/init,', '-s', ',^storekit-new$,./opt/ios/storekit-purchase-checks,']
	}
	if os.exists(out + '/data-task-probe.txt') {
		os.cp(out + '/session-data-task-checks', out + '/replacement/data-task-new')!
		args << ['-s', ',^opt/ios/session-data-task-checks$,,', '-s', ',^[.]/opt/ios/session-data-task-checks$,,',
			'-s', ',^data-task-new$,./opt/ios/session-data-task-checks,']
	}
	if os.exists(out + '/url-resource-values-probe.txt') {
		os.cp(out + '/url-resource-values-checks', out + '/replacement/url-resource-new')!
		args << ['-s', ',^opt/ios/url-resource-values-checks$,,', '-s', ',^[.]/opt/ios/url-resource-values-checks$,,',
			'-s', ',^url-resource-new$,./opt/ios/url-resource-values-checks,']
	}
	if os.exists(out + '/number-long-long-probe.txt') {
		os.cp(out + '/number-long-long-checks', out + '/replacement/number-long-new')!
		args << ['-s', ',^opt/ios/number-long-long-checks$,,', '-s', ',^[.]/opt/ios/number-long-long-checks$,,',
			'-s', ',^number-long-new$,./opt/ios/number-long-long-checks,']
	}
	args << ['@' + state + '/initramfs.tar.gz', '-C', out + '/replacement', 'runtime-new']
	if queue { args << ['init-new', 'storekit-new'] }
	if os.exists(out + '/data-task-probe.txt') { args << 'data-task-new' }
	if os.exists(out + '/url-resource-values-probe.txt') { args << 'url-resource-new' }
	if os.exists(out + '/number-long-long-probe.txt') { args << 'number-long-new' }
	capture(out + '/replace-runtime', args)!
	os.rename(state + '/replacement.tar.gz', state + '/initramfs.tar.gz')!
	preflight := out + '/runtime-preflight'
	os.mkdir_all(preflight)!
	capture(out + '/runtime-preflight', ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz',
		'-C', preflight, '--fast-read', './opt/ios/run-ios'])!
	if digest(preflight + '/opt/ios/run-ios')! != digest(out + '/run-ios-gles')!
		|| !os.is_executable(preflight + '/opt/ios/run-ios') { return error('missing, changed or non-executable guest runtime') }
	if queue { queue_media(out, state)! }
	capture(out + '/replace-boot-member', ['mcopy', '-o', '-i', state + '/boot.img', state + '/initramfs.tar.gz', '::/boot/initramfs.tar.gz'])!
}

fn queue_media(out string, state string) ! {
	preflight := out + '/runtime-preflight'
	mut pairs := [['native-init', 'sbin/init'], ['storekit-purchase-checks', 'opt/ios/storekit-purchase-checks']]
	if os.exists(out + '/data-task-probe.txt') { pairs << ['session-data-task-checks', 'opt/ios/session-data-task-checks'] }
	if os.exists(out + '/url-resource-values-probe.txt') { pairs << ['url-resource-values-checks', 'opt/ios/url-resource-values-checks'] }
	if os.exists(out + '/number-long-long-probe.txt') { pairs << ['number-long-long-checks', 'opt/ios/number-long-long-checks'] }
	mut args := ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz', '-C', preflight]
	for pair in pairs { args << './' + pair[1] }
	capture(out + '/queue-media', args)!
	for pair in pairs {
		if digest(out + '/' + pair[0])! != digest(preflight + '/' + pair[1])!
			|| !os.is_executable(preflight + '/' + pair[1]) { return error('changed supplemental guest input: ' + pair[1]) }
	}
	listing := os.exec(['/usr/bin/tar', '-tzf', state + '/initramfs.tar.gz'])
	if listing.exit_code != 0 { return error('cannot inspect supplemental guest input inventory') }
	for pair in pairs {
		member := pair[1]
		if listing.output.split_into_lines().filter(it == member || it == './' + member).len != 1 {
			return error('missing or duplicated supplemental guest input: ' + member)
		}
	}
}

fn validate_queue_results(raw string) ! {
	serial := raw.replace('\r\n', '\n')
	for marker in ['IOS-NATIVE: /opt/ios/storekit-purchase-checks wait status 0\n',
		'IOS-STOREKIT-PURCHASE:', 'IOS-STOREKIT-PURCHASE-REJECT: 276 ',
		'IOS-STOREKIT-QUEUE:', 'IOS-STOREKIT-QUEUE-REJECT: seven ',
		'IOS-STOREKIT-OBSERVERS:', 'IOS-STOREKIT-OBSERVERS-REJECT:'] {
		if serial.count(marker) != 1 { return error('missing or duplicated queue guest result: ' + marker) }
	}
}

fn validate_data_task_results(raw string) ! {
	serial := raw.replace('\r\n', '\n')
	for marker in ['IOS-NATIVE: /opt/ios/session-data-task-checks wait status 0\n',
		'IOS-SESSION-DATA-TASK:', 'IOS-SESSION-DATA-TASK-REJECT: ten '] {
		if serial.count(marker) != 1 { return error('missing or duplicated data-task guest result: ' + marker) }
	}
}

fn validate_url_resource_values_results(raw string) ! {
	serial := raw.replace('\r\n', '\n')
	for marker in ['IOS-NATIVE: /opt/ios/url-resource-values-checks wait status 0\n',
		'IOS-URL-RESOURCE-VALUES:', 'IOS-URL-RESOURCE-VALUES-REJECT: four '] {
		if serial.count(marker) != 1 { return error('missing or duplicated URL resource values guest result: ' + marker) }
	}
}

fn validate_number_long_long_results(raw string) ! {
	serial := raw.replace('\r\n', '\n')
	for marker in ['IOS-NATIVE: /opt/ios/number-long-long-checks wait status 0\n', 'IOS-NUMBER-LONG-LONG:'] {
		if serial.count(marker) != 1 { return error('missing or duplicated number long-long guest result: ' + marker) }
	}
}

fn queue_results(out string, state string) ! {
	serial := os.read_file(state + '/serial.log')!
	validate_queue_results(serial)!
	println('Supplemental fresh StoreKit guest fixture: PASS')
	if os.exists(out + '/data-task-probe.txt') {
		validate_data_task_results(serial)!
		println('Supplemental fresh suspended data-task guest fixture: PASS')
	}
	if os.exists(out + '/url-resource-values-probe.txt') {
		validate_url_resource_values_results(serial)!
		println('Fresh URL resource values guest fixture: PASS')
	}
	if os.exists(out + '/number-long-long-probe.txt') {
		validate_number_long_long_results(serial)!
		println('Fresh number long-long guest fixture: PASS')
	}
}

fn queue_results_selftest() ! {
	serial := 'IOS-NATIVE: /opt/ios/storekit-purchase-checks wait status 0\n'
		+ 'IOS-STOREKIT-PURCHASE: PASS\nIOS-STOREKIT-PURCHASE-REJECT: 276 PASS\n'
		+ 'IOS-STOREKIT-QUEUE: PASS\nIOS-STOREKIT-QUEUE-REJECT: seven PASS\n'
		+ 'IOS-STOREKIT-OBSERVERS: PASS\nIOS-STOREKIT-OBSERVERS-REJECT: PASS\n'
	validate_queue_results(serial)!
	validate_queue_results(serial.replace('\n', '\r\n'))!
	for bad in [serial.replace('wait status 0', 'wait status 1'),
		serial.replace('IOS-STOREKIT-QUEUE: PASS\n', ''),
		serial.replace('IOS-STOREKIT-OBSERVERS: PASS\n', ''), serial + serial] {
		mut rejected := false
		validate_queue_results(bad) or { rejected = true }
		assert rejected
	}
	println('Queue guest result validation: LF/CRLF accepted; failure, missing and duplicate results rejected PASS')
	tasks := 'IOS-NATIVE: /opt/ios/session-data-task-checks wait status 0\n'
		+ 'IOS-SESSION-DATA-TASK: PASS\nIOS-SESSION-DATA-TASK-REJECT: ten PASS\n'
	validate_data_task_results(tasks)!
	validate_data_task_results(tasks.replace('\n', '\r\n'))!
	for bad in [tasks.replace('wait status 0', 'wait status 1'),
		tasks.replace('IOS-SESSION-DATA-TASK: PASS\n', ''),
		tasks.replace('IOS-SESSION-DATA-TASK-REJECT: ten PASS\n', ''), tasks + tasks] {
		mut rejected := false
		validate_data_task_results(bad) or { rejected = true }
		assert rejected
	}
	println('Data-task guest result validation: LF/CRLF accepted; failure, missing and duplicate results rejected PASS')
	resources := 'IOS-NATIVE: /opt/ios/url-resource-values-checks wait status 0\n'
		+ 'IOS-URL-RESOURCE-VALUES: PASS\nIOS-URL-RESOURCE-VALUES-REJECT: four PASS\n'
	validate_url_resource_values_results(resources)!
	validate_url_resource_values_results(resources.replace('\n', '\r\n'))!
	for bad in [resources.replace('wait status 0', 'wait status 1'),
		resources.replace('IOS-URL-RESOURCE-VALUES: PASS\n', ''),
		resources.replace('IOS-URL-RESOURCE-VALUES-REJECT: four PASS\n', ''), resources + resources] {
		mut rejected := false
		validate_url_resource_values_results(bad) or { rejected = true }
		assert rejected
	}
	println('URL resource values guest result validation: LF/CRLF accepted; failure, missing and duplicate results rejected PASS')
	numbers := 'IOS-NATIVE: /opt/ios/number-long-long-checks wait status 0\nIOS-NUMBER-LONG-LONG: PASS\n'
	validate_number_long_long_results(numbers)!
	validate_number_long_long_results(numbers.replace('\n', '\r\n'))!
	for bad in [numbers.replace('wait status 0', 'wait status 1'),
		numbers.replace('IOS-NUMBER-LONG-LONG: PASS\n', ''), numbers + numbers] {
		mut rejected := false
		validate_number_long_long_results(bad) or { rejected = true }
		assert rejected
	}
	println('Number long-long guest result validation: LF/CRLF accepted; failure, missing and duplicate results rejected PASS')
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
	if os.exists(out + '/queue-probe.txt') { queue_results(out, state)! }
	println('Fresh runtime probe complete. Run the unchanged checkpoint seal/check and negative-controls before reporting qualification.')
}

fn replacement_selftest(out string) ! {
	if os.exists(out) { return error('selftest requires a fresh directory') }
	queue_results_selftest()!
	stream_copy_selftest(out + '/stream-copy')!
	for profile in ['queue', 'data-task', 'url-resource-values', 'number-long-long'] {
	for spelling in ['opt/ios/run-ios', './opt/ios/run-ios', 'absent'] {
		path := out + '/' + profile + '/' + if spelling == 'absent' { 'absent' } else if spelling.starts_with('.') { 'dot' } else { 'plain' }
		os.mkdir_all(path + '/old/opt/ios')!
		os.write_file(path + '/old/keep', 'unchanged')!
		os.write_file(path + '/old/opt/ios/url-resource-checks', 'pinned URL setter fixture')!
		os.chmod(path + '/old/opt/ios/url-resource-checks', 0o755)!
		os.write_file(path + '/old/opt/ios/number-unsigned-checks', 'pinned unsigned number fixture')!
		os.chmod(path + '/old/opt/ios/number-unsigned-checks', 0o755)!
		os.write_file(path + '/old/opt/ios/run-ios', 'old runtime')!
		os.write_file(path + '/run-ios-gles', 'new runtime')!
		os.chmod(path + '/run-ios-gles', 0o755)!
		os.mkdir_all(path + '/old/sbin')!
		os.write_file(path + '/old/sbin/init', 'old init')!
		os.write_file(path + '/native-init', 'new init')!
		os.write_file(path + '/storekit-purchase-checks', 'new StoreKit fixture')!
		for file in ['native-init', 'storekit-purchase-checks'] { os.chmod(path + '/' + file, 0o755)! }
		os.write_file(path + '/queue-probe.txt', 'selftest\n')!
		if profile != 'queue' {
			os.write_file(path + '/data-task-probe.txt', 'selftest\n')!
			os.write_file(path + '/session-data-task-checks', 'new data-task fixture')!
			os.chmod(path + '/session-data-task-checks', 0o755)!
			os.write_file(path + '/old/opt/ios/session-data-task-checks', 'old data-task fixture')!
		}
		if profile in ['url-resource-values', 'number-long-long'] {
			os.write_file(path + '/url-resource-values-probe.txt', 'selftest\n')!
			os.write_file(path + '/url-resource-values-checks', 'new URL resource fixture')!
			os.chmod(path + '/url-resource-values-checks', 0o755)!
			os.write_file(path + '/old/opt/ios/url-resource-values-checks', 'old URL resource fixture')!
		}
		if profile == 'number-long-long' {
			os.write_file(path + '/number-long-long-probe.txt', 'selftest\n')!
			os.write_file(path + '/number-long-long-checks', 'new number long-long fixture')!
			os.chmod(path + '/number-long-long-checks', 0o755)!
			os.write_file(path + '/old/opt/ios/number-long-long-checks', 'old number long-long fixture')!
		}
		mut args := ['/usr/bin/tar', '-czf', path + '/initramfs.tar.gz', '-C', path + '/old', 'keep', 'opt/ios/url-resource-checks', 'opt/ios/number-unsigned-checks',
			if spelling.starts_with('.') { './sbin/init' } else { 'sbin/init' }]
		if spelling != 'absent' { args << spelling }
		if profile != 'queue' && spelling != 'absent' {
			args << if spelling.starts_with('.') { './opt/ios/session-data-task-checks' } else { 'opt/ios/session-data-task-checks' }
		}
		if profile in ['url-resource-values', 'number-long-long'] && spelling != 'absent' {
			args << if spelling.starts_with('.') { './opt/ios/url-resource-values-checks' } else { 'opt/ios/url-resource-values-checks' }
		}
		if profile == 'number-long-long' && spelling != 'absent' {
			args << if spelling.starts_with('.') { './opt/ios/number-long-long-checks' } else { 'opt/ios/number-long-long-checks' }
		}
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
		capture(path + '/pinned-resource', ['/usr/bin/tar', '-xzf', path + '/initramfs.tar.gz', '-C', path + '/runtime-preflight', 'opt/ios/url-resource-checks'])!
		pinned := path + '/runtime-preflight/opt/ios/url-resource-checks'
		if os.read_file(pinned)! != 'pinned URL setter fixture' || !os.is_executable(pinned) { return error('changed pinned historical resource fixture') }
		capture(path + '/pinned-number', ['/usr/bin/tar', '-xzf', path + '/initramfs.tar.gz', '-C', path + '/runtime-preflight', 'opt/ios/number-unsigned-checks'])!
		pinned_number := path + '/runtime-preflight/opt/ios/number-unsigned-checks'
		if os.read_file(pinned_number)! != 'pinned unsigned number fixture' || !os.is_executable(pinned_number) { return error('changed pinned historical number fixture') }
	}
	}
	println('Runtime, init, StoreKit, data-task, URL resource and number fixture replacement: plain, dot-prefixed and absent prior members; exact bytes, executable permissions, unique members and unchanged content PASS')
}

fn main() {
	if os.args.len == 3 && os.args[1] == 'selftest' { replacement_selftest(os.abs_path(os.args[2]))!; return }
	if os.args.len == 3 && os.args[1] == 'inspect-queue' {
		out := os.real_path(os.args[2])
		state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
		if os.dir(state) != out { panic('unsafe queue state pointer') }
		queue_results(out, state)!
		return
	}
	if os.args.len == 4 && os.args[1] == 'check-queue' {
		out := os.real_path(os.args[2])
		scratch := os.abs_path(os.args[3])
		if os.exists(scratch) || scratch.starts_with(out + '/') { panic('check-queue needs fresh independent scratch') }
		os.mkdir_all(scratch)!
		capture(scratch + '/historical-check', [out + '/checkpoint', 'check', out])!
		state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
		if os.dir(state) != out { panic('unsafe queue state pointer') }
		capture(scratch + '/queue-media', ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz',
			'-C', scratch, './opt/ios/storekit-purchase-checks'])!
		if digest(out + '/storekit-purchase-checks')! != digest(scratch + '/opt/ios/storekit-purchase-checks')!
			|| !os.is_executable(scratch + '/opt/ios/storekit-purchase-checks') { panic('changed supplemental StoreKit fixture') }
		if os.exists(out + '/data-task-probe.txt') {
			capture(scratch + '/data-task-media', ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz',
				'-C', scratch, './opt/ios/session-data-task-checks'])!
			if digest(out + '/session-data-task-checks')! != digest(scratch + '/opt/ios/session-data-task-checks')!
				|| !os.is_executable(scratch + '/opt/ios/session-data-task-checks') { panic('changed supplemental data-task fixture') }
		}
		if os.exists(out + '/url-resource-values-probe.txt') {
			capture(scratch + '/url-resource-media', ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz',
				'-C', scratch, './opt/ios/url-resource-values-checks'])!
			if digest(out + '/url-resource-values-checks')! != digest(scratch + '/opt/ios/url-resource-values-checks')!
				|| !os.is_executable(scratch + '/opt/ios/url-resource-values-checks') { panic('changed URL resource values fixture') }
		}
		if os.exists(out + '/number-long-long-probe.txt') {
			capture(scratch + '/number-long-long-media', ['/usr/bin/tar', '-xzf', state + '/initramfs.tar.gz',
				'-C', scratch, './opt/ios/number-long-long-checks'])!
			if digest(out + '/number-long-long-checks')! != digest(scratch + '/opt/ios/number-long-long-checks')!
				|| !os.is_executable(scratch + '/opt/ios/number-long-long-checks') { panic('changed number long-long fixture') }
		}
		queue_results(out, state)!
		return
	}
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
	if os.args.len !in [4, 5] || (os.args.len == 5 && os.args[4] !in ['--queue-copy', '--data-task-copy', '--url-resource-values-copy', '--number-long-long-copy']) { panic('usage: storekit-operation-probe COMPLETE_PARENT FRESH_EXTERNAL_OUT FRESH_HOST [--queue-copy|--data-task-copy|--url-resource-values-copy|--number-long-long-copy]') }
	queue := os.args.len == 5
	number_long_long := queue && os.args[4] == '--number-long-long-copy'
	resource_values := queue && os.args[4] in ['--url-resource-values-copy', '--number-long-long-copy']
	data_task := queue && os.args[4] in ['--data-task-copy', '--url-resource-values-copy', '--number-long-long-copy']
	root := os.real_path(os.getwd())
	parent := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	host := os.real_path(os.args[3])
	if [parent, out, host].any(it == root || it.starts_with(root + '/'))
		|| os.exists(out) || os.is_link(out) || out.starts_with(parent + '/') || out.starts_with(host + '/') {
		panic('requires external evidence and a fresh independent output directory')
	}
	verify_parent(parent)!
	// Default mode requires an APFS clone. Queue mode explicitly permits a
	// complete cross-volume copy, for example to a guarded RAM disk.
	if os.disk_usage(os.dir(out).clone())!.available < u64(if queue { 12 } else { 8 }) * 1024 * 1024 * 1024 {
		panic('runtime replacement and its full media audit need 8 GiB free (12 GiB in queue mode)')
	}
	if queue {
		stream_copy(parent, out)!
		verify_parent(out)!
		os.write_file(out + '-clone.log', 'V stream copy: complete bytes and permissions verified\n')!
		os.write_file(out + '-clone.status.txt', '0\n')!
	} else { capture(out + '-clone', ['/bin/cp', '-cRp', parent, out])! }
	if queue { os.write_file(out + '/queue-probe.txt', 'fresh StoreKit fixture and native init; 45 reused guest fixtures\n')! }
	if data_task { os.write_file(out + '/data-task-probe.txt', 'fresh suspended data-task and StoreKit fixtures; fresh native init and VM driver; 45 reused guest fixtures\n')! }
	if resource_values { os.write_file(out + '/url-resource-values-probe.txt', 'fresh URL resources, suspended data-task and StoreKit fixtures; fresh native init and VM driver; 45 reused guest fixtures\n')! }
	if number_long_long { os.write_file(out + '/number-long-long-probe.txt', 'fresh number long-long, URL resources, suspended data-task and StoreKit fixtures; fresh native init and VM driver; 45 reused guest fixtures\n')! }
	os.rename(out + '/manifest.sha256', out + '/parent-manifest.sha256')!
	os.write_file(out + '/parent-bundle.txt', parent + '\n' + parent_manifest + '\n')!
	os.cp(os.executable(), out + '/storekit-operation-probe')!
	os.cp(root + '/tests/ios/storekit-operation-probe.v', out + '/storekit-operation-probe.v')!
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
		if os.read_file(host + '/' + label + '.status.txt')! != '0\n' { panic('failed fresh host step: ' + label) }
	}
	for label in ['host', 'host-deterministic'] {
		log := os.read_file(host + '/' + label + '.log')!
		markers := if number_long_long { ['IOS-NUMBER-LONG-LONG-NATIVE:', 'IOS-NUMBER-LONG-LONG:'] } else if resource_values { ['IOS-URL-RESOURCE-VALUES-NATIVE:', 'IOS-URL-RESOURCE-VALUES:', 'IOS-URL-RESOURCE-VALUES-REJECT: four '] } else if data_task { ['IOS-SESSION-DATA-TASK-NATIVE:', 'IOS-SESSION-DATA-TASK:', 'IOS-SESSION-DATA-TASK-REJECT: ten '] } else { ['IOS-STOREKIT-PURCHASE:', 'IOS-STOREKIT-PURCHASE-REJECT: 276 ',
			'IOS-STOREKIT-QUEUE:', 'IOS-STOREKIT-QUEUE-REJECT: seven ',
			'IOS-STOREKIT-OBSERVERS:', 'IOS-STOREKIT-OBSERVERS-REJECT:'] }
		for marker in markers {
			if log.count(marker) != 1 { panic('missing or duplicate host result: ' + marker) }
		}
		for failure in ['ERROR: AddressSanitizer', 'runtime error:', 'V panic:', '> assert '] {
			if log.contains(failure) { panic('failed host log: ' + label) }
		}
	}
	capture(out + '/copy-fresh-host', ['/bin/cp', '-Rp', host, out + '/host/' + if number_long_long { 'number-long-long-host' } else if resource_values { 'url-resource-values-host' } else if data_task { 'session-data-task-host' } else { 'storekit-operation-host' }])!
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
	if data_task {
		os.rename(out + '/notification-vm', out + '/reused-notification-vm')!
		os.cp(root + '/tests/ios/notification-vm.v', out + '/session-data-task-notification-vm.v')!
		capture(out + '/build-notification-vm', [root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v',
			'-nocache', '-gc', 'none', '-cc', 'clang', '-path', '@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules',
			'-o', out + '/notification-vm', out + '/session-data-task-notification-vm.v'])!
		os.write_file(out + '/notification-vm-revision.txt', revision.output)!
	}
	capture(out + '/build-runtime', [out + '/notification-vm', 'build-run-ios-gles', out])!
	if queue {
		capture(out + '/build-native-init', [out + '/notification-vm', 'build-init', out])!
		capture(out + '/build-storekit', [out + '/notification-vm', 'build-storekit-purchase', out])!
	}
	if data_task { capture(out + '/build-data-task', [out + '/notification-vm', 'build-session-data-task', out])! }
	if resource_values { capture(out + '/build-url-resource-values', [out + '/notification-vm', 'build-url-resource-values', out])! }
	if number_long_long { capture(out + '/build-number-long-long', [out + '/notification-vm', 'build-number-long-long', out])! }
	capture(out + '/built-source-check', ['git', 'diff', '--exit-code', revision.output.trim_space(), '--', 'compat/ios', 'tests/ios'])!
	mut hashes := []string{}
	for line in os.read_lines(out + '/built-inputs.sha256')! {
		path := line[66..]
		if path !in ['run-ios-gles', 'run-ios-gles.c'] && !(queue && path in ['native-init', 'native-init.c'])
			&& !(data_task && path == 'notification-vm')
			&& digest(out + '/' + path)! != line[..64] {
			panic('changed reused fixture or driver: ' + path)
		}
		hashes << digest(out + '/' + path)! + '  ' + path
	}
	os.write_file(out + '/built-inputs.sha256', hashes.join('\n') + '\n')!
	replay(out)!
}
