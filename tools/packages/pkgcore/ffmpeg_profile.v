// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

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

// Retire independent reply metadata; published locks and caller inputs survive.
pub fn (mut info FfmpegProfileInfo) close() {
	unsafe {
		info.directory.free(); info.catalog.free(); info.catalog_sha256.free(); info.runtime_version.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
	}
	info = FfmpegProfileInfo{}
}

fn ffmpeg_profile_result(version string, directory string, canonical string) FfmpegProfileInfo {
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	return FfmpegProfileInfo{ directory: directory.clone(), catalog: directory + '/catalog.json',
		catalog_sha256: index_digest(canonical), runtime_version: version.clone(), architectures: review_strings(architectures) }
}

// Scalar manifest fields borrow literals and the caller's runtime version.
// Templates own argument/selector text and collection buffers; packed manifests
// are independent decodes. Catalog wrappers borrow the template selectors.
struct FfmpegProfilePlan {
	templates []RootRecipe
mut:
	packages []CatalogImport
}

fn ffmpeg_profile_plan(version string) FfmpegProfilePlan {
	mut templates := []RootRecipe{cap: 6}
	for architecture in ['aarch64', 'x86_64']! {
		recipes := ffmpeg_templates(architecture, version)
		for recipe in recipes { unsafe { templates.push_many(&recipe, 1) } }
		unsafe { (&array(&recipes)).free() }
	}
	return FfmpegProfilePlan{ templates: templates, packages: []CatalogImport{cap: 6} }
}

fn (mut plan FfmpegProfilePlan) close() {
	for item in plan.packages { close_decoded_package(item.recipe.manifest) }
	unsafe {
		(&array(&plan.packages)).free()
		for recipe in plan.templates {
			for entry in recipe.entries { entry.source.free(); entry.path.free() }
			for argument in recipe.manifest.arguments { argument.free() }
			(&array(&recipe.entries)).free(); (&array(&recipe.manifest.arguments)).free()
			(&array(&recipe.manifest.permissions)).free(); (&array(&recipe.manifest.dependencies)).free()
		}
		(&array(&plan.templates)).free()
	}
	plan = FfmpegProfilePlan{}
}

fn (plan FfmpegProfilePlan) canonical() !string {
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	text := publisher_json(CatalogRecipe{ format: 1, architectures: architectures, packages: plan.packages })
	defer { unsafe { text.free() } }
	input := catalog_recipe(text)!
	defer { close_decoded_catalog(input) }
	canonical := publisher_json(input)
	if canonical.len > max_metadata { unsafe { canonical.free() }; return error('FFmpeg catalog lock exceeds metadata limit') }
	return canonical
}

fn ffmpeg_elf_kind(path string) string {
	return if path in ['bin/ffmpeg', 'bin/ffprobe']! { 'pie' } else if path == 'bin/vinix-linux-runner' { 'static' }
		else if path.starts_with('lib/') { 'shared' } else { '' }
}

fn ffmpeg_templates(architecture string, runtime_version string) []RootRecipe {
	mut recipes := []RootRecipe{cap: 3}
	for name in ['ffmpeg', 'ffprobe']! {
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
	mut entries := []RootEntry{cap: 20}
	entries << RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' }
	entries << RootEntry{ source: 'lib/libc.so', path: 'lib/libc.so' }
	entries << RootEntry{ source: 'lib/libc.so', path: 'lib/ld-musl-' + architecture + '.so.1' }
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
	validated_version(runtime_version)!
	if compare_versions(runtime_version, '1.0.0') < 0 || compare_versions(runtime_version, '2.0.0') >= 0 {
		return error('FFmpeg profile runtime must be in the supported 1.x compatibility range')
	}
	root := capture_prepared_root(source_roots, 'FFmpeg profile')!
	defer { C.close(root) }
	target := export_target(destination, 'FFmpeg profile')!
	defer { unsafe { target.free() } }
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) }; unsafe { roots.free() } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64']! {
		fd := C.openat(root, architecture.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('FFmpeg profile requires both ordinary architecture roots: ${architecture}') }
		roots[architecture] = fd
		mut root_bytes := u64(0)
		for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so']! {
			profile_elf(fd, path, architecture, ffmpeg_elf_kind(path), true)!
			node := import_node(fd, path)!
			C.close(node.fd)
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		for path in ffmpeg_libraries {
			profile_elf(fd, path, architecture, 'shared', true)!
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
	temporary := import_temporary_directory()
	defer { unsafe { parent.free(); temporary.free() } }
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-ffmpeg-profile', 'FFmpeg profile')!
	defer { exporting.close() }
	canonical := write_ffmpeg_profile(runtime_version, roots, target, options, mut exporting) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return ffmpeg_profile_result(runtime_version, target, canonical)
}

fn write_ffmpeg_profile(runtime_version string, roots map[string]int, target string, options CatalogOptions, mut exporting ProfileStage) !string {
	stage := exporting.stage.path
	exporting.checkpoint('created', options)!
	mut plan := ffmpeg_profile_plan(runtime_version)
	defer { plan.close() }
	inventory := stage + '/inventory'; object_path := inventory + '/objects'
	defer { unsafe { inventory.free(); object_path.free() } }
	for recipe in plan.templates {
		architecture := recipe.manifest.architecture
		p := pack_root_descriptor(recipe, roots[architecture], inventory, false)!
		mut transferred := false
		defer { if !transferred { close_decoded_package(p) } }
		profile_file_inventory(recipe, p, ffmpeg_notices)!
		objects := C.open(object_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if objects < 0 { return error('cannot inspect FFmpeg profile inventory') }
		for file in p.files {
			kind := ffmpeg_elf_kind(file.path)
			if kind != '' {
				if !file.executable { C.close(objects); return error('FFmpeg profile payload is not executable: ${file.path}') }
				profile_elf(objects, file.sha256, architecture, kind, false) or {
					C.close(objects)
					cause := err.msg()
					message := 'FFmpeg profile imported ' + p.id + '/' + file.path + ': ' + cause
					unsafe { cause.free(); err.free() }
					return error(message)
				}
			}
			if file.path == 'sources/ffmpeg.tar.xz' && (file.sha256 != ffmpeg_source_digest || file.bytes != ffmpeg_source_bytes || file.executable) {
				C.close(objects)
				return error('FFmpeg profile source archive differs from the reviewed 8.0.1 pin')
			}
		}
		C.close(objects)
		plan.packages << CatalogImport{ source: architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
		transferred = true
		exporting.checkpoint('packed', options)!
	}
	canonical := plan.canonical()!
	mut published := false
	defer { if !published { unsafe { canonical.free() } } }
	exporting.publish(canonical, target, options)!
	published = true
	return canonical
}
