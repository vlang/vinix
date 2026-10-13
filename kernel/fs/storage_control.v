// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import aesxts
import errno
import event.eventstruct
import file
import kbudget
import katomic
import klock
import memory
import proc
import resource
import sched
import security
import stat
import usercopy

const volume_create = u64(0x56560001)
const volume_resize = u64(0x56560002)
const volume_remove = u64(0x56560003)
const volume_create_encrypted = u64(0x56560006)
const volume_limit = 64

struct VolumeRequest {
mut:
	version u32
	slot    u32
	offset  u64
	length  u64
	flags   u64
}

struct EncryptedVolumeRequest {
mut:
	data VolumeRequest
	key [64]u8
}

struct VolumeResourceBox {
mut:
	value resource.Resource
}

@[heap]
struct LogicalVolume {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
mut:
	charge        kbudget.Charge
	parent        &resource.Resource = unsafe { nil }
	box           &resource.Resource = unsafe { nil }
	identity      resource.BlockIdentity
	parent_offset u64
	slot          u32
	generation    u64
	readonly      bool
	removed       bool
	metrics       resource.BlockMetrics
	policy_token  int = -1
	encrypted     bool
	cipher        aesxts.Cipher
}

__global (
	logical_volumes           [volume_limit]&LogicalVolume
	logical_volumes_lock      klock.Lock
	logical_volume_generation u64
	encrypted_block_used      int
)

// Monotonic for the boot: an unencrypted RAM image must never persist keys
// or plaintext, including after a mapping has been closed or rejected.
pub fn block_encryption_used() bool { return katomic.load(&encrypted_block_used) != 0 }

fn volume_extent(parent resource.BlockIdentity, offset u64, bytes u64, sector u64) ?resource.BlockIdentity {
	if !parent.valid() || sector == 0 || bytes == 0 || offset % sector != 0
		|| bytes % sector != 0 || offset > parent.length || bytes > parent.length - offset
		|| bytes > u64(0x7fffffffffffffff) {
		errno.set(errno.einval)
		return none
	}
	return resource.BlockIdentity{
		is_block: true
		disk_id:  parent.disk_id
		start:    parent.start + offset
		length:   bytes
	}
}

fn volume_name(slot u32, buffer &u8) string {
	prefix := 'mapper/vinix'
	unsafe { C.memcpy(buffer, prefix.str, prefix.len) }
	mut length := prefix.len
	if slot >= 10 {
		unsafe { buffer[length] = u8(slot / 10) + `0` }
		length++
	}
	unsafe { buffer[length] = u8(slot % 10) + `0` }
	return unsafe { tos(buffer, length + 1) }
}

fn (volume &LogicalVolume) block_identity() resource.BlockIdentity {
	mut current := unsafe { volume }
	current.l.acquire()
	defer { current.l.release() }
	if current.removed { return resource.BlockIdentity{ is_block: true } }
	return current.identity
}

fn (volume &LogicalVolume) read_only_backend() bool { return volume.readonly }

fn (mut volume LogicalVolume) block_status() resource.BlockStatus {
	volume.l.acquire()
	defer { volume.l.release() }
	mut flags := resource.block_volume
	if volume.readonly { flags |= resource.block_readonly }
	if volume.removed { flags |= resource.block_offline }
	if volume.encrypted { flags |= resource.block_encrypted }
	if parent := resource.block_status(mut volume.parent) {
		flags |= parent.flags & (resource.block_offline | resource.block_flush | resource.block_discard)
	}
	if volume.encrypted { flags &= ~resource.block_discard }
	mut result := volume.metrics.snapshot(u64(volume.stat.size), u64(volume.stat.blksize), flags, volume.identity)
	result.slot = volume.slot
	result.generation = volume.generation
	return result
}

fn (mut volume LogicalVolume) open_owned(flags int) ?&resource.Resource {
	volume.l.acquire()
	defer { volume.l.release() }
	if volume.removed || volume.refcount == 0 {
		errno.set(errno.enodev)
		return none
	}
	if volume.readonly && flags & resource.o_accmode != resource.o_rdonly
		&& flags & resource.o_path == 0 {
		errno.set(errno.erofs)
		return none
	}
	for {
		refs := katomic.load(&volume.refcount)
		if refs == 0 {
			errno.set(errno.enodev)
			return none
		}
		if katomic.cas(mut &volume.refcount, refs, refs + 1) { break }
	}
	return volume.box
}

