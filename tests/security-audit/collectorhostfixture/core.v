// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module collectorhostfixture

#include <native-abi.h>

struct C.record {
mut:
	v [15]u64
}
struct C.snapshot {
mut:
	total u64
	retained u64
	dropped u64
	boot [33]char
	records [128]C.record
}
struct C.collector {
mut:
	session [33]char
	boot [33]char
	epoch u64
	last u64
	total u64
	dropped u64
	started i32
	pending [128]C.record
	pending_count usize
	observed [128]C.record
	observed_count usize
}
struct C.output {
mut:
	bytes [139264]char
	used usize
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stderr voidptr
fn C.__builtin_alloca(usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strcpy(&char, &char) &char
fn C.strstr(&char, &char) &char
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.fprintf(voidptr, &char, ...) i32
fn C.mkdtemp(&char) &char
fn C.open(&char, i32, ...) i32
fn C.openat(i32, &char, i32, ...) i32
fn C.geteuid() u32
fn C.read(i32, voidptr, usize) i64
fn C.write(i32, voidptr, usize) i64
fn C.close(i32) i32
fn C.fchmod(i32, u32) i32
fn C.linkat(i32, &char, i32, &char, i32) i32
fn C.unlinkat(i32, &char, i32) i32
fn C.symlinkat(&char, i32, &char) i32
fn C.mkfifoat(i32, &char, u32) i32
fn C.renameat(i32, &char, i32, &char) i32
fn C.rmdir(&char) i32
fn C.puts(&char) i32
fn C.vka_number(&char, &u64) i32
fn C.vka_parse_snapshot(&char, &C.snapshot) i32
fn C.vka_collect(&C.collector, &C.snapshot, &C.output) i32
fn C.vka_end_pending(&C.output, &C.collector, &char) i32
fn C.vka_log_stat(i32, u32) i32
fn C.vka_open_log_at(i32, &char, u32, i32) i32
fn C.vka_open_log(&char, i32) i32
fn C.vka_append(i32, &C.output, u32) i32
fn C.vka_read_snapshot(&char, &C.snapshot) i32
fn C.vka_add(&C.output, &char) i32

fn check(ok bool, line i32) bool {
	if !ok {
		expression := match line {
			68 { &char(c'collect(&c, &s, &o) == 0') }
			69 { &char(c'occurrences(o.bytes, "decision ") == 1 && strstr(o.bytes, "reason=collector_start")') }
			70 { &char(c'c.pending_count == 1') }
			71 { &char(c'collect(&c, &s, &o) == 0 && o.used == 0') }
			75 { &char(c'collect(&c, &s, &o) == 0 && occurrences(o.bytes, "completion ") == 1') }
			76 { &char(c'!strstr(o.bytes, "decision ") && strstr(o.bytes, "result=18446744073709551615 errno=1")') }
			77 { &char(c'c.pending_count == 0') }
			78 { &char(c'collect(&c, &s, &o) == 0 && o.used == 0') }
			81 { &char(c'collect(&next, &s, &o) == -1 && errno == EPROTO') }
			82 { &char(c'c.pending_count == 0 && c.last == 1') }
			87 { &char(c'collect(&c, &s, &o) == 0 && occurrences(o.bytes, "decision ") == 119') }
			88 { &char(c'!strstr(o.bytes, "loss ") && c.pending_count == 1') }
			90 { &char(c'collect(&c, &s, &o) == 0') }
			91 { &char(c'strstr(o.bytes, "first=121 last=172 count=52 reason=not_observed")') }
			92 { &char(c'strstr(o.bytes, "sequence=120 reason=ring_eviction")') }
			93 { &char(c'occurrences(o.bytes, "decision ") == 128') }
			94 { &char(c'strstr(o.bytes, "overwritten=172")') }
			95 { &char(c'collect(&c, &s, &o) == 0 && o.used == 0') }
			98 { &char(c'collect(&c, &s, &o) == 0 && occurrences(o.bytes, "decision ") == 1') }
			99 { &char(c'!strstr(o.bytes, "loss ")') }
			101 { &char(c'collect(&c, &s, &o) == 0 && c.epoch == 2') }
			102 { &char(c'strstr(o.bytes, "reason=source_reset") && occurrences(o.bytes, "decision ") == 1') }
			104 { &char(c'collect(&c, &s, &o) == 0 && c.epoch == 3 && strstr(o.bytes, "reason=source_reset")') }
			107 { &char(c'collect(&c, &s, &o) == 0 && strstr(o.bytes, "first=1 last=172 count=172")') }
			110 { &char(c'collect(&c, &s, &o) == 0') }
			112 { &char(c'end_pending(&o, &c, "collector_stop") == 0 && strstr(o.bytes, "sequence=301 reason=collector_stop")') }
			124 { &char(c'parse_snapshot(text, &s) == 0 && s.records[0].v[13] == UINT64_MAX') }
			136 { &char(c'parse_snapshot(text, &s) == -1') }
			139 { &char(c'parse_snapshot(text, &s) == -1') }
			142 { &char(c'parse_snapshot(text, &s) == 0 && !strcmp(s.boot, "unknown")') }
			145 { &char(c'parse_snapshot(text, &s) == -1') }
			148 { &char(c'parse_snapshot(text, &s) == -1') }
			150 { &char(c'number("+1", &n) == -1 && number("", &n) == -1 && number("1x", &n) == -1') }
			157 { &char(c'mkdtemp(path) != NULL') }
			159 { &char(c'dir >= 0') }
			162 { &char(c'fd >= 0 && log_stat(fd, owner) == 0') }
			163 { &char(c'open_log_at(dir, "audit.log", owner, -1) == -1') }
			165 { &char(c'again >= 0') }
			167 { &char(c'add(&o, "first\\n") == 0 && append(fd, &o, owner) == 0') }
			169 { &char(c'add(&o, "second\\n") == 0 && append(fd, &o, owner) == 0') }
			172 { &char(c'read(reader, buffer, sizeof(buffer)) == 13 && !strcmp(buffer, "first\\nsecond\\n")') }
			174 { &char(c'log_stat(fd, owner + 1) == -1') }
			175 { &char(c'fchmod(fd, 0644) == 0 && append(fd, &o, owner) == -1') }
			176 { &char(c'fchmod(fd, 0600) == 0') }
			177 { &char(c'linkat(dir, "audit.log", dir, "hardlink", 0) == 0') }
			178 { &char(c'append(fd, &o, owner) == -1') }
			179 { &char(c'unlinkat(dir, "hardlink", 0) == 0') }
			180 { &char(c'symlinkat("audit.log", dir, "symlink") == 0') }
			181 { &char(c'open_log_at(dir, "symlink", owner, -1) == -1') }
			182 { &char(c'mkfifoat(dir, "fifo", 0600) == 0 && open_log_at(dir, "fifo", owner, -1) == -1') }
			183 { &char(c'open_log_at(dir, "../escape", owner, -1) == -1') }
			184 { &char(c'fchmod(dir, 0770) == 0 && open_log_at(dir, "bad.log", owner, -1) == -1') }
			185 { &char(c'fchmod(dir, 0700) == 0') }
			187 { &char(c'open_log("/tmp/should-not-be-created-vinix-audit.log", -1) == -1') }
			188 { &char(c'renameat(dir, "audit.log", dir, "rotated.log") == 0') }
			190 { &char(c'rotated >= 0 && append(rotated, &o, owner) == 0') }
			192 { &char(c'unlinkat(dir, "rotated.log", 0) == 0 && append(fd, &o, owner) == -1') }
			194 { &char(c'unlinkat(dir, "audit.log", 0) == 0 && unlinkat(dir, "symlink", 0) == 0 && unlinkat(dir, "fifo", 0) == 0') }
			197 { &char(c'fd >= 0 && write(fd, "version=1", 9) == 9') }
			201 { &char(c'read_snapshot(snapshot_path, &s) == -1 && errno == EPROTO') }
			202 { &char(c'unlinkat(dir, "snapshot", 0) == 0') }
			204 { &char(c'rmdir(path) == 0') }
			else { &char(c'') }
		}
		unsafe { C.fprintf(C.stderr, c'collector test line %d: %s (errno=%d)\n', line, expression, C.errno) }
	}
	return ok
}

fn fixture(s &C.snapshot, total u64) {
	unsafe {
		C.memset(s, 0, sizeof(C.snapshot))
		C.strcpy(&s.boot[0], c'00112233445566778899aabbccddeeff')
		s.total = total
		s.retained = if total < u64(C.CAPACITY) { total } else { u64(C.CAPACITY) }
		s.dropped = total - s.retained
		for i := usize(0); i < usize(s.retained); i++ {
			v := &s.records[i].v[0]
			v[0] = total - s.retained + u64(i) + 1
			v[1] = v[0] * 100
			v[2] = 3221225534
			v[3] = 39
			v[4] = 123456
			v[6] = 42
			v[5] = 42
			v[10] = 1000
			v[9] = 1000
			v[8] = 1000
			v[7] = 1000
			v[11] = 0x7ffc0000
			v[12] = 1
			v[13] = 42
		}
	}
}

fn occurrences(text &char, needle &char) usize {
	unsafe {
		mut at := &char(voidptr(text))
		mut count := usize(0)
		for {
			at = C.strstr(at, needle)
			if at == nil { break }
			count++
			at += C.strlen(needle)
		}
		return count
	}
}

fn collection_tests() i32 {
	unsafe {
		c := &C.collector(C.__builtin_alloca(sizeof(C.collector)))
		C.memset(c, 0, sizeof(C.collector))
		C.strcpy(&c.session[0], c'ffeeddccbbaa99887766554433221100')
		s := &C.snapshot(C.__builtin_alloca(sizeof(C.snapshot)))
		o := &C.output(C.__builtin_alloca(sizeof(C.output)))
		fixture(s, 1)
		s.records[0].v[13] = 0
		s.records[0].v[12] = 0
		if !check(C.vka_collect(c, s, o) == 0, 68) { return 1 }
		if !check(occurrences(&o.bytes[0], c'decision ') == 1 && C.strstr(&o.bytes[0], c'reason=collector_start') != nil, 69) { return 1 }
		if !check(c.pending_count == 1, 70) { return 1 }
		if !check(C.vka_collect(c, s, o) == 0 && o.used == 0, 71) { return 1 }
		s.records[0].v[12] = 1
		s.records[0].v[13] = u64(0xffffffffffffffff)
		s.records[0].v[14] = 1
		if !check(C.vka_collect(c, s, o) == 0 && occurrences(&o.bytes[0], c'completion ') == 1, 75) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'decision ') == nil && C.strstr(&o.bytes[0], c'result=18446744073709551615 errno=1') != nil, 76) { return 1 }
		if !check(c.pending_count == 0, 77) { return 1 }
		if !check(C.vka_collect(c, s, o) == 0 && o.used == 0, 78) { return 1 }
		next := &C.collector(C.__builtin_alloca(sizeof(C.collector)))
		*next = *c
		s.records[0].v[14] = 0
		s.records[0].v[13] = 0
		s.records[0].v[12] = 0
		if !check(C.vka_collect(next, s, o) == -1 && C.errno == C.EPROTO, 81) { return 1 }
		if !check(c.pending_count == 0 && c.last == 1, 82) { return 1 }
		fixture(s, 120)
		s.records[0].v[13] = u64(0xffffffffffffffff)
		s.records[0].v[14] = 1
		s.records[119].v[13] = 0
		s.records[119].v[12] = 0
		if !check(C.vka_collect(c, s, o) == 0 && occurrences(&o.bytes[0], c'decision ') == 119, 87) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'loss ') == nil && c.pending_count == 1, 88) { return 1 }
		fixture(s, 300)
		if !check(C.vka_collect(c, s, o) == 0, 90) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'first=121 last=172 count=52 reason=not_observed') != nil, 91) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'sequence=120 reason=ring_eviction') != nil, 92) { return 1 }
		if !check(occurrences(&o.bytes[0], c'decision ') == 128, 93) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'overwritten=172') != nil, 94) { return 1 }
		if !check(C.vka_collect(c, s, o) == 0 && o.used == 0, 95) { return 1 }
		fixture(s, 301)
		if !check(C.vka_collect(c, s, o) == 0 && occurrences(&o.bytes[0], c'decision ') == 1, 98) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'loss ') == nil, 99) { return 1 }
		fixture(s, 1)
		if !check(C.vka_collect(c, s, o) == 0 && c.epoch == 2, 101) { return 1 }
		if !check(C.strstr(&o.bytes[0], c'reason=source_reset') != nil && occurrences(&o.bytes[0], c'decision ') == 1, 102) { return 1 }
		C.strcpy(&s.boot[0], c'10112233445566778899aabbccddeeff')
		if !check(C.vka_collect(c, s, o) == 0 && c.epoch == 3 && C.strstr(&o.bytes[0], c'reason=source_reset') != nil, 104) { return 1 }
		C.memset(c, 0, sizeof(C.collector))
		C.strcpy(&c.session[0], c'test')
		fixture(s, 300)
		if !check(C.vka_collect(c, s, o) == 0 && C.strstr(&o.bytes[0], c'first=1 last=172 count=172') != nil, 107) { return 1 }
		fixture(s, 301)
		s.records[127].v[13] = 0
		s.records[127].v[12] = 0
		if !check(C.vka_collect(c, s, o) == 0, 110) { return 1 }
		o.used = 0
		if !check(C.vka_end_pending(o, c, c'collector_stop') == 0 && C.strstr(&o.bytes[0], c'sequence=301 reason=collector_stop') != nil, 112) { return 1 }
	}
	return 0
}

