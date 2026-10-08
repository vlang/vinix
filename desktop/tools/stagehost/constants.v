// SPDX-License-Identifier: GPL-2.0-only
module stagehost

const main_pattern = '^fn main\\(\\) \\{'
const embedded_view_pattern = '^const\\s+([A-Za-z_]\\w*_(?:qml|vml)_source)\\s*=\\s*\\\$embed_file\\([^\\n]+\\)\\.to_string\\(\\)\\n'
const legacy_license_preamble = '\\A// Copyright \\(c\\) [^\\n]+\\. All rights reserved\\.\\n// Use of this source code is governed by a GPL v2 license\\n// that can be found in the LICENSE file\\.\\n\\n(?=// SPDX-License-Identifier:)'
const icon_lines_0 = [
	'// Generated from desktop/assets/*.qoi by desktop/tools/stage_app.py.',
	'// Edit the QOI files, not this.',
	'// Returned bytes belong to static read-only storage. Never modify or free them.',
	'#ifndef VINIX_APP_ICON_DATA_H',
	'#define VINIX_APP_ICON_DATA_H',
	'#include <stddef.h>',
	'#include <string.h>',
	'',
]
const icon_lines_1 = [
	'};',
	'',
]
const icon_lines_2 = [
	'static inline void *vinix_app_icon_data(const char *name, size_t *size) {',
	'    if (size != NULL) *size = 0;',
	'    if (name == NULL) return NULL;',
]
const icon_lines_3 = [
	'    return NULL;',
	'}',
	'',
	'static inline size_t vinix_app_icon_size(const char *name) {',
	'    size_t size = 0;',
	'    vinix_app_icon_data(name, &size);',
	'    return size;',
	'}',
	'#endif',
	'',
]
