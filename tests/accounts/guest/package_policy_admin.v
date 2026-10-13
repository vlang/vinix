// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import json2
import os
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn qualify_package_policy_admin(mut t Test, db accountcore.Database, alex accountcore.User, sam accountcore.User) ! {
	service := pkgcore.Service{}
	initial := pkgcore.load_config('')!
	mut original := service.policy()!
	defer { original.close() }
	before := service.state()!
	path := '/tmp/company policy; $literal é.json'
	proposed := pkgcore.PolicyDocument{ architecture: initial.architecture,
		policy: pkgcore.Policy{ offline: true, allowed: ['another-app'], permissions: [], licenses: [], allow_firmware: false, reserve_bytes: 65536 } }
	os.write_file(path, json2.encode(proposed))!
	os.chmod(path, 0o644)!
	for user in [alex, sam] {
		current := run(['/usr/bin/vinix-package', 'policy'], '', db, user)
		assert current.status == 0, current.output
		mut displayed := pkgprotocol.decode_policy_document(current.output)!
		assert displayed.architecture == initial.architecture && displayed.policy.offline
		displayed.close()
		response := run(['/usr/bin/vinix-package', 'policy-review', path], '', db, user)
		assert response.status == 0, response.output
		mut review := pkgprotocol.decode_policy_review(response.output)!
		assert review.generation == before.generation && review.rows.len == 1
		assert review.rows[0].id == 'admin-fixture' && review.rows[0].public_key == initial.repositories[0].public_key
		assert review.rows[0].diagnostic_before == '' && review.rows[0].diagnostic_after.contains('allowlist')
		assert review.proposed.permissions.len == 0 && !review.proposed.allow_firmware && review.proposed.licenses.len == 0
		assert pkgcore.load_config('')!.policy == initial.policy && service.state()! == before
		review.close()
	}
	mut review := service.review_policy(path)!
	defer { review.close() }
	command := ['/usr/bin/vinix-package', 'admin', 'policy-apply', review.fingerprint, path]
	standard := run(command, sam_password + '\n', db, sam)
	assert standard.status != 0 && standard.output.contains('cannot approve'), standard.output
	wrong := run(command, 'wrong password\n', db, alex)
	assert wrong.status != 0 && pkgcore.load_config('')!.policy == initial.policy, wrong.output
	// A file change after review is checked again inside the privileged writer.
	os.write_file(path, json2.encode(pkgcore.PolicyDocument{ ...proposed,
		policy: pkgcore.Policy{ ...proposed.policy, reserve_bytes: 65537 } }))!
	stale := run(command, alex_password + '\n', db, alex)
	assert stale.status != 0 && stale.output.contains('stale'), stale.output
	assert pkgcore.load_config('')!.policy == initial.policy && service.state()! == before
	os.write_file(path, json2.encode(proposed))!
	applied := run(command, alex_password + '\n', db, alex)
	assert applied.status == 0, applied.output
	mut displayed := pkgprotocol.decode_policy_document(applied.output)!
	assert displayed.policy.allowed == ['another-app'] && displayed.policy.reserve_bytes == 65536
	displayed.close()
	assert service.state()! == before && pkgcore.load_config('')!.repositories == initial.repositories
	assert owner_of('/etc/vinix-packages/config.json') == 0
	assert !applied.output.contains(alex_password) && os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	// Restore policy before the existing remove/rollback/trust lifecycle checks.
	os.write_file(path, json2.encode(original))!
	mut restoration := service.review_policy(path)!
	defer { restoration.close() }
	restored := run(['/usr/bin/vinix-package', 'admin', 'policy-apply', restoration.fingerprint, path], alex_password + '\n', db, alex)
	assert restored.status == 0 && pkgcore.load_config('')!.policy == original.policy && service.state()! == before, restored.output
	t.say('PACKAGE POLICY ordinary-admin-standard public-read complete-impact literal-path password-role stale-file-refusal atomic-policy-only reload clean-runtime PASS')
}
