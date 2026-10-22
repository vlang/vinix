// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import crypto.sha256
import json2
import os
import generators

// Package Mesa's window-system-independent entrypoint/dispatch libraries only.
// The surfaceless EGL provider is built separately in native_egl_provider.v.
fn build_native_gl_dispatch(output string, compiler string, arch string) ! {
	work := output + '/gles-ws'
	os.mkdir_all(work)!
	mut receipt := map[string]json2.Any{}
	for record in [
		'mesa-gles-21.2.6-r0.apk 5c15c7e6a4569b24b96d8276e52be2469ea1c0f4ad349e7d1b49cf140de66c7d',
		'mesa-glapi-21.2.6-r0.apk 24f087e42b90e30c1d63ea30ffbabb30eb5024f104140e6b6663437570a04bfa',
	] {
		parts := record.split(' ')
		archive := work + '/' + parts[0]
		ws_fetch(archive, 'https://dl-cdn.alpinelinux.org/alpine/v3.15/main/aarch64/' + parts[0], parts[1])!
		checked(['tar', '-xf', archive, '-C', work, 'usr/lib'])!
		receipt[parts[0]] = parts[1]
		receipt[parts[0] + '.metadata'] = checked(['tar', '-xOf', archive, '.PKGINFO'])!.stdout
	}
	for source, name in {
		'libGLESv2.so.2.0.0':    'libvinix-ws-GLESv2.so'
		'libglapi.so.0.0.0':     'libglapi.so.0'
	} {
		os.cp(work + '/usr/lib/' + source, output + '/' + name)!
		receipt[name] = sha256.sum(os.read_bytes(output + '/' + name)!).hex()
	}
	// Include the actual dispatch/header sources and their copyright notices,
	// in addition to Mesa's license overview, with the redistributed binaries.
	source_archive := work + '/mesa-21.2.6.tar.xz'
	source_hash := '1e7e22d93c6e8859fa044b1121119d26b2e67e4184b92ebb81c66497dc80c954'
	ws_fetch(source_archive, 'https://archive.mesa3d.org/older-versions/21.x/mesa-21.2.6.tar.xz', source_hash)!
	inputs := ['docs/license.rst', 'src/mapi', 'include/c11', 'include/GL', 'include/GLES', 'include/GLES2',
		'include/GLES3']
	mut extract := ['tar', '-xf', source_archive, '-C', work]
	extract << inputs.map('mesa-21.2.6/' + it)
	checked(extract)!
	// Alpine's matching release packages GLES2 only. Generate the GLES1 ABI
	// in V against the same dispatcher, rather than mixing Mesa TLS ABIs.
	build_native_gl1_dispatch(work, compiler, arch)!
	os.cp(work + '/libvinix-ws-GLESv1_CM.so', output + '/libvinix-ws-GLESv1_CM.so')!
	receipt['libvinix-ws-GLESv1_CM.so'] = sha256.sum(os.read_bytes(output + '/libvinix-ws-GLESv1_CM.so')!).hex()
	mut package := ['tar', '-czf', output + '/mesa-ws-sources.tar.gz', '-C', work + '/mesa-21.2.6']
	package << inputs
	checked(package)!
	os.cp(work + '/mesa-21.2.6/docs/license.rst', output + '/mesa-ws-NOTICE')!
	receipt['upstream_source_sha256'] = source_hash
	receipt['license_sources_sha256'] = sha256.sum(os.read_bytes(output + '/mesa-ws-sources.tar.gz')!).hex()
	receipt['scope'] = 'Mesa 21.2.6 ARM64 GLES dispatch, matching the EGL/DRI provider. No X11 or GTK.'
	os.write_file(output + '/mesa-ws-manifest.json', json2.encode(receipt, prettify: true) + '\n')!
}

fn native_gl_type(declaration string) !string {
	if declaration.contains('*') { return 'voidptr' }
	return match declaration.trim_space() {
		'void' { '' }
		'GLenum', 'GLuint', 'GLbitfield' { 'u32' }
		'GLint', 'GLsizei', 'GLfixed', 'GLclampx' { 'i32' }
		'GLfloat', 'GLclampf' { 'f32' }
		'GLsizeiptr', 'GLintptr' { 'isize' }
		'GLboolean', 'GLubyte' { 'u8' }
		else { return error('unhandled GLES1 ABI type: ' + declaration) }
	}
}

fn build_native_gl1_dispatch(work string, compiler string, arch string) ! {
	dir := work + '/gles1'
	os.mkdir_all(dir)!
	mut source := '// Generated from the pinned Khronos GLES header; see mesa-ws-sources.tar.gz.\n@[translated]\nmodule gles1\nfn C._glapi_get_proc_address(&char) voidptr\n'
	mut count := 0
	for line in os.read_lines(work + '/mesa-21.2.6/include/GLES/gl.h')! {
		if !line.starts_with('GL_API ') || !line.contains('GL_APIENTRY ') { continue }
		result := native_gl_type(line.all_after('GL_API ').all_before('GL_APIENTRY'))!
		name := line.all_after('GL_APIENTRY ').all_before('(').trim_space()
		mut types := []string{}
		mut params := []string{}
		mut values := []string{}
		arguments := line.all_after('(').all_before(')').trim_space()
		if arguments != 'void' {
			for i, argument in arguments.split(',') {
				declaration := argument.trim_space()
				arg_name := declaration.split(' ').last().trim_left('*')
				typ := native_gl_type(declaration[..declaration.len - arg_name.len])!
				types << typ
				params << 'p${i} ${typ}'
				values << 'p${i}'
			}
		}
		source += 'type Entry${count} = fn (${types.join(', ')}) ${result}\n'
		source += "@[export: '${name}']\npub fn entry_${count}(${params.join(', ')}) ${result} { unsafe { "
		if result != '' { source += 'return ' }
		source += "Entry${count}(C._glapi_get_proc_address(c'${name}'))(${values.join(', ')}) } }\n"
		count++
	}
	if count != 145 { return error('unexpected GLES1 header entrypoint count: ${count}') }
	os.write_file(dir + '/dispatch.v', source)!
	generators.generate_module(dir, work + '/gles1.c', arch, []string{})!
	checked([compiler, '-O2', '-fPIC', '-shared', '-fvisibility=hidden',
		'-Wl,--no-undefined,-z,max-page-size=65536', work + '/gles1.c',
		'-L' + work + '/usr/lib', '-l:libglapi.so.0', '-o', work + '/libvinix-ws-GLESv1_CM.so'])!
}
