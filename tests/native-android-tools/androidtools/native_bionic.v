// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import crypto.sha256
import json2
import os

const ws_bionic_commit = 'ee37eb21c91409fe0eed833d0a5a0aa6b931bb7b'
const ws_egl_commit = 'db3425b8246136faccb5e2782b5694960bd6edf1'

fn ws_fetch(path string, url string, expected string) ! {
	if !os.is_file(path) {
		checked(['curl', '-fLsS', '--retry', '3', url, '-o', path + '.part'])!
		if sha256.sum(os.read_bytes(path + '.part')!).hex() != expected {
			os.rm(path + '.part')!
			return error('native Bionic dependency hash mismatch: ' + url)
		}
		os.mv(path + '.part', path)!
	}
	if sha256.sum(os.read_bytes(path)!).hex() != expected {
		return error('native Bionic dependency hash mismatch: ' + path)
	}
}

// Compile the pinned upstream linker with the existing 16 KiB page patch.
// V supplies optional GL lookup and mapped-segment range accounting. EGL is
// never linked or loaded by this library.
pub fn build_native_bionic(output string, runtime string, compiler string, arch string) ! {
	if arch != 'arm64' { return error('native APK Bionic loader requires ARM64') }
	work := output + '/bionic-ws'
	os.mkdir_all(work)!
	mut inputs := map[string]json2.Any{}
	archive := work + '/bionic.tar.gz'
	source_hash := 'b1b2fa762485c1f33e71c0de6a4cbf4ca7006cfaec9c4c9cc20949393cbf49ef'
	ws_fetch(archive, 'https://gitlab.com/android_translation_layer/bionic_translation/-/archive/' + ws_bionic_commit + '/bionic_translation-' + ws_bionic_commit + '.tar.gz', source_hash)!
	inputs['source_sha256'] = source_hash
	source := work + '/bionic_translation-' + ws_bionic_commit
	if os.exists(source) { os.rmdir_all(source)! }
	checked(['tar', '-xf', archive, '-C', work])!
	patch := root() + '/build-support/android/bionic16k.patch'
	checked(['patch', '--batch', '--fuzz=0', '-p1', '-d', source, '-i', patch])!
	inputs['patch_sha256'] = sha256.sum(os.read_bytes(patch)!).hex()
	// Keep range accounting, copy mapping and page protection in V. These
	// guarded ABI hooks connect the pinned upstream loader to wsloader.
	linker := source + '/linker/linker.c'
	linker_text := os.read_file(linker)!
	if linker_text.count('total_sz += len;') != 1 { return error('unexpected Bionic segment accounting') }
	mut bridged := linker_text.replace('total_sz += len;',
		'total_sz = vinix_ws_segment_extent(base, si->size, (uintptr_t)pbase, len, total_sz);')
	mapper := 'ElfW(Addr) base = (ElfW(Addr))si->base;'
	if bridged.count(mapper) != 1 { return error('unexpected Bionic segment mapper') }
	bridged = bridged.replace(mapper, mapper + '\n' +
		'if (vinix_ws_copy_required(phdr, ehdr->e_phnum))\n' +
		' return vinix_ws_copy_segments(fd, phdr, ehdr->e_phnum, base, si->size, (void **)&si->dynamic,\n' +
		'  &si->wrprotect_start, &si->wrprotect_end, &si->gnu_relro_start, &si->gnu_relro_len);')
	protection := 'if (si->gnu_relro_start != 0 && si->gnu_relro_len != 0) {'
	if bridged.count(protection) != 1 { return error('unexpected Bionic RELRO finalization') }
	bridged = bridged.replace(protection,
		'if (vinix_ws_copy_required(si->phdr, si->phnum) &&\n' +
		' vinix_ws_finish_copy_segments(si->phdr, si->phnum, si->base, si->size) < 0) goto fail;\n' + protection)
	// A host dependency has no soinfo, but a failed APK dependency must fail
	// its parent instead of silently being replaced by the built-in libdl.
	dependency := 'lsi = apkenv_find_library(si->strtab + d->d_un.d_val, true, RTLD_NOW, NULL);'
	if bridged.count(dependency) != 1 { return error('unexpected Bionic dependency loading') }
	bridged = bridged.replace(dependency,
		'void *host_dependency = NULL;\n' +
		'lsi = apkenv_find_library(si->strtab + d->d_un.d_val, true, RTLD_NOW | RTLD_GLOBAL, &host_dependency);\n' +
		'if (!vinix_ws_dependency_loaded(lsi, host_dependency, si->strtab + d->d_un.d_val, si->name, apkenv_linker_get_error())) goto fail;')
	os.write_file(linker, bridged)!
	dlfcn := source + '/linker/dlfcn.c'
	mut dynamic_text := os.read_file(dlfcn)!
	lookup := 'sym = apkenv_lookup_in_library(found, symbol);'
	if dynamic_text.count(lookup) != 1 { return error('unexpected Bionic handle lookup') }
	dynamic_text = dynamic_text.replace(lookup,
		'sym = vinix_ws_lookup_dependencies(found, symbol, (void **)&found, offsetof(soinfo, dynamic), ' +
		'(void *(*)(void *, const char *))apkenv_lookup_in_library);')
	// Defined weak symbols are valid dlsym results as well as global symbols.
	if dynamic_text.count('(bind == STB_GLOBAL)') != 1 { return error('unexpected Bionic symbol binding check') }
	dynamic_text = dynamic_text.replace('(bind == STB_GLOBAL)', '(bind == STB_GLOBAL || bind == STB_WEAK)')
	os.write_file(dlfcn, dynamic_text)!
	bridge := work + '/vinix-segments.h'
	os.write_file(bridge, '#include <stdint.h>\n#include <stddef.h>\n' +
		'extern size_t vinix_ws_segment_extent(uintptr_t, size_t, uintptr_t, size_t, size_t);\n' +
		'extern int vinix_ws_copy_required(const void *, size_t);\n' +
		'extern int vinix_ws_copy_segments(int, const void *, size_t, uintptr_t, size_t, void **, uint32_t *, uint32_t *, uintptr_t *, unsigned *);\n' +
		'extern int vinix_ws_finish_copy_segments(const void *, size_t, uintptr_t, size_t);\n' +
		'extern int vinix_ws_dependency_loaded(void *, void *, const char *, const char *, const char *);\n' +
		'extern void *vinix_ws_lookup_dependencies(void *, const char *, void **, size_t, void *(*)(void *, const char *));\n')!
	inputs['segment_bridge_sha256'] = sha256.sum(os.read_bytes(bridge)!).hex()
	inputs['linker_with_v_bridge_sha256'] = sha256.sum(os.read_bytes(linker)!).hex()
	inputs['dlfcn_with_v_bridge_sha256'] = sha256.sum(os.read_bytes(dlfcn)!).hex()
	headers := work + '/headers'
	os.mkdir_all(headers)!
	for record in [
		'libunwind-dev-1.8.3-r0.apk d5bbe71aa4ef87844518203038db988726fa44e0451aca825cfb5c7d001b471b',
		'elfutils-dev-0.195-r0.apk 6a9398f4b8b7abe6c3a41a1840d84c9e60f79598f5f8d4f225b5d8762dd03faa',
		'bsd-compat-headers-0.7.2-r6.apk 2ae95e33fd57930d8be3321b287a1149c852d98bc2184dd34a273313c9c7e2a4',
	] {
		parts := record.split(' ')
		path := work + '/' + parts[0]
		ws_fetch(path, 'https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/' + parts[0], parts[1])!
		checked(['tar', '-xf', path, '-C', headers, 'usr/include'])!
		inputs[parts[0]] = parts[1]
	}
	include := headers + '/usr/include'
	for folder in ['EGL', 'KHR'] { os.mkdir_all(include + '/' + folder)! }
	for record in [
		'EGL/egl.h a7c24c828bf2e1a4dfe6511b4f4812b948a285eb54787074015896976d4da076',
		'EGL/eglplatform.h 25b5391655effcf363a38fa00c3154f356a3eab3d35dc067847875513cf1e441',
		'KHR/khrplatform.h 7b1e01aaa7ad8f6fc34b5c7bdf79ebf5189bb09e2c4d2e79fc5d350623d11e83',
	] {
		parts := record.split(' ')
		ws_fetch(include + '/' + parts[0], 'https://raw.githubusercontent.com/KhronosGroup/EGL-Registry/' + ws_egl_commit + '/api/' + parts[0], parts[1])!
		inputs[parts[0]] = parts[1]
	}
	mut objects := []string{}
	for name in ['linker/dlfcn.c', 'linker/linker.c', 'linker/linker_environ.c', 'linker/linker_tls.c',
		'linker/rt.c', 'linker/strlcpy.c', 'wrapper/wrapper.c', 'shared/config/config.c'] {
		object := work + '/' + name.replace('/', '_') + '.o'
		checked([compiler, '-O2', '-fPIC', '-D_GNU_SOURCE', '-D_LARGEFILE64_SOURCE', '-include', bridge,
			'-DBIONIC_PAGE_SIZE=16384', '-DLINKER_DEBUG=1', '-I' + include,
			'-I' + source + '/shared/config', '-DeglGetProcAddress=vinix_ws_gl_symbol',
			'-c', source + '/' + name, '-o', object])!
		objects << object
	}
	mut link := [compiler, '-shared', '-fPIC', '-Wl,-soname,libdl_bio.so.0',
		'-Wl,-z,max-page-size=65536', output + '/android-loader.c']
	link << objects
	link << [if os.is_file(runtime + '/usr/lib/libunwind.so.8') {
		runtime + '/usr/lib/libunwind.so.8'
	} else { '-lunwind' }, '-ldl', '-o', output + '/libdl_bio.so.0']
	checked(link)!
	inputs['loader_sha256'] = sha256.sum(os.read_bytes(output + '/libdl_bio.so.0')!).hex()
	inputs['compiler'] = checked([compiler, '--version'])!.stdout.split_into_lines()[0]
	os.write_file(output + '/bionic-ws-manifest.json', json2.encode(inputs, prettify: true) + '\n')!
	// Preserve the upstream linker license for runtime redistribution.
	os.cp(source + '/linker/NOTICE', output + '/bionic-ws-NOTICE')!
	os.write_file(output + '/bionic-ws.cfg',
		'libc.so libc_bio.so.0\nlibstdc++.so libstdc++_bio.so.0\n' +
		'libandroid.so libvinix-android-native.so\nlibjnigraphics.so libvinix-android-native.so\n' +
		'libOpenSLES.so libOpenSLES.so.1\n' +
		'libEGL.so libvinix-android-native.so\nlibEGL.so.1 libvinix-android-native.so\n' +
		'libGLESv1_CM.so libvinix-ws-GLESv1_CM.so\nlibGLESv2.so libvinix-ws-GLESv2.so\nlibGLESv3.so libvinix-ws-GLESv2.so\n')!
}
