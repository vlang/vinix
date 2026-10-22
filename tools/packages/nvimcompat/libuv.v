// SPDX-License-Identifier: GPL-2.0-or-later
module nvimcompat

pub const libuv_define = 'VINIX_LIBUV_NO_IO_URING'
pub const libuv_original = 'static int uv__use_io_uring(uint32_t flags) {\n#if defined(__ANDROID_API__)\n  return 0;  /* Possibly available but blocked by seccomp. */'
pub const libuv_replacement = 'static int uv__use_io_uring(uint32_t flags) {\n#if defined(__ANDROID_API__) || defined(VINIX_LIBUV_NO_IO_URING)\n  return 0;  /* Possibly available but blocked by seccomp. */'

// Select libuv's existing no-io_uring implementation for Vinix. In 1.52.1,
// UV_USE_IO_URING=0 controls SQPOLL only; epoll batching probes a ring first.
// Refuse drift or a second application rather than guessing at upstream code.
pub fn libuv_linux(source string) !string {
	if source.contains(libuv_define) || source.count(libuv_original) != 1 {
		return error('libuv compatibility branch differs from the pinned source')
	}
	return source.replace(libuv_original, libuv_replacement)
}
