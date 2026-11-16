// SPDX-License-Identifier: GPL-2.0-or-later
// SBPL ordinary data-read projection. Directory/metadata reads stay open.
module winereadclosure

pub const system_roots = ['/usr/lib', '/System/Library']
pub const devices = ['/dev/null', '/dev/random', '/dev/urandom']

fn safe(path string) bool {
	if !path.starts_with('/') || path.len > 4096 { return false }
	for part in path[1..].split('/') { if part in ['', '.', '..'] { return false } }
	return path.bytes().all(it.is_alnum() || it in [u8(`/`), `.`, `_`, `-`, `+`])
}

pub fn system(path string) bool {
	return system_roots.any(path.starts_with(it + '/'))
}

pub fn policy(paths []string) !string {
	if paths.len == 0 || paths.len > 8192 { return error('bounded nonempty read capability list required') }
	mut ordered := paths.clone(); ordered.sort()
	mut text := '(version 1)\n(allow default)\n(deny file-read-data)\n(allow file-read-data (vnode-type DIRECTORY))\n(allow file-read-data\n'
	for root in system_roots { text += '  (subpath "' + root + '")\n' }
	for device in devices { text += '  (literal "' + device + '")\n' }
	mut previous := ''
	for path in ordered {
		if !safe(path) || path == previous { return error('read capability path is unsafe or repeated') }
		text += '  (literal "' + path + '")\n'
		previous = path
	}
	return text + ')\n'
}
