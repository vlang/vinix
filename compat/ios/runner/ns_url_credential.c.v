// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Password credentials only. Certificate and trust credentials require Security
// objects and must never become a successful password authentication fallback.
struct CredentialSnapshot {
	user string
	password string
	has_user bool
	has_password bool
}

fn ns_credential_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSURLCredential']] or { panic('iOS: missing NSURLCredential') }
	cls.ivars['_internal'] = &ObjIvar{name: '_internal'.clone(), types: '@"NSURLCredentialInternal"'.clone(), offset: 8, size: 8}
}

fn ns_credential_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSURLCredential' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic credential superclass chain')
}

fn ns_credential_require_class(cls u64) {
	if ns_credential_family(cls) && cls != ios_runtime.names['NSURLCredential'] { panic('iOS: custom credential construction is not implemented') }
}

// Runtime lock held. The opaque native slot identifies owned metadata; it is
// compared, never dereferenced, so forged object bytes cannot grant ownership.
fn ns_credential_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.credential_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size != 16
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSURLCredential']
		|| read64(object + 8) != if header.credential_initialized { u64(header) } else { u64(0) } {
		panic('iOS: NSURLCredential requires live owned credential storage')
	}
	if initialized && !header.credential_initialized { panic('iOS: credential requires initialization') }
	return header
}

fn ns_credential_text(object u64) string {
	if object == 0 { return '' }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: credential input requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(object) or { panic('iOS: credential input requires a live UTF8 string') }
	if text.len > 65536 { panic('iOS: credential string exceeds byte limit') }
	return text
}

fn ns_credential_snapshot(user u64, password u64) CredentialSnapshot {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Validate and snapshot both inputs before any application constructor runs.
	a := ns_credential_text(user)
	b := ns_credential_text(password)
	return CredentialSnapshot{a.clone(), b.clone(), user != 0, password != 0}
}

fn ns_credential_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.credential_initializing { panic('iOS: destroying an active NSURLCredential') }
}

fn ns_credential_dispose(object u64, mut header ObjHeader) {
	if !header.credential_owned { return }
	// Generic field destruction releases the two immutable string references,
	// even after an isa change. No allocation is owned by the opaque slot itself.
	unsafe { C.memset(voidptr(object + 8), 0, 8) }
	header.credential_initialized = false
}

fn ns_credential_failed_init(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_credential_storage(object, false)
	if C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: credential constructor consumed receiver ownership') }
	if header.caller_storage { panic('iOS: failed credential initializer cannot consume caller-owned storage') }
	header.credential_initializing = false
	C.ios_objc_initialize_unlock()
	objc_release(object)
	return 0
}

fn ns_credential_commit(object u64, snapshot CredentialSnapshot, persistence u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_credential_storage(object, false)
	if header.credential_initialized || header.credential_initializing || header.fields[0] != 0 || header.fields[1] != 0 {
		panic('iOS: credential is already initialized or its constructor changed storage')
	}
	header.credential_initializing = true
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer { objc_release(object) }
	user := if snapshot.has_user { owned_string(snapshot.user) } else { u64(0) }
	defer { objc_release(user) }
	if snapshot.has_user && user == 0 { return ns_credential_failed_init(object) }
	password := if snapshot.has_password { owned_string(snapshot.password) } else { u64(0) }
	defer { objc_release(password) }
	if snapshot.has_password && password == 0 { return ns_credential_failed_init(object) }
	C.ios_objc_initialize_lock()
	header = ns_credential_storage(object, false)
	if !header.credential_initializing || header.credential_initialized || header.fields[0] != 0 || header.fields[1] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: credential string constructor changed destination storage') }
	header.fields[0] = objc_retain(user)
	header.fields[1] = objc_retain(password)
	header.credential_persistence = persistence
	header.credential_initialized = true
	header.credential_initializing = false
	unsafe { *(&u64(object + 8)) = u64(header) }
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_credential_initialize(object u64, user u64, password u64, persistence u64) u64 {
	snapshot := ns_credential_snapshot(user, password)
	defer { unsafe { snapshot.user.free(); snapshot.password.free() } }
	return ns_credential_commit(object, snapshot, persistence)
}

fn ns_credential_create(cls u64, user u64, password u64, persistence u64) u64 {
	ns_credential_require_class(cls)
	if cls != ios_runtime.names['NSURLCredential'] { panic('iOS: credential factory requires NSURLCredential') }
	snapshot := ns_credential_snapshot(user, password)
	defer { unsafe { snapshot.user.free(); snapshot.password.free() } }
	object := objc_allocate(cls)
	if object == 0 { return 0 }
	return ns_credential_commit(object, snapshot, persistence)
}

fn ns_credential_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ns_credential_storage(object, true)
	return objc_retain(object)
}

fn ns_credential_types(name string, meta bool, selector string) ?string {
	if name != 'NSURLCredential' { return none }
	if meta {
		return match selector {
			'credentialWithUser:password:persistence:' { '@40@0:8@16@24Q32' }
			else { return none }
		}
	}
	return match selector {
		'initWithUser:password:persistence:' { '@40@0:8@16@24Q32' }
		'user', 'password', 'certificates', 'copy' { '@16@0:8' }
		'hasPassword' { 'B16@0:8' }
		'persistence' { 'Q16@0:8' }
		'identity' { '^{__SecIdentity=}16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		else { return none }
	}
}

fn ns_credential_unsupported(selector string) bool {
	return selector in ['init', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'isEqual:', 'hash', 'description', 'debugDescription', 'initWithTrust:', 'credentialForTrust:',
		'initWithIdentity:certificates:persistence:', 'credentialWithIdentity:certificates:persistence:',
		'initWithUser:password:initialAccess:', '_CFURLCredential', '_cfurlcredential', '_hasSWCACreatorAttribute',
		'_initWithCFURLCredential:', '_initWithWebKitPropertyListData:', '_webKitPropertyListData']!
}

fn ns_credential_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_credential_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.credential_owned }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_credential_unsupported(selector) { panic('iOS: credential option is not implemented') }
	if ns_credential_types('NSURLCredential', meta, selector) == none { return false }
	if meta {
		frame.x[0] = objc_autorelease(ns_credential_create(object, frame.x[2], frame.x[3], frame.x[4]))
	} else {
		match selector {
			'initWithUser:password:persistence:' { frame.x[0] = ns_credential_initialize(object, frame.x[2], frame.x[3], frame.x[4]) }
			'copy', 'copyWithZone:' {
				if selector == 'copyWithZone:' && frame.x[2] != 0 { panic('iOS: credential copy zones are not implemented') }
				frame.x[0] = ns_credential_copy(object)
			}
			else {
				C.ios_objc_initialize_lock()
				header := ns_credential_storage(object, true)
				frame.x[0] = match selector {
					'user' { header.fields[0] }
					'password' { header.fields[1] }
					'hasPassword' { u64(header.fields[1] != 0) }
					'persistence' { header.credential_persistence }
					else { u64(0) } // A password credential has no identity or certificates.
				}
				C.ios_objc_initialize_unlock()
			}
		}
	}
	return true
}
