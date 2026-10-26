// SPDX-License-Identifier: GPL-2.0-or-later
// JNI adapter to the authenticated account broker.
@[translated]
module atlframework

type WsAccountBuild = fn (u64, u16, &char, &char) voidptr
type WsAccountTokenBuild = fn (u64, &char, &char, &char) voidptr
type WsAccountFeature = fn (voidptr, &char) i32
type WsAccountOption = fn (voidptr, &char, u16, &char, i64) i32
type WsAccountFree = fn (voidptr)
type WsAccountSubmit = fn (voidptr, &char) voidptr
type WsAccountRead = fn (voidptr, &u16, &u64, i32) i32
type WsAccountCount = fn (voidptr) u32
type WsAccountText = fn (voidptr, u32) &char
type WsAccountTag = fn (voidptr, u32) u16
type WsAccountNumber = fn (voidptr, u32) i64
type WsAccountInteraction = fn (voidptr, &u8, u32) i32
type WsAccountRedeem = fn (u64, u64, &u8, u32, &char) voidptr
struct WsAccountItem {
mut:
	key &char
	text &char
	tag u16
	number i64
}
struct WsAccountRequest {
mut:
	next &WsAccountRequest
	handle voidptr
	future voidptr
	activity voidptr
	endpoint &char
	redemption voidptr
	redemption_id u64
	interacted bool
	error_code i32
	id u64
	started i64
	kind u16
	count u32
	items [32]WsAccountItem
}
__global ws_account_library voidptr
__global ws_account_build WsAccountBuild
__global ws_account_token_build WsAccountTokenBuild
__global ws_account_feature WsAccountFeature
__global ws_account_option WsAccountOption
__global ws_account_free WsAccountFree
__global ws_account_submit WsAccountSubmit
__global ws_account_read WsAccountRead
__global ws_account_count WsAccountCount
__global ws_account_key WsAccountText
__global ws_account_tag WsAccountTag
__global ws_account_text WsAccountText
__global ws_account_number WsAccountNumber
__global ws_account_close WsAccountFree
__global ws_account_interaction WsAccountInteraction
__global ws_account_redeem WsAccountRedeem
__global ws_account_mutex C.pthread_mutex_t
__global ws_account_initialized bool
__global ws_account_requests &WsAccountRequest
__global ws_account_sequence u64
__global ws_account_active u32
__global ws_account_closing bool

// Bootstrap precedes APK execution. Missing transport retains the existing
// unavailable future behavior; it never supplies invented account results.
fn ws_account_client_init() bool {
	unsafe {
		if ws_account_initialized { return true }
		if C.pthread_mutex_init(&ws_account_mutex, nil) != 0 { return false }
		ws_account_initialized = true
		ws_account_library = C.dlopen(c'libvinix-android-account.so', 2)
		if ws_account_library == nil { return true }
		ws_account_build = WsAccountBuild(C.dlsym(ws_account_library, c'vinix_android_account_request'))
		ws_account_token_build = WsAccountTokenBuild(C.dlsym(ws_account_library, c'vinix_android_account_token_request'))
		ws_account_feature = WsAccountFeature(C.dlsym(ws_account_library, c'vinix_android_account_feature'))
		ws_account_option = WsAccountOption(C.dlsym(ws_account_library, c'vinix_android_account_option'))
		ws_account_free = WsAccountFree(C.dlsym(ws_account_library, c'vinix_android_account_request_free'))
		ws_account_submit = WsAccountSubmit(C.dlsym(ws_account_library, c'vinix_android_account_submit'))
		ws_account_read = WsAccountRead(C.dlsym(ws_account_library, c'vinix_android_account_read'))
		ws_account_count = WsAccountCount(C.dlsym(ws_account_library, c'vinix_android_account_count'))
		ws_account_key = WsAccountText(C.dlsym(ws_account_library, c'vinix_android_account_key'))
		ws_account_tag = WsAccountTag(C.dlsym(ws_account_library, c'vinix_android_account_tag'))
		ws_account_text = WsAccountText(C.dlsym(ws_account_library, c'vinix_android_account_text'))
		ws_account_number = WsAccountNumber(C.dlsym(ws_account_library, c'vinix_android_account_number'))
		ws_account_close = WsAccountFree(C.dlsym(ws_account_library, c'vinix_android_account_close'))
		ws_account_interaction = WsAccountInteraction(C.dlsym(ws_account_library, c'vinix_android_account_interaction'))
		ws_account_redeem = WsAccountRedeem(C.dlsym(ws_account_library, c'vinix_android_account_redeem'))
		if voidptr(ws_account_build) == nil || voidptr(ws_account_feature) == nil || voidptr(ws_account_option) == nil
			|| voidptr(ws_account_free) == nil || voidptr(ws_account_submit) == nil || voidptr(ws_account_read) == nil
			|| voidptr(ws_account_count) == nil || voidptr(ws_account_key) == nil || voidptr(ws_account_tag) == nil
			|| voidptr(ws_account_text) == nil || voidptr(ws_account_number) == nil || voidptr(ws_account_close) == nil {
			C.dlclose(ws_account_library); ws_account_library = nil
		}
		return true
	}
}

