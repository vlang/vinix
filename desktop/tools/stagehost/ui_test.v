// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import json2

fn test_headless_monitor_has_no_x11_dependency() {
	for name in ['monitor_linux.v', 'monitor_nix.v'] {
		result := staged_source(name, '/unused') or { panic(err) }
		assert result !is json2.Null
		text := decode(result.str()) or { panic(err) }
		assert text.contains('fn native_monitor_refresh_rate() f64')
		assert text.contains('return 0')
		assert !text.contains('#include')
	}
}

fn test_headless_manifest_excludes_native_window_backends() {
	manifest := "Module { name: 'ui2', subdirs: ['ui', 'appkit', 'uikit', 'windows', 'linux'] }"
	staged := filter_manifest_subdirs(manifest)!
	assert module_subdirs(staged)! == ['ui', 'uikit', 'windows']
}
