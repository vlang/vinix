// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah
import gapcore as gc

fn global(name string) !string {
	return gc.callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn str(id string) !string { return call('builtins.str', o(id))! }

fn text_id(id string) !string { return gc.call('builtins.str', o(id))!.text() }

fn command(items []ah.Value) !string {
	result := list()!
	for item in items { append(result, item)! }
	return result
}

fn argument_error(parser string, message string) ! { method(parser, 'error', [s(message)], {})! }

fn write(path string, data string) ! { method(path, 'write_text', [o(data)], {})! }

fn runtime_inputs(root_value string) !string {
	root := method(root_value, 'resolve', [], {
		'strict': v(ah.Value(true))
	})!
	if !truth(method(root, 'is_dir', [], {})!)! {
		fail('ValueError', 'Expected a glibc root directory: ' + format(root)!)!
	}
	files := dict()!
	for row in [['libc'], ['loader']] {
		producer := call('_vm.native_iterator', o('arg1'), s('env-runtime_candidate'), o(root), s(row[0]))!
		candidate := call('builtins.next', o(producer), o(null_id()!))!
		if compare('is_', candidate, o(null_id()!))! {
			fail('ValueError', 'Missing matching glibc ' + row[0] + ' in ' + format(root)!)!
		}
		set(files, row[0], o(call('elf_input', o(candidate), n(62))!))!
	}
	result := dict()!
	set(result, 'root', o(str(root)!))!
	method(result, 'update', [o(files)], {})!
	return result
}

fn env_main(options string, parser string, work string) ! {
	kernel_dir := method(attr(options, 'kernel_dir')!, 'resolve', [], {})!
	validated := env_validate(options, work, kernel_dir) or {
		failure := err
		gc.activate(failure, true)!
		if !matches(failure, ['OSError', 'ValueError'])! { return failure }
		message := if failure is gc.BindingError && 'binding_error' in failure.value {
			text_id(gc.callback('error_object', {
				'error': ah.Value(failure.value)
			})!.text())!
		} else {
			failure.msg()
		}
		argument_error(parser, message)!
		return failure
	}
	pins, translator, kernel, native_cc, cc := validated[0], validated[1], validated[2], validated[3], validated[4]
	method(work, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
	root := join(work, 'root')!
	for directory in ['sbin', 'usr/bin', 'dev', 'proc', 'sys', 'tmp', 'root', 'opt/glibc-old/lib64',
		'opt/glibc-new/lib64'] {
		mkdir(join(root, directory)!)!
	}
	for label in ['old', 'new'] {
		destination := join(root, 'opt/glibc-' + label)!
		for row in [['libc', 'lib/libc.so.6'], ['loader', 'lib64/ld-linux-x86-64.so.2']] {
			call('install_pin', o(get(get(pins, s(label))!, s(row[0]))!), o(join(destination, row[1])!))!
		}
	}
	call('install_pin', o(translator), o(join(root, 'usr/bin/qemu-x86_64')!))!
	pinned_kernel := join(work, 'kernel/bin/vinix')!
	call('install_pin', o(kernel), o(pinned_kernel))!
	native := join(work, 'init')!
	native_command := command([o(native_cc), s('-static'), s('-O2'), s('-Wall'), s('-Wextra'),
		s('-Werror'), o(str(join(global('HERE')!, 'env-native-wait.c')!)!), s('-o'), o(str(native)!)])!
	invoke('subprocess.run', [o(native_command)], {
		'check': v(ah.Value(true))
	})!
	call('shutil.copy2', o(native), o(join(root, 'sbin/init')!))!
	build_commands := dict()!
	binary_pins := dict()!
	for label in ['old', 'new'] {
		binary := join(work, 'env-test-' + label)!
		cmd := command([o(cc), s('--target=x86_64-linux-gnu'), s('-fPIE'), s('-pie'), s('-O2'),
			s('-fno-stack-protector'), s('-nostdlib'), s('-fuse-ld=lld'), s('-Wall'), s('-Wextra'),
			s('-Werror'), s('-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2'), s('-Wl,-e,_start'),
			s('-Wl,-z,now'), o(str(join(global('HERE')!, 'env-test.c')!)!),
			o(str(join(join(root, 'opt/glibc-' + label)!, 'lib/libc.so.6')!)!), s('-o'),
			o(str(binary)!)])!
		invoke('subprocess.run', [o(cmd)], {
			'check': v(ah.Value(true))
		})!
		set(build_commands, label, o(cmd))!
		set(binary_pins, label, o(call('elf_input', o(binary), n(62))!))!
	}
	if compare('ne', get(get(binary_pins, s('old'))!, s('sha256'))!, o(get(get(binary_pins, s('new'))!, s('sha256'))!))! {
		gc.callback('raise_builtin', {
			'kind':  ah.Value('SystemExit')
			'value': s('Both libc links must produce the same test ELF')
		})!
	}
	call('shutil.copy2', o(join(work, 'env-test-old')!), o(join(root, 'usr/bin/env-test')!))!
	archive := join(work, 'initramfs.tar')!
	manager := invoke('tarfile.open', [o(archive), s('w')], {
		'format': o(call('tarfile.USTAR_FORMAT')!)
	})!
	output := enter(manager)!
	mut retired := false
	invoke_archive(output, root) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	env_finish(options, work, pinned_kernel, archive, pins, translator, kernel, native, native_command, build_commands, binary_pins)!
}

fn invoke_archive(output string, root string) ! {
	method(output, 'add', [o(root)], {
		'arcname': s('.')
	})!
}

fn env_validate(options string, work string, kernel_dir string) ![]string {
	pins := dict()!
	set(pins, 'old', o(call('runtime_inputs', o(attr(options, 'old_glibc_root')!))!))!
	set(pins, 'new', o(call('runtime_inputs', o(attr(options, 'new_glibc_root')!))!))!
	if eq(get(get(get(pins, s('old'))!, s('libc'))!, s('sha256'))!, o(get(get(get(pins, s('new'))!, s('libc'))!, s('sha256'))!))! {
		fail('ValueError', 'Old and new libc must differ for the paired control')!
	}
	translator := call('elf_input', o(attr(options, 'translator')!), n(183), n(32 * 1024 * 1024))!
	kernel := call('elf_input', o(join(kernel_dir, 'bin/vinix')!), n(183), n(64 * 1024 * 1024))!
	for source in [path(get(get(pins, s('old'))!, s('root'))!)!,
		path(get(get(pins, s('new'))!, s('root'))!)!, kernel_dir] {
		if eq(work, o(source))! || truth(call('operator.contains', o(attr(work, 'parents')!), o(source))!)! || truth(call('operator.contains', o(attr(source, 'parents')!), o(work))!)! {
			fail('ValueError', 'Fixture must be separate from every source directory')!
		}
	}
	native_cc := call('shutil.which', o(attr(options, 'native_cc')!))!
	cc := call('shutil.which', o(attr(options, 'cc')!))!
	if compare('is_', native_cc, o(null_id()!))! || compare('is_', cc, o(null_id()!))! {
		fail('ValueError', 'Both native and x86 cross compilers must exist')!
	}
	return [pins, translator, kernel, native_cc, cc]
}

fn env_finish(options string, work string, pinned_kernel string, archive string, pins string, translator string, kernel string, native string, native_command string, build_commands string, binary_pins string) ! {
	environment := call('_vm.mapping_copy', o(call('os.environ')!))!
	for row in [['VINIX_PRUNE_BUILD', '0'],
		['VINIX_KERNEL_DIR', text_id(attr(attr(pinned_kernel, 'parent')!, 'parent')!)!],
		['VINIX_INITRAMFS', text_id(archive)!], ['VINIX_BOOT_DISK', text_id(join(work, 'boot.img')!)!],
		['VINIX_BOOT_DISK_SIZE_MB', '64'], ['VINIX_EFIVARS', text_id(join(work, 'efivars.fd')!)!],
		['VINIX_QEMU_HOST_SOURCE', '0'],
		['VINIX_QEMU_PACKAGE_STORE', text_id(join(work, 'packages.tar')!)!],
		['VINIX_QEMU_PACKAGE_PERSIST', '0'], ['VINIX_QEMU_AUDIO', 'off'], ['VINIX_QEMU_SMP', '4'],
		['VINIX_QEMU_NETWORK', '0'], ['VINIX_QEMU_ROOT_DISK', '0'],
		['VINIX_QEMU_EXTRA', '-qmp unix:' + format(join(work, 'qmp.sock')!)! + ',server=on,wait=off']] {
		set(environment, row[0], s(row[1]))!
	}
	for inherited in ['VINIX_QEMU_PERSIST_DISK', 'VINIX_INITRAMFS_COMPRESSED', 'VINIX_QEMU_GUEST_INIT',
		'VINIX_QEMU_OVERLAY', 'VINIX_QEMU_MODULE_ISO', 'VINIX_QEMU_BASE_ARCHIVE',
		'VINIX_QEMU_MODULE_MANIFEST', 'VINIX_QEMU_EXTRA_MODULES', 'VINIX_BOOT_HYPRLAND',
		'VINIX_UI2_SOURCE'] {
		method(environment, 'pop', [s(inherited), o(null_id()!)], {})!
	}
	if compare('ne', call('sys.platform')!, s('darwin'))! {
		method(environment, 'setdefault', [s('USE_TCG'), s('1')], {})!
	}
	cmd := command([o(str(join(global('REPO')!, 'scripts/run-aarch64.sh')!)!), s('--no-build'),
		s('--serial'), s('--no-persist'), s('--mem=2048')])!
	report := dict()!
	for row in [
		['test_source_sha256', call('digest', o(join(global('HERE')!, 'env-test.c')!))!],
		['native_source_sha256', call('digest', o(join(global('HERE')!, 'env-native-wait.c')!))!],
		['test_ELF_sha256', get(get(binary_pins, s('old'))!, s('sha256'))!],
		['test_build_commands', build_commands],
		['native_init_sha256', call('digest', o(native))!],
		['native_build_command', native_command],
		['translator', translator],
		['kernel', kernel],
		['runtime_pins', pins],
		['archive_sha256', call('digest', o(archive))!],
	] {
		set(report, row[0], o(row[1]))!
	}
	set(report, 'guest_memory_mib', n(2048))!
	set(report, 'guest_cpus', n(4))!
	set(report, 'guest_watchdog_seconds_per_variant', n(110))!
	set(report, 'host_timeout_seconds', o(attr(options, 'timeout')!))!
	set(report, 'compatibility_preloads', o(list()!))!
	translator_environment := dict()!
	set(translator_environment, 'VINIX_ALLOW_WX', s('1'))!
	set(report, 'native_translator_environment', o(translator_environment))!
	set(report, 'boot_command', o(cmd))!
	set(report, 'vm_started', v(ah.Value(false)))!
	set(report, 'proof_scope', s('Only concurrent glibc environment synchronization; no game-root-cause claim or game execution.'))!
	write_json(join(work, 'provenance.json')!, report)!
	if truth(attr(options, 'prepare_only')!)! {
		print_json(report, true)!
		return
	}
	spec := call('importlib.util.spec_from_file_location', s('dota2_env_boot'), o(join(global('REPO')!, 'tests/kernel-gaps/run.py')!))!
	helper := call('importlib.util.module_from_spec', o(spec))!
	call('operator.setitem', o(call('sys.modules')!), o(attr(spec, 'name')!), o(helper))!
	method(attr(spec, 'loader')!, 'exec_module', [o(helper)], {})!
	status := method(helper, 'boot', [o(cmd), o(environment), o(work),
		o(command([s('VINIX-DOTA2-ENV-PAIR-END')])!),
		o(command([s('KERNEL PANIC'), s('FATAL EXCEPTION'), s('VINIX-DOTA2-ENV-PAIR-ABORT')])!),
		o(attr(options, 'timeout')!)], {})!
	log := join(work, 'serial.log')!
	method(report, 'update', [o(call('verdict', o(method(log, 'read_text', [], {
		'errors': s('replace')
	})!), o(status))!)], {})!
	method(report, 'update', [], {
		'vm_started':          v(ah.Value(true))
		'host_harness_status': o(status)
		'log':                 o(str(log)!)
		'log_sha256':          o(call('digest', o(log))!)
	})!
	write_json(join(work, 'results.json')!, report)!
	print_json(report, true)!
	if !truth(get(report, s('passed'))!)! {
		gc.callback('raise_builtin', {
			'kind':  ah.Value('SystemExit')
			'value': n(1)
		})!
	}
}

fn matches(cause IError, names []string) !bool {
	mut classes := []ah.Value{}
	for name in names { classes << o(global(name)!) }
	tuple := call('_vm.tuple_value', o(command(classes)!))!
	return gc.flag(gc.callback('exception_matches', {
		'error': gc.error_detail(cause)
		'class': ah.Value(tuple)
	})!)
}

fn runtime_candidate(root string, label string, previous string) !string {
	name := gc.call('_vm.format_value', o(label))!.text()
	alternatives := if name == 'libc' {
		['lib/x86_64-linux-gnu/libc.so.6', 'usr/lib/x86_64-linux-gnu/libc.so.6']
	} else {
		['lib64/ld-linux-x86-64.so.2', 'usr/lib64/ld-linux-x86-64.so.2',
			'lib/x86_64-linux-gnu/ld-linux-x86-64.so.2', 'usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2']
	}
	start := if compare('is_', previous, o(null_id()!))! {
		0
	} else {
		gc.call('_vm.format_value', o(call('operator.index', o(previous))!))!.text().int()
	}
	packet := dict()!
	for index := start; index < alternatives.len; index++ {
		if truth(method(join(root, alternatives[index])!, 'is_file', [], {})!)! {
			set(packet, 'position', n(index + 1))!
			set(packet, 'done', v(ah.Value(false)))!
			set(packet, 'value', o(join(root, alternatives[index])!))!
			return packet
		}
	}
	set(packet, 'position', n(alternatives.len))!
	set(packet, 'done', v(ah.Value(true)))!
	return packet
}
