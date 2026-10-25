// SPDX-License-Identifier: GPL-2.0-or-later
module audiopcm

import crypto.sha256
import os

// Fixed kernel-generated decimal files, read without following a final link
// or accepting a truncated number. No path comes from the request.
fn login_number(path string) !u32 {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('audio login identity unavailable') }
	defer { C.close(fd) }
	mut bytes := [12]u8{}
	mut used := 0
	for used < bytes.len {
		count := C.read(fd, unsafe { &bytes[used] }, usize(bytes.len - used))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('audio login identity unavailable') }
		if count == 0 { break }
		used += int(count)
	}
	if used < 2 || used == bytes.len || bytes[used - 1] != `\n` { return error('invalid audio login identity') }
	value := decimal(unsafe { tos(&bytes[0], used - 1) })!
	if value == 0 || value > 0xffff_ffff { return error('invalid audio login identity') }
	return u32(value)
}

// The account action is callable by an ordinary user. Its authenticated
// transport peer and the selected worker must still belong to that user's
// active immutable seat login; an isolated app cannot mint its own handoff.
pub fn account_admission(capability Capability, uid u32, transport int) ! {
	if C.geteuid() != 0 || !capability.valid_binding() { return error('audio admission requires the account service') }
	identity := peer(transport)!
	if identity.uid != uid || identity.pid <= 0 || identity.pid == capability.worker { return error('invalid ordinary audio launcher') }
	seat := login_number('/proc/sys/kernel/seat_session')!
	if !active_login(peer_login(transport)!, uid, seat) { return error('audio launcher is outside the active ordinary login') }
	// Connect to the exact admitted inode. The listener creator's cached login
	// label proves its origin even after exit or numeric PID reuse. This root
	// probe sends no protocol request and never opens the output device.
	worker := endpoint_connection(capability, uid)!
	defer { C.close(worker) }
	if !active_login(peer_login(worker)!, uid, seat) { return error('audio worker is outside the active ordinary login') }
	if login_number('/proc/sys/kernel/seat_session')! != seat { return error('audio seat changed during admission') }
}

fn (capability Capability) proof(id string) string {
	device := capability.device.str()
	inode := capability.inode.str()
	worker := capability.worker.str()
	generation := capability.generation.str()
	text := 'VINIX-AUDIO-BOOTSTRAP-1\n' + id + '\n' + capability.path + '\n' + device + '\n' + inode + '\n' + worker + '\n' + generation + '\n' + capability.manifest
	defer { unsafe { device.free(); inode.free(); worker.free(); generation.free(); text.free() } }
	bytes := text.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut sum)
	return sum.hex()
}

// The authenticated account worker makes this pair while still root. Only
// the isolated package launcher receives its read endpoint as descriptor 3.
// Cached socket peer credentials authenticate the proof after root is shed.
pub fn root_bootstrap(capability Capability, id string) !int {
	if C.geteuid() != 0 || !capability.valid_binding() { return error('audio bootstrap requires the account service') }
	mut pair := [2]i32{}
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pair[0]) != 0 { return error('cannot create authenticated audio handoff') }
	defer { C.close(pair[0]) }
	mut accepted := false
	defer { if !accepted { C.close(pair[1]) } }
	nonblocking(pair[0])!
	nonblocking(pair[1])!
	proof := capability.proof(id)
	defer { unsafe { proof.free() } }
	write_exact(pair[0], proof.str, proof.len, -1)!
	accepted = true
	return pair[1]
}

pub fn consume_bootstrap(capability Capability, id string) ! {
	value := os.getenv('VINIX_AUDIO_BOOTSTRAP_FD')
	defer { unsafe { value.free() }; os.unsetenv('VINIX_AUDIO_BOOTSTRAP_FD'); os.unsetenv('VINIX_SESSION_FD') }
	if value != '3' { return error('audio endpoint has no authenticated account handoff') }
	defer { C.close(3) }
	identity := peer(3)!
	if identity.uid != 0 { return error('audio handoff is not from the account service') }
	mut bytes := [64]u8{}
	read_exact(3, &bytes[0], bytes.len, -1)!
	proof := capability.proof(id)
	defer { unsafe { proof.free() } }
	for index, byte in proof { if bytes[index] != byte { return error('audio handoff selection changed') } }
}

// A declaration/policy change may remove audio between the two signed reads.
// Retire a recognized one-use handoff before continuing without audio.
pub fn discard_bootstrap() {
	value := os.getenv('VINIX_AUDIO_BOOTSTRAP_FD')
	defer { unsafe { value.free() } }
	if value == '3' { C.close(3); os.unsetenv('VINIX_SESSION_FD') }
	clear_environment()
}
