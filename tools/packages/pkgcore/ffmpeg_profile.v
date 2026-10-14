// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

pub const ffmpeg_application_id = 'org.ffmpeg.cli'
pub const ffprobe_application_id = 'org.ffmpeg.probe'
pub const ffmpeg_runtime_id = 'org.vinix.ffmpeg-runtime'
pub const ffmpeg_profile_version = '8.0.1'
pub const ffmpeg_source_digest = '05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41'
pub const ffmpeg_source_bytes = u64(11388848)

const ffmpeg_libraries = ['lib/libavcodec.so.62', 'lib/libavdevice.so.62', 'lib/libavfilter.so.11',
	'lib/libavformat.so.62', 'lib/libavutil.so.60', 'lib/libswresample.so.6', 'lib/libswscale.so.9']
const ffmpeg_notices = ['licenses/ffmpeg-LICENSE.md', 'licenses/ffmpeg-COPYING.LGPLv2.1',
	'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING', 'licenses/v-COPYRIGHT', 'sources/build.json',
	'sources/linux-runner.v', 'sources/ffmpeg-build.v', 'sources/ffmpeg-source.json']

pub struct FfmpegProfileInfo {
pub:
	format int = 1
	profile string = 'ffmpeg-cli'
	directory string
	catalog string
	catalog_sha256 string
	ffmpeg_version string = ffmpeg_profile_version
	runtime_version string
	architectures []string
}

fn ffmpeg_elf_kind(path string) string {
	return if path in ['bin/ffmpeg', 'bin/ffprobe'] { 'pie' } else if path == 'bin/vinix-linux-runner' { 'static' }
		else if path.starts_with('lib/') { 'shared' } else { '' }
}

fn ffmpeg_templates(architecture string, runtime_version string) []RootRecipe {
	mut recipes := []RootRecipe{}
	for name in ['ffmpeg', 'ffprobe'] {
		recipes << RootRecipe{
			manifest: Package{ id: if name == 'ffmpeg' { ffmpeg_application_id } else { ffprobe_application_id },
				version: ffmpeg_profile_version, architecture: architecture, name: if name == 'ffmpeg' { 'FFmpeg' } else { 'FFprobe' },
				description: if name == 'ffmpeg' { 'Isolated FFmpeg CLI profile: local AVI/MPEG-4 and WAV/PCM encoding, generated video/audio and filters. Use run-args for command flags; network, hardware codecs and external codecs are disabled.' }
					else { 'Isolated FFprobe CLI profile: inspect local AVI/MPEG-4 and WAV/PCM media with run-args. Shares the explicitly versioned FFmpeg runtime.' },
				homepage: 'https://ffmpeg.org/', license: 'LGPL-2.1-or-later', kind: 'linux',
				runtime: ffmpeg_runtime_id, entrypoint: 'bin/vinix-linux-runner', permissions: ['files'],
				arguments: ['@RUNTIME@/lib/ld-musl-' + architecture + '.so.1', '@APP@/bin/' + name],
				dependencies: [Dependency{ id: ffmpeg_runtime_id, minimum: '1.0.0', before: '2.0.0' }] }
			entries: [RootEntry{ source: 'bin/' + name, path: 'bin/' + name },
				RootEntry{ source: ffmpeg_notices[0], path: ffmpeg_notices[0] },
				RootEntry{ source: ffmpeg_notices[1], path: ffmpeg_notices[1] }]
		}
	}
	mut entries := [RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
		RootEntry{ source: 'lib/libc.so', path: 'lib/libc.so' },
		RootEntry{ source: 'lib/libc.so', path: 'lib/ld-musl-' + architecture + '.so.1' }]
	for path in ffmpeg_libraries { entries << RootEntry{ source: path, path: path } }
	for path in ffmpeg_notices { entries << RootEntry{ source: path, path: path } }
	entries << RootEntry{ source: 'sources/ffmpeg.tar.xz', path: 'sources/ffmpeg.tar.xz' }
	recipes << RootRecipe{
		manifest: Package{ id: ffmpeg_runtime_id, version: runtime_version, architecture: architecture,
			name: 'FFmpeg isolated runtime', description: 'Explicit musl loader, FFmpeg 8.0 shared libraries, static SDK runner, unmodified upstream source and build instructions for the local media CLI profile.',
			homepage: 'https://ffmpeg.org/', license: 'GPL-2.0-or-later AND MIT AND LGPL-2.1-or-later', kind: 'runtime' }
		entries: entries
	}
	return recipes
}