fn (mut volume LogicalVolume) transfer(buffer voidptr, offset u64, bytes u64, writing bool) ?i64 {
	// User faults may read an executable on this same volume. Never copy or
	// call its driver while holding an IRQ-masking volume lock over user data.
	if u64(buffer) < memory.user_address_limit() && bytes != 0 {
		volume.l.acquire()
		size := u64(volume.stat.size)
		sector := u64(volume.stat.blksize)
		removed := volume.removed
		invalid := offset > size || bytes > size - offset
			|| offset % sector != 0 || bytes % sector != 0
		volume.l.release()
		if removed {
			errno.set(errno.enodev)
			return none
		}
		if invalid {
			errno.set(errno.einval)
			return none
		}
		if buffer == unsafe { nil } || bytes > memory.user_address_limit() - u64(buffer) {
			errno.set(errno.efault)
			return none
		}
		charge := proc.reserve_kernel(.file, if bytes < 65536 { bytes } else { u64(65536) })?
		defer { kbudget.release(charge) }
		copy := memory.malloc_packed_fallible(if bytes < 65536 { bytes } else { u64(65536) }) @[freed]
		if copy == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
		defer { if volume.encrypted { aesxts.erase(copy, usize(if bytes < 65536 { bytes } else { u64(65536) })) }; memory.free(copy) }
		mut done := u64(0)
		for done < bytes {
			count := if bytes - done < 65536 { bytes - done } else { u64(65536) }
			if writing && !usercopy.copy_from_user(copy, u64(buffer) + done, count) {
				errno.set(errno.efault)
				return none
			}
			volume.transfer(copy, offset + done, count, writing)?
			if !writing && !usercopy.copy_to_user(u64(buffer) + done, copy, count) {
				errno.set(errno.efault)
				return none
			}
			done += count
		}
		return i64(bytes)
	}
	if volume.encrypted { return volume.encrypted_transfer(buffer, offset, bytes, writing) }
	volume.l.acquire()
	defer { volume.l.release() }
	if volume.removed {
		errno.set(errno.enodev)
		return none
	}
	if writing && volume.readonly {
		errno.set(errno.erofs)
		return none
	}
	size := u64(volume.stat.size)
	sector := u64(volume.stat.blksize)
	if offset > size || bytes > size - offset || offset % sector != 0 || bytes % sector != 0 {
		errno.set(errno.einval)
		return none
	}
	if bytes == 0 { return 0 }
	mut result := i64(0)
	if writing { result = volume.parent.write(unsafe { nil }, buffer, volume.parent_offset + offset, bytes) or { volume.metrics.failed(); return none } }
	else { result = volume.parent.read(unsafe { nil }, buffer, volume.parent_offset + offset, bytes) or { volume.metrics.failed(); return none } }
	if result != i64(bytes) {
		errno.set(errno.eio)
		volume.metrics.failed()
		return none
	}
	volume.metrics.completed(bytes, writing)
	return result
}

fn (mut volume LogicalVolume) read(_ voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	return volume.transfer(buffer, offset, bytes, false)
}

fn (mut volume LogicalVolume) write(_ voidptr, buffer voidptr, offset u64, bytes u64) ?i64 {
	return volume.transfer(buffer, offset, bytes, true)
}

fn (mut volume LogicalVolume) sync(_ voidptr) ? {
	volume.l.acquire()
	defer { volume.l.release() }
	if volume.removed {
		errno.set(errno.enodev)
		return none
	}
	resource.sync_resource(mut volume.parent, unsafe { nil }) or {
		volume.metrics.failed()
		return none
	}
	volume.metrics.flushed()
}

fn (mut volume LogicalVolume) discard(offset u64, bytes u64) ? {
	volume.l.acquire()
	defer { volume.l.release() }
	if volume.removed { errno.set(errno.enodev); return none }
	if volume.readonly { errno.set(errno.erofs); return none }
	if volume.encrypted { errno.set(errno.eopnotsupp); return none }
	if !resource.discard_range_valid(u64(volume.stat.size), u64(volume.stat.blksize), offset, bytes) {
		errno.set(errno.einval); return none
	}
	resource.discard_resource(mut volume.parent, volume.parent_offset + offset, bytes) or {
		volume.metrics.failed()
		return none
	}
}

fn (mut volume LogicalVolume) ioctl(handle voidptr, request u64, argument voidptr) ?int {
	return resource.default_ioctl(handle, request, argument)
}