fn parsing_tests() i32 {
	unsafe {
		header := &char(c'version=1 boot=00112233445566778899aabbccddeeff capacity=128 total=1 retained=1 dropped=0\n# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n')
		text := &char(C.__builtin_alloca(2048))
		s := &C.snapshot(C.__builtin_alloca(sizeof(C.snapshot)))
		valid := &char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 18446744073709551615 1\n')
		C.snprintf(text, 2048, c'%s%s', header, valid)
		if !check(C.vka_parse_snapshot(text, s) == 0 && s.records[0].v[13] == u64(0xffffffffffffffff), 124) { return 1 }
		invalid := [
			&char(c'2 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 42 0\n'),
			&char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 2 42 0\n'),
			&char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 0 42 0\n'),
			&char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 18446744073709551616 0\n'),
			&char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 -1 0\n'),
			&char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 42\n'),
			&char(c'1 99 3221225534 39 123456 42 42 1000 1000 1000 1000 2147221504 1 42 0 extra\n'),
		]!
		for i := usize(0); i < usize(invalid.len); i++ {
			C.snprintf(text, 2048, c'%s%s', header, invalid[i])
			if !check(C.vka_parse_snapshot(text, s) == -1, 136) { return 1 }
		}
		C.snprintf(text, 2048, c'%s%s%s', header, valid, valid)
		if !check(C.vka_parse_snapshot(text, s) == -1, 139) { return 1 }
		C.strcpy(text, c'version=1 capacity=128 total=0 retained=0 dropped=0\n# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n')
		if !check(C.vka_parse_snapshot(text, s) == 0 && C.strcmp(&s.boot[0], c'unknown') == 0, 142) { return 1 }
		C.strcpy(text, c'version=1 capacity=128 total=1 retained=0 dropped=1\n# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n')
		if !check(C.vka_parse_snapshot(text, s) == -1, 145) { return 1 }
		C.strcpy(text, c'version=1 boot=not-a-boot-id capacity=128 total=0 retained=0 dropped=0\n# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno\n')
		if !check(C.vka_parse_snapshot(text, s) == -1, 148) { return 1 }
		n := &u64(C.__builtin_alloca(sizeof(u64)))
		if !check(C.vka_number(c'+1', n) == -1 && C.vka_number(c'', n) == -1 && C.vka_number(c'1x', n) == -1, 150) { return 1 }
	}
	return 0
}

