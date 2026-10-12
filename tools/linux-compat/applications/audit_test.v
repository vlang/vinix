module main

import crypto.sha256
import os

fn fixture(name string) !(string, string) {
	root := os.real_path(os.dir(@FILE) + '/../../..')
	base := root + '/tests/linux-compat/results/2026-10-11/'
	return os.read_file(base + name + '.json')!, os.read_file(base + 'inputs-' + name + '.json')!
}

fn reseal(receipt string, old string, changed string) string {
	return receipt.replace(sha256.sum(old.trim_space().bytes()).hex(), sha256.sum(changed.trim_space().bytes()).hex())
}

fn test_guest_evidence_rejects_edited_output_even_with_passing_verdict() {
	raw, receipt := fixture('catalog-aarch64')!
	assert audit_application(raw, receipt, 'aarch64', 'media')!.status == 'passed'
	changed := raw.replace('"mpeg4"', '"h264"')
	assert changed != raw
	audit_application(changed, receipt, 'aarch64', 'media') or { return }
	assert false, 'edited evidence was accepted'
}

fn test_host_architecture_duplicate_and_exit_contradictions_are_refused() {
	raw, receipt := fixture('catalog-aarch64')!
	for changed in [raw.replace('"vinix-guest"', '"host"'),
		raw.replace('"native-aarch64"', '"native-x86_64"'),
		raw.replace('"name": "office"', '"name": "media"')] {
		audit_application(changed, reseal(receipt, raw, changed), 'aarch64', 'media') or { continue }
		assert false, 'resealed invalid evidence was accepted'
	}
	audit_application(raw, receipt.replace('"exit_code": 0', '"exit_code": 1'), 'aarch64', 'media') or { return }
	assert false, 'contradictory controller exit was accepted'
}

fn test_index_preserves_all_families_qualified_runtimes_and_remaining_failures() {
	root := os.real_path(os.dir(@FILE) + '/../../..')
	index := application_index(root)!
	assert !index.complete_support_qualified
	for arch in ['aarch64', 'x86_64'] {
		for category in ['browsers', 'office', 'media', 'language runtimes', 'databases', 'servers', 'games'] {
			assert index.applications.any(it.architecture == arch && it.category == category)
		}
		browsers := index.applications.filter(it.architecture == arch && it.category == 'browsers')
		assert browsers.len == 2
		assert browsers.filter(it.workload == 'chromium').all(it.status == 'failed')
		firefox := browsers.filter(it.workload == 'firefox')[0]
		assert firefox.status == if arch == 'x86_64' { 'passed' } else { 'failed' }
		if arch == 'x86_64' { assert firefox.limitations.contains('4096 MiB') && !firefox.full_lifecycle_qualified }
		java := index.applications.filter(it.architecture == arch && it.workload == 'java')[0]
		assert java.status == 'passed' && java.limitations.contains('UID 1000') && !java.full_lifecycle_qualified
	}
	assert index.applications.all(valid_hash(it.report_sha256) && valid_hash(it.receipt_sha256)
		&& valid_hash(it.kernel_sha256) && it.limitations != '')
}