fn (mut volume LogicalVolume) mmap(_ voidptr, _ u64, _ int) voidptr { return unsafe { nil } }

fn (mut volume LogicalVolume) grow(_ voidptr, _ u64) ? {
	errno.set(errno.eopnotsupp)
	return none
}

fn (mut volume LogicalVolume) link(_ voidptr) ? {
	errno.set(errno.eopnotsupp)
	return none
}

fn (mut volume LogicalVolume) unlink(_ voidptr) ? {
	errno.set(errno.eopnotsupp)
	return none
}

fn (mut volume LogicalVolume) unref(_ voidptr) ? {
	if !katomic.dec(mut &volume.refcount) {
		aesxts.clear(mut volume.cipher)
		release_resource_after_grace(volume.parent)
		free_after_grace(volume.box)
		free_charged_after_grace(volume, volume.charge)
	}
}

fn storage_request(request u64) bool {
	return request == volume_create || request == volume_resize || request == volume_remove
		|| request == volume_create_encrypted
		|| request == resource.block_status_ioctl || request == 0x80081272 || request == 0x1260
		|| request == 0x1268 || request == 0x125e
		|| request == resource.block_discard_ioctl
		|| request == resource.block_health_ioctl
}

fn storage_admin() bool {
	process := proc.current_thread().process
	return proc.mac_trusted() && proc.is_initial_namespace(process.ns.user)
		&& proc.has_capability(process, proc.cap_sys_admin)
}

fn storage_ioctl(mut descriptor file.FD, request u64, argument voidptr) ?int {
	if request == resource.block_health_ioctl { return storage_health(mut descriptor, argument) }
	if request == resource.block_discard_ioctl { return storage_discard(mut descriptor, argument) }
	if request != volume_create && request != volume_resize && request != volume_remove && request != volume_create_encrypted {
		snapshot := resource.block_status(mut descriptor.handle.resource)?
		if request == resource.block_status_ioctl {
			if !usercopy.copy_to_user(u64(argument), &snapshot, sizeof(snapshot)) {
				errno.set(errno.efault)
				return none
			}
		} else if request == 0x1268 || request == 0x125e {
			value := i32(if request == 0x1268 {
				snapshot.sector
			} else {
				snapshot.flags & resource.block_readonly
			})
			if !usercopy.copy_to_user(u64(argument), &value, sizeof(value)) {
				errno.set(errno.efault)
				return none
			}
		} else {
			value := if request == 0x1260 { snapshot.bytes / 512 } else { snapshot.bytes }
			if !usercopy.copy_to_user(u64(argument), &value, sizeof(value)) {
				errno.set(errno.efault)
				return none
			}
		}
		return 0
	}
	if !storage_admin() {
		errno.set(errno.eperm)
		return none
	}
	if request == volume_create_encrypted {
		katomic.store(mut &encrypted_block_used, 1)
		mut encrypted := EncryptedVolumeRequest{}
		defer { aesxts.erase(unsafe { &encrypted }, sizeof(encrypted)) }
		if !usercopy.copy_from_user(unsafe { &encrypted }, u64(argument), sizeof(encrypted)) { errno.set(errno.efault); return none }
		if encrypted.data.version != 1 { errno.set(errno.einval); return none }
		return create_encrypted_volume(mut descriptor, encrypted.data, unsafe { &encrypted.key })
	}
	mut data := VolumeRequest{}
	if request != volume_remove {
		if !usercopy.copy_from_user(&data, u64(argument), sizeof(data)) {
			errno.set(errno.efault)
			return none
		}
		if data.version != 1 {
			errno.set(errno.einval)
			return none
		}
	}
	if request == volume_create { return create_logical_volume(mut descriptor, data) }
	mut backend := descriptor.handle.resource
	if mut backend is LogicalVolume { return change_logical_volume(mut backend, request, data) }
	errno.set(errno.enotty)
	return none
}

