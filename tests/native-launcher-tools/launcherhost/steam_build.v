// SPDX-License-Identifier: GPL-2.0-or-later
module launcherhost

import cachecli
import gamehost
import os
import runtimehost
import steamshim

pub fn unpack_steam_deb(argv []string) !int {
	args := cachecli.arguments(argv, [], [], [], 2, 2, 'Unpack the Steam installer control and data archives.\nUsage: unpack-steam-deb INSTALLER.deb OUTPUT') or { return error_with_code(err.msg(), 2) }
	bytes := os.read_bytes(args.positional[0])!
	output := args.positional[1]
	gamehost.mkdir(output)!
	members := runtimehost.ar_members(bytes)!
	for member in members {
		if !member.name.starts_with('control.tar') && !member.name.starts_with('data.tar') {
			continue
		}
		temporary := output + '/.payload-' + os.getpid().str()
		os.write_file_array(temporary, member.payload)!
		defer { os.rm(temporary) or {} }
		steamshim.extract(temporary, output + '/' + member.name.all_before('.'), steamshim.TarOptions{
			preserve_attributes: true
			decompressors:       {
				'gzip':  os.find_abs_path_of_executable('gzip')!
				'xz':    os.find_abs_path_of_executable('xz')!
				'bzip2': os.find_abs_path_of_executable('bzip2')!
			}
		})!
	}
	return 0
}

fn lexical_absolute(path string) string {
	full := if path.starts_with('/') { path } else { os.getwd() + '/' + path }
	mut parts := []string{}
	for part in full.split('/') {
		if part in ['', '.'] { continue }
		if part == '..' {
			if parts.len > 0 { parts.pop() }
		} else {
			parts << part
		}
	}
	return (if full.starts_with('//') && !full.starts_with('///') { '//' } else { '/' }) + parts.join('/')
}

pub fn relative_link(argv []string) !int {
	args := cachecli.arguments(argv, [], [], [], 2, 2, 'Print the relative target of an in-root Steam directory link.\nUsage: relative-link TARGET LINK') or { return error_with_code(err.msg(), 2) }
	target := lexical_absolute(args.positional[0])
	link := args.positional[1]
	base := lexical_absolute(gamehost.parent(link))
	target_parts := target.split('/').filter(it != '')
	base_parts := base.split('/').filter(it != '')
	mut common := 0
	for common < target_parts.len && common < base_parts.len && target_parts[common] == base_parts[common] {
		common++
	}
	mut result := []string{}
	for _ in common .. base_parts.len { result << '..' }
	result << target_parts[common..]
	println(if result.len == 0 { '.' } else { result.join('/') })
	return 0
}
