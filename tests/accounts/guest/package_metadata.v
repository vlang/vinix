// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import json2
import os
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn qualify_package_metadata(mut t Test, db accountcore.Database, alex accountcore.User, sam accountcore.User) ! {
	service := pkgcore.Service{}
	before := service.state()!
	config := os.read_file('/etc/vinix-packages/config.json')!
	lock_path := '/tmp/metadata lock é; $literal.json'
	mut document := service.lock_deployment([])!
	defer { document.close() }
	lock_text := json2.encode(document)
	mut decoded := pkgprotocol.decode_deployment_document(lock_text)!
	assert decoded.packages == before.requested && decoded.locked.len == before.packages.len
	assert decoded.locked[0].id == 'admin-fixture' && decoded.locked[0].minimum_sequence == 1
	decoded.close(); decoded.close()
	os.write_file(lock_path, lock_text)!
	os.chmod(lock_path, 0o644)!
	for user in [alex, sam] {
		view_response := run(['/usr/bin/vinix-package', 'view'], '', db, user)
		assert view_response.status == 0, view_response.output
		mut view := pkgprotocol.decode_software_view(view_response.output)!
		assert view.generation == before.generation && view.rows.len == 1 && view.launch_user == ''
		assert view.rows[0].id == 'admin-fixture' && view.rows[0].installed_version == '1.0.0'
		assert view.rows[0].kind == 'data' && view.rows[0].installed_kind == 'data'
		assert !view.rows[0].firmware && !view.rows[0].proprietary && !view.rows[0].updatable
		assert view.rows[0].installed_permissions.len == 0 && view.rows[0].installed_window_protocol == 0
		view.close()
		for malformed in [view_response.output.replace('"firmware":false,', ''),
			view_response.output.replace('"installed_window_protocol":0', '"installed_window_protocol":false'),
			view_response.output.replace('"installed_permissions":[]', '"installed_permissions":[],"installed_permission\\u0073":["files"]')] {
			mut invalid := false
			pkgprotocol.decode_software_view(malformed) or { invalid = true }
			assert invalid
		}
		status_response := run(['/usr/bin/vinix-package', '--json', 'repo-list'], '', db, user)
		assert status_response.status == 0, status_response.output
		mut status := pkgprotocol.decode_repositories(status_response.output)!
		assert status.repositories.len == 1 && status.history.len == 1 && status.history[0].sequence == 1
		status.close()
		review_response := run(['/usr/bin/vinix-package', 'review', 'install', 'admin-fixture'], '', db, user)
		assert review_response.status == 0, review_response.output
		mut review := pkgprotocol.decode_review(review_response.output)!
		assert review.rows.len == 1 && review.rows[0].action == 'keep' && review.rows[0].requested
		assert !review.rows[0].proprietary && !review.rows[0].firmware && review.rows[0].permissions.len == 0
		review.close()
		mut refused := false
		pkgprotocol.decode_review(review_response.output.replace('"firmware":false,', '')) or { refused = true }
		assert refused
		trust_response := run(['/usr/bin/vinix-package', 'repo-review', 'revoke', 'admin-publisher'], '', db, user)
		assert trust_response.status == 0, trust_response.output
		mut trust := pkgprotocol.decode_repository_review(trust_response.output)!
		assert trust.operation == 'revoke' && trust.sequence == 0 && trust.index_sha256 == ''
		trust.close()
		mirror_response := run(['/usr/bin/vinix-package', 'mirror-review', '/tmp/metadata export é; $literal', 'admin-fixture'], '', db, user)
		assert mirror_response.status == 0, mirror_response.output
		mut mirror := pkgprotocol.decode_mirror_review(mirror_response.output)!
		assert mirror.review.rows.len == 1 && mirror.review.rows[0].action == 'export'
		mirror.close()
		locked_response := run(['/usr/bin/vinix-package', 'mirror-deployment-review', '/tmp/metadata locked export', lock_path], '', db, user)
		assert locked_response.status == 0, locked_response.output
		mut locked := pkgprotocol.decode_deployment_mirror_review(locked_response.output)!
		assert locked.deployment == lock_path && locked.mirror.review.rows.len == 1
		locked.close()
		refused = false
		pkgprotocol.decode_deployment_mirror_review(locked_response.output.replace('"firmware":false,', '')) or { refused = true }
		assert refused
		for malformed in [lock_text[..lock_text.len / 2], lock_text.replace('"format":2', '"format":2.0'),
			lock_text.replace('"minimum_sequence":1', '"minimum_sequence":18446744073709551616'),
			lock_text.replace('"locked":[', '"locked":[null,'),
			lock_text.replace('"id":"admin-fixture"', '"id":"admin-fixture","i\\u0064":"admin-fixture"')] {
			os.write_file(lock_path, malformed)!
			for operation in [['deployment-review', lock_path],
				['mirror-deployment-review', '/tmp/metadata locked export', lock_path]] {
				response := run(['/usr/bin/vinix-package', ...operation], '', db, user)
				assert response.status != 0 && response.output.trim_space() != '' && !response.output.contains('V panic:'), response.output
			}
		}
		os.write_file(lock_path, '{"packages":[],"architecture":"' + before.architecture + '","format":1}')!
		roots_response := run(['/usr/bin/vinix-package', 'deployment-review', lock_path], '', db, user)
		assert roots_response.status == 0, roots_response.output
		mut roots_review := pkgprotocol.decode_review(roots_response.output)!
		assert roots_review.rows.len == 1 && roots_review.rows[0].action == 'remove'; roots_review.close()
		os.write_file(lock_path, lock_text)!
	}
	assert service.state()! == before && os.read_file('/etc/vinix-packages/config.json')! == config
	assert !os.exists('/tmp/metadata export é; $literal') && !os.exists('/tmp/metadata locked export')
	t.say('PACKAGE METADATA ordinary-admin-standard complete-package-trust-history-offline-lock typed-flags nested-refusal read-only PASS')
	t.say('PACKAGE VIEW ordinary-admin-standard complete-catalog installed-launch-fields typed-flags nested-refusal read-only PASS')
	t.say('PACKAGE DEPLOYMENT bounded-reader formats-1-2 owned-fields malformed-refusal read-only PASS')
}
