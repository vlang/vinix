// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import cachecli
import crypto.sha256
import guesthost
import hosttest
import os
import strconv

pub struct AndroidVmPlan {
pub:
	command []string
pub mut:
	environment map[string]string
}

pub fn android_arm_plan(work string, kernel_dir string, archive string) AndroidVmPlan {
	mut environment := os.environ()
	for key, value in {'VINIX_KERNEL_DIR': kernel_dir, 'VINIX_INITRAMFS': archive, 'VINIX_INITRAMFS_COMPRESSED': '1', 'VINIX_QEMU_ROOT_DISK': '0', 'VINIX_BOOT_DISK': work + '/boot.img', 'VINIX_EFIVARS': work + '/efivars.fd', 'VINIX_BOOT_DISK_SIZE_MB': '128', 'VINIX_QEMU_PACKAGE_STORE': work + '/packages.tar', 'VINIX_QEMU_PACKAGE_PERSIST': '0', 'VINIX_QEMU_HOST_SOURCE': '0', 'VINIX_QEMU_AUDIO': 'off', 'VINIX_QEMU_SMP': '2', 'VINIX_QEMU_NETWORK': '0', 'VINIX_QEMU_EXTRA': '-qmp unix:' + work + '/qmp.sock,server=on,wait=off'} { environment[key] = value }
	for key in ['VINIX_QEMU_PERSIST_DISK', 'VINIX_QEMU_GUEST_INIT', 'VINIX_QEMU_OVERLAY', 'VINIX_QEMU_MODULE_ISO', 'VINIX_QEMU_BASE_ARCHIVE', 'VINIX_QEMU_MODULE_MANIFEST', 'VINIX_QEMU_EXTRA_MODULES', 'VINIX_BOOT_HYPRLAND', 'VINIX_UI2_SOURCE'] { environment.delete(key) }
	return AndroidVmPlan{[root() + '/scripts/run-aarch64.sh', '--no-build', '--serial', '--no-persist', '--mem=1024'], environment}
}

