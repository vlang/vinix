// SPDX-License-Identifier: MIT
module gothicguest

import androidhost as ah
import gapcore as gc
import json2

fn global(name string) !string {
	return gc.callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn float(text string) ah.Value { return v(ah.Value(ah.Number{text})) }

fn close_guest(pid string, master string) ! {
	gc.callback('retiring', {}) or {
		failure := err
		gc.activate(failure, true)!
		stop_owned(pid, master)!
		return failure
	}
	stop_owned(pid, master)!
}

fn stop_owned(pid string, master string) ! {
	stop_process(pid, master) or { return err }
	call('os.close', o(master))!
	gc.callback('closed', {})!
}

fn terminate(pid string, master string) ! {
	call('os.write', o(master), b('0178'))!
	call('time.sleep', n(1))!
	call('os.killpg', o(pid), o(global('signal.SIGTERM')!))!
}

fn stop_process(pid string, master string) ! {
	terminate(pid, master) or {
		if !exception_any(err, ['OSError', 'ProcessLookupError'])! {
			return err
		}
	}
	gc.activate(none, false)!
	deadline := call('operator.add', o(call('time.monotonic')!), n(5))!
	for compare('lt', call('time.monotonic')!, o(deadline))! {
		waited := call('os.waitpid', o(pid), o(global('os.WNOHANG')!))!
		if eq(get(waited, n(0))!, o(pid))! {
			gc.callback('reaped', {})!
			return
		}
		call('time.sleep', float('0.1'))!
	}
	kill(pid)!
	gc.activate(none, false)!
	waited := call('os.waitpid', o(pid), o(global('os.WNOHANG')!))!
	if eq(get(waited, n(0))!, o(pid))! { gc.callback('reaped', {})! }
}

fn kill(pid string) ! {
	call('os.killpg', o(pid), o(global('signal.SIGKILL')!)) or {
		failure := err
		if !exception_is(failure, 'OSError')! { return failure }
		gc.activate(failure, true)!
		call('os.kill', o(pid), o(global('signal.SIGKILL')!)) or {
			if !exception_is(err, 'ProcessLookupError')! {
				return err
			}
		}
	}
}

fn global_resource(name string) !string { return name }

fn str(id string) !string { return call('builtins.str', o(id))! }

fn hash(path string) !string {
	return method(call('hashlib.sha256', o(method(path, 'read_bytes', [], {})!))!, 'hexdigest', [], {})!
}

fn extend(id string, value ah.Value) ! { method(id, 'extend', [value], {})! }

fn say(value string) ! {
	invoke('builtins.print', [s(value)], {
		'flush': v(ah.Value(true))
	})!
}

struct State {
mut:
	transcript string
	screenshot string
	menu       string
	started    string
	world      string
	loading    bool
	passed     bool
	fps        string
}

fn archive(root string, work string) !string {
	path := join(work, 'initramfs.tar')!
	manager := invoke('tarfile.open', [o(path), s('w')], {
		'format': o(global('tarfile.USTAR_FORMAT')!)
	})!
	tar := enter(manager)!
	method(tar, 'add', [o(root)], {
		'arcname': s('.')
	}) or {
		if !retire(manager, err)! { return err }
		return path
	}
	retire(manager, none)!
	return path
}

fn environment(args string, work string, archive string, socket string) !string {
	env := method(global('os.environ')!, 'copy', [], {})!
	config := dict()!
	for row in [['VINIX_KERNEL_DIR', text(attr(args, 'kernel_dir')!)!],
		['VINIX_INITRAMFS', text(archive)!], ['VINIX_INITRAMFS_COMPRESSED', '0'],
		['VINIX_QEMU_ROOT_DISK', '0'], ['VINIX_VENUS_STAGING', text(attr(args, 'venus_runtime')!)!],
		['VINIX_BOOT_DISK', text(join(work, 'boot.img')!)!],
		['VINIX_EFIVARS', text(join(work, 'efivars.fd')!)!], ['VINIX_BOOT_DISK_SIZE_MB', '2048'],
		['VINIX_QEMU_PACKAGE_STORE', text(join(work, 'packages.tar')!)!],
		['VINIX_QEMU_PACKAGE_PERSIST', '0'], ['VINIX_QEMU_HOST_SOURCE', '0'],
		['VINIX_QEMU_AUDIO', 'off'], ['VINIX_QEMU_SMP', text(attr(args, 'cpus')!)!],
		['VINIX_KEEP_TEMP_BOOT_DISK', '1'], ['VINIX_QEMU_EXTRA',
			'-qmp unix:' + format(socket)! + ',server=on,wait=off -d guest_errors -D ' + format(work)! + '/qemu-errors.log']] {
		set(config, row[0], s(row[1]))!
	}
	method(env, 'update', [o(config)], {})!
	firmware := join(attr(args, 'repo')!, 'boot-image/edk2-aarch64-code-2048x1536.fd')!
	if truth(method(firmware, 'exists', [], {})!)! {
		set(env, 'VINIX_QEMU_RESOLUTION', s('2048x1536x32'))!
		set(env, 'VINIX_OVMF_CODE', o(str(firmware)!))!
	}
	return env
}

fn run_guest(args string, work string, root string) !string {
	kernel := hash(join(attr(args, 'kernel_dir')!, 'bin/vinix')!)!
	archive_path := archive(root, work)!
	socket := join(work, 'qmp.sock')!
	if truth(method(socket, 'exists', [], {})!)! { method(socket, 'unlink', [], {})! }
	env := environment(args, work, archive_path, socket)!
	command := list()!
	for value in [str(join(attr(args, 'repo')!, 'scripts/run-aarch64.sh')!)!,
		literal(ah.Value('--no-build'))!, literal(ah.Value('--no-persist'))!,
		literal(ah.Value(if truth(attr(args, 'venus')!)! { '--mem=12288' } else { '--mem=8192' }))!,
		literal(ah.Value(if truth(attr(args, 'venus')!)! { '--venus' } else { '--serial' }))!] {
		append(command, o(value))!
	}
	say('Booting Vinix with Gothic II open')!
	fork := gc.callback('fork', {
		'command':    ah.Value(command)
		'env':        ah.Value(env)
		'root_owner': ah.Value(attr(args, 'repo')!)
	})!.items()
	pid, master := literal(fork[0])!, literal(fork[1])!
	state := capture(args, work, socket, master) or {
		failure := err
		gc.activate(failure, true)!
		public_stop(pid, master)!
		return failure
	}
	public_stop(pid, master)!
	gc.callback('retired', {})!
	if !state.passed {
		reached := if truth(state.world)! {
			'the world'
		} else if state.loading {
			'the loading screen'
		} else if truth(state.menu)! {
			'the menu'
		} else {
			'nothing'
		}
		gc.callback('raise_builtin', {
			'kind':  ah.Value('SystemExit')
			'value': s('OpenGothic failed after reaching ' + reached + '; inspect ' + format(work)! + '/vinix.log')
		})!
	}
	if truth(attr(args, 'venus')!)! { performance(args, work, root, kernel, state)! }
	return state.screenshot
}

fn public_stop(pid string, master string) ! {
	call('stop', o(pid), o(master))!
	gc.callback('reaped', {})!
	gc.callback('closed', {})!
}

fn serial(args string, work string, socket string, master string, deadline string, mut state State) ! {
	manager := method(join(work, 'vinix.log')!, 'open', [s('wb')], {})!
	log := enter(manager)!
	serial_loop(args, socket, master, deadline, log, mut state) or {
		if !retire(manager, err)! { return err }
		return
	}
	retire(manager, none)!
}

fn serial_loop(args string, socket string, master string, deadline string, log string, mut state State) ! {
	for compare('lt', call('time.monotonic')!, o(deadline))! {
		ready := call('select.select', o(list_with([master])!), o(list()!), o(list()!), n(1))!
		if truth(get(ready, n(0))!)! {
			chunk := call('os.read', o(master), n(65536)) or {
				if !exception_is(err, 'OSError')! { return err }
				gc.activate(none, false)!
				return
			}
			if !truth(chunk)! { return }
			if truth(attr(args, 'venus')!)! && truth(state.world)! && compare('ge', call('operator.sub', o(call('time.monotonic')!), o(state.world))!, o(attr(args, 'warmup')!))! {
				fps_samples(state.transcript, chunk, state.fps)!
			}
			extend(state.transcript, o(chunk))!
			method(log, 'write', [o(chunk)], {})!
			method(log, 'flush', [], {})!
		}
		markers := iter(global('FAILURES')!)!
		mut failed := false
		for {
			marker := next(markers)!
			if marker.done { break }
			if truth(call('operator.contains', o(state.transcript), o(marker.id))!)! {
				failed = true
				break
			}
		}
		if failed { return }
		now := call('time.monotonic')!
		if compare('is_', state.menu, o(null_id()!))! {
			if truth(call('operator.contains', o(state.transcript), o(global('MENU')!))!)! {
				state.menu = now
				say('The engine reached its menu')!
			}
		} else if compare('is_', state.started, o(null_id()!))! {
			if compare('gt', call('operator.sub', o(now), o(state.menu))!, n(10))! {
				call('press', o(socket), s('ret'))!
				state.started = now
			}
		} else if compare('is_', state.world, o(null_id()!))! {
			if !state.loading && truth(call('operator.contains', o(state.transcript), o(global('LOADING')!))!)! {
				state.loading = true
				say('New game: loading the world')!
			}
			if truth(call('operator.contains', o(state.transcript), o(global('WORLD')!))!)! {
				state.world = now
				say('The world is running')!
			}
		} else if compare('gt', call('operator.sub', o(now), o(state.world))!, o(call('operator.add', o(attr(args, 'warmup')!), o(attr(args, 'seconds')!))!))! {
			call('press', o(socket), s('up'), n(1))!
			cmd := list_with([
				str(join(global('ROOT')!, 'desktop/tools/screenshot.sh')!)!,
				str(state.screenshot)!,
			])!
			env := dict()!
			method(env, 'update', [o(global('os.environ')!)], {})!
			set(env, 'VINIX_QMP_SOCKET', o(str(socket)!))!
			invoke('subprocess.run', [o(cmd)], {
				'check':  v(ah.Value(true))
				'env':    o(env)
				'stdout': o(global('subprocess.DEVNULL')!)
			})!
			state.passed = true
			return
		}
	}
}

fn list_with(items []string) !string {
	value := list()!
	for item in items { append(value, o(item))! }
	return value
}

fn fps_samples(transcript string, chunk string, fps string) ! {
	begin := call('builtins.len', o(transcript))!
	start := call('builtins.max', n(0), o(call('operator.sub', o(begin), n(100))!))!
	tail := get(transcript, o(gc.callback('slice', {
		'args': ah.Value([ah.Value(start), ah.Value(null_id()!)])
	})!.text()))!
	combined := call('operator.add', o(call('builtins.bytes', o(tail))!), o(chunk))!
	matches := iter(call('re.finditer', b(r'(?m)^0, 0, ([0-9.]+), ([0-9]+)\r*\n'.bytes().hex()), o(combined))!)!
	for {
		hit := next(matches)!
		if hit.done { break }
		if compare('gt', method(hit.id, 'end', [], {})!, o(call('builtins.min', n(100), o(begin))!))! {
			append(fps, o(call('builtins.float', o(method(hit.id, 'group', [n(1)], {})!))!))!
		}
	}
}

fn performance(args string, work string, root string, kernel string, state State) ! {
	for marker in ['VINIX_VENUS_FENCE_FD_PASS', 'VINIX_VENUS_GPU_FILL_PASS',
		'VENUS GPU: Virtio-GPU Venus'] {
		if !truth(call('operator.contains', o(state.transcript), b(marker.bytes().hex()))!)! {
			gc.callback('raise_builtin', {
				'kind':  ah.Value('SystemExit')
				'value': s('Native Venus GPU smoke failed')
			})!
		}
	}
	if compare('lt', call('builtins.len', o(state.fps))!, o(call('operator.floordiv', o(attr(args, 'seconds')!), n(2))!))! {
		gc.callback('raise_builtin', {
			'kind':  ah.Value('SystemExit')
			'value': s('Too few gameplay FPS samples')
		})!
	}
	result := dict()!
	for row in [['samples', call('builtins.len', o(state.fps))!],
		['median_fps', call('statistics.median', o(state.fps))!],
		['min_fps', call('builtins.min', o(state.fps))!],
		['max_fps', call('builtins.max', o(state.fps))!], ['seconds', attr(args, 'seconds')!],
		['warmup_seconds', attr(args, 'warmup')!], ['cpus', attr(args, 'cpus')!],
		['kernel_sha256', kernel], ['engine_sha256', hash(join(root, 'opt/opengothic/Gothic2Notr')!)!],
		['venus_sha256', hash(join(root, 'opt/venus/lib/libvulkan_virtio.so')!)!],
		['screenshot', str(state.screenshot)!]] {
		set(result, row[0], o(row[1]))!
	}
	write_json(join(work, 'performance.json')!, result)!
	median := get(result, s('median_fps'))!
	say('Native Venus gameplay: median ' + gc.callback('format', {
		'id':   ah.Value(median)
		'spec': ah.Value('.2f')
	})!.text() + ' FPS (' + format(call('builtins.len', o(state.fps))!)! + ' samples)')!
	if compare('lt', median, o(attr(args, 'min_fps')!))! {
		gc.callback('raise_builtin', {
			'kind':  ah.Value('SystemExit')
			'value': s('Gameplay median below required ' + format(attr(args, 'min_fps')!)! + ' FPS; inspect ' + format(work)! + '/performance.json')
		})!
	}
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(ah.field(row, 'arguments').object(), 'public_operation').text()
	match operation {
		'stop' {
			close_guest(global_resource('arg0')!, global_resource('arg1')!)!
			return ah.Value(json2.Null{})
		}
		'run_guest' {
			return export(run_guest(global_resource('arg0')!, global_resource('arg1')!, global_resource('arg2')!)!)
		}
		else { return error('unknown OpenGothic guest policy') }
	}
}

fn exception_is(failure IError, name string) !bool {
	return gc.flag(gc.callback('exception_matches', {
		'error': gc.error_detail(failure)
		'class': ah.Value(global(name)!)
	})!)
}

fn exception_any(failure IError, names []string) !bool {
	mut ids := []ah.Value{}
	for name in names { ids << ah.Value(global(name)!) }
	return gc.flag(gc.callback('exception_matches', {
		'error':   gc.error_detail(failure)
		'classes': ah.Value(ids)
	})!)
}

fn capture(args string, work string, socket string, master string) !State {
	mut state := State{ transcript: call('builtins.bytearray')!, screenshot: join(work, 'gothic.png')!, menu: null_id()!, started: null_id()!, world: null_id()!, fps: list()! }
	deadline := call('operator.add', o(call('time.monotonic')!), o(attr(args, 'timeout')!))!
	serial(args, work, socket, master, deadline, mut state)!
	return state
}
