// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixture

import os
import sourcecommand

#include <sys/stat.h>

fn header_version(directory string) !string {
	if !os.is_file(directory + '/Python.h') { return error('CPython development headers were not found: ' + directory) }
	text := os.read_file(directory + '/patchlevel.h')!
	mut numbers := []string{}
	for name in ['PY_MAJOR_VERSION', 'PY_MINOR_VERSION'] {
		mut found := ''
		for line in text.split_into_lines() {
			fields := line.fields()
			if fields.len >= 3 && fields[0] == '#define' && fields[1] == name {
				if found != '' || fields[2] == '' || !fields[2].bytes().all(it.is_digit()) { return error('invalid CPython version macro: ' + name) }
				found = fields[2]
			}
		}
		if found == '' { return error('missing CPython version macro: ' + name) }
		numbers << found
	}
	return numbers.join('.')
}

// Discover SDK data without launching an interpreter. An explicit include
// directory wins; otherwise resolve the chosen executable and its base prefix.
pub fn cpython_headers(executable string, explicit string) !string {
	if explicit != '' { header_version(explicit)!; return os.real_path(explicit) }
	selected := if executable.contains('/') { executable } else { os.find_abs_path_of_executable(executable)! }
	if !os.is_file(selected) { return error('CPython executable was not found: ' + executable) }
	resolved := os.real_path(selected)
	mut prefixes := [os.dir(os.dir(resolved))]
	venv := os.dir(os.dir(os.abs_path(selected))) + '/pyvenv.cfg'
	if os.is_file(venv) {
		for line in os.read_file(venv)!.split_into_lines() {
			if line.all_before('=').trim_space() == 'home' {
				home_path := line.all_after('=').trim_space()
				if home_path != '' { prefixes.prepend(os.dir(os.real_path(home_path))) }
			}
		}
	}
	$if macos {
		// Apple's /usr/bin launcher belongs to the active developer SDK.
		if resolved == '/usr/bin/python3' {
			developer := os.getenv_opt('DEVELOPER_DIR') or {
				selected_sdk := sourcecommand.capture_full(['/usr/bin/xcode-select', '-p'], os.environ(), 5, 65536, unsafe { nil })!
				if selected_sdk.status != 0 { return error('cannot find active developer SDK; set VINIX_CPYTHON_INCLUDE') }
				selected_sdk.stdout.trim_space()
			}
			for base in [developer + '/Library/Frameworks/Python3.framework/Versions',
				developer + '/Frameworks/Python3.framework/Versions'] {
				versions := os.ls(base) or { continue }
				for version in versions { if version != 'Current' { prefixes << base + '/' + version } }
			}
		}
	}
	name := os.file_name(resolved)
	version_hint := if name.starts_with('python') { name[6..].trim_right('dm') } else { '' }
	mut matches := []string{}
	for prefix in prefixes {
		mut candidates := [prefix + '/Headers']
		for name_part in os.ls(prefix + '/include') or { []string{} } {
			if name_part.starts_with('python') { candidates << prefix + '/include/' + name_part }
		}
		for directory in candidates {
			version := header_version(directory) or { continue }
			if version_hint.contains('.') && version != version_hint { continue }
			canonical := os.real_path(directory)
			if canonical !in matches { matches << canonical }
		}
		if matches.len != 0 { break }
	}
	if matches.len == 0 { return error('CPython development headers were not found; set VINIX_CPYTHON_INCLUDE') }
	if matches.len != 1 { return error('ambiguous CPython SDK; set VINIX_CPYTHON_INCLUDE') }
	return matches[0]
}

pub fn cpython_version(executable string, explicit string) !string {
	return header_version(cpython_headers(executable, explicit)!)
}
