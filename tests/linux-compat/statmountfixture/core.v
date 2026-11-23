// SPDX-License-Identifier: GPL-2.0-or-later
module statmountfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.__errno_location() &i32
fn C.alloca(usize) voidptr
fn C._exit(i32)
fn C.chdir(&char) i32
fn C.chroot(&char) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.mkdir(&char, u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.rename(&char, &char) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(i64, ...) i64
fn C.umount2(&char, i32) i32
fn C.unshare(i32) i32
fn C.waitpid(i32, &i32, i32) i32

const all_fields = u64(0x7f)
const mnt_basic = u64(2)
const mnt_point = u64(0x10)
const fs_type = u64(0x20)
const ns_id = u64(0x40)
const ordinary_id = u64(0x1000)
const unique_id = u64(0x4000)
const sys_statmount = i64(457)
const sys_listmount = i64(458)

struct Request {
mut:
	size u32 = 32
	spare u32
	id u64
	param u64
	namespace_id u64
}

struct Result {
mut:
	size u32
	mnt_opts u32
	mask u64
	sb_dev_major u32
	sb_dev_minor u32
	sb_magic u64
	sb_flags u32
	fs_type u32
	mnt_id u64
	mnt_parent_id u64
	mnt_id_old u32
	mnt_parent_id_old u32
	mnt_attr u64
	mnt_propagation u64
	mnt_peer_group u64
	mnt_master u64
	propagate_from u64
	mnt_root u32
	mnt_point u32
	mnt_ns_id u64
	reserved [49]u64
}

struct Output {
mut:
	header Result
	strings [2048]u8
}

struct MountIds {
	unique u64
	ordinary u64
	device u64
}

fn need(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX STATMOUNT FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn query(request voidptr, output voidptr, size u64, flags u64) i64 {
	result := C.syscall(sys_statmount, request, output, size, flags)
	return if result >= 0 { result } else { unsafe { -i64(*C.__errno_location()) } }
}

fn path_mount_ids(path &char) MountIds {
	unsafe {
		mut words := [32]u64{}
		ret := C.syscall(i64(C.SYS_statx), i64(C.AT_FDCWD), path, u64(0), ordinary_id, &words[0])
		need(ret == 0 && words[0] & ordinary_id != 0 && words[18] != 0, c'get ordinary mount ID')
		ordinary := words[18]
		next := C.syscall(i64(C.SYS_statx), i64(C.AT_FDCWD), path, u64(0), unique_id, &words[0])
		need(next == 0 && words[0] & unique_id != 0 && words[18] != 0, c'get unique mount ID')
		return MountIds{unique: words[18], ordinary: ordinary, device: words[17]}
	}
}

fn check_string(output &Output, offset u32, expected &char) {
	unsafe {
		need(output.header.size > sizeof(Result) && output.header.size <= sizeof(Output), c'valid total size')
		need(offset > 0 && offset < output.header.size - sizeof(Result), c'string offset is in the buffer')
		need(output.strings[0] == 0 && output.strings[output.header.size - sizeof(Result) - 1] == 0,
			c'string area starts and ends with NUL')
		need(C.strcmp(&char(&output.strings[offset]), expected) == 0, c'string matches the requested mount')
	}
}

fn check_abi(id u64) {
	unsafe {
		mut output := &Output(C.alloca(sizeof(Output)))
		*output = Output{}
		mut req := Request{id: id, param: mnt_basic}
		need(query(nil, nil, 0, 1) == -C.EINVAL, c'flags precede request copy')
		need(query(nil, nil, 0, 0) == -C.EFAULT, c'missing request')
		req.size = 23
		need(query(&req, nil, 0, 0) == -C.EINVAL, c'reject short request')
		req.size = 24
		req.namespace_id = u64(-1)
		need(query(&req, output, 16, u64(1) << 32) == 0 && output.header.size == 16
			&& output.header.mask == mnt_basic && output.header.mnt_id == 0,
			c'version zero and short numeric output, using the low flag word')
		req.size = 32
		need(query(&req, output, sizeof(Output), 0) == -C.ENOENT, c'unknown namespace')
		req.namespace_id = 0
		need(query(&req, nil, 0, 0) == 0, c'zero-sized numeric output')
		need(query(&req, voidptr(1), sizeof(Result), 0) == -C.EFAULT, c'bad output address')
		req.id = u64(-1)
		need(query(&req, output, sizeof(Result), 0) == -C.ENOENT, c'unknown mount ID')
		req.id = id
		req.param = u64(1) << 63
		need(query(&req, output, sizeof(Result), 0) == 0 && output.header.mask == 0,
			c'unknown result bits are ignored')
		req.param = fs_type
		output.header.size = 0x57
		need(query(&req, output, sizeof(Result), 0) == -C.EOVERFLOW && output.header.size == 0x57,
			c'missing string space preserves output')
		need(query(&req, output, sizeof(Result) + 6, 0) == -C.EOVERFLOW && output.header.size == 0x57,
			c'short string buffer preserves output')
		need(query(&req, output, sizeof(Result) + 7, 0) == 0 && output.header.size == sizeof(Result) + 7,
			c'exact fit includes sentinel and terminator')
		check_string(output, output.header.fs_type, c'tmpfs')
	}
}

fn check_mount(ids MountIds, parent MountIds, root &char, point &char) u64 {
	unsafe {
		req := Request{id: ids.unique, param: all_fields}
		mut output := &Output(C.alloca(sizeof(Output)))
		*output = Output{}
		need(query(&req, output, sizeof(Output), 0) == 0 && output.header.mask == all_fields,
			c'statmount returns the requested fields')
		need(output.header.mnt_id == ids.unique && output.header.mnt_parent_id == parent.unique
			&& output.header.mnt_id_old == ids.ordinary && output.header.mnt_parent_id_old == parent.ordinary,
			c'attachment IDs agree with statx and identify the parent')
		need(output.header.sb_magic == 0x01021994 && output.header.sb_flags == 0
			&& ((u64(output.header.sb_dev_minor) << 32) | u64(output.header.sb_dev_major)) == ids.device,
			c'tmpfs superblock metadata agrees with statx')
		need(output.header.mnt_attr & 0x1e == 0x1e && output.header.mnt_propagation == u64(C.MS_PRIVATE)
			&& output.header.mnt_master == 0 && output.header.mnt_peer_group == 0
			&& output.header.propagate_from == 0, c'mount attributes and private propagation')
		for word in output.header.reserved { need(word == 0, c'header padding is zero') }
		check_string(output, output.header.fs_type, c'tmpfs')
		check_string(output, output.header.mnt_root, root)
		check_string(output, output.header.mnt_point, point)
		need(output.header.mnt_ns_id != 0, c'mount namespace ID is present')
		return output.header.mnt_ns_id
	}
}

fn check_namespace(parent u64, namespace u64) {
	unsafe {
		mut request := Request{id: parent, param: ns_id, namespace_id: namespace}
		mut output := &Output(C.alloca(sizeof(Output)))
		*output = Output{}
		need(query(&request, output, sizeof(Result), 0) == 0 && output.header.mnt_ns_id == namespace,
			c'explicit current namespace round-trips through statmount')
		request.param = 0
		mut ids := [4]u64{}
		need(C.syscall(sys_listmount, &request, &ids[0], u64(4), u64(0)) == 2,
			c'explicit current namespace round-trips through listmount')
		child := C.fork()
		need(child >= 0, c'fork namespace probe')
		if child == 0 {
			need(C.unshare(C.CLONE_NEWNS) == 0, c'copy namespace')
			request = Request{id: parent, param: ns_id}
			need(query(&request, output, sizeof(Result), 0) == -C.ENOENT, c'old mount ID is outside copy')
			request.id = path_mount_ids(c'/tmp/statmount').unique
			need(query(&request, output, sizeof(Result), 0) == 0 && output.header.mnt_ns_id != namespace,
				c'new mount belongs to a distinct namespace')
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'namespace probe passed')
	}
}

fn check_chroot(id u64, outside u64) {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork chroot probe')
		if child == 0 {
			need(C.chroot(c'/tmp/statmount/target') == 0 && C.chdir(c'/') == 0, c'enter chroot')
			need(C.setgid(1000) == 0 && C.setuid(1000) == 0, c'drop capabilities')
			mut request := Request{id: id, param: mnt_point}
			mut output := &Output(C.alloca(sizeof(Output)))
			*output = Output{}
			need(query(&request, output, sizeof(Output), 0) == 0, c'inside mount is visible')
			check_string(output, output.header.mnt_point, c'/new name')
			request.id = outside
			need(query(&request, output, sizeof(Output), 0) == -C.EPERM, c'outside mount needs capability')
			C._exit(0)
		}
		mut status := i32(0)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'chroot probe passed')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		need(sizeof(Result) == 512, c'fixed header ABI size')
		need(C.mkdir(c'/tmp/statmount', 0o755) == 0
			&& C.mount(c'tmpfs', c'/tmp/statmount', c'tmpfs',
				C.MS_NOATIME | C.MS_NODEV | C.MS_NOEXEC | C.MS_NOSUID, nil) == 0, c'attach primary tmpfs')
		need(C.mkdir(c'/tmp/statmount/tree name', 0o755) == 0 && C.mkdir(c'/tmp/statmount/alias', 0o755) == 0
			&& C.mkdir(c'/tmp/statmount/target', 0o755) == 0, c'prepare bind and move targets')
		need(C.mount(c'tmpfs', c'/tmp/statmount/target', c'tmpfs', 0, nil) == 0
			&& C.mkdir(c'/tmp/statmount/target/new name', 0o755) == 0, c'attach destination tmpfs')
		need(C.mount(c'/tmp/statmount/tree name', c'/tmp/statmount/alias', nil, C.MS_BIND, nil) == 0,
			c'bind a subdirectory')
		parent := path_mount_ids(c'/tmp/statmount')
		mounted := path_mount_ids(c'/tmp/statmount/alias')
		check_abi(mounted.unique)
		namespace := check_mount(mounted, parent, c'/tree name', c'/tmp/statmount/alias')
		check_namespace(parent.unique, namespace)
		need(C.rename(c'/tmp/statmount/tree name', c'/tmp/statmount/renamed') == 0, c'rename the bind source')
		need(C.mount(c'/tmp/statmount/alias', c'/tmp/statmount/target/new name', nil, C.MS_MOVE, nil) == 0,
			c'move the bind attachment')
		destination := path_mount_ids(c'/tmp/statmount/target')
		check_mount(mounted, destination, c'/renamed', c'/tmp/statmount/target/new name')
		check_chroot(mounted.unique, parent.unique)
		need(C.umount2(c'/tmp/statmount/target/new name', C.MNT_DETACH) == 0, c'detach bind mount')
		req := Request{id: mounted.unique, param: mnt_basic}
		mut output := &Output(C.alloca(sizeof(Output)))
		*output = Output{}
		need(query(&req, output, sizeof(Output), 0) == -C.ENOENT, c'detached identifier is absent')
		C.puts(c'LINUX STATMOUNT SUMMARY: paths=distinct namespaces=checked move=preserved')
		C.puts(if reference { c'LINUX STATMOUNT REFERENCE: PASS' } else { c'LINUX STATMOUNT: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
