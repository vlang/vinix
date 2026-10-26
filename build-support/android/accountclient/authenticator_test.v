// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient
import accountipc
import nativeaccountauth
import time
#include <sys/socket.h>
fn C.socketpair(i32,i32,i32,&i32) i32
fn C.getuid() u32
fn C.close(i32) i32

fn auth_pair() (&Authenticator, &accountipc.Stream) {
	mut fds := [i32(-1),i32(-1)]!
	assert C.socketpair(C.AF_UNIX,C.SOCK_STREAM,0,&fds[0]) == 0
	return &Authenticator{stream:accountipc.open_stream(int(fds[0])) or { panic(err) }},
		accountipc.open_stream(int(fds[1])) or { panic(err) }
}
fn auth_dispatch(mut peer accountipc.Stream, id u64) {
	wire := accountipc.encode_command(accountipc.Command{
		session:id, capability:[]u8{len:32,init:u8(id)}
		caller:nativeaccountauth.Caller{'org.vinix.app',10001,10001,1234,'a'.repeat(64),'b'.repeat(64)}
		request:nativeaccountauth.Request{id:77,operation:.add_account,account_type:'com.google',features:['feature'],options:[nativeaccountauth.Option{'fixture',nativeaccountauth.Scalar{kind:.text,text:'value'}}]}
	}) or { panic(err) }
	defer { unsafe { wire.free() } }
	peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
}
fn test_authenticator_identity_scalars_continuation_and_exact_session() {
	mut owner, mut peer := auth_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	auth_dispatch(mut peer,7)
	mut id := u64(0)
	assert auth_read(owner,&id,0) == 1 && id == 7
	assert auth_caller_uid(owner) == 10001 && auth_caller_pid(owner) == 1234
	assert unsafe { cstring_to_vstring(auth_caller_package(owner)) } == 'org.vinix.app'
	assert unsafe { cstring_to_vstring(auth_account_type(owner)) } == 'com.google'
	assert auth_token_type(owner) == unsafe { nil }
	assert auth_feature_count(owner) == 1 && auth_count(owner) == 4
	assert unsafe { cstring_to_vstring(auth_key(owner,1)) } == 'callerUid'
	assert auth_number(owner,1) == 10001 && auth_number(owner,2) == 1234
	assert unsafe { cstring_to_vstring(auth_text(owner,3)) } == 'org.vinix.app'
	assert auth_response(owner,8,1) == unsafe { nil }
	invalid_interaction := auth_response(owner,7,4)
	assert auth_response_send(invalid_interaction) == -1
	auth_response_free(invalid_interaction)
	continued := auth_response(owner,7,5)
	assert auth_response_option(continued,c'bad',0,unsafe { nil },0) == -1
	assert auth_response_send(continued) == 0
	auth_response_free(continued)
	assert auth_read(owner,&id,0) == 0
	packet := peer.read(0) or { panic(err) }
	assert packet.available && packet.header.kind == .continued
	unsafe { packet.body.free() }
	result := auth_response(owner,7,1)
	assert auth_response_option(result,c'name',1,c'Zoë 🌍',0) == 0
	assert auth_response_option(result,c'name',0,unsafe { nil },0) == -1
	assert auth_response_option(result,c'badbool',2,unsafe { nil },2) == -1
	assert auth_response_option(result,c'badint',3,unsafe { nil },2147483648) == -1
	assert auth_response_send(result) == 0 && auth_response_send(result) == -1
	auth_response_free(result)
	assert auth_read(owner,&id,0) == 0
	returned := peer.read(0) or { panic(err) }
	decoded := accountipc.decode_event(returned.header,returned.body,true) or { panic(err) }
	defer { accountipc.dispose_event(decoded); unsafe { returned.body.free() } }
	assert decoded.id == 7 && decoded.kind == .result && decoded.options[0].value.text == 'Zoë 🌍'
	assert owner.sessions.len == 0 && owner.current == unsafe { nil }
}

fn test_authenticator_cancellation_expiration_and_builder_survives_close() {
	mut owner, mut peer := auth_pair()
	defer { peer.close(); unsafe { free(peer) } }
	auth_dispatch(mut peer,9)
	mut id := u64(0)
	assert auth_read(owner,&id,0) == 1
	late := auth_response(owner,9,1)
	wire := accountipc.encode_event(accountipc.Event{kind:.cancel,id:9,capability:[]u8{len:32,init:9}},true) or { panic(err) }
	peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
	unsafe { wire.free() }
	assert auth_read(owner,&id,0) == 2 && id == 9
	assert auth_response_send(late) == -1
	auth_response_free(late)
	auth_dispatch(mut peer,10)
	assert auth_read(owner,&id,0) == 1
	assert auth_read(owner,&id,0) == 0 // release borrowed current getter view
	old := owner.sessions[10] or { panic('missing session') }
	owner.sessions[10] = &AuthSession{command:old.command,started:time.sys_mono_now() - 5*time.minute}
	unsafe { free(old) }
	assert auth_read(owner,&id,0) == 2 && id == 10
	auth_dispatch(mut peer,11)
	assert auth_read(owner,&id,0) == 1
	last := auth_response(owner,11,1)
	auth_close(owner)
	assert auth_response_send(last) == -1
	auth_response_free(last)
}

