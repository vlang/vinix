// SPDX-License-Identifier: GPL-2.0-or-later
module boottest

import androidhost as ah

fn verify(target string, output string, developer bool) ! {
	mut args := [o(output), v(ah.Value('x86_64'))!, v(none_value())!, v(ah.Value('sbsign'))!]
	if developer { args << v(ah.Value(true))! }
	discard(invoke_target(target, args, {})!)!
}

fn read(path string) !string { return invoke_target(member(path, 'read_bytes')!, [], {})! }

fn unlink(path string) ! { discard(invoke_target(member(path, 'unlink')!, [], {})!)! }

fn build(target string, args string) ! { discard(invoke_target(target, [o(args)], {})!)! }

fn bundle_body(self string, temporary string, pins string) ! {
	mut f := Frame{ pins: pins }
	bundle_statements(mut f, self, temporary) or {
		cause := err
		f.pin_failure()!
		return cause
	}
}

fn bundle_statements(mut f Frame, self string, temporary string) ! {
	f.named('temporary', temporary)!
	f.named('self', self)!
	work := f.named('work', invoke_target(constant('Path')!, [o(temporary)], {})!)!
	discard(invoke_target(member(join(work, 'loader')!, 'write_bytes')!, [o(invoke_target(constant('pe')!, [], {})!)], {})!)!
	f.clean()!
	discard(invoke_target(member(join(work, 'kernel')!, 'write_bytes')!, [o(invoke_target(constant('elf')!, [v(ah.Value('x86_64'))!], {})!)], {})!)!
	f.clean()!
	discard(invoke_target(member(join(work, 'root')!, 'write_bytes')!, [b('66697273742061726368697665')!], {})!)!
	f.clean()!
	discard(invoke_target(member(join(work, 'overlay')!, 'write_bytes')!, [b('7365636f6e642061726368697665')!], {})!)!
	f.clean()!
	output := f.named('output', join(work, 'bundle')!)!
	args := f.named('args', invoke_target(constant('argparse.Namespace')!, [], {
		'arch':               v(ah.Value('x86_64'))!
		'loader':             o(join(work, 'loader')!)
		'kernel':             o(join(work, 'kernel')!)
		'initramfs':          o(sequence('list', [join(work, 'root')!, join(work, 'overlay')!])!)
		'output':             o(output)
		'cmdline':            v(ah.Value('quiet'))!
		'dtb':                v(none_value())!
		'developer_unsigned': v(ah.Value(true))!
		'key':                v(none_value())!
		'certificate':        v(none_value())!
		'backend':            v(ah.Value('sbsign'))!
	})!)!
	f.clean()!
	build(constant('boot.build_bundle')!, args)!
	f.clean()!
	verify(constant('boot.verify_bundle')!, output, true)!
	f.clean()!
	expect(self, 'boot.InvalidBundle', fn [output] () ! {
		verify(constant('boot.verify_bundle')!, output, false)!
	})!
	f.clean()!
	expect(self, 'boot.InvalidBundle', fn [args] () ! {
		build(constant('boot.build_bundle')!, args)!
	})!
	f.clean()!
	for filename in ['boot/vinix', 'boot/root-0.tar', 'boot/root-1.tar', 'boot/limine.conf'] {
		f.named('filename', literal(ah.Value(filename))!)!
		path := f.named('path', join(output, filename)!)!
		original := f.named('original', read(path)!)!
		discard(invoke_target(member(path, 'write_bytes')!, [o(add(original, b('74616d706572')!)!)], {})!)!
		f.clean()!
		subtest(self, {
			'filename': o(f.names['filename'])
		}, fn [self, output] () ! {
			expect(self, 'boot.InvalidBundle', fn [output] () ! {
				verify(constant('boot.verify_bundle')!, output, true)!
			})!
		})!
		f.clean()!
		discard(invoke_target(member(path, 'write_bytes')!, [o(original)], {})!)!
		f.clean()!
	}
	discard(invoke_target(member(join(output, 'EFI/BOOT/extra.efi')!, 'write_bytes')!, [b('756e6578706563746564206c6f61646572')!], {})!)!
	f.clean()!
	expect(self, 'boot.InvalidBundle', fn [output] () ! {
		verify(constant('boot.verify_bundle')!, output, true)!
	})!
	f.clean()!
	unlink(join(output, 'EFI/BOOT/extra.efi')!)!
	f.clean()!
	path := f.named('path', join(output, 'boot/root-1.tar')!)!
	unlink(path)!
	f.clean()!
	discard(invoke_target(member(path, 'symlink_to')!, [o(join(work, 'overlay')!)], {})!)!
	f.clean()!
	expect(self, 'boot.InvalidBundle', fn [output] () ! {
		verify(constant('boot.verify_bundle')!, output, true)!
	})!
}

