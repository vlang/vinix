// SPDX-License-Identifier: GPL-2.0-or-later
module wakehost

import androidhost as ah
import json2

fn export(id string) ah.Value { return ah.Value(id) }

fn arg(args string, name string) !string { return attribute(args, name)! }

fn path_named(name string) !string {
	return method(call('Path', o(constant('__file__')!))!, 'with_name', [v(ah.Value(name))], {})!
}

fn parser_error(parser string, message string) ! {
	discard(method(parser, 'error', [v(ah.Value(message))], {})!)!
}

fn dictionary() !string { return literal(ah.Value(map[string]ah.Value{}))! }

fn as_text(id string) !string { return call('str', o(id))! }

fn pair(id string) !(string, string) {
	values := callback('unpack_pair', {
		'owner': ah.Value(id)
	})!.items()
	return values[0].text(), values[1].text()
}

fn digest(path string) !string {
	factory := constant('hashlib.sha256')!
	reader := attribute(path, 'read_bytes') or {
		release_error(err, factory)!
		return err
	}
	content := invoke_target(reader, [], {}) or {
		release_error(err, reader, factory)!
		return err
	}
	release(reader)!
	hasher := invoke_target(factory, [o(content)], {}) or {
		release_error(err, content, factory)!
		return err
	}
	release(content, factory)!
	hex := attribute(hasher, 'hexdigest') or {
		release_error(err, hasher)!
		return err
	}
	release(hasher)!
	result := invoke_target(hex, [], {}) or {
		release_error(err, hex)!
		return err
	}
	release(hex)!
	return result
}

fn public_digest(path string) !string { return call('digest', o(path))! }

fn print_json(value string) ! {
	printer := constant('print')!
	dumper := constant('json.dumps') or {
		release_error(err, printer)!
		return err
	}
	encoded := invoke_target(dumper, [o(value)], {
		'indent': v(ah.Value(2))
	}) or {
		release_error(err, dumper, printer)!
		return err
	}
	release(dumper)!
	result := invoke_target(printer, [o(encoded)], {}) or {
		release_error(err, encoded, printer)!
		return err
	}
	release(encoded, printer, result)!
}

fn write_json(path string, value string) ! {
	writer := attribute(path, 'write_text') or {
		release_error(err, path)!
		return err
	}
	release(path)!
	dumper := constant('json.dumps') or {
		release_error(err, path, writer)!
		return err
	}
	encoded := invoke_target(dumper, [o(value)], {
		'indent': v(ah.Value(2))
	}) or {
		release_error(err, dumper, writer)!
		return err
	}
	release(dumper)!
	data := add(encoded, literal(ah.Value('\n'))!) or {
		release_error(err, encoded, writer)!
		return err
	}
	release(encoded)!
	result := invoke_target(writer, [o(data)], {}) or {
		release_error(err, data, writer)!
		return err
	}
	release(data, writer, result)!
}