fn test_authenticator_rejects_forged_cancel_duplicate_and_nonroot_open() {
	for forged in [true,false] {
		mut owner, mut peer := auth_pair()
		auth_dispatch(mut peer,7)
		mut id := u64(0)
		assert auth_read(owner,&id,0) == 1
		if forged {
			wire := accountipc.encode_event(accountipc.Event{kind:.cancel,id:7,capability:[]u8{len:32,init:8}},true) or { panic(err) }
			peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
			unsafe { wire.free() }
		} else { auth_dispatch(mut peer,7) }
		assert auth_read(owner,&id,0) == -1 && owner.closed && owner.sessions.len == 0
		auth_close(owner); peer.close(); unsafe { free(peer) }
	}
	if C.getuid() != 0 {
		mut fds := [i32(-1),i32(-1)]!
		assert C.socketpair(C.AF_UNIX,C.SOCK_STREAM,0,&fds[0]) == 0
		assert auth_open(fds[0]) == unsafe { nil }
		C.close(fds[0]); C.close(fds[1])
	}
}

fn test_authenticator_interaction_bound_launch_and_final_response() {
	mut owner, mut peer := auth_pair()
	defer { auth_close(owner); peer.close(); unsafe { free(peer) } }
	auth_dispatch(mut peer,7)
	mut id := u64(0)
	assert auth_read(owner,&id,0) == 1
	mut frame := []u8{len:64}
	defer { unsafe { frame.free() } }
	frame[0] = `W`; frame[1] = `S`; frame[2] = `U`; frame[3] = `I`; frame[5] = 1; frame[15] = 7
	for i in 16 .. 48 { frame[i] = 7 }
	assert auth_ui_authority(owner,7,frame.data,u32(frame.len)) == -1
	assert auth_launch_target(owner,7,c'com.google.android.gms',c'com.google.android.gms.auth.AccountIntroActivity') == -1
	interaction := auth_response(owner,7,4)
	assert auth_response_interaction(interaction,c'com.google.android.gms',c'com.google.android.gms.auth.AccountIntroActivity') == 0
	assert auth_response_send(interaction) == 0
	assert auth_response_send(interaction) == -1
	auth_response_free(interaction)
	assert auth_read(owner,&id,0) == 0
	packet := peer.read(0) or { panic(err) }
	event := accountipc.decode_event(packet.header,packet.body,true) or { panic(err) }
	defer { accountipc.dispose_event(event); unsafe { packet.body.free() } }
	assert event.kind == .interaction && event.interaction.handle.len == 32
	wire := accountipc.encode_launch(accountipc.Launch{7,event.capability,event.interaction}) or { panic(err) }
	defer { unsafe { wire.free() } }
	peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
	assert auth_read(owner,&id,0) == 3 && id == 7
	assert auth_launch_target(owner,7,c'com.google.android.gms',c'com.google.android.gms.auth.AccountIntroActivity') == 0
	assert auth_launch_target(owner,7,c'com.google.android.gms',c'com.google.android.gms.auth.OtherActivity') == -1
	assert auth_launch_target(owner,7,c'org.other',c'com.google.android.gms.auth.AccountIntroActivity') == -1
	assert auth_ui_authority(owner,8,frame.data,64) == -1
	assert auth_ui_authority(owner,7,frame.data,63) == -1
	frame[16] ^= 1
	assert auth_ui_authority(owner,7,frame.data,64) == -1
	frame[16] ^= 1
	for index in [0,4,6,60] {
		frame[index] ^= 1
		assert auth_ui_authority(owner,7,frame.data,64) == -1
		frame[index] ^= 1
	}
	assert auth_ui_authority(owner,7,frame.data,64) == 0
	assert auth_ui_authority(owner,7,frame.data,64) == -1
	result := auth_response(owner,7,1)
	assert auth_response_option(result,c'authAccount',1,c'fixture@example.test',0) == 0
	assert auth_response_send(result) == 0
	auth_response_free(result)
	assert auth_read(owner,&id,0) == 0
	assert owner.sessions.len == 0
	assert auth_ui_authority(owner,7,frame.data,64) == -1
	assert auth_launch_target(owner,7,c'com.google.android.gms',c'com.google.android.gms.auth.AccountIntroActivity') == -1
}

fn test_authenticator_rejects_forged_or_replayed_launch() {
	for variant in ['replay','handle','capability','package','class'] {
		mut owner, mut peer := auth_pair()
		auth_dispatch(mut peer,7)
		mut id := u64(0)
		assert auth_read(owner,&id,0) == 1
		response := auth_response(owner,7,4)
		assert auth_response_interaction(response,c'com.google.android.gms',c'com.google.android.gms.auth.AccountIntroActivity') == 0
		assert auth_response_send(response) == 0
		auth_response_free(response)
		assert auth_read(owner,&id,0) == 0
		packet := peer.read(0) or { panic(err) }
		event := accountipc.decode_event(packet.header,packet.body,true) or { panic(err) }
		mut opaque := event.interaction.handle.clone()
		mut capability := event.capability.clone()
		if variant == 'handle' { opaque[0] ^= 1 }
		if variant == 'capability' { capability[0] ^= 1 }
		pkg := if variant == 'package' { 'org.other' } else { event.interaction.target_package }
		name := if variant == 'class' { 'OtherActivity' } else { event.interaction.target_class }
		wire := accountipc.encode_launch(accountipc.Launch{7,capability,accountipc.Interaction{opaque,pkg,name}}) or { panic(err) }
		peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
		if variant == 'replay' {
			assert auth_read(owner,&id,0) == 3
			peer.enqueue(wire) or { panic(err) }; peer.flush() or { panic(err) }
		}
		assert auth_read(owner,&id,0) == -1 && owner.closed
		accountipc.dispose_event(event)
		unsafe { packet.body.free(); opaque.free(); capability.free(); wire.free() }
		auth_close(owner); peer.close(); unsafe { free(peer) }
	}
}