fn ws_account_is(e voidptr, value voidptr, name &char) bool {
	unsafe {
		if pending(e) { return false }
		c := cls(e, name)
		if c == nil { return false }
		result := Same(slot(e, 32))(e, value, c) != 0
		Drop(slot(e, 23))(e, c)
		return result
	}
}

// Copy before iteration. Parcelable/Binder values require separate broker
// capabilities; never stringify an arbitrary caller object or log its contents.
fn ws_account_options(e voidptr, builder voidptr, original voidptr) bool {
	return ws_account_copy_options(e, builder, original, ws_account_option)
}

fn ws_account_copy_options(e voidptr, builder voidptr, original voidptr, put WsAccountOption) bool {
	unsafe {
		if original == nil { return true }
		copy_args := [Value{ l: original }]!
		bundle := new_object(e, c'android/os/Bundle', c'(Landroid/os/Bundle;)V', &copy_args[0])
		if pending(e) || bundle == nil { return false }
		defer { Drop(slot(e, 23))(e, bundle) }
		keys := obj(e, bundle, c'android/os/Bundle', c'keySet', c'()Ljava/util/Set;', nil)
		iter := obj(e, keys, c'java/util/Set', c'iterator', c'()Ljava/util/Iterator;', nil)
		mut count := u32(0)
		for !pending(e) && boolean(e, iter, c'java/util/Iterator', c'hasNext', c'()Z', nil) != 0 {
			count++
			if count > 32 { return false }
			key := obj(e, iter, c'java/util/Iterator', c'next', c'()Ljava/lang/Object;', nil)
			if !ws_account_is(e, key, c'java/lang/String') { return false }
			key_text := ws_account_utf8(e, key)
			if key_text == nil { return false }
			args := [Value{ l: key }]!
			value := obj(e, bundle, c'android/os/Bundle', c'get', c'(Ljava/lang/String;)Ljava/lang/Object;', &args[0])
			mut tag := u16(0)
			mut number := i64(0)
			mut text := &char(nil)
			mut valid := !pending(e)
			if value != nil && valid {
				if ws_account_is(e, value, c'java/lang/String') { tag = 1; text = ws_account_utf8(e, value); valid = text != nil }
				else if ws_account_is(e, value, c'java/lang/Boolean') { tag = 2; number = i64(boolean(e, value, c'java/lang/Boolean', c'booleanValue', c'()Z', nil)) }
				else if ws_account_is(e, value, c'java/lang/Integer') { tag = 3; number = i64(integer(e, value, c'java/lang/Integer', c'intValue', c'()I', nil)) }
				else if ws_account_is(e, value, c'java/lang/Long') {
					tag = 4
					m := method(e, c'java/lang/Long', c'longValue', c'()J')
					if m == nil { valid = false } else { number = WsLongCall(slot(e, 54))(e, value, m, nil) }
				} else { valid = false }
			}
			if valid && !pending(e) { valid = put(builder, key_text, tag, text, number) == 0 }
			C.free(text); C.free(key_text)
			Drop(slot(e, 23))(e, key)
			if value != nil { Drop(slot(e, 23))(e, value) }
			if !valid { return false }
		}
		return !pending(e)
	}
}

