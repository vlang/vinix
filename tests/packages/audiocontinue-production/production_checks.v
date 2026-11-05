// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only companion for a private production overlay. The pinned compiler
// removes assert statements under -prod, so these reviewed checks use ordinary
// control flow. Never copy this file into the production implementation module.
module audiocontinue

import crypto.sha256
import os

const production_original_tests2 = {
	'budget_test.v': '4ef52a06ee9bd8b29c6fc9768acd75728fa76948517f8c47b2a41c442374a886'
	'inventory_test.v': '5ca9f740da9df5172613cfa4e6617fcfdc75ee14486873649a14b40fc98c02ca'
	'trace_test.v': '63411a7b2ab130daa24ba8d6680939a306aa63ba0e38774c64e6cd528dd15df9'
	'commands_test.v': '95613c5af7c9015591341a80f45cb77d5c8cbfd40675b14fd23aab2fdbfd402a'
	'boundary_test.v': '7c21ed14431f55778243b52797e8fb72ecaef1398a21713c0d8ae4aa9c357e97'
	'owner_test.v': '9c4c38a853370fef38527349d6723ab050f72fbd8de17aa833e71ee3917b924f'
}

const production_sites2 = {
	'budget_test.v': 15
	'inventory_test.v': 31
	'trace_test.v': 3
	'commands_test.v': 33
	'boundary_test.v': 30
	'owner_test.v': 14
}

const production_implementation_files2 = ['types.v', 'inventory.v', 'donor.v',
	'plan.v', 'budget.v', 'trace.v', 'commands.v', 'completion.v', 'engine.v', 'verify.v']

// Unlike the language assert statement, this body survives -prod. A failure is
// intentionally fail-fast; a successful 44-call main still runs every check.
fn production_require2(condition bool, description string) {
	if !condition { panic('AUDIO PRODUCTION CHECK FAILED: ' + description) }
}

fn production_source2(path string) !string {
	ordinary2(path, 'file')!
	before := os.lstat(path)!
	if before.nlink != 1 || before.size > 256 * 1024 {
		return error('production check source must be an independent bounded ordinary file')
	}
	text := os.read_file(path)!
	if !same2(before, os.lstat(path)!) { return error('production check source changed during reading') }
	return text
}

fn production_verify2() !int {
	original := os.getenv('AUDIO_CONTINUATION_PROD_ORIGINAL')
	derived := os.dir(@FILE)
	ordinary2(original, 'directory')!
	ordinary2(derived, 'directory')!
	if !disjoint2(original, derived) { return error('production test source roots must be separate') }
	prefix := 'production_require2(('
	suffix := "), 'production assertion')"
	mut total := 0
	for name, sum in production_original_tests2 {
		before := production_source2(original + '/' + name)!
		after := production_source2(derived + '/' + name)!
		sites := production_sites2[name] or { return error('missing production test site count') }
		if sha256.hexhash(before) != sum || before.contains(prefix) || before.contains(suffix)
			|| before.count('assert ') != sites || after.contains('assert ')
			|| after.count(prefix) != sites || after.count(suffix) != sites {
			return error('production test source hash or exact site count differs: ' + name)
		}
		// The complete inverse must recover every original byte. Independent
		// source review also checked all 126 wrapper positions and conditions,
		// including inline guards, multiline arrays and side-effecting SIGTERM.
		if after.replace(prefix, 'assert ').replace(suffix, '') != before {
			return error('production test inverse differs: ' + name)
		}
		a := os.lstat(original + '/' + name)!
		b := os.lstat(derived + '/' + name)!
		if a.dev == b.dev && a.inode == b.inode { return error('production test source aliases its original') }
		total += sites
	}
	for name in production_implementation_files2 {
		before := production_source2(original + '/' + name)!
		after := production_source2(derived + '/' + name)!
		if after != before { return error('production implementation differs: ' + name) }
		a := os.lstat(original + '/' + name)!
		b := os.lstat(derived + '/' + name)!
		if a.dev == b.dev && a.inode == b.inode { return error('production implementation aliases its original') }
	}
	if total != 126 { return error('production assertion count must remain126') }
	return total
}

fn init() {
	sites := production_verify2() or { panic('AUDIO PRODUCTION SOURCE PROOF FAILED: ' + err.msg()) }
	println('AUDIO PRODUCTION SOURCE PROOF PASS sites=' + sites.str())
	if os.getenv('AUDIO_CONTINUATION_PROD_FORCE_FAILURE') == '1' {
		println('AUDIO PRODUCTION FORCED FALSE')
		production_require2(false, 'intentional forced false')
	}
}
