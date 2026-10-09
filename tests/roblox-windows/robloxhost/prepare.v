// SPDX-License-Identifier: MIT
module robloxhost

import androidhost as ah

fn prepare(args string, work string, client string, deployment string) !string {
	root := join(work, 'root')!
	if !exists(join(root, '.prepared')!)! {
		if exists(root)! { call('shutil.rmtree', o(root))! }
		public_host('copy_layer', [
			join(attribute(args, 'repo')!, 'build-aarch64-x11/staging')!,
			root,
		])!
		userland := join(attribute(args, 'repo')!, 'build-aarch64-userland/staging')!
		for directory in ['lib', 'usr/lib'] {
			libraries := iterator(method(join(userland, directory)!, 'glob', [v(ah.Value('*.so*'))], {})!)!
			for {
				library := next(libraries)!
				if library.done { break }
				target := call('operator.truediv', o(join(root, directory)!), o(attribute(library.value, 'name')!))!
				if !exists(target)! && !truth(method(target, 'is_symlink', [], {})!)! {
					if truth(method(library.value, 'is_symlink', [], {})!)! {
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
		for directory in ['sbin', 'proc', 'dev', 'sys', 'tmp', 'root', 'run', 'etc'] {
			mkdir(join(root, directory)!, true)!
		}
		method(join(root, 'etc/passwd')!, 'write_text', [v(ah.Value('root:x:0:0:root:/root:/bin/sh\n'))], {})!
		method(join(root, 'etc/group')!, 'write_text', [v(ah.Value('root:x:0:root\n'))], {})!
		public_host('copy_layer', [attribute(args, 'translation')!, root, global('UNUSED')!])!
		method(join(root, '.prepared')!, 'touch', [], {})!
	}
	for launcher in ['run-wine-x86-64', 'run-x86-64', 'run-x86-32'] {
		call('shutil.copy2', o(join(join(global('ROOT')!, 'build-support/x86-translation')!, launcher)!), o(join(join(root, 'usr/bin')!, launcher)!))!
	}
	installed := join(root, 'root/.wine-x86_64/drive_c/Roblox')!
	if exists(installed)! { call('shutil.rmtree', o(installed))! }
	public_host('copy_layer', [client,
		call('operator.truediv', o(join(installed, 'Versions')!), o(deployment))!])!
	test := join(root, 'opt/roblox-test')!
	mkdir(test, true)!
	configuration := call('builtins.dict')!
	for row in [
		['TEST_EXECUTABLE',
			lit('C:\\Roblox\\Versions\\' + text(deployment)! + '\\RobloxPlayerBeta.exe')!],
		['TEST_WINEDEBUG', attribute(args, 'winedebug')!],
		['TEST_UPLOAD', lit('http://10.0.2.2:' + text(attribute(args, 'port')!)!)!],
		['TEST_SECONDS', call('str', o(attribute(args, 'seconds')!))!],
		['TEST_GEOMETRY', lit('1280x720x24')!],
		['TEST_ARGUMENTS', attribute(args, 'arguments')!],
		['TEST_SHELL', lit(if truth(attribute(args, 'shell')!)! { '1' } else { '0' })!],
		['TEST_STRACE', lit(if truth(attribute(args, 'strace')!)! { '1' } else { '0' })!],
	] {
		set(configuration, row[0], row[1])!
	}
	parts := list([])!
	items := iterator(method(configuration, 'items', [], {})!)!
	for {
		item := next(items)!
		if item.done { break }
		pair := callback('unpack_pair', {
			'owner': ah.Value(item.value)
		})!.items().map(it.text())
		method(parts, 'append', [v(ah.Value(text(pair[0])! + '=' + text(call('shlex.quote', o(pair[1]))!)! + '\n'))], {})!
	}
	method(join(test, 'config.sh')!, 'write_text', [o(method(lit('')!, 'join', [o(parts)], {})!)], {})!
	init := method(call('Path', o(global('__file__')!))!, 'with_name', [v(ah.Value('guest-init.sh'))], {})!
	call('shutil.copy2', o(init), o(join(root, 'sbin/init')!))!
	method(join(root, 'sbin/init')!, 'chmod', [v(ah.Value(0o755))], {})!
	return root
}

fn serve(directory string, port string) !string {
	mkdir(directory, true)!
	handler := call('_handler', o(directory))!
	server := call('http.server.ThreadingHTTPServer', o(tuple_pair(lit('127.0.0.1')!, port)!), o(handler))!
	worker := invoke('threading.Thread', [], {
		'target': o(attribute(server, 'serve_forever')!)
		'daemon': v(ah.Value(true))
	})!
	method(worker, 'start', [], {})!
	return server
}

fn upload(handler string, directory string) ! {
	path := call('Path', o(attribute(handler, 'path')!))!
	name_value := attribute(path, 'name')!
	name := if truth(name_value)! { name_value } else { lit('upload')! }
	count := call('int', o(method(attribute(handler, 'headers')!, 'get', [
		v(ah.Value('Content-Length')),
		v(ah.Value(0)),
	], {})!))!
	data := method(attribute(handler, 'rfile')!, 'read', [o(count)], {})!
	method(call('operator.truediv', o(directory), o(name))!, 'write_bytes', [o(data)], {})!
	method(handler, 'send_response', [v(ah.Value(200))], {})!
	method(handler, 'send_header', [v(ah.Value('Content-Length')), v(ah.Value('0'))], {})!
	method(handler, 'end_headers', [], {})!
}
