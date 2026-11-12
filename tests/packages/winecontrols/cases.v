// SPDX-License-Identifier: GPL-2.0-or-later
module winecontrols

pub fn source() string { return $embed_file('cases.v').to_string() }

pub fn names(architecture string, forksafe bool) ![]string {
	if architecture !in ['aarch64', 'x86_64'] || (forksafe && architecture != 'aarch64') {
		return error('invalid Wine control architecture/mode')
	}
	mut result := ['failed', 'interrupted', 'reason', 'missing-ready', 'duplicate-ready', 'missing-pass',
		'marker-order', 'forbidden', 'input-mismatch', 'missing-fixture-input', 'missing-library-input',
		'missing-hidden-library-input', 'producer-missing-hidden-library-input', 'missing-generated-c',
		'missing-generated-log', 'missing-generated-argv', 'changed-generated-c', 'missing-package-c',
		'missing-package-log', 'missing-package-argv', 'changed-package', 'package-v-argv',
		'package-cc-argv', 'changed-account', 'changed-sandbox', 'producer-c-output-only',
		'producer-missing-c', 'producer-missing-log', 'producer-missing-argv', 'producer-v-argv',
		'producer-cc-argv', 'producer-missing-locale', 'producer-missing-intl',
		'producer-changed-locale', 'producer-changed-intl', 'producer-missing-inf',
		'producer-changed-inf', 'pe-executable-binding', 'resealed-prepared-pe', 'source-offer-closure',
		'wine-server-resealed-patch', 'wine-client-resealed-patch', 'wine-server-proc-nls',
		'wine-client-rwx-image', 'missing-image-marker', 'wine-client-unwind-index', 'wine-client-unwind-cfa',
		'missing-software-exception', 'missing-read-fault', 'duplicate-read-fault', 'exception-marker-order']
	if architecture == 'aarch64' {
		result << ['translator-declaration', 'translator-resealed-patch', 'translator-resealed-smoke',
			'missing-smoke-marker', 'missing-arm-loader-input', 'missing-firmware-vars-input',
			'missing-arm-loader-declaration', 'missing-firmware-vars-declaration']
	} else {
		result << ['missing-iso-input', 'changed-iso-argv', 'x86-firmware-vars', 'missing-wx-marker']
	}
	if forksafe {
		result << ['forksafe-implicit', 'forksafe-missing-translator',
			'forksafe-missing-translator_manifest', 'forksafe-missing-fork_patch',
			'forksafe-manifest-binding']
	}
	return result
}
