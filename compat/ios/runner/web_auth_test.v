// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework AuthenticationServices
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
type AuthSend = fn (u64, u64, u64, u64, u64) u64
struct AuthApi { native bool send u64 cls u64 strings u64 urls u64 root u64 }
fn (api AuthApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { AuthSend(voidptr(api.send))(object, selector, a, b, c) }
}
fn (api AuthApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api AuthApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0, 0) }
fn (api AuthApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api AuthApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
struct AuthCapture {
mut:
	api AuthApi
	copied int
	disposed int
	called int
	owner u64
	release_owner bool
}
struct AuthDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct AuthLiteral { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
fn auth_test_copy(dst u64, src u64) { mut cap := unsafe { &AuthCapture(read64(src + 32)) }; cap.copied++; unsafe { *(&u64(dst + 32)) = u64(cap) } }
fn auth_test_dispose(block u64) { mut cap := unsafe { &AuthCapture(read64(block + 32)) }; cap.disposed++ }
fn auth_test_completion(block u64, url u64, error_object u64) {
	mut cap := unsafe { &AuthCapture(read64(block + 32)) }; api := cap.api
	assert url == 0 && error_object != 0
	assert api.message(error_object, c'code', 0, 0, 0) == 2
	assert ctext(api.message(api.message(error_object, c'domain', 0, 0, 0), c'UTF8String', 0, 0, 0)) == 'com.apple.AuthenticationServices.WebAuthenticationSession'
	cap.called++
	if cap.release_owner {
		cap.release_owner = false
		// Apple's missing-anchor completion recurses when it starts again.
		// Check Vinix's guard separately, with the native trial retained.
		if !api.native {
			assert api.message(cap.owner, c'start', 0, 0, 0) == 0
			api.message(cap.owner, c'cancel', 0, 0, 0)
		}
		api.release(cap.owner); cap.owner = 0
	}
}
__global auth_provider_queries = int(0)
__global auth_provider_anchor = u64(0)
__global auth_provider_reentry = u64(0)
fn auth_test_anchor(provider u64, selector &char, session u64) u64 {
	_ = provider; _ = selector; _ = session; auth_provider_queries++
	if auth_provider_reentry != 0 { web_auth_check(auth_provider_reentry, false) }
	return auth_provider_anchor
}
fn auth_test_provider_class(api AuthApi) u64 {
	$if macos { if api.native {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixAuthProviderFixture', 0); assert cls != unsafe { nil }
		assert C.class_addMethod(cls, C.sel_registerName(c'presentationAnchorForWebAuthenticationSession:'), unsafe { voidptr(auth_test_anchor) }, c'@24@0:8@16')
		C.objc_registerClassPair(cls); return u64(cls)
	} }
	cls := objc_allocate_class(api.root, c'VinixAuthProviderFixture', 0)
	assert objc_add_method(cls, u64(c'presentationAnchorForWebAuthenticationSession:'), u64(unsafe { voidptr(auth_test_anchor) }), c'@24@0:8@16')
	objc_register_class(cls); return cls
}
fn auth_cases(api AuthApi) {
	pool := api.pool(); provider_class := auth_test_provider_class(api)
	url := api.message(api.urls, c'URLWithString:', api.string(c'https://example.invalid/login'), 0, 0)
	scheme := api.string(c'fortnite')
	descriptor := AuthDescriptor{0, sizeof(AuthLiteral), u64(unsafe { voidptr(auth_test_copy) }), u64(unsafe { voidptr(auth_test_dispose) })}
	mut isa := block_isa(0)
	$if macos { if api.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	for scenario in 0 .. 5 {
		mut cap := AuthCapture{api: api}
		literal := AuthLiteral{isa, u32(1) << 25, 0, u64(unsafe { voidptr(auth_test_completion) }), u64(unsafe { &descriptor }), u64(unsafe { &cap })}
		object := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithURL:callbackURLScheme:completionHandler:', url, scheme, u64(unsafe { &literal }))
		cap.owner = object
		assert object != 0 && cap.copied == 1 && cap.disposed == 0 && cap.called == 0
		assert api.message(object, c'prefersEphemeralWebBrowserSession', 0, 0, 0) == 0 && api.message(object, c'presentationContextProvider', 0, 0, 0) == 0
		api.message(object, c'setPrefersEphemeralWebBrowserSession:', 1, 0, 0); assert api.message(object, c'prefersEphemeralWebBrowserSession', 0, 0, 0) == 1
		if scenario == 0 { api.message(object, c'cancel', 0, 0, 0); api.message(object, c'cancel', 0, 0, 0); assert cap.called == 0 }
		if scenario == 2 {
			provider := api.message(provider_class, c'new', 0, 0, 0)
			api.message(object, c'setPresentationContextProvider:', provider, 0, 0)
			inner := api.pool(); assert api.message(object, c'presentationContextProvider', 0, 0, 0) == provider; api.drain(inner)
			auth_provider_queries = 0; assert api.message(object, c'canStart', 0, 0, 0) == 0 && auth_provider_queries == 1 && cap.called == 0
			assert api.message(object, c'start', 0, 0, 0) == 0 && auth_provider_queries == 2 && cap.called == 1
			api.release(provider); assert api.message(object, c'presentationContextProvider', 0, 0, 0) == 0
		} else {
			assert api.message(object, c'canStart', 0, 0, 0) == 0 && cap.called == 0
			if scenario != 0 {
				cap.release_owner = scenario == 4
				if scenario == 3 { api.message(object, c'cancel', 0, 0, 0) }
				assert api.message(object, c'start', 0, 0, 0) == 0 && cap.called == 1
			}
		}
		if cap.owner != 0 { assert api.message(object, c'start', 0, 0, 0) == 0; assert cap.called == 1; api.release(object) }
		assert cap.disposed == 1
	}
	for flags in 0 .. 4 {
		object := api.message(api.message(api.cls, c'alloc', 0, 0, 0), c'initWithURL:callbackURLScheme:completionHandler:', if flags & 1 == 0 { url } else { u64(0) }, if flags & 2 == 0 { scheme } else { u64(0) }, 0)
		assert object != 0; api.release(object)
	}
	api.drain(pool)
}
fn auth_runtime_api() AuthApi { return AuthApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), cls: ios_runtime.names['ASWebAuthenticationSession'], strings: ios_runtime.names['NSString'], urls: ios_runtime.names['NSURL'], root: ios_runtime.names['NSObject']} }
fn test_auth_native_reference() {
	$if macos {
		objc_start()
		api := AuthApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), cls: u64(C.objc_getClass(c'ASWebAuthenticationSession')), strings: u64(C.objc_getClass(c'NSString')), urls: u64(C.objc_getClass(c'NSURL')), root: u64(C.objc_getClass(c'NSObject'))}
		auth_cases(api); assert ios_runtime.live == 0; objc_stop()
		println('IOS-AUTH-NATIVE: block promotion/retirement, nullable configuration, weak providers, ephemeral flag, nil-anchor checks, synchronous error2, inactive cancel, repeat suppression and reentrant owning release passed')
	}
}
fn test_auth_runtime_lifetimes() {
	for _ in 0 .. 2 {
		objc_start(); api := auth_runtime_api(); auth_cases(api)
		assert objc_class_size(api.cls) == 136 && objc_class_parent(api.cls) == api.root
		assert ctext(u64(objc_method_types(objc_instance_method(api.cls, u64(c'initWithURL:callbackURLScheme:completionHandler:'))))) == '@40@0:8@16@24@?32'
		assert runtime_symbol('/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices', '_OBJC_CLASS_$_ASWebAuthenticationSession') or { panic(err) } == api.cls
		// The session must outlive the constructor's autorelease pool and keep
		// an independent callback-scheme copy even if the source text changes.
		ownership_pool := api.pool()
		owned_url := api.message(api.urls, c'URLWithString:', api.string(c'https://example.invalid/login'), 0, 0)
		owned_scheme := objc_autorelease(owned_string('fortnite'))
		owned_session := api.message(objc_allocate(api.cls), c'initWithURL:callbackURLScheme:completionHandler:', owned_url, owned_scheme, 0)
		unsafe { obj_header(owned_scheme).text[0] = char(`X`) }
		api.drain(ownership_pool)
		assert obj_header(owned_session).auth.url == owned_url && owned_url in ios_runtime.objects
		assert string_text(obj_header(owned_session).auth.scheme) == 'fortnite'
		objc_release(owned_session); assert ios_runtime.live == 0
		for _ in 0 .. 100 {
			pool := api.pool(); url := api.message(api.urls, c'URLWithString:', api.string(c'https://example.invalid/login'), 0, 0)
			object := api.message(objc_allocate(api.cls), c'initWithURL:callbackURLScheme:completionHandler:', url, api.string(c'fortnite'), 0)
			provider := objc_new(api.root); api.message(object, c'setPresentationContextProvider:', provider, 0, 0); objc_release(provider)
			assert obj_header(object).auth.provider == 0
			objc_set_class(object, api.root); objc_release(object); api.drain(pool); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 136)); assert objc_construct_instance(api.cls, storage) == storage
		api.message(storage, c'initWithURL:callbackURLScheme:completionHandler:', 0, 0, 0)
		assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) })
		assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0; objc_stop()
	}
	println('IOS-AUTH: shared native cases, measured metadata, callback pins, retained URL/copied scheme, weak provider cleanup, 100 isa-change releases, caller storage and two clean cycles passed')
}
fn test_auth_rejections() {
	objc_start(); api := auth_runtime_api(); cls := auth_test_provider_class(api)
	for mode in ['new', 'url-type', 'scheme-type', 'handler-type', 'uninitialized', 'reinitialize', 'browser', 'missing-method', 'reentry', 'headers', 'modern-callback']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			object := objc_allocate(api.cls)
			if mode == 'new' { objc_new(api.cls) }
			if mode == 'uninitialized' { api.message(object, c'start', 0, 0, 0) }
			if mode == 'url-type' { api.message(object, c'initWithURL:callbackURLScheme:completionHandler:', api.string(c'wrong'), 0, 0) }
			if mode == 'scheme-type' { api.message(object, c'initWithURL:callbackURLScheme:completionHandler:', 0, objc_new(api.root), 0) }
			if mode == 'handler-type' { api.message(object, c'initWithURL:callbackURLScheme:completionHandler:', 0, 0, objc_new(api.root)) }
			api.message(object, c'initWithURL:callbackURLScheme:completionHandler:', 0, 0, 0)
			match mode {
				'reinitialize' { api.message(object, c'initWithURL:callbackURLScheme:completionHandler:', 0, 0, 0) }
				'headers' { api.message(object, c'setAdditionalHeaderFields:', 0, 0, 0) }
				'modern-callback' { api.message(object, c'initWithURL:callback:completionHandler:', 0, 0, 0) }
				else {
					provider := objc_new(if mode == 'missing-method' { api.root } else { cls }); api.message(object, c'setPresentationContextProvider:', provider, 0, 0)
					if mode == 'browser' { auth_provider_anchor = objc_new(ios_runtime.names['UIWindow']) }
					if mode == 'reentry' { auth_provider_reentry = object }
					api.message(object, c'start', 0, 0, 0)
				}
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'new' { 'authentication session requires designated construction' }
			'url-type' { 'authentication URL requires NSURL' }
			'scheme-type' { 'authentication callback scheme requires a string' }
			'handler-type' { 'authentication completion requires a block' }
			'uninitialized' { 'authentication session is not initialized' }
			'reinitialize' { 'authentication session reinitialization is not implemented' }
			'browser' { 'authentication browser presentation is not implemented' }
			'missing-method' { 'authentication provider has no presentation anchor implementation' }
			'reentry' { 'recursive authentication presentation check is not implemented' }
			else { 'authentication selector is outside the measured session profile' }
		}
		assert output.contains('iOS: ' + reason), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-AUTH-REJECT: designated init, input types, uninitialized/repeated init, unsupported browser, missing/recursive provider, headers and modern callbacks fail explicitly')
}
