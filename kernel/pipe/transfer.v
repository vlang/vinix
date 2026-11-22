// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module pipe

// Moving bytes between descriptors without routing them through userspace:
// splice, tee, vmsplice and copy_file_range. They live here rather than in the
// file module because a splice needs a pipe, and pipe already builds on file.

import errno
import event
import file
import proc
import memory
import resource
import security
import stat
import usercopy

// splice(2)/vmsplice(2)/tee(2) flags. None of them change what happens here —
// there is no page stealing to ask for and nothing ever blocks on a gift — but
// an unknown one is still refused.
const splice_f_known = 0xf
const splice_f_nonblock = 2

// How much is moved per round trip. Bounded so that a caller asking to move a
// gigabyte does not ask the kernel for a gigabyte of bounce buffer.
const transfer_chunk = u64(16384)

// Whether a descriptor was opened for reading, or for writing. These calls
// went straight to the files' own read and write, which do not look, so
// anyone could write a file they could only open for reading, or a FIFO
// another user reads, by copying, splicing or vmsplicing into it, and read
// one opened only for writing.
fn readable(fd &file.FD) bool {
	access := fd.handle.flags & resource.o_accmode
	return access == resource.o_rdonly || access == resource.o_rdwr
}

fn writable(fd &file.FD) bool {
	access := fd.handle.flags & resource.o_accmode
	return access == resource.o_wronly || access == resource.o_rdwr
}

// The pipe behind a descriptor, or none when it is not one.
pub fn pipe_from_fd(fd &file.FD) ?&Pipe {
	mut res := fd.handle.resource
	if mut res is Pipe {
		return res
	}
	return none
}

// The caller pins the writer for the entire wait and subsequent transfer.
pub fn (mut sink Pipe) wait_transfer_room(nonblocking bool) ?u64 {
	mut broken := false
	sink.l.acquire()
	defer {
		sink.l.release()
		if broken { queue_broken_pipe_signal() }
	}
	for {
		if sink.readers == 0 {
			broken = true
			errno.set(errno.epipe)
			return none
		}
		room := sink.room()
		if room != 0 {
			return room
		}
		if nonblocking {
			errno.set(errno.eagain)
			return none
		}
		generation := event.generation(mut sink.event)
		sink.l.release()
		event.await_one_from_generation(mut sink.event, true, generation) or {
			sink.l.acquire()
			errno.set(proc.interrupted_errno)
			return none
		}
		sink.l.acquire()
	}
}

fn (mut source Pipe) wait_transfer_input(nonblocking bool) ?u64 {
	source.l.acquire()
	defer { source.l.release() }
	source.wait_readable_locked(nonblocking)?
	return source.used
}

// splice(fd_in, off_in, fd_out, off_out, len, flags). At least one side has to
// be a pipe, which is what makes it splice rather than a general copy. The move
// happens through a kernel buffer rather than by handing pages over: there is
// no page stealing here, and the observable result is the same.
pub fn syscall_splice(_ voidptr, fd_in int, off_in u64, fd_out int, off_out u64, length u64, flags u32) (u64, u64) {
	if length == 0 {
		return 0, 0
	}
	if flags & ~u32(splice_f_known) != 0 {
		return errno.err, errno.einval
	}

	mut source := file.fd_from_fdnum(unsafe { nil }, int(i32(fd_in))) or { return errno.err, errno.ebadf }
	defer {
		source.unref()
	}
	mut sink := file.fd_from_fdnum(unsafe { nil }, int(i32(fd_out))) or { return errno.err, errno.ebadf }
	defer {
		sink.unref()
	}

	if (source.handle.flags | sink.handle.flags) & resource.o_path != 0 {
		return errno.err, errno.ebadf
	}

	source_pipe := pipe_from_fd(source) or { unsafe { nil } }
	sink_pipe := pipe_from_fd(sink) or { unsafe { nil } }
	// An offset only makes sense for the side that is not a pipe.
	if (source_pipe != unsafe { nil } && off_in != 0)
		|| (sink_pipe != unsafe { nil } && off_out != 0) {
		return errno.err, errno.espipe
	}
	sink_offset := read_transfer_offset(off_out) or { return errno.err, errno.efault }
	source_offset := read_transfer_offset(off_in) or { return errno.err, errno.efault }
	if !readable(source) || !writable(sink) {
		return errno.err, errno.ebadf
	}
	if (source_pipe == unsafe { nil } && sink_pipe == unsafe { nil })
		|| (source_pipe != unsafe { nil } && voidptr(source_pipe) == voidptr(sink_pipe))
		|| sink.handle.flags & resource.o_append != 0 {
		return errno.err, errno.einval
	}

	return move_between(mut source, source_offset, mut sink, sink_offset, length, flags)
}

