// SPDX-License-Identifier: GPL-2.0-or-later
module memfdcreatefixture

#include <sys/xattr.h>

fn C.fchmod(i32, u32) i32
fn C.chmod(&char, u32) i32
fn C.fsetxattr(i32, &char, voidptr, u64, i32) i32

const mfd_noexec_seal = u64(8)
const f_seal_exec = 0x20
const nr_fchmodat2 = i64(452)

fn mode_of(fd i32) u32 {
	mut metadata := C.stat{}
	need(C.fstat(fd, &metadata) == 0, c'get memfd mode')
	return metadata.st_mode & 0o7777
}

fn check_noexec() {
	unsafe {
		need(create(nil, mfd_exec | mfd_noexec_seal) == -C.EINVAL, c'conflicting execution flags precede name faults')
		fd := create(c'nonexecutable', (u64(0xcafe) << 32) | mfd_noexec_seal | mfd_cloexec)
		need(fd >= 0, c'create with MFD_NOEXEC_SEAL')
		need(mode_of(fd) == 0o666 && C.fcntl(fd, C.F_GETFD) == C.FD_CLOEXEC
			&& C.fcntl(fd, f_get_seals) == f_seal_exec, c'initial mode, descriptor flags and execution seal')
		need(C.fchmod(fd, 0o777) == -1 && *C.__errno_location() == C.EPERM
			&& mode_of(fd) == 0o666, c'fchmod refuses execute bits')
		need(C.fchmod(fd, 0o640) == 0 && mode_of(fd) == 0o640, c'change read and write bits with execution sealed')
		mut path := [48]char{}
		C.snprintf(&path[0], path.len, c'/proc/self/fd/%d', fd)
		need(C.chmod(&path[0], 0o740) == -1 && *C.__errno_location() == C.EPERM,
			c'path-based chmod refuses execute bits')
		alias := C.open(&path[0], C.O_PATH | C.O_CLOEXEC)
		need(alias >= 0 && C.syscall(nr_fchmodat2, alias, c'', 0o650, C.AT_EMPTY_PATH) == -1
			&& *C.__errno_location() == C.EPERM && C.close(alias) == 0,
			c'empty-path chmod on O_PATH preserves execution seal')
		readonly := C.open(&path[0], C.O_RDONLY | C.O_CLOEXEC)
		need(readonly >= 0 && C.fcntl(readonly, f_get_seals) == f_seal_exec
			&& C.fcntl(readonly, f_add_seals, f_seal_grow) == -1 && *C.__errno_location() == C.EPERM
			&& C.close(readonly) == 0, c'read-only aliases can query seals and cannot add them')
		page := C.sysconf(C._SC_PAGESIZE)
		need(page > 0 && C.ftruncate(fd, page) == 0 && C.write(fd, c'm', 1) == 1,
			c'nonexecutable file remains writable and resizable')
		mapping := C.mmap(nil, u64(page), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
		need(i64(mapping) != -1 && *(&u8(mapping)) == `m`, c'shared writable mapping remains available')
		need(C.munmap(mapping, u64(page)) == 0, c'unmap writable view')
		executable := C.mmap(nil, u64(page), C.PROT_READ | C.PROT_EXEC, C.MAP_PRIVATE, fd, 0)
		need(i64(executable) != -1 && C.munmap(executable, u64(page)) == 0, c'execution seal preserves mmap protections')
		need(C.fcntl(fd, f_add_seals, f_seal_grow | f_seal_seal) == 0
			&& C.fcntl(fd, f_get_seals) == (f_seal_exec | f_seal_grow | f_seal_seal),
			c'NOEXEC_SEAL permits further seals without MFD_ALLOW_SEALING')
		need(C.ftruncate(fd, page + 1) == -1 && *C.__errno_location() == C.EPERM
			&& C.close(fd) == 0, c'additional seal enforces size limit')
		explicit := create(c'nonexecutable-sealing', mfd_noexec_seal | mfd_allow_sealing)
		need(explicit >= 0 && C.fcntl(explicit, f_get_seals) == f_seal_exec && C.close(explicit) == 0,
			c'MFD_NOEXEC_SEAL combines with MFD_ALLOW_SEALING')
		manual := create(c'manual-execution-seal', mfd_allow_sealing)
		need(manual >= 0 && C.fchmod(manual, 0o600) == 0
			&& C.fcntl(manual, f_add_seals, f_seal_exec) == 0 && C.fcntl(manual, f_get_seals) == f_seal_exec,
			c'explicit execution seal on nonexecutable memfd')
		need(C.fchmod(manual, 0o700) == -1 && *C.__errno_location() == C.EPERM
			&& mode_of(manual) == 0o600 && C.close(manual) == 0, c'explicit seal also locks execute bits')
	}
}

struct AclEntry {
	tag u16
mut:
	permissions u16
	id u32 = u32(-1)
}

struct AccessAcl {
	version u32 = 2
mut:
	entries [3]AclEntry
}

fn check_noexec_acl() {
	unsafe {
		fd := create(c'nonexecutable-acl', mfd_noexec_seal)
		need(fd >= 0, c'create execution-sealed memfd for ACL test')
		mut acl := AccessAcl{entries: [AclEntry{tag: 1, permissions: 6}, AclEntry{tag: 4, permissions: 4}, AclEntry{tag: 32}]!}
		name := c'system.posix_acl_access'
		need(C.fsetxattr(fd, name, voidptr(&acl), sizeof(AccessAcl), 0) == 0 && mode_of(fd) == 0o640,
			c'ACL can narrow read and write permissions')
		acl.entries[0].permissions = 7
		need(C.fsetxattr(fd, name, voidptr(&acl), sizeof(AccessAcl), 0) == -1
			&& *C.__errno_location() == C.EPERM && mode_of(fd) == 0o640 && C.close(fd) == 0,
			c'ACL mode update honors the execution seal')
		C.puts(c'LINUX MEMFDCREATE ACL: PASS')
	}
}
