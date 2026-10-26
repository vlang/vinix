// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsStoreOpen = fn (voidptr,&char,&char,&char) voidptr
type WsStoreClose = fn (voidptr) i32
type WsStoreInsert = fn (voidptr,&char,&char,&char) voidptr
type WsStoreTextPut = fn (voidptr,&char,&char) i32
type WsStoreVisibilityPut = fn (voidptr,&char,i32) i32
type WsStoreSnapshot = fn (voidptr,&char) voidptr
type WsStoreSize = fn (voidptr) i32
type WsStoreQuery = fn (voidptr,voidptr,u64) i32
type WsStoreRead = fn (voidptr,&char,&char) voidptr
type WsStoreData = fn (voidptr,&char,&char,&char) voidptr
type WsStoreWrite = fn (voidptr,&char,&char,&char) i32
type WsStoreWriteData = fn (voidptr,&char,&char,&char,&char) i32
type WsStoreWriteVisibility = fn (voidptr,&char,&char,&char,i32) i32

struct WsStoreIdentity {
mut:
	name &char
	kind &char
}
__global ws_store_handle voidptr
__global ws_store_open WsStoreOpen
__global ws_store_close WsStoreClose
__global ws_store_insertion WsStoreInsert
__global ws_store_userdata WsStoreTextPut
__global ws_store_map_visibility WsStoreVisibilityPut
__global ws_store_commit WsStoreClose
__global ws_store_insertion_free WsAuthFree
__global ws_store_snapshot WsStoreSnapshot
__global ws_store_snapshot_count WsStoreSize
__global ws_store_snapshot_name WsAuthText
__global ws_store_snapshot_type WsAuthText
__global ws_store_snapshot_free WsAuthFree
__global ws_store_query WsStoreQuery
__global ws_store_password WsStoreRead
__global ws_store_data WsStoreData
__global ws_store_cell_text WsAuthString
__global ws_store_cell_free WsAuthFree
__global ws_store_password_put WsStoreWrite
__global ws_store_data_put WsStoreWriteData
__global ws_store_visibility_put WsStoreWriteVisibility

// Consume before APK execution, even when no service channel is present.
fn ws_store_take_type() &char {
	unsafe {
		value := C.getenv(c'VINIX_ANDROID_AUTHENTICATOR_TYPE')
		mut result := &char(nil)
		if value != nil { result = C.strdup(value) }
		C.unsetenv(c'VINIX_ANDROID_AUTHENTICATOR_TYPE')
		return result
	}
}

