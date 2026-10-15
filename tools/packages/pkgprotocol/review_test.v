// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

fn protocol_fixture() Review {
	return Review{
		format:       1
		operation:    'install'
		names:        ['app']
		architecture: 'aarch64'
		fingerprint:  'a'.repeat(64)
		requested:    ['app']
		rows:         [ReviewPackage{
			id:           'app'
			name:         'Application'
			version:      '1.0.0'
			architecture: 'aarch64'
			kind:         'native'
			repository:   'trusted'
			public_key:   'b'.repeat(64)
			license:      'MIT'
			requested:    true
			action:       'install'
		}]
	}
}

fn test_public_review_rejects_unknown_formats_and_incomplete_package_sets() {
	valid := protocol_fixture()
	valid.validate()!
	mut decoded := decode_review(json2.encode(valid))!
	decoded.validate()!
	decoded.close()
	assert decoded.rows.len == 0 && decoded.fingerprint == ''
	for bad in [Review{ ...valid, format: 2 }, Review{ ...valid, format: 0 },
		Review{ ...valid, operation: 'shell' }, Review{ ...valid, fingerprint: 'unsigned' },
		Review{ ...valid, rows: [] }, Review{ ...valid, requested: ['missing'] },
		Review{ ...valid, rows: [valid.rows[0], valid.rows[0]] },
		Review{ ...valid, names: ['bad;command'] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], action: 'remove' }] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], architecture: 'x86_64' }] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], permissions: ['root'] }] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], public_key: '' }] },
		Review{ ...valid, operation: 'rollback', names: [], target_generation: 0 }] {
		mut refused := false
		bad.validate() or { refused = true }
		assert refused
	}
}

fn test_repair_review_preserves_installed_versions_and_excludes_other_actions() {
	base := protocol_fixture()
	valid := Review{ ...base, operation: 'repair', names: [], rows: [ReviewPackage{ ...base.rows[0], installed_version: '1.0.0', action: 'update' }] }
	for action in ['update', 'keep'] {
		mut decoded := decode_review(json2.encode(Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], action: action }] }))!
		decoded.close()
	}
	for bad in [Review{ ...valid, names: ['app'] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], installed_version: '' }] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], version: '2.0.0' }] },
		Review{ ...valid, rows: [ReviewPackage{ ...valid.rows[0], action: 'install' }] },
		Review{ ...valid, requested: [], rows: [ReviewPackage{ ...valid.rows[0], requested: false, action: 'remove' }] }] {
		mut refused := false
		bad.validate() or { refused = true; unsafe { err.free() } }
		assert refused
	}
}
