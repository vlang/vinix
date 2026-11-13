// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import json2

fn test_headless_monitor_has_no_x11_dependency() {
	result := staged_source('monitor_linux.v', '/unused') or { panic(err) }
	assert result !is json2.Null
	text := decode(result.str()) or { panic(err) }
	assert text.contains('fn native_monitor_refresh_rate() f64')
	assert text.contains('return 0')
	assert !text.contains('#include')
}

fn test_headless_manifest_excludes_native_window_hosts() {
	text := filter_manifest_subdirs("Module { subdirs: ['ui', 'appkit', 'uikit', 'windows', 'linux'] }")!
	assert module_subdirs(text)! == ['ui', 'uikit', 'windows']
}