fn ws_store_init(account_type &char) bool {
	unsafe {
		if account_type == nil { return true }
		if !ws.service || ws_auth_handle == nil || ws_auth_origin == nil || ws.data == nil { return false }
		ws_store_open = WsStoreOpen(C.dlsym(ws_auth_library,c'vinix_android_account_store_open'))
		ws_store_close = WsStoreClose(C.dlsym(ws_auth_library,c'vinix_android_account_store_close'))
		ws_store_insertion = WsStoreInsert(C.dlsym(ws_auth_library,c'vinix_android_account_store_insertion'))
		ws_store_userdata = WsStoreTextPut(C.dlsym(ws_auth_library,c'vinix_android_account_store_userdata'))
		ws_store_map_visibility = WsStoreVisibilityPut(C.dlsym(ws_auth_library,c'vinix_android_account_store_visibility'))
		ws_store_commit = WsStoreClose(C.dlsym(ws_auth_library,c'vinix_android_account_store_commit'))
		ws_store_insertion_free = WsAuthFree(C.dlsym(ws_auth_library,c'vinix_android_account_store_insertion_free'))
		ws_store_snapshot = WsStoreSnapshot(C.dlsym(ws_auth_library,c'vinix_android_account_store_snapshot'))
		ws_store_snapshot_count = WsStoreSize(C.dlsym(ws_auth_library,c'vinix_android_account_store_snapshot_count'))
		ws_store_snapshot_name = WsAuthText(C.dlsym(ws_auth_library,c'vinix_android_account_store_snapshot_name'))
		ws_store_snapshot_type = WsAuthText(C.dlsym(ws_auth_library,c'vinix_android_account_store_snapshot_type'))
		ws_store_snapshot_free = WsAuthFree(C.dlsym(ws_auth_library,c'vinix_android_account_store_snapshot_free'))
		ws_store_query = WsStoreQuery(C.dlsym(ws_auth_library,c'vinix_android_account_store_query'))
		ws_store_password = WsStoreRead(C.dlsym(ws_auth_library,c'vinix_android_account_store_password'))
		ws_store_data = WsStoreData(C.dlsym(ws_auth_library,c'vinix_android_account_store_get_data'))
		ws_store_cell_text = WsAuthString(C.dlsym(ws_auth_library,c'vinix_android_account_store_cell_text'))
		ws_store_cell_free = WsAuthFree(C.dlsym(ws_auth_library,c'vinix_android_account_store_cell_free'))
		ws_store_password_put = WsStoreWrite(C.dlsym(ws_auth_library,c'vinix_android_account_store_set_password'))
		ws_store_data_put = WsStoreWriteData(C.dlsym(ws_auth_library,c'vinix_android_account_store_set_data'))
		ws_store_visibility_put = WsStoreWriteVisibility(C.dlsym(ws_auth_library,c'vinix_android_account_store_set_visibility'))
		if voidptr(ws_store_open) == nil || voidptr(ws_store_close) == nil || voidptr(ws_store_insertion) == nil
			|| voidptr(ws_store_userdata) == nil || voidptr(ws_store_map_visibility) == nil || voidptr(ws_store_commit) == nil
			|| voidptr(ws_store_insertion_free) == nil || voidptr(ws_store_snapshot) == nil || voidptr(ws_store_snapshot_count) == nil
			|| voidptr(ws_store_snapshot_name) == nil || voidptr(ws_store_snapshot_type) == nil || voidptr(ws_store_snapshot_free) == nil
			|| voidptr(ws_store_query) == nil || voidptr(ws_store_password) == nil || voidptr(ws_store_data) == nil
			|| voidptr(ws_store_cell_text) == nil || voidptr(ws_store_cell_free) == nil || voidptr(ws_store_password_put) == nil
			|| voidptr(ws_store_data_put) == nil || voidptr(ws_store_visibility_put) == nil { return false }
		ws_store_handle = ws_store_open(ws_auth_handle,ws.data,account_type,ws_auth_origin)
		return ws_store_handle != nil
	}
}

// The caller holds the native authenticator mutex.
fn ws_store_live() bool {
	return ws.service && unsafe { ws_auth_handle != nil && ws_store_handle != nil }
}

