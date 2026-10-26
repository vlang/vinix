module nativeaccountauth

import crypto.sha256

fn attestation_registry(selector string, digest string) !Registry {
	return parse_registry(registry_header + '\n' +
		['com.example.auth', '10001', '10002', '/srv/android/auth.apk', digest,
		'b'.repeat(64), selector].join('\t') + '\n')
}

fn attestation_launch(digest string) ServiceLaunch {
	return ServiceLaunch{'com.example.auth', 'com.example.auth.Service', 'android.accounts.AccountAuthenticator', digest}
}

fn test_account_type_attestation_is_optional_and_selected_exactly() {
	selector := 'com.example.auth.Service@android.accounts.AccountAuthenticator'
	digest := 'a'.repeat(64)
	legacy := attestation_registry(selector, digest)!
	assert selected_authenticator_type(legacy.entries[0], attestation_launch(digest))! == ''
	for value in ['com.example.account', 'opaque-account_type:1', 'com.google'] {
		registry := attestation_registry(selector + '@' + value, digest)!
		assert registry.entries[0].services[0].account_type == value
		assert selected_authenticator_type(registry.entries[0], attestation_launch(digest))! == value
	}
	// The type is selected by both class and action, never by first registration.
	registry := attestation_registry('com.example.other.Service@com.example.OTHER@other,' +
		selector + '@selected', digest)!
	assert selected_authenticator_type(registry.entries[0], attestation_launch(digest))! == 'selected'
}

fn test_conflicting_or_unframed_account_type_attestations_are_rejected() {
	selector := 'com.example.auth.Service@android.accounts.AccountAuthenticator'
	for suffix in ['', 'has space', 'has\ttab', 'has\nnewline', 'has\x00nul', 'has\x7fdel',
		'nonascii-ö', 'x'.repeat(256), 'type@extra', 'type,extra'] {
		mut rejected := false
		attestation_registry(selector + '@' + suffix, 'a'.repeat(64)) or { rejected = true }
		assert rejected, suffix
	}
	for selectors in [selector + ',' + selector + '@com.example.type',
		selector + '@one,' + selector + '@two', selector + '@one,' + selector,
		selector + '@one,' + selector + '@one'] {
		mut rejected := false
		attestation_registry(selectors, 'a'.repeat(64)) or { rejected = true }
		assert rejected
	}
}

fn test_attestation_rejects_package_selector_or_apk_pin_substitution() {
	digest := 'a'.repeat(64)
	registry := attestation_registry('com.example.auth.Service@android.accounts.AccountAuthenticator@registered', digest)!
	for launch in [
		ServiceLaunch{'com.other.auth', 'com.example.auth.Service', 'android.accounts.AccountAuthenticator', digest},
		ServiceLaunch{'com.example.auth', 'com.example.other.Service', 'android.accounts.AccountAuthenticator', digest},
		ServiceLaunch{'com.example.auth', 'com.example.auth.Service', 'com.example.OTHER', digest},
		attestation_launch('b'.repeat(64)),
	] {
		mut rejected := false
		selected_authenticator_type(registry.entries[0], launch) or { rejected = true }
		assert rejected
	}
	for identity in [['/other.apk', '10001', '10002'], ['/srv/android/auth.apk', '10002', '10002'],
		['/srv/android/auth.apk', '10001', '10003']] {
		mut rejected := false
		registry.verify_authenticator_type(identity[0], identity[1].u32(), identity[2].u32(), attestation_launch(digest)) or {
			rejected = true
		}
		assert rejected
	}
}

fn test_changed_authenticator_metadata_cannot_reuse_an_apk_attestation() {
	// The registry pins all APK bytes, including XML metadata. No XML value is
	// consulted as runtime authority, and a changed metadata digest cannot be
	// substituted into the root service frame under the old registration.
	metadata := '<account-authenticator accountType="com.example.account" customTokens="true"/>'
	digest := sha256.sum(metadata.bytes()).hex()
	changed := sha256.sum(metadata.replace('com.example.account', 'com.other.account').bytes()).hex()
	assert changed != digest
	registry := attestation_registry('com.example.auth.Service@android.accounts.AccountAuthenticator@com.example.account', digest)!
	assert selected_authenticator_type(registry.entries[0], attestation_launch(digest))! == 'com.example.account'
	mut rejected := false
	selected_authenticator_type(registry.entries[0], attestation_launch(changed)) or { rejected = true }
	assert rejected
}