// tee(fd_in, fd_out, len, flags): copy between two pipes and leave the source
// as it was, so the same bytes can still be read from it.
pub fn syscall_tee(_ voidptr, fd_in int, fd_out int, length u64, flags u32) (u64, u64) {
	if flags & ~u32(splice_f_known) != 0 {
		return errno.err, errno.einval
	}
	if length == 0 {
		return 0, 0
	}

	mut source := file.fd_from_fdnum(unsafe { nil }, fd_in) or { return errno.err, errno.ebadf }
	defer {
		source.unref()
	}
	mut sink := file.fd_from_fdnum(unsafe { nil }, fd_out) or { return errno.err, errno.ebadf }
	defer {
		sink.unref()
	}

	if !readable(source) || !writable(sink) {
		return errno.err, errno.ebadf
	}
	source.handle.mac_check(proc.mac_read) or { return errno.err, errno.get() }
	sink.handle.mac_check(proc.mac_write) or { return errno.err, errno.get() }
	mut source_pipe := pipe_from_fd(source) or { return errno.err, errno.einval }
	mut sink_pipe := pipe_from_fd(sink) or { return errno.err, errno.einval }

	if voidptr(source_pipe) == voidptr(sink_pipe) {
		return errno.err, errno.einval
	}

	nonblocking := flags & splice_f_nonblock != 0
		|| (source.handle.flags | sink.handle.flags) & resource.o_nonblock != 0
	available := source_pipe.wait_transfer_input(nonblocking) or { return errno.err, errno.get() }
	room := sink_pipe.wait_transfer_room(nonblocking) or { return errno.err, errno.get() }
	mut want := if length < available { length } else { available }
	if want > room { want = room }
	if want == 0 {
		return 0, 0
	}
	if want > transfer_chunk {
		want = transfer_chunk
	}

	buffer := memory.malloc(want)
	defer {
		unsafe { free(buffer) }
	}

	peeked := source_pipe.peek(buffer, want)
	if peeked == 0 {
		return 0, 0
	}

	mut handle := sink.handle
	written := handle.resource.write(voidptr(handle), buffer, 0, peeked) or {
		return errno.err, errno.get()
	}

	return u64(written), 0
}

// vmsplice(fd, iov, nr_segs, flags): move a program's own pages into a pipe.
// Only the write direction is served; reading into user memory this way is
// what read(2) already does.
pub fn syscall_vmsplice(_ voidptr, fdnum int, iov u64, nr_segs u64, flags u32) (u64, u64) {
	if flags & ~u32(splice_f_known) != 0 {
		return errno.err, errno.einval
	}
	if nr_segs == 0 {
		return 0, 0
	}
	if nr_segs > 1024 {
		return errno.err, errno.einval
	}

	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.ebadf }
	defer {
		fd.unref()
	}

	pipe_from_fd(fd) or { return errno.err, errno.ebadf }
	// It only ever puts the caller's memory into the pipe.
	if !writable(fd) {
		return errno.err, errno.ebadf
	}

	mut handle := fd.handle
	handle.mac_check(proc.mac_write) or { return errno.err, errno.get() }
	mut total := u64(0)

	for i := u64(0); i < nr_segs; i++ {
		mut entry := [2]u64{}
		if !usercopy.copy_from_user(voidptr(&entry[0]), iov + i * 16, 16) {
			if total > 0 {
				return total, 0
			}
			return errno.err, errno.efault
		}
		base := entry[0]
		mut remaining := entry[1]

		for remaining > 0 {
			mut chunk := remaining
			if chunk > transfer_chunk {
				chunk = transfer_chunk
			}
			buffer := memory.malloc(chunk)
			if !usercopy.copy_from_user(buffer, base + (entry[1] - remaining), chunk) {
				unsafe { free(buffer) }
				if total > 0 {
					return total, 0
				}
				return errno.err, errno.efault
			}
			written := handle.resource.write(voidptr(handle), buffer, 0, chunk) or {
				unsafe { free(buffer) }
				if total > 0 {
					return total, 0
				}
				return errno.err, errno.get()
			}
			unsafe { free(buffer) }
			if written <= 0 {
				return total, 0
			}
			total += u64(written)
			remaining -= u64(written)
			if u64(written) < chunk {
				return total, 0
			}
		}
	}

	return total, 0
}

// copy_file_range(fd_in, off_in, fd_out, off_out, len, flags): copy between two
// files without the bytes passing through the caller.
pub fn syscall_copy_file_range(_ voidptr, fd_in int, off_in u64, fd_out int, off_out u64, length u64, flags u32) (u64, u64) {
	mut source := file.fd_from_fdnum(unsafe { nil }, int(i32(fd_in))) or { return errno.err, errno.ebadf }
	defer {
		source.unref()
	}
	mut sink := file.fd_from_fdnum(unsafe { nil }, int(i32(fd_out))) or { return errno.err, errno.ebadf }
	defer {
		sink.unref()
	}
	if (source.handle.flags | sink.handle.flags) & resource.o_path != 0 {
		return errno.err, errno.ebadf
	}
	source_offset := read_transfer_offset(off_in) or { return errno.err, errno.efault }
	sink_offset := read_transfer_offset(off_out) or { return errno.err, errno.efault }
	if flags != 0 {
		return errno.err, errno.einval
	}

	source_mode := source.handle.resource.stat.mode
	sink_mode := sink.handle.resource.stat.mode
	if stat.isdir(source_mode) || stat.isdir(sink_mode) {
		return errno.err, errno.eisdir
	}
	if !stat.isreg(source_mode) || !stat.isreg(sink_mode) {
		return errno.err, errno.einval
	}
	// As on Linux, an O_APPEND file cannot be written at an offset this way.
	if !readable(source) || !writable(sink) || sink.handle.flags & resource.o_append != 0 {
		return errno.err, errno.ebadf
	}

	return move_between(mut source, source_offset, mut sink, sink_offset, length, 0)
}

