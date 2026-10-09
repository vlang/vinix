// SPDX-License-Identifier: GPL-2.0-or-later
module bootbuild

import androidhost as ah

fn any_identity(values []string, operation string) !bool {
	iter := iterator(collection('tuple', values)!)!
	producer := call('_bundle_iterator', v(ah.Value(operation)), o(iter))!
	return truth(call('any', o(producer))!)!
}

fn identity_next(iter string, is_none bool) !string {
	value := next(iter)!
	packet := dictionary()!
	set_item(packet, v(ah.Value('done')), v(ah.Value(value.done)))!
	if value.done { return packet }
	result := compare('is_', value.value, null()!)!
	set_item(packet, v(ah.Value('value')), v(ah.Value(if is_none { result } else { !result })))!
	return packet
}

fn build_bundle(args string) ! {
	mut cmdline := call('check_cmdline', o(attribute(args, 'cmdline')!))!
	root_image := call('getattr', o(args), v(ah.Value('verity_root')), o(null()!))!
	root_device := call('getattr', o(args), v(ah.Value('verity_device')), o(null()!))!
	root_count := call('getattr', o(args), v(ah.Value('verity_data_blocks')), o(null()!))!
	root_digest := call('getattr', o(args), v(ah.Value('verity_root_hash')), o(null()!))!
	mut root_token := null()!
	values := [root_image, root_device, root_count, root_digest]
	if any_identity(values, 'nonnull_next')! {
		if any_identity(values, 'none_next')! {
			invalid('verified block root requires --verity-root, --verity-device, --verity-data-blocks and --verity-root-hash')!
		}
		root_token = call('root_call', o(constant('verity.command_line')!), o(root_device), o(root_count), o(root_digest))!
		cmdline = call('check_cmdline', o(method(literal(ah.Value(text(cmdline)! + ' ' + text(root_token)!))!, 'strip', [], {})!), o(root_token))!
	}
	output := method(attribute(args, 'output')!, 'absolute', [], {})!
	if truth(method(output, 'exists', [], {})!)! { invalid('output already exists; choose a new bundle directory')! }
	if !truth(attribute(args, 'developer_unsigned')!)! && (compare('is_', attribute(args, 'key')!, null()!)! || compare('is_', attribute(args, 'certificate')!, null()!)!) {
		invalid('signed mode requires --key and --certificate')!
	}
	if truth(attribute(args, 'developer_unsigned')!)! && (!compare('is_', attribute(args, 'key')!, null()!)! || !compare('is_', attribute(args, 'certificate')!, null()!)!) {
		invalid('developer mode cannot also specify signing credentials')!
	}
	loader_data := method(attribute(args, 'loader')!, 'read_bytes', [], {})!
	pe := unpack_pair(call('pe_info', o(loader_data), o(attribute(args, 'arch')!))!)!
	if truth(pe[1])! { invalid('loader input must be unsigned: enrollment must happen before signing')! }
	method(attribute(output, 'parent')!, 'mkdir', [], {'parents': v(ah.Value(true)), 'exist_ok': v(ah.Value(true))})!
	manager := invoke('tempfile.TemporaryDirectory', [], {
		'prefix': v(ah.Value('.vinix-verified-'))
		'dir': o(attribute(output, 'parent')!)
	})!
	temporary := enter(manager)!
	mut retired := false
	build_body(args, output, temporary, loader_data, pe[0], cmdline, root_image, root_count, root_digest, root_token) or {
		cause := err
		retired = true
		if !retire(manager, cause)! { return cause }
	}
	if !retired { retire(manager, none)! }
	mode := if truth(attribute(args, 'developer_unsigned')!)! { 'UNAUTHENTICATED developer bundle' } else { 'signed UEFI bundle' }
	call('print', v(ah.Value('Created ' + mode + ': ' + text(output)!)))!
	if !truth(attribute(args, 'developer_unsigned')!)! {
		call('print', v(ah.Value('Boot authentication requires UEFI Secure Boot enabled with this certificate trusted in firmware.')))!
	}
}

fn build_body(args string, output string, temporary string, loader_data string, field string, cmdline string, root_image string, root_count string, root_digest string, root_token string) ! {
	staging := call('Path', o(temporary))!
	boot := join(staging, 'boot')!
	efi := join(staging, 'EFI/BOOT')!
	method(boot, 'mkdir', [], {})!
	method(efi, 'mkdir', [], {'parents': v(ah.Value(true))})!
	call('shutil.copyfile', o(attribute(args, 'kernel')!), o(join(boot, 'vinix')!))!
	call('check_kernel', o(join(boot, 'vinix')!), o(attribute(args, 'arch')!))!
	entries := iterator(call('enumerate', o(attribute(args, 'initramfs')!))!)!
	for {
		entry := next(entries)!
		if entry.done { break }
		pair := unpack_pair(entry.value)!
		call('shutil.copyfile', o(pair[1]), o(join(boot, 'root-' + text(pair[0])! + '.tar')!))!
	}
	if truth(root_image)! {
		call('shutil.copyfile', o(root_image), o(join(boot, 'verity-root.img')!))!
		call('root_call', o(constant('verity.verify')!), o(join(boot, 'verity-root.img')!), o(root_count), o(root_digest))!
	}
	mut dtb_hash := null()!
	if truth(attribute(args, 'dtb')!)! {
		call('shutil.copyfile', o(attribute(args, 'dtb')!), o(join(boot, 'platform.dtb')!))!
		dtb_hash = call('digest', o(join(boot, 'platform.dtb')!))!
	}
	config := join(boot, 'limine.conf')!
	kernel_hash := call('digest', o(join(boot, 'vinix')!))!
	module_hashes := call('builtins.list')!
	indices := iterator(call('range', o(call('len', o(attribute(args, 'initramfs')!))!))!)!
	for {
		idx := next(indices)!
		if idx.done { break }
		append(module_hashes, o(call('digest', o(join(boot, 'root-' + text(idx.value)! + '.tar')!))!))!
	}
	content := call('config_text', o(kernel_hash), o(module_hashes), o(cmdline), o(dtb_hash), o(root_token))!
	method(config, 'write_text', [o(content)], {'encoding': v(ah.Value('ascii'))})!
	enrolled := call('bytearray', o(loader_data))!
	key := call('builtins.slice', o(field), o(add(field, literal(ah.Value(128))!)!))!
	set_item(enrolled, o(key), o(method(call('digest', o(config))!, 'encode', [v(ah.Value('ascii'))], {})!))!
	loader := call('operator.truediv', o(efi), o(index(item(constant('ARCHES')!, o(attribute(args, 'arch')!))!, 2)!))!
	if truth(attribute(args, 'developer_unsigned')!)! {
		method(loader, 'write_bytes', [o(enrolled)], {})!
	} else {
		unsigned := join(staging, 'enrolled.efi')!
		method(unsigned, 'write_bytes', [o(enrolled)], {})!
		call('sign_image', o(unsigned), o(loader), o(method(attribute(args, 'key')!, 'resolve', [], {})!), o(method(attribute(args, 'certificate')!, 'resolve', [], {})!), o(attribute(args, 'backend')!))!
		method(unsigned, 'unlink', [], {})!
	}
	call('verify_bundle', o(staging), o(attribute(args, 'arch')!), o(attribute(args, 'certificate')!), o(attribute(args, 'backend')!), o(attribute(args, 'developer_unsigned')!))!
	call('os.rename', o(staging), o(output))!
}
