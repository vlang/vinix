module pipe

// Moving bytes between descriptors without routing them through userspace:
// splice, tee, vmsplice and copy_file_range. They live here rather than in the
// file module because a splice needs a pipe, and pipe already builds on file.

import errno
import file
import memory
import usercopy

// splice(2)/vmsplice(2)/tee(2) flags. None of them change what happens here —
// there is no page stealing to ask for and nothing ever blocks on a gift — but
// an unknown one is still refused.
const splice_f_known = 0xf

// How much is moved per round trip. Bounded so that a caller asking to move a
// gigabyte does not ask the kernel for a gigabyte of bounce buffer.
const transfer_chunk = u64(16384)

// The pipe behind a descriptor, or none when it is not one.
fn pipe_from_fd(fd &file.FD) ?&Pipe {
	mut res := fd.handle.resource
	if mut res is Pipe {
		return res
	}
	return none
}

// splice(fd_in, off_in, fd_out, off_out, len, flags). At least one side has to
// be a pipe, which is what makes it splice rather than a general copy. The move
// happens through a kernel buffer rather than by handing pages over: there is
// no page stealing here, and the observable result is the same.
pub fn syscall_splice(_ voidptr, fd_in int, off_in u64, fd_out int, off_out u64, length u64, flags u32) (u64, u64) {
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

	source_pipe := pipe_from_fd(source) or { unsafe { nil } }
	sink_pipe := pipe_from_fd(sink) or { unsafe { nil } }

	if source_pipe == unsafe { nil } && sink_pipe == unsafe { nil } {
		return errno.err, errno.einval
	}
	// An offset only makes sense for the side that is not a pipe.
	if (source_pipe != unsafe { nil } && off_in != 0)
		|| (sink_pipe != unsafe { nil } && off_out != 0) {
		return errno.err, errno.espipe
	}

	return move_between(mut source, off_in, mut sink, off_out, length)
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

	mut source_pipe := pipe_from_fd(source) or { return errno.err, errno.einval }
	mut sink_pipe := pipe_from_fd(sink) or { return errno.err, errno.einval }

	if voidptr(source_pipe) == voidptr(sink_pipe) {
		return errno.err, errno.einval
	}

	mut want := length
	if want > source_pipe.available() {
		want = source_pipe.available()
	}
	if want > sink_pipe.room() {
		want = sink_pipe.room()
	}
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

	mut handle := fd.handle
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
	if flags != 0 {
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

	// Both sides must be ordinary files; a pipe is splice(2)'s business.
	if pipe_from_fd(source) != none || pipe_from_fd(sink) != none {
		return errno.err, errno.einval
	}

	return move_between(mut source, off_in, mut sink, off_out, length)
}

// The shared body of splice and copy_file_range: read a chunk, write it, repeat.
// An offset pointer, where given, is read and written back rather than the
// descriptor's own position being disturbed.
fn move_between(mut source file.FD, off_in u64, mut sink file.FD, off_out u64, length u64) (u64, u64) {
	mut source_offset := i64(0)
	mut sink_offset := i64(0)

	if off_in != 0 {
		if !usercopy.copy_from_user(voidptr(&source_offset), off_in, sizeof(i64)) {
			return errno.err, errno.efault
		}
		if source_offset < 0 {
			return errno.err, errno.einval
		}
	}
	if off_out != 0 {
		if !usercopy.copy_from_user(voidptr(&sink_offset), off_out, sizeof(i64)) {
			return errno.err, errno.efault
		}
		if sink_offset < 0 {
			return errno.err, errno.einval
		}
	}

	mut source_handle := source.handle
	mut sink_handle := sink.handle

	mut moved := u64(0)

	for moved < length {
		mut chunk := length - moved
		if chunk > transfer_chunk {
			chunk = transfer_chunk
		}

		buffer := memory.malloc(chunk)

		read_from := if off_in != 0 {
			u64(source_offset) + moved
		} else {
			u64(source_handle.loc)
		}
		got := source_handle.resource.read(voidptr(source_handle), buffer, read_from,
			chunk) or {
			unsafe { free(buffer) }
			if moved > 0 {
				break
			}
			return errno.err, errno.get()
		}
		if got <= 0 {
			unsafe { free(buffer) }
			break
		}

		write_to := if off_out != 0 {
			u64(sink_offset) + moved
		} else {
			u64(sink_handle.loc)
		}
		put := sink_handle.resource.write(voidptr(sink_handle), buffer, write_to, u64(got)) or {
			unsafe { free(buffer) }
			if moved > 0 {
				break
			}
			return errno.err, errno.get()
		}
		unsafe { free(buffer) }

		if put <= 0 {
			break
		}

		// Only a side without an explicit offset advances its descriptor.
		if off_in == 0 {
			source_handle.loc += put
		}
		if off_out == 0 {
			sink_handle.loc += put
		}

		moved += u64(put)

		if put < got {
			break
		}
	}

	if off_in != 0 {
		updated := source_offset + i64(moved)
		if !usercopy.copy_to_user(off_in, voidptr(&updated), sizeof(i64)) {
			return errno.err, errno.efault
		}
	}
	if off_out != 0 {
		updated := sink_offset + i64(moved)
		if !usercopy.copy_to_user(off_out, voidptr(&updated), sizeof(i64)) {
			return errno.err, errno.efault
		}
	}

	return moved, 0
}
