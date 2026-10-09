module runnercore

import androidhost as ah
import boothost
import runtimebuild as rb

fn image_api(root ah.Value, output ah.Value, linux bool) ! {
	rb.api('image', [o(root), o(output), rb.ordinary(ah.Value(linux))], {}, false)!
}

fn guest_plan(args ah.Value, work ah.Value, root ah.Value, os_name ah.Value) !(ah.Value, ah.Value) {
	mut command := rb.null()
	mut environment := rb.null()
	if rb.eq_value(os_name, ah.Value('debian'))! {
		linux_root := join(work, 'debian-root')!
		if test(linux_root, 'exists')! {
			rb.call('invoke', 'shutil', 'rmtree', [o(linux_root)], {})!
		}
		rb.api('copy_layer', [o(root), o(linux_root)], {}, false)!
		mkdir(join(linux_root, 'sys')!, false)!
		rb.api('copy_layer', [o(attr(args, 'debian_root')!), o(linux_root)], {}, false)!
		candidates := rb.call('acquire', 'builtins', 'tuple', [o(rb.make_sequence([
			o(join(attr(args, 'debian_root')!, 'usr/bin/busybox')!),
			o(join(attr(args, 'debian_root')!, 'bin/busybox')!),
		])!)], {})!
		choices := rb.api('_iter_test', [o(candidates), v('exists')], {}, true)!
		busybox := builtin('next', [o(choices)])!
		copy(busybox, join(linux_root, 'bin/busybox')!)!
		rb.method('invoke', join(linux_root, 'init')!, 'symlink_to', [v('sbin/init')], {})!
		initrd := join(work, 'initrd.cpio')!
		image_api(linux_root, initrd, true)!
		command = rb.make_sequence([v('qemu-system-aarch64'), v('-machine'), v('virt,gic-version=3'),
			v('-accel'), v('hvf'), v('-cpu'), v('host'), v('-smp'), v('4'), v('-m'), v('8192'),
			v('-kernel'), o(py_str(attr(args, 'debian_kernel')!)!), v('-initrd'), o(py_str(initrd)!),
			v('-append'), v('console=ttyAMA0 rdinit=/init quiet'), v('-display'), v('none'),
			v('-serial'), v('mon:stdio'), v('-no-reboot')])!
		environment = method(attr(global('os')!, 'environ')!, 'copy', [])!
	} else {
		archive := join(work, 'initramfs.tar')!
		image_api(root, archive, false)!
		environment = method(attr(global('os')!, 'environ')!, 'copy', [])!
		updates := rb.dictionary([v('VINIX_KERNEL_DIR'), v('VINIX_INITRAMFS'),
			v('VINIX_INITRAMFS_COMPRESSED'), v('VINIX_QEMU_ROOT_DISK'), v('VINIX_BOOT_DISK'),
			v('VINIX_EFIVARS'), v('VINIX_BOOT_DISK_SIZE_MB'), v('VINIX_QEMU_PACKAGE_STORE'),
			v('VINIX_QEMU_PACKAGE_PERSIST'), v('VINIX_QEMU_HOST_SOURCE'), v('VINIX_QEMU_AUDIO'),
			v('VINIX_QEMU_SMP'), v('VINIX_KEEP_TEMP_BOOT_DISK')], [
			o(py_str(attr(args, 'kernel_dir')!)!),
			o(py_str(archive)!),
			v('0'),
			v('0'),
			o(py_str(join(work, 'boot.img')!)!),
			o(py_str(join(work, 'efivars.fd')!)!),
			v('2048'),
			o(py_str(join(work, 'packages.tar')!)!),
			v('0'),
			v('0'),
			v('off'),
			v('4'),
			v('1'),
		])!
		rb.method('invoke', environment, 'update', [o(updates)], {})!
		command = rb.make_sequence([
			o(py_str(join(attr(args, 'repo')!, 'scripts/run-aarch64.sh')!)!),
			v('--no-build'),
			v('--serial'),
			v('--no-persist'),
			v('--mem=8192'),
		])!
	}
	return command, environment
}

