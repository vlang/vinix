// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import boothost
import os

pub const musl_libraries = ['lib/ld-musl-aarch64.so.1', 'lib/libc.musl-aarch64.so.1']
pub const musl_manifest = 'usr/share/vinix/musl-build.json'
pub const musl_source_sha256 = 'd585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a'

pub fn musl_constants() map[string]ah.Value {
	return {'MUSL': ah.Value(root() + '/build-support/musl'), 'MANIFEST': ah.Value(musl_manifest), 'PATCH': ah.Value(root() + '/build-support/android/musl-mallinfo.patch'), 'SOURCE_SHA256': ah.Value(musl_source_sha256), 'LIBRARIES': ah.Value(musl_libraries.map(ah.Value(it)))}
}

pub fn musl_source_patches(musl string, patch string) !ah.Value {
	alpine := read_value(musl + '/alpine-1.2.6/manifest.json')!
	if alpine !is []ah.Value { return error('musl Alpine patch inventory must be an array') }
	mut paths := []string{}
	for record in alpine.items() { paths << musl + '/alpine-1.2.6/' + ah.field(record.object(), 'name').text() }
	paths << [musl + '/malloc-retain.patch', patch]
	mut records := []ah.Value{}
	for path in paths { records << ah.Value({'name': ah.Value(os.file_name(path)), 'sha256': ah.Value(ah.digest(path)!)}) }
	return ah.Value(records)
}

pub fn read_musl(runtime string, musl string, patch string) !ah.Value {
	path := runtime + '/' + musl_manifest
	if os.lstat(path)!.get_filetype() != .regular { return error('Android libc build receipt must be a regular file') }
	manifest := read_value(path)!
	row := manifest.object()
	if manifest !is map[string]ah.Value { return error('Android requires its source-built ARM64 musl allocator statistics provider') }
	expected := {'version': ah.Value('1.2.6'), 'arch': ah.Value('aarch64'), 'source_sha256': ah.Value(musl_source_sha256), 'source_url': ah.Value('https://musl.libc.org/releases/musl-1.2.6.tar.gz'), 'patches': musl_source_patches(musl, patch)!, 'retention': ah.Value(1), 'cflags': ah.Value('-fstack-protector-strong -DVINIX_MALLOC_RETAIN=1'), 'ldflags': ah.Value('-Wl,-soname,libc.musl-aarch64.so.1 -Wl,-z,max-page-size=65536')}
	for key, value in expected { if !boothost.receipt_equal(ah.field(row, key), value) { return error('Android requires its source-built ARM64 musl allocator statistics provider') } }
	if !ah.field(row, 'compiler_target').text().starts_with('aarch64-') { return error('Android requires its source-built ARM64 musl allocator statistics provider') }
	for name in musl_libraries {
		library := runtime + '/' + name
		if os.lstat(library)!.get_filetype() != .regular { return error('Android libc differs from its verified build: ' + library) }
		if !boothost.receipt_equal(ah.Value(ah.digest(library)!), ah.field(row, 'libc_so_sha256')) { return error('Android libc differs from its verified build: ' + library) }
		ah.check_elf(library, true)!
	}
	return manifest
}

pub fn read_android_musl(runtime string) !ah.Value {
	return read_musl(runtime, root() + '/build-support/musl', root() + '/build-support/android/musl-mallinfo.patch')
}
