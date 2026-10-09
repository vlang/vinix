// SPDX-License-Identifier: GPL-2.0-or-later
module pcivm

import androidhost as ah
import json2

// The original main frame owns these locals through its outer report cleanup.
// Publish replacement values before retiring the previous owned table entry.
struct Preparation {
	args      string
	state     string
	frame     string
	copy_cell string
mut:
	names map[string]string
}

fn (mut p Preparation) save(name string, value string) !string {
	// The original copies local is a closure cell, retired after fast locals.
	if name == 'copies' && p.copy_cell != '' {
		discard(target_call(p.copy_cell, [o(value)], {})!)!
	}
	set_item(p.frame, name, o(value))!
	old := p.names[name]
	p.names[name] = value
	if old != '' { discard(old)! }
	return value
}

fn (p &Preparation) get(name string) string { return p.names[name] }

fn (mut p Preparation) load(names []string) ! {
	for name in names {
		p.names[name] = call('operator.getitem', o(p.frame), v(ah.Value(name)))!
	}
}

fn tuple(items []string) !string { return collection('tuple', items)! }

fn collection(kind string, items []string) !string {
	return callback('collection', {
		'kind':   ah.Value(kind)
		'values': ah.Value(items.map(ah.Value(it)))
	})!.text()
}

fn list(items []string) !string { return collection('list', items)! }

fn lit(text string) !string { return literal(ah.Value(text))! }

fn empty_dict() !string { return literal(ah.Value(map[string]ah.Value{}))! }

fn divide(parent string, child string) !string {
	return call('operator.truediv', o(parent), v(ah.Value(child)))!
}

fn division(parent string, child string) !string {
	return call('operator.truediv', o(parent), o(child))!
}

fn consumed_method(receiver string, name string, args []ah.Value, kwargs map[string]ah.Value) !string {
	target := attribute(receiver, name) or {
		discard(receiver)!
		return err
	}
	discard(receiver)!
	result := target_call(target, args, kwargs) or {
		discard(target)!
		return err
	}
	discard(target)!
	return result
}

fn resolved_attribute(owner string, name string) !string {
	return consumed_method(attribute(owner, name)!, 'resolve', [], {})!
}

fn stringify(value string) !string { return call('str', o(value))! }

// This narrow syntax binding uses Python's FORMAT_VALUE/BUILD_STRING directly.
fn prefixed(prefix string, value string) !string {
	return call('_pci_format', v(ah.Value(prefix)), o(value))!
}

fn changed(path string, original string) !bool {
	hash := call('digest', o(path))!
	value := call('operator.ne', o(hash), o(original)) or {
		discard(hash)!
		return err
	}
	discard(hash)!
	result := truth(value) or {
		discard(value)!
		return err
	}
	discard(value)!
	return result
}

fn prep_error(prefix string, value string) ! {
	target := resolve('RuntimeError')!
	message := prefixed(prefix, value) or {
		discard(target)!
		return err
	}
	raise_message(target, message)!
}

fn ignore_method(owner string, name string, args []ah.Value, kwargs map[string]ah.Value) ! {
	discard(method(owner, name, args, kwargs)!)!
}

fn (mut p Preparation) input_paths() ! {
	path_target := resolve('Path')!
	executable_target := resolve('executable') or {
		discard(path_target)!
		return err
	}
	name := attribute(p.args, 'qemu') or {
		release(executable_target, path_target)!
		return err
	}
	found := target_call(executable_target, [o(name)], {}) or {
		release(name, executable_target, path_target)!
		return err
	}
	release(name, executable_target)!
	qemu := target_call(path_target, [o(found)], {}) or {
		release(found, path_target)!
		return err
	}
	release(found, path_target)!
	p.save('qemu', qemu)!
	parent := attribute(qemu, 'parent')!
	grandparent := attribute(parent, 'parent') or {
		discard(parent)!
		return err
	}
	discard(parent)!
	share := divide(grandparent, 'share/qemu') or {
		discard(grandparent)!
		return err
	}
	discard(grandparent)!
	p.save('share', share)!
	for row in [['firmware', 'edk2-aarch64-code.fd'], ['vars_template', 'edk2-arm-vars.fd']] {
		provided := attribute(p.args, row[0])!
		chosen := if truth(provided)! {
			provided
		} else {
			discard(provided)!
			divide(share, row[1])!
		}
		p.save(row[0], consumed_method(chosen, 'resolve', [], {})!)!
	}
	p.save('loader', resolved_attribute(p.args, 'bootloader')!)!
	p.save('kernel', resolved_attribute(p.args, 'kernel')!)!
	for input_name in ['firmware', 'vars_template', 'loader', 'kernel'] {
		// STORE_FAST aliases the existing actual input; give its local a new ID.
		p.save('path', call('operator.getitem', o(p.frame), v(ah.Value(input_name)))!)!
		result := method(p.get('path'), 'is_file', [], {})!
		present := truth(result) or {
			discard(result)!
			return err
		}
		discard(result)!
		if !present { prep_error('required read-only input unavailable: ', p.get('path'))! }
	}
}

