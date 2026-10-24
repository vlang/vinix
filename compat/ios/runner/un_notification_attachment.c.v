// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Immutable values only: no file import, options, security scopes or coding.
// fields[0..2] own the identifier snapshot, retained URL and type snapshot.
fn un_attachment_ivars() [7]string {
	return ['_securityScopedURL', '_securityScopeLock', '_userInfo', '_identifier', '_URL', '_type', '_options']!
}
fn un_attachment_ivar_types() [7]string {
	return ['@"UNSecurityScopedURL"', '{os_unfair_lock_s="_os_unfair_lock_opaque"I}', '@"NSDictionary"', '@"NSString"', '@"NSURL"', '@"NSString"', '@"UNNotificationAttachmentOptions"']!
}
fn un_attachment_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['UNNotificationAttachment']] or { panic('iOS: missing notification attachment') }
	for i, name in un_attachment_ivars() {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: un_attachment_ivar_types()[i].clone(), offset: i64(8 + 8 * i), size: if i == 1 { u64(4) } else { u64(8) }}
	}
}
fn un_attachment_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UNNotificationAttachment' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic notification attachment superclass chain')
}
fn un_attachment_require_class(cls u64) {
	if un_attachment_family(cls) && cls != ios_runtime.names['UNNotificationAttachment'] { panic('iOS: custom notification attachment construction is not implemented') }
}
// Caller holds the runtime lock. Do not accept isa changes as provenance.
fn un_attachment_url(url u64) {
	header := ios_runtime.objects[url] or { panic('iOS: attachment requires a live built-in URL') }
	if header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.allocation_cls != ios_runtime.names['NSURL'] || header.cls != header.allocation_cls || read64(url) != header.allocation_cls
		|| header.number !in [i64(0), 1]! || header.fields[0] == 0 {
		panic('iOS: attachment requires an initialized built-in URL')
	}
	un_request_text(header.fields[0])
	for i in 1 .. 7 { if header.fields[i] != 0 && i != 6 { un_request_text(header.fields[i]) } }
	if header.number == 1 && (header.fields[1] == 0 || header.fields[2] == 0 || header.fields[3] == 0) { panic('iOS: attachment requires a complete HTTP URL') }
}
fn un_attachment_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.un_attachment_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 64
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['UNNotificationAttachment'] { panic('iOS: attachment requires live owned built-in storage') }
	if initialized && !header.un_attachment_initialized { panic('iOS: attachment requires designated construction') }
	for offset := u64(8); offset < 64; offset += 8 {
		expected := if offset >= 32 && offset <= 48 { header.fields[(offset - 32) / 8] } else { u64(0) }
		if read64(object + offset) != expected { panic('iOS: notification attachment body was changed') }
	}
	if header.un_attachment_initialized { un_request_text(header.fields[0]); un_attachment_url(header.fields[1]); un_request_text(header.fields[2]) }
	return header
}
fn un_attachment_identifier() string {
	mut bytes := [16]u8{}; darwin_uuid_generate(unsafe { &bytes[0] })
	mut buffer := [36]u8{}; mut position := 0
	for byte in bytes {
		if position in [8, 13, 18, 23]! { buffer[position] = `-`; position++ }
		buffer[position] = '0123456789ABCDEF'[byte >> 4]; buffer[position + 1] = '0123456789ABCDEF'[byte & 15]; position += 2
	}
	return unsafe { tos(&buffer[0], 36).clone() }
}
fn un_attachment_failed_init(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := un_attachment_storage(object, false)
	if C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: attachment constructor consumed receiver ownership') }
	if header.caller_storage { panic('iOS: failed attachment initializer cannot consume caller-owned storage') }
	header.un_attachment_initializing = false
	C.ios_objc_initialize_unlock()
	objc_release(object)
	return 0
}
fn un_attachment_initialize(object u64, identifier u64, url u64, type_id u64, options u64) u64 {
	if options != 0 { panic('iOS: notification attachment options are not implemented') }
	C.ios_objc_initialize_lock()
	mut header := un_attachment_storage(object, false)
	if header.un_attachment_initialized || header.un_attachment_initializing || header.fields[0] != 0 || header.fields[1] != 0 || header.fields[2] != 0 { panic('iOS: attachment is already initialized or its constructor changed storage') }
	un_attachment_url(url)
	// Snapshot both inputs before running any application string constructor.
	a := if identifier == 0 { un_attachment_identifier() } else { un_request_text(identifier).clone() }
	b := if type_id == 0 { 'public.item'.clone() } else { un_request_text(type_id).clone() }
	header.un_attachment_initializing = true; objc_retain(object); objc_retain(url)
	C.ios_objc_initialize_unlock()
	defer { unsafe { a.free(); b.free() }; objc_release(url); objc_release(object) }
	name := owned_string(a); defer { objc_release(name) }
	if name == 0 { return un_attachment_failed_init(object) }
	kind := owned_string(b); defer { objc_release(kind) }
	if kind == 0 { return un_attachment_failed_init(object) }
	C.ios_objc_initialize_lock()
	header = un_attachment_storage(object, false)
	if !header.un_attachment_initializing || header.un_attachment_initialized || header.fields[0] != 0 || header.fields[1] != 0 || header.fields[2] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: attachment string constructor changed destination storage') }
	un_request_text(name); un_request_text(kind); un_attachment_url(url)
	header.fields[0] = objc_retain(name); header.fields[1] = objc_retain(url); header.fields[2] = objc_retain(kind)
	unsafe { *(&u64(object + 32)) = name; *(&u64(object + 40)) = url; *(&u64(object + 48)) = kind }
	header.un_attachment_initialized = true; header.un_attachment_initializing = false
	C.ios_objc_initialize_unlock()
	return object
}
fn un_attachment_copy(object u64) u64 {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	un_attachment_storage(object, true)
	return objc_retain(object)
}
fn un_attachment_retire(header &ObjHeader) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if header.un_attachment_initializing { panic('iOS: destroying an active notification attachment') }
}
fn un_attachment_dispose(object u64, mut header ObjHeader) {
	if !header.un_attachment_owned { return }
	unsafe { C.memset(voidptr(object + 8), 0, 56) }; header.un_attachment_initialized = false
	// Generic field destruction releases all three references, even after isa changes.
}
fn un_attachment_types(name string, meta bool, selector string) ?string {
	if name != 'UNNotificationAttachment' || meta { return none }
	return match selector {
		'initWithIdentifier:URL:type:options:' { '@48@0:8@16@24@32@40' }
		'init', 'copy', 'identifier', 'URL', 'type', 'options', 'userInfo' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		else { none }
	}
}
fn un_attachment_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'supportsSecureCoding', 'initWithCoder:', 'encodeWithCoder:', 'classForCoder', 'isEqual:', 'hash', 'description', 'debugDescription', 'family',
		'attachmentWithIdentifier:URL:options:error:', 'attachmentWithIdentifier:URL:options:userInfo:error:', 'initWithIdentifier:URL:type:options:userInfo:', 'initWithIdentifier:family:URL:type:options:',
		'enterSecurityScope', 'leaveSecurityScope', 'removeSecurityScope', 'addSecurityScope:', '_encodableURL', '_withSecurityScopeLock:']!
}
fn un_attachment_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := un_attachment_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.un_attachment_owned }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if un_attachment_unsupported(selector) { panic('iOS: notification attachment option is not implemented') }
	if un_attachment_types('UNNotificationAttachment', meta, selector) == none { return false }
	match selector {
		'init' { panic('iOS: notification attachment requires designated construction') }
		'initWithIdentifier:URL:type:options:' { frame.x[0] = un_attachment_initialize(object, frame.x[2], frame.x[3], frame.x[4], frame.x[5]) }
		'copy', 'copyWithZone:' {
			if selector == 'copyWithZone:' && frame.x[2] != 0 { panic('iOS: attachment copy zones are not implemented') }
			frame.x[0] = un_attachment_copy(object)
		}
		else {
			C.ios_objc_initialize_lock()
			header := un_attachment_storage(object, true)
			frame.x[0] = match selector { 'identifier' { header.fields[0] } 'URL' { header.fields[1] } 'type' { header.fields[2] } else { u64(0) } }
			C.ios_objc_initialize_unlock()
		}
	}
	return true
}
