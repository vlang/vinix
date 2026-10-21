// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_content_client(e voidptr, value voidptr, uri bool) voidptr {
	unsafe {
		if value == unsafe { nil } {
			throw(e, c'java/lang/NullPointerException', c'Content provider authority')
			return unsafe { nil }
		}
		args := &Value(C.alloca(sizeof(Value)))
		mut authority := value
		if uri {
			scheme := obj(e, value, c'android/net/Uri', c'getScheme', c'()Ljava/lang/String;', unsafe { nil })
			args[0] = Value{ l: ws_string(e, c'content') }
			if scheme == nil || boolean(e, scheme, c'java/lang/String', c'equals', c'(Ljava/lang/Object;)Z', args) == 0 {
				return nil
			}
			authority = obj(e, value, c'android/net/Uri', c'getAuthority', c'()Ljava/lang/String;', unsafe { nil })
		}
		args[0] = Value{ l: authority }
		provider := static_obj(e, c'android/content/ContentProvider', c'atl_get_content_provider', c'(Ljava/lang/String;)Landroid/content/ContentProvider;', args)
		if provider == unsafe { nil } || pending(e) { return unsafe { nil } }
		args[0] = Value{ l: provider }
		return new_object(e, c'android/content/ContentProviderClient', c'(Landroid/content/ContentProvider;)V', args)
	}
}

fn ws_client_provider(e voidptr, client voidptr) voidptr {
	if get_int(e, client, c'android/content/ContentProviderClient', c'vinixClosed') != 0 {
		throw(e, c'java/lang/IllegalStateException', c'ContentProviderClient is closed')
		return unsafe { nil }
	}
	return get_object(e, client, c'android/content/ContentProviderClient', c'vinixProvider', c'Landroid/content/ContentProvider;')
}

fn ws_client_release(e voidptr, client voidptr) u8 {
	unsafe {
		if Monitor(slot(e, 217))(e, client) != 0 { return 0 }
		defer { Monitor(slot(e, 218))(e, client) }
		if get_int(e, client, c'android/content/ContentProviderClient', c'vinixClosed') != 0 {
			return 0
		}
		put_int(e, client, c'android/content/ContentProviderClient', c'vinixClosed', 1)
		put_object(e, client, c'android/content/ContentProviderClient', c'vinixProvider', c'Landroid/content/ContentProvider;', nil)
		return 1
	}
}

fn ws_client_type(e voidptr, client voidptr, uri voidptr) voidptr {
	provider := ws_client_provider(e, client)
	if provider == unsafe { nil } { return unsafe { nil } }
	unsafe {
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{ l: uri }
		return obj(e, provider, c'android/content/ContentProvider', c'getType', c'(Landroid/net/Uri;)Ljava/lang/String;', args)
	}
}

fn ws_client_call(e voidptr, client voidptr, name voidptr, arg voidptr, extras voidptr) voidptr {
	provider := ws_client_provider(e, client)
	if provider == unsafe { nil } { return unsafe { nil } }
	unsafe {
		args := &Value(C.alloca(3 * sizeof(Value)))
		args[0] = Value{ l: name }
		args[1] = Value{ l: arg }
		args[2] = Value{ l: extras }
		return obj(e, provider, c'android/content/ContentProvider', c'call', c'(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;', args)
	}
}
