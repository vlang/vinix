module runhost

import androidhost as ah
import json2
import math.big

fn payload_size(value string) !big.Integer {
	row := callback('stat', {
		'path':   ah.Value(value)
		'fields': strings(['st_size'])
	})!.object()
	return big.integer_from_string(ah.encode(ah.field(row, 'st_size')))!
}

fn vm_plan(args map[string]ah.Value, overlay ah.Value, root string) !ah.Value {
	state := attribute_text(args, 'state_dir')!
	socket := join([state, 'qmp.sock'])!
	if test('exists', socket)! {
		return failure('QMP socket already exists: ' + socket + '; choose another --state-dir')
	}
	snapshot := join([state, 'kernel/bin'])!
	mkdir(snapshot, true, true)!
	copy(join([attribute_text(args, 'kernel_dir')!, 'bin/vinix'])!, join([snapshot, 'vinix'])!)!
	mut payload := payload_size(attribute_text(args, 'initramfs')!)!
	if overlay !is json2.Null {
		for item in list('rglob', overlay.text(), [ah.Value('*')])! {
			if test('is_file', item)! && !test('is_symlink', item)! {
				payload = payload + payload_size(item)!
			}
		}
	}
	megabyte := big.integer_from_int(1024 * 1024)
	unit := big.integer_from_int(512)
	minimum := big.integer_from_int(4096)
	requested := ((payload / megabyte + big.integer_from_int(256 + 511)) / unit) * unit
	size := if requested < minimum { minimum } else { requested }
	mut environment := callback('environ', map[string]ah.Value{})!.object()
	environment['VINIX_KERNEL_DIR'] = path('parent', snapshot, []ah.Value{}, map[string]ah.Value{})!
	environment['VINIX_INITRAMFS'] = attribute_string('initramfs')!
	environment['VINIX_INITRAMFS_COMPRESSED'] = ah.Value(if path('suffix', attribute_text(args, 'initramfs')!, []ah.Value{}, map[string]ah.Value{})!.text() == '.gz' {
		'1'
	} else {
		'0'
	})
	environment['VINIX_QEMU_ROOT_DISK'] = ah.Value('0')
	environment['VINIX_BOOT_DISK'] = ah.Value(join([state, 'boot.img'])!)
	environment['VINIX_EFIVARS'] = ah.Value(join([state, 'efivars.fd'])!)
	environment['VINIX_BOOT_DISK_SIZE_MB'] = ah.Value(size.str())
	environment['VINIX_QEMU_PACKAGE_STORE'] = ah.Value(join([state, 'packages.tar'])!)
	environment['VINIX_QEMU_PACKAGE_PERSIST'] = ah.Value('0')
	environment['VINIX_QEMU_HOST_SOURCE'] = ah.Value('0')
	environment['VINIX_KEEP_TEMP_BOOT_DISK'] = ah.Value('1')
	environment['VINIX_QEMU_AUDIO'] = ah.Value('off')
	environment['VINIX_QEMU_SMP'] = attribute_string('cpus')!
	environment['VINIX_QEMU_EXTRA'] = ah.Value('-qmp unix:' + socket + ',server=on,wait=off')
	if overlay !is json2.Null {
		environment['VINIX_QEMU_OVERLAY'] = overlay
	} else {
		environment.delete('VINIX_QEMU_OVERLAY')
	}
	if callback('platform', map[string]ah.Value{})!.text() != 'Darwin' {
		environment['USE_TCG'] = ah.Value('1')
	} else if truth(attribute(args, 'interactive')!) {
		environment['QEMU_DISPLAY_BACKEND'] = ah.Value('cocoa')
	}
	mut argv := [join([attribute_text(args, 'repo')!, 'scripts/run-aarch64.sh'])!, '--no-build',
		'--no-persist', '--mem=' + attribute_string('memory')!.text(),
		'--guest-init=' + join([root, 'tests/android/guest-init.sh'])!]
	if !truth(attribute(args, 'interactive')!) { argv << '--serial' }
	return ah.Value({
		'state':       ah.Value(state)
		'socket':      ah.Value(socket)
		'environment': ah.Value(environment)
		'command':     strings(argv)
	})
}
