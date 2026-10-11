// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn native_runtime_fixture(language string, path string, source string) !string {
	if path !in ['native-aarch64', 'native-x86_64'] {
		return error('unsupported: ' + language + ' compilation requires a native runtime path')
	}
	guard := match language {
		'go' { 'runtime.GOARCH == "arm64"' }
		'java' { '"aarch64".equals(System.getProperty("os.arch"))' }
		else { return error('unknown runtime fixture language') }
	}
	if source.count(guard) != 1 {
		return error('application input has an unexpected architecture assertion')
	}
	if path == 'native-aarch64' { return source }
	mut result := source.replace(guard, if language == 'go' {
		'runtime.GOARCH == "amd64"'
	} else {
		'"amd64".equals(System.getProperty("os.arch"))'
	})
	if language == 'go' {
		result = result.replace('VINIX ARM64 GO SMOKE', 'VINIX AMD64 GO SMOKE')
			.replace('AArch64 Go runtime', 'x86-64 Go runtime')
	}
	return result
}

fn complete_java_bin(directory string) bool {
	return ['java', 'javac', 'jar'].all(os.is_executable(directory + '/' + it))
}

fn native_java_bin() !string {
	mut candidates := []string{}
	if java := os.find_abs_path_of_executable('java') {
		candidates << os.dir(os.real_path(java))
	}
	// Extracted qualification roots do not run java-common's post-install
	// script. Select all tools from one actual JDK, preserving PATH preference.
	if os.is_dir('/usr/lib/jvm') {
		mut names := os.ls('/usr/lib/jvm')!
		names.sort()
		for name in names { candidates << '/usr/lib/jvm/' + name + '/bin' }
	}
	for directory in candidates {
		if complete_java_bin(directory) { return os.real_path(directory) }
	}
	return error('unsupported: complete native JDK java/javac/jar tools are missing')
}
