module nativeaccountauth

import time

fn C.socketpair(i32, i32, i32, &i32) i32
fn C.close(int) int
fn C.shutdown(i32, i32) i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32

#include <signal.h>
#include <sys/wait.h>

fn request_fixture() Request {
	return Request{
		id:              0xf123456789abcdef
		operation:       .add_account
		account_type:    'com.google'
		auth_token_type: none
		features:        ['service_mail']
		options:         [
			Option{'optional', Scalar{ kind: .null_value }},
			Option{'locale', Scalar{ kind: .text, text: 'en-GB' }},
			Option{'boolean', Scalar{ kind: .boolean, boolean: true }},
			Option{'minimum', Scalar{ kind: .int32, number: -2147483648 }},
			Option{'maximum', Scalar{ kind: .int32, number: 2147483647 }},
			Option{'longMinimum', Scalar{ kind: .int64, number: -9223372036854775807 - 1 }},
			Option{'longMaximum', Scalar{ kind: .int64, number: 9223372036854775807 }},
		]
	}
}

fn decode_frame(frame []u8) !Request {
	if frame.len < request_header_size { return error('short test frame') }
	return decode_request(frame[..request_header_size], frame[request_header_size..])
}

fn bad_frame(frame []u8) bool {
	decode_frame(frame) or { return true }
	return false
}

fn bad_request(request Request) bool {
	encode_request(request) or { return true }
	return false
}

fn wire_request(frame []u8, end_write bool, timeout time.Duration) !Request {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	if frame.len > 0 {
		assert C.send(sockets[1], frame.data, uint(frame.len), 0) == frame.len
	}
	if end_write {
		assert C.shutdown(sockets[1], C.SHUT_WR) == 0
	}
	return receive_request_frame(sockets[0], time.sys_mono_now() + timeout)
}

fn test_request_round_trip_preserves_nullable_and_scalar_types() {
	expected := request_fixture()
	encoded := encode_request(expected)!
	assert encoded[..8] == [u8(`V`), `X`, `A`, `1`, 0, 1, 0, 2]
	assert decode_frame(encoded)! == expected
	for account_type in [?string(none), ?string('com.google')] {
		request := Request{ id: 1, operation: .get_accounts, account_type: account_type }
		assert decode_frame(encode_request(request)!)! == request
	}
	request := Request{ id: 1, operation: .add_account, account_type: 'com.google', auth_token_type: '' }
	assert decode_frame(encode_request(request)!)! == request
}

fn test_request_rejects_every_truncation_and_header_corruption() {
	valid := encode_request(request_fixture())!
	for length in 0 .. valid.len {
		assert bad_frame(valid[..length])
	}
	for index in [0, 4, 5, 6, 7] {
		mut changed := valid.clone()
		changed[index] = 255
		assert bad_frame(changed)
	}
	mut zero_id := valid.clone()
	for index in 8 .. 16 { zero_id[index] = 0 }
	assert bad_frame(zero_id)
	mut oversized := valid.clone()
	oversized[16] = 1
	assert bad_frame(oversized)
	mut extra := valid.clone()
	extra << u8(0)
	assert bad_frame(extra)
	// A declared extra body byte is also rejected, rather than silently ignored.
	extra[19]++
	assert bad_frame(extra)
}

fn test_request_encoder_rejects_identity_injection_and_unbounded_data() {
	for key in ['callerUid', 'callerPid', 'androidPackageName', 'accountAuthenticatorResponse',
		'android.accounts.AccountAuthenticatorResponse', 'vinixCaller', 'vinixSession'] {
		assert bad_request(Request{
			id:           1
			operation:    .add_account
			account_type: 'com.google'
			options:      [Option{key, Scalar{ kind: .text, text: 'forged' }}]
		})
	}
	assert bad_request(Request{ id: 0, operation: .get_accounts })
	assert bad_request(Request{ id: 1, operation: .add_account })
	assert bad_request(Request{ id: 1, operation: .get_accounts, account_type: '' })
	assert bad_request(Request{ id: 1, operation: .get_accounts, features: ['a'] })
	assert bad_request(Request{ id: 1, operation: .add_account, account_type: 'com.google', features: [
		'a',
		'a',
	] })
	assert bad_request(Request{ id: 1, operation: .add_account, account_type: 'com.google', features: []string{len: 33, init: 'a'} })
	assert bad_request(Request{ id: 1, operation: .add_account, account_type: '\xff' })
	assert bad_request(Request{ id: 1, operation: .add_account, account_type: 'com\x00google' })
	assert bad_request(Request{ id: 1, operation: .add_account, account_type: 'x'.repeat(4097) })
	assert bad_request(Request{
		id:           1
		operation:    .add_account
		account_type: 'com.google'
		options:      [Option{'x', Scalar{ kind: .int32, number: 2147483648 }}]
	})
	assert bad_request(Request{
		id:           1
		operation:    .add_account
		account_type: 'com.google'
		options:      [Option{'x', Scalar{}}, Option{'x', Scalar{}}]
	})
	mut large_options := []Option{}
	for index in 0 .. 17 {
		large_options << Option{'field${index}', Scalar{ kind: .text, text: 'x'.repeat(4096) }}
	}
	assert bad_request(Request{
		id:           1
		operation:    .add_account
		account_type: 'com.google'
		options:      large_options
	})
}

