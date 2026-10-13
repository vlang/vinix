// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module planguest

#include <volume.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <elf.h>
#include <sys/auxv.h>
#include <sys/stat.h>

@[c_extern] __global C.stdout voidptr
@[c_extern] __global C.errno i32
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) i64
fn C.write(i32, voidptr, usize) i64
fn C.pread(i32, voidptr, usize, i64) i64
fn C.pwrite(i32, voidptr, usize, i64) i64
fn C.fsync(i32) i32
fn C.ioctl(i32, u64, ...voidptr) i32
fn C.printf(&char, ...voidptr) i32
fn C.setbuf(voidptr, voidptr)
fn C.pause() i32
fn C.sleep(u32) u32
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.dup2(i32, i32) i32
fn C.fopen(&char, &char) voidptr
fn C.fclose(voidptr) i32
fn C.fgets(&char, i32, voidptr) &char
fn C.sscanf(&char, &char, ...voidptr) i32
fn C.getauxval(u64) u64
fn C.fstat(i32, &C.stat) i32
fn C.chmod(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.rename(&char, &char) i32
fn C.mknod(&char, u32, u64) i32
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.mkdir(&char, u32) i32

struct C.stat { st_rdev u64; st_mode u32; st_size i64; st_uid u32 }

@[typedef]
struct C.Elf64_Phdr {
	p_type u32
	p_flags u32
	p_vaddr u64
	p_memsz u64
}

@[typedef]
struct C.Elf64_Ehdr {
	e_type u16
	e_phoff u64
}

struct Status {
mut:
	version u64
	bytes u64
	sector u64
	flags u64
	reads u64
	writes u64
	read_bytes u64
	write_bytes u64
	flushes u64
	errors u64
	last_error u64
	disk_id u64
	start u64
	slot u64
	generation u64
	reserved u64
}

struct Heap {
mut:
	count int
	sizes [32]i64
	live [32]i64
	large i64
}

fn check(condition bool, message &char) {
	if condition { return }
	C.printf(c'PLAN FAIL: %s errno=%d\n', message, unsafe { C.errno })
	for { C.pause() }
}

fn status(path &char) Status {
	fd := C.open(path, C.O_RDONLY)
	check(fd >= 0, c'open status')
	mut result := Status{}
	check(C.ioctl(fd, u64(0x56560004), &result) == 0 && result.version == 1, c'query status')
	check(C.close(fd) == 0, c'close status')
	return result
}

fn missing(path &char) {
	fd := C.open(path, C.O_RDONLY)
	check(fd < 0 && unsafe { C.errno == C.ENOENT }, c'expected absent mapping')
}

fn tool(command &char, device &char, a &char, b &char, c &char, expected i32) {
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), command, device, a, b, c, &char(nil)]!
		run_utility(&arguments[0], expected)
	}
}

fn run_utility(arguments &&char, expected i32) {
	child := C.fork()
	check(child >= 0, c'fork utility')
	if child == 0 { unsafe { C.execv(arguments[0], arguments) }; C._exit(127) }
	mut code := i32(0)
	check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'utility exit')
}

fn simple(command &char, device &char, file &char, expected i32) {
	unsafe { tool(command, device, file, &char(nil), &char(nil), expected) }
}

@[direct_array_access]
fn view_data() {
	fd := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
	check(fd >= 0, c'open restored view')
	mut bytes := [4096]u8{}
	check(C.pread(fd, &bytes[0], 4096, 0) == 4096, c'read restored data')
	for value in bytes { check(value == 0x6d, c'reboot data preserved') }
	check(C.close(fd) == 0, c'close restored view')
	readonly := C.open(c'/dev/mapper/vinix5', C.O_RDWR)
	check(readonly < 0 && unsafe { C.errno == C.EROFS }, c'restored read-only mode')
}

@[direct_array_access]
fn heap_snapshot(mut snapshot Heap) {
	snapshot = Heap{}
	file := C.fopen(c'/proc/slabinfo', c'r')
	check(file != unsafe { nil }, c'open heap snapshot')
	mut text := [256]char{}
	for C.fgets(&text[0], 256, file) != unsafe { nil } {
		mut index := i64(0); mut size := i64(0); mut live := i64(0); mut pages := i64(0)
		if C.sscanf(&text[0], c'size-%ld %ld %ld %ld', &index, &size, &live, &pages) == 4 {
			check(snapshot.count < 32, c'bounded heap classes')
			snapshot.sizes[snapshot.count] = size
			snapshot.live[snapshot.count] = live
			snapshot.count++
		} else if C.sscanf(&text[0], c'large - - %ld', &pages) == 1 { snapshot.large = pages }
	}
	check(C.fclose(file) == 0 && snapshot.count > 0, c'close heap snapshot')
}