fn ws_account_start(e voidptr, manager voidptr, account_type voidptr, token_type voidptr, features voidptr, options voidptr, activity voidptr, future voidptr) u8 {
	unsafe {
		if !ws_account_initialized || ws_account_library == nil || future == nil { return 0 }
		kind := ws_account_utf8(e, account_type)
		token := ws_account_utf8(e, token_type)
		defer { C.free(kind); C.free(token) }
		if kind == nil || (token_type != nil && token == nil) || pending(e) { return 0 }
		C.pthread_mutex_lock(&ws_account_mutex)
		if ws_account_closing || ws_account_active >= 32 || ws_account_sequence == ~u64(0) { C.pthread_mutex_unlock(&ws_account_mutex); return 0 }
		ws_account_sequence++
		id := ws_account_sequence
		C.pthread_mutex_unlock(&ws_account_mutex)
		builder := ws_account_build(id, 2, kind, token)
		if builder == nil { return 0 }
		defer { ws_account_free(builder) }
		n := ws_array_len(e, features)
		if n > 32 { return 0 }
		for i := i32(0); i < n; i++ {
			feature := WsArrayGet(slot(e, 173))(e, features, i)
			text := ws_account_utf8(e, feature)
			valid := text != nil && ws_account_feature(builder, text) == 0
			C.free(text)
			if feature != nil { Drop(slot(e, 23))(e, feature) }
			if !valid || pending(e) { return 0 }
		}
		return ws_account_queue(e, id, builder, options, activity, future)
	}
}

// Token requests share the existing future/cancellation/opaque interaction
// path. The broker-selected authenticator checks account visibility separately.
fn ws_account_token(e voidptr, manager voidptr, account voidptr, token_type voidptr, options voidptr, activity voidptr, future voidptr) u8 {
	unsafe {
		if !ws_account_initialized || ws_account_library == nil || voidptr(ws_account_token_build) == nil
			|| account == nil || token_type == nil || future == nil { return 0 }
		name_value := get_object(e, account, c'android/accounts/Account', c'name', c'Ljava/lang/String;')
		kind_value := get_object(e, account, c'android/accounts/Account', c'type', c'Ljava/lang/String;')
		name := ws_account_utf8(e, name_value)
		kind := ws_account_utf8(e, kind_value)
		token := ws_account_utf8(e, token_type)
		if name_value != nil { Drop(slot(e,23))(e,name_value) }
		if kind_value != nil { Drop(slot(e,23))(e,kind_value) }
		defer { C.free(name); C.free(kind); C.free(token) }
		if name == nil || kind == nil || token == nil || pending(e) { return 0 }
		C.pthread_mutex_lock(&ws_account_mutex)
		if ws_account_closing || ws_account_active >= 32 || ws_account_sequence == ~u64(0) { C.pthread_mutex_unlock(&ws_account_mutex); return 0 }
		ws_account_sequence++
		id := ws_account_sequence
		C.pthread_mutex_unlock(&ws_account_mutex)
		builder := ws_account_token_build(id, name, kind, token)
		if builder == nil { return 0 }
		defer { ws_account_free(builder) }
		return ws_account_queue(e, id, builder, options, activity, future)
	}
}

fn ws_account_queue(e voidptr, id u64, builder voidptr, options voidptr, activity voidptr, future voidptr) u8 {
	unsafe {
		if !ws_account_options(e, builder, options) || pending(e) { return 0 }
		node := &WsAccountRequest(C.calloc(1, sizeof(WsAccountRequest)))
		if node == nil { return 0 }
		node.id = id; node.started = ws_millis()
		node.future = WsRef(slot(e, 21))(e, future)
		if node.future == nil { C.free(node); return 0 }
		if activity != nil {
			node.activity = WsRef(slot(e, 21))(e, activity)
			if node.activity == nil { ws_account_dispose(e, node); return 0 }
		}
		endpoint := C.getenv(c'VINIX_ANDROID_ACCOUNT_SOCKET')
		node.endpoint = C.strdup(if endpoint == nil { c'/run/vinix/android/accounts.sock' } else { endpoint })
		if node.endpoint == nil { ws_account_dispose(e, node); return 0 }
		node.handle = ws_account_submit(builder, node.endpoint)
		if node.handle == nil { ws_account_dispose(e, node); return 0 }
		C.pthread_mutex_lock(&ws_account_mutex)
		if ws_account_closing || ws_account_active >= 32 {
			C.pthread_mutex_unlock(&ws_account_mutex)
			ws_account_dispose(e, node); return 0
		}
		node.next = ws_account_requests; ws_account_requests = node; ws_account_active++
		C.pthread_mutex_unlock(&ws_account_mutex)
		return 1
	}
}

