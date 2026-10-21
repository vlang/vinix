// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import crypto.sha256
import json2
import os

// Package Mesa's window-system-independent entrypoint/dispatch libraries only.
// The runtime deliberately has no EGL vendor or graphics context provider.
fn build_native_gl_dispatch(output string) ! {
	work := output + '/gles-ws'
	os.mkdir_all(work)!
	mut receipt := map[string]json2.Any{}
	for record in [
		'mesa-gles-23.3.6-r0.apk c45f5ba2e8995cc0e284405a97cf23fc8918082c5ee59dc9e6b11b98b24410e3',
		'mesa-glapi-23.3.6-r0.apk 62341b3b87102d22619157f39436ea4b9a3fab2e5889d72c4fe11b6b4ca25c31',
	] {
		parts := record.split(' ')
		archive := work + '/' + parts[0]
		ws_fetch(archive, 'https://dl-cdn.alpinelinux.org/alpine/v3.19/main/aarch64/' + parts[0], parts[1])!
		checked(['tar', '-xf', archive, '-C', work, 'usr/lib'])!
		receipt[parts[0]] = parts[1]
		receipt[parts[0] + '.metadata'] = checked(['tar', '-xOf', archive, '.PKGINFO'])!.stdout
	}
	for source, name in {
		'libGLESv1_CM.so.1.1.0': 'libvinix-ws-GLESv1_CM.so'
		'libGLESv2.so.2.0.0':    'libvinix-ws-GLESv2.so'
		'libglapi.so.0.0.0':     'libglapi.so.0'
	} {
		os.cp(work + '/usr/lib/' + source, output + '/' + name)!
		receipt[name] = sha256.sum(os.read_bytes(output + '/' + name)!).hex()
	}
	// Include the actual dispatch/header sources and their copyright notices,
	// in addition to Mesa's license overview, with the redistributed binaries.
	source_archive := work + '/mesa-23.3.6.tar.xz'
	source_hash := 'cd3d6c60121dea73abbae99d399dc2facaecde1a8c6bd647e6d85410ff4b577b'
	ws_fetch(source_archive, 'https://archive.mesa3d.org/mesa-23.3.6.tar.xz', source_hash)!
	inputs := ['docs/license.rst', 'src/mapi', 'src/c11', 'include/GL', 'include/GLES', 'include/GLES2',
		'include/GLES3']
	mut extract := ['tar', '-xf', source_archive, '-C', work]
	extract << inputs.map('mesa-23.3.6/' + it)
	checked(extract)!
	mut package := ['tar', '-czf', output + '/mesa-ws-sources.tar.gz', '-C', work + '/mesa-23.3.6']
	package << inputs
	checked(package)!
	os.cp(work + '/mesa-23.3.6/docs/license.rst', output + '/mesa-ws-NOTICE')!
	receipt['upstream_source_sha256'] = source_hash
	receipt['license_sources_sha256'] = sha256.sum(os.read_bytes(output + '/mesa-ws-sources.tar.gz')!).hex()
	receipt['scope'] = 'Mesa 23.3.6 ARM64 GLES dispatch only. No EGL vendor, context creation, renderer, X11 or GTK.'
	os.write_file(output + '/mesa-ws-manifest.json', json2.encode(receipt, prettify: true) + '\n')!
}