fn cycles(parent &char, count int) {
	other := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
	crypt_cycles(parent, count)
	recovery_cycles(count)
	for _ in 0 .. count {
		scrub_tool(c'/root/data.vhash', c'/root/scrub-report.txt', parent, other, 0, unsafe { nil })
		data_tool(unsafe { nil }, c'/root/data.vhash', parent, other, false, 0, unsafe { nil })
		tool(c'save-set', c'/etc/vinix/volumes.vset', parent, other, unsafe { &char(nil) }, 0)
		mapping_growths(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'9', c'8192', c'mbr:12345678', c'2', c'8192', true, 0, unsafe { nil })
		mapping_growths(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'9', c'8192', c'mbr:12345678', c'2', c'8192', false, 0, unsafe { nil })
		capacity_batch(c'/etc/vinix/volumes.vset', c'0', parent, c'16777216', c'1', other, c'16777216', true, 0, unsafe { nil })
		capacity_batch(c'/etc/vinix/volumes.vset', c'0', parent, c'16777216', c'1', other, c'16777216', false, 0, unsafe { nil })
		capacity_contracts(c'/etc/vinix/volumes.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', parent, c'16777216', true, 0, unsafe { nil })
		capacity_contracts(c'/etc/vinix/volumes.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', parent, c'16777216', false, 0, unsafe { nil })
		pool_members_batch(c'/etc/vinix/volumes.vset', c'3', c'0', c'6291456', c'6295552', c'1', c'6291456', c'6303744', false, true, 0, unsafe { nil })
		pool_members_batch(c'/etc/vinix/volumes.vset', c'3', c'0', c'6291456', c'6295552', c'1', c'6291456', c'6303744', false, false, 0, unsafe { nil })
		pool_order(c'/etc/vinix/volumes.vset', c'3', c'0', c'1', true, 0, unsafe { nil })
		pool_order(c'/etc/vinix/volumes.vset', c'3', c'0', c'1', false, 0, unsafe { nil })
		pool_expand_batch(c'/etc/vinix/volumes.vset', c'3', c'0', c'6299648', c'1', c'6303744', true, 0, unsafe { nil })
		pool_expand_batch(c'/etc/vinix/volumes.vset', c'3', c'0', c'6299648', c'1', c'6303744', false, 0, unsafe { nil })
		simple(c'pool-space', c'/etc/vinix/volumes.vset', c'3', 0)
		pool_batch(c'/etc/vinix/volumes.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', true, 0, unsafe { nil })
		pool_batch(c'/etc/vinix/volumes.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', false, 0, unsafe { nil })
		pool_grow_batch(c'/etc/vinix/volumes.vset', c'3', c'14', c'8192', c'15', c'12288', true, 0, unsafe { nil })
		pool_grow_batch(c'/etc/vinix/volumes.vset', c'3', c'14', c'8192', c'15', c'12288', false, 0, unsafe { nil })
		mapping_additions(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'15', c'6291456', c'12288', c'rw',
			c'mbr:12345678', c'14', c'6291456', c'8192', c'ro', true, 0, unsafe { nil })
		mapping_additions(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'15', c'6291456', c'12288', c'rw',
			c'mbr:12345678', c'14', c'6291456', c'8192', c'ro', false, 0, unsafe { nil })
		pool_members_batch(c'/etc/vinix/volumes.vset', c'4', c'0', c'1048576', c'1056768', unsafe { nil }, unsafe { nil }, unsafe { nil }, false, false, 0, unsafe { nil })
		multi_pool_allocations(c'/etc/vinix/volumes.vset', c'3', c'15', c'12288', c'rw', c'4', c'2', c'8192', c'rw', true, 0, unsafe { nil })
		multi_pool_allocations(c'/etc/vinix/volumes.vset', c'3', c'15', c'12288', c'rw', c'4', c'2', c'8192', c'rw', false, 0, unsafe { nil })
		multi_pool_growth(c'/etc/vinix/volumes.vset', c'4', c'2', c'8192', c'3', c'15', c'12288', true, 0, unsafe { nil })
		multi_pool_growth(c'/etc/vinix/volumes.vset', c'4', c'2', c'8192', c'3', c'15', c'12288', false, 0, unsafe { nil })
		tool(c'pool-remove', c'/etc/vinix/volumes.vset', c'4', c'0', unsafe { nil }, 0)
		pool_contractions(c'/etc/vinix/volumes.vset', c'3', c'mbr:12345679', c'6303744', c'mbr:12345678', c'6299648', true, 0, unsafe { nil })
		pool_contractions(c'/etc/vinix/volumes.vset', c'3', c'mbr:12345679', c'6303744', c'mbr:12345678', c'6299648', false, 0, unsafe { nil })
		pool_resizes(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'3', c'6291456', c'6303744', c'mbr:12345678', c'3', c'6291456', c'6299648', true, 0, unsafe { nil })
		pool_resizes(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'3', c'6291456', c'6303744', c'mbr:12345678', c'3', c'6291456', c'6299648', false, 0, unsafe { nil })
		tool(c'check-bundle', c'/etc/vinix/volumes.vset', c'grow', unsafe { &char(nil) }, unsafe { &char(nil) }, 0)
		mapping_removals(c'/etc/vinix/volumes.vset', c'15', c'14', unsafe { nil }, true, 0, unsafe { nil })
		mapping_removals(c'/etc/vinix/volumes.vset', c'15', c'14', unsafe { nil }, false, 0, unsafe { nil })
		enrollment_plans(c'/etc/vinix/volumes.vset', c'/root/offline.vmap', c'/root/offline-second.vmap', true, 0, unsafe { nil })
		enrollment_plans(c'/etc/vinix/volumes.vset', c'/root/offline.vmap', c'/root/offline-second.vmap', false, 0, unsafe { nil })
		disk_forgets(c'/etc/vinix/volumes.vset', c'mbr:1234567c', c'mbr:1234567b', unsafe { nil }, true, 0, unsafe { nil })
		disk_forgets(c'/etc/vinix/volumes.vset', c'mbr:1234567c', c'mbr:1234567b', unsafe { nil }, false, 0, unsafe { nil })
		tool(c'restore-bundle', c'/etc/vinix/volumes.vset', c'grow', unsafe { &char(nil) }, unsafe { &char(nil) }, 0)
		simple(c'boot-restore', unsafe { &char(nil) }, unsafe { &char(nil) }, 0)
	}
	C.sleep(13)
	missing(c'/dev/mapper/vinix14')
	missing(c'/dev/mapper/vinix15')
}

