// SPDX-License-Identifier: GPL-2.0-or-later
module lavacore

import androidhost as ah
import gapcore as gc
import json2

struct Inputs {
	libraries string
	loader string
	vulkan string
	closure string
	translator string
	kernel string
	native_cc string
	cc string
}
fn option(options string, name string) !string { return attr(options, name)! }
fn parser_error(parser string, message string) ! { method(parser, 'error', [s(message)], {})! }
fn resolve(path string) !string { return method(path, 'resolve', [], {})! }
fn validation(options string, work string, kernel_dir string, runtime string, drivers string) !Inputs {
	libraries := dict()!
	sources := call('builtins.list', o(option(options, 'control')!))!
	append(sources, o(option(options, 'fixed')!))!
	pairs := iter(call('builtins.zip', o(drivers), o(sources))!)!
	for {
		row := next(pairs)!
		if row.done { break }
		label, source := get(row.id, n(0))!, get(row.id, n(1))!
		call('operator.setitem', o(libraries), o(label), o(call('elf_input', o(source), n(62))!))!
	}
	hashes := call('builtins.set')!
	values := iter(method(libraries, 'values', [], {})!)!
	for {
		row := next(values)!
		if row.done { break }
		method(hashes, 'add', [o(get(row.id, s('sha256'))!)], {})!
	}
	if !eq(call('builtins.len', o(hashes))!, o(call('builtins.len', o(libraries))!))! {
		fail('ValueError', 'Every control must differ from the fixed driver and each other')!
	}
	loader := call('elf_input', o(join(runtime, 'lib64/ld-linux-x86-64.so.2')!), n(62))!
	vulkan := call('elf_input', o(join(runtime, 'usr/lib/x86_64-linux-gnu/libvulkan.so.1')!), n(62))!
	roots := list()!
	append(roots, o(path(get(vulkan, s('resolved_source'))!)!))!
	vals := iter(method(libraries, 'values', [], {})!)!
	for {
		row := next(vals)!
		if row.done { break }
		append(roots, o(path(get(row.id, s('resolved_source'))!)!))!
	}
	closure := call('runtime_closure', o(option(options, 'readelf')!), o(runtime), o(roots))!
	translator := call('elf_input', o(option(options, 'translator')!), n(183), n(32 * 1024 * 1024))!
	kernel := call('elf_input', o(join(kernel_dir, 'bin/vinix')!), n(183), n(64 * 1024 * 1024))!
	include := option(options, 'vulkan_include')!
	if !truth(method(join(include, 'vulkan/vulkan.h')!, 'is_file', [], {})!)! {
		fail('ValueError', 'Missing Vulkan headers: ' + format(include)!)!
	}
	for source in [runtime, kernel_dir] {
		if eq(work, o(source))! || truth(call('operator.contains', o(attr(work, 'parents')!), o(source))!)! || truth(call('operator.contains', o(attr(source, 'parents')!), o(work))!)! {
			fail('ValueError', 'Fixture must be separate from every source directory')!
		}
	}
	native_cc := call('shutil.which', o(option(options, 'native_cc')!))!
	cc := call('shutil.which', o(option(options, 'cc')!))!
	if compare('is_', native_cc, o(null_id()!))! || compare('is_', cc, o(null_id()!))! {
		fail('ValueError', 'Both native and x86 cross compilers must exist')!
	}
	return Inputs{libraries, loader, vulkan, closure, translator, kernel, native_cc, cc}
}
fn command_list(items []ah.Value) !string {
	result := list()!
	for item in items { append(result, item)! }
	return result
}
fn prepare(options string, work string, input Inputs, drivers string) !string {
	root := join(work, 'root')!
	for directory in ['sbin', 'etc', 'usr/bin', 'dev', 'proc', 'sys', 'tmp', 'root', 'runtime/icd'] { mkdir(join(root, directory)!)! }
	call('install_pin', o(input.loader), o(join(root, 'runtime/lib64/ld-linux-x86-64.so.2')!))!
	call('install_pin', o(input.vulkan), o(join(root, 'runtime/lib/libvulkan.so.1')!))!
	closures := iter(method(input.closure, 'items', [], {})!)!
	for {
		row := next(closures)!
		if row.done { break }
		name, pin := get(row.id, n(0))!, get(row.id, n(1))!
		call('install_pin', o(pin), o(call('operator.truediv', o(join(root, 'runtime/lib')!), o(name))!))!
	}
	libraries := iter(method(input.libraries, 'items', [], {})!)!
	for {
		row := next(libraries)!
		if row.done { break }
		label, pin := get(row.id, n(0))!, get(row.id, n(1))!
		name := format(label)!
		call('install_pin', o(pin), o(join(root, 'runtime/lib/libvulkan_lvp-' + name + '.so')!))!
		icd := dict()!
		set(icd, 'file_format_version', s('1.0.0'))!
		entry := dict()!
		set(entry, 'library_path', s('/runtime/lib/libvulkan_lvp-' + name + '.so'))!
		set(entry, 'api_version', s('1.3.230'))!
		set(icd, 'ICD', o(entry))!
		encoded := call('json.dumps', o(icd))!
		method(join(root, 'runtime/icd/' + name + '.json')!, 'write_text', [o(call('operator.add', o(encoded), s('\n'))!)], {})!
	}
	mut plan := ''
	di := iter(drivers)!
	for {
		driver := next(di)!
		if driver.done { break }
		mi := iter(call('MODES')!)!
		for {
			mode := next(mi)!
			if mode.done { break }
			plan += format(driver.id)! + ' ' + format(mode.id)! + '\n'
		}
	}
	method(join(root, 'etc/vinix-lavapipe-plan')!, 'write_text', [s(plan)], {})!
	call('install_pin', o(input.translator), o(join(root, 'usr/bin/qemu-x86_64')!))!
	pinned_kernel := join(work, 'kernel/bin/vinix')!
	call('install_pin', o(input.kernel), o(pinned_kernel))!
	native := join(work, 'init')!
	native_command := command_list([o(input.native_cc), s('-static'), s('-O2'), s('-Wall'), s('-Wextra'), s('-Werror'),
		o(call('builtins.str', o(join('here', 'lavapipe-native-wait.c')!))!), s('-o'), o(call('builtins.str', o(native))!)])!
	invoke('subprocess.run', [o(native_command)], {'check': v(ah.Value(true))})!
	call('shutil.copy2', o(native), o(join(root, 'sbin/init')!))!
	probe := join(work, 'lavapipe-null-sets')!
	probe_command := command_list([o(input.cc), s('--target=x86_64-linux-gnu'), s('-ffreestanding'), s('-nostdlibinc'),
		s('-I' + text(resolve(option(options, 'vulkan_include')!)!)!), s('-fPIE'), s('-pie'), s('-O2'),
		s('-fno-stack-protector'), s('-nostdlib'), s('-fuse-ld=lld'), s('-Wall'), s('-Wextra'), s('-Werror'),
		s('-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2'), s('-Wl,-e,_start'), s('-Wl,-z,now'),
		o(call('builtins.str', o(join('here', 'lavapipe-null-sets.c')!))!),
		o(get(get(input.closure, s('libc.so.6'))!, s('resolved_source'))!), o(get(input.vulkan, s('resolved_source'))!),
		s('-o'), o(call('builtins.str', o(probe))!)])!
	invoke('subprocess.run', [o(probe_command)], {'check': v(ah.Value(true))})!
	call('shutil.copy2', o(probe), o(join(root, 'usr/bin/lavapipe-null-sets')!))!
	archive := join(work, 'initramfs.tar.gz')!
	manager := invoke('tarfile.open', [o(archive), s('w:gz')], {
		'compresslevel': n(1), 'format': o(call('tarfile.USTAR_FORMAT')!)})!
	output := enter(manager)!
	method(output, 'add', [o(root)], {'arcname': s('.')}) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return provenance(options, work, input, drivers, native, native_command, probe, probe_command, archive)
	}
	retire(manager, none)!
	return provenance(options, work, input, drivers, native, native_command, probe, probe_command, archive)
}
fn provenance(options string, work string, input Inputs, drivers string, native string, native_command string, probe string, probe_command string, archive string) !string {
	environment := call('builtins.dict', o(call('os.environ')!))!
	for entry in [['VINIX_PRUNE_BUILD', '0'], ['VINIX_INITRAMFS_COMPRESSED', '1'], ['VINIX_BOOT_DISK_SIZE_MB', '512'],
		['VINIX_QEMU_HOST_SOURCE', '0'], ['VINIX_QEMU_PACKAGE_PERSIST', '0'], ['VINIX_QEMU_AUDIO', 'off'],
		['VINIX_QEMU_SMP', '4'], ['VINIX_QEMU_NETWORK', '0'], ['VINIX_QEMU_ROOT_DISK', '0']] { set(environment, entry[0], s(entry[1]))! }
	for entry in [['VINIX_KERNEL_DIR', text(attr(attr(join(work, 'kernel/bin/vinix')!, 'parent')!, 'parent')!)!],
		['VINIX_INITRAMFS', text(archive)!], ['VINIX_BOOT_DISK', text(join(work, 'boot.img')!)!],
		['VINIX_EFIVARS', text(join(work, 'efivars.fd')!)!], ['VINIX_QEMU_PACKAGE_STORE', text(join(work, 'packages.tar')!)!],
		['VINIX_QEMU_EXTRA', '-qmp unix:' + format(join(work, 'qmp.sock')!)! + ',server=on,wait=off']] {
		set(environment, entry[0], s(entry[1]))!
	}
	for inherited in ['VINIX_QEMU_PERSIST_DISK', 'VINIX_QEMU_GUEST_INIT', 'VINIX_QEMU_OVERLAY',
		'VINIX_QEMU_MODULE_ISO', 'VINIX_QEMU_BASE_ARCHIVE', 'VINIX_QEMU_MODULE_MANIFEST',
		'VINIX_QEMU_EXTRA_MODULES', 'VINIX_BOOT_HYPRLAND', 'VINIX_UI2_SOURCE'] { method(environment, 'pop', [s(inherited), v(ah.Value(json2.Null{}))], {})! }
	if !eq(call('sys.platform')!, s('darwin'))! { method(environment, 'setdefault', [s('USE_TCG'), s('1')], {})! }
	command := command_list([o(call('builtins.str', o(join('repo', 'scripts/run-aarch64.sh')!))!),
		s('--no-build'), s('--serial'), s('--no-persist'), s('--mem=' + format(option(options, 'memory_mib')!)!)])!
	report := dict()!
	set(report, 'probe_source_sha256', o(call('digest', o(join('here', 'lavapipe-null-sets.c')!))!))!
	set(report, 'native_source_sha256', o(call('digest', o(join('here', 'lavapipe-native-wait.c')!))!))!
	set(report, 'probe_ELF_sha256', o(call('digest', o(probe))!))!
	set(report, 'probe_build_command', o(probe_command))!
	set(report, 'native_init_sha256', o(call('digest', o(native))!))!
	set(report, 'native_build_command', o(native_command))!
	for entry in [['drivers', input.libraries], ['loader', input.loader], ['vulkan_loader', input.vulkan],
		['runtime_closure', input.closure], ['translator', input.translator], ['kernel', input.kernel]] { set(report, entry[0], o(entry[1]))! }
	set(report, 'modes', o(call('builtins.list', o(call('MODES')!))!))!
	set(report, 'archive_sha256', o(call('digest', o(archive))!))!
	set(report, 'guest_memory_mib', o(option(options, 'memory_mib')!))!
	set(report, 'guest_cpus', n(4))!
	set(report, 'host_timeout_seconds', o(option(options, 'timeout')!))!
	set(report, 'boot_command', o(command))!
	set(report, 'vm_started', v(ah.Value(false)))!
	set(report, 'proof_scope', s('Lavapipe compute descriptor-set binding only; no game execution.'))!
	write_json(join(work, 'provenance.json')!, report)!
	if truth(option(options, 'prepare_only')!)! { print_json(report, true)!; return report }
	specification := call('importlib.util.spec_from_file_location', s('dota2_lavapipe_boot'), o(join('repo', 'tests/kernel-gaps/run.py')!))!
	helper := call('importlib.util.module_from_spec', o(specification))!
	call('operator.setitem', o(call('sys.modules')!), o(attr(specification, 'name')!), o(helper))!
	method(attr(specification, 'loader')!, 'exec_module', [o(helper)], {})!
	status := method(helper, 'boot', [o(command), o(environment), o(work),
		v(ah.Value([ah.Value('VINIX-DOTA2-LVP-PAIR-END')])),
		v(ah.Value([ah.Value('KERNEL PANIC'), ah.Value('FATAL EXCEPTION'), ah.Value('VINIX-DOTA2-LVP-PAIR-ABORT')])),
		o(option(options, 'timeout')!)], {})!
	log := join(work, 'serial.log')!
	transcript := method(log, 'read_text', [], {'errors': s('replace')})!
	method(report, 'update', [o(call('verdict', o(transcript), o(status), o(drivers))!)], {})!
	method(report, 'update', [], {'vm_started': v(ah.Value(true)), 'host_harness_status': o(status),
		'log': o(call('builtins.str', o(log))!), 'log_sha256': o(call('digest', o(log))!)})!
	write_json(join(work, 'results.json')!, report)!
	summary := dict()!
	for key in ['passed', 'pair_completed', 'controls_reproduced', 'fixed_passed'] { set(summary, key, o(get(report, s(key))!))! }
	print_json(summary, true)!
	rows := iter(get(report, s('observations'))!)!
	for {
		row := next(rows)!
		if row.done { break }
		print_json(row.id, false)!
	}
	if !truth(get(report, s('passed'))!)! { gc.callback('raise_builtin', {'kind': ah.Value('SystemExit'), 'value': n(1)})! }
	return report
}
fn main_policy(options string, parser string) ! {
	work := resolve(option(options, 'work')!)!
	if compare('le', option(options, 'timeout')!, n(0))! || compare('lt', option(options, 'memory_mib')!, n(1024))! {
		parser_error(parser, 'timeout must be positive and the guest needs at least 1 GiB')!
	}
	if truth(method(work, 'exists', [], {})!)! {
		parser_error(parser, 'Use a fresh work directory to preserve previous evidence')!
	}
	kernel_dir := resolve(option(options, 'kernel_dir')!)!
	runtime := resolve(option(options, 'runtime_root')!)!
	drivers := list()!
	count := gc.integer(gc.call('builtins.len', o(option(options, 'control')!))!)
	for index in 1 .. count + 1 { append(drivers, s('control-' + index.str()))! }
	append(drivers, s('fixed'))!
	input := validation(options, work, kernel_dir, runtime, drivers) or {
		if gc.kind(err, 'os_error') || gc.kind(err, 'value_error') || gc.kind(err, 'called_process') {
			gc.activate(err, true)!
			parser_error(parser, err.msg())!
		}
		return err
	}
	method(work, 'mkdir', [], {'parents': v(ah.Value(true))})!
	prepare(options, work, input, drivers)!
}