fn storage_discard(mut descriptor file.FD, argument voidptr) ?int {
	if !storage_admin() { errno.set(errno.eperm); return none }
	if descriptor.handle.flags & resource.o_accmode != resource.o_rdwr
		&& descriptor.handle.flags & resource.o_accmode != resource.o_wronly {
		errno.set(errno.ebadf); return none
	}
	descriptor.handle.mac_check(proc.mac_write)?
	mut range := [2]u64{}
	if !usercopy.copy_from_user(&range[0], u64(argument), sizeof(range)) {
		errno.set(errno.efault); return none
	}
	mut backend := descriptor.handle.resource
	for {
		identity := resource.block_identity(mut backend)
		snapshot := resource.block_status(mut backend) or {
			if errno.get() == errno.enotty { errno.set(errno.eopnotsupp) }
			return none
		}
		if snapshot.flags & resource.block_offline != 0 { errno.set(errno.enodev); return none }
		if snapshot.flags & resource.block_readonly != 0 { errno.set(errno.erofs); return none }
		if snapshot.flags & resource.block_discard == 0 { errno.set(errno.eopnotsupp); return none }
		if !resource.discard_range_valid(snapshot.bytes, snapshot.sector, range[0], range[1]) {
			errno.set(errno.einval); return none
		}
		token := security.begin_block_discard(identity) or {
			if identity != resource.block_identity(mut backend) { continue }
			return none
		}
		if identity != resource.block_identity(mut backend) {
			security.end_block_reconfigure(token)
			continue
		}
		defer { security.end_block_reconfigure(token) }
		// Keep every batch sector aligned, including devices whose logical
		// sector is larger than the usual 64 KiB batch size.
		batch_bytes := if snapshot.sector > 65536 {
			snapshot.sector
		} else {
			u64(65536) - u64(65536) % snapshot.sector
		}
		mut done := u64(0)
		for done < range[1] {
			current := proc.current_thread()
			if katomic.load(&current.must_exit) || current.process.exiting
				|| proc.pending_signals(current) & ~current.masked_signals != 0 {
				errno.set(errno.eintr); return none
			}
			if security.securelevel() >= 2 { errno.set(errno.eperm); return none }
			// Keep the reservation and descriptor across bounded device calls,
			// but release volume/driver locks before yielding or handling signals.
			count := if range[1] - done < batch_bytes { range[1] - done } else { batch_bytes }
			resource.discard_resource(mut backend, range[0] + done, count)?
			done += count
			if done < range[1] { sched.yield(true) }
		}
		return 0
	}
	return none
}

fn create_logical_volume(mut descriptor file.FD, data VolumeRequest) ?int {
	return create_volume(mut descriptor, data, unsafe { nil })
}

fn create_encrypted_volume(mut descriptor file.FD, data VolumeRequest, key &[64]u8) ?int {
	katomic.store(mut &encrypted_block_used, 1)
	mut cipher := unsafe { &aesxts.Cipher(C.vinix_stack_alloc(sizeof(aesxts.Cipher))) }; unsafe { *cipher = aesxts.Cipher{} }
	defer { aesxts.clear(mut cipher) }
	if !aesxts.initialize(mut cipher, key) { errno.set(errno.einval); return none }
	return create_volume(mut descriptor, data, cipher)
}