@[direct_array_access]
fn second_view_data() {
	fd := C.open(c'/dev/mapper/vinix9', C.O_RDONLY)
	mut bytes := [4096]u8{}
	check(fd >= 0 && C.pread(fd, &bytes[0], 4096, 0) == 4096, c'read second disk data')
	for value in bytes { check(value == 0xb3, c'second disk data preserved') }
	check(C.close(fd) == 0, c'close second disk view')
}

fn copy_plan(from &char, to &char) {
	input := C.open(from, C.O_RDONLY)
	mut bytes := [2112]u8{}
	size := C.read(input, &bytes[0], 2112)
	check(input >= 0 && size >= 64 && size <= 2112 && C.close(input) == 0, c'read plan copy')
	output := C.open(to, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(output >= 0 && C.write(output, &bytes[0], usize(size)) == size && C.fsync(output) == 0 && C.close(output) == 0, c'write plan copy')
}

// Change a record while preserving a valid checksum, so the plan-set test
// reaches global slot validation rather than failing the format check.
@[direct_array_access]
fn conflicting_plan_slot(path &char) {
	fd := C.open(path, C.O_RDWR)
	mut bytes := [96]u8{}
	check(fd >= 0 && C.read(fd, &bytes[0], 96) == 96, c'read slot conflict fixture')
	bytes[68] = 2
	mut crc := u32(-1)
	for i := 0; i < 96; i++ {
		crc ^= if i >= 36 && i < 40 { u32(0) } else { u32(bytes[i]) }
		for _ in 0 .. 8 { crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
	}
	crc = ~crc
	for i := 0; i < 4; i++ { bytes[36 + i] = u8(crc >> (8 * i)) }
	check(C.pwrite(fd, &bytes[0], 96, 0) == 96 && C.fsync(fd) == 0 && C.close(fd) == 0, c'write slot conflict fixture')
}

fn missing_set() {
	missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5'); missing(c'/dev/mapper/vinix9')
}

fn remove_set() {
	unsafe {
		simple(c'remove', c'/dev/mapper/vinix2', &char(nil), 0)
		simple(c'remove', c'/dev/mapper/vinix5', &char(nil), 0)
		simple(c'remove', c'/dev/mapper/vinix9', &char(nil), 0)
	}
}

@[direct_array_access]
fn multiple_plans(parent &char, other &char) {
	unsafe {
		check(C.mkdir(c'/etc/vinix/volumes.d', 0o755) == 0, c'create boot plans directory')
		tool(c'create', other, c'9', c'1048576', c'4096', 0)
		fd := C.open(c'/dev/mapper/vinix9', C.O_RDWR)
		mut bytes := [4096]u8{init: 0xb3}
		check(fd >= 0 && C.pwrite(fd, &bytes[0], 4096, 0) == 4096 && C.fsync(fd) == 0 && C.close(fd) == 0, c'write second disk data')
		simple(c'save', other, c'/root/second.vmap', 0)
		simple(c'save', parent, c'/etc/vinix/volumes.vmap', 0)
		copy_plan(c'/root/second.vmap', c'/etc/vinix/volumes.d/z-data.vmap')
		// Ignored files must not become enabled plans accidentally.
		copy_plan(c'/root/bad.vmap', c'/etc/vinix/volumes.d/.disabled.vmap')
		copy_plan(c'/root/bad.vmap', c'/etc/vinix/volumes.d/old.vmap.bak')
		remove_set()
		copy_plan(c'/root/bad.vmap', c'/etc/vinix/volumes.d/z-data.vmap')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		copy_plan(c'/root/second.vmap', c'/etc/vinix/volumes.d/z-data.vmap')
		copy_plan(c'/etc/vinix/volumes.vmap', c'/etc/vinix/volumes.d/a-duplicate.vmap')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		check(C.unlink(c'/etc/vinix/volumes.d/a-duplicate.vmap') == 0, c'remove duplicate plan')
		conflicting_plan_slot(c'/etc/vinix/volumes.d/z-data.vmap')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		copy_plan(c'/root/second.vmap', c'/etc/vinix/volumes.d/z-data.vmap')
		signature(other, 0x1234567a)
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		signature(other, 0x12345679)
		check(C.chmod(c'/etc/vinix/volumes.d', 0o777) == 0, c'untrusted set directory')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		check(C.chmod(c'/etc/vinix/volumes.d', 0o755) == 0 && C.chmod(c'/etc/vinix/volumes.d/z-data.vmap', 0o622) == 0, c'untrusted set file')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		check(C.chmod(c'/etc/vinix/volumes.d/z-data.vmap', 0o600) == 0 && C.chown(c'/etc/vinix/volumes.d/z-data.vmap', 65534, 65534) == 0, c'untrusted set owner')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		check(C.chown(c'/etc/vinix/volumes.d/z-data.vmap', 0, 0) == 0, c'restore set owner')
		check(C.rename(c'/etc/vinix/volumes.d/z-data.vmap', c'/etc/vinix/volumes.d/.real-data') == 0
			&& C.symlink(c'.real-data', c'/etc/vinix/volumes.d/z-data.vmap') == 0, c'set symlink fixture')
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		check(C.unlink(c'/etc/vinix/volumes.d/z-data.vmap') == 0
			&& C.rename(c'/etc/vinix/volumes.d/.real-data', c'/etc/vinix/volumes.d/z-data.vmap') == 0, c'restore regular set file')
		// A conflict on the later disk cannot create mappings on the first.
		tool(c'create', other, c'9', c'3145728', c'4096', 0)
		kept := status(c'/dev/mapper/vinix9').generation
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		check(status(c'/dev/mapper/vinix9').generation == kept, c'conflicting mapping unchanged')
		simple(c'remove', c'/dev/mapper/vinix9', &char(nil), 0)
		// The same guarantee includes an unlisted overlapping slot.
		tool(c'create', other, c'12', c'1048576', c'4096', 0)
		simple(c'boot-restore', &char(nil), &char(nil), 1); missing_set()
		simple(c'remove', c'/dev/mapper/vinix12', &char(nil), 0)
		// Exercise directory-only restoration, then legacy plus directory.
		check(C.rename(c'/etc/vinix/volumes.vmap', c'/etc/vinix/volumes.d/a-primary.vmap') == 0, c'directory-only set')
		simple(c'restore-set', c'/etc/vinix/volumes.d', &char(nil), 0)
		view_data(); second_view_data()
		first_generation := status(c'/dev/mapper/vinix2').generation
		second_generation := status(c'/dev/mapper/vinix9').generation
		simple(c'boot-restore', &char(nil), &char(nil), 0)
		check(C.rename(c'/etc/vinix/volumes.d/a-primary.vmap', c'/etc/vinix/volumes.vmap') == 0, c'restore legacy plan')
		simple(c'boot-restore', &char(nil), &char(nil), 0)
		check(status(c'/dev/mapper/vinix2').generation == first_generation
			&& status(c'/dev/mapper/vinix9').generation == second_generation, c'plan set idempotence')
		C.printf(c'PLAN SET PREFLIGHT PASSED\n')
	}
}

fn fixture_plan(bytes &u8) {
	fd := C.open(c'/etc/vinix/volumes.vmap', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0 && C.write(fd, bytes, 128) == 128 && C.fsync(fd) == 0 && C.close(fd) == 0, c'write boot plan fixture')
}

@[direct_array_access]
fn signature(device &char, value u32) {
	fd := C.open(device, C.O_RDWR)
	mut sector := [512]u8{}
	check(fd >= 0 && C.pread(fd, &sector[0], 512, 0) == 512, c'read duplicate identity fixture')
	for i := 0; i < 4; i++ { sector[440 + i] = u8(value >> (8 * i)) }
	check(C.pwrite(fd, &sector[0], 512, 0) == 512 && C.fsync(fd) == 0 && C.close(fd) == 0, c'change duplicate identity fixture')
}

fn physical_alias(parent &char) {
	fd := C.open(parent, C.O_RDONLY)
	mut info := C.stat{}
	check(fd >= 0 && C.fstat(fd, &info) == 0 && C.close(fd) == 0, c'physical alias identity')
	check(C.mknod(c'/dev/volume-plan-alias', C.S_IFBLK | 0o600, info.st_rdev) == 0, c'physical alias creation')
	check(C.symlink(parent, c'/dev/volume-plan-link') == 0, c'discovery symlink fixture')
}

// The static fixture itself stays alive across the measurement. Touch every
// readable load page so later diagnostic code/data faults do not count as
// save/restore retention (especially with x86's smaller pages).
fn warm_image() {
	unsafe {
		address := C.getauxval(C.AT_PHDR)
		count := C.getauxval(C.AT_PHNUM)
		page := C.getauxval(C.AT_PAGESZ)
		check(address > sizeof(C.Elf64_Ehdr) && count > 0 && count <= 64
			&& C.getauxval(C.AT_PHENT) == sizeof(C.Elf64_Phdr) && page >= 4096 && page <= 65536, c'fixture ELF metadata')
		header := &C.Elf64_Ehdr(address - sizeof(C.Elf64_Ehdr))
		check(header.e_type == C.ET_EXEC && header.e_phoff == sizeof(C.Elf64_Ehdr), c'static fixture ELF layout')
		segments := &C.Elf64_Phdr(address)
		mut checksum := u8(0)
		for i := u64(0); i < count; i++ {
			segment := segments[i]
			if segment.p_type != C.PT_LOAD || segment.p_flags & C.PF_R == 0 { continue }
			check(segment.p_memsz <= 16 * 1024 * 1024 && segment.p_vaddr <= u64(-1) - segment.p_memsz, c'fixture load bounds')
			end := segment.p_vaddr + segment.p_memsz
			for at := segment.p_vaddr; at < end; at = (at / page + 1) * page {
				checksum ^= *(&u8(at))
			}
		}
		C.printf(c'PLAN WARM image=%u\n', u32(checksum))
	}
}

fn allocation_trace(path &char, print bool) {
	fd := C.open(path, C.O_RDONLY)
	if fd < 0 { return } // Ordinary kernels need not enable ALLOC_TRACK.
	mut bytes := [4096]u8{}
	for {
		count := C.read(fd, &bytes[0], 4096)
		if count <= 0 { break }
		if print { C.write(1, &bytes[0], usize(count)) }
	}
	C.close(fd)
}

@[direct_array_access]
fn first_boot(parent &char) {
	unsafe {
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid initial boot plan')
		simple(c'boot-restore', &char(nil), &char(nil), 0)
		tool(c'create', parent, c'2', c'1048576', c'4096', 0)
		arguments := [&char(c'/usr/sbin/vinix-volume'), &char(c'create'), parent, &char(c'5'), &char(c'2097152'), &char(c'8192'), &char(c'ro'), &char(nil)]!
		child := C.fork(); check(child >= 0, c'fork read-only create')
		if child == 0 { C.execv(arguments[0], &arguments[0]); C._exit(127) }
		mut code := i32(0); check(C.waitpid(child, &code, 0) == child && code == 0, c'read-only create')
		fd := C.open(c'/dev/mapper/vinix2', C.O_RDWR); check(fd >= 0, c'open writable view')
		mut data := [4096]u8{init: 0x6d}
		check(C.pwrite(fd, &data[0], 4096, 0) == 4096 && C.fsync(fd) == 0 && C.close(fd) == 0, c'write durable view data')
		simple(c'save', parent, c'/root/saved.vmap', 0)
		original := status(c'/dev/mapper/vinix2').generation
		simple(c'restore', parent, c'/root/saved.vmap', 0)
		check(status(c'/dev/mapper/vinix2').generation == original, c'idempotent restore keeps generation')
		simple(c'remove', c'/dev/mapper/vinix2', &char(nil), 0)
		simple(c'remove', c'/dev/mapper/vinix5', &char(nil), 0)
		// Corrupted on-disk plans cannot create even the first mapping.
		plan_fd := C.open(c'/root/saved.vmap', C.O_RDONLY)
		mut damaged := [128]u8{}
		check(plan_fd >= 0 && C.read(plan_fd, &damaged[0], 128) == 128 && C.close(plan_fd) == 0, c'read corruption fixture')
		damaged[112] ^= 1
		bad_fd := C.open(c'/root/bad.vmap', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad_fd >= 0 && C.write(bad_fd, &damaged[0], 128) == 128 && C.close(bad_fd) == 0, c'write corruption fixture')
		simple(c'restore', parent, c'/root/bad.vmap', 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		fixture_plan(&damaged[0])
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		damaged[112] ^= 1
		fixture_plan(&damaged[0])
		check(C.chmod(c'/etc/vinix/volumes.vmap', 0o622) == 0, c'untrusted plan mode')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.chmod(c'/etc/vinix/volumes.vmap', 0o600) == 0 && C.chmod(c'/etc/vinix', 0o777) == 0, c'untrusted directory mode')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.chmod(c'/etc/vinix', 0o755) == 0, c'restore trusted directory')
		check(C.chown(c'/etc/vinix/volumes.vmap', 65534, 65534) == 0, c'untrusted plan owner')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.chown(c'/etc/vinix/volumes.vmap', 0, 0) == 0, c'restore trusted plan owner')
		check(C.rename(c'/etc/vinix/volumes.vmap', c'/etc/vinix/real.vmap') == 0
			&& C.symlink(c'real.vmap', c'/etc/vinix/volumes.vmap') == 0, c'boot plan symlink fixture')
		simple(c'boot-restore', &char(nil), &char(nil), 1)
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0
			&& C.rename(c'/etc/vinix/real.vmap', c'/etc/vinix/volumes.vmap') == 0, c'restore regular boot plan')
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		// A different physical disk must fail before creating any mapping.
		wrong := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		simple(c'restore', wrong, c'/root/saved.vmap', 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		physical_alias(parent)
		signature(wrong, 0x12345678)
		simple(c'restore-auto', c'/root/saved.vmap', &char(nil), 1)
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5')
		signature(wrong, 0x12345679)
		simple(c'discover', c'/root/saved.vmap', &char(nil), 0)
		tool(c'create', parent, c'5', c'3145728', c'4096', 0)
		simple(c'restore-auto', c'/root/saved.vmap', &char(nil), 1)
		missing(c'/dev/mapper/vinix2') // Conflict in a later slot cannot create a prefix.
		simple(c'remove', c'/dev/mapper/vinix5', &char(nil), 0)
		simple(c'restore-auto', c'/root/saved.vmap', &char(nil), 0)
		kept := status(c'/dev/mapper/vinix5').generation
		simple(c'remove', c'/dev/mapper/vinix2', &char(nil), 0)
		simple(c'restore', parent, c'/root/saved.vmap', 0)
		check(status(c'/dev/mapper/vinix5').generation == kept, c'resume keeps existing mapping')
		view_data()
		check(C.unlink(c'/dev/volume-plan-alias') == 0 && C.unlink(c'/dev/volume-plan-link') == 0, c'alias fixture cleanup')
		multiple_plans(parent, wrong)
		bundle_plans(parent, wrong)
		planned_growth(parent, wrong)
		planned_mappings(parent, wrong)
		planned_disks(wrong)
		planned_space(parent)
		planned_pools(parent, wrong)
		planned_pool_growth(parent)
		planned_pool_batch(parent, wrong)
		planned_pool_grow_batch(parent, wrong)
		planned_pool_expand_batch(parent, wrong)
		planned_capacity_batch(parent, wrong)
		planned_pool_members_batch(parent, wrong)
		planned_pool_order(parent, wrong)
		planned_mapping_removals(parent, wrong)
		planned_enrollment_batch(parent, wrong)
		planned_forget_batch()
		planned_addition_batch(parent, wrong)
		planned_explicit_growth_batch(parent, wrong)
		planned_pool_contractions(parent)
		planned_pool_resizes(parent)
		planned_capacity_contracts(parent, wrong)
		planned_multi_pool_batch(parent, wrong)
		planned_data(parent, wrong)
		planned_scrub(parent, wrong)
		planned_lock(parent, wrong)
		planned_crypt(parent)
		planned_recovery(parent)
		planned_sealed(parent)
		sealed_retention(parent)
		planned_rewrap(parent)
		rewrap_retention(parent)
		planned_volume_seal(parent, wrong)
		volume_seal_retention(parent)
		planned_volume_rewrap(parent, wrong)
		volume_rewrap_retention(parent)
		planned_volume_discovery(parent, wrong)
		volume_discovery_retention(parent)
		planned_volume_growth(parent, wrong)
		volume_growth_retention(parent)
		volume_boot_retention(parent)
		boot_set_retention(parent, wrong)
		health_check(parent)
		health_cycles(parent)
		$if nvme_health_test ? { nvme_health_check(); nvme_health_cycles() }
		// Warm both retained measurement buffers and the snapshot reader before
		// either baseline. The fixture remains alive across the whole workload.
		mut before := Heap{}; mut after := Heap{}
		heap_snapshot(mut before); heap_snapshot(mut after)
		C.printf(c'PLAN SNAPSHOT WARM first=%ld second=%ld\n', before.large, after.large)
		allocation_trace(c'/proc/allocstart', false)
		cycles(parent, 200)
		heap_snapshot(mut before); heap_snapshot(mut after)
		C.printf(c'PLAN SNAPSHOT READY first=%ld second=%ld\n', before.large, after.large)
		heap_snapshot(mut before)
		health_cycles(parent)
		$if nvme_health_test ? { nvme_health_cycles() }
		cycles(parent, 200)
		heap_snapshot(mut after)
		C.printf(c'PLAN LARGE before=%ld after=%ld\n', before.large, after.large)
		mut retained := before.count != after.count || after.large > before.large
		for i := 0; i < before.count; i++ {
			C.printf(c'PLAN RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
			if before.sizes[i] != after.sizes[i] || after.live[i] > before.live[i] { retained = true }
		}
		if retained {
			allocation_trace(c'/proc/allocsites', true)
			// Observe asynchronous reclamation without changing the failed verdict.
			C.sleep(2)
			mut observed := Heap{}
			heap_snapshot(mut observed)
			C.printf(c'PLAN OBSERVE large=%ld after_wait=%ld\n', after.large, observed.large)
		}
		check(!retained, c'heap retention')
		check(C.unlink(c'/root/crypt.key') == 0, c'remove original key before reboot recovery')
		tool(c'save-set', c'/etc/vinix/volumes.vset', parent, wrong, &char(nil), 0)
		pool_members(c'/etc/vinix/volumes.vset')
		boot_volume_prepare(c'/root/volume-grown-ro.sealed')
		boot_set_prepare()
		plan := C.open(c'/root/saved.vmap', C.O_RDONLY); check(plan >= 0, c'open exported plan')
		mut bytes := [2112]u8{}
		size := C.read(plan, &bytes[0], 2112)
		check(size >= 128 && size <= 2112 && C.close(plan) == 0, c'export plan bytes')
		C.printf(c'PLAN FILE ')
		for i := i64(0); i < size; i++ { C.printf(c'%02x', u32(bytes[i])) }
		C.printf(c'\n')
		phase := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(phase >= 0 && C.write(phase, c'1', 1) == 1 && C.fsync(phase) == 0 && C.close(phase) == 0, c'persist reboot phase')
		directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
		check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist reboot phase directory')
	}
}

@[export: 'main']
pub fn entry(_argc i32, _argv &&char) i32 {
	unsafe { C.setbuf(C.stdout, nil) }
	$if amd64 {
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		check(serial >= 0 && C.dup2(serial, 1) == 1 && C.dup2(serial, 2) == 2 && C.close(serial) == 0, c'serial console')
		if C.getpid() == 1 {
			unsafe {
				arguments := [&char(c'/bin/sh'), &char(c'/usr/libexec/volume-test-init'), &char(nil)]!
				C.execv(c'/bin/sh', &arguments[0])
			}
			check(false, c'exec packaged init')
		}
	}
	$if volume_recovery_test ? { return volume_recovery_entry() }
	$if volume_recovery_unlock_test ? { return recovery_unlock_entry() }
	$if volume_recovery_rewrap_test ? { return recovery_rewrap_entry() }
	$if volume_recovery_growth_test ? { return recovery_growth_entry() }
	$if volume_recovery_inspect_test ? { return recovery_inspect_entry() }
	$if volume_inspect_test ? { return volume_inspect_entry() }
	$if volume_growth_preview_test ? { return growth_preview_entry() }
	$if volume_ciphertext_test ? { return ciphertext_entry() }
	$if volume_ciphertext_scrub_test ? { return ciphertext_scrub_entry() }
	parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
	C.printf(c'PLAN START\n')
	warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 { first_boot(parent) }
	else {
		C.close(phase)
		actual := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		other := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		volume_boot_reboot_probe(actual)
		boot_set_reboot_probe(actual, other)
		data_phase := C.open(c'/data-boot', C.O_RDONLY)
		if data_phase >= 0 {
			check(C.close(data_phase) == 0, c'close checksum phase marker'); data_boot_phase(actual, other)
			scrub_boot_phase(actual, other)
			C.printf(c'PLAN DONE\n'); for { C.pause() }
		}
		multi_growth := C.open(c'/multi-pool-growth-boot', C.O_RDONLY)
		if multi_growth >= 0 {
			check(C.close(multi_growth) == 0, c'close multi-pool growth phase marker'); multi_pool_growth_boot_phase(actual, other)
			prepare_data_boot(actual, other)
			prepare_scrub_boot(actual, other)
			C.printf(c'PLAN DONE\n'); for { C.pause() }
		}
		multi := C.open(c'/multi-pool-boot', C.O_RDONLY)
		if multi >= 0 {
			check(C.close(multi) == 0, c'close multi-pool phase marker'); multi_pool_boot_phase(actual, other)
			C.printf(c'PLAN DONE\n'); for { C.pause() }
		}
		if status(actual).bytes == 20971520 {
			volume_discovery_tool(c'/root/volume-capacity.sealed', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
			C.printf(c'PLAN VOLUME GROWTH PHYSICAL CONTRACTION REFUSED\n')
			pending := C.open(c'/etc/vinix/boot-volume.vcrypt', C.O_RDONLY)
			if pending >= 0 { check(C.close(pending) == 0, c'close refused boot configuration'); boot_volume_disable() }
			physical_capacity_contract_phase(actual, other)
			C.printf(c'PLAN DONE\n')
			for { C.pause() }
		}
		if status(actual).bytes == 25165824 {
			volume_seal_open_tool(actual, c'/root/volume.sealed', c'/root/crypt.pass', true, 1); missing(c'/dev/mapper/vinix60')
			C.printf(c'PLAN VOLUME SEAL CHANGED CAPACITY REFUSED\n')
			volume_seal_open_tool(actual, c'/root/volume-next.sealed', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
			C.printf(c'PLAN VOLUME REWRAP CHANGED CAPACITY REFUSED\n')
			volume_discovery_tool(c'/root/volume-next.sealed', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
			C.printf(c'PLAN VOLUME DISCOVERY CHANGED CAPACITY REFUSED\n')
			volume_growth_capacity_boot(actual)
			boot_volume_prepare(c'/root/volume-capacity-ro.sealed')
			physical_capacity_phase(actual, other)
			C.printf(c'PLAN DONE\n')
			for { C.pause() }
		}
		view_data(); second_view_data()
		grown_view_data()
		edited_view_data()
		pool_boot_check()
		check(C.getppid() == 1 && status(c'/dev/mapper/vinix2').disk_id == status(actual).disk_id
			&& status(c'/dev/mapper/vinix9').disk_id == status(other).disk_id, c'init restored reordered physical disks')
		C.printf(c'PLAN BOOT RESTORED\n')
		data_tool(unsafe { nil }, c'/root/data.vhash', actual, other, false, 0, unsafe { nil }); C.printf(c'PLAN DATA BOOT VERIFIED\n')
		scrub_reordered_boot(actual, other)
		recovery_reordered_boot()
		crypt_reordered_boot(actual)
		sealed_reordered_boot(actual)
		rewrap_reordered_boot(actual)
		volume_seal_reordered_boot(actual, other)
		volume_rewrap_reordered_boot(actual, other)
		volume_discovery_reordered_boot(actual)
		volume_growth_reordered_boot(actual)
		planned_volume_boot(actual)
		$if nvme_health_test ? { nvme_health_check() }
		before := status(c'/dev/mapper/vinix2').generation
		second_before := status(c'/dev/mapper/vinix9').generation
		simple(c'boot-restore', unsafe { &char(nil) }, unsafe { &char(nil) }, 0)
		boot_volume_view(actual, 8192, true)
		check(status(c'/dev/mapper/vinix2').generation == before
			&& status(c'/dev/mapper/vinix9').generation == second_before, c'reboot restore idempotence')
		planned_boot_set(actual, other)
	}
	C.printf(c'PLAN DONE\n')
	for { C.pause() }
	return 0
}