fn test_request_decoder_rejects_duplicate_options_reserved_keys_and_bad_tags() {
	for key in ['callerUid', 'callerPid', 'androidPackageName', 'accountAuthenticatorResponse'] {
		mut body := []u8{}
		append_string(mut body, 'com.google')!
		append_string(mut body, none)!
		body << [u8(0), 1]
		append_string(mut body, key)!
		body << u8(0)
		mut header := encode_request(Request{ id: 1, operation: .add_account, account_type: 'com.google' })![..20].clone()
		for i in 0 .. 4 { header[16 + i] = u8(u32(body.len) >> ((3 - i) * 8)) }
		header << body
		assert bad_frame(header)
	}
	for tag in [u8(2), 5, 255] {
		mut frame := encode_request(Request{
			id:           1
			operation:    .add_account
			account_type: 'com.google'
			options:      [Option{'x', Scalar{ kind: .boolean, boolean: true }}]
		})!
		if tag == 2 { frame[frame.len - 1] = 2 } else { frame[frame.len - 2] = tag }
		assert bad_frame(frame)
	}
	mut duplicate := encode_request(Request{
		id:           1
		operation:    .add_account
		account_type: 'com.google'
		options:      [Option{'x', Scalar{}}, Option{'y', Scalar{}}]
	})!
	duplicate[duplicate.len - 2] = `x`
	assert bad_frame(duplicate)
}

fn test_request_stream_requires_exact_frame_and_actual_write_half_close() {
	valid := encode_request(request_fixture())!
	assert wire_request(valid, true, time.second)! == request_fixture()
	mut doubled := valid.clone()
	doubled << valid
	wire_request(doubled, true, time.second) or {
		assert err.msg().contains('trailing')
		return
	}
	assert false, 'coalesced frames accepted'
}

fn test_request_stream_rejects_missing_half_close_and_early_eof() {
	valid := encode_request(request_fixture())!
	for frame in [valid, valid[..10]] {
		wire_request(frame, false, 20 * time.millisecond) or {
			assert err.msg().contains('deadline') || err.msg().contains('unavailable')
			continue
		}
		assert false, 'unfinished request accepted'
	}
	wire_request(valid[..10], true, time.second) or {
		assert err.msg().contains('early')
		return
	}
	assert false, 'short request accepted'
}

fn test_request_stream_supports_fragmentation_and_rejects_delayed_trailing_bytes() {
	valid := encode_request(request_fixture())!
	for trailing in [false, true] {
		mut sockets := [2]i32{}
		assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
		child := C.fork()
		assert child >= 0
		if child == 0 {
			C.close(sockets[0])
			for byte in valid {
				if C.send(sockets[1], &byte, 1, 0) != 1 { C._exit(1) }
			}
			time.sleep(20 * time.millisecond)
			if trailing {
				byte := u8(255)
				if C.send(sockets[1], &byte, 1, 0) != 1 { C._exit(2) }
			}
			C.shutdown(sockets[1], C.SHUT_WR)
			C.close(sockets[1])
			C._exit(0)
		}
		C.close(sockets[1])
		defer {
			C.close(sockets[0])
			// Parent keeps the child unreaped until cleanup, so PID cannot be reused.
			C.kill(child, C.SIGKILL)
			mut status := i32(0)
			C.waitpid(child, &status, 0)
		}
		actual := receive_request_frame(sockets[0], time.sys_mono_now() + time.second) or {
			assert trailing && err.msg().contains('trailing')
			continue
		}
		assert !trailing && actual == request_fixture()
	}
}

fn test_request_public_boundary_rejects_unprivileged_broker_and_untrusted_server() {
	registry := Registry{}
	mut rejected := false
	registry.receive_request(-1, -1) or {
		rejected = true
		if C.getuid() != 0 || C.geteuid() != 0 {
			assert err.msg().contains('root broker')
		} else {
			assert err.msg().contains('separate channel')
		}
	}
	assert rejected
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	if C.getuid() != 0 {
		send_request(sockets[0], request_fixture()) or {
			assert err.msg().contains('root peer')
			return
		}
		assert false, 'untrusted server accepted'
	}
}
