// SPDX-License-Identifier: GPL-2.0-or-later
module runtimeroot

import androidhost as ah
import json2

// Named Python locals retain their objects until replacement or function return.
struct Workflow {
mut:
	names map[string]string
}

fn (mut state Workflow) save(name string, value string) !string {
	if previous := state.names[name] { release(previous)! }
	state.names[name] = value
	return value
}

fn (state Workflow) local(name string) string { return state.names[name] }

fn checkpoint() !ah.Value { return callback('checkpoint', {})! }

fn sweep(mark ah.Value, state Workflow) ! {
	callback('release_since', {
		'checkpoint': mark
		'keep':       ah.Value(state.names.values().map(ah.Value(it)))
	})!
}

fn set_attribute(id string, name string, value string) ! {
	callback('set_attribute', {
		'owner': ah.Value(id)
		'name':  ah.Value(name)
		'value': o(value)
	})!
}

fn attr(args string, name string) !string { return attribute(args, name)! }

fn number(value i64) !string { return literal(ah.Value(value))! }

fn null_value() !string { return literal(ah.Value(json2.Null{}))! }

fn discard(id string) ! { release(id)! }

fn mkdir(id string) ! {
	discard(method(id, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!)!
}

fn public(target string, values []string, kwargs map[string]ah.Value) !string {
	result := target_call(target, values.map(o(it)), kwargs) or {
		cause := err
		release_error([target], cause)!
		return cause
	}
	release(target)!
	return result
}

fn copyfile(source string, destination string) ! {
	discard(call('shutil.copyfile', o(source), o(destination))!)!
}

fn write_text(path string, contents string) ! {
	discard(method(path, 'write_text', [o(contents)], {})!)!
}

fn write_bytes(path string, contents string) ! {
	discard(method(path, 'write_bytes', [o(contents)], {})!)!
}

fn cmd(target string, values []string, kwargs map[string]ah.Value) ! {
	request := list(values)!
	result := public(target, [request], kwargs) or {
		cause := err
		release_error([request], cause)!
		return cause
	}
	release(request, result)!
}

fn devnull() !ah.Value { return o(global('subprocess.DEVNULL')!) }

fn guest(target string, args string, work string, bundle string, attached string, scenario string, expected string, probe ?string) ! {
	mut values := [args, work, bundle, attached, scenario, expected]
	if value := probe { values << value }
	discard(public(target, values, {})!)!
}

fn truncate_source(path string, mut state Workflow) ! {
	manager := method(path, 'open', [v(ah.Value('xb'))], {})!
	stream := enter(manager)!
	state.save('stream', stream)!
	truncate_source_body(stream) or {
		if !retired(manager, err)! { return err }
		return
	}
	retired(manager, none)!
}

fn retired(manager string, cause ?IError) !bool {
	result := retire(manager, cause) or {
		caught := err
		release_error([manager], caught)!
		return caught
	}
	release(manager)!
	return result
}

fn truncate_source_body(stream string) ! {
	target := attribute(stream, 'truncate')!
	amount := call('operator.mul', o(global('BLOCKS')!), v(ah.Value(4096))) or {
		cause := err
		release_error([target], cause)!
		return cause
	}
	result := target_call(target, [o(amount)], {}) or {
		cause := err
		release_error([amount, target], cause)!
		return cause
	}
	release(amount, target, result)!
}

fn archive(path string, mut state Workflow) ! {
	target := global('tarfile.open')!
	format := global('tarfile.USTAR_FORMAT')!
	manager := public(target, [path, lit('w')!], {
		'format': o(format)
	})!
	tar := enter(manager)!
	state.save('tar', tar)!
	archive_body(tar, mut state) or {
		if !retired(manager, err)! { return err }
		return
	}
	retired(manager, none)!
}

fn archive_body(tar string, mut state Workflow) ! {
	info := state.save('info', call('tarfile.TarInfo', v(ah.Value('bootstrap-only')))!)!
	content := state.save('content', callback('literal', {
		'value': ah.Value([ah.Value('bytes'),
			ah.Value('546869732061757468656e74696361746564206d6f64756c65206d757374206e6f742062652065787472616374656420696e746f206120766572696669656420726f6f742e0a')])
	})!.text())!
	size := call('len', o(content))!
	set_attribute(info, 'size', size)!
	addfile := attribute(tar, 'addfile')!
	stream := call('io.BytesIO', o(content)) or {
		cause := err
		release_error([addfile], cause)!
		return cause
	}
	result := target_call(addfile, [o(info), o(stream)], {}) or {
		cause := err
		release_error([stream, addfile], cause)!
		return cause
	}
	release(stream, addfile, result)!
}

fn active(cause ?IError) ! {
	callback('active_error', {
		'error': if error := cause { detail(error) } else { ah.Value(json2.Null{}) }
	})!
}

fn loader_checks(args string, work string, bundle string, attached string, mut state Workflow) ! {
	info := call('operator.getitem', o(global('boot.ARCHES')!), o(attr(args, 'arch')!))!
	loader := state.save('loader', join(bundle, 'EFI/BOOT/' + text(get(info, ah.Value(2))!)!)!)!
	signed := state.save('signed', method(loader, 'read_bytes', [], {})!)!
	loader_checks_body(args, work, bundle, attached, loader, signed, mut state) or {
		cause := err
		active(cause)!
		write_bytes(loader, signed) or { return err }
		active(none)!
		return cause
	}
	write_bytes(loader, signed)!
}

fn loader_checks_body(args string, work string, bundle string, attached string, loader string, signed string, mut state Workflow) ! {
	write := attribute(loader, 'write_bytes')!
	data := method(attr(args, 'loader')!, 'read_bytes', [], {}) or {
		cause := err
		release_error([write], cause)!
		return cause
	}
	result := target_call(write, [o(data)], {}) or {
		cause := err
		release_error([data, write], cause)!
		return cause
	}
	release(data, write, result)!
	guest(global('run_guest')!, args, work, bundle, attached, lit('unsigned-loader')!, lit('Access Denied')!, none)!
	modified := state.save('modified', call('bytearray', o(signed))!)!
	pe := global('boot.pe_info')!
	info_pair := public(pe, [modified, attr(args, 'arch')!], {})!
	field, ignored := pair(info_pair)!
	state.save('field', field)!
	state.save('_', ignored)!
	condition := compare('ne', call('operator.getitem', o(modified), o(field))!, call('ord', v(ah.Value('a')))!)!
	replacement := call('ord', v(ah.Value(if condition { 'a' } else { 'b' })))!
	discard(call('operator.setitem', o(modified), o(field), o(replacement))!)!
	write_bytes(loader, modified)!
	guest(global('run_guest')!, args, work, bundle, attached, lit('modified-loader')!, lit('Access Denied')!, none)!
}

fn main_workflow(args string, work string) ! {
	mut state := Workflow{
		names: {
			'args': args
			'work': work
		}
	}
	mut mark := checkpoint()!
	for name in ['kernel', 'loader', 'firmware_code', 'firmware_vars'] {
		state.save('name', lit(name)!)!
		target := global('setattr')!
		getter := global('getattr')!
		value := public(getter, [args, state.local('name')], {})!
		resolved := method(value, 'resolve', [], {})!
		discard(public(target, [args, state.local('name'), resolved], {})!)!
		sweep(mark, state)!
		mark = checkpoint()!
	}
	qemu := attr(args, 'qemu')!
	set_attribute(args, 'qemu', if truth(qemu)! {
		qemu
	} else {
		lit('qemu-system-' + text(attr(args, 'arch')!)!)!
	})!
	none_value := null_value()!
	set_attribute(args, 'key', none_value)!
	set_attribute(args, 'certificate', none_value)!
	sweep(mark, state)!
	mark = checkpoint()!
	if truth(attr(args, 'secure_boot')!)! {
		key := join(work, 'test.key')!
		certificate := join(work, 'test.crt')!
		set_attribute(args, 'key', key)!
		set_attribute(args, 'certificate', certificate)!
		target := global('command')!
		cmd(target, [lit('openssl')!, lit('req')!, lit('-new')!, lit('-x509')!, lit('-newkey')!,
			lit('rsa:2048')!, lit('-nodes')!, lit('-sha256')!, lit('-subj')!,
			lit('/CN=Vinix temporary verified root test')!, lit('-days')!, lit('1')!, lit('-addext')!,
			lit('extendedKeyUsage=codeSigning')!, lit('-keyout')!, attr(args, 'key')!, lit('-out')!,
			attr(args, 'certificate')!], {
			'stdout': devnull()!
			'stderr': devnull()!
		})!
		secure_vars := state.save('secure_vars', join(work, 'secure-vars.fd')!)!
		fw := global('command')!
		cmd(fw, [attr(args, 'virt_fw_vars')!, lit('--input')!, attr(args, 'firmware_vars')!,
			lit('--enroll-cert')!, attr(args, 'certificate')!, lit('--add-db')!,
			lit('d4b396e7-cdd6-4a48-a2d1-d62a4c6e02ce')!, attr(args, 'certificate')!,
			lit('--microsoft-db')!, lit('none')!, lit('--sb')!, lit('--output')!, secure_vars], {})!
		set_attribute(args, 'firmware_vars', secure_vars)!
		sweep(mark, state)!
		mark = checkpoint()!
	}
	staging := state.save('staging', join(work, 'root')!)!
	for directory in ['dev', 'proc', 'sys', 'tmp', 'run', 'var', 'root', 'sbin'] {
		state.save('directory', lit(directory)!)!
		mkdir(join(staging, directory)!)!
		sweep(mark, state)!
		mark = checkpoint()!
	}
	compile := global('command')!
	cc := attr(args, 'cc')!
	cmd(compile, [
		if truth(cc)! { cc } else { lit(text(attr(args, 'arch')!)! + '-linux-musl-gcc')! },
		lit('-static')!,
		lit('-O2')!,
		lit('-Wall')!,
		lit('-Wextra')!,
		lit('-Werror')!,
		join(global('ROOT')!, 'tests/verified-root/guest.c')!,
		lit('-o')!,
		join(staging, 'sbin/init')!,
	], {})!
	sweep(mark, state)!
	mark = checkpoint()!
	payload := attribute(join(staging, 'payload')!, 'write_bytes')!
	block := callback('literal', {
		'value': ah.Value([ah.Value('bytes'), ah.Value('76')])
	})!.text()
	discard(public(payload, [call('operator.mul', o(block), v(ah.Value(4096)))!], {})!)!
	sweep(mark, state)!
	mark = checkpoint()!
	write_data_blocks(staging)!
	sweep(mark, state)!
	mark = checkpoint()!
	device := state.save('device', lit(if compare('eq', attr(args, 'arch')!, lit('aarch64')!)! {
		'/dev/vda'
	} else {
		'/dev/ata0'
	})!)!
	write_text(join(staging, 'raw-device')!, device)!
	sweep(mark, state)!
	mark = checkpoint()!
	source := state.save('source', join(work, 'root.ext2')!)!
	truncate_source(source, mut state)!
	sweep(mark, state)!
	mark = checkpoint()!
	mk := global('command')!
	cmd(mk, [attr(args, 'mke2fs')!, lit('-q')!, lit('-F')!, lit('-t')!, lit('ext2')!, lit('-b')!,
		lit('4096')!, lit('-I')!, lit('128')!, lit('-O')!,
		lit('filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum')!,
		lit('-d')!, staging, source], {})!
	sweep(mark, state)!
	mark = checkpoint()!
	probe := state.save('probe', first_block(args, source, '/payload')!)!
	sweep(mark, state)!
	mark = checkpoint()!
	init_block := state.save('init_block', first_block(args, source, '/sbin/init')!)!
	sweep(mark, state)!
	mark = checkpoint()!
	write_probe(work, probe)!
	sweep(mark, state)!
	mark = checkpoint()!
	debug := global('command')!
	cmd(debug, [attr(args, 'debugfs')!, lit('-w')!, lit('-R')!,
		lit('write ' + text(join(work, 'probe-block')!)! + ' /probe-block')!, source], {
		'stdout': devnull()!
		'stderr': devnull()!
	})!
	sweep(mark, state)!
	mark = checkpoint()!
	owner := global('command')!
	cmd(owner, [lit('python3')!, join(global('ROOT')!, 'build-support/ext2-set-root-owner.py')!,
		source], {
		'stdout': devnull()!
	})!
	sweep(mark, state)!
	mark = checkpoint()!
	image := state.save('image', join(work, 'root.verity')!)!
	metadata := state.save('metadata', call('verity.build', o(source), o(image))!)!
	sweep(mark, state)!
	mark = checkpoint()!
	tarpath := state.save('archive', join(work, 'bootstrap.tar')!)!
	archive(tarpath, mut state)!
	sweep(mark, state)!
	mark = checkpoint()!
	bundle := state.save('bundle', join(work, 'boot-bundle')!)!
	namespace := global('argparse.Namespace')!
	build := state.save('build', target_call(namespace, [], {
		'arch':               o(attr(args, 'arch')!)
		'loader':             o(attr(args, 'loader')!)
		'kernel':             o(attr(args, 'kernel')!)
		'initramfs':          o(list([tarpath])!)
		'output':             o(bundle)
		'cmdline':            v(ah.Value(if compare('eq', attr(args, 'arch')!, lit('aarch64')!)! {
			'vinix.qemu_platform=1'
		} else {
			''
		}))
		'dtb':                v(ah.Value(json2.Null{}))
		'developer_unsigned': v(ah.Value(!truth(attr(args, 'secure_boot')!)!))
		'key':                o(attr(args, 'key')!)
		'certificate':        o(attr(args, 'certificate')!)
		'backend':            o(attr(args, 'backend')!)
		'verity_root':        o(image)
		'verity_device':      o(device)
		'verity_data_blocks': o(global('BLOCKS')!)
		'verity_root_hash':   o(get(metadata, ah.Value('root_hash'))!)
	})!)!
	release(namespace)!
	sweep(mark, state)!
	mark = checkpoint()!
	discard(call('boot.build_bundle', o(build))!)!
	sweep(mark, state)!
	mark = checkpoint()!
	valid_config := state.save('valid_config', method(join(bundle, 'boot/limine.conf')!, 'read_text', [], {})!)!
	sweep(mark, state)!
	mark = checkpoint()!
	attached := state.save('attached', join(work, 'attached.img')!)!
	copyfile(image, attached)!
	sweep(mark, state)!
	mark = checkpoint()!
	if truth(attr(args, 'secure_boot')!)! {
		loader_checks(args, work, bundle, attached, mut state)!
	}
	guest(global('run_guest')!, args, work, bundle, attached, lit('valid')!, lit('VERIFIED ROOT: PASS')!, probe)!
	sweep(mark, state)!
	mark = checkpoint()!
	if !truth(attr(args, 'only_valid')!)! {
		negative(args, work, bundle, attached, image, source, metadata, valid_config, device, init_block, mut state)!
	}
	if truth(attr(args, 'key')!)! { discard(method(attr(args, 'key')!, 'unlink', [], {})!)! }
	final := global('print')!
	discard(public(final, [lit('PASS: real kernel verified-root enforcement' + if truth(attr(args, 'secure_boot')!)! {
		' with enabled UEFI Secure Boot.'
	} else {
		'; firmware Secure Boot was disabled, so firmware trust enrollment is a separate test.'
	})!], {})!)!
	sweep(mark, state)!
}

fn negative(args string, work string, bundle string, attached string, image string, source string, metadata string, valid_config string, device string, init_block string, mut state Workflow) ! {
	mut mark := checkpoint()!
	// Python evaluates all four tuple entries before beginning this loop.
	offsets := [number(1024)!,
		call('operator.add', o(call('operator.mul', o(init_block), v(ah.Value(4096)))!), v(ah.Value(17)))!,
		call('operator.add', o(call('operator.mul', o(global('BLOCKS')!), v(ah.Value(4096)))!), v(ah.Value(17)))!,
		call('operator.add', o(call('operator.mul', o(get(get(call('verity.layout', o(global('BLOCKS')!))!, ah.Value(0))!, ah.Value(0))!), v(ah.Value(4096)))!), v(ah.Value(17)))!]
	mut pairs := []string{}
	for index, scenario in ['metadata', 'init-data', 'top-tree', 'leaf-tree'] {
		pairs << collection('tuple', [lit(scenario)!, offsets[index]])!
	}
	values := collection('tuple', pairs)!
	items := iterator(values)!
	release(values)!
	release(...pairs)!
	release(...offsets)!
	for {
		item := next(items)!
		if item.done { break }
		name_value, offset_value := pair(item.value)!
		name := state.save('scenario', name_value)!
		offset := state.save('offset', offset_value)!
		scenario := text(name)!
		copyfile(image, attached)!
		discard(call('tamper', o(attached), o(offset))!)!
		expected := state.save('expected', lit(if scenario == 'init-data' {
			if compare('eq', attr(args, 'arch')!, lit('x86_64')!)! {
				'Kernel has called exit()'
			} else {
				'Could not start init process'
			}
		} else {
			'verity: root integrity or filesystem check failed'
		})!)!
		guest(global('run_guest')!, args, work, bundle, attached, name, expected, none)!
	}
	release(items)!
	copyfile(image, attached)!
	manager := method(attached, 'open', [v(ah.Value('r+b'))], {})!
	stream := enter(manager)!
	state.save('stream', stream)!
	truncate_backing_scoped(manager, stream, image)!
	guest(global('run_guest')!, args, work, bundle, attached, lit('truncated')!, lit('verity: incompatible or truncated backing device')!, none)!
	copyfile(image, attached)!
	root := state.save('root', get(metadata, ah.Value('root_hash'))!)!
	first := if compare('ne', get(root, ah.Value(0))!, lit('0')!)! { '0' } else { '1' }
	tail := call('operator.getitem', o(root), o(call('builtins.slice', v(ah.Value(1)), v(ah.Value(json2.Null{})))!))!
	wrong := state.save('wrong', call('operator.add', v(ah.Value(first)), o(tail))!)!
	enrol := global('enroll')!
	replacement := method(valid_config, 'replace', [o(root), o(wrong)], {})!
	discard(public(enrol, [bundle, replacement, args, work], {})!)!
	guest(global('run_guest')!, args, work, bundle, attached, lit('wrong-root')!, lit('verity: root integrity or filesystem check failed')!, none)!
	token := state.save('token', call('verity.command_line', o(device), o(global('BLOCKS')!), o(root))!)!
	// Keep the original tuple construction and replacement evaluation order.
	replacements := [lit(text(token)! + ' ' + text(token)!)!, lit('vinix.disk=auto ' + text(token)!)!,
		method(token, 'replace', [v(ah.Value('vinix.verity=1,')), v(ah.Value('vinix.verity=2,'))], {})!]
	mut policies := []string{}
	for index, scenario in ['duplicate-policy', 'conflicting-policy', 'malformed-policy'] {
		policies << collection('tuple', [lit(scenario)!, replacements[index]])!
	}
	policy_values := collection('tuple', policies)!
	policy_items := iterator(policy_values)!
	release(policy_values)!
	release(...policies)!
	release(...replacements)!
	for {
		item := next(policy_items)!
		if item.done { break }
		name_value, replacement_item := pair(item.value)!
		name := state.save('scenario', name_value)!
		replacement_value := state.save('replacement', replacement_item)!
		target := global('enroll')!
		config := method(valid_config, 'replace', [o(token), o(replacement_value)], {})!
		discard(public(target, [bundle, config, args, work], {})!)!
		guest(global('run_guest')!, args, work, bundle, attached, name, lit('verity: invalid, duplicate or conflicting root policy')!, none)!
	}
	release(policy_items)!
	command_target := global('command')!
	cmd(command_target, [attr(args, 'debugfs')!, lit('-w')!, lit('-R')!, lit('rmdir /sys')!, source], {
		'stdout': devnull()!
		'stderr': devnull()!
	})!
	missing := state.save('missing', join(work, 'missing-sys.verity')!)!
	broken := state.save('broken', call('verity.build', o(source), o(missing))!)!
	copyfile(missing, attached)!
	enrol_missing := global('enroll')!
	config := method(valid_config, 'replace', [o(root), o(get(broken, ah.Value('root_hash'))!)], {})!
	discard(public(enrol_missing, [bundle, config, args, work], {})!)!
	guest(global('run_guest')!, args, work, bundle, attached, lit('missing-mountpoint')!, lit('verity: verified root is not a bootable system')!, none)!
	discard(call('enroll', o(bundle), o(valid_config), o(args), o(work))!)!
	sweep(mark, state)!
	mark = checkpoint()!
}

fn truncate_backing(stream string, image string) ! {
	truncate_target := attribute(stream, 'truncate')!
	amount := backing_length(image) or {
		cause := err
		release_error([truncate_target], cause)!
		return cause
	}
	result := target_call(truncate_target, [o(amount)], {}) or {
		cause := err
		release_error([amount, truncate_target], cause)!
		return cause
	}
	release(amount, truncate_target, result)!
}

fn backing_length(image string) !string {
	status := method(image, 'stat', [], {})!
	size := attribute(status, 'st_size') or {
		cause := err
		release_error([status], cause)!
		return cause
	}
	release(status)!
	amount := call('operator.sub', o(size), v(ah.Value(4096))) or {
		cause := err
		release_error([size], cause)!
		return cause
	}
	release(size)!
	return amount
}

fn truncate_backing_scoped(manager string, stream string, image string) ! {
	truncate_backing(stream, image) or {
		if !retired(manager, err)! { return err }
		return
	}
	retired(manager, none)!
}

fn first_block(args string, source string, path string) !string {
	values := call('device_blocks', o(args), o(source), v(ah.Value(path)))!
	result := get(values, ah.Value(0)) or {
		cause := err
		release_error([values], cause)!
		return cause
	}
	release(values)!
	return result
}

fn write_data_blocks(staging string) ! {
	target := attribute(join(staging, 'data-blocks')!, 'write_text')!
	contents := blocks_contents() or {
		cause := err
		release_error([target], cause)!
		return cause
	}
	discard(public(target, [contents], {})!)!
	release(contents)!
}

fn write_probe(work string, probe string) ! {
	target := attribute(join(work, 'probe-block')!, 'write_text')!
	contents := probe_contents(probe) or {
		cause := err
		release_error([target], cause)!
		return cause
	}
	discard(public(target, [contents], {})!)!
	release(contents)!
}

fn blocks_contents() !string { return lit(text(global('BLOCKS')!)! + '\n')! }

fn probe_contents(probe string) !string { return lit(text(probe)! + '\n')! }
