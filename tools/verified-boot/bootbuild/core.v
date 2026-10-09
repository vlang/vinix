// SPDX-License-Identifier: GPL-2.0-or-later
module bootbuild

import androidhost as ah

fn target(id string, args []string) !string {
	return callback('function', {
		'call': ah.Value(true)
		'target': ah.Value(id)
		'args': ah.Value(args.map(o(it)))
	})!.text()
}

fn matches(err IError, kind string) !bool {
	return callback('exception_matches', {
		'error': detail(err)
		'class': ah.Value(kind)
	})! as bool
}

fn root_call(function string, args []string) !string {
	return target(function, args) or {
		if !matches(err, constant('verity.InvalidImage')!)! { return err }
		cause := err
		callback('active_error', {'error': detail(cause)})!
		object := callback('error_object', {'error': detail(cause)})!.text()
		callback('raise', {
			'kind': ah.Value('InvalidBundle')
			'args': ah.Value([o(call('str', o(object))!)])
			'cause': detail(cause)
			'direct_cause': ah.Value(true)
		})!
		return null()!
	}
}

fn command(args string) ! {
	invoke('subprocess.run', [o(args)], {
		'check': v(ah.Value(true))
		'stdin': o(constant('subprocess.DEVNULL')!)
	})!
}

fn sign_image(source string, destination string, key string, certificate string, backend string) ! {
	mut args := []string{}
	if compare('eq', backend, literal(ah.Value('sbsign'))!)! {
		args = [literal(ah.Value('sbsign'))!, literal(ah.Value('--key'))!, call('str', o(key))!,
			literal(ah.Value('--cert'))!, call('str', o(certificate))!, literal(ah.Value('--output'))!,
			call('str', o(destination))!, call('str', o(source))!]
	} else {
		args = [literal(ah.Value('osslsigncode'))!, literal(ah.Value('sign'))!, literal(ah.Value('-h'))!,
			literal(ah.Value('sha256'))!, literal(ah.Value('-certs'))!, call('str', o(certificate))!,
			literal(ah.Value('-key'))!, call('str', o(key))!, literal(ah.Value('-in'))!, call('str', o(source))!,
			literal(ah.Value('-out'))!, call('str', o(destination))!]
	}
	call('command', o(collection('list', args)!))!
}

fn verify_signature(loader string, certificate string, backend string) ! {
	mut args := []string{}
	if compare('eq', backend, literal(ah.Value('sbsign'))!)! {
		args = [literal(ah.Value('sbverify'))!, literal(ah.Value('--cert'))!, call('str', o(certificate))!,
			call('str', o(loader))!]
	} else {
		args = [literal(ah.Value('osslsigncode'))!, literal(ah.Value('verify'))!, literal(ah.Value('-CAfile'))!,
			call('str', o(certificate))!, literal(ah.Value('-in'))!, call('str', o(loader))!]
	}
	call('command', o(collection('list', args)!))!
}

fn index(value string, n int) !string { return item(value, v(ah.Value(n)))! }

fn unpack_pair(value string) ![]string {
	return callback('unpack_pair', {'owner': ah.Value(value)})!.items().map(it.text())
}

fn invalid(message string) ! { failure('InvalidBundle', [v(ah.Value(message))])! }

fn slice(value string, start string, end string) !string {
	return item(value, o(call('builtins.slice', o(start), o(end))!))!
}

fn regex(name string, pattern string, text string) !string {
	return call('re.' + name, v(ah.Value(pattern)), o(text), o(constant('re.M')!))!
}

