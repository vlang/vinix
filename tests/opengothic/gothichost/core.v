// SPDX-License-Identifier: MIT
module gothichost

import androidhost as ah
import json2

fn global(name string) !string {
	return callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn lit(value string) !string { return literal(ah.Value(value))! }

fn str(value string) !string { return call('str', o(value))! }

fn attr(value string, name string) !string { return attribute(value, name)! }

fn exists(value string) !bool { return truth(method(value, 'exists', [], {})!)! }

fn symlink(value string) !bool { return truth(method(value, 'is_symlink', [], {})!)! }

fn is_dir(value string) !bool { return truth(method(value, 'is_dir', [], {})!)! }

fn append(value string, item string) ! { method(value, 'append', [o(item)], {})! }

fn words(items []string) !string {
	mut result := []string{}
	for item in items { result << lit(item)! }
	return collection('list', result)!
}

fn mkdir(value string, parents bool) ! {
	mut kw := {
		'exist_ok': v(ah.Value(true))
	}
	if parents { kw['parents'] = v(ah.Value(true)) }
	method(value, 'mkdir', [], kw)!
}

fn public(name string, args []string) !string { return invoke(name, args.map(o(it)), {})! }

fn close(owner string, cause ?IError) ! {
	mut record := ah.Value(json2.Null{})
	if failure := cause { record = detail(failure) }
	callback('close', {
		'owner': ah.Value(owner)
		'error': record
	})!
}

fn copy_layer(source string, dest string) ! {
	mkdir(dest, true)!
	iter := iterator(method(source, 'iterdir', [], {})!)!
	for {
		item := next(iter)!
		if item.done { break }
		target := call('operator.truediv', o(dest), o(attr(item.value, 'name')!))!
		if symlink(item.value)! {
			if exists(target)! || symlink(target)! { method(target, 'unlink', [], {})! }
			method(target, 'symlink_to', [o(call('os.readlink', o(item.value))!)], {})!
		} else if is_dir(item.value)! {
			public('copy_layer', [item.value, target])!
		} else {
			if exists(target)! || symlink(target)! { method(target, 'unlink', [], {})! }
			call('shutil.copy2', o(item.value), o(target))!
		}
	}
}

fn prepare(args string, work string) !string {
	root := join(work, 'root')!
	if !exists(join(root, '.prepared')!)! {
		if exists(root)! { call('shutil.rmtree', o(root))! }
		public('copy_layer', [join(attr(args, 'repo')!, 'build-aarch64-x11/staging')!, root])!
		userland := join(attr(args, 'repo')!, 'build-aarch64-userland/staging')!
		for directory in ['lib', 'usr/lib'] {
			libraries := iterator(method(join(userland, directory)!, 'glob', [v(ah.Value('*.so*'))], {})!)!
			for {
				library := next(libraries)!
				if library.done { break }
				target := call('operator.truediv', o(join(root, directory)!), o(attr(library.value, 'name')!))!
				if !exists(target)! && !symlink(target)! {
					if symlink(library.value)! {
						method(target, 'symlink_to', [o(call('os.readlink', o(library.value))!)], {})!
					} else {
						call('shutil.copy2', o(library.value), o(target))!
					}
				}
			}
		}
		mkdir(join(root, 'bin')!, false)!
		call('shutil.copy2', o(join(userland, 'bin/busybox')!), o(join(root, 'bin/busybox')!))!
		tools := iterator(global('TOOLS')!)!
		for {
			tool := next(tools)!
			if tool.done { break }
			method(call('operator.truediv', o(join(root, 'bin')!), o(tool.value))!, 'symlink_to', [v(ah.Value('busybox'))], {})!
		}
		for dir in ['sbin', 'proc', 'dev', 'sys', 'tmp', 'root', 'run', 'etc'] {
			mkdir(join(root, dir)!, true)!
		}
		method(join(root, 'etc/passwd')!, 'write_text', [v(ah.Value('root:x:0:0:root:/root:/bin/sh\n'))], {})!
		method(join(root, 'etc/group')!, 'write_text', [v(ah.Value('root:x:0:root\n'))], {})!
		method(join(root, '.prepared')!, 'touch', [], {})!
	}
	for stale in ['opt/opengothic', 'usr/share/games/gothic2'] {
		path := join(root, stale)!
		if exists(path)! { call('shutil.rmtree', o(path))! }
	}
	public('copy_layer', [join(attr(args, 'build')!, 'staging')!, root])!
	if truth(attr(args, 'engine')!)! {
		call('shutil.copy2', o(attr(args, 'engine')!), o(join(root, 'opt/opengothic/Gothic2Notr')!))!
	}
	videos := iterator(method(join(root, 'usr/share/games/gothic2')!, 'rglob', [v(ah.Value('*'))], {})!)!
	for {
		video := next(videos)!
		if video.done { break }
		if compare('eq', method(attr(video.value, 'name')!, 'lower', [], {})!, lit('intro.bik')!)! {
			method(video.value, 'unlink', [], {})!
		}
	}
	call('shutil.copy2', o(attr(args, 'desktop')!), o(join(root, 'usr/bin/vinix-desktop')!))!
	link := join(root, 'usr/bin/vinix-opengothic')!
	if symlink(link)! || exists(link)! { method(link, 'unlink', [], {})! }
	method(link, 'symlink_to', [v(ah.Value('vinix-desktop'))], {})!
	sysroot := join(attr(args, 'repo')!, 'build-aarch64-x11/sysroot')!
	host_core := join(root, 'wine-host-core.c')!
	invoke('subprocess.run', [o(collection('list', [lit('python3')!,
		str(join(global('ROOT')!, 'build-support/xorg-server/compile-v-host.py')!)!, lit('winehost')!,
		str(host_core)!, lit('--arch')!, lit('arm64')!])!)], {
		'check': v(ah.Value(true))
	})!
	argv := words(['aarch64-linux-musl-gcc', '-O2', '-w', '-D__vinix__',
		'-I' + text(sysroot)! + '/usr/include'])!
	append(argv, str(host_core)!)!
	for item in ['-I' + text(global('ROOT')!)! + '/build-support/xorg-server',
		'-L' + text(sysroot)! + '/usr/lib', '-L' + text(sysroot)! + '/lib',
		'-Wl,--allow-shlib-undefined', '-lXtst', '-lXdamage', '-lX11', '-lXext', '-lxcb', '-o'] {
		append(argv, lit(item)!)!
	}
	append(argv, str(join(root, 'usr/bin/vinix-wine-host')!)!)!
	invoke('subprocess.run', [o(argv)], {
		'check': v(ah.Value(true))
	})!
	if truth(attr(args, 'venus')!)! {
		public('copy_layer', [attr(args, 'venus_runtime')!, root])!
		launcher := method(join(global('ROOT')!, 'build-support/opengothic/run-opengothic')!, 'read_text', [], {})!
		changed := method(launcher, 'replace', [v(ah.Value('set -eu')),
			v(ah.Value('set -eu\nexport VK_INSTANCE_LAYERS=VK_LAYER_MESA_overlay\nexport VK_LAYER_PATH=/opt/venus/share/vulkan/explicit_layer.d\nexport VK_LAYER_MESA_OVERLAY_CONFIG=fps,frame_timing,position=top-left,output_file=/tmp/gothic-fps.csv,fps_sampling_period=500'))], {})!
		launch_path := join(root, 'usr/bin/run-opengothic')!
		method(launch_path, 'unlink', [], {})!
		method(launch_path, 'write_text', [o(changed)], {})!
		method(launch_path, 'chmod', [v(ah.Value(0o755))], {})!
	}
	call('shutil.copy2', o(method(call('Path', o(global('__file__')!))!, 'with_name', [v(ah.Value('guest-init.sh'))], {})!), o(join(root, 'sbin/init')!))!
	method(join(root, 'sbin/init')!, 'chmod', [v(ah.Value(0o755))], {})!
	return root
}

fn press(socket_path string, key string, seconds string) ! {
	spec := call('importlib.util.spec_from_file_location', v(ah.Value('vinix_input')), o(join(global('ROOT')!, 'desktop/tools/input.py')!))!
	module_object := call('importlib.util.module_from_spec', o(spec))!
	method(attr(spec, 'loader')!, 'exec_module', [o(module_object)], {})!
	monitor := callback('function', {
		'owner':       ah.Value(module_object)
		'name':        ah.Value('Monitor')
		'args':        ah.Value([o(str(socket_path)!)])
		'own_methods': ah.Value([ah.Value('stream.close'), ah.Value('sock.close')])
	})!.text()
	press_body(monitor, key, seconds) or {
		failure := err
		close(monitor, failure)!
		return failure
	}
	close(monitor, none)!
}

fn press_body(monitor string, key string, seconds string) ! {
	for down in [true, false] {
		value := call('builtins.dict')!
		key_record := call('builtins.dict')!
		callback('function', {
			'name': ah.Value('operator.setitem')
			'args': ah.Value([o(key_record), v(ah.Value('type')), v(ah.Value('qcode'))])
		})!
		callback('function', {
			'name': ah.Value('operator.setitem')
			'args': ah.Value([o(key_record), v(ah.Value('data')), o(key)])
		})!
		data := call('builtins.dict')!
		call('operator.setitem', o(data), v(ah.Value('down')), v(ah.Value(down)))!
		call('operator.setitem', o(data), v(ah.Value('key')), o(key_record))!
		call('operator.setitem', o(value), v(ah.Value('type')), v(ah.Value('key')))!
		call('operator.setitem', o(value), v(ah.Value('data')), o(data))!
		method(monitor, 'send_input', [o(collection('list', [value])!)], {})!
		call('time.sleep', o(if down { seconds } else { literal(ah.Value(ah.Number{'0.12'}))! }))!
	}
}

fn main_policy(args string, parser string) ! {
	callback('set_attribute', {
		'owner': ah.Value(args)
		'name':  ah.Value('repo')
		'value': o(method(attr(args, 'repo')!, 'resolve', [], {})!)
	})!
	for row in [['build', 'build/opengothic', 'repo'],
		['venus_runtime', 'build-aarch64-venus/staging', 'repo'],
		['desktop', 'build/vinix-desktop', 'ROOT'], ['kernel_dir', 'kernel', 'repo']] {
		prior := attr(args, row[0])!
		fallback := if row[2] == 'ROOT' { global('ROOT')! } else { attr(args, row[2])! }
		chosen := if truth(prior)! { prior } else { join(fallback, row[1])! }
		callback('set_attribute', {
			'owner': ah.Value(args)
			'name':  ah.Value(row[0])
			'value': o(method(chosen, 'resolve', [], {})!)
		})!
	}
	if !is_dir(join(attr(args, 'build')!, 'staging/usr/share/games/gothic2/_work/Data')!)! {
		method(parser, 'error', [v(ah.Value('no game data is staged: run scripts/build-opengothic-aarch64.sh with --demo or --game'))], {})!
	}
	work := method(attr(args, 'work')!, 'resolve', [], {})!
	mkdir(work, true)!
	screenshot := public('run_guest', [args, work, public('prepare', [args, work])!])!
	call('print', v(ah.Value('OpenGothic rendered the world for ' + text(attr(args, 'seconds')!)! + ' s: ' + text(screenshot)!)))!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'copy_layer' { copy_layer(args[0], args[1])! }
		'prepare' { return ah.Value(prepare(args[0], args[1])!) }
		'press' { press(args[0], args[1], args[2])! }
		'main' { main_policy(args[0], args[1])! }
		else { return error('unknown OpenGothic host policy') }
	}
	return ah.Value(null()!)
}