fn android_x86_plan(work string, kernel string, archive string) !AndroidVmPlan {
	mut environment := os.environ()
	for key, value in {'VINIX_AMD64_KERNEL': kernel, 'VINIX_AMD64_INITRAMFS': archive, 'VINIX_AMD64_ISO': work + '/test.iso', 'VINIX_AMD64_ISO_BUILD_DIR': work + '/iso-build'} { environment[key] = value }
	cache := root() + '/build-amd64-iso/limine'
	if os.is_dir(cache) { copy_tree(cache, work + '/iso-build/limine', false)! }
	status := source_run([root() + '/build-support/build-amd64-iso.sh'], environment)!
	if status != 0 { return error('Android x86 image build failed: ' + status.str()) }
	qemu := os.find_abs_path_of_executable('qemu-system-x86_64')!
	firmware := os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd'
	return AndroidVmPlan{[qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', work + '/test.iso', '-display', 'none', '-monitor', 'none', '-qmp', 'unix:' + work + '/qmp.sock,server=on,wait=off', '-serial', 'mon:stdio', '-no-reboot', '-nic', 'none'], environment}
}

fn dependencies(initial []string, directories []string, readelf string, prefix string, skipped []string, mut files map[string]string) ! {
	mut pending := initial.clone(); mut seen := map[string]bool{}
	for pending.len > 0 {
		name := pending.pop()
		if name in seen { continue }
		seen[name] = true
		if name in skipped { continue }
		mut source := ''
		for directory in directories { if os.is_file(directory + '/' + name) { source = directory + '/' + name; break } }
		if source == '' { return error('Missing native dependency: ' + name) }
		files[prefix + name] = source
		pending << needed_libraries(source, readelf)!
	}
}

fn needed_libraries(source string, readelf string) ![]string {
	output := probe_command([readelf, '-d', source], true, '')!
	mut names := []string{}
	for line in output.split_into_lines() {
		start := line.index('Shared library: [') or { continue }
		rest := line[start + 'Shared library: ['.len..]
		end := rest.index(']') or { continue }
		if end > 0 { names << rest[..end] }
	}
	return names
}

fn guest_root(work string, files map[string]string, script string) !string {
	guest := work + '/root'
	for name, source in files { copy_tree(source, guest + '/' + name, false)! }
	for name in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] { posix_parents(guest + '/' + name)! }
	for name in ['sh', 'sleep', 'mount'] { os.symlink('busybox', guest + '/bin/' + name)! }
	os.write_file(guest + '/sbin/init', script)!
	os.chmod(guest + '/sbin/init', 0o755)!
	return guest
}

fn guest_archive(guest string, path string, compressed bool) ! {
	if !compressed { guesthost.archive_tree(guest, path)!; return }
	plain := path + '.plain'
	guesthost.archive_tree(guest, plain)!
	defer { os.rm(plain) or {} }
	contents := checked(['gzip', '-c', plain])!.stdout
	os.write_file_array(path, contents.bytes())!
}

pub fn runtime_vm_cli(argv []string) !int {
	args := parse_arguments(argv, ['--work', '--kernel', '--arch', '--runtime', '--native-root', '--baseline', '--timeout'], []string{}, []string{}, 0, 0, 'usage: run-runtime-vm --work NEW_DIR --kernel KERNEL [--arch aarch64|x86_64 --runtime DIR --native-root DIR --baseline C --timeout SECONDS]')!
	work := hosttest.module_resolve(required_value(args, '--work')!)!
	kernel_source := hosttest.module_resolve(required_value(args, '--kernel')!)!
	arch := args.value('--arch', 'aarch64')
	if arch !in ['aarch64', 'x86_64'] { return InputError{'unsupported runtime architecture'} }
	timeout := strconv.atoi(args.value('--timeout', '900'))!
	if os.exists(work) || os.is_link(work) || timeout <= 0 { return InputError{'use a fresh work directory and positive timeout'} }
	arm := arch == 'aarch64'
	runtime := hosttest.module_resolve(args.value('--runtime', root() + if arm { '/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64' } else { '/build-aarch64-android/staging/opt/vinix-android' }))!
	native := hosttest.module_resolve(args.value('--native-root', root() + if arm { '/build-aarch64-userland/staging' } else { '/build-amd64-userland/staging' }))!
	cc := os.getenv_opt(if arm { 'CC_ARM' } else { 'CC_X86' }) or { arch + '-linux-musl-gcc' }
	os.mkdir(work)!
	build_runtime(work + '/compat-v.so', cc, work + '/generated', if arm { 'arm64' } else { 'amd64' })!
	mut variants := ['v']
	if '--baseline' in args.options {
		copy_tree(hosttest.module_resolve(args.value('--baseline', ''))!, work + '/baseline.c', false)!
		checked([cc, '-O2', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC', '-I', root() + '/build-support/android', work + '/baseline.c', '-ldl', '-o', work + '/compat-c.so'])!
		variants = ['c', 'v']
	}
	mut probes := ['runtime-stack-probe', 'memory-probe']
	if arm { probes << ['atfork-test', 'fortify-test', 'mallinfo-test'] }
	loader_name := 'ld-musl-' + arch + '.so.1'
	mut files := map[string]string{'bin/busybox': native + '/bin/busybox', 'lib/' + loader_name: native + '/lib/' + loader_name}
	mut fixtures := map[string]ah.Value{}
	for probe in probes {
		copy_tree(root() + '/tests/android/' + probe + '.c', work + '/' + probe + '.c', false)!
		checked([cc, '-O2', '-Wall', '-Wextra', '-Werror', '-I', root() + '/build-support/android', work + '/' + probe + '.c', '-ldl', '-pthread', '-o', work + '/' + probe])!
		files['usr/bin/' + probe] = work + '/' + probe
		fixtures[probe] = ah.digest(work + '/' + probe + '.c')!
	}
	for variant in variants { files['runtime/compat-' + variant + '.so'] = work + '/compat-' + variant + '.so' }
	files['runtime/lib/' + loader_name] = runtime + '/lib/' + loader_name
	files['runtime/lib/libc.musl-' + arch + '.so.1'] = runtime + '/lib/' + loader_name
	if arm { dependencies(['libc_bio.so.0'], [runtime + '/usr/lib', runtime + '/lib'], 'aarch64-linux-musl-readelf', 'runtime/lib/', ['libc.musl-aarch64.so.1'], mut files)! }
	mut script := '#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1\nunset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\nulimit -s 32768\n'
	if !arm { script += 'exec >/dev/com1 2>&1\n' }
	mut expected := []string{}
	for variant in variants {
		script += 'echo ANDROID-RUNTIME-BEGIN:' + variant + '\n'
		for probe in probes {
			arguments := if probe == 'fortify-test' { ' /runtime/compat-' + variant + '.so /runtime/lib/libc_bio.so.0' } else if probe == 'mallinfo-test' { ' /runtime/compat-' + variant + '.so' } else { '' }
			script += 'LD_PRELOAD=/runtime/compat-' + variant + '.so /runtime/lib/' + loader_name + ' --library-path /runtime/lib /usr/bin/' + probe + arguments + '\necho ANDROID-RUNTIME-PASS:' + variant + ':' + probe + '\n'
			expected << 'ANDROID-RUNTIME-PASS:' + variant + ':' + probe
		}
	}
	script += 'echo ANDROID-RUNTIME-GUEST-END\nwhile :; do sleep 60; done\n'; expected << 'ANDROID-RUNTIME-GUEST-END'
	guest := guest_root(work, files, script)!
	kernel := work + '/kernel/bin/vinix'; copy_tree(kernel_source, kernel, false)!
	archive := work + if arm { '/initramfs.tar.gz' } else { '/initramfs.tar' }
	guest_archive(guest, archive, arm)!
	mut installed := map[string]ah.Value{}
	for name, _ in files { installed[name] = ah.digest(guest + '/' + name)! }
	mut inputs := map[string]ah.Value{'kernel_sha256': ah.Value(ah.digest(kernel)!), 'archive_sha256': ah.Value(ah.digest(archive)!), 'architecture': ah.Value(arch), 'variants': ah.Value(variants.map(ah.Value(it))), 'runner_sha256': ah.Value(ah.digest(root() + '/tests/native-android-tools/androidtools/runtime_vm.v')!), 'v_inputs_sha256': ah.Value(sha256.sum(runtime_inputs()!).hex()), 'fixture_sources': ah.Value(fixtures), 'files': ah.Value(installed)}
	write_receipt(work + '/inputs.json', ah.Value(inputs))!
	plan := if arm { android_arm_plan(work, os.dir(os.dir(kernel)), archive) } else { android_x86_plan(work, kernel, archive)! }
	status := guesthost.boot_from_cancelled(plan.command, plan.environment, work, expected, ['KERNEL PANIC', 'ANDROID-STACK-FAIL', 'ANDROID-MEMORY-FAIL', 'ANDROID-ATFORK-FAIL', 'ANDROID-FORTIFY-FAIL', 'ANDROID-MALLINFO-FAIL'], timeout, true, '', cachecli.cancelled)!
	inputs['exit_code'] = status; inputs['expected_markers'] = ah.Value(expected.map(ah.Value(it)))
	write_receipt(work + '/results.json', ah.Value(inputs))!
	return status
}
