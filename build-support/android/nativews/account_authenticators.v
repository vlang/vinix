// SPDX-License-Identifier: GPL-2.0-or-later
// Authenticator descriptions come only from the authenticated broker registry.
@[translated]
module atlframework

type WsAuthenticatorsBuild = fn (u64) voidptr
type WsAuthenticatorResource = fn (voidptr,u32,u16) u32
type WsAuthenticatorCustom = fn (voidptr,u32) i32

fn ws_account_description_array(e voidptr, client voidptr, count u32, type_fn WsAccountText,
	package_fn WsAccountText, resource_fn WsAuthenticatorResource, custom_fn WsAuthenticatorCustom) voidptr {
	unsafe {
		if count > 16 { throw(e,c'java/lang/UnsupportedOperationException',c'invalid authenticator snapshot'); return nil }
		description_class := cls(e,c'android/accounts/AuthenticatorDescription')
		if description_class == nil || pending(e) {
			if description_class != nil { Drop(slot(e,23))(e,description_class) }
			if !pending(e) { throw(e,c'java/lang/UnsupportedOperationException',c'authenticator description class unavailable') }
			return nil
		}
		defer { Drop(slot(e,23))(e,description_class) }
		array := ObjectArrayNew(slot(e,172))(e,i32(count),description_class,nil)
		if array == nil || pending(e) {
			if array != nil { Drop(slot(e,23))(e,array) }
			if !pending(e) { throw(e,c'java/lang/OutOfMemoryError',c'authenticator description array') }
			return nil
		}
		args := &Value(C.alloca(7*sizeof(Value)))
		for i := u32(0); i < count; i++ {
			custom := custom_fn(client,i)
			if custom != 0 && custom != 1 {
				Drop(slot(e,23))(e,array)
				throw(e,c'java/lang/UnsupportedOperationException',c'invalid authenticator customTokens'); return nil
			}
			type_text := type_fn(client,i)
			args[0] = Value{l:if type_text != nil && type_text[0] != 0 { ws_account_java_text(e,type_text) } else { nil }}
			package_text := package_fn(client,i)
			args[1] = Value{l:if !pending(e) && package_text != nil && package_text[0] != 0 { ws_account_java_text(e,package_text) } else { nil }}
			// Android resource IDs use all 32 bits, including the signed jint bit.
			for field := u16(0); field < 4; field++ { args[2 + field] = Value{i:i32(resource_fn(client,i,field))} }
			args[6] = Value{i:custom}
			mut description := voidptr(nil)
			if args[0].l != nil && args[1].l != nil && !pending(e) {
				description = new_object(e,c'android/accounts/AuthenticatorDescription',c'(Ljava/lang/String;Ljava/lang/String;IIIIZ)V',args)
			}
			if description != nil && !pending(e) { WsArraySet(slot(e,174))(e,array,i32(i),description) }
			if args[0].l != nil { Drop(slot(e,23))(e,args[0].l) }
			if args[1].l != nil { Drop(slot(e,23))(e,args[1].l) }
			if description != nil { Drop(slot(e,23))(e,description) }
			if description == nil || pending(e) {
				Drop(slot(e,23))(e,array)
				if !pending(e) { throw(e,c'java/lang/UnsupportedOperationException',c'invalid authenticator description') }
				return nil
			}
		}
		return array
	}
}

fn ws_account_authenticator_types(e voidptr, manager voidptr) voidptr {
	unsafe {
		if pending(e) { return nil }
		if !ws_account_initialized || ws_account_library == nil {
			throw(e,c'java/lang/UnsupportedOperationException',c'account broker is unavailable'); return nil
		}
		build := WsAuthenticatorsBuild(C.dlsym(ws_account_library,c'vinix_android_account_authenticators_request'))
		count_fn := WsAccountCount(C.dlsym(ws_account_library,c'vinix_android_account_authenticator_count'))
		type_fn := WsAccountText(C.dlsym(ws_account_library,c'vinix_android_account_authenticator_type'))
		package_fn := WsAccountText(C.dlsym(ws_account_library,c'vinix_android_account_authenticator_package'))
		resource_fn := WsAuthenticatorResource(C.dlsym(ws_account_library,c'vinix_android_account_authenticator_resource'))
		custom_fn := WsAuthenticatorCustom(C.dlsym(ws_account_library,c'vinix_android_account_authenticator_custom_tokens'))
		if voidptr(build) == nil || voidptr(count_fn) == nil || voidptr(type_fn) == nil
			|| voidptr(package_fn) == nil || voidptr(resource_fn) == nil || voidptr(custom_fn) == nil {
			throw(e,c'java/lang/UnsupportedOperationException',c'authenticator query API is unavailable'); return nil
		}
		C.pthread_mutex_lock(&ws_account_mutex)
		if ws_account_closing || ws_account_sequence == ~u64(0) {
			C.pthread_mutex_unlock(&ws_account_mutex)
			throw(e,c'java/lang/UnsupportedOperationException',c'account client is closing'); return nil
		}
		ws_account_sequence++
		id := ws_account_sequence
		C.pthread_mutex_unlock(&ws_account_mutex)
		builder := build(id)
		if builder == nil { throw(e,c'java/lang/UnsupportedOperationException',c'authenticator query rejected'); return nil }
		mut endpoint := C.getenv(c'VINIX_ANDROID_ACCOUNT_SOCKET')
		if endpoint == nil { endpoint = c'/run/vinix/android/accounts.sock' }
		client := ws_account_submit(builder,endpoint)
		ws_account_free(builder)
		if client == nil { throw(e,c'java/lang/UnsupportedOperationException',c'account broker connection failed'); return nil }
		defer { ws_account_close(client) }
		deadline := ws_millis() + 5000
		for ws_millis() < deadline {
			mut response_kind := u16(0)
			mut response_id := u64(0)
			status := ws_account_read(client,&response_kind,&response_id,100)
			if status == 0 { continue }
			if status != 1 || response_id != id { break }
			if response_kind == 5 { continue }
			if response_kind == 9 {
				return ws_account_description_array(e,client,count_fn(client),type_fn,package_fn,resource_fn,custom_fn)
			}
			break
		}
		throw(e,c'java/lang/UnsupportedOperationException',c'authenticator query failed or timed out')
		return nil
	}
}