fn ws_account_dispose(e voidptr, node &WsAccountRequest) {
	unsafe {
		if node.handle != nil { ws_account_close(node.handle) }
		if node.redemption != nil { ws_account_close(node.redemption) }
		if node.future != nil { Drop(slot(e, 22))(e, node.future) }
		if node.activity != nil { Drop(slot(e, 22))(e, node.activity) }
		C.free(node.endpoint)
		for i := u32(0); i < node.count; i++ { C.free(node.items[i].key); C.free(node.items[i].text) }
		C.free(node)
	}
}

// done() may run on any Java thread. Detach under the mutex, release outside.
fn ws_account_finished(e voidptr, future voidptr) {
	unsafe {
		if !ws_account_initialized { return }
		C.pthread_mutex_lock(&ws_account_mutex)
		mut link := &ws_account_requests
		for *link != nil {
			node := *link
			if Same(slot(e, 24))(e, node.future, future) != 0 {
				*link = node.next; ws_account_active--
				C.pthread_mutex_unlock(&ws_account_mutex)
				ws_account_dispose(e, node); return
			}
			link = &node.next
		}
		C.pthread_mutex_unlock(&ws_account_mutex)
	}
}

fn ws_account_client_shutdown(e voidptr) {
	unsafe {
		if !ws_account_initialized { return }
		C.pthread_mutex_lock(&ws_account_mutex)
		mut node := ws_account_requests
		ws_account_closing = true
		ws_account_requests = nil; ws_account_active = 0
		C.pthread_mutex_unlock(&ws_account_mutex)
		for node != nil { next := node.next; ws_account_dispose(e, node); node = next }
	}
}

fn ws_account_complete(e voidptr, node &WsAccountRequest) {
	unsafe {
		if node.kind == 1 {
			bundle := new_object(e, c'android/os/Bundle', c'()V', nil)
			for i := u32(0); i < node.count && !pending(e); i++ {
				item := &node.items[i]
				key := ws_account_java_text(e, item.key)
				if key == nil { node.kind = 2; break }
				mut args := [Value{ l: key }, Value{ j: item.number }]!
				if item.tag <= 1 {
					args[1] = Value{ l: ws_account_java_text(e, item.text) }
					if item.tag == 1 && args[1].l == nil { node.kind = 2; break }
					call(e, bundle, c'android/os/Bundle', c'putString', c'(Ljava/lang/String;Ljava/lang/String;)V', &args[0])
					if args[1].l != nil { Drop(slot(e, 23))(e, args[1].l) }
				} else if item.tag == 2 {
					args[1] = Value{ i: i32(item.number) }
					call(e, bundle, c'android/os/Bundle', c'putBoolean', c'(Ljava/lang/String;Z)V', &args[0])
				} else if item.tag == 3 {
					args[1] = Value{ i: i32(item.number) }
					call(e, bundle, c'android/os/Bundle', c'putInt', c'(Ljava/lang/String;I)V', &args[0])
				} else if item.tag == 4 {
					call(e, bundle, c'android/os/Bundle', c'putLong', c'(Ljava/lang/String;J)V', &args[0])
				} else { node.kind = 2 }
				Drop(slot(e, 23))(e, key)
			}
			if node.kind == 1 && !pending(e) {
				args := [Value{ l: bundle }]!
				call(e, node.future, c'android/atl/VinixAccountFuture', c'vinixResult', c'(Landroid/os/Bundle;)V', &args[0])
				return
			}
		}
		if pending(e) { return }
		mut code := if node.error_code != 0 { node.error_code } else { i32(1) }
		mut message := ws_string(e, if node.error_code == 6 { c'Account interaction requires an Activity and supported broker transport' } else { c'Account broker request failed' })
		for i := u32(0); i < node.count; i++ {
			item := &node.items[i]
			if item.key != nil && item.tag == 3 && C.strcmp(item.key, c'errorCode') == 0 { code = i32(item.number) }
			if item.key != nil && item.tag == 1 && C.strcmp(item.key, c'errorMessage') == 0 { message = ws_account_java_text(e, item.text) }
		}
		args := [Value{ i: code }, Value{ l: message }]!
		call(e, node.future, c'android/atl/VinixAccountFuture', c'vinixError', c'(ILjava/lang/String;)V', &args[0])
	}
}