fn create_volume(mut descriptor file.FD, data VolumeRequest, cipher &aesxts.Cipher) ?int {
	if data.slot >= volume_limit || data.flags & ~u64(1) != 0 {
		errno.set(errno.einval)
		return none
	}
	mut parent := descriptor.handle.resource
	info := resource.block_status(mut parent)?
	if info.flags & (resource.block_volume | resource.block_offline) != 0 {
		errno.set(errno.enodev)
		return none
	}
	readonly := data.flags & 1 != 0
	if !readonly && (info.flags & resource.block_readonly != 0
		|| descriptor.handle.flags & resource.o_accmode != resource.o_rdwr) {
		errno.set(errno.erofs)
		return none
	}
	if descriptor.handle.flags & resource.o_path != 0 {
		errno.set(errno.ebadf)
		return none
	}
	if readonly && descriptor.handle.flags & resource.o_accmode == resource.o_wronly {
		errno.set(errno.ebadf)
		return none
	}
	if info.sector == 0 || info.sector > 4096 || 4096 % info.sector != 0
		|| info.bytes != resource.block_identity(mut parent).length {
		errno.set(errno.einval)
		return none
	}
	if cipher != unsafe { nil } && info.sector != 512 && info.sector != 4096 { errno.set(errno.einval); return none }
	descriptor.handle.mac_check(if readonly { proc.mac_read } else { proc.mac_write })?
	identity := volume_extent(resource.block_identity(mut parent), data.offset, data.length, info.sector)?
	logical_volumes_lock.acquire()
	defer { logical_volumes_lock.release() }
	if logical_volumes[data.slot] != unsafe { nil } {
		errno.set(errno.eexist)
		return none
	}
	for existing in logical_volumes {
		if existing != unsafe { nil } && identity.overlaps(existing.identity) {
			errno.set(errno.ebusy)
			return none
		}
	}
	token := security.begin_block_reconfigure(identity)?
	defer { security.end_block_reconfigure(token) }
	if logical_volume_generation == u64(-1) {
		errno.set(errno.eoverflow)
		return none
	}
	charge := proc.reserve_kernel(.file, 8192)?
	mut owned := false
	defer { if !owned { kbudget.release(charge) } }
	policy_token := security.register_dynamic_block_device(identity)?
	mut published := false
	defer { if !published { security.release_dynamic_block_device(policy_token) } }
	mut volume := unsafe { &LogicalVolume(memory.malloc_packed_fallible(sizeof(LogicalVolume))) } @[freed]
	if volume == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	storage := memory.malloc_packed_fallible(sizeof(VolumeResourceBox)) @[freed]
	if storage == unsafe { nil } {
		memory.free(volume)
		errno.set(errno.enomem)
		return none
	}
	owned_box := unsafe { &VolumeResourceBox(storage) }
	box := &owned_box.value
	logical_volume_generation++
	unsafe {
		*volume = LogicalVolume{
			charge:        charge
			parent:        parent
			box:           box
			refcount:      2
			identity:      identity
			policy_token:  policy_token
			parent_offset: data.offset
			slot:          data.slot
			generation:    logical_volume_generation
			readonly:      readonly
		}
	}
	volume.stat.mode = stat.ifblk | if readonly { u32(0o440) } else { u32(0o600) }
	if cipher != unsafe { nil } { volume.encrypted = true; volume.cipher = unsafe { *cipher } }
	volume.stat.rdev = resource.create_dev_id()
	volume.stat.size = i64(data.length)
	volume.stat.blocks = i64(data.length / 512)
	volume.stat.blksize = i64(info.sector)
	unsafe { *box = resource.Resource(volume) }
	resource.retain_resource(mut parent)
	mut name := [32]u8{}
	devtmpfs_add_volume(box, volume_name(data.slot, &name[0])) or {
		resource.release_resource(mut parent)
		aesxts.clear(mut volume.cipher)
		memory.free(box)
		memory.free(volume)
		return none
	}
	logical_volumes[data.slot] = volume
	published = true
	owned = true
	return 0
}

fn change_logical_volume(mut volume LogicalVolume, request u64, data VolumeRequest) ?int {
	logical_volumes_lock.acquire()
	defer { logical_volumes_lock.release() }
	if voidptr(logical_volumes[volume.slot]) != voidptr(volume) {
		errno.set(errno.enodev)
		return none
	}
	mut identity := volume.identity
	if request == volume_resize {
		if data.slot != 0 || data.offset != 0 || data.flags != 0 || data.length < identity.length {
			errno.set(errno.einval)
			return none
		}
		identity = volume_extent(resource.block_identity(mut volume.parent), volume.parent_offset,
			data.length, u64(volume.stat.blksize))?
		for existing in logical_volumes {
			if existing != unsafe { nil } && voidptr(existing) != voidptr(volume) && identity.overlaps(existing.identity) {
				errno.set(errno.ebusy)
				return none
			}
		}
	}
	token := security.begin_block_reconfigure(identity)?
	defer { security.end_block_reconfigure(token) }
	volume.l.acquire()
	if request == volume_resize {
		volume.l.release()
		new_policy := security.register_dynamic_block_device(identity)?
		volume.l.acquire()
		old_policy := volume.policy_token
		volume.policy_token = new_policy
		volume.identity = identity
		volume.stat.size = i64(identity.length)
		volume.stat.blocks = i64(identity.length / 512)
		volume.l.release()
		security.release_dynamic_block_device(old_policy)
	} else {
		volume.removed = true
		volume.l.release()
		mut name := [32]u8{}
		if !devtmpfs_remove_device(volume_name(volume.slot, &name[0]), volume.box) {
			volume.l.acquire()
			volume.removed = false
			volume.l.release()
			errno.set(errno.ebusy)
			return none
		}
		security.release_dynamic_block_device(volume.policy_token)
		volume.l.acquire(); aesxts.clear(mut volume.cipher); volume.l.release()
		volume.policy_token = -1
		logical_volumes[volume.slot] = unsafe { nil }
		volume.unref(unsafe { nil })?
	}
	return 0
}
