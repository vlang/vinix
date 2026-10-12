// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public configuration and missing-presentation behavior measured against the
// installed AuthenticationServices. The private 136-byte record stays opaque;
// this adapter cannot open an authentication browser or produce a login token.
struct WebAuthState {
mut:
	url u64
	scheme u64
	handler u64
	provider u64 // Zeroing weak; getter pins through the caller's pool.
	ephemeral bool
	completed bool
	checking bool
}
type WebAuthAnchor = fn (u64, &char, u64) u64
type WebAuthCompletion = fn (u64, u64, u64)

fn web_auth_name(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'ASWebAuthenticationSession' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic authentication superclass chain')
}

fn web_auth_types(name string, meta bool, selector string) ?string {
	if name != 'ASWebAuthenticationSession' || meta { return none }
	return match selector {
		'initWithURL:callbackURLScheme:completionHandler:' { '@40@0:8@16@24@?32' }
		'presentationContextProvider' { '@16@0:8' }
		'setPresentationContextProvider:' { 'v24@0:8@16' }
		'prefersEphemeralWebBrowserSession', 'canStart', 'start' { 'B16@0:8' }
		'setPrefersEphemeralWebBrowserSession:' { 'v20@0:8B16' }
		'cancel' { 'v16@0:8' }
		else { return none }
	}
}

fn web_auth_selector(object u64, selector string) bool {
	return object !in ios_runtime.classes && web_auth_name(read64(object)) && web_auth_types('ASWebAuthenticationSession', false, selector) != none
}

fn web_auth_initialize(object u64, url u64, scheme u64, handler u64) {
	mut header := obj_header(object)
	if !header.auth_owned || header.auth != unsafe { nil } { panic('iOS: authentication session reinitialization is not implemented') }
	if url != 0 && !objc_is_kind(url, ios_runtime.names['NSURL']) { panic('iOS: authentication URL requires NSURL') }
	if scheme != 0 && (!objc_is_kind(scheme, ios_runtime.names['NSString']) || string_text(scheme).len > 4096) { panic('iOS: authentication callback scheme requires a string through 4096 bytes') }
	if handler != 0 && !is_block(handler) { panic('iOS: authentication completion requires a block') }
	header.auth = unsafe { &WebAuthState(C.calloc(1, sizeof(WebAuthState))) }
	if header.auth == unsafe { nil } { panic('iOS: cannot allocate authentication state') }
	header.auth.url = objc_retain(url)
	header.auth.scheme = if scheme == 0 { u64(0) } else { owned_string(string_text(scheme)) }
	header.auth.handler = block_copy(handler)
}

fn web_auth_dispose(mut header ObjHeader) {
	state := header.auth
	if state == unsafe { nil } { return }
	if state.checking { panic('iOS: authentication storage destruction during a callback is not implemented') }
	objc_destroy_weak(unsafe { &state.provider })
	objc_release(state.url)
	objc_release(state.scheme)
	block_release(state.handler)
	C.free(state)
	header.auth = unsafe { nil }
}

fn web_auth_missing_anchor(object u64, mut state WebAuthState) {
	provider := objc_load_weak(unsafe { &state.provider })
	if provider == 0 { return }
	defer { objc_release(provider) }
	imp := native_method(read64(provider), 'presentationAnchorForWebAuthenticationSession:')
	if imp == 0 { panic('iOS: authentication provider has no presentation anchor implementation') }
	anchor := unsafe { WebAuthAnchor(voidptr(imp))(provider, c'presentationAnchorForWebAuthenticationSession:', object) }
	if anchor != 0 { panic('iOS: authentication browser presentation is not implemented') }
}

fn web_auth_check(object u64, start bool) bool {
	if u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: authentication presentation requires the runtime main thread') }
	objc_retain(object)
	defer { objc_release(object) }
	mut state := obj_header(object).auth
	if state == unsafe { nil } { panic('iOS: authentication session is not initialized') }
	if state.completed { return false }
	if state.checking { panic('iOS: recursive authentication presentation check is not implemented') }
	state.checking = true
	defer { state.checking = false }
	web_auth_missing_anchor(object, mut state)
	if start {
		// Publish completion before invoking user code. Reentrant start/cancel
		// cannot deliver twice, and receiver/block pins permit an owning release.
		state.completed = true
		handler := block_retain(state.handler)
		defer { block_release(handler) }
		if handler != 0 {
			domain := owned_string('com.apple.AuthenticationServices.WebAuthenticationSession')
			error_object := ns_error_create(domain, 2, 0)
			objc_release(domain)
			unsafe { WebAuthCompletion(voidptr(read64(handler + 16)))(handler, 0, error_object) }
			objc_release(error_object)
		}
	}
	return false
}

fn web_auth_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !web_auth_name(if meta { object } else { read64(object) }) { return false }
	if selector in ['init', 'new', 'initWithURL:callback:completionHandler:', 'additionalHeaderFields', 'setAdditionalHeaderFields:', 'copy', 'copyWithZone:'] { panic('iOS: authentication selector is outside the measured session profile') }
	if web_auth_types('ASWebAuthenticationSession', meta, selector) == none { return false }
	if selector == 'initWithURL:callbackURLScheme:completionHandler:' { web_auth_initialize(object, frame.x[2], frame.x[3], frame.x[4]); return true }
	mut state := obj_header(object).auth
	if state == unsafe { nil } { panic('iOS: authentication session is not initialized') }
	if selector in ['start', 'canStart'] { frame.x[0] = u64(web_auth_check(object, selector == 'start')); return true }
	match selector {
		'presentationContextProvider' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &state.provider })) }
		'setPresentationContextProvider:' { objc_store_weak(unsafe { &state.provider }, frame.x[2]) }
		'prefersEphemeralWebBrowserSession' { frame.x[0] = u64(state.ephemeral) }
		'setPrefersEphemeralWebBrowserSession:' { state.ephemeral = u8(frame.x[2]) != 0 }
		'cancel' {} // Measured inactive cancellation leaves the handler configured.
		else { return false }
	}
	return true
}