fn verify_bundle(bundle_arg string, arch string, certificate string, backend string, developer string) ! {
	bundle := method(bundle_arg, 'resolve', [], {})!
	files := call('set')!
	paths := iterator(method(bundle, 'rglob', [v(ah.Value('*'))], {})!)!
	for {
		path := next(paths)!
		if path.done { break }
		if truth(method(path.value, 'is_symlink', [], {})!)! || !(truth(method(path.value, 'is_file', [], {})!)! || truth(method(path.value, 'is_dir', [], {})!)!) {
			invalid('bundle contains a symlink or special file: ' + text(path.value)!)!
		}
		if truth(method(path.value, 'is_file', [], {})!)! {
			method(files, 'add', [o(method(method(path.value, 'relative_to', [o(bundle)], {})!, 'as_posix', [], {})!)], {})!
		}
	}
	loader_relative := literal(ah.Value('EFI/BOOT/' + text(index(item(constant('ARCHES')!, o(arch))!, 2)!)!))!
	loader := call('regular_file', o(call('operator.truediv', o(bundle), o(loader_relative))!))!
	data := method(loader, 'read_bytes', [], {})!
	pe := unpack_pair(call('pe_info', o(data), o(arch))!)!
	field := pe[0]
	signature_size := pe[1]
	if truth(developer)! {
		if truth(signature_size)! { invalid('developer bundle unexpectedly contains a PE signature')! }
	} else {
		if compare('is_', certificate, null()!)! || !truth(signature_size)! {
			invalid('signed mode requires a signature and a separately trusted certificate')!
		}
		call('verify_signature', o(loader), o(method(certificate, 'resolve', [], {})!), o(backend))!
	}
	config := call('regular_file', o(join(bundle, 'boot/limine.conf')!))!
	enrolled := slice(data, field, add(field, literal(ah.Value(128))!)!)!
	if compare('ne', method(method(enrolled, 'decode', [], {})!, 'lower', [], {})!, call('digest', o(config))!)! {
		invalid('configuration differs from the hash enrolled in the loader')!
	}
	content := method(config, 'read_text', [], {'encoding': v(ah.Value('ascii'))})!
	kernel_match := regex('search', '^    path: boot\\(\\):/boot/vinix#([0-9a-f]{128})$', content)!
	modules := regex('findall', '^    module_path: boot\\(\\):/boot/root-([0-9]+)\\.tar#([0-9a-f]{128})$', content)!
	cmdline_match := regex('search', '^    cmdline: (.*)$', content)!
	dtb := regex('search', '^    dtb_path: boot\\(\\):/boot/platform\\.dtb#([0-9a-f]{128})$', content)!
	if !truth(kernel_match)! || !truth(modules)! || !truth(cmdline_match)! { invalid('configuration is not a verified initramfs profile')! }
	indices := call('builtins.list')!
	entries := iterator(modules)!
	for {
		entry := next(entries)!
		if entry.done { break }
		pair := unpack_pair(entry.value)!
		append(indices, o(pair[0]))!
	}
	expected_indices := call('builtins.list')!
	range := iterator(call('range', o(call('len', o(modules))!))!)!
	for {
		value := next(range)!
		if value.done { break }
		append(expected_indices, o(call('str', o(value.value))!))!
	}
	if compare('ne', indices, expected_indices)! { invalid('initramfs modules must have consecutive indexes')! }
	root_tokens := call('builtins.list')!
	tokens := iterator(method(index(cmdline_match, 1)!, 'split', [], {})!)!
	for {
		token := next(tokens)!
		if token.done { break }
		if truth(method(token.value, 'startswith', [o(constant('verity.TOKEN_PREFIX')!)], {})!)! { append(root_tokens, o(token.value))! }
	}
	if compare('gt', call('len', o(root_tokens))!, literal(ah.Value(1))!)! { invalid('duplicate verified-root command-line policy')! }
	root_token := if truth(root_tokens)! { index(root_tokens, 0)! } else { null()! }
	module_hashes := call('builtins.list')!
	module_entries := iterator(modules)!
	for {
		entry := next(module_entries)!
		if entry.done { break }
		pair := unpack_pair(entry.value)!
		append(module_hashes, o(pair[1]))!
	}
	dtb_hash := if truth(dtb)! { index(dtb, 1)! } else { null()! }
	expected := call('config_text', o(index(kernel_match, 1)!), o(module_hashes), o(index(cmdline_match, 1)!), o(dtb_hash), o(root_token))!
	if compare('ne', content, expected)! { invalid('unexpected configuration directive or command line')! }
	hashes := dictionary()!
	set_item(hashes, v(ah.Value('boot/vinix')), o(index(kernel_match, 1)!))!
	additions := dictionary()!
	hash_entries := iterator(modules)!
	for {
		entry := next(hash_entries)!
		if entry.done { break }
		pair := unpack_pair(entry.value)!
		set_item(additions, v(ah.Value('boot/root-' + text(pair[0])! + '.tar')), o(pair[1]))!
	}
	method(hashes, 'update', [o(additions)], {})!
	if truth(dtb)! { set_item(hashes, v(ah.Value('boot/platform.dtb')), o(index(dtb, 1)!))! }
	mut expected_values := [loader_relative, literal(ah.Value('boot/limine.conf'))!]
	hash_keys := iterator(hashes)!
	for {
		key := next(hash_keys)!
		if key.done { break }
		expected_values << key.value
	}
	expected_files := collection('set', expected_values)!
	if truth(root_token)! { method(expected_files, 'add', [v(ah.Value('boot/verity-root.img'))], {})! }
	if compare('ne', files, expected_files)! { invalid('bundle contains missing or unexpected boot files')! }
	call('check_kernel', o(join(bundle, 'boot/vinix')!), o(arch))!
	artifacts := iterator(method(hashes, 'items', [], {})!)!
	for {
		artifact := next(artifacts)!
		if artifact.done { break }
		pair := unpack_pair(artifact.value)!
		if compare('ne', call('digest', o(call('regular_file', o(call('operator.truediv', o(bundle), o(pair[0]))!))!))!, pair[1])! {
			invalid('boot artifact checksum mismatch: ' + text(pair[0])!)!
		}
	}
	if truth(root_token)! {
		parsed := call('root_call', o(constant('verity.parse_command_line')!), o(root_token))!
		parts := call('_bundle_three', o(parsed))!
		call('root_call', o(constant('verity.verify')!), o(call('regular_file', o(join(bundle, 'boot/verity-root.img')!))!), o(index(parts, 1)!), o(index(parts, 2)!))!
	}
}
