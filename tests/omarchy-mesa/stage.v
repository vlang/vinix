// SPDX-License-Identifier: GPL-2.0-or-later
// Stage Omarchy's prebuilt Mesa and everything it needs from Arch Linux ARM
// into a root directory, checking every package against its sync database.
//
//   v run tests/omarchy-mesa/stage.v --state NEW_DIR [--cache DIR] [--omarchy URL]
//       [--mirror URL] [ROOT...]
//
// A package in the cache directory is used instead of downloading it only if
// its size and SHA-256 match the database.
import os
import crypto.sha256
import pacmandb

const default_roots = ['filesystem', 'mesa-aurora', 'vulkan-aurora', 'libdrm', 'mesa-utils',
	'vulkan-tools']
const arch_repos = ['core', 'extra', 'alarm']
// Documentation, terminfo and the netfilter headers are left out: nothing
// here uses them, and some of systemd's man pages, terminfo entries and the
// kernel's xt_*.h headers differ only in case.
const left_out = ['usr/share/man', 'usr/share/doc', 'usr/share/info', 'usr/share/gtk-doc',
	'usr/share/locale', 'usr/share/terminfo', 'usr/include/linux/netfilter',
	'usr/include/linux/netfilter_ipv4', 'usr/include/linux/netfilter_ipv6',
	'usr/include/linux/netfilter_bridge']

fn run(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args.join(' ')}: ${result.output}')
	}
	return result.output
}

fn fetch(url string, path string) ! {
	run(['curl', '-fsSL', '--retry', '3', '--max-time', '900', '-o', path, url])!
}

fn file_sha256(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

// tar_of returns a tar that bsdtar reads directly: the zstd packages are
// decompressed first, since this bsdtar has no zstd; xz and gzip it reads.
fn tar_of(path string, scratch string) !string {
	if path.ends_with('.zst') {
		run(['zstd', '-d', '-q', '-f', '-o', scratch, '--', path])!
		return scratch
	}
	if path.ends_with('.xz') || path.ends_with('.gz') {
		return path
	}
	return error('unknown compression: ${path}')
}

fn main() {
	mut state := ''
	mut cache := ''
	mut omarchy := 'https://pkgs.omarchy.org/edge/aarch64'
	mut mirror := 'https://de3.mirror.archlinuxarm.org/aarch64'
	mut roots := []string{}
	mut index := 1
	for index < os.args.len {
		argument := os.args[index]
		match argument {
			'--state', '--cache', '--omarchy', '--mirror' {
				if index + 1 >= os.args.len {
					eprintln('${argument} needs a value')
					exit(2)
				}
				value := os.args[index + 1]
				match argument {
					'--state' { state = value }
					'--cache' { cache = value }
					'--omarchy' { omarchy = value }
					else { mirror = value }
				}
				index += 2
			}
			else {
				if argument.starts_with('-') {
					eprintln('usage: stage.v --state NEW_DIR [--cache DIR] [--omarchy URL] [--mirror URL] [ROOT...]')
					exit(2)
				}
				roots << argument
				index++
			}
		}
	}
	if state == '' {
		eprintln('--state is required')
		exit(2)
	}
	if roots.len == 0 {
		roots = default_roots.clone()
	}
	if os.exists(state) && os.ls(state)!.len > 0 {
		eprintln('${state} is not empty')
		exit(2)
	}
	stage(os.real_path(os.dir(state)) + '/' + os.base(state), cache, omarchy, mirror, roots) or {
		eprintln('stage: ${err.msg()}')
		exit(1)
	}
}

fn stage(state string, cache string, omarchy string, mirror string, roots []string) ! {
	for dir in ['db', 'pkgs', 'root'] {
		os.mkdir_all('${state}/${dir}')!
	}
	mut db := pacmandb.Db{}
	mut db_lines := []string{}
	mut sources := map[string]string{}
	sources['omarchy'] = omarchy
	for repo in arch_repos {
		sources[repo] = '${mirror}/${repo}'
	}
	for repo in ['omarchy', ...arch_repos] {
		archive := '${state}/db/${repo}.db'
		fetch('${sources[repo]}/${repo}.db', archive)!
		extracted := '${state}/db/${repo}'
		os.mkdir_all(extracted)!
		run(['tar', '-xf', archive, '-C', extracted])!
		db.load(repo, extracted)!
		db_lines << '${file_sha256(archive)!}  ${repo}.db  ${sources[repo]}/${repo}.db'
	}
	os.write_file('${state}/db/SHA256SUMS', db_lines.join('\n') + '\n')!

	chosen := db.closure(roots)!
	mut download := u64(0)
	mut installed := u64(0)
	for p in chosen {
		download += p.csize
		installed += p.isize
	}
	println('closure: ${chosen.len} packages, ${download / 1048576} MiB to download, ${installed / 1048576} MiB installed')

	mut manifest := ['# repo\tname\tversion\tfilename\tsha256\tcsize']
	for p in chosen {
		path := '${state}/pkgs/${p.filename}'
		cached := '${cache}/${p.filename}'
		if cache != '' && os.is_file(cached) && u64(os.file_size(cached)) == p.csize
			&& file_sha256(cached)! == p.sha256 {
			os.cp(cached, path)!
		} else {
			fetch('${sources[p.repo]}/${p.filename}', path)!
		}
		size := u64(os.file_size(path))
		digest := file_sha256(path)!
		if size != p.csize || digest != p.sha256 {
			return error('${p.filename}: got ${size} bytes, sha256 ${digest}; database says ${p.csize}, ${p.sha256}')
		}
		manifest << '${p.repo}\t${p.name}\t${p.version}\t${p.filename}\t${p.sha256}\t${p.csize}'
	}
	os.write_file('${state}/manifest.tsv', manifest.join('\n') + '\n')!

	// macOS volumes ignore case; two paths that differ only in case would
	// silently become one file in the staged root.
	scratch := '${state}/pkgs/.current.tar'
	mut seen := map[string]string{}
	mut collisions := []string{}
	for p in chosen {
		archive := tar_of('${state}/pkgs/${p.filename}', scratch)!
		for entry in run(['tar', '-tf', archive])!.split_into_lines() {
			name := entry.trim_right('/')
			if name == '' || name.starts_with('.') || left_out.any(name == it || name.starts_with(it + '/')) {
				continue
			}
			key := name.to_lower()
			if other := seen[key] {
				if other != name {
					collisions << '${other} and ${name} (${p.name})'
				}
			}
			seen[key] = name
		}
		mut exclusions := []string{}
		for prefix in left_out {
			exclusions << ['--exclude', prefix]
		}
		run(['tar', '-xf', archive, '-C', '${state}/root', ...exclusions, '--exclude', '.PKGINFO',
			'--exclude', '.MTREE', '--exclude', '.BUILDINFO', '--exclude', '.INSTALL', '--exclude',
			'.CHANGELOG'])!
	}
	os.rm(scratch) or {}
	if collisions.len > 0 {
		return error('paths that differ only in case:\n' + collisions.join('\n'))
	}
	// Extracted as an ordinary user, a file such as dbus's setuid helper can
	// end up unreadable to its owner, and mke2fs could not copy it.
	unreadable := run(['find', '${state}/root', '!', '-type', 'l', '!', '-perm', '-u+r'])!.trim_space()
	os.write_file('${state}/made-readable.txt', unreadable + '\n')!
	for path in unreadable.split_into_lines() {
		run(['chmod', 'u+r', path])!
	}
	println('staged ${state}/root')
}