fn ws_store_owner(e voidptr) bool {
	unsafe {
		if !ws.service || !ws_auth_ready {
			throw(e,c'java/lang/SecurityException',c'account mutation requires the selected authenticator'); return false
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		live := ws_store_live()
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if !live { throw(e,c'java/lang/UnsupportedOperationException',c'account store is unavailable') }
		return live
	}
}

fn ws_store_identity(e voidptr, account voidptr, identity &WsStoreIdentity) bool {
	unsafe {
		if account == nil { throw(e,c'java/lang/IllegalArgumentException',c'account is null'); return false }
		name := get_object(e,account,c'android/accounts/Account',c'name',c'Ljava/lang/String;')
		kind := get_object(e,account,c'android/accounts/Account',c'type',c'Ljava/lang/String;')
		identity.name = ws_account_utf8(e,name)
		identity.kind = ws_account_utf8(e,kind)
		if name != nil { Drop(slot(e,23))(e,name) }
		if kind != nil { Drop(slot(e,23))(e,kind) }
		valid := !pending(e) && identity.name != nil && identity.kind != nil
		if !valid && !pending(e) { throw(e,c'java/lang/IllegalArgumentException',c'invalid account identity') }
		return valid
	}
}

// Snapshot Java containers before backend calls. No Java code runs under the
// authenticator mutex; ABI builders enforce total UTF-8 bounds independently.
fn ws_store_copy_map(e voidptr, builder voidptr, original voidptr, metadata bool) bool {
	unsafe {
		if original == nil { return true }
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{l:original}
		copy := if metadata { new_object(e,c'android/os/Bundle',c'(Landroid/os/Bundle;)V',args) }
			else { new_object(e,c'java/util/HashMap',c'(Ljava/util/Map;)V',args) }
		if copy == nil || pending(e) { return false }
		defer { Drop(slot(e,23))(e,copy) }
		keys := if metadata { obj(e,copy,c'android/os/Bundle',c'keySet',c'()Ljava/util/Set;',nil) }
			else { obj(e,copy,c'java/util/HashMap',c'keySet',c'()Ljava/util/Set;',nil) }
		if keys == nil || pending(e) { return false }
		defer { Drop(slot(e,23))(e,keys) }
		iter := obj(e,keys,c'java/util/Set',c'iterator',c'()Ljava/util/Iterator;',nil)
		if iter == nil || pending(e) { return false }
		defer { Drop(slot(e,23))(e,iter) }
		mut count := i32(0)
		for !pending(e) && boolean(e,iter,c'java/util/Iterator',c'hasNext',c'()Z',nil) != 0 {
			count++
			if count > 64 { return false }
			key := obj(e,iter,c'java/util/Iterator',c'next',c'()Ljava/lang/Object;',nil)
			if !ws_account_is(e,key,c'java/lang/String') { if key != nil { Drop(slot(e,23))(e,key) }; return false }
			args[0] = Value{l:key}
			value := if metadata { obj(e,copy,c'android/os/Bundle',c'get',c'(Ljava/lang/String;)Ljava/lang/Object;',args) }
				else { obj(e,copy,c'java/util/HashMap',c'get',c'(Ljava/lang/Object;)Ljava/lang/Object;',args) }
			key_text := ws_account_utf8(e,key)
			mut text := &char(nil)
			mut valid := key_text != nil && !pending(e)
			if metadata {
				if value != nil { valid = valid && ws_account_is(e,value,c'java/lang/String'); if valid { text = ws_account_utf8(e,value); valid = text != nil } }
				if valid { valid = ws_store_userdata(builder,key_text,text) == 0 }
			} else {
				valid = valid && value != nil && ws_account_is(e,value,c'java/lang/Integer')
				if valid { number := integer(e,value,c'java/lang/Integer',c'intValue',c'()I',nil); valid = !pending(e) && ws_store_map_visibility(builder,key_text,number) == 0 }
			}
			C.free(key_text); C.free(text)
			Drop(slot(e,23))(e,key)
			if value != nil { Drop(slot(e,23))(e,value) }
			if !valid { return false }
		}
		return !pending(e)
	}
}

fn ws_store_add(e voidptr, manager voidptr, account voidptr, password voidptr, userdata voidptr, visibility voidptr) u8 {
	unsafe {
		if !ws_store_owner(e) { return 0 }
		identity := &WsStoreIdentity(C.calloc(1,sizeof(WsStoreIdentity)))
		if identity == nil { throw(e,c'java/lang/OutOfMemoryError',c'account identity'); return 0 }
		defer { C.free(identity.name); C.free(identity.kind); C.free(identity) }
		if !ws_store_identity(e,account,identity) { return 0 }
		secret := ws_account_utf8(e,password)
		defer { C.free(secret) }
		if pending(e) { return 0 }
		if password != nil && secret == nil { throw(e,c'java/lang/IllegalArgumentException',c'invalid account password'); return 0 }
		C.pthread_mutex_lock(&ws_auth_mutex)
		builder := if ws_store_live() { ws_store_insertion(ws_store_handle,identity.name,identity.kind,secret) } else { voidptr(nil) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if builder == nil { throw(e,c'java/lang/UnsupportedOperationException',c'account insertion rejected'); return 0 }
		defer { ws_store_insertion_free(builder) }
		if !ws_store_copy_map(e,builder,userdata,true) || !ws_store_copy_map(e,builder,visibility,false) {
			if !pending(e) { throw(e,c'java/lang/IllegalArgumentException',c'invalid account metadata') }; return 0
		}
		result := ws_store_commit(builder)
		if result < 0 { throw(e,c'java/lang/UnsupportedOperationException',c'account insertion failed'); return 0 }
		return u8(result == 1)
	}
}

fn ws_store_array(e voidptr, snapshot voidptr, count i32, name_fn WsAuthText, type_fn WsAuthText) voidptr {
	unsafe {
		if count < 0 || count > 64 { throw(e,c'java/lang/UnsupportedOperationException',c'invalid account snapshot'); return nil }
		account_class := cls(e,c'android/accounts/Account')
		if account_class == nil { return nil }
		defer { Drop(slot(e,23))(e,account_class) }
		array := ObjectArrayNew(slot(e,172))(e,count,account_class,nil)
		if array == nil || pending(e) { return nil }
		args := &Value(C.alloca(2*sizeof(Value)))
		for i := i32(0); i < count; i++ {
			args[0] = Value{l:ws_account_java_text(e,name_fn(snapshot,u32(i)))}
			args[1] = Value{l:ws_account_java_text(e,type_fn(snapshot,u32(i)))}
			mut account := voidptr(nil)
			if args[0].l != nil && args[1].l != nil && !pending(e) { account = new_object(e,c'android/accounts/Account',c'(Ljava/lang/String;Ljava/lang/String;)V',args) }
			if account != nil && !pending(e) { WsArraySet(slot(e,174))(e,array,i,account) }
			if args[0].l != nil { Drop(slot(e,23))(e,args[0].l) }
			if args[1].l != nil { Drop(slot(e,23))(e,args[1].l) }
			if account != nil { Drop(slot(e,23))(e,account) }
			if account == nil || pending(e) {
				if !pending(e) { throw(e,c'java/lang/UnsupportedOperationException',c'invalid account snapshot text') }
				Drop(slot(e,23))(e,array); return nil
			}
		}
		return array
	}
}

fn ws_store_accounts(e voidptr, manager voidptr, account_type voidptr, target_package voidptr) voidptr {
	unsafe {
		if target_package != nil && !ws_appops_owns(e,i32(C.getuid()),target_package) {
			throw(e,c'java/lang/SecurityException',c'account query package does not belong to caller'); return nil
		}
		kind := ws_account_utf8(e,account_type)
		defer { C.free(kind) }
		if pending(e) { return nil }
		if account_type != nil && kind == nil { throw(e,c'java/lang/IllegalArgumentException',c'invalid account type'); return nil }
		if ws.service {
			if !ws_store_owner(e) { return nil }
			C.pthread_mutex_lock(&ws_auth_mutex)
			snapshot := if ws_store_live() { ws_store_snapshot(ws_store_handle,kind) } else { voidptr(nil) }
			C.pthread_mutex_unlock(&ws_auth_mutex)
			if snapshot == nil { throw(e,c'java/lang/UnsupportedOperationException',c'account snapshot failed'); return nil }
			defer { ws_store_snapshot_free(snapshot) }
			return ws_store_array(e,snapshot,ws_store_snapshot_count(snapshot),ws_store_snapshot_name,ws_store_snapshot_type)
		}
		if !ws_account_initialized || ws_account_library == nil {
			throw(e,c'java/lang/UnsupportedOperationException',c'account broker is unavailable'); return nil
		}
		count_fn := WsAccountCount(C.dlsym(ws_account_library,c'vinix_android_account_account_count'))
		name_fn := WsAuthText(C.dlsym(ws_account_library,c'vinix_android_account_account_name'))
		type_fn := WsAuthText(C.dlsym(ws_account_library,c'vinix_android_account_account_type'))
		if voidptr(count_fn) == nil || voidptr(name_fn) == nil || voidptr(type_fn) == nil {
			throw(e,c'java/lang/UnsupportedOperationException',c'account query API is unavailable'); return nil
		}
		C.pthread_mutex_lock(&ws_account_mutex)
		if ws_account_closing || ws_account_sequence == ~u64(0) {
			C.pthread_mutex_unlock(&ws_account_mutex)
			throw(e,c'java/lang/UnsupportedOperationException',c'account client is closing'); return nil
		}
		ws_account_sequence++
		id := ws_account_sequence
		C.pthread_mutex_unlock(&ws_account_mutex)
		builder := ws_account_build(id,1,kind,nil)
		if builder == nil { throw(e,c'java/lang/IllegalArgumentException',c'invalid account query'); return nil }
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
			if response_kind == 3 { return ws_store_array(e,client,i32(count_fn(client)),name_fn,type_fn) }
			break
		}
		throw(e,c'java/lang/UnsupportedOperationException',c'account query failed or timed out')
		return nil
	}
}

fn ws_store_read(e voidptr, account voidptr, key voidptr, password bool) voidptr {
	unsafe {
		if !ws_store_owner(e) { return nil }
		identity := &WsStoreIdentity(C.calloc(1,sizeof(WsStoreIdentity)))
		if identity == nil { throw(e,c'java/lang/OutOfMemoryError',c'account identity'); return nil }
		defer { C.free(identity.name); C.free(identity.kind); C.free(identity) }
		if !ws_store_identity(e,account,identity) { return nil }
		key_text := ws_account_utf8(e,key)
		defer { C.free(key_text) }
		if pending(e) { return nil }
		if !password && key_text == nil { throw(e,c'java/lang/IllegalArgumentException',c'invalid account metadata key'); return nil }
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut cell := voidptr(nil)
		mut text := &char(nil)
		mut copied := true
		if ws_store_live() {
			cell = if password { ws_store_password(ws_store_handle,identity.name,identity.kind) }
				else { ws_store_data(ws_store_handle,identity.name,identity.kind,key_text) }
			if cell != nil {
				value := ws_store_cell_text(cell)
				if value != nil { text = C.strdup(value); copied = text != nil }
			}
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		defer { C.free(text); if cell != nil { ws_store_cell_free(cell) } }
		if cell == nil || !copied { throw(e,c'java/lang/UnsupportedOperationException',c'account value read failed'); return nil }
		if text == nil { return nil }
		result := ws_account_java_text(e,text)
		if result == nil && !pending(e) { throw(e,c'java/lang/UnsupportedOperationException',c'invalid account value text') }
		return result
	}
}

fn ws_store_get_password(e voidptr, manager voidptr, account voidptr) voidptr {
	return ws_store_read(e,account,unsafe { nil },true)
}

fn ws_store_get_data(e voidptr, manager voidptr, account voidptr, key voidptr) voidptr {
	return ws_store_read(e,account,key,false)
}

fn ws_store_write(e voidptr, account voidptr, key voidptr, value voidptr, mode i32, visibility i32) i32 {
	unsafe {
		if !ws_store_owner(e) { return -1 }
		identity := &WsStoreIdentity(C.calloc(1,sizeof(WsStoreIdentity)))
		if identity == nil { throw(e,c'java/lang/OutOfMemoryError',c'account identity'); return -1 }
		defer { C.free(identity.name); C.free(identity.kind); C.free(identity) }
		if !ws_store_identity(e,account,identity) { return -1 }
		key_text := ws_account_utf8(e,key)
		value_text := ws_account_utf8(e,value)
		defer { C.free(key_text); C.free(value_text) }
		if pending(e) { return -1 }
		if (mode != 0 && key_text == nil) || (value != nil && value_text == nil) {
			throw(e,c'java/lang/IllegalArgumentException',c'invalid account value'); return -1
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut result := i32(-1)
		if ws_store_live() {
			if mode == 0 { result = ws_store_password_put(ws_store_handle,identity.name,identity.kind,value_text) }
			else if mode == 1 { result = ws_store_data_put(ws_store_handle,identity.name,identity.kind,key_text,value_text) }
			else if mode == 2 { result = ws_store_visibility_put(ws_store_handle,identity.name,identity.kind,key_text,visibility) }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if result < 0 { throw(e,c'java/lang/UnsupportedOperationException',c'account update failed') }
		return result
	}
}

fn ws_store_set_password(e voidptr, manager voidptr, account voidptr, value voidptr) {
	ws_store_write(e,account,unsafe { nil },value,0,0)
}

fn ws_store_set_data(e voidptr, manager voidptr, account voidptr, key voidptr, value voidptr) {
	ws_store_write(e,account,key,value,1,0)
}

fn ws_store_visibility(e voidptr, manager voidptr, account voidptr, package_name voidptr, visibility i32) u8 {
	return u8(ws_store_write(e,account,package_name,unsafe { nil },2,visibility) == 1)
}

// Query sessions are resolved by the native store using their authenticated
// caller, and never passed to APK Java code or supplied a claimed package.
fn ws_store_dispatch(id u64) bool {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		if ws_store_live() {
			result := ws_store_query(ws_store_handle,ws_auth_handle,id)
			C.pthread_mutex_unlock(&ws_auth_mutex)
			return result == 0
		}
		builder := if ws_auth_handle != nil { ws_auth_response(ws_auth_handle,id,2) } else { voidptr(nil) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if builder == nil { return false }
		defer { ws_auth_free(builder) }
		return ws_auth_error_fields(builder,6,c'account store is unavailable') && ws_auth_send(builder) == 0
	}
}

// Caller holds the native mutex. Repeated shutdown is harmless.
fn ws_store_shutdown() {
	unsafe {
		handle := ws_store_handle
		ws_store_handle = nil
		if handle != nil { ws_store_close(handle) }
	}
}