// Called only under ws_account_mutex. Redeem encodes an owning copy before
// returning and never waits for the broker. The original future stays pending:
// an acknowledgement proves launch delivery, never successful account login.
fn ws_account_interact(node &WsAccountRequest) bool {
	unsafe {
		if node.activity == nil || voidptr(ws_account_interaction) == nil || voidptr(ws_account_redeem) == nil {
			node.error_code = 6
			return false
		}
		if node.interacted || node.endpoint == nil || ws_account_sequence == ~u64(0) {
			node.error_code = 7
			return false
		}
		mut ticket := [32]u8{}
		if ws_account_interaction(node.handle, &ticket[0], 32) != 0 { return false }
		ws_account_sequence++
		node.redemption_id = ws_account_sequence
		node.interacted = true
		node.redemption = ws_account_redeem(node.redemption_id, node.id, &ticket[0], 32, node.endpoint)
		C.memset(&ticket[0], 0, 32)
		return node.redemption != nil
	}
}

fn ws_account_copy_result(node &WsAccountRequest, handle voidptr) {
	unsafe {
		count := ws_account_count(handle)
		if count > 32 { node.kind = 2; return }
		for i := u32(0); i < count; i++ {
			key := ws_account_key(handle, i)
			text := ws_account_text(handle, i)
			if key == nil || C.strlen(key) > 4096 || (text != nil && C.strlen(text) > 4096) { node.kind = 2; break }
			node.items[i].key = C.strdup(key)
			node.items[i].text = if text == nil { &char(nil) } else { C.strdup(text) }
			node.items[i].tag = ws_account_tag(handle, i)
			node.items[i].number = ws_account_number(handle, i)
			node.count++
			if node.items[i].key == nil || (text != nil && node.items[i].text == nil) { node.kind = 2; break }
		}
	}
}

// Read only bounded nonblocking steps on the Looper. Copy borrowed ABI values
// before unlocking; Java completion can reenter AccountManager or cancel.
fn ws_account_client_pump(e voidptr) {
	unsafe {
		if !ws_account_initialized || ws_account_library == nil { return }
		for work := u32(0); work < 32; work++ {
			C.pthread_mutex_lock(&ws_account_mutex)
			mut link := &ws_account_requests
			mut ready := &WsAccountRequest(nil)
			mut retired := voidptr(nil)
			for *link != nil {
				node := *link
				mut kind := u16(0)
				mut id := u64(0)
				status := ws_account_read(node.handle, &kind, &id, 0)
				mut done := status < 0 || ws_millis() - node.started > 300000
				mut result := voidptr(nil)
				node.kind = 2
				if !done && status == 1 {
					if id != node.id { done = true }
					else if kind == 4 { done = !ws_account_interact(node) }
					else if kind != 5 {
						done = true
						if kind == 1 || kind == 2 { node.kind = kind; result = node.handle }
					}
				}
				if !done && node.redemption != nil {
					ack := ws_account_read(node.redemption, &kind, &id, 0)
					if ack < 0 || (ack == 1 && (id != node.redemption_id || (kind != 1 && kind != 2))) {
						done = true
					} else if ack == 1 {
						if kind == 2 { done = true; result = node.redemption }
						else if ws_account_count(node.redemption) != 0 { done = true }
						else { retired = node.redemption; node.redemption = nil }
					}
				}
				if done {
					if result != nil { ws_account_copy_result(node, result) }
					*link = node.next; ws_account_active--; ready = node; break
				}
				if retired != nil { break }
				link = &node.next
			}
			C.pthread_mutex_unlock(&ws_account_mutex)
			if retired != nil { ws_account_close(retired); continue }
			if ready == nil { return }
			push_frame(e)
			ws_account_complete(e, ready)
			ws_account_dispose(e, ready)
			pop_frame(e)
			if pending(e) { return }
		}
	}
}