fn (mut p Preparation) fixture_inputs() ! {
	path_target := resolve('Path')!
	file := resolve('__file__') or {
		discard(path_target)!
		return err
	}
	path := target_call(path_target, [o(file)], {}) or {
		release(file, path_target)!
		return err
	}
	release(file, path_target)!
	p.save('fixture', consumed_method(path, 'with_name', [v(ah.Value('armfixture'))], {})!)!
	mut rows := []string{}
	for item in [['init_source', 'core.v'], ['init_abi', 'pci-arm-fixture-native-abi.h'],
		['init_syscall', 'syscall3.S'],
		['fixture_generator', 'tests/kernel-gaps/compile-v-fixture.py'],
		['module_generator', 'build-support/compile-v-module.py']] {
		name := lit(item[0])!
		fixture_path := if item[0].starts_with('init_') {
			divide(p.get('fixture'), item[1])!
		} else {
			root := resolve('ROOT')!
			result := divide(root, item[1]) or {
				release(root, name)!
				return err
			}
			discard(root)!
			result
		}
		row := tuple([name, fixture_path]) or {
			release(fixture_path, name)!
			return err
		}
		release(name, fixture_path)!
		rows << row
	}
	inputs := tuple(rows)!
	release(...rows)!
	p.save('fixture_inputs', inputs)!
}

struct PrepNext {
	done  bool
	value string
}

fn prep_next(iterator string) !PrepNext {
	row := callback('next', {
		'owner': ah.Value(iterator)
	})!.object()
	if ah.field(row, 'done') as bool { return PrepNext{ done: true } }
	return PrepNext{ value: ah.field(row, 'value').text() }
}

fn prep_iterator(value string) !string { return call('builtins.iter', o(value))! }

fn (mut p Preparation) unpack(row string) ! {
	values := callback('unpack_pair', {
		'owner': ah.Value(row)
	})!.items()
	discard(row)!
	p.save('name', values[0].text())!
	p.save('source', values[1].text())!
}

