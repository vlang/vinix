// SPDX-License-Identifier: GPL-2.0-or-later
// Root-authorized account dispatch through one bounded Binder-style worker.
// The main Looper retains UI delivery and the separate service lifetime channel.
@[translated]
module atlframework

fn C.unsetenv(&char) i32
type WsAuthArray = fn (voidptr,i32,voidptr,voidptr) voidptr

type WsAuthOpen = fn (i32) voidptr
type WsAuthRead = fn (voidptr, &u64, i32) i32
type WsAuthOperation = fn (voidptr) u16
type WsAuthFree = fn (voidptr)
type WsAuthCount = fn (voidptr) u32
type WsAuthString = fn (voidptr) &char
type WsAuthText = fn (voidptr,u32) &char
type WsAuthTag = fn (voidptr,u32) u16
type WsAuthNumber = fn (voidptr,u32) i64
type WsAuthResponse = fn (voidptr,u64,u16) voidptr
type WsAuthOption = fn (voidptr,&char,u16,&char,i64) i32
type WsAuthSend = fn (voidptr) i32
type WsAuthInteraction = fn (voidptr,&char,&char) i32
type WsAuthUiAuthority = fn (voidptr,u64,&u8,u32) i32
type WsAuthLaunchTarget = fn (voidptr,u64,&char,&char) i32
type WsAuthTokenAuthorized = fn (voidptr,voidptr,u64) i32

