// SPDX-License-Identifier: GPL-2.0-or-later
module generatorsdk

import os
import encoding.utf8

#include <sys/stat.h>

fn metadata(path string, expected string, version string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len > 1024 * 1024 || !utf8.validate(bytes.data, bytes.len) { return error('invalid SDK distribution metadata: ' + path) }
	mut fields := map[string]string{}
	for line in bytes.bytestr().replace('\r\n', '\n').split('\n') {
		if line == '' { break }
		key := line.all_before(':')
		if key !in ['Name', 'Version'] { continue }
		value := line.all_after(':').trim_space()
		if key in fields || value == '' { return error('invalid SDK metadata field: ' + key) }
		fields[key] = value
	}
	if fields['Name'].to_lower().replace('_', '-') != expected.to_lower().replace('_', '-') || fields['Version'] == '' || (version != '' && fields['Version'] != version) {
		return error('SDK requires ' + expected + if version == '' { '' } else { '==' + version })
	}
}

fn distribution(site string, name string, version string, module_path string) ! {
	mut matches := []string{}
	for entry in os.ls(site)! {
		if !entry.ends_with('.dist-info') { continue }
		stem := entry[..entry.len - 10].all_before_last('-').to_lower().replace('_', '-')
		if stem == name.to_lower().replace('_', '-') { matches << site + '/' + entry + '/METADATA' }
	}
	if matches.len != 1 { return error('SDK needs one installed distribution of ' + name + ': ' + site) }
	metadata(matches[0], name, version)!
	if !os.is_file(site + '/' + module_path) { return error('SDK module is missing: ' + module_path) }
}

// Deliberately require an isolated SDK layout. Package metadata verifies its
// declared prerequisites, not importability or the upstream generator runtime.
pub fn verify(kind string, executable string) !string {
	if kind !in ['qemu', 'virgl'] { return error('unknown generator SDK: ' + kind) }
	selected := if executable.contains('/') { os.abs_path(executable) } else { os.find_abs_path_of_executable(executable)! }
	if !os.is_file(selected) || !os.is_executable(selected) { return error('generator SDK executable is missing: ' + selected) }
	// Keep the selected venv prefix: resolving a Python symlink would select its
	// base installation and lose the isolated site-packages directory.
	prefix := os.dir(os.dir(selected))
	mut sites := []string{}
	for base in [prefix + '/lib', prefix + '/lib64'] {
		for name in os.ls(base) or { []string{} } {
			if !name.starts_with('python3.') { continue }
			minor := name[8..]
			if minor == '' || !minor.bytes().all(it.is_digit()) { continue }
			site := base + '/' + name + '/site-packages'
			if os.is_dir(site) {
				canonical := os.real_path(site)
				if canonical !in sites { sites << canonical }
			}
		}
	}
	if sites.len != 1 { return error('generator SDK needs one Python 3 site-packages directory: ' + prefix) }
	if kind == 'qemu' {
		distribution(sites[0], 'tomli', '2.2.1', 'tomli/__init__.py')!
	} else {
		distribution(sites[0], 'meson', '', 'mesonbuild/__init__.py')!
		distribution(sites[0], 'PyYAML', '', 'yaml/__init__.py')!
	}
	return selected
}