struct TransferOffset {
	address u64
	value i64
}

fn read_transfer_offset(address u64) ?TransferOffset {
	mut value := i64(0)
	if address != 0 && !usercopy.copy_from_user(unsafe { &value }, address, sizeof(i64)) {
		return none
	}
	return TransferOffset{address: address, value: value}
}

// An explicit offset is written back instead of advancing the description.
fn move_between(mut source file.FD, source_offset TransferOffset, mut sink file.FD, sink_offset TransferOffset, length u64, flags u32) (u64, u64) {
	if source_offset.value < 0 || sink_offset.value < 0
		|| sink.handle.resource is resource.NoByteIOResource {
		return errno.err, errno.einval
	}

	mut source_handle := source.handle
	mut sink_handle := sink.handle
	source_handle.mac_check(proc.mac_read) or { return errno.err, errno.get() }
	sink_handle.mac_check(proc.mac_write) or { return errno.err, errno.get() }
	if length == 0 {
		return 0, 0
	}
	mut source_pipe := pipe_from_fd(source) or { unsafe { nil } }
	mut sink_pipe := pipe_from_fd(sink) or { unsafe { nil } }
	source_without_io := source_handle.resource is resource.NoByteIOResource
	nonblocking := flags & splice_f_nonblock != 0 || sink_handle.flags & resource.o_nonblock != 0
		|| (source_pipe != unsafe { nil } && source_handle.flags & resource.o_nonblock != 0)

	mut moved := u64(0)

	for moved < length {
		mut chunk := length - moved
		if chunk > transfer_chunk { chunk = transfer_chunk }
		if sink_pipe != unsafe { nil } {
			if source_pipe != unsafe { nil } {
				source_pipe.wait_transfer_input(nonblocking || moved != 0) or {
					if moved != 0 { break }
					return errno.err, errno.get()
				}
			}
			room := sink_pipe.wait_transfer_room(nonblocking || moved != 0) or {
				if moved != 0 { break }
				return errno.err, errno.get()
			}
			if chunk > room { chunk = room }
		}
		if source_without_io { return errno.err, errno.einval }
		// Authorize before reading a pipe: a refused disk sink must leave
		// its input untouched. Hold the scalar reservation through the read
		// and write so a mount cannot publish over an in-flight raw transfer.
		block_token := security.begin_user_device_write(mut sink_handle.resource) or {
			if moved > 0 { break }
			return errno.err, errno.get()
		}
		buffer := memory.malloc(chunk)

		read_from := if source_offset.address != 0 {
			u64(source_offset.value) + moved
		} else {
			u64(source_handle.loc)
		}
		got := source_handle.resource.read(voidptr(source_handle), buffer, read_from,
			chunk) or {
			unsafe { free(buffer) }
			security.end_user_device_write(block_token)
			if moved > 0 {
				break
			}
			return errno.err, errno.get()
		}
		if got <= 0 {
			unsafe { free(buffer) }
			security.end_user_device_write(block_token)
			break
		}

		write_to := if sink_offset.address != 0 {
			u64(sink_offset.value) + moved
		} else {
			u64(sink_handle.loc)
		}
		put := sink_handle.resource.write(voidptr(sink_handle), buffer, write_to, u64(got)) or {
			unsafe { free(buffer) }
			security.end_user_device_write(block_token)
			if moved > 0 {
				break
			}
			return errno.err, errno.get()
		}
		unsafe { free(buffer) }
		security.end_user_device_write(block_token)

		if put <= 0 {
			break
		}

		// Only a side without an explicit offset advances its descriptor.
		if source_offset.address == 0 {
			source_handle.loc += put
		}
		if sink_offset.address == 0 {
			sink_handle.loc += put
		}

		moved += u64(put)

		if put < got {
			break
		}
	}

	if source_offset.address != 0 {
		updated := source_offset.value + i64(moved)
		if !usercopy.copy_to_user(source_offset.address, voidptr(&updated), sizeof(i64)) {
			return errno.err, errno.efault
		}
	}
	if sink_offset.address != 0 {
		updated := sink_offset.value + i64(moved)
		if !usercopy.copy_to_user(sink_offset.address, voidptr(&updated), sizeof(i64)) {
			return errno.err, errno.efault
		}
	}

	return moved, 0
}
