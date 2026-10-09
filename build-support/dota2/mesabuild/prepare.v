// SPDX-License-Identifier: GPL-2.0-or-later
module mesabuild

import androidhost as ah

fn prepare_source(resolver string, inputs string, downloads string, source string) ! {
	archives := dictionary()!
	for key in ['source', 'debian_diff'] {
		pin := get(inputs, key)!
		package := method(resolver, 'Package', [v(ah.Value(key)), o(get(inputs, 'debian_version')!),
			v(ah.Value('source')), o(get(pin, 'filename')!), o(get(pin, 'sha256')!), v(ah.Value(0)),
			o(collection('tuple', [])!), o(collection('tuple', [])!)], {})!
		set_item(archives, v(ah.Value(key)), o(method(resolver, 'download', [
			o(get(inputs, 'mirror')!),
			o(package),
			o(downloads),
		], {})!))!
	}
	pending := renamed(source, '.pending')!
	if truth(method(pending, 'exists', [], {})!)! { call('shutil.rmtree', o(pending))! }
	method(pending, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
	command := collection('list', [call('tool', v(ah.Value('tar')))!, literal(ah.Value('xzf'))!,
		call('str', o(get(archives, 'source')!))!, literal(ah.Value('-C'))!, call('str', o(pending))!,
		literal(ah.Value('--strip-components=1'))!])!
	invoke('subprocess.run', [o(command)], {
		'check': v(ah.Value(true))
	})!
	gzip := collection('list', [call('tool', v(ah.Value('gzip')))!, literal(ah.Value('-dc'))!,
		call('str', o(get(archives, 'debian_diff')!))!])!
	patch := call('subprocess.check_output', o(gzip))!
	label := attribute(call('Path', o(get(get(inputs, 'debian_diff')!, 'filename')!))!, 'name')!
	call('apply_patch', o(pending), o(patch), o(label))!
	patches := join(pending, 'debian/patches')!
	series := call('builtins.list')!
	lines := iterator(method(method(join(patches, 'series')!, 'read_text', [], {})!, 'splitlines', [], {})!)!
	for {
		line := next(lines)!
		if line.done { break }
		if truth(method(line.value, 'strip', [], {})!)! && !truth(method(method(line.value, 'lstrip', [], {})!, 'startswith', [v(ah.Value('#'))], {})!)! {
			append(series, o(item(method(line.value, 'split', [], {})!, v(ah.Value(0)))!))!
		}
	}
	if compare('ne', series, call('list', o(get(inputs, 'debian_patches')!))!)! {
		failure('SystemExit', [v(ah.Value("Debian's Mesa patch series differs from the pinned series"))])!
	}
	names := iterator(series)!
	for {
		name := next(names)!
		if name.done { break }
		path := call('operator.truediv', o(patches), o(name.value))!
		if compare('ne', call('digest', o(path))!, item(get(inputs, 'debian_patches')!, o(name.value))!)! {
			failure('SystemExit', [v(ah.Value('Debian Mesa patch has an unexpected hash: ' + text(name.value)!))])!
		}
		call('apply_patch', o(pending), o(method(path, 'read_bytes', [], {})!), o(name.value))!
	}
	call('check_sources', o(pending), o(get(inputs, 'debian_source_sha256')!), v(ah.Value('Debian-patched')))!
	own_patches := iterator(method(get(inputs, 'patches')!, 'items', [], {})!)!
	for {
		row := next(own_patches)!
		if row.done { break }
		pair := callback('unpack_pair', {
			'owner': ah.Value(row.value)
		})!.items().map(it.text())
		path := call('operator.truediv', o(constant('SUPPORT')!), o(pair[0]))!
		if compare('ne', call('digest', o(path))!, pair[1])! {
			failure('SystemExit', [v(ah.Value('Lavapipe patch has an unexpected hash: ' + text(path)!))])!
		}
		call('apply_patch', o(pending), o(method(path, 'read_bytes', [], {})!), o(pair[0]))!
	}
	call('check_sources', o(pending), o(get(inputs, 'patched_source_sha256')!), v(ah.Value('patched')))!
	if truth(method(source, 'exists', [], {})!)! { call('shutil.rmtree', o(source))! }
	method(pending, 'rename', [o(source)], {})!
}

fn prepare_sysroot(resolver string, inputs string, base string, downloads string, sysroot string) ! {
	pending := renamed(sysroot, '.pending')!
	if truth(method(pending, 'exists', [], {})!)! { call('shutil.rmtree', o(pending))! }
	if compare('eq', constant('sys.platform')!, literal(ah.Value('darwin'))!)! {
		command := collection('list', [literal(ah.Value('/bin/cp'))!, literal(ah.Value('-cRp'))!,
			call('str', o(base))!, call('str', o(pending))!])!
		invoke('subprocess.run', [o(command)], {
			'check': v(ah.Value(true))
		})!
	} else {
		invoke('shutil.copytree', [o(base), o(pending)], {
			'symlinks': v(ah.Value(true))
		})!
	}
	packages := iterator(get(inputs, 'packages')!)!
	for {
		row := next(packages)!
		if row.done { break }
		package := method(resolver, 'Package', [o(get(row.value, 'name')!),
			o(get(row.value, 'version')!), o(get(row.value, 'architecture')!),
			o(get(row.value, 'filename')!), o(get(row.value, 'sha256')!), o(get(row.value, 'size')!),
			o(collection('tuple', [])!), o(collection('tuple', [])!)], {})!
		archive := method(resolver, 'download', [o(get(inputs, 'mirror')!), o(package), o(downloads)], {})!
		method(resolver, 'extract_deb', [o(archive), o(pending)], {})!
	}
	if truth(method(sysroot, 'exists', [], {})!)! { call('shutil.rmtree', o(sysroot))! }
	method(pending, 'rename', [o(sysroot)], {})!
}

fn verify_library(path string, base string, tools string) ! {
	header := item(method(path, 'read_bytes', [], {})!, o(call('builtins.slice', o(null()!), v(ah.Value(20)))!))!
	if !truth(call('_native_request', v(ah.Value('shared-elf')), o(header))!)! {
		failure('SystemExit', [v(ah.Value('Lavapipe must be an x86-64 shared library: ' + text(path)!))])!
	}
	command := collection('list', [call('str', o(join(tools, 'llvm-readelf')!))!,
		literal(ah.Value('-d'))!, literal(ah.Value('--dyn-syms'))!, call('str', o(path))!])!
	dynamic := invoke('subprocess.check_output', [o(command)], {
		'text': v(ah.Value(true))
	})!
	encoded := method(dynamic, 'encode', [v(ah.Value('utf-8')), v(ah.Value('surrogatepass'))], {})!
	invoke('_native_request', [v(ah.Value('verify-dynamic')), o(encoded)], {
		'base': o(call('str', o(base))!)
	})!
}
