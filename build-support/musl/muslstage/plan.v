// SPDX-License-Identifier: GPL-2.0-or-later
module muslstage

import androidhost as ah

// All Python values remain borrowed: V chooses validation, ordering and inputs.
fn plan(args string, parser string, version string, retain string, source_sha string, package string, patch_directory string) !string {
	source_url := literal(ah.Value('https://musl.libc.org/releases/musl-' + text(version)! + '.tar.gz'))!
	cc_option := attribute(args, 'cc')!
	cc_text := if truth(cc_option)! {
		cc_option
	} else {
		method(attribute(constant('os')!, 'environ')!, 'get', [
			v(ah.Value('VINIX_MUSL_CC_' + text(method(attribute(args, 'arch')!, 'upper', [], {})!)!)),
			v(ah.Value(text(attribute(args, 'arch')!)! + '-linux-musl-gcc')),
		], {})!
	}
	cc := call('shlex.split', o(cc_text))!
	executable := if truth(cc)! {
		call('shutil.which', o(item(cc, v(ah.Value(0)))!))!
	} else {
		literal(none_value())!
	}
	if !truth(executable)! {
		method(parser, 'error', [v(ah.Value('target compiler missing: ' + text(call('shlex.join', o(cc))!)!))], {})!
	}
	set_item(cc, v(ah.Value(0)), o(call('str', o(method(call('Path', o(executable))!, 'resolve', [], {})!))!))!
	machine := method(invoke('subprocess.check_output', [o(add(cc, words(['-dumpmachine'])!)!)], {
		'text': v(ah.Value(true))
	})!, 'strip', [], {})!
	if !truth(method(machine, 'startswith', [o(add(attribute(args, 'arch')!, literal(ah.Value('-'))!)!)], {})!)! || !truth(call('operator.contains', o(machine), v(ah.Value('linux')))!)! {
		method(parser, 'error', [v(ah.Value('compiler target must be ' + text(attribute(args, 'arch')!)! + '-linux: ' + text(machine)!))], {})!
	}
	compiler_version := item(method(invoke('subprocess.check_output', [o(add(cc, words(['--version'])!)!)], {
		'text': v(ah.Value(true))
	})!, 'splitlines', [], {})!, v(ah.Value(0)))!
	ar := method(invoke('subprocess.check_output', [o(add(cc, words(['-print-prog-name=ar'])!)!)], {
		'text': v(ah.Value(true))
	})!, 'strip', [], {})!
	ranlib := method(invoke('subprocess.check_output', [o(add(cc, words(['-print-prog-name=ranlib'])!)!)], {
		'text': v(ah.Value(true))
	})!, 'strip', [], {})!
	support := constant('SUPPORT')!
	alpine_manifest := call('json.loads', o(method(join(div(support, patch_directory)!, 'manifest.json')!, 'read_text', [], {})!))!
	patches := collection('list', [])!
	records := iterator(alpine_manifest)!
	for {
		record := next(records)!
		if record.done { break }
		patch := div(div(support, patch_directory)!, get(record.value, 'name')!)!
		if compare('ne', read_hash('hashlib.sha512', patch)!, get(record.value, 'sha512')!)! {
			fail('Alpine musl patch checksum mismatch: ' + text(patch)!)!
		}
		append(patches, o(patch))!
	}
	append(patches, o(join(support, 'malloc-retain.patch')!))!
	extras := iterator(attribute(args, 'extra_patch')!)!
	for {
		extra := next(extras)!
		if extra.done { break }
		append(patches, o(method(method(extra.value, 'expanduser', [], {})!, 'resolve', [], {
			'strict': v(ah.Value(true))
		})!))!
	}
	names := collection('set', [])!
	patch_iterator := iterator(patches)!
	for {
		patch := next(patch_iterator)!
		if patch.done { break }
		method(names, 'add', [o(attribute(patch.value, 'name')!)], {})!
	}
	if compare('ne', call('len', o(names))!, call('len', o(patches))!)! {
		method(parser, 'error', [v(ah.Value('patch filenames must be distinct'))], {})!
	}
	patch_inputs := collection('list', [])!
	input_iterator := iterator(patches)!
	for {
		patch := next(input_iterator)!
		if patch.done { break }
		append(patch_inputs, o(collection('tuple', [attribute(patch.value, 'name')!,
			method(patch.value, 'read_bytes', [], {})!])!))!
	}
	cflags := literal(ah.Value('-fstack-protector-strong -DVINIX_MALLOC_RETAIN=' + text(retain)!))!
	mut ldflags := literal(ah.Value('-Wl,-soname,libc.musl-' + text(attribute(args, 'arch')!)! + '.so.1'))!
	max_page_size := attribute(args, 'max_page_size')!
	if !truth(call('operator.is_', o(max_page_size), v(none_value()))!)! {
		ldflags = call('operator.iadd', o(ldflags), v(ah.Value(' -Wl,-z,max-page-size=' + text(attribute(args, 'max_page_size')!)!)))!
	}
	optimization := literal(ah.Value('internal,malloc,malloc/mallocng/*.c,string'))!
	manifest_arch := attribute(args, 'arch')!
	patch_records := collection('list', [])!
	inputs := iterator(patch_inputs)!
	for {
		input := next(inputs)!
		if input.done { break }
		values := pair(input.value)!
		append(patch_records, o(invoke('builtins.dict', [], {
			'name':   o(values[0])
			'sha256': o(hash_hex(constant('hashlib.sha256')!, values[1])!)
		})!))!
	}
	manifest := invoke('builtins.dict', [], {
		'version':          o(version)
		'alpine_package':   o(package)
		'arch':             o(manifest_arch)
		'source_url':       o(source_url)
		'source_sha256':    o(source_sha)
		'patches':          o(patch_records)
		'cc':               o(cc)
		'compiler_version': o(compiler_version)
		'compiler_target':  o(machine)
		'cflags':           o(cflags)
		'ldflags':          o(ldflags)
		'optimize':         o(optimization)
		'retention':        o(call('int', o(retain))!)
	})!
	key := manifest_hash(manifest)!
	cache := method(attribute(args, 'build_dir')!, 'resolve', [], {})!
	unsafe_paths := collection('tuple', [call('Path', v(ah.Value('/')))!, constant('ROOT')!])!
	if truth(call('operator.contains', o(unsafe_paths), o(cache))!)! {
		method(parser, 'error', [v(ah.Value('unsafe build directory'))], {})!
	}
	method(cache, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	return collection('tuple', [source_url, cc, executable, machine, compiler_version, ar, ranlib,
		alpine_manifest, patches, patch_inputs, cflags, ldflags, optimization, manifest, key, cache])!
}

fn hash_hex(factory string, data string) !string {
	// The caller may retain this input (patch_inputs); release only its borrowed ID.
	hash := apply(factory, [o(data)]) or {
		cause := err
		release_error([data, factory], cause)!
		return cause
	}
	release(data, factory)!
	result := method(hash, 'hexdigest', [], {}) or {
		cause := err
		release_error([hash], cause)!
		return cause
	}
	release(hash)!
	return result
}

fn read_hash(name string, path string) !string {
	factory := constant(name)!
	data := method(path, 'read_bytes', [], {}) or {
		cause := err
		release_error([factory], cause)!
		return cause
	}
	return hash_hex(factory, data)!
}

fn manifest_hash(manifest string) !string {
	factory := constant('hashlib.sha256')!
	data := manifest_bytes(manifest) or {
		cause := err
		release_error([factory], cause)!
		return cause
	}
	return hash_hex(factory, data)!
}

fn manifest_bytes(manifest string) !string {
	return method(invoke('json.dumps', [o(manifest)], {
		'sort_keys': v(ah.Value(true))
	})!, 'encode', [], {})!
}
