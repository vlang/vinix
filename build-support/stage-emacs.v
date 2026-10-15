// SPDX-License-Identifier: GPL-2.0-or-later
// Stage Alpine's unchanged Emacs and its libraries in a private runtime.
module main

import alpinecore
import crypto.sha256
import json2
import os

const mirror = 'https://dl-cdn.alpinelinux.org/alpine/v3.22'

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

fn main() {
	if os.args.len != 2 {
		eprintln('usage: v run build-support/stage-emacs.v OUTPUT_DIRECTORY')
		exit(2)
	}
	os.mkdir_all(os.args[1])!
	output := os.real_path(os.args[1])
	cache := '${output}/downloads'
	root := '${output}/staging/usr/libexec/vinix-emacs/root'
	os.mkdir_all(root)!
	mut packages := []alpinecore.Package{}
	for repository in ['main', 'community'] {
		index := '${cache}/${repository}'
		os.mkdir_all(index)!
		download('${mirror}/${repository}/aarch64/APKINDEX.tar.gz', '${index}/index.tar.gz')!
		run('tar', ['-xzf', '${index}/index.tar.gz', '-C', index, 'APKINDEX'])!
		packages << alpinecore.parse_index('${index}/APKINDEX', repository)!
	}
	resolved := alpinecore.resolve(packages, ['emacs-x11', 'font-dejavu', 'fontconfig',
		'xkeyboard-config'])!
	mut pins := []PackagePin{}
	for package in resolved {
		if package.name == 'emacs-x11' && package.version != '30.1-r1' {
			panic('expected the tested Emacs 30.1-r1 package; update its launcher paths before upgrading')
		}
		filename := '${package.name}-${package.version}.apk'
		path := '${cache}/${filename}'
		println(filename)
		download('${mirror}/${package.repository}/aarch64/${filename}', path)!
		run('tar', ['-xzf', path, '-C', root])!
		pins << PackagePin{ name: package.name, version: package.version,
			repository: package.repository, sha256: sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file('${output}/packages.json', json2.encode(pins))!
	println('Staged native ARM64 Emacs: ${root}/usr/bin/emacs')
}