fn caught(cause IError, kinds []string) !bool {
	if cause is boothost.BindingError {
		return rb.callback('exception_is', {
			'error': ah.Value(cause.value)
			'kinds': rb.strings(kinds)
		})! == ah.Value(true)
	}
	return false
}

fn clock() !ah.Value { return rb.call('acquire', 'time', 'monotonic', [], {})! }

fn add_number(value ah.Value, number int) !ah.Value {
	return rb.call('acquire', 'operator', 'add', [o(value), rb.ordinary(ah.Value(number))], {})!
}

fn before(left ah.Value, right ah.Value) !bool {
	return rb.bool_object(rb.call('acquire', 'operator', 'lt', [o(left), o(right)], {})!)!
}

fn read_step_body(master ah.Value, transcript ah.Value, deadline ah.Value, log ah.Value, locals ah.Value) !bool {
	if !before(clock()!, deadline)! { return true }
	ready := rb.call('acquire', 'select', 'select', [
		o(rb.make_sequence([o(master)])!),
		o(rb.make_sequence([])!),
		o(rb.make_sequence([])!),
		rb.ordinary(ah.Value(1)),
	], {})!
	if !rb.bool_object(getitem(ready, rb.ordinary(ah.Value(0)))!)! { return false }
	chunk := rb.call('acquire', 'os', 'read', [o(master), rb.ordinary(ah.Value(65536))], {}) or {
		if caught(err, ['OSError'])! { return true }
		return err
	}
	rb.method('invoke', locals, '__setitem__', [v('chunk'), o(chunk)], {})!
	if !rb.bool_object(chunk)! { return true }
	rb.method('invoke', transcript, 'extend', [o(chunk)], {})!
	rb.method('invoke', log, 'write', [o(chunk)], {})!
	rb.method('invoke', log, 'flush', [], {})!
	selection := rb.call('acquire', 'builtins', 'slice', [
		rb.ordinary(ah.Value(-65536)),
		rb.ordinary(rb.null()),
	], {})!
	recent := getitem(transcript, o(selection))!
	rb.method('invoke', locals, '__setitem__', [v('recent'), o(recent)], {})!
	markers := rb.call('acquire', 'builtins', 'tuple', [o(rb.make_sequence([
		o(raw('DHEWM3-DONE')!),
		o(raw('DHEWM3-FAILED')!),
		o(raw('KERNEL PANIC')!),
		o(raw('crashed with signal')!),
	])!)], {})!
	checks := rb.api('_iter_contains', [o(markers), o(recent)], {}, true)!
	checked := builtin('any', [o(checks)])!
	rb.callback('release', {
		'ids': ah.Value([checks])
	})!
	return rb.bool_object(checked)!
}

fn read_step(master ah.Value, transcript ah.Value, deadline ah.Value, log ah.Value, locals ah.Value) !bool {
	checkpoint := rb.callback('checkpoint', {})!
	mut stopped := false
	mut failed := false
	mut cause := IError(none)
	stopped = read_step_body(master, transcript, deadline, log, locals) or {
		failed = true
		cause = err
		false
	}
	// Only the completed step's temporary IDs retire; persistent handles precede it.
	rb.callback('release_since', {
		'id': checkpoint
	})!
	if failed { return cause }
	return stopped
}

fn read_log(master ah.Value, transcript ah.Value, deadline ah.Value, log ah.Value, locals ah.Value) ! {
	for { if read_step(master, transcript, deadline, log, locals)! { break } }
}

fn read_guest(master ah.Value, transcript ah.Value, deadline ah.Value, work ah.Value, os_name ah.Value) ! {
	locals := rb.call('acquire', 'builtins', 'dict', [], {})!
	log := rb.method('enter', join(work, text(os_name)! + '.log')!, 'open', [v('wb')], {})!
	mut failed := false
	mut cause := IError(none)
	read_log(master, transcript, deadline, log, locals) or {
		failed = true
		cause = err
	}
	suppressed := exit(log, failed, cause)!
	if failed && !suppressed { return cause }
}