fn block_body(self string, temporary string, pins string) ! {
	mut f := Frame{ pins: pins }
	block_statements(mut f, self, temporary) or {
		cause := err
		f.pin_failure()!
		return cause
	}
}

fn block_statements(mut f Frame, self string, temporary string) ! {
	f.named('temporary', temporary)!
	f.named('self', self)!
	work := f.named('work', invoke_target(constant('Path')!, [o(temporary)], {})!)!
	discard(invoke_target(member(join(work, 'loader')!, 'write_bytes')!, [o(invoke_target(constant('pe')!, [], {})!)], {})!)!
	f.clean()!
	discard(invoke_target(member(join(work, 'kernel')!, 'write_bytes')!, [o(invoke_target(constant('elf')!, [v(ah.Value('x86_64'))!], {})!)], {})!)!
	f.clean()!
	discard(invoke_target(member(join(work, 'bootstrap')!, 'write_bytes')!, [b('61757468656e7469636174656420626f6f7473747261702061726368697665')!], {})!)!
	f.clean()!
	discard(invoke_target(member(join(work, 'data')!, 'write_bytes')!, [o(invoke_target(constant('operator.mul')!, [
		b('78')!,
		v(ah.Value(129 * 4096))!,
	], {})!)], {})!)!
	f.clean()!
	metadata := f.named('metadata', invoke_target(constant('boot.verity.build')!, [
		o(join(work, 'data')!),
		o(join(work, 'root-image')!),
	], {})!)!
	f.clean()!
	options := f.named('options', invoke_target(constant('dict')!, [], {
		'arch':               v(ah.Value('x86_64'))!
		'loader':             o(join(work, 'loader')!)
		'kernel':             o(join(work, 'kernel')!)
		'initramfs':          o(sequence('list', [join(work, 'bootstrap')!])!)
		'output':             o(join(work, 'bundle')!)
		'cmdline':            v(ah.Value('quiet'))!
		'dtb':                v(none_value())!
		'developer_unsigned': v(ah.Value(true))!
		'key':                v(none_value())!
		'certificate':        v(none_value())!
		'backend':            v(ah.Value('sbsign'))!
		'verity_root':        o(join(work, 'root-image')!)
		'verity_device':      v(ah.Value('/dev/vda'))!
		'verity_data_blocks': o(get(metadata, 'data_blocks')!)
		'verity_root_hash':   o(get(metadata, 'root_hash')!)
	})!)!
	f.clean()!
	build(constant('boot.build_bundle')!, namespace(options)!)!
	f.clean()!
	verify(constant('boot.verify_bundle')!, join(work, 'bundle')!, true)!
	f.clean()!
	token := f.named('token', invoke_target(constant('boot.verity.command_line')!, [
		v(ah.Value('/dev/vda'))!,
		v(ah.Value(129))!,
		o(get(metadata, 'root_hash')!),
	], {})!)!
	f.clean()!
	config := f.named('config', join(work, 'bundle/boot/limine.conf')!)!
	assertion := member(self, 'assertIn')!
	needle := formatted_string([literal(ah.Value('cmdline: quiet '))!, format_value(token)!,
		literal(ah.Value('\n'))!])!
	discard(invoke_target(assertion, [o(needle),
		o(invoke_target(member(config, 'read_text')!, [], {})!)], {})!)!
	f.clean()!
	image := f.named('image', join(work, 'bundle/boot/verity-root.img')!)!
	original := f.named('original', read(image)!)!
	f.clean()!
	last := invoke_target(constant('operator.sub')!, [o(length(original)!), v(ah.Value(1))!], {})!
	offsets := [literal(ah.Value(0))!, literal(ah.Value(129 * 4096))!, literal(ah.Value(130 * 4096))!,
		last]
	for offset in offsets { f.named('offset-tuple-' + offset, offset)! }
	for offset in offsets {
		f.named('offset', offset)!
		corrupt := f.named('corrupt', invoke_target(constant('bytearray')!, [o(original)], {})!)!
		set_item(corrupt, o(offset), o(invoke_target(constant('operator.xor')!, [
			o(item(corrupt, o(offset))!),
			v(ah.Value(1))!,
		], {})!))!
		discard(invoke_target(member(image, 'write_bytes')!, [o(corrupt)], {})!)!
		f.clean()!
		subtest(self, {
			'offset': o(offset)
		}, fn [self, work] () ! {
			expect(self, 'boot.InvalidBundle', fn [work] () ! {
				verify(constant('boot.verify_bundle')!, join(work, 'bundle')!, true)!
			})!
		})!
		f.clean()!
	}
	discard(invoke_target(member(image, 'write_bytes')!, [o(original)], {})!)!
	f.clean()!
	discard(invoke_target(member(image, 'write_bytes')!, [o(item(original, o(slice(v(none_value())!, v(ah.Value(-1))!)!))!)], {})!)!
	f.clean()!
	expect(self, 'boot.InvalidBundle', fn [work] () ! {
		verify(constant('boot.verify_bundle')!, join(work, 'bundle')!, true)!
	})!
	f.clean()!
	discard(invoke_target(member(image, 'write_bytes')!, [o(original)], {})!)!
	f.clean()!
	for key in ['verity_root', 'verity_device', 'verity_data_blocks', 'verity_root_hash'] {
		f.named('key', literal(ah.Value(key))!)!
		display := invoke_target(constant('_dict_display')!, [o(options)], {})!
		set_item(display, v(ah.Value('output'))!, o(join(work, 'incomplete')!))!
		set_item(display, v(ah.Value(key))!, v(none_value())!)!
		incomplete := f.named('incomplete', display)!
		f.clean()!
		subtest(self, {
			'missing': o(f.names['key'])
		}, fn [self, incomplete] () ! {
			expect(self, 'boot.InvalidBundle', fn [incomplete] () ! {
				build(constant('boot.build_bundle')!, namespace(incomplete)!)!
			})!
		})!
		f.clean()!
	}
	for index, key in ['verity_data_blocks', 'verity_root_hash'] {
		f.named('key', literal(ah.Value(key))!)!
		value := f.named('value', literal(if index == 0 {
			ah.Value(128)
		} else {
			ah.Value('0'.repeat(64))
		})!)!
		display := invoke_target(constant('_dict_display')!, [o(options)], {})!
		set_item(display, v(ah.Value('output'))!, o(join(work, 'wrong')!))!
		set_item(display, v(ah.Value(key))!, o(value))!
		wrong := f.named('wrong', display)!
		f.clean()!
		subtest(self, {
			'key': o(f.names['key'])
		}, fn [self, wrong] () ! {
			expect(self, 'boot.InvalidBundle', fn [wrong] () ! {
				build(constant('boot.build_bundle')!, namespace(wrong)!)!
			})!
		})!
		f.clean()!
	}
	values := [
		formatted_string([format_value(token)!, literal(ah.Value(' '))!, format_value(token)!])!,
		formatted_string([literal(ah.Value('x='))!, format_value(token)!, literal(ah.Value(' '))!,
			format_value(token)!])!,
		formatted_string([format_value(token)!, literal(ah.Value(' quiet'))!])!,
	]
	// Python evaluates the complete tuple before iterating it.
	for value in values { f.named('tuple-' + value, value)! }
	for value in values {
		f.named('value', value)!
		subtest(self, {
			'cmdline': o(value)
		}, fn [self, value, token] () ! {
			expect(self, 'boot.InvalidBundle', fn [value, token] () ! {
				discard(invoke_target(constant('boot.check_cmdline')!, [o(value), o(token)], {})!)!
			})!
		})!
		f.clean()!
	}
}

fn namespace(options string) !string {
	return callback('function', {
		'name':         ah.Value('argparse.Namespace')
		'call':         ah.Value(true)
		'args':         ah.Value([]ah.Value{})
		'kwargs':       ah.Value(map[string]ah.Value{})
		'kwargs_owner': ah.Value(options)
	})!.text()
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	operation := ah.field(row, 'operation').text()
	if operation == 'elf' { return ah.Value(elf(args[1], args[0])!) }
	if operation == 'pe' { return ah.Value(pe(args[1], args[0])!) }
	if operation !in ['bundle', 'block_root'] {
		return error('Unknown verified-boot test operation')
	}
	manager := invoke_target(constant('tempfile.TemporaryDirectory')!, [], {})!
	self := args[1]
	pins := args[0]
	with_manager(manager, fn [operation, self, pins] (temporary string) ! {
		if operation == 'bundle' {
			bundle_body(self, temporary, pins)!
		} else {
			block_body(self, temporary, pins)!
		}
	})!
	return none_value()
}
