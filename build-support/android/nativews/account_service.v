// SPDX-License-Identifier: GPL-2.0-or-later
// Root-authorized account dispatch on the service main Looper. Never accepts
// commands on the separate service lifetime channel.
@[translated]
module atlframework

fn C.unsetenv(&char) i32
type WsAuthArray = fn (voidptr,i32,voidptr,voidptr) voidptr

type WsAuthOpen = fn (i32) voidptr
type WsAuthRead = fn (voidptr, &u64, i32) i32
type WsAuthFree = fn (voidptr)
type WsAuthCount = fn (voidptr) u32
type WsAuthString = fn (voidptr) &char
type WsAuthText = fn (voidptr,u32) &char
type WsAuthTag = fn (voidptr,u32) u16
type WsAuthNumber = fn (voidptr,u32) i64
type WsAuthResponse = fn (voidptr,u64,u16) voidptr
type WsAuthOption = fn (voidptr,&char,u16,&char,i64) i32
type WsAuthSend = fn (voidptr) i32

struct WsAuthSlot {
mut:
	next &WsAuthSlot
	id u64
	response voidptr
}

struct WsAuthValue {
mut:
	key &char
	text &char
	tag u16
	number i64
}

struct WsAuthCommand {
mut:
	id u64
	account_type &char
	token_type &char
	feature_count u32
	features [32]&char
	count u32
	options [35]WsAuthValue
}

__global ws_auth_library voidptr
__global ws_auth_handle voidptr
__global ws_auth_mutex C.pthread_mutex_t
__global ws_auth_ready bool
__global ws_auth_slots &WsAuthSlot
__global ws_auth_scope bool
__global ws_auth_broker_pid i32
__global ws_auth_open WsAuthOpen
__global ws_auth_read WsAuthRead
__global ws_auth_close WsAuthFree
__global ws_auth_type WsAuthString
__global ws_auth_token WsAuthString
__global ws_auth_features WsAuthCount
__global ws_auth_feature WsAuthText
__global ws_auth_count WsAuthCount
__global ws_auth_key WsAuthText
__global ws_auth_tag WsAuthTag
__global ws_auth_text WsAuthText
__global ws_auth_number WsAuthNumber
__global ws_auth_response WsAuthResponse
__global ws_auth_option WsAuthOption
__global ws_auth_send WsAuthSend
__global ws_auth_free WsAuthFree

fn ws_account_service_init() bool {
	unsafe {
		value := C.getenv(c'VINIX_ANDROID_AUTHENTICATOR_FD')
		if value == nil { return true }
		mut fd := i32(0)
		mut valid := value[0] != 0
		for p := value; *p != 0; p++ {
			if *p < `0` || *p > `9` || fd > 214748364 || (fd == 214748364 && *p > `7`) { valid = false; break }
			fd = fd * 10 + i32(*p - `0`)
		}
		C.unsetenv(c'VINIX_ANDROID_AUTHENTICATOR_FD')
		if !valid || fd < 3 || C.pthread_mutex_init(&ws_auth_mutex,nil) != 0 { return false }
		ws_auth_ready = true
		mut peer := WsServicePeer{}
		mut peer_size := u32(sizeof(WsServicePeer))
		if C.getsockopt(fd,1,17,&peer,&peer_size) != 0 || peer_size != sizeof(WsServicePeer) || peer.uid != 0 || peer.pid <= 0 {
			C.close(fd); return false
		}
		ws_auth_broker_pid = peer.pid
		ws_auth_library = C.dlopen(c'libvinix-android-account.so',2)
		if ws_auth_library == nil { C.close(fd); return false }
		ws_auth_open = WsAuthOpen(C.dlsym(ws_auth_library,c'vinix_android_authenticator_open'))
		ws_auth_read = WsAuthRead(C.dlsym(ws_auth_library,c'vinix_android_authenticator_read'))
		ws_auth_close = WsAuthFree(C.dlsym(ws_auth_library,c'vinix_android_authenticator_close'))
		ws_auth_type = WsAuthString(C.dlsym(ws_auth_library,c'vinix_android_authenticator_account_type'))
		ws_auth_token = WsAuthString(C.dlsym(ws_auth_library,c'vinix_android_authenticator_auth_token_type'))
		ws_auth_features = WsAuthCount(C.dlsym(ws_auth_library,c'vinix_android_authenticator_feature_count'))
		ws_auth_feature = WsAuthText(C.dlsym(ws_auth_library,c'vinix_android_authenticator_feature'))
		ws_auth_count = WsAuthCount(C.dlsym(ws_auth_library,c'vinix_android_authenticator_count'))
		ws_auth_key = WsAuthText(C.dlsym(ws_auth_library,c'vinix_android_authenticator_key'))
		ws_auth_tag = WsAuthTag(C.dlsym(ws_auth_library,c'vinix_android_authenticator_tag'))
		ws_auth_text = WsAuthText(C.dlsym(ws_auth_library,c'vinix_android_authenticator_text'))
		ws_auth_number = WsAuthNumber(C.dlsym(ws_auth_library,c'vinix_android_authenticator_number'))
		ws_auth_response = WsAuthResponse(C.dlsym(ws_auth_library,c'vinix_android_authenticator_response'))
		ws_auth_option = WsAuthOption(C.dlsym(ws_auth_library,c'vinix_android_authenticator_response_option'))
		ws_auth_send = WsAuthSend(C.dlsym(ws_auth_library,c'vinix_android_authenticator_response_send'))
		ws_auth_free = WsAuthFree(C.dlsym(ws_auth_library,c'vinix_android_authenticator_response_free'))
		if voidptr(ws_auth_open) == nil || voidptr(ws_auth_read) == nil || voidptr(ws_auth_close) == nil
			|| voidptr(ws_auth_type) == nil || voidptr(ws_auth_token) == nil || voidptr(ws_auth_features) == nil || voidptr(ws_auth_feature) == nil
			|| voidptr(ws_auth_count) == nil || voidptr(ws_auth_key) == nil || voidptr(ws_auth_tag) == nil || voidptr(ws_auth_text) == nil || voidptr(ws_auth_number) == nil
			|| voidptr(ws_auth_response) == nil || voidptr(ws_auth_option) == nil || voidptr(ws_auth_send) == nil || voidptr(ws_auth_free) == nil {
			C.close(fd); return false
		}
		ws_auth_handle = ws_auth_open(fd)
		if ws_auth_handle == nil { C.close(fd); return false }
		return true
	}
}