struct WsAuthSlot {
mut:
	next &WsAuthSlot
	id u64
	response voidptr
	bundle voidptr
	intent voidptr
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
	account_name &char
	account_type &char
	operation u16
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
__global ws_auth_worker_thread usize
__global ws_auth_broker_pid i32
__global ws_auth_open WsAuthOpen
__global ws_auth_read WsAuthRead
__global ws_auth_operation WsAuthOperation
__global ws_auth_close WsAuthFree
__global ws_auth_type WsAuthString
__global ws_auth_name WsAuthString
__global ws_auth_token WsAuthString
__global ws_auth_token_authorized WsAuthTokenAuthorized
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
__global ws_auth_interaction WsAuthInteraction
__global ws_auth_origin &char
__global ws_auth_ui_authority WsAuthUiAuthority
__global ws_auth_launch_target WsAuthLaunchTarget

fn ws_account_service_init() bool {
	unsafe {
		account_type := ws_store_take_type()
		defer { C.free(account_type) }
		value := C.getenv(c'VINIX_ANDROID_AUTHENTICATOR_FD')
		if value == nil { return true }
		mut fd := i32(0)
		mut valid := value[0] != 0
		for p := value; *p != 0; p++ {
			if *p < `0` || *p > `9` || fd > 214748364 || (fd == 214748364 && *p > `7`) { valid = false; break }
			fd = fd * 10 + i32(*p - `0`)
		}
		C.unsetenv(c'VINIX_ANDROID_AUTHENTICATOR_FD')
		if !valid || fd < 3 { return ws_auth_init_failure(1,22,0,nil) }
		mutex_code := C.pthread_mutex_init(&ws_auth_mutex,nil)
		if mutex_code != 0 { return ws_auth_init_failure(2,mutex_code,0,nil) }
		ws_auth_ready = true
		mut peer := WsServicePeer{}
		mut peer_size := u32(sizeof(WsServicePeer))
		if C.getsockopt(fd,1,17,&peer,&peer_size) != 0 {
			code := *C.__errno_location()
			C.close(fd); return ws_auth_init_failure(3,code,0,nil)
		}
		if peer_size != sizeof(WsServicePeer) || peer.uid != 0 || peer.pid <= 0 {
			detail := if peer_size != sizeof(WsServicePeer) { 1 } else if peer.uid != 0 { 2 } else { 3 }
			C.close(fd); return ws_auth_init_failure(4,1,detail,nil)
		}
		ws_auth_broker_pid = peer.pid
		C.dlerror()
		*C.__errno_location() = 0
		ws_auth_library = C.dlopen(c'libvinix-android-account.so',2)
		if ws_auth_library == nil {
			code := *C.__errno_location()
			loader := C.dlerror()
			C.close(fd); return ws_auth_init_failure(5,code,0,loader)
		}
		ws_auth_open = WsAuthOpen(ws_auth_init_symbol(c'vinix_android_authenticator_open',1))
		ws_auth_read = WsAuthRead(ws_auth_init_symbol(c'vinix_android_authenticator_read',2))
		ws_auth_operation = WsAuthOperation(ws_auth_init_symbol(c'vinix_android_authenticator_operation',3))
		ws_auth_close = WsAuthFree(ws_auth_init_symbol(c'vinix_android_authenticator_close',4))
		ws_auth_type = WsAuthString(ws_auth_init_symbol(c'vinix_android_authenticator_account_type',5))
		ws_auth_name = WsAuthString(ws_auth_init_symbol(c'vinix_android_authenticator_account_name',6))
		ws_auth_token = WsAuthString(ws_auth_init_symbol(c'vinix_android_authenticator_auth_token_type',7))
		ws_auth_token_authorized = WsAuthTokenAuthorized(ws_auth_init_symbol(c'vinix_android_account_store_token_authorized',8))
		ws_auth_features = WsAuthCount(ws_auth_init_symbol(c'vinix_android_authenticator_feature_count',9))
		ws_auth_feature = WsAuthText(ws_auth_init_symbol(c'vinix_android_authenticator_feature',10))
		ws_auth_count = WsAuthCount(ws_auth_init_symbol(c'vinix_android_authenticator_count',11))
		ws_auth_key = WsAuthText(ws_auth_init_symbol(c'vinix_android_authenticator_key',12))
		ws_auth_tag = WsAuthTag(ws_auth_init_symbol(c'vinix_android_authenticator_tag',13))
		ws_auth_text = WsAuthText(ws_auth_init_symbol(c'vinix_android_authenticator_text',14))
		ws_auth_number = WsAuthNumber(ws_auth_init_symbol(c'vinix_android_authenticator_number',15))
		ws_auth_response = WsAuthResponse(ws_auth_init_symbol(c'vinix_android_authenticator_response',16))
		ws_auth_option = WsAuthOption(ws_auth_init_symbol(c'vinix_android_authenticator_response_option',17))
		ws_auth_send = WsAuthSend(ws_auth_init_symbol(c'vinix_android_authenticator_response_send',18))
		ws_auth_free = WsAuthFree(ws_auth_init_symbol(c'vinix_android_authenticator_response_free',19))
		ws_auth_interaction = WsAuthInteraction(ws_auth_init_symbol(c'vinix_android_authenticator_response_interaction',20))
		ws_auth_ui_authority = WsAuthUiAuthority(ws_auth_init_symbol(c'vinix_android_authenticator_ui_authority',21))
		ws_auth_launch_target = WsAuthLaunchTarget(ws_auth_init_symbol(c'vinix_android_authenticator_launch_target',22))
		if voidptr(ws_auth_open) == nil || voidptr(ws_auth_read) == nil || voidptr(ws_auth_operation) == nil || voidptr(ws_auth_close) == nil
			|| voidptr(ws_auth_type) == nil || voidptr(ws_auth_name) == nil || voidptr(ws_auth_token) == nil || voidptr(ws_auth_token_authorized) == nil || voidptr(ws_auth_features) == nil || voidptr(ws_auth_feature) == nil
			|| voidptr(ws_auth_count) == nil || voidptr(ws_auth_key) == nil || voidptr(ws_auth_tag) == nil || voidptr(ws_auth_text) == nil || voidptr(ws_auth_number) == nil
			|| voidptr(ws_auth_response) == nil || voidptr(ws_auth_option) == nil || voidptr(ws_auth_send) == nil || voidptr(ws_auth_free) == nil || voidptr(ws_auth_interaction) == nil || voidptr(ws_auth_ui_authority) == nil || voidptr(ws_auth_launch_target) == nil {
			C.close(fd); return false
		}
		*C.__errno_location() = 0
		ws_auth_handle = ws_auth_open(fd)
		if ws_auth_handle == nil {
			code := *C.__errno_location()
			C.close(fd); return ws_auth_init_failure(7,code,0,nil)
		}
		*C.__errno_location() = 0
		if !ws_store_init(account_type) { return ws_auth_init_failure(8,*C.__errno_location(),0,nil) }
		return true
	}
}

fn C.strstr(&char, &char) &char

// Classify only the first 512 loader bytes. Never print paths, symbol names or
// other loader-controlled text. Codes: 0 none, 1 other, 2 missing file,
// 3 missing symbol, 4 invalid ELF, 5 permission.
fn ws_auth_init_loader(loader &char) i32 {
	unsafe {
		if loader == nil { return 0 }
		text := &char(C.alloca(513))
		mut length := 0
		for length < 512 && loader[length] != 0 { text[length] = loader[length]; length++ }
		text[length] = 0
		if C.strstr(text,c'No such file') != nil || C.strstr(text,c'cannot open shared object') != nil { return 2 }
		if C.strstr(text,c'undefined symbol') != nil || C.strstr(text,c'symbol not found') != nil { return 3 }
		if C.strstr(text,c'ELF') != nil || C.strstr(text,c'Exec format') != nil { return 4 }
		if C.strstr(text,c'Permission denied') != nil { return 5 }
		return 1
	}
}

// One bounded line per failing stage (at most 22 missing-symbol lines). Stage:
// 1 descriptor, 2 mutex, 3 peer syscall, 4 peer identity, 5 library, 6 symbol,
// 7 authenticator open, 8 account store. Code is errno or the mutex return code;
// detail is the identity field (size/uid/pid) or stable 1-based symbol index.
fn ws_auth_init_failure(stage i32, code i32, detail i32, loader &char) bool {
	unsafe {
		buffer := &char(C.alloca(128))
		length := C.snprintf(buffer,128,c'ANDROID-AUTH-INIT-FAIL stage=%d code=%d detail=%d loader=%d\n',stage,code,detail,ws_auth_init_loader(loader))
		if length > 0 && length < 128 { C.write(2,buffer,usize(length)) }
		return false
	}
}

fn ws_auth_init_symbol(name &char, detail i32) voidptr {
	unsafe {
		C.dlerror()
		*C.__errno_location() = 0
		value := C.dlsym(ws_auth_library,name)
		if value == nil {
			code := *C.__errno_location()
			loader := C.dlerror()
			ws_auth_init_failure(6,code,detail,loader)
		}
		return value
	}
}

fn ws_auth_slot_free(e voidptr, node &WsAuthSlot) {
	unsafe {
		if e != nil {
			Drop(slot(e,22))(e,node.response)
			if node.bundle != nil { Drop(slot(e,22))(e,node.bundle) }
			if node.intent != nil { Drop(slot(e,22))(e,node.intent) }
		}
		C.free(node)
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
		if node != nil && kind != 5 && kind != 4 {
			if previous == nil { ws_auth_slots = node.next } else { previous.next = node.next }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if node != nil && kind != 5 && kind != 4 { ws_auth_slot_free(e,node) }
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

fn ws_auth_extract(e voidptr, bundle voidptr, response voidptr) voidptr {
	unsafe {
		if bundle == nil || ws_auth_origin == nil { return nil }
		args := &Value(C.alloca(3 * sizeof(Value)))
		args[0] = Value{l:bundle}
		args[1] = Value{l:response}
		args[2] = Value{l:ws_account_java_text(e,ws_auth_origin)}
		if args[2].l == nil || pending(e) { return nil }
		return static_obj(e,c'android/atl/VinixAccountInteraction',c'extract',c'(Landroid/os/Bundle;Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;)Landroid/content/Intent;',&args[0])
	}
}

// Keep the original graph in its VM. No class loader, Parcelable or Java
// object crosses the broker boundary; only a random normal-side handle does.
fn ws_auth_try_interaction(e voidptr, response voidptr, bundle voidptr) bool {
	unsafe {
		mut id := u64(0)
		builder := ws_auth_claim(e,response,4,&id)
		if builder == nil { return true }
		defer { ws_auth_free(builder) }
		intent := ws_auth_extract(e,bundle,response)
		if intent == nil || pending(e) {
			if pending(e) { WsApplicationClear(slot(e,17))(e) }
			return false
		}
		component := obj(e,intent,c'android/content/Intent',c'getComponent',c'()Landroid/content/ComponentName;',nil)
		if component == nil || pending(e) { return false }
		pkg := obj(e,component,c'android/content/ComponentName',c'getPackageName',c'()Ljava/lang/String;',nil)
		if pkg == nil || pending(e) { return false }
		name := obj(e,component,c'android/content/ComponentName',c'getClassName',c'()Ljava/lang/String;',nil)
		if name == nil || pending(e) { return false }
		package_text := ws_account_utf8(e,pkg)
		if package_text == nil || pending(e) { C.free(package_text); return false }
		class_text := ws_account_utf8(e,name)
		defer { C.free(package_text); C.free(class_text) }
		if pending(e) || package_text == nil || class_text == nil
			|| ws_auth_interaction(builder,package_text,class_text) != 0 { return false }
		bundle_ref := WsRef(slot(e,21))(e,bundle)
		if bundle_ref == nil || pending(e) {
			if bundle_ref != nil { Drop(slot(e,22))(e,bundle_ref) }
			return false
		}
		intent_ref := WsRef(slot(e,21))(e,intent)
		if intent_ref == nil || pending(e) {
			if bundle_ref != nil { Drop(slot(e,22))(e,bundle_ref) }
			if intent_ref != nil { Drop(slot(e,22))(e,intent_ref) }
			return false
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut node := ws_auth_slots
		for node != nil && Same(slot(e,24))(e,node.response,response) == 0 { node = node.next }
		installed := node != nil && ws_auth_handle != nil && node.bundle == nil && node.intent == nil
		if installed { node.bundle = bundle_ref; node.intent = intent_ref }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if !installed {
			Drop(slot(e,22))(e,bundle_ref); Drop(slot(e,22))(e,intent_ref)
			return true
		}
		if ws_auth_send(builder) != 0 { ws_auth_cancel(e,id) }
		return true
	}
}

fn ws_auth_result(e voidptr, response voidptr, bundle voidptr) {
	unsafe {
		if ws_auth_try_interaction(e,response,bundle) { return }
		if pending(e) { WsApplicationClear(slot(e,17))(e) }
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

// Transport has already validated the session capability, opaque local handle
// and explicit target before this main-Looper entry point can run.
fn ws_auth_launch(e voidptr, id u64) bool {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut node := ws_auth_slots
		for node != nil && node.id != id { node = node.next }
		mut bundle := voidptr(nil)
		mut intent := voidptr(nil)
		mut response := voidptr(nil)
		if node != nil && ws_auth_handle != nil && node.bundle != nil && node.intent != nil {
			bundle = WsRef(slot(e,25))(e,node.bundle)
			if bundle != nil && !pending(e) {
				intent = WsRef(slot(e,25))(e,node.intent)
				if intent != nil && !pending(e) { response = WsRef(slot(e,25))(e,node.response) }
			}
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		defer {
			if bundle != nil { Drop(slot(e,23))(e,bundle) }
			if intent != nil { Drop(slot(e,23))(e,intent) }
			if response != nil { Drop(slot(e,23))(e,response) }
		}
		if bundle == nil || intent == nil || response == nil || pending(e) { return false }
		again := ws_auth_extract(e,bundle,response)
		if again == nil || pending(e) || Same(slot(e,24))(e,again,intent) == 0 { return false }
		component := obj(e,intent,c'android/content/Intent',c'getComponent',c'()Landroid/content/ComponentName;',nil)
		if component == nil || pending(e) { return false }
		pkg := obj(e,component,c'android/content/ComponentName',c'getPackageName',c'()Ljava/lang/String;',nil)
		if pkg == nil || pending(e) { return false }
		name := obj(e,component,c'android/content/ComponentName',c'getClassName',c'()Ljava/lang/String;',nil)
		if name == nil || pending(e) { return false }
		package_text := ws_account_utf8(e,pkg)
		if package_text == nil || pending(e) { C.free(package_text); return false }
		class_text := ws_account_utf8(e,name)
		defer { C.free(package_text); C.free(class_text) }
		if package_text == nil || class_text == nil || pending(e) { return false }
		C.pthread_mutex_lock(&ws_auth_mutex)
		matches := ws_auth_handle != nil && ws_auth_launch_target(ws_auth_handle,id,package_text,class_text) == 0
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if !matches { return false }
		return ws_service_activity(e,intent,id)
	}
}

fn ws_auth_launch_failed(e voidptr, id u64) {
	unsafe {
		if pending(e) { WsApplicationClear(slot(e,17))(e) }
		C.pthread_mutex_lock(&ws_auth_mutex)
		builder := if ws_auth_handle == nil { voidptr(nil) } else { ws_auth_response(ws_auth_handle,id,2) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if builder != nil {
			if ws_auth_error_fields(builder,6,c'authenticator activity launch failed') { ws_auth_send(builder) }
			ws_auth_free(builder)
		}
		ws_auth_cancel(e,id)
	}
}

fn ws_auth_calling_uid() i32 {
	unsafe {
		if !ws_auth_ready { return -2 }
		C.pthread_mutex_lock(&ws_auth_mutex)
		allowed := ws != nil && ws_auth_worker_thread != 0
			&& usize(C.pthread_self()) == ws_auth_worker_thread && ws_auth_scope
		C.pthread_mutex_unlock(&ws_auth_mutex)
		return if allowed { i32(1000) } else { i32(-2) }
	}
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
		C.free(command.account_name); C.free(command.account_type); C.free(command.token_type)
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
		command.operation = ws_auth_operation(ws_auth_handle)
		name := ws_auth_type(ws_auth_handle)
		if command.operation != 1 && command.operation != 2 && command.operation != 4 && command.operation != 5 { ws_auth_command_free(command); return nil }
		if name != nil { command.account_type = C.strdup(name) }
		if command.operation == 5 {
			if name == nil || name[0] == 0 || command.account_type == nil { ws_auth_command_free(command); return nil }
			return command
		}
		account := ws_auth_name(ws_auth_handle)
		if account != nil { command.account_name = C.strdup(account) }
		token := ws_auth_token(ws_auth_handle)
		if token != nil { command.token_type = C.strdup(token) }
		command.feature_count = ws_auth_features(ws_auth_handle)
		command.count = ws_auth_count(ws_auth_handle)
		if command.feature_count > 32 || command.count > 35 {
			command.feature_count = 0; command.count = 0
			ws_auth_command_free(command); return nil
		}
		mut valid := (name == nil || command.account_type != nil) && (command.operation == 1 || name != nil) && (token == nil || command.token_type != nil)
			&& (account == nil || command.account_name != nil)
			&& (command.operation != 4 || (account != nil && account[0] != 0 && token != nil && token[0] != 0 && command.feature_count == 0))
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

// The normal store checks the exact account and root-authenticated requesting
// package against the active session. Denial never initializes APK classes.
// Return one for authorized, zero for a queued denial, minus one for failure.
fn ws_auth_token_check(id u64) i32 {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		allowed := ws_store_live() && ws_auth_token_authorized(ws_store_handle,ws_auth_handle,id) == 0
		failure := if allowed || ws_auth_handle == nil { voidptr(nil) } else { ws_auth_response(ws_auth_handle,id,2) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if allowed { return 1 }
		if failure == nil { return -1 }
		defer { ws_auth_free(failure) }
		if !ws_auth_error_fields(failure,7,c'account is unavailable to this caller') { return -1 }
		return if ws_auth_send(failure) == 0 { i32(0) } else { i32(-1) }
	}
}

fn ws_auth_dispatch(e voidptr, binder voidptr, command &WsAuthCommand) bool {
	unsafe {
		if command.operation == 1 { return ws_store_dispatch(command.id) }
		if command.operation == 5 { return ws_store_invalidate_dispatch(command.id) }
		if command.operation == 4 {
			status := ws_auth_token_check(command.id)
			if status != 1 { return status == 0 }
		}
		arg := &Value(C.alloca(sizeof(Value)))
		arg.l = binder
		authenticator := static_obj(e,c'android/accounts/IAccountAuthenticator$Stub',c'asInterface',c'(Landroid/os/IBinder;)Landroid/accounts/IAccountAuthenticator;',arg)
		if authenticator == nil || pending(e) { return false }
		constructor := &Value(C.alloca(sizeof(Value)))
		constructor.j = i64(command.id)
		response := new_object(e,c'android/atl/VinixAuthenticatorResponse',c'(J)V',constructor)
		bundle := ws_auth_bundle(e,command)
		if pending(e) || response == nil || bundle == nil { return false }
		mut account := voidptr(nil)
		mut features := voidptr(nil)
		if command.operation == 4 {
			identity := &Value(C.alloca(2 * sizeof(Value)))
			identity[0] = Value{l:ws_account_java_text(e,command.account_name)}
			identity[1] = Value{l:ws_account_java_text(e,command.account_type)}
			if pending(e) || identity[0].l == nil || identity[1].l == nil { return false }
			account = new_object(e,c'android/accounts/Account',c'(Ljava/lang/String;Ljava/lang/String;)V',identity)
			if pending(e) || account == nil { return false }
		} else {
			string_class := cls(e,c'java/lang/String')
			features = WsAuthArray(slot(e,172))(e,i32(command.feature_count),string_class,nil)
			Drop(slot(e,23))(e,string_class)
			for i := u32(0); i < command.feature_count && !pending(e); i++ {
				text := ws_account_java_text(e,command.features[i])
				WsArraySet(slot(e,174))(e,features,i32(i),text)
				Drop(slot(e,23))(e,text)
			}
			if pending(e) || features == nil { return false }
		}
		node := &WsAuthSlot(C.calloc(1,sizeof(WsAuthSlot)))
		if node == nil { return false }
		node.id = command.id
		node.response = WsRef(slot(e,21))(e,response)
		if node.response == nil { C.free(node); return false }
		C.pthread_mutex_lock(&ws_auth_mutex)
		if ws_auth_handle == nil || !ws_auth_worker_active_locked(command.id) {
			C.pthread_mutex_unlock(&ws_auth_mutex)
			ws_auth_slot_free(e,node)
			return true
		}
		node.next = ws_auth_slots; ws_auth_slots = node
		C.pthread_mutex_unlock(&ws_auth_mutex)
		args := &Value(C.alloca(5 * sizeof(Value)))
		args[0] = Value{l:response}
		args[1] = Value{l:if command.operation == 4 { account } else { ws_account_java_text(e,command.account_type) }}
		args[2] = Value{l:ws_account_java_text(e,command.token_type)}
		args[3] = Value{l:if command.operation == 4 { bundle } else { features }}
		args[4] = Value{l:bundle}
		if pending(e) || (command.operation == 4 && args[2].l == nil) { return false }
		return ws_auth_dispatch_call(e,authenticator,command.operation,args)
	}
}

// Synthetic Binder identity is scoped to this synchronous call on the exact
// dedicated worker; concurrent app and main threads retain their own identity.
fn ws_auth_dispatch_call(e voidptr, authenticator voidptr, operation u16, args &Value) bool {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		ws_auth_scope = true
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if operation == 4 {
			call(e,authenticator,c'android/accounts/IAccountAuthenticator',c'getAuthToken',c'(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)V',args)
		} else {
			call(e,authenticator,c'android/accounts/IAccountAuthenticator',c'addAccount',c'(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)V',args)
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		ws_auth_scope = false
		C.pthread_mutex_unlock(&ws_auth_mutex)
		return !pending(e)
	}
}

fn ws_auth_cancel(e voidptr, id u64) {
	unsafe {
		ws_auth_worker_cancel(id)
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut previous := &WsAuthSlot(nil)
		mut node := ws_auth_slots
		for node != nil && node.id != id { previous = node; node = node.next }
		if node != nil {
			if previous == nil { ws_auth_slots = node.next } else { previous.next = node.next }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if node != nil { ws_auth_slot_free(e,node) }
	}
}

// One bounded record on the terminal pump failure. Stage: 1 transport read,
// 2 Activity launch, 3 command copy, 4 command dispatch. No session/account data
// enters this record. The exception trace stays in the private service log.
fn ws_auth_pump_failure(e voidptr, stage i32, status i32) bool {
	unsafe {
		exception := pending(e)
		failure := if exception { WsApplicationException(slot(e,15))(e) } else { nil }
		buffer := &char(C.alloca(128))
		length := C.snprintf(buffer,128,c'ANDROID-AUTH-PUMP-FAIL stage=%d status=%d pending=%d\n',stage,status,i32(exception))
		if length > 0 && length < 128 { C.write(2,buffer,usize(length)) }
		// ExceptionDescribe clears pending. Restore the same Throwable so the
		// existing launch/shutdown cleanup retains ownership of clearing it.
		if failure != nil {
			ws_failure(e,c'ANDROID-SERVICE-FAIL account pump')
			WsApplicationThrow(slot(e,13))(e,failure)
			Drop(slot(e,23))(e,failure)
		}
		return false
	}
}

fn ws_account_service_pump(e voidptr, binder voidptr) bool {
	unsafe {
		if !ws_auth_ready { return true }
		worker_error := ws_auth_worker_error()
		if worker_error != 0 { return ws_auth_pump_failure(e,4,worker_error) }
		for _ in 0 .. 8 {
			mut id := u64(0)
			C.pthread_mutex_lock(&ws_auth_mutex)
			status := if ws_auth_handle == nil { i32(-1) } else { ws_auth_read(ws_auth_handle,&id,0) }
			command := if status == 1 { ws_auth_copy(id) } else { &WsAuthCommand(nil) }
			C.pthread_mutex_unlock(&ws_auth_mutex)
			if status < 0 { return ws_auth_pump_failure(e,1,status) }
			if status == 0 { return true }
			if status == 2 { ws_auth_cancel(e,id); continue }
			if status == 3 {
				if !ws_auth_launch(e,id) {
					ws_auth_pump_failure(e,2,status)
					ws_auth_launch_failed(e,id)
					return false
				}
				continue
			}
			if command == nil { return ws_auth_pump_failure(e,3,status) }
			mut transferred := false
			mut ok := true
			// An authenticator may synchronously query/invalidate its own store.
			// Those native-only operations must not wait behind its Java call.
			if command.operation == 1 || command.operation == 5 {
				ok = ws_auth_dispatch(e,binder,command)
			} else {
				transferred = ws_auth_worker_enqueue(e,binder,command)
				ok = transferred
			}
			if !transferred { ws_auth_command_free(command) }
			if !ok { return ws_auth_pump_failure(e,4,status) }
		}
		return true
	}
}

fn ws_account_service_shutdown(e voidptr) {
	unsafe {
		if !ws_auth_ready { return }
		ws_auth_worker_shutdown(e)
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut nodes := ws_auth_slots
		ws_auth_slots = nil
		ws_store_shutdown()
		handle := ws_auth_handle
		ws_auth_handle = nil
		// Response builders hold a transport reference, so callbacks already
		// copying a Bundle can finish safely and observe the closed handle.
		if handle != nil { ws_auth_close(handle) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		for nodes != nil {
			next := nodes.next
			ws_auth_slot_free(e,nodes); nodes = next
		}
	}
}