fn (mut p Preparation) freeze_row() ! {
	p.save('before', call('digest', o(p.get('source')))!)!
	starts := method(p.get('name'), 'startswith', [v(ah.Value('init_'))], {})!
	is_init := truth(starts) or {
		discard(starts)!
		return err
	}
	discard(starts)!
	target := if is_init {
		base := divide(p.get('frozen'), 'armfixture')!
		name := attribute(p.get('source'), 'name') or {
			discard(base)!
			return err
		}
		result := division(base, name) or {
			release(name, base)!
			return err
		}
		release(base, name)!
		result
	} else {
		division(p.get('frozen'), p.get('name'))!
	}
	p.save('target', target)!
	parent := attribute(target, 'parent')!
	discard(consumed_method(parent, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!)!
	discard(call('shutil.copyfile', o(p.get('source')), o(target))!)!
	if changed(target, p.get('before'))! || changed(p.get('source'), p.get('before'))! {
		prep_error('input changed while freezing: ', p.get('source'))!
	}
	text := stringify(p.get('source'))!
	discard(call('operator.setitem', o(p.get('originals')), o(p.get('name')), o(text))!)!
	discard(text)!
	discard(call('operator.setitem', o(p.get('copies')), o(p.get('name')), o(target))!)!
}

fn (mut p Preparation) freeze_inputs() ! {
	p.save('frozen', divide(p.state, 'inputs')!)!
	ignore_method(p.get('frozen'), 'mkdir', [], {})!
	p.save('originals', empty_dict()!)!
	p.save('copies', empty_dict()!)!
	p.fixture_inputs()!
	mut rows := []string{}
	for pair in [['kernel', 'kernel'], ['firmware', 'firmware'], ['bootloader', 'loader'],
		['vars_template', 'vars_template']] {
		name := lit(pair[0])!
		rows << tuple([name, p.get(pair[1])])!
		discard(name)!
	}
	iterator := prep_iterator(p.get('fixture_inputs'))!
	for {
		next := prep_next(iterator)!
		if next.done { break }
		rows << next.value
	}
	discard(iterator)!
	// The actual iterable retains its elements until the original for completes.
	all := tuple(rows)!
	release(...rows)!
	loop := prep_iterator(all)!
	discard(all)!
	for {
		next := prep_next(loop)!
		if next.done { break }
		p.unpack(next.value)!
		p.freeze_row()!
	}
	discard(loop)!
	mut replacement := []string{}
	for name in ['kernel', 'firmware', 'bootloader', 'vars_template'] {
		replacement << call('operator.getitem', o(p.get('copies')), v(ah.Value(name)))!
	}
	for i, name in ['kernel', 'firmware', 'loader', 'vars_template'] {
		p.save(name, replacement[i])!
	}
}

fn (mut p Preparation) toolchain() ! {
	target := resolve('executable')!
	name := attribute(p.args, 'cc') or {
		discard(target)!
		return err
	}
	compiler := target_call(target, [o(name)], {}) or {
		release(name, target)!
		return err
	}
	release(name, target)!
	p.save('cc', compiler)!
	p.save('ld', call('executable', v(ah.Value('ld.lld')))!)!
	tools := empty_dict()!
	for tool_name in ['mformat', 'mmd', 'mcopy'] {
		found := call('executable', v(ah.Value(tool_name)))!
		set_item(tools, tool_name, o(found))!
		discard(found)!
	}
	p.save('tools', tools)!
	p.save('rootfs', divide(p.state, 'rootfs')!)!
	for directory in ['sbin', 'dev', 'proc', 'sys', 'root', 'tmp'] {
		p.save('directory', lit(directory)!)!
		path := division(p.get('rootfs'), p.get('directory'))!
		discard(consumed_method(path, 'mkdir', [], {
			'parents': v(ah.Value(true))
		})!)!
	}
	p.save('obj', divide(p.state, 'arm_init.o')!)!
	p.save('syscall_obj', divide(p.state, 'syscall3.o')!)!
	p.save('generated_source', divide(p.state, 'arm_init.c')!)!
	p.save('init', divide(p.get('rootfs'), 'sbin/init')!)!
}

fn string_path(parent string, child string) !string {
	target := resolve('str')!
	path := divide(parent, child) or {
		discard(target)!
		return err
	}
	result := target_call(target, [o(path)], {}) or {
		release(path, target)!
		return err
	}
	release(path, target)!
	return result
}

fn (mut p Preparation) build_commands() ! {
	mut values := [p.get('cc'), lit('--target=aarch64-linux-musl')!]
	path := resolved_attribute(p.args, 'sysroot')!
	option := prefixed('--sysroot=', path) or {
		discard(path)!
		return err
	}
	discard(path)!
	values << option
	for text in ['-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror', '-nostdlib', '-ffreestanding',
		'-fno-stack-protector', '-fno-pie', '-Wno-unused-function', '-Wno-unused-parameter', '-I'] {
		values << lit(text)!
	}
	values << string_path(p.get('frozen'), 'armfixture')!
	values << lit('-c')!
	values << stringify(p.get('generated_source'))!
	values << lit('-o')!
	values << stringify(p.get('obj'))!
	command := list(values)!
	for value in values { if value != p.get('cc') { discard(value)! } }
	p.save('compile_command', command)!
	mut link := [p.get('ld')]
	for text in ['-m', 'aarch64elf', '--nostdlib', '-static', '-e', '_start', '--build-id=none'] {
		link << lit(text)!
	}
	link << stringify(p.get('obj'))!
	link << stringify(p.get('syscall_obj'))!
	link << lit('-o')!
	link << stringify(p.get('init'))!
	linked := list(link)!
	for value in link { if value != p.get('ld') { discard(value)! } }
	p.save('link_command', linked)!
}

fn prepare_start_body(ids []ah.Value) ! {
	mut p := Preparation{ args: ids[0].text(), state: ids[1].text(), frame: ids[2].text(), copy_cell: ids[3].text() }
	p.input_paths()!
	p.freeze_inputs()!
	p.toolchain()!
	p.build_commands()!
}

fn clear_preparation_since(point ah.Value) ! {
	end := checkpoint()!
	first := int(ah.integer(point) or { return error('invalid checkpoint') })
	last := int(ah.integer(end) or { return error('invalid checkpoint') })
	// Failed expressions unwind their stack in reverse order; named values
	// remain authoritative in the caller's actual frame dictionary.
	for i := last - 1; i >= first; i-- { discard(i.str())! }
}

fn prepare_start(ids []ah.Value) ! {
	point := checkpoint()!
	prepare_start_body(ids) or {
		clear_preparation_since(point)!
		return err
	}
}

fn run_values(run string, values []string, borrowed []string) ! {
	command := list(values)!
	for value in values { if value !in borrowed { discard(value)! } }
	result := target_call(run, [o(command)], {}) or {
		discard(command)!
		return err
	}
	release(command, result)!
}

fn generated_fixture(run string, p &Preparation) ! {
	python := resolve('sys.executable')!
	root := resolve('ROOT')!
	generator := string_path(root, 'tests/kernel-gaps/compile-v-fixture.py') or {
		release(root, python)!
		return err
	}
	discard(root)!
	run_values(run, [python, generator, stringify(p.get('generated_source'))!, lit('--arch')!,
		lit('aarch64')!, lit('--module')!, string_path(p.get('frozen'), 'armfixture')!], [])!
}

fn (mut p Preparation) check_generated() ! {
	iterator := prep_iterator(p.get('fixture_inputs'))!
	for {
		next := prep_next(iterator)!
		if next.done { break }
		p.unpack(next.value)!
		left := call('digest', o(p.get('source')))!
		target := resolve('digest') or {
			discard(left)!
			return err
		}
		copied := call('operator.getitem', o(p.get('copies')), o(p.get('name'))) or {
			release(target, left)!
			return err
		}
		right := target_call(target, [o(copied)], {}) or {
			release(copied, target, left)!
			return err
		}
		release(copied, target)!
		compared := call('operator.ne', o(left), o(right)) or {
			release(right, left)!
			return err
		}
		release(right, left)!
		input_changed := truth(compared) or {
			discard(compared)!
			return err
		}
		discard(compared)!
		if input_changed {
			prep_error('fixture input changed during generation: ', p.get('source'))!
		}
	}
	discard(iterator)!
}

fn compile_fixture(run string, p &Preparation) ! {
	discard(target_call(run, [o(p.get('compile_command'))], {})!)!
	str_target := resolve('str')!
	syscall := call('operator.getitem', o(p.get('copies')), v(ah.Value('init_syscall'))) or {
		discard(str_target)!
		return err
	}
	text := target_call(str_target, [o(syscall)], {}) or {
		release(syscall, str_target)!
		return err
	}
	release(syscall, str_target)!
	run_values(run, [p.get('cc'), lit('--target=aarch64-linux-musl')!, lit('-c')!, text, lit('-o')!,
		stringify(p.get('syscall_obj'))!], [p.get('cc')])!
	discard(target_call(run, [o(p.get('link_command'))], {})!)!
	ignore_method(p.get('init'), 'chmod', [v(ah.Value(0o755))], {})!
}

fn prep_enter(manager string) !string {
	return callback('enter', {
		'owner':   ah.Value(manager)
		'consume': ah.Value(true)
	})!.text()
}

fn prep_exit(manager string, cause ?IError) !bool {
	row := {
		'owner': ah.Value(manager)
		'error': if error := cause { detail(error) } else { ah.Value(json2.Null{}) }
	}
	result := callback('exit', row) or {
		discard(manager)!
		return err
	}
	discard(manager)!
	suppressed := result as bool
	if suppressed {
		if error := cause {
			callback('retire_error', {
				'error': detail(error)
			})!
		}
	}
	return suppressed
}

fn (mut p Preparation) archive() ! {
	p.save('archive_path', divide(p.state, 'initramfs.tar')!)!
	target := resolve('tarfile.open')!
	format := resolve('tarfile.USTAR_FORMAT') or {
		discard(target)!
		return err
	}
	manager := target_call(target, [o(p.get('archive_path')), v(ah.Value('w'))], {
		'format': o(format)
	}) or {
		release(format, target)!
		return err
	}
	release(format, target)!
	entered := prep_enter(manager) or {
		discard(manager)!
		return err
	}
	discard(manager)!
	p.save('archive', entered)!
	ignore_method(entered, 'add', [o(p.get('rootfs'))], {
		'arcname': v(ah.Value('.'))
	}) or {
		if !prep_exit(manager, err)! { return err }
		return
	}
	prep_exit(manager, none)!
}

fn (mut p Preparation) boot_disk() ! {
	p.save('conf', divide(p.state, 'limine.conf')!)!
	ignore_method(p.get('conf'), 'write_text', [v(ah.Value('timeout: 0\nverbose: yes\n\n/Vinix PCI configuration\n    protocol: limine\n    kernel_path: boot():/boot/vinix\n    module_path: boot():/boot/initramfs.tar\n    resolution: 1024x768x32\n    kaslr: no\n    cmdline: vinix.qemu_platform=1\n'))], {})!
	p.save('disk', divide(p.state, 'boot.img')!)!
	manager := method(p.get('disk'), 'open', [v(ah.Value('wb'))], {})!
	image := prep_enter(manager) or {
		discard(manager)!
		return err
	}
	discard(manager)!
	p.save('image', image)!
	ignore_method(image, 'truncate', [v(ah.Value(256 * 1024 * 1024))], {}) or {
		if !prep_exit(manager, err)! { return err }
		return
	}
	prep_exit(manager, none)!
}

fn (mut p Preparation) populate(run string) ! {
	format := call('operator.getitem', o(p.get('tools')), v(ah.Value('mformat')))!
	run_values(run, [format, lit('-F')!, lit('-i')!, stringify(p.get('disk'))!, lit('::')!], [])!
	for directory in ['::/EFI', '::/EFI/BOOT', '::/boot'] {
		p.save('directory', lit(directory)!)!
		tool := call('operator.getitem', o(p.get('tools')), v(ah.Value('mmd')))!
		run_values(run, [tool, lit('-i')!, stringify(p.get('disk'))!, p.get('directory')], [p.get('directory')])!
	}
	mut rows := []string{}
	for entry in [['loader', '::/EFI/BOOT/BOOTAA64.EFI'], ['kernel', '::/boot/vinix'],
		['conf', '::/boot/limine.conf'], ['archive_path', '::/boot/initramfs.tar']] {
		destination := lit(entry[1])!
		rows << tuple([p.get(entry[0]), destination])!
		discard(destination)!
	}
	all := tuple(rows)!
	release(...rows)!
	iterator := prep_iterator(all)!
	discard(all)!
	for {
		next := prep_next(iterator)!
		if next.done { break }
		values := callback('unpack_pair', {
			'owner': ah.Value(next.value)
		})!.items()
		discard(next.value)!
		p.save('source', values[0].text())!
		p.save('target', values[1].text())!
		tool := call('operator.getitem', o(p.get('tools')), v(ah.Value('mcopy')))!
		run_values(run, [tool, lit('-i')!, stringify(p.get('disk'))!, stringify(p.get('source'))!,
			p.get('target')], [p.get('target')])!
	}
	discard(iterator)!
	p.save('private_vars', divide(p.state, 'efivars.fd')!)!
	discard(call('shutil.copyfile', o(p.get('vars_template')), o(p.get('private_vars')))!)!
}

fn inputs_row(inputs string, row string) ! {
	values := callback('unpack_pair', {
		'owner': ah.Value(row)
	})!.items()
	discard(row)!
	name := values[0].text()
	path := values[1].text()
	text := stringify(path)!
	hash := call('digest', o(path)) or {
		release(text, path, name)!
		return err
	}
	record := empty_dict()!
	set_item(record, 'path', o(text))!
	set_item(record, 'sha256', o(hash))!
	release(text, hash)!
	discard(call('operator.setitem', o(inputs), o(name), o(record))!)!
	release(record, path, name)!
}

fn (p &Preparation) inputs(report string) ! {
	mut rows := []string{}
	for pair in [['kernel', 'kernel'], ['firmware', 'firmware'], ['bootloader', 'loader'],
		['vars_template', 'vars_template']] {
		name := lit(pair[0])!
		rows << tuple([name, p.get(pair[1])])!
		discard(name)!
	}
	items := method(p.get('copies'), 'items', [], {})!
	iterator := prep_iterator(items)!
	discard(items)!
	for {
		next := prep_next(iterator)!
		if next.done { break }
		rows << next.value
	}
	discard(iterator)!
	for pair in [['generated_init_source', 'generated_source'], ['init', 'init'],
		['initramfs', 'archive_path'], ['limine_conf', 'conf']] {
		name := lit(pair[0])!
		rows << tuple([name, p.get(pair[1])])!
		discard(name)!
	}
	all := tuple(rows)!
	release(...rows)!
	loop := prep_iterator(all)!
	discard(all)!
	inputs := empty_dict()!
	for {
		next := prep_next(loop)!
		if next.done { break }
		inputs_row(inputs, next.value)!
	}
	discard(loop)!
	set_item(report, 'inputs', o(inputs))!
	discard(inputs)!
	set_item(report, 'original_input_paths', o(p.get('originals')))!
}

fn (mut p Preparation) launch_command(commands string, report string) ! {
	p.save('serial', divide(p.state, 'serial.log')!)!
	mut values := [stringify(p.get('qemu'))!]
	for text in ['-machine', 'virt,gic-version=3', '-accel', 'tcg', '-cpu', 'max', '-m', '1024',
		'-smp', '4', '-display', 'none', '-monitor', 'none', '-device', 'ramfb', '-drive'] {
		values << lit(text)!
	}
	values << prefixed('if=pflash,format=raw,unit=0,readonly=on,file=', p.get('firmware'))!
	values << lit('-drive')!
	values << prefixed('if=pflash,format=raw,unit=1,file=', p.get('private_vars'))!
	values << lit('-drive')!
	values << prefixed('if=none,id=bootdisk,format=raw,file=', p.get('disk'))!
	for text in ['-device', 'virtio-blk-pci,drive=bootdisk', '-device', 'e1000', '-nic', 'none',
		'-serial'] {
		values << lit(text)!
	}
	values << prefixed('file:', p.get('serial'))!
	values << lit('-no-reboot')!
	command := list(values)!
	release(...values)!
	p.save('command', command)!
	ignore_method(commands, 'append', [o(command)], {})!
	path := divide(p.state, 'commands.json')!
	writer := attribute(path, 'write_text') or {
		discard(path)!
		return err
	}
	discard(path)!
	encoded := callback('function', {
		'name':   ah.Value('json.dumps')
		'call':   ah.Value(true)
		'args':   ah.Value([o(commands)])
		'kwargs': ah.Value({
			'indent': v(ah.Value(2))
		})
	})!.text()
	text := call('operator.add', o(encoded), v(ah.Value('\n'))) or {
		release(encoded, writer)!
		return err
	}
	discard(encoded)!
	result := target_call(writer, [o(text)], {}) or {
		release(text, writer)!
		return err
	}
	release(text, writer, result)!
	set_item(report, 'status', v(ah.Value('running')))!
}

fn prepare_finish_body(ids []ah.Value) ! {
	mut p := Preparation{ args: ids[0].text(), state: ids[1].text(), frame: ids[5].text() }
	p.load(['qemu', 'share', 'firmware', 'vars_template', 'loader', 'kernel', 'path', 'frozen',
		'originals', 'copies', 'fixture', 'fixture_inputs', 'name', 'source', 'before', 'target',
		'cc', 'ld', 'tools', 'rootfs', 'directory', 'obj', 'syscall_obj', 'generated_source', 'init',
		'compile_command', 'link_command'])!
	run := ids[4].text()
	generated_fixture(run, p)!
	p.check_generated()!
	compile_fixture(run, p)!
	p.archive()!
	p.boot_disk()!
	p.populate(run)!
	p.inputs(ids[2].text())!
	p.launch_command(ids[3].text(), ids[2].text())!
}

fn prepare_finish(ids []ah.Value) ! {
	point := checkpoint()!
	prepare_finish_body(ids) or {
		clear_preparation_since(point)!
		return err
	}
}