pub fn ffmpeg_catalog(runtime_version string, source_roots string, destination string) !FfmpegProfileInfo {
	return ffmpeg_catalog_with(runtime_version, source_roots, destination, CatalogOptions{})
}

fn ffmpeg_catalog_with(runtime_version string, source_roots string, destination string, options CatalogOptions) !FfmpegProfileInfo {
	version_parts(runtime_version)!
	if compare_versions(runtime_version, '1.0.0') < 0 || compare_versions(runtime_version, '2.0.0') >= 0 {
		return error('FFmpeg profile runtime must be in the supported 1.x compatibility range')
	}
	root := capture_prepared_root(source_roots, 'FFmpeg profile')!
	defer { C.close(root) }
	target := export_target(destination, 'FFmpeg profile')!
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64'] {
		fd := C.openat(root, architecture.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('FFmpeg profile requires both ordinary architecture roots: ${architecture}') }
		roots[architecture] = fd
		mut root_bytes := u64(0)
		for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so', ...ffmpeg_libraries] {
			profile_elf(fd, path, architecture, ffmpeg_elf_kind(path), true)!
			node := import_node(fd, path)!
			C.close(node.fd)
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		for path in ffmpeg_notices {
			node := import_node(fd, path)!
			C.close(node.fd)
			if node.mode & 0o170000 != 0o100000 || node.bytes == 0 || node.bytes > u64(1024 * 1024) {
				return error('FFmpeg profile requires a nonempty redistribution/build notice of at most 1 MiB: ${path}')
			}
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		source := import_node(fd, 'sources/ffmpeg.tar.xz')!
		C.close(source.fd)
		if source.mode & 0o170000 != 0o100000 || source.bytes != ffmpeg_source_bytes || source.mode & 0o111 != 0 {
			return error('FFmpeg profile requires the ordinary, nonexecutable pinned 8.0.1 source archive')
		}
		root_bytes = mirror_cost(root_bytes, source.bytes)!
		needed = mirror_cost(needed, root_bytes)!
		if root_bytes > scratch { scratch = root_bytes }
	}
	parent := os.dir(target)
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(os.temp_dir())!, scratch, 64 * 1024 * 1024)!
	stage := export_stage(parent, '.vinix-ffmpeg-profile')!
	defer { os.rmdir_all(stage) or {} }
	options.checkpoint('created', stage)!
	mut packages := []CatalogImport{}
	for architecture in ['aarch64', 'x86_64'] {
		for recipe in ffmpeg_templates(architecture, runtime_version) {
			p := pack_root_descriptor(recipe, roots[architecture], stage + '/inventory', false)!
			profile_file_inventory(recipe, p, ffmpeg_notices)!
			objects := C.open((stage + '/inventory/objects').str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
			if objects < 0 { return error('cannot inspect FFmpeg profile inventory') }
			for file in p.files {
				kind := ffmpeg_elf_kind(file.path)
				if kind != '' {
					if !file.executable { C.close(objects); return error('FFmpeg profile payload is not executable: ${file.path}') }
					profile_elf(objects, file.sha256, architecture, kind, false) or {
						C.close(objects)
						return error('FFmpeg profile imported ${p.id}/${file.path}: ${err}')
					}
				}
				if file.path == 'sources/ffmpeg.tar.xz' && (file.sha256 != ffmpeg_source_digest || file.bytes != ffmpeg_source_bytes || file.executable) {
					C.close(objects)
					return error('FFmpeg profile source archive differs from the reviewed 8.0.1 pin')
				}
			}
			C.close(objects)
			packages << CatalogImport{ source: architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
		}
	}
	canonical := json2.encode(catalog_recipe(json2.encode(CatalogRecipe{ format: 1,
		architectures: ['aarch64', 'x86_64'], packages: packages }))!) + '\n'
	if canonical.len > max_metadata { return error('FFmpeg catalog lock exceeds metadata limit') }
	os.mkdir(stage + '/lock')!
	os.chmod(stage + '/lock', 0o700)!
	atomic_write(stage + '/lock/catalog.json', canonical)!
	publish_new_directory(stage + '/lock', target, 'FFmpeg profile')!
	sync_directory(parent) or { return error('FFmpeg profile published at ${target}, but its directory flush failed: ${err}') }
	return FfmpegProfileInfo{ directory: target, catalog: target + '/catalog.json', catalog_sha256: index_digest(canonical),
		runtime_version: runtime_version, architectures: ['aarch64', 'x86_64'] }
}
