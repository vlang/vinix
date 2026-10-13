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
	os.write_file(lock_path, json2.encode(service.lock_deployment([])!))!
	os.chmod(lock_path, 0o644)!
	for user in [alex, sam] {
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
	}
	assert service.state()! == before && os.read_file('/etc/vinix-packages/config.json')! == config
	assert !os.exists('/tmp/metadata export é; $literal') && !os.exists('/tmp/metadata locked export')
	t.say('PACKAGE METADATA ordinary-admin-standard complete-package-trust-history-offline-lock typed-flags nested-refusal read-only PASS')
}
