// SPDX-License-Identifier: GPL-2.0-or-later
module vkcore

import androidhost as ah

fn option(options string, name string) !string { return attr(options, name)! }
fn prepare(options string, work string) !string {
	root := join(work, 'root')!
	staging := option(options, 'staging')!
	staged_translator := method(join(staging, 'usr/bin/qemu-x86_64')!, 'exists', [], {})!
	if !truth(method(join(root, '.prepared')!, 'exists', [], {})!)! {
		call('copy_layer', o(join('repo', 'build-aarch64-x11/staging')!), o(root))!
		if !truth(staged_translator)! { call('install_native_translator', o(join('repo', 'build-aarch64-x86-translation/staging')!), o(root))! }
		method(join(root, 'bin')!, 'mkdir', [], {'exist_ok': v(ah.Value(true))})!
		userland := join('repo', 'build-aarch64-userland/staging')!
		call('shutil.copy2', o(join(userland, 'bin/busybox')!), o(join(root, 'bin/busybox')!))!
		loader := join(root, 'lib/ld-musl-aarch64.so.1')!
		if truth(method(loader, 'is_symlink', [], {})!)! { method(loader, 'unlink', [], {})! }
		call('shutil.copy2', o(join(userland, 'lib/ld-musl-aarch64.so.1')!), o(loader))!
		for name in ['sh', 'cat', 'mkdir', 'chmod', 'sleep', 'kill', 'base64', 'uname', 'grep'] {
			target := join(join(root, 'bin')!, name)!
			if truth(method(target, 'exists', [], {})!)! || truth(method(target, 'is_symlink', [], {})!)! { method(target, 'unlink', [], {})! }
			method(target, 'symlink_to', [s('busybox')], {})!
		}
		for name in ['sbin', 'proc', 'dev', 'sys', 'tmp', 'root', 'run', 'etc'] { mkdir(join(root, name)!)! }
		method(join(root, 'etc/passwd')!, 'write_text', [s('root:x:0:0:root:/root:/bin/sh\n')], {})!
		method(join(root, 'etc/group')!, 'write_text', [s('root:x:0:root\n')], {})!
		method(join(root, '.prepared')!, 'touch', [], {})!
	}
	if truth(staged_translator)! { call('install_native_translator', o(staging), o(root))! }
	source := join(staging, 'usr/libexec/vinix-dota2/root')!
	generation := method(join(source, '.vinix-dota2-vulkan-generation')!, 'read_text', [], {})!
	marker := join(root, '.vulkan-runtime-generation')!
	guest := join(root, 'usr/libexec/vinix-dota2/root')!
	if !truth(method(marker, 'exists', [], {})!)! || !eq(method(marker, 'read_text', [], {})!, o(generation))! || !truth(method(guest, 'exists', [], {})!)! {
		if truth(method(guest, 'exists', [], {})!)! { call('shutil.rmtree', o(guest))! }
		mkdir(attr(guest, 'parent')!)!
		if eq(call('sys.platform')!, s('darwin'))! {
			command := list()!
			for value in [s('/bin/cp'), s('-cRp'), o(text_id(source)!), o(text_id(guest)!)] { append(command, value)! }
			invoke('subprocess.run', [o(command)], {'check': v(ah.Value(true))})!
		} else { invoke('shutil.copytree', [o(source), o(guest)], {'symlinks': v(ah.Value(true))})! }
		method(marker, 'write_text', [o(generation)], {})!
	}
	init := method(call('Path', o('file'))!, 'with_name', [s('vulkan-init.sh')], {})!
	call('shutil.copy2', o(init), o(join(root, 'sbin/init')!))!
	method(join(root, 'sbin/init')!, 'chmod', [n(0o755)], {})!
	call('complete_native_closure', o(root))!
	call('retain_software_gl', o(source), o(guest))!
	for name in ['usr/lib/i386-linux-gnu', 'lib/i386-linux-gnu', 'usr/share/doc', 'usr/share/man', 'usr/share/locale'] {
		location := join(guest, name)!
		if truth(method(location, 'exists', [], {})!)! { call('shutil.rmtree', o(location))! }
	}
	return root
}
