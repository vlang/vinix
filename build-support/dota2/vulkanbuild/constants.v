// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanbuild

import json2

pub fn exported_constant(repo string, name string) !json2.Any {
	path_values := {
		'GLIBC_PIN':           'build-support/dota2/glibc-package.json'
		'MMAP32_SOURCE':       'build-support/dota2/mmapcore/core.v'
		'EARLY_CLIENT_SOURCE': 'build-support/dota2/earlycore/core.v'
		'MESA_BUILDER':        'build-support/dota2/mesa-build.py'
		'VENUS_BUILDER':       'build-support/dota2/venus-build.py'
	}
	if name in path_values { return json2.Any(repo + '/' + path_values[name]) }
	strings := {
		'GLIBC_MARKER':         '.vinix-dota2-glibc-package.json'
		'GLIBC_ALIAS_POLICY':   'bookworm-lib-to-usrmerged-libc-relative-v1'
		'MMAP32_LIBRARY':       'usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so'
		'EARLY_CLIENT_LIBRARY': 'usr/lib/x86_64-linux-gnu/libvinix-dota2-steam-loader.so'
		'LAVAPIPE_LIBRARY':     'usr/lib/x86_64-linux-gnu/libvulkan_lvp.so'
		'LAVAPIPE_MARKER':      '.vinix-dota2-lavapipe.json'
		'VENUS_LIBRARY':        'usr/lib/x86_64-linux-gnu/libvulkan_virtio.so'
		'VENUS_ICD':            'usr/share/vulkan/icd.d/virtio_icd.x86_64.json'
		'VENUS_MARKER':         '.vinix-dota2-venus.json'
	}
	if name in strings { return json2.Any(strings[name]) }
	if name == 'GLIBC_LIBRARIES' {
		return words(['ld-linux-x86-64.so.2', 'libc.so.6', 'libm.so.6', 'libresolv.so.2',
			'libpthread.so.0', 'libdl.so.2'])
	}
	if name in ['MMAP32_COMPILE', 'EARLY_CLIENT_COMPILE'] {
		mut flags := ['clang', '--target=x86_64-linux-gnu', '-fPIC', '-shared', '-nostdlib',
			'-ffreestanding', '-O2', '-fvisibility=hidden', '-fuse-ld=lld', '-Wall', '-Wextra',
			'-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter',
			'-DVINIX_DOTA_BARE_FFI', '-I', repo + '/build-support/dota2']
		if name == 'MMAP32_COMPILE' {
			flags << '-Wl,--version-script=' + repo + '/build-support/dota2/mmap32.exports'
		}
		flags << '-Wl,-soname,' + if name == 'MMAP32_COMPILE' {
			'libvinix-dota2-mmap32.so'
		} else {
			'libvinix-dota2-steam-loader.so'
		}
		return words(flags)
	}
	return StageError{'AttributeError', name}
}
