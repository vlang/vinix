// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import os
import tools.packages.audiopcm

$if track_heap ? {
	#include "heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn audio_check(ok bool, message string) { if !ok { panic(message) } }
fn audio_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn audio_refuse(text string) {
	if mut request := decode(text) { request.close(); panic('accepted noncanonical audio transport') } else { audio_error(err) }
}

fn audio_fixture() Request {
	return Request{ format: 3, nonce: 'a'.repeat(32), arguments: ['run-args', 'org.tone', '--', '', '$(literal)', '\xff'],
		audio: audiopcm.Capability{ path: '/run/user/1000/vinix-audio-0123456789abcdef0123456789abcdef.sock', device: u64(-1), inode: 17, worker: 1234, generation: u64(-1), manifest: 'b'.repeat(64) } }
}

fn test_audio_transport_roundtrip_owns_fields_and_preserves_legacy_bytes() {
	request := audio_fixture()
	text := request.encode()!
	defer { unsafe { text.free() } }
	mut first := decode(text)!
	mut second := decode(text)!
	first.close()
	audio_check(second.format == 3 && second.audio == request.audio && second.arguments == request.arguments, 'owned audio roundtrip')
	second.close(); second.close()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut parsed := decode(text)!
		audio_check(parsed.audio == request.audio, 'repeated owned audio selection')
		parsed.close(); parsed.close()
	}
	$if track_heap ? { audio_check(C.vinix_heap_end() == 0, 'audio decode retains V storage') }
	$if track_heap ? { C.vinix_heap_begin() }
	for cut in 0 .. text.len { audio_refuse(unsafe { tos(text.str, cut) }) }
	$if track_heap ? { audio_check(C.vinix_heap_end() == 0, 'truncated audio decode retains V storage') }
	legacy := Request{ nonce: 'b'.repeat(32), arguments: ['run', 'org.tone'] }.encode()!
	legacy_expected := '{"format":1,"nonce":"' + 'b'.repeat(32) + '","arguments":["run","org.tone"]}'
	audio_check(legacy == legacy_expected, 'version one byte compatibility')
	display := Request{ format: 2, nonce: 'b'.repeat(32), arguments: ['run', 'org.tone'], display: ':42', authority: '/run/user/1000/vinix-hosted-x11/app/Xauthority' }.encode()!
	display_expected := '{"format":2,"nonce":"' + 'b'.repeat(32) + '","arguments":["run","org.tone"],"display":":42","authority":"/run/user/1000/vinix-hosted-x11/app/Xauthority"}'
	audio_check(display == display_expected, 'version two byte compatibility')
	unsafe { legacy.free(); legacy_expected.free(); display.free(); display_expected.free() }
}

fn test_audio_transport_refuses_malformed_identity_and_unknown_fields() {
	text := audio_fixture().encode()!
	defer { unsafe { text.free() } }
	for bad in [text + ' ', text.replace('"format":3', '"format":2'), text.replace('"audio":', '"environment":'),
		text.replace('"inode":17', '"inode":0'), text.replace('"inode":17', '"inode":017'), text.replace('"inode":17', '"inode":-1'),
		text.replace('"device":18446744073709551615', '"device":18446744073709551616'),
		text.replace('"worker":1234', '"worker":0'), text.replace('"worker":1234', '"worker":2147483648'),
		text.replace('"generation":18446744073709551615', '"generation":0'),
		text.replace('"manifest":', '"capture":true,"manifest":'),
		text.replace('bbbbbbbb', 'BBBBBBBB'), text.replace('/1000/', '/01000/'), text.replace('"display":""', '"display":":1"')] {
		audio_refuse(bad)
		unsafe { bad.free() }
	}
	for format in [1, 2, 4] {
		request := Request{ ...audio_fixture(), format: format }
		if value := request.encode() { unsafe { value.free() }; panic('accepted capability in older/unknown envelope') } else { audio_error(err) }
	}
}

fn test_audio_receipt_binds_entire_private_selection_and_refusal_clears_ambient() {
	request := audio_fixture()
	receipt := request.receipt(23)
	defer { unsafe { receipt.free() } }
	audio_check(request.result(receipt)! == 23, 'audio receipt positive control')
	for capability in [audiopcm.Capability{ ...request.audio, device: 7 }, audiopcm.Capability{ ...request.audio, inode: 18 },
		audiopcm.Capability{ ...request.audio, worker: 1235 }, audiopcm.Capability{ ...request.audio, generation: 42 },
		audiopcm.Capability{ ...request.audio, manifest: 'c'.repeat(64) }, audiopcm.Capability{ ...request.audio, path: request.audio.path.replace('0123', '1123') }] {
		changed := Request{ ...request, audio: capability }
		if _ := changed.result(receipt) { panic('receipt accepted another private selection') } else { audio_error(err) }
	}
	defer { audiopcm.clear_environment() }
	os.setenv('VINIX_AUDIO_SOCKET', 'ambient', true)
	os.setenv('VINIX_AUDIO_BOOTSTRAP_FD', '3', true)
	audio_check(Request{}.forward_audio(1000, -1)! == -1, 'no audio needs no bootstrap')
	audio_check(os.getenv('VINIX_AUDIO_SOCKET') == '' && os.getenv('VINIX_AUDIO_BOOTSTRAP_FD') == '', 'absent capability clears ambient audio')
	os.setenv('VINIX_AUDIO_SOCKET', 'ambient', true)
	if _ := request.forward_audio(1000, -1) { panic('forwarded nonexistent private endpoint') } else { audio_error(err) }
	audio_check(os.getenv('VINIX_AUDIO_SOCKET') == '' && os.getenv('VINIX_AUDIO_BOOTSTRAP_FD') == '', 'refused capability clears ambient audio')
}
