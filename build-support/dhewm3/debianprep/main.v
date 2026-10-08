module debianprep

import androidhost as ah
import boothost
import runtimebuild as rb

fn join(base ah.Value, name string) !ah.Value {
	return rb.method('acquire', base, '__truediv__', [rb.ordinary(ah.Value(name))], {})!
}

fn root() !ah.Value {
	return rb.callback('borrow_global', {
		'name': ah.Value('ROOT')
	})!
}

fn exists(path ah.Value) !bool {
	return rb.bool_object(rb.method('acquire', path, 'exists', [], {})!)!
}

fn invoke(module ah.Value, name string, arguments []ah.Value) !ah.Value {
	return rb.method('acquire', module, name, arguments, {})!
}

fn package(mapping ah.Value, name ah.Value) !ah.Value {
	return rb.method('acquire', mapping, '__getitem__', [rb.object(name)], {})!
}

fn retained(value ah.Value) !ah.Value {
	return rb.callback('retain', {
		'value': rb.ordinary(value)
	})!
}

fn kernel_dependency(meta ah.Value) !ah.Value {
	groups := rb.iter_object(rb.attribute(meta, 'dependencies', true)!)!
	for {
		group := rb.next(groups)!
		if group == rb.null() { break }
		names := rb.iter_object(group)!
		for {
			name := rb.next(names)!
			if name == rb.null() { break }
			if rb.bool_object(rb.method('acquire', name, 'startswith', [rb.ordinary(ah.Value('linux-image-'))], {})!)! {
				return name
			}
		}
	}
	return rb.callback('raise', {
		'kind': ah.Value('StopIteration')
	})!
}

fn prepare(args ah.Value) !ah.Value {
	work := rb.method('acquire', rb.attribute(args, 'output', true)!, 'resolve', [], {})!
	cache := join(work, 'downloads')!
	rb.method('invoke', cache, 'mkdir', [], {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
	archive := join(cache, 'Packages.xz')!
	if !exists(archive)! {
		temporary := rb.method('acquire', archive, 'with_suffix', [rb.ordinary(ah.Value('.part'))], {})!
		argv := ['curl', '-fL', '--retry', '3', '-o',
			rb.call('invoke', 'builtins', 'str', [rb.object(temporary)], {})!.text(),
			'https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz']
		rb.call('invoke', 'subprocess', 'run', [rb.ordinary(rb.strings(argv))], {
			'check': ah.Value(true)
		})!
		rb.method('invoke', temporary, 'replace', [rb.object(archive)], {})!
	}
	index := join(cache, 'Packages')!
	if !exists(index)! {
		data := rb.method('acquire', archive, 'read_bytes', [], {})!
		decoded := rb.call('acquire', 'lzma', 'decompress', [rb.object(data)], {})!
		rb.method('invoke', index, 'write_bytes', [rb.object(decoded)], {})!
	}
	source := join(root()!, 'build-support/debian-root.py')!
	spec := rb.call('acquire', 'importlib.util', 'spec_from_file_location', [
		rb.ordinary(ah.Value('debian_root')),
		rb.object(source),
	], {})!
	module := rb.call('acquire', 'importlib.util', 'module_from_spec', [rb.object(spec)], {})!
	modules := rb.attribute(rb.callback('borrow_global', {
		'name': ah.Value('sys')
	})!, 'modules', true)!
	rb.method('invoke', modules, '__setitem__', [
		rb.object(rb.attribute(spec, 'name', true)!),
		rb.object(module),
	], {})!
	rb.method('invoke', rb.attribute(spec, 'loader', true)!, 'exec_module', [rb.object(module)], {})!
	packages := invoke(module, 'parse_index', [rb.object(index)])!
	by_name := rb.call('acquire', 'builtins', 'dict', [], {})!
	iter := rb.iter_object(packages)!
	for {
		value := rb.next(iter)!
		if value == rb.null() { break }
		rb.method('invoke', by_name, '__setitem__', [
			rb.object(rb.attribute(value, 'name', true)!),
			rb.object(value),
		], {})!
	}
	meta := package(by_name, retained(ah.Value('linux-image-cloud-arm64'))!)!
	selected := package(by_name, kernel_dependency(meta)!)!
	kernel_root := join(work, 'root')!
	rb.method('invoke', kernel_root, 'mkdir', [], {
		'exist_ok': ah.Value(true)
	})!
	deb := invoke(module, 'download', [
		rb.ordinary(ah.Value('https://deb.debian.org/debian')),
		rb.object(selected),
		rb.object(cache),
	])!
	invoke(module, 'extract_deb', [rb.object(deb), rb.object(kernel_root)])!
	executable := rb.attribute(rb.callback('borrow_global', {
		'name': ah.Value('sys')
	})!, 'executable', false)!.text()
	argv := [executable,
		rb.call('invoke', 'builtins', 'str', [rb.object(join(root()!, 'build-support/debian-root.py')!)], {})!.text(),
		'--index', rb.call('invoke', 'builtins', 'str', [rb.object(index)], {})!.text(), '--mirror',
		'https://deb.debian.org/debian', '--cache',
		rb.call('invoke', 'builtins', 'str', [rb.object(cache)], {})!.text(), '--root',
		rb.call('invoke', 'builtins', 'str', [rb.object(join(work, 'userland')!)], {})!.text(),
		'--manifest',
		rb.call('invoke', 'builtins', 'str', [rb.object(join(work, 'packages.tsv')!)], {})!.text(),
		'base-files', 'busybox-static']
	rb.call('invoke', 'subprocess', 'run', [rb.ordinary(rb.strings(argv))], {
		'check': ah.Value(true)
	})!
	replaced := rb.method('acquire', rb.attribute(selected, 'name', true)!, 'replace', [
		rb.ordinary(ah.Value('linux-image-')),
		rb.ordinary(ah.Value('vmlinuz-')),
		rb.ordinary(ah.Value(1)),
	], {})!
	kernel := rb.method('acquire', join(kernel_root, 'boot')!, '__truediv__', [rb.object(replaced)], {})!
	if !rb.bool_object(rb.method('acquire', kernel, 'is_file', [], {})!)! {
		return boothost.PolicyError{'SystemExit', 'Debian package did not contain ' + rb.format_object(rb.attribute(kernel, 'name', true)!)!}
	}
	metadata := rb.dictionary([rb.ordinary(ah.Value('package')), rb.ordinary(ah.Value('version')),
		rb.ordinary(ah.Value('sha256')), rb.ordinary(ah.Value('image'))], [
		rb.object(rb.attribute(selected, 'name', true)!),
		rb.object(rb.attribute(selected, 'version', true)!),
		rb.object(rb.attribute(selected, 'sha256', true)!),
		rb.object(rb.call('acquire', 'builtins', 'str', [rb.object(kernel)], {})!),
	])!
	encoded := rb.call('acquire', 'json', 'dumps', [rb.object(metadata)], {
		'indent': ah.Value(2)
	})!
	text := rb.call('acquire', 'operator', 'add', [rb.object(encoded), rb.ordinary(ah.Value('\n'))], {})!
	rb.method('invoke', join(work, 'kernel.json')!, 'write_text', [rb.object(text)], {})!
	rb.callback('print', {
		'data': ah.Value('Debian kernel: ' + rb.format_object(kernel)! + '\nDebian root: ' + rb.format_object(join(work, 'userland')!)!)
	})!
	return rb.null()
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	if ah.field(row, 'operation').text() == 'main' { return prepare(rb.borrow('args')!)! }
	return error('Unknown Debian kernel preparation operation')
}
