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
	work := 'build/package-sqlite-builder-owned-work'; cli := os.real_path(work + '/host-1/vinix-package')
	root := os.real_path(work) + '/cli fixture'; assert !os.exists(root); os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	for arch in ['aarch64', 'x86_64']! {
		for name in ['bin', 'lib', 'licenses']! { os.mkdir_all(root + '/roots/' + arch + '/' + name)! }
		for index, path in ['bin/sqlite3', 'bin/vinix-linux-runner', 'lib/libc.so', 'lib/libsqlite3.so.0']! {
			file := root + '/roots/' + arch + '/' + path
			os.write_file_array(file, elffixture.image(arch, if index == 0 { 'pie' } else if index == 1 { 'static' } else { 'shared' }))!
			os.chmod(file, 0o755)!
		}
		for name in ['sqlite-COPYRIGHT', 'musl-COPYRIGHT', 'vinix-COPYING']! { os.write_file(root + '/roots/' + arch + '/licenses/' + name, name)! }
	}
	mut inputs := []pkgcore.CatalogRecipe{}
	for index, version in ['1.0.0', '1.1.0']! {
		target := root + '/lock-' + index.str()
		code, output := invoke(cli, ['sqlite-catalog', '3.53.4', version, root + '/roots', target])
		assert code == 0, output
		mut reply := json2.decode[pkgcore.SqliteProfileInfo](output)!
		assert reply.format == 1 && reply.profile == 'sqlite-cli' && reply.directory == target && reply.catalog == target + '/catalog.json'
		assert reply.sqlite_version == '3.53.4' && reply.runtime_version == version && reply.architectures == ['aarch64', 'x86_64']
		text := os.read_file(reply.catalog)!
		assert reply.catalog_sha256 == sha256.sum(text.bytes()).hex()
		if index == 0 { assert reply.catalog_sha256 == '359e8ab218db656657a0b64cca63263e6b589397960b9503e953a65c10fc86e2' }
		inputs << json2.decode[pkgcore.CatalogRecipe](text)!
		reply.close(); reply.close(); assert os.is_file(target + '/catalog.json')
	}
	assert inputs[0].packages.filter(it.recipe.manifest.id == 'org.sqlite.cli') == inputs[1].packages.filter(it.recipe.manifest.id == 'org.sqlite.cli')
	for mode in ['occupied', 'version', 'range']! {
		target := root + if mode == 'occupied' { '/lock-0' } else { '/refused' }
		before := os.read_file(root + '/lock-0/catalog.json')!
		code, output := invoke(cli, ['sqlite-catalog', '3.53.4', if mode == 'range' { '2.0.0' } else if mode == 'version' { '1.01.0' } else { '1.0.0' }, root + '/roots', target])
		assert code != 0 && output.contains(match mode { 'occupied' { 'destination must be new' } 'version' { 'invalid version' } else { 'supported 1.x' } })
		assert before == os.read_file(root + '/lock-0/catalog.json')! && !os.exists(root + '/refused')
	}
	println('SQLITE BUILDER production CLI format-1 replies, paths with spaces, unchanged application on runtime update and exact refusal preservation PASS')
}