fn storage_tests() i32 {
	unsafe {
		path := &char(C.__builtin_alloca(30))
		C.strcpy(path, c'/tmp/vinix-audit-tests.XXXXXX')
		if !check(C.mkdtemp(path) != nil, 157) { return 1 }
		dir := C.open(path, C.O_RDONLY | C.O_DIRECTORY)
		if !check(dir >= 0, 159) { return 1 }
		owner := C.geteuid()
		mut fd := C.vka_open_log_at(dir, c'audit.log', owner, -1)
		if !check(fd >= 0 && C.vka_log_stat(fd, owner) == 0, 162) { return 1 }
		if !check(C.vka_open_log_at(dir, c'audit.log', owner, -1) == -1, 163) { return 1 }
		again := C.vka_open_log_at(dir, c'audit.log', owner, fd)
		if !check(again >= 0, 165) { return 1 }
		C.close(again)
		o := &C.output(C.__builtin_alloca(sizeof(C.output)))
		C.memset(o, 0, sizeof(C.output))
		if !check(C.vka_add(o, c'first\n') == 0 && C.vka_append(fd, o, owner) == 0, 167) { return 1 }
		o.used = 0
		if !check(C.vka_add(o, c'second\n') == 0 && C.vka_append(fd, o, owner) == 0, 169) { return 1 }
		reader := C.openat(dir, c'audit.log', C.O_RDONLY)
		mut buffer := [32]char{}
		if !check(C.read(reader, &buffer[0], sizeof(buffer)) == 13 && C.strcmp(&buffer[0], c'first\nsecond\n') == 0, 172) { return 1 }
		C.close(reader)
		if !check(C.vka_log_stat(fd, owner + 1) == -1, 174) { return 1 }
		if !check(C.fchmod(fd, u32(0o644)) == 0 && C.vka_append(fd, o, owner) == -1, 175) { return 1 }
		if !check(C.fchmod(fd, u32(0o600)) == 0, 176) { return 1 }
		if !check(C.linkat(dir, c'audit.log', dir, c'hardlink', i32(0)) == 0, 177) { return 1 }
		if !check(C.vka_append(fd, o, owner) == -1, 178) { return 1 }
		if !check(C.unlinkat(dir, c'hardlink', i32(0)) == 0, 179) { return 1 }
		if !check(C.symlinkat(c'audit.log', dir, c'symlink') == 0, 180) { return 1 }
		if !check(C.vka_open_log_at(dir, c'symlink', owner, -1) == -1, 181) { return 1 }
		if !check(C.mkfifoat(dir, c'fifo', u32(0o600)) == 0 && C.vka_open_log_at(dir, c'fifo', owner, -1) == -1, 182) { return 1 }
		if !check(C.vka_open_log_at(dir, c'../escape', owner, -1) == -1, 183) { return 1 }
		if !check(C.fchmod(dir, u32(0o770)) == 0 && C.vka_open_log_at(dir, c'bad.log', owner, -1) == -1, 184) { return 1 }
		if !check(C.fchmod(dir, u32(0o700)) == 0, 185) { return 1 }
		if !check(C.vka_open_log(c'/tmp/should-not-be-created-vinix-audit.log', -1) == -1, 187) { return 1 }
		if !check(C.renameat(dir, c'audit.log', dir, c'rotated.log') == 0, 188) { return 1 }
		rotated := C.vka_open_log_at(dir, c'audit.log', owner, fd)
		if !check(rotated >= 0 && C.vka_append(rotated, o, owner) == 0, 190) { return 1 }
		C.close(rotated)
		if !check(C.unlinkat(dir, c'rotated.log', i32(0)) == 0 && C.vka_append(fd, o, owner) == -1, 192) { return 1 }
		C.close(fd)
		if !check(C.unlinkat(dir, c'audit.log', i32(0)) == 0 && C.unlinkat(dir, c'symlink', i32(0)) == 0 && C.unlinkat(dir, c'fifo', i32(0)) == 0, 194) { return 1 }
		fd = C.openat(dir, c'snapshot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, i32(0o600))
		if !check(fd >= 0 && C.write(fd, c'version=1', 9) == 9, 197) { return 1 }
		C.close(fd)
		snapshot_path := &char(C.__builtin_alloca(usize(C.PATH_MAX)))
		C.snprintf(snapshot_path, usize(C.PATH_MAX), c'%s/snapshot', path)
		s := &C.snapshot(C.__builtin_alloca(sizeof(C.snapshot)))
		if !check(C.vka_read_snapshot(snapshot_path, s) == -1 && C.errno == C.EPROTO, 201) { return 1 }
		if !check(C.unlinkat(dir, c'snapshot', i32(0)) == 0, 202) { return 1 }
		C.close(dir)
		if !check(C.rmdir(path) == 0, 204) { return 1 }
	}
	return 0
}

@[export: 'main']
pub fn entry() i32 {
	if collection_tests() != 0 || parsing_tests() != 0 || storage_tests() != 0 { return 1 }
	C.puts(c'SECURITY AUDIT COLLECTOR PASS')
	return 0
}