// Only the exact callback object created for this dispatch can claim it.
// IsSameObject is a reference comparison; no Java code executes under the lock.
fn ws_auth_claim(e voidptr, response voidptr, kind u16, id &u64) voidptr {
	unsafe {
		if !ws_auth_ready || response == nil { return nil }
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut previous := &WsAuthSlot(nil)
		mut node := ws_auth_slots
		for node != nil && Same(slot(e,24))(e,node.response,response) == 0 {
			previous = node; node = node.next
		}
		mut builder := voidptr(nil)
		if node != nil && ws_auth_handle != nil {
			*id = node.id
			builder = ws_auth_response(ws_auth_handle,node.id,kind)
		}
		if node != nil && kind != 5 {
			if previous == nil { ws_auth_slots = node.next } else { previous.next = node.next }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if node != nil && kind != 5 { Drop(slot(e,22))(e,node.response); C.free(node) }
		return builder
	}
}

fn ws_auth_error_fields(builder voidptr, code i32, text &char) bool {
	return ws_auth_option(builder,c'errorCode',3,unsafe { nil },i64(code)) == 0
		&& ws_auth_option(builder,c'errorMessage',1,text,0) == 0
}

fn ws_auth_error(e voidptr, response voidptr, code i32, message voidptr) {
	unsafe {
		mut id := u64(0)
		builder := ws_auth_claim(e,response,2,&id)
		if builder == nil { return }
		defer { ws_auth_free(builder) }
		text := ws_account_utf8(e,message)
		defer { C.free(text) }
		if pending(e) { WsApplicationClear(slot(e,17))(e) }
		if ws_auth_error_fields(builder,code,if text == nil { c'authenticator error' } else { text }) { ws_auth_send(builder) }
	}
}

fn ws_auth_continued(e voidptr, response voidptr) {
	unsafe {
		mut id := u64(0)
		builder := ws_auth_claim(e,response,5,&id)
		if builder == nil { return }
		ws_auth_send(builder); ws_auth_free(builder)
	}
}

fn ws_auth_result(e voidptr, response voidptr, bundle voidptr) {
	unsafe {
		mut id := u64(0)
		builder := ws_auth_claim(e,response,1,&id)
		if builder == nil { return }
		valid := bundle != nil && ws_account_copy_options(e,builder,bundle,WsAccountOption(ws_auth_option))
		if valid { ws_auth_send(builder) }
		ws_auth_free(builder)
		if valid { return }
		if pending(e) { WsApplicationClear(slot(e,17))(e) }
		// Parcelable results (including Intent) need an opaque Activity route.
		// Report unsupported data rather than serializing or inventing success.
		C.pthread_mutex_lock(&ws_auth_mutex)
		failure := if ws_auth_handle == nil { voidptr(nil) } else { ws_auth_response(ws_auth_handle,id,2) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if failure != nil {
			if ws_auth_error_fields(failure,6,c'unsupported authenticator result') { ws_auth_send(failure) }
			ws_auth_free(failure)
		}
	}
}

fn ws_auth_calling_uid() i32 {
	if ws != unsafe { nil } && usize(C.pthread_self()) == ws.main_thread && ws_auth_scope { return 1000 }
	return -2
}

fn ws_auth_calling_pid() i32 {
	return if ws_auth_calling_uid() == 1000 { ws_auth_broker_pid } else { -2 }
}

fn ws_auth_permission(e voidptr, permission voidptr, pid i32, uid i32) i32 {
	if ws_auth_calling_uid() != 1000 || (uid != -1 && uid != 1000)
		|| (pid != -1 && pid != ws_auth_broker_pid) { return -2 }
	if ws_service_string(e,permission,c'android.permission.ACCOUNT_MANAGER') { return 0 }
	return -2
}

fn ws_auth_command_free(command &WsAuthCommand) {
	unsafe {
		C.free(command.account_type); C.free(command.token_type)
		for i := u32(0); i < command.feature_count; i++ { C.free(command.features[i]) }
		for i := u32(0); i < command.count; i++ {
			C.free(command.options[i].key); C.free(command.options[i].text)
		}
		C.free(command)
	}
}

// Copy borrowed transport values before releasing the native lock. Java class
// initialization, constructors and authenticator calls always run after it.
fn ws_auth_copy(id u64) &WsAuthCommand {
	unsafe {
		command := &WsAuthCommand(C.calloc(1,sizeof(WsAuthCommand)))
		if command == nil { return nil }
		command.id = id
		name := ws_auth_type(ws_auth_handle)
		if name == nil { ws_auth_command_free(command); return nil }
		command.account_type = C.strdup(name)
		token := ws_auth_token(ws_auth_handle)
		if token != nil { command.token_type = C.strdup(token) }
		command.feature_count = ws_auth_features(ws_auth_handle)
		command.count = ws_auth_count(ws_auth_handle)
		if command.feature_count > 32 || command.count > 35 {
			command.feature_count = 0; command.count = 0
			ws_auth_command_free(command); return nil
		}
		mut valid := command.account_type != nil && (token == nil || command.token_type != nil)
		for i := u32(0); i < command.feature_count; i++ {
			value := ws_auth_feature(ws_auth_handle,i)
			if value == nil { valid = false; continue }
			command.features[i] = C.strdup(value)
			if command.features[i] == nil { valid = false }
		}
		for i := u32(0); i < command.count; i++ {
			key := ws_auth_key(ws_auth_handle,i)
			if key == nil { valid = false; continue }
			command.options[i].key = C.strdup(key)
			command.options[i].tag = ws_auth_tag(ws_auth_handle,i)
			command.options[i].number = ws_auth_number(ws_auth_handle,i)
			text := ws_auth_text(ws_auth_handle,i)
			if text != nil { command.options[i].text = C.strdup(text) }
			if command.options[i].key == nil || command.options[i].tag > 4
				|| (command.options[i].tag == 1 && command.options[i].text == nil) { valid = false }
		}
		if !valid { ws_auth_command_free(command); return nil }
		return command
	}
}

fn ws_auth_bundle(e voidptr, command &WsAuthCommand) voidptr {
	unsafe {
		bundle := new_object(e,c'android/os/Bundle',c'()V',nil)
		for i := u32(0); i < command.count && !pending(e); i++ {
			item := &command.options[i]
			key := ws_account_java_text(e,item.key)
			mut args := [Value{l:key},Value{j:item.number}]!
			if item.tag == 0 || item.tag == 1 {
				args[1] = Value{l: if item.tag == 0 { voidptr(nil) } else { ws_account_java_text(e,item.text) }}
				call(e,bundle,c'android/os/Bundle',c'putString',c'(Ljava/lang/String;Ljava/lang/String;)V',&args[0])
				if args[1].l != nil { Drop(slot(e,23))(e,args[1].l) }
			} else if item.tag == 2 {
				args[1] = Value{i:i32(item.number)}
				call(e,bundle,c'android/os/Bundle',c'putBoolean',c'(Ljava/lang/String;Z)V',&args[0])
			} else if item.tag == 3 {
				args[1] = Value{i:i32(item.number)}
				call(e,bundle,c'android/os/Bundle',c'putInt',c'(Ljava/lang/String;I)V',&args[0])
			} else {
				call(e,bundle,c'android/os/Bundle',c'putLong',c'(Ljava/lang/String;J)V',&args[0])
			}
			Drop(slot(e,23))(e,key)
		}
		return bundle
	}
}

fn ws_auth_dispatch(e voidptr, binder voidptr, command &WsAuthCommand) bool {
	unsafe {
		arg := &Value(C.alloca(sizeof(Value)))
		arg.l = binder
		authenticator := static_obj(e,c'android/accounts/IAccountAuthenticator$Stub',c'asInterface',c'(Landroid/os/IBinder;)Landroid/accounts/IAccountAuthenticator;',arg)
		if authenticator == nil || pending(e) { return false }
		constructor := &Value(C.alloca(sizeof(Value)))
		constructor.j = i64(command.id)
		response := new_object(e,c'android/atl/VinixAuthenticatorResponse',c'(J)V',constructor)
		bundle := ws_auth_bundle(e,command)
		string_class := cls(e,c'java/lang/String')
		features := WsAuthArray(slot(e,172))(e,i32(command.feature_count),string_class,nil)
		Drop(slot(e,23))(e,string_class)
		for i := u32(0); i < command.feature_count && !pending(e); i++ {
			text := ws_account_java_text(e,command.features[i])
			WsArraySet(slot(e,174))(e,features,i32(i),text)
			Drop(slot(e,23))(e,text)
		}
		if pending(e) || response == nil || bundle == nil || features == nil { return false }
		node := &WsAuthSlot(C.calloc(1,sizeof(WsAuthSlot)))
		if node == nil { return false }
		node.id = command.id
		node.response = WsRef(slot(e,21))(e,response)
		if node.response == nil { C.free(node); return false }
		C.pthread_mutex_lock(&ws_auth_mutex)
		node.next = ws_auth_slots; ws_auth_slots = node
		C.pthread_mutex_unlock(&ws_auth_mutex)
		args := [Value{l:response},Value{l:ws_account_java_text(e,command.account_type)},Value{l:ws_account_java_text(e,command.token_type)},Value{l:features},Value{l:bundle}]!
		if pending(e) { return false }
		ws_auth_scope = true
		call(e,authenticator,c'android/accounts/IAccountAuthenticator',c'addAccount',c'(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)V',&args[0])
		ws_auth_scope = false
		return !pending(e)
	}
}

fn ws_auth_cancel(e voidptr, id u64) {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut previous := &WsAuthSlot(nil)
		mut node := ws_auth_slots
		for node != nil && node.id != id { previous = node; node = node.next }
		if node != nil {
			if previous == nil { ws_auth_slots = node.next } else { previous.next = node.next }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if node != nil { Drop(slot(e,22))(e,node.response); C.free(node) }
	}
}

fn ws_account_service_pump(e voidptr, binder voidptr) bool {
	unsafe {
		if !ws_auth_ready { return true }
		for _ in 0 .. 8 {
			mut id := u64(0)
			C.pthread_mutex_lock(&ws_auth_mutex)
			status := if ws_auth_handle == nil { i32(-1) } else { ws_auth_read(ws_auth_handle,&id,0) }
			command := if status == 1 { ws_auth_copy(id) } else { &WsAuthCommand(nil) }
			C.pthread_mutex_unlock(&ws_auth_mutex)
			if status < 0 { return false }
			if status == 0 { return true }
			if status == 2 { ws_auth_cancel(e,id); continue }
			if command == nil { return false }
			ok := ws_auth_dispatch(e,binder,command)
			ws_auth_command_free(command)
			if !ok { return false }
		}
		return true
	}
}

fn ws_account_service_shutdown(e voidptr) {
	unsafe {
		if !ws_auth_ready { return }
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut nodes := ws_auth_slots
		ws_auth_slots = nil
		handle := ws_auth_handle
		ws_auth_handle = nil
		// Response builders hold a transport reference, so callbacks already
		// copying a Bundle can finish safely and observe the closed handle.
		if handle != nil { ws_auth_close(handle) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		for nodes != nil {
			next := nodes.next
			if e != nil { Drop(slot(e,22))(e,nodes.response) }
			C.free(nodes); nodes = next
		}
	}
}
