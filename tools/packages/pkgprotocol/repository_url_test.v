// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

const repository_url_accepted = [
	'https://example.invalid', 'https://example.invalid/', 'https://example.invalid///',
	'https://localhost:8443/repository', 'https://localhost:000443/repository',
	'https://localhost:0/repository', 'https://localhost:65535/repository',
	'https://127.0.0.1:10443/repository', 'https://[::1]:8443/repository',
	'https://[2001:db8::1]/repository', 'https://[fe80::1%25en0]:443/repository',
	'https://example.invalid/a%20b/%2F/%40/%3f%23',
	'https://example.invalid/literal@path;dollar$/é',
	// The transport, not this syntax guard, validates literal address content.
	'https://[address-for-transport]/repository',
	'file:///srv/repository', 'file:///media/repository with spaces; $literal',
	'file:///media/100%literal/@repo', 'file:///é/文件',
]

const repository_url_refused = [
	'', 'http://example.invalid', 'HTTPS://example.invalid', 'https://', 'https:///',
	'https:///repository', 'https://:443/repository', 'https://user@example.invalid',
	'https://user:secret@example.invalid', 'https://host:443@other/repository',
	'https://host:443@/repository', 'https://host name/repository',
	'https://host/repository with spaces', 'https://host/\t', 'https://host/\r\n',
	'https://host/\x00', 'https://host/\x7f', 'https://host\\other/repository',
	'https://host/repository\\other', 'https://host/%', 'https://host/%1',
	'https://host/%q0', 'https://host/%0q', 'https://host%/repository',
	'https://[::1/repository', 'https://[]/repository', 'https://[[::1]]/repository',
	'https://[::1]]/repository', 'https://[::1]extra/repository',
	'https://[::1]@other/repository', 'https://[user@host]/repository',
	'https://host]/repository', 'https://ho[st/repository', 'https://::1/repository',
	'https://host:/repository', 'https://[::1]:/repository', 'https://host:443:80/repository',
	'https://host:+443/repository', 'https://host:-1/repository',
	'https://host:65536/repository', 'https://host:999999999999999999999999/repository',
	'https://host:port/repository', 'https://host/repository?query', 'https://host/repository#fragment',
	'file://relative', 'file:///', 'file:///a/', 'file:///a//b', 'file:///a/./b',
	'file:///a/../b', 'file:///a\\b', 'file:///a?b', 'file:///a#b',
]

fn url_require(ok bool, message string) { if !ok { panic(message) } }

fn test_repository_url_syntax_and_borrowed_validation_agree() {
	key := 'a'.repeat(64)
	defer { unsafe { key.free() } }
	for accepted in repository_url_accepted {
		url_require(valid_repository_url(accepted), 'refused supported URL: ' + accepted)
		validate_repository('fixture', accepted, key)!
	}
	for refused in repository_url_refused {
		url_require(!valid_repository_url(refused), 'accepted malformed URL: ' + refused)
		if _ := validate_repository('fixture', refused, key) {
			panic('SDK repository admission bypassed shared guard')
		} else { message := err.msg(); unsafe { message.free(); err.free() } }
	}
	maximum := 'https://host/' + 'a'.repeat(4096 - 13)
	overflow := maximum + 'a'
	defer { unsafe { maximum.free(); overflow.free() } }
	url_require(maximum.len == 4096 && valid_repository_url(maximum), '4096-byte URL refused')
	url_require(!valid_repository_url(overflow), 'oversized URL admitted')
	validate_repository('fixture', maximum, key)!
	if _ := validate_repository('fixture', overflow, key) { panic('SDK accepted oversized HTTPS URL') }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
	file_maximum := 'file:///' + 'a'.repeat(1024)
	file_overflow := file_maximum + 'a'
	defer { unsafe { file_maximum.free(); file_overflow.free() } }
	url_require(valid_repository_url(file_maximum), '1024-byte literal file suffix refused')
	url_require(!valid_repository_url(file_overflow), 'oversized literal file suffix admitted')
	validate_repository('fixture', file_maximum, key)!
	if _ := validate_repository('fixture', file_overflow, key) { panic('SDK accepted oversized file suffix') }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
	println('REPOSITORY URL syntax, literal file compatibility and exact size bound PASS')
}

fn test_repository_previous_identity_uses_shared_url_admission() {
	key := 'a'.repeat(64)
	defer { unsafe { key.free() } }
	review := RepositoryReview{ format: 1, operation: 'enroll', architecture: 'aarch64',
		id: 'fixture', url: 'https://localhost:8443/catalog', public_key: key,
		previous_url: 'https://host:443@other', previous_public_key: key,
		fingerprint: key, index_sha256: key, sequence: 1, expires: 2000000000 }
	if _ := review.validate() { panic('malformed previous identity accepted') }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
	valid := RepositoryReview{ ...review, previous_url: 'https://[::1]:8443/catalog' }
	valid.validate()!
	maximum := 'file:///' + 'a'.repeat(1024)
	overflow := maximum + 'a'
	defer { unsafe { maximum.free(); overflow.free() } }
	boundary := RepositoryReview{ ...review, previous_url: maximum }
	boundary.validate()!
	too_long := RepositoryReview{ ...review, previous_url: overflow }
	if _ := too_long.validate() { panic('oversized previous file identity accepted') }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
	url_require(review.previous_url == 'https://host:443@other' && valid.public_key == key,
		'validation changed caller-owned review fields')
	println('REPOSITORY URL previous identity admission and borrowed fields PASS')
}

fn test_repository_url_repeated_validation_keeps_no_allocations() {
	owned := 'https://[::1]:000443/a%20b'.clone()
	defer { unsafe { owned.free() } }
	mut accepted := 0
	mut refused := 0
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		for url in repository_url_accepted { if valid_repository_url(url) { accepted++ } }
		for url in repository_url_refused { if !valid_repository_url(url) { refused++ } }
		if valid_repository_url(owned) { accepted++ }
	}
	$if track_heap ? {
		kept := C.vinix_heap_end(); count := C.vinix_heap_count()
		url_require(kept == 0 && count == 0, 'URL scan retained tracked allocations')
	}
	url_require(accepted == (repository_url_accepted.len + 1) * 1000
		&& refused == repository_url_refused.len * 1000, 'incomplete repeated URL matrix')
	url_require(owned == 'https://[::1]:000443/a%20b', 'borrowed URL changed')
	println('REPOSITORY URL 1000 repeated matrices preserve borrowed input PASS')
	$if track_heap ? { println('REPOSITORY URL zero retained tracked bytes and records PASS') }
}