fn main_policy(args string, parser string) ! {
	work := method(arg(args, 'work')!, 'resolve', [], {})!
	if truth(method(work, 'exists', [], {})!)! {
		parser_error(parser, 'use a fresh --work directory to preserve earlier evidence')!
	}
	base := method(arg(args, 'base_root')!, 'resolve', [], {})!
	runtime_arg := arg(args, 'runtime_root')!
	runtime := method(if truth(runtime_arg)! {
		runtime_arg
	} else {
		join(base, 'usr/libexec/vinix-dota2/root')!
	}, 'resolve', [], {})!
	kernel_source := join(method(arg(args, 'kernel_dir')!, 'resolve', [], {})!, 'bin/vinix')!
	source := path_named('wake-op.c')!
	linker := path_named('wake-op.ld')!
	files := dictionary()!
	for row in [['bin/busybox', join(base, 'bin/busybox')!],
		['lib/ld-musl-aarch64.so.1', join(base, 'lib/ld-musl-aarch64.so.1')!],
		['usr/bin/qemu-old', method(arg(args, 'old_translator')!, 'resolve', [], {})!],
		['usr/bin/qemu-new', method(arg(args, 'new_translator')!, 'resolve', [], {})!],
		['runtime/lib/x86_64-linux-gnu/libc.so.6', join(runtime, 'lib/x86_64-linux-gnu/libc.so.6')!],
		['runtime/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2',
			join(runtime, 'lib/x86_64-linux-gnu/ld-linux-x86-64.so.2')!]] {
		set_item(files, v(ah.Value(row[0])), o(row[1]))!
	}
	preloads := literal(ah.Value([]ah.Value{}))!
	for name in ['libvinix-steam-robust.so', 'libvinix-dota2-mmap32.so'] {
		path := join(join(runtime, 'usr/lib/x86_64-linux-gnu')!, name)!
		if truth(method(path, 'is_file', [], {})!)! {
			guest := 'runtime/usr/lib/x86_64-linux-gnu/' + name
			set_item(files, v(ah.Value(guest)), o(path))!
			append(preloads, v(ah.Value('/' + guest)))!
		}
	}
	if truth(arg(args, 'signal_probe')!)! {
		guest := 'runtime/usr/lib/x86_64-linux-gnu/wake-op-signal-probe.so'
		set_item(files, v(ah.Value(guest)), o(method(arg(args, 'signal_probe')!, 'resolve', [], {})!))!
		append(preloads, v(ah.Value('/' + guest)))!
	}
	mut required := []string{}
	values := iterator(method(files, 'values', [], {})!)!
	for {
		value := next(values)!
		if value.done { break }
		required << value.value
	}
	required << kernel_source
	required << source
	required << linker
	inputs_tuple := collection('tuple', required)!
	entries := iterator(inputs_tuple)!
	for {
		path := next(entries)!
		if path.done { break }
		if !truth(method(path.value, 'is_file', [], {})!)! {
			parser_error(parser, text(add(literal(ah.Value('missing fixture input: '))!, as_text(path.value)!)!)!)!
		}
	}
	boot := join(method(arg(args, 'boot_repo')!, 'resolve', [], {})!, 'scripts/run-aarch64.sh')!
	if truth(arg(args, 'run')!)! && !truth(method(boot, 'is_file', [], {})!)! {
		parser_error(parser, text(add(literal(ah.Value('missing VM runner: '))!, as_text(boot)!)!)!)!
	}
	discard(method(work, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!)!
	binary := join(work, 'wake-op-x86_64')!
	command := collection('list', [arg(args, 'cc')!, literal(ah.Value('--target=x86_64-linux-gnu'))!,
		literal(ah.Value('-O2'))!, literal(ah.Value('-fno-pie'))!, literal(ah.Value('-no-pie'))!,
		literal(ah.Value('-fno-stack-protector'))!, literal(ah.Value('-nostdlib'))!,
		literal(ah.Value('-fuse-ld=lld'))!, literal(ah.Value('-Wl,-z,now'))!,
		literal(ah.Value('-Wl,-z,max-page-size=0x4000'))!,
		add(literal(ah.Value('-Wl,-T,'))!, as_text(linker)!)!,
		literal(ah.Value('-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2'))!,
		literal(ah.Value('-Wl,-e,_start'))!, as_text(source)!,
		as_text(join(runtime, 'lib/x86_64-linux-gnu/libc.so.6')!)!, literal(ah.Value('-o'))!,
		as_text(binary)!])!
	discard(invoke('subprocess.run', [o(command)], {
		'check': v(ah.Value(true))
	})!)!
	set_item(files, v(ah.Value('usr/bin/wake-op-x86_64')), o(binary))!
	root := join(work, 'root')!
	copy_items := iterator(method(files, 'items', [], {})!)!
	for {
		entry := next(copy_items)!
		if entry.done { break }
		name, input_path := pair(entry.value)!
		target := div(root, name)!
		discard(method(attribute(target, 'parent')!, 'mkdir', [], {
			'parents':  v(ah.Value(true))
			'exist_ok': v(ah.Value(true))
		})!)!
		discard(call('shutil.copy2', o(input_path), o(target))!)!
	}
	for name in ['etc', 'proc', 'sys', 'dev', 'tmp', 'sbin', 'runtime/lib64'] {
		discard(method(join(root, name)!, 'mkdir', [], {
			'parents':  v(ah.Value(true))
			'exist_ok': v(ah.Value(true))
		})!)!
	}
	for name in ['sh', 'sleep', 'uname'] {
		discard(method(join(join(root, 'bin')!, name)!, 'symlink_to', [v(ah.Value('busybox'))], {})!)!
	}
	discard(method(join(root, 'runtime/lib64/ld-linux-x86-64.so.2')!, 'symlink_to', [v(ah.Value('../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2'))], {})!)!
	init := join(root, 'sbin/init')!
	init_writer := attribute(init, 'write_text')!
	init_text := init_script(args, preloads) or {
		release_error(err, init_writer)!
		return err
	}
	init_written := invoke_target(init_writer, [o(init_text)], {}) or {
		release_error(err, init_text, init_writer)!
		return err
	}
	release(init_text, init_writer, init_written)!
	discard(method(init, 'chmod', [v(ah.Value(0o755))], {})!)!
	kernel := join(work, 'kernel/bin/vinix')!
	discard(method(attribute(kernel, 'parent')!, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!)!
	discard(call('shutil.copy2', o(kernel_source), o(kernel))!)!
	archive := join(work, 'initramfs.tar.gz')!
	make_archive(root, archive)!
	inputs := provenance(args, root, files, kernel, source, linker, binary, command, archive)!
	write_json(join(work, 'inputs.json')!, inputs)!
	if !truth(arg(args, 'run')!)! {
		print_json(inputs)!
		return
	}
	environment := boot_environment(work, kernel, archive)!
	boot_command := collection('list', [as_text(boot)!, literal(ah.Value('--no-build'))!,
		literal(ah.Value('--serial'))!, literal(ah.Value('--no-persist'))!,
		literal(ah.Value('--mem=2048'))!])!
	capture := call('_wake_guest', v(ah.Value('boot')), o(args), o(work), o(boot_command), o(environment))!
	transcript := item(capture, v(ah.Value(0)))!
	reaped := item(capture, v(ah.Value(1)))!
	copied := call('_wake_copy', o(inputs))!
	judge := constant('verdict')!
	byte_factory := constant('bytes')!
	data := invoke_target(byte_factory, [o(transcript)], {}) or {
		release_error(err, byte_factory, judge)!
		return err
	}
	release(byte_factory)!
	judgment := invoke_target(judge, [o(data), o(reaped)], {}) or {
		release_error(err, data, judge)!
		return err
	}
	release(data, judge)!
	result := call('_wake_merge', o(copied), o(judgment)) or {
		release_error(err, copied, judgment)!
		return err
	}
	release(copied, judgment)!
	write_json(join(work, 'results.json')!, result)!
	print_json(result)!
	if !truth(get(result, 'passed')!)! {
		callback('raise', {
			'kind': ah.Value('SystemExit')
			'args': ah.Value([v(ah.Value(1))])
		})!
	}
}

fn make_archive(root string, archive string) ! {
	opener := constant('tarfile.open')!
	format := constant('tarfile.USTAR_FORMAT') or {
		release_error(err, opener)!
		return err
	}
	manager := invoke_target(opener, [o(archive), v(ah.Value('w:gz'))], {
		'compresslevel': v(ah.Value(1))
		'format':        o(format)
	}) or {
		release_error(err, format, opener)!
		return err
	}
	release(format, opener)!
	tar := enter(manager) or {
		release_error(err, manager)!
		return err
	}
	added := method(tar, 'add', [o(root)], {
		'arcname': v(ah.Value('.'))
	}) or {
		cause := err
		suppressed := retire(manager, cause) or {
			release_error(err, manager)!
			return err
		}
		release_error(cause, manager)!
		if !suppressed { return cause }
		return
	}
	discard(added)!
	retire(manager, none) or {
		release_error(err, manager)!
		return err
	}
	release(manager)!
}

fn provenance(args string, root string, files string, kernel string, source string, linker string, binary string, command string, archive string) !string {
	inputs := dictionary()!
	for row in [['kernel_sha256', public_digest(kernel)!],
		['fixture_source_sha256', public_digest(source)!],
		['fixture_linker_sha256', public_digest(linker)!], ['fixture_runner_sha256', runner_digest()!],
		['fixture_binary_sha256', public_digest(binary)!], ['build_command', command],
		['archive_sha256', public_digest(archive)!]] {
		set_item(inputs, v(ah.Value(row[0])), o(row[1]))!
	}
	hashes := dictionary()!
	items := iterator(files)!
	for {
		name := next(items)!
		if name.done { break }
		target := constant('digest')!
		input := div(root, name.value) or {
			release_error(err, target)!
			return err
		}
		hash := invoke_target(target, [o(input)], {}) or {
			release_error(err, input, target)!
			return err
		}
		release(input, target)!
		set_item(hashes, o(name.value), o(hash))!
	}
	set_item(inputs, v(ah.Value('files')), o(hashes))!
	set_item(inputs, v(ah.Value('run_requested')), o(arg(args, 'run')!))!
	return inputs
}

fn runner_digest() !string {
	target := constant('digest')!
	path := call('Path', o(constant('__file__')!)) or {
		release_error(err, target)!
		return err
	}
	result := invoke_target(target, [o(path)], {}) or {
		release_error(err, path, target)!
		return err
	}
	release(path, target)!
	return result
}

fn boot_environment(work string, kernel string, archive string) !string {
	env := call('_wake_copy', o(constant('os.environ')!))!
	formatter := constant('str')!
	directory := attribute(attribute(kernel, 'parent')!, 'parent')!
	kernel_text := invoke_target(formatter, [o(directory)], {})!
	release(directory, formatter)!
	set_item(env, v(ah.Value('VINIX_KERNEL_DIR')), o(kernel_text))!
	set_item(env, v(ah.Value('VINIX_INITRAMFS')), o(as_text(archive)!))!
	set_item(env, v(ah.Value('VINIX_INITRAMFS_COMPRESSED')), v(ah.Value('1')))!
	set_item(env, v(ah.Value('VINIX_QEMU_ROOT_DISK')), v(ah.Value('0')))!
	environment_path(env, 'VINIX_BOOT_DISK', work, 'boot.img')!
	environment_path(env, 'VINIX_EFIVARS', work, 'efivars.fd')!
	set_item(env, v(ah.Value('VINIX_BOOT_DISK_SIZE_MB')), v(ah.Value('128')))!
	environment_path(env, 'VINIX_QEMU_PACKAGE_STORE', work, 'packages.tar')!
	for row in [
		['VINIX_QEMU_PACKAGE_PERSIST', '0'],
		['VINIX_QEMU_HOST_SOURCE', '0'],
		['VINIX_QEMU_AUDIO', 'off'],
		['VINIX_QEMU_SMP', '4'],
		['VINIX_QEMU_NETWORK', '0'],
		['VINIX_KEEP_TEMP_BOOT_DISK', '1'],
		['VINIX_QEMU_EXTRA', ''],
	] {
		set_item(env, v(ah.Value(row[0])), v(ah.Value(row[1])))!
	}
	for name in ['VINIX_QEMU_PERSIST_DISK', 'VINIX_QEMU_GUEST_INIT', 'VINIX_QEMU_OVERLAY',
		'VINIX_QEMU_MODULE_ISO', 'VINIX_QEMU_BASE_ARCHIVE', 'VINIX_QEMU_MODULE_MANIFEST',
		'VINIX_QEMU_EXTRA_MODULES', 'VINIX_BOOT_HYPRLAND', 'VINIX_UI2_SOURCE'] {
		discard(method(env, 'pop', [v(ah.Value(name)), v(ah.Value(json2.Null{}))], {})!)!
	}
	return env
}

fn environment_path(env string, name string, work string, child string) ! {
	formatter := constant('str')!
	path := join(work, child) or {
		release_error(err, formatter)!
		return err
	}
	value := invoke_target(formatter, [o(path)], {}) or {
		release_error(err, path, formatter)!
		return err
	}
	release(path, formatter)!
	set_item(env, v(ah.Value(name)), o(value))!
}

fn init_script(args string, preloads string) !string {
	prefix := '#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1 QEMU_CPU=Haswell\nexport VINIX_X86_64_ROOT=/runtime VINIX_I386_ROOT=/runtime VINIX_X86_MULTIARCH=1\nunset LD_PRELOAD LD_LIBRARY_PATH\n'
	probe := if truth(arg(args, 'signal_probe')!)! {
		'export VINIX_DOTA2_SIGNAL_PROBE=1\n'
	} else {
		''
	}
	middle := 'uname -a\nfor variant in old new; do\n    echo WAKE-OP-VARIANT-BEGIN:$variant\n    status=0\n    /usr/bin/qemu-$variant -B 0x100000000 -L /runtime \\\n        -E LD_LIBRARY_PATH=/runtime/lib/x86_64-linux-gnu:/runtime/usr/lib/x86_64-linux-gnu \\\n        -E LD_PRELOAD='
	tail := ' /usr/bin/wake-op-x86_64 || status=$?\n    echo WAKE-OP-VARIANT-EXIT:$variant:$status\ndone\necho WAKE-OP-GUEST-END\nwhile :; do sleep 60; done\n'
	return add(add(literal(ah.Value(prefix + probe + middle))!, method(literal(ah.Value(':'))!, 'join', [o(preloads)], {})!)!, literal(ah.Value(tail))!)!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items()
	op := ah.field(row, 'operation').text()
	match op {
		'digest' { return export(digest(args[0].text())!) }
		'main' { main_policy(args[0].text(), args[1].text())! }
		else { return error('unknown Wake host operation') }
	}
	return ah.Value(json2.Null{})
}
