module runnercore

import androidhost as ah
import runtimebuild as rb

fn copy_layer(source ah.Value, dest ah.Value) ! {
	mkdir(dest, true)!
	iter := rb.iter_object(method(source, 'iterdir', [])!)!
	for {
		entry := rb.next(iter)!
		if entry == rb.null() { break }
		target := method(dest, '__truediv__', [o(attr(entry, 'name')!)])!
		if test(entry, 'is_symlink')! {
			if test(target, 'is_dir')! && !test(target, 'is_symlink')! { continue }
			if test(target, 'exists')! || test(target, 'is_symlink')! {
				rb.method('invoke', target, 'unlink', [], {})!
			}
			rb.method('invoke', target, 'symlink_to', [o(rb.call('acquire', 'os', 'readlink', [o(entry)], {})!)], {})!
		} else if test(entry, 'is_dir')! {
			native_copy(entry, target)!
		} else {
			if test(target, 'is_symlink')! { rb.method('invoke', target, 'unlink', [], {})! }
			copy(entry, target)!
		}
	}
}

fn fixture_file(name string) !ah.Value {
	return method(make_path(global('__file__')!)!, 'with_name', [v(name)])!
}

fn prepare(args ah.Value, work ah.Value) !ah.Value {
	root := join(work, 'root')!
	if !test(join(root, '.prepared')!, 'exists')! {
		if test(root, 'exists')! { rb.call('invoke', 'shutil', 'rmtree', [o(root)], {})! }
		native_copy(join(attr(args, 'build')!, 'staging')!, root)!
		native_copy(join(attr(args, 'repo')!, 'build-aarch64-x11/staging/usr')!, join(root, 'usr')!)!
		mkdir(join(root, 'bin')!, false)!
		copy(join(attr(args, 'repo')!, 'build-aarch64-userland/staging/bin/busybox')!, join(root, 'bin/busybox')!)!
		for name in ['sh', 'cat', 'mkdir', 'chmod', 'chown', 'sleep', 'kill', 'base64', 'uname',
			'mount', 'grep'] {
			rb.method('invoke', join(join(root, 'bin')!, name)!, 'symlink_to', [v('busybox')], {})!
		}
		loader := join(root, 'lib/ld-musl-aarch64.so.1')!
		if test(loader, 'is_symlink')! { rb.method('invoke', loader, 'unlink', [], {})! }
		copy(join(attr(args, 'repo')!, 'build-aarch64-userland/staging/lib/ld-musl-aarch64.so.1')!, loader)!
		for directory in ['sbin', 'proc', 'dev', 'tmp', 'root', 'run', 'opt/dhewm3', 'etc'] {
			mkdir(join(root, directory)!, true)!
		}
		rb.method('invoke', join(root, 'etc/passwd')!, 'write_text', [v('root:x:0:0:root:/root:/bin/sh\ndoom:x:1000:1000:Doom:/home/doom:/bin/sh\n')], {})!
		rb.method('invoke', join(root, 'etc/group')!, 'write_text', [v('root:x:0:root\ndoom:x:1000:doom\n')], {})!
		rb.method('invoke', join(root, '.prepared')!, 'touch', [], {})!
	}
	copy(fixture_file('guest-init.sh')!, join(root, 'sbin/init')!)!
	for helper in ['as-user', 'clock-probe'] {
		argv := rb.make_sequence([v('aarch64-linux-musl-gcc'), v('-O2'), v('-Wall'), v('-Wextra'),
			v('-static'), o(py_str(fixture_file(helper + '.c')!)!), v('-o'),
			o(py_str(join(join(root, 'opt/dhewm3')!, helper)!)!)])!
		rb.call('invoke', 'subprocess', 'run', [o(argv)], {
			'check': ah.Value(true)
		})!
	}
	mode := if flag(args, 'record')! {
		'record'
	} else if flag(args, 'screenshot')! {
		'screenshot'
	} else if flag(args, 'clock_only')! {
		'clock'
	} else {
		'benchmark'
	}
	config := 'MODE=' + mode + '\nROUNDS=' + text(attr(args, 'rounds')!)! + '\nCHECK_CLOCK=' + text(rb.api('_call_name', [
		v('int'),
		o(attr(args, 'check_clock')!),
	], {}, true)!)! + '\n'
	rb.method('invoke', join(root, 'opt/dhewm3/config')!, 'write_text', [v(config)], {})!
	if !flag(args, 'record')! && !flag(args, 'clock_only')! {
		demo := join(work, 'vinix-demo.demo')!
		if !test(demo, 'exists')! { return failure('Record a shared demo first with --record') }
		target := join(root, 'usr/share/games/dhewm3/demo/demos/vinix-demo.demo')!
		mkdir(attr(target, 'parent')!, false)!
		copy(demo, target)!
	}
	return root
}

fn cpio_body(root ah.Value, names ah.Value, out ah.Value) ! {
	joined := method(literal('\n')!, 'join', [o(names)])!
	data := method(rb.call('acquire', 'operator', 'add', [o(joined), v('\n')], {})!, 'encode', [])!
	rb.callback('invoke', {
		'module':          ah.Value('subprocess')
		'name':            ah.Value('run')
		'arguments':       ah.Value([rb.ordinary(rb.strings(['cpio', '-o', '-H', 'newc', '--quiet']))])
		'keyword_objects': ah.Value({
			'cwd':    root
			'input':  data
			'stdout': out
			'check':  rb.callback('retain', {
				'value': rb.ordinary(ah.Value(true))
			})!
		})
	})!
}

fn image(root ah.Value, output ah.Value, linux bool) ! {
	if linux {
		names := rb.make_sequence([v('.')])!
		paths := rb.iter_object(rb.api('_call_name', [v('sorted'), o(method(root, 'rglob', [v('*')])!)], {}, true)!)!
		for {
			path := rb.next(paths)!
			if path == rb.null() { break }
			append(names, py_str(method(path, 'relative_to', [o(root)])!)!)!
		}
		out := rb.method('enter', output, 'open', [v('wb')], {})!
		mut failed := false
		mut cause := IError(none)
		cpio_body(root, names, out) or {
			failed = true
			cause = err
		}
		suppressed := exit(out, failed, cause)!
		if failed && !suppressed { return cause }
	} else {
		tar := rb.callback('enter', {
			'module':          ah.Value('tarfile')
			'name':            ah.Value('open')
			'arguments':       ah.Value([o(output), v('w')])
			'keyword_objects': ah.Value({
				'format': attr(global('tarfile')!, 'USTAR_FORMAT')!
			})
		})!
		mut failed := false
		mut cause := IError(none)
		rb.method('invoke', tar, 'add', [o(root)], {
			'arcname': ah.Value('.')
		}) or {
			failed = true
			cause = err
		}
		suppressed := exit(tar, failed, cause)!
		if failed && !suppressed { return cause }
	}
}
