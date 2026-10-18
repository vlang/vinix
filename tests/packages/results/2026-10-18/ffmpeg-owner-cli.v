// SPDX-License-Identifier: GPL-2.0-or-later
module main
import crypto.sha256
import json2
import os
import tests.packages.elffixture
import tools.packages.pkgcore

fn invoke(cli string, arguments []string) (int, string) {
	mut child := os.new_process(cli); child.set_args(arguments); child.set_redirect_stdio_merged()
	child.run(); text := child.stdout_slurp(); child.wait(); code := child.code; child.close(); return code, text
}

fn main() {
	work := 'build/package-ffmpeg-owner-work'; cli := os.real_path(work + '/host-1/vinix-package')
	root := os.real_path(work) + '/cli fixture'; assert !os.exists(root); os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	archive := os.getenv('VINIX_PROFILE_EXPORT_SOURCE'); assert os.file_size(archive) == pkgcore.ffmpeg_source_bytes
	assert sha256.sum(os.read_bytes(archive)!).hex() == pkgcore.ffmpeg_source_digest
	for arch in ['aarch64', 'x86_64']! {
		for name in ['bin', 'lib', 'licenses', 'sources']! { os.mkdir_all(root + '/roots/' + arch + '/' + name)! }
		for path in ['bin/ffmpeg', 'bin/ffprobe', 'bin/vinix-linux-runner', 'lib/libc.so', 'lib/libavcodec.so.62', 'lib/libavdevice.so.62', 'lib/libavfilter.so.11', 'lib/libavformat.so.62', 'lib/libavutil.so.60', 'lib/libswresample.so.6', 'lib/libswscale.so.9']! {
			file := root + '/roots/' + arch + '/' + path
			kind := if path in ['bin/ffmpeg', 'bin/ffprobe']! { 'pie' } else if path == 'bin/vinix-linux-runner' { 'static' } else { 'shared' }
			os.write_file_array(file, elffixture.image(arch, kind))!; os.chmod(file, 0o755)!
		}
		for path in ['licenses/ffmpeg-LICENSE.md', 'licenses/ffmpeg-COPYING.LGPLv2.1', 'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING', 'licenses/v-COPYRIGHT', 'sources/build.json', 'sources/linux-runner.v', 'sources/ffmpeg-build.v', 'sources/ffmpeg-source.json']! { os.write_file(root + '/roots/' + arch + '/' + path, path)! }
		os.cp(archive, root + '/roots/' + arch + '/sources/ffmpeg.tar.xz')!
	}
	mut inputs := []pkgcore.CatalogRecipe{}
	for index, version in ['1.0.0', '1.1.0']! {
		target := root + '/lock-' + index.str()
		code, output := invoke(cli, ['ffmpeg-catalog', version, root + '/roots', target])
		assert code == 0, output
		mut reply := json2.decode[pkgcore.FfmpegProfileInfo](output)!
		assert reply.format == 1 && reply.profile == 'ffmpeg-cli' && reply.directory == target && reply.catalog == target + '/catalog.json'
		assert reply.ffmpeg_version == '8.0.1' && reply.runtime_version == version && reply.architectures == ['aarch64', 'x86_64']
		text := os.read_file(reply.catalog)!
		assert reply.catalog_sha256 == sha256.sum(text.bytes()).hex()
		if index == 0 { assert reply.catalog_sha256 == '3e143c0de9b7304576820a7dd70ad5949b23525211ca30a40a6791e8ccfc6431' }
		inputs << json2.decode[pkgcore.CatalogRecipe](text)!
		reply.close(); reply.close(); assert os.is_file(target + '/catalog.json')
	}
	assert inputs[0].packages.filter(it.recipe.manifest.kind == 'linux') == inputs[1].packages.filter(it.recipe.manifest.kind == 'linux')
	for mode in ['occupied', 'version', 'range']! {
		target := root + if mode == 'occupied' { '/lock-0' } else { '/refused' }
		before := os.read_file(root + '/lock-0/catalog.json')!
		code, output := invoke(cli, ['ffmpeg-catalog', if mode == 'range' { '2.0.0' } else if mode == 'version' { '1.01.0' } else { '1.0.0' }, root + '/roots', target])
		assert code != 0 && output.contains(match mode { 'occupied' { 'destination must be new' } 'version' { 'invalid version' } else { 'supported 1.x' } })
		assert before == os.read_file(root + '/lock-0/catalog.json')! && !os.exists(root + '/refused')
	}
	println('FFMPEG OWNER production CLI format-1 replies, paths with spaces, unchanged application on runtime update and exact refusal preservation PASS')
}
