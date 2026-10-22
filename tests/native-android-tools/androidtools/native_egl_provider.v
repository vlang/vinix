// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import crypto.sha256
import json2
import os

// Build only Mesa's surfaceless EGL platform. The software DRI renderer has
// no dependency on an X server, GTK, Wayland or a DRM device.
fn build_native_egl_provider(output string, runtime string, compiler string) ! {
	work := output + '/egl-build'
	provider := output + '/egl-ws'
	os.mkdir_all(work + '/obj')!
	os.mkdir_all(provider + '/dri')!
	os.mkdir_all(provider + '/licenses')!
	mut receipt := map[string]json2.Any{}
	for record in [
		'libdrm-dev-2.4.109-r0.apk 3572b04026532db599bdb9492ab27dac3dc93dde4052b0ac8188722dc845d0e6',
		'expat-dev-2.5.0-r0.apk 7eb6e1bc74d41505e0bf5e92ad07dadd70f477566b59b92284462aa4b6a6b08e',
		'libdrm-2.4.109-r0.apk 09b4cfaa1eb726cb7eec1944ea622f32ecae8c63781a55b1e1ca335892b6c542',
		'expat-2.5.0-r0.apk bcc835f9daea246b54fd232428511c74464066d9f8b7cafd77f37e47a15841c6',
		'mesa-dri-gallium-21.2.6-r0.apk cb31934e0f98ee1a6aca687a80e61a2e6940a9b5c9a4c6becdc61e00ec4ffedb',
		'llvm12-libs-12.0.1-r0.apk 7763d4ebceabfc86466a37b5250dd4255d545a6093e5ae528c27a83d1e5f2976',
	] {
		parts := record.split(' ')
		archive := work + '/' + parts[0]
		ws_fetch(archive, 'https://dl-cdn.alpinelinux.org/alpine/v3.15/main/aarch64/' + parts[0], parts[1])!
		checked(['tar', '-xf', archive, '-C', work, 'usr'])!
		receipt[parts[0]] = parts[1]
		receipt[parts[0] + '.metadata'] = checked(['tar', '-xOf', archive, '.PKGINFO'])!.stdout
	}
	source_hash := '1e7e22d93c6e8859fa044b1121119d26b2e67e4184b92ebb81c66497dc80c954'
	archive := work + '/mesa-21.2.6.tar.xz'
	ws_fetch(archive, 'https://archive.mesa3d.org/older-versions/21.x/mesa-21.2.6.tar.xz', source_hash)!
	checked(['tar', '-xf', archive, '-C', work])!
	src := work + '/mesa-21.2.6'
	mut config := '#define _GNU_SOURCE 1\n#define NDEBUG 1\n#define WITH_XMLCONFIG 1\n#define _EGL_NATIVE_PLATFORM _EGL_PLATFORM_SURFACELESS\n#define DEFAULT_DRIVER_DIR "/usr/lib/art/native-ws/dri"\n#define SYSCONFDIR "/etc"\n#define DATADIR "/usr/share"\n#define PACKAGE_VERSION "21.2.6"\n'
	for name in ['HAVE_LIBDRM', 'HAVE_SURFACELESS_PLATFORM', 'HAVE_PTHREAD', 'HAVE_ENDIAN_H', 'HAVE_DLFCN_H',
		'HAVE_FUNC_ATTRIBUTE_PACKED', 'HAVE_FUNC_ATTRIBUTE_PURE', 'HAVE_FUNC_ATTRIBUTE_CONST', 'HAVE_FUNC_ATTRIBUTE_MALLOC',
		'HAVE_FUNC_ATTRIBUTE_FORMAT', 'HAVE_FUNC_ATTRIBUTE_WARN_UNUSED_RESULT', 'HAVE_FUNC_ATTRIBUTE_UNUSED',
		'HAVE_FUNC_ATTRIBUTE_NORETURN', 'HAVE_FUNC_ATTRIBUTE_VISIBILITY', 'HAVE_FUNC_ATTRIBUTE_WEAK',
		'HAVE_POSIX_MEMALIGN', 'HAVE_TIMESPEC_GET', 'HAVE_CLOCK_GETTIME', 'HAVE_STRUCT_TIMESPEC',
		'HAVE_STRTOF', 'HAVE_STRTOD_L', 'HAVE_STRTOD', 'HAVE_MKOSTEMP', 'HAVE_MEMFD_CREATE',
		'HAVE_FCNTL_H', 'HAVE_SYS_STAT_H', 'HAVE_UNISTD_H', 'HAVE_DIRENT_H', 'HAVE_SYS_MMAN_H',
		'HAVE_DLOPEN', 'HAVE_MINCORE', 'HAVE_GETRANDOM', 'HAVE_PTHREAD_SETAFFINITY', 'HAVE_LINUX_FUTEX_H'] {
		config += '#define ' + name + ' 1\n'
	}
	os.write_file(work + '/config.h', config)!
	os.write_file(work + '/git_sha1.h', '#define MESA_GIT_SHA1 ""\n')!
	os.write_file(work + '/version.h', '#define PACKAGE_VERSION "21.2.6"\n#define MESA_VERSION_STRING "21.2.6"\n')!
	mut sources := []string{}
	for name in ['eglapi', 'eglarray', 'eglconfig', 'eglcontext', 'eglcurrent', 'egldevice', 'egldisplay',
		'eglglobals', 'eglimage', 'egllog', 'eglsurface', 'eglsync'] {
		sources << 'src/egl/main/' + name + '.c'
	}
	sources << ['src/egl/drivers/dri2/egl_dri2.c', 'src/egl/drivers/dri2/platform_device.c',
		'src/egl/drivers/dri2/platform_surfaceless.c', 'src/loader/loader.c', 'src/loader/loader_dri_helper.c',
		'src/loader/pci_id_driver_map.c']
	for name in ['anon_file', 'bitscan', 'blob', 'build_id', 'debug', 'hash_table', 'log', 'memstream',
		'os_time', 'os_file', 'os_misc', 'u_process', 'ralloc', 'set', 'string_buffer', 'strtod',
		'u_atomic', 'u_vector', 'u_math', 'u_debug', 'u_debug_memory', 'u_cpu_detect', 'u_debug_stack', 'u_debug_symbol', 'xmlconfig'] {
		sources << 'src/util/' + name + '.c'
	}
	mut flags := [compiler, '-DEGL_NO_X11', '-std=gnu11', '-fPIC', '-O2', '-fvisibility=hidden',
		'-ffunction-sections', '-fdata-sections', '-include', work + '/config.h']
	for path in [work, src + '/include', src + '/src', src + '/src/egl/main', src + '/src/egl/drivers/dri2',
		src + '/src/loader', src + '/src/util', src + '/src/gallium/include', src + '/src/mapi',
		src + '/src/mesa', src + '/src/gallium/auxiliary', work + '/usr/include', work + '/usr/include/libdrm'] {
		flags << '-I' + path
	}
	mut objects := []string{}
	for source in sources {
		object := work + '/obj/' + source.replace('/', '_') + '.o'
		objects << object
		mut command := flags.clone()
		command << ['-c', src + '/' + source, '-o', object]
		checked(command)!
	}
	mut link := [compiler, '-shared', '-Wl,-Bsymbolic,--gc-sections,--no-undefined,-z,max-page-size=65536',
		'-o', provider + '/libvinix-ws-mesa-EGL.so']
	link << objects
	link << ['-L' + output + '/gles-ws/usr/lib', '-L' + work + '/usr/lib',
		'-l:libglapi.so.0', '-ldrm', '-lexpat', '-lm', '-ldl', '-pthread']
	checked(link)!
	os.cp(work + '/usr/lib/xorg/modules/dri/armada-drm_dri.so', provider + '/dri/swrast_dri.so')!
	os.cp(work + '/usr/lib/libLLVM-12.so', provider + '/libLLVM-12.so')!
	for name in os.ls(work + '/usr/lib')! {
		if (name.starts_with('libdrm') || name.starts_with('libexpat')) && name.contains('.so.') && !os.is_link(work + '/usr/lib/' + name) {
			// Preserve the SONAME rather than depending on host symlink handling.
			dynamic := checked(['aarch64-linux-musl-readelf', '-d', work + '/usr/lib/' + name])!.stdout
			soname := dynamic.split_into_lines().filter(it.contains('(SONAME)'))
			if soname.len != 1 { return error('missing graphics SONAME: ' + name) }
			os.cp(work + '/usr/lib/' + name, provider + '/' + soname[0].all_after('[').all_before(']'))!
		}
	}
	// Audit the transitive ELF closure against the prepared runtime. Never
	// copy the older distro libstdc++ over ART's newer C++ runtime.
	mut pending := os.walk_ext(provider, '.so')
	pending << os.ls(provider)!.filter(it.contains('.so.')).map(provider + '/' + it)
	mut binaries := map[string]json2.Any{}
	for pending.len > 0 {
		path := pending.pop()
		name := os.file_name(path)
		if name in binaries { continue }
		if name.contains('X11') || name.contains('gtk') || name.contains('xcb') || name.contains('wayland') { return error('non-native graphics dependency: ' + name) }
		binaries[name] = sha256.sum(os.read_bytes(path)!).hex()
		for line in checked(['aarch64-linux-musl-readelf', '-d', path])!.stdout.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			needed := line.all_after('[').all_before(']')
			mut found := ''
			for dir in [provider, output, runtime + '/usr/lib', runtime + '/lib'] {
				if os.is_file(dir + '/' + needed) { found = dir + '/' + needed; break }
			}
			// musl's loader is also libc; it is already mapped by the process.
			if found == '' && needed == 'libc.so' && os.is_file(runtime + '/lib/ld-musl-aarch64.so.1') {
				found = runtime + '/lib/ld-musl-aarch64.so.1'
			}
			if found == '' { return error('unpackaged graphics dependency: ' + needed) }
			pending << found
		}
	}
	receipt['elf_closure_sha256'] = binaries
	receipt['upstream_source_sha256'] = source_hash
	receipt['compiler'] = checked([compiler, '--version'])!.stdout
	receipt['scope'] = 'Mesa 21.2.6 surfaceless EGL and softpipe software DRI. LLVM 12 satisfies the distro DRI ELF dependency; llvmpipe is not selected. Native WS CPU presentation; no X11, GTK, Wayland or DRM device.'
	os.cp(src + '/docs/license.rst', output + '/egl-ws-NOTICE')!
	os.cp(src + '/docs/license.rst', provider + '/licenses/Mesa-NOTICE')!
	for record in [
		'LLVM-12-LICENSE 8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-12.0.1/llvm/LICENSE.TXT',
		'expat-2.5-LICENSE 122f2c27000472a201d337b9b31f7eb2b52d091b02857061a8880371612d9534 https://raw.githubusercontent.com/libexpat/libexpat/R_2_5_0/expat/COPYING',
	] {
		parts := record.split(' ')
		ws_fetch(provider + '/licenses/' + parts[0], parts[2], parts[1])!
		receipt[parts[0]] = parts[1]
	}
	drm_archive := work + '/libdrm-2.4.109.tar.xz'
	ws_fetch(drm_archive, 'https://dri.freedesktop.org/libdrm/libdrm-2.4.109.tar.xz', '629352e08c1fe84862ca046598d8a08ce14d26ab25ee1f4704f993d074cb7f26')!
	checked(['tar', '-xf', drm_archive, '-C', work])!
	// libdrm carries notices in each source file rather than a top-level COPYING.
	os.cp(drm_archive, provider + '/licenses/libdrm-sources.tar.xz')!
	os.cp(archive, provider + '/licenses/mesa-sources.tar.xz')!
	receipt['libdrm_license_source_sha256'] = sha256.sum(os.read_bytes(drm_archive)!).hex()
	os.write_file(output + '/egl-ws-manifest.json', json2.encode(receipt, prettify: true) + '\n')!
	// Retain the exact sources and distro metadata alongside generated output.
	os.cp(archive, output + '/mesa-egl-ws-sources.tar.xz')!
}