fn guest_body(guard ah.Value, args ah.Value, work ah.Value, root ah.Value, os_name ah.Value) !ah.Value {
	command, environment := guest_plan(args, work, root, os_name)!
	action := if flag(args, 'record')! {
		'recording'
	} else if flag(args, 'screenshot')! {
		'capturing'
	} else if flag(args, 'clock_only')! {
		'checking clocks'
	} else {
		'benchmarking'
	}
	rb.callback('print', {
		'data':    ah.Value('Booting ' + text(os_name)! + ', ' + action)
		'options': ah.Value({
			'flush': ah.Value(true)
		})
	})!
	pair := method(guard, 'fork_exec', [o(args), o(command), o(environment)])!
	values := rb.callback('unpack_pair', {
		'id': pair
	})!.items()
	transcript := builtin('bytearray', [])!
	deadline := rb.call('acquire', 'operator', 'add', [o(clock()!), o(attr(args, 'timeout')!)], {})!
	rb.method('invoke', guard, 'arm', [], {})!
	read_guest(values[1], transcript, deadline, work, os_name)!
	return transcript
}

fn guest(args ah.Value, work ah.Value, root ah.Value, os_name ah.Value) !ah.Value {
	guard := rb.callback('enter_existing', {
		'id': rb.api('_guest_owner', [], {}, true)!
	})!
	mut transcript := rb.null()
	mut failed := false
	mut cause := IError(none)
	transcript = guest_body(guard, args, work, root, os_name) or {
		failed = true
		cause = err
		rb.null()
	}
	rb.method('invoke', guard, 'normal_exit', [], {})!
	suppressed := exit(guard, failed, cause)!
	if failed && !suppressed { return cause }
	return result(args, work, transcript, os_name)!
}

fn stop_body(guard ah.Value) ! {
	pid := attr(guard, 'pid')!
	master := attr(guard, 'master')!
	stop_request(pid, master) or {
		if !caught(err, ['OSError', 'ProcessLookupError'])! {
			return err
		}
	}
	stop_deadline := add_number(clock()!, 5)!
	mut reaped := false
	for before(clock()!, stop_deadline)! {
		status := method(guard, 'wait_once', [])!
		if rb.eq(getitem(status, rb.ordinary(ah.Value(0)))!, pid)! {
			reaped = true
			break
		}
		rb.call('invoke', 'time', 'sleep', [rb.ordinary(ah.Value(ah.Number{'0.1'}))], {})!
	}
	if !reaped {
		rb.call('invoke', 'os', 'killpg', [o(pid), o(attr(global('signal')!, 'SIGKILL')!)], {}) or {
			if !caught(err, ['OSError'])! { return err }
			rb.call('invoke', 'os', 'kill', [o(pid), o(attr(global('signal')!, 'SIGKILL')!)], {}) or {
				if !caught(err, ['ProcessLookupError'])! { return err }
			}
		}
		rb.method('invoke', guard, 'wait_once', [], {})!
	}
	rb.method('invoke', guard, 'close_fd', [], {})!
}

fn stop_request(pid ah.Value, master ah.Value) ! {
	rb.call('invoke', 'os', 'write', [o(master), o(raw('\x01x')!)], {})!
	rb.call('invoke', 'time', 'sleep', [rb.ordinary(ah.Value(1))], {})!
	rb.call('invoke', 'os', 'killpg', [o(pid), o(attr(global('signal')!, 'SIGTERM')!)], {})!
}

fn shutdown(guard ah.Value) ! {
	mut failed := false
	mut cause := IError(none)
	stop_body(guard) or {
		failed = true
		cause = err
	}
	rb.method('invoke', guard, 'finish', [], {})!
	if failed { return cause }
}
