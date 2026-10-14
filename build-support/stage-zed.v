// SPDX-License-Identifier: GPL-2.0-or-later
// Stage Alpine's native ARM64 Zed in a private musl/Vulkan runtime.
module main

import alpinecore
import crypto.sha256
import json2
import os

const zed_version = '0.138.4-r5'
const zed_sha256 = 'a520ddd336bcabf39b029c0fce5547d8ae03761880dcd6f00d929776df57b797'
const zed_url = 'https://repo.huaweicloud.com/alpine/edge/testing/aarch64/zed-${zed_version}.apk'
const runtime_mirror = 'https://dl-cdn.alpinelinux.org/alpine/v3.22'

struct PackagePin {
	name       string
	version    string
	repository string
	sha256     string
}

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	defer { process.close() }
	process.set_args(args)
	process.run()
	process.wait()
	if process.code != 0 { return error('${program} failed (${process.code})') }
}

fn download(url string, path string) ! {
	if os.is_file(path) { return }
	part := path + '.partial'
	defer { os.rm(part) or {} }
	run('curl', ['-fLsS', '--retry', '3', '--connect-timeout', '15', '--max-time', '180', url,
		'-o', part])!
	os.mv(part, path)!
}

fn stage(directory string) ! {
	os.mkdir_all(directory)!
	output := os.real_path(directory)
	cache := '${output}/downloads'
	os.mkdir_all(cache)!
	archive := '${cache}/zed-${zed_version}.apk'
	if os.is_file(archive) && sha256.sum(os.read_bytes(archive)!).hex() != zed_sha256 {
		os.rm(archive)!
	}
	download(zed_url, archive)!
	if sha256.sum(os.read_bytes(archive)!).hex() != zed_sha256 {
		return error('Zed archive checksum mismatch')
	}
	metadata := os.exec(['tar', '-xOzf', archive, '.PKGINFO'])
	if metadata.exit_code != 0 { return error('cannot read Zed package metadata') }
	mut requests := ['vulkan-loader', 'mesa-vulkan-swrast', 'font-dejavu', 'fontconfig',
		'xkeyboard-config']
	for line in metadata.output.split_into_lines() {
		if line.starts_with('depend = ') { requests << line['depend = '.len..] }
	}
	mut packages := []alpinecore.Package{}
	for repository in ['main', 'community'] {
		index_dir := '${cache}/${repository}'
		os.mkdir_all(index_dir)!
		download('${runtime_mirror}/${repository}/aarch64/APKINDEX.tar.gz', '${index_dir}/index.tar.gz')!
		run('tar', ['-xzf', '${index_dir}/index.tar.gz', '-C', index_dir, 'APKINDEX'])!
		packages << alpinecore.parse_index('${index_dir}/APKINDEX', repository)!
	}
	resolved := alpinecore.resolve(packages, requests)!
	println('Alpine Zed ${zed_version}: ${resolved.len} private runtime packages')
	root := '${output}/staging/usr/libexec/vinix-zed/root'
	os.mkdir_all(root)!
	mut pins := []PackagePin{}
	for package in resolved {
		filename := '${package.name}-${package.version}.apk'
		path := '${cache}/${filename}'
		println('  ${filename}')
		download('${runtime_mirror}/${package.repository}/aarch64/${filename}', path)!
		run('tar', ['-xzf', path, '-C', root])!
		pins << PackagePin{ name: package.name, version: package.version, repository: package.repository, sha256: sha256.sum(os.read_bytes(path)!).hex() }
	}
	run('tar', ['-xzf', archive, '-C', root])!
	icd := '${root}/usr/share/vulkan/icd.d/lvp_icd.aarch64.json'
	os.write_file(icd, os.read_file(icd)!.replace('"/usr/lib/libvulkan_lvp.so"',
		'"/usr/libexec/vinix-zed/root/usr/lib/libvulkan_lvp.so"'))!
	os.write_file('${output}/packages.json', json2.encode(pins))!
	os.write_file('${output}/zed-package.txt', metadata.output)!
	println('Staged unchanged Alpine ARM64 Zed at ${root}/usr/libexec/zed-editor')
}

fn main() {
	if os.args.len != 2 {
		eprintln('usage: v run build-support/stage-zed.v OUTPUT_DIRECTORY')
		exit(2)
	}
	stage(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
