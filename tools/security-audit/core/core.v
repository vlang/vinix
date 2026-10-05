// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded snapshots and output retain explicit stack storage. Durable append
// precedes publishing the next collector state; loss and outcome changes remain visible.
@[translated]
module auditcore
#include "collector_v.h"
struct C.record { mut: v [15]u64 }
struct C.snapshot { mut: total u64 retained u64 dropped u64 boot [33]char records [128]C.record }
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
struct C.output { mut: bytes [139264]char used usize }
struct C.vka_stat { mut: mode u64 owner u64 links u64 device u64 inode u64 regular i32 directory i32 }
@[c_extern] __global C.stopping i32
@[c_extern] __global C.reopening i32
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.strchr(&char, i32) &char
fn C.strcpy(&char, &char) &char
fn C.vka_token(&char, &char, &&char) &char
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memchr(voidptr, i32, usize) voidptr
fn C.vka_stat(i32, &C.vka_stat) i32
fn C.vka_path_max() usize
fn C.vka_errno() i32
fn C.vka_is_error(i32) i32
fn C.vka_set_errno(i32)
fn C.vka_restore_errno(i32)
fn C.vka_open_read(&char) i32
fn C.vka_open_root() i32
fn C.vka_open_dir(i32, &char) i32
fn C.vka_open_log_file(i32, &char, i32) i32
fn C.vka_dup(i32) i32
fn C.vka_lock(i32) i32
fn C.vka_mkdir(i32, &char) i32
fn C.vka_read(i32, voidptr, usize) i64
fn C.vka_write(i32, voidptr, usize) i64
fn C.vka_close(i32) i32
fn C.vka_fsync(i32) i32
fn C.vka_uid() u32
fn C.vka_euid() u32
fn C.vka_pid() i64
fn C.vka_umask()
fn C.vka_signals() i32
fn C.vka_wall_ns() u64
fn C.vka_sleep(&u64, &u64) i32
fn C.vka_usage()
fn C.vka_root_required()
fn C.vka_perror(&char)
fn C.vka_collection_error(i32)

@[export: 'vka_number']
pub fn number(text &char, value &u64) i32 {
 unsafe {
  if text[0] == 0 { return -1 }
  mut n := u64(0)
  for p := text; p[0] != 0; p++ {
   b := u8(p[0]); if b < 48 || b > 57 { return -1 }
   digit := u64(b - 48)
   if n > (u64(-1) - digit) / 10 { return -1 }
   n = n * 10 + digit
  }
  *value = n; return 0
 }
}
fn boot_id(text &char) i32 {
 unsafe {
  if C.strlen(text) != 32 { return -1 }
  for p := text; p[0] != 0; p++ {
   b := u8(p[0]); if !((b >= 48 && b <= 57) || (b >= 97 && b <= 102)) { return -1 }
  }
  return 0
 }
}
@[export: 'vka_parse_snapshot']
pub fn parse_snapshot(text &char, snapshot &C.snapshot) i32 {
 unsafe {
  C.memset(snapshot, 0, sizeof(C.snapshot)); C.strcpy(&snapshot.boot[0], c'unknown')
  mut line_save := &char(nil)
  mut token_save := &char(nil)
  mut line := C.vka_token(text, c'\n', &line_save)
  if usize(line) == 0 { return -1 }
  mut seen := u32(0)
  for token := C.vka_token(line, c' ', &token_save); usize(token) != 0; token = C.vka_token(nil, c' ', &token_save) {
   mut equals := C.strchr(token, 61)
   if usize(equals) == 0 { return -1 }
   equals[0] = 0; equals++
   mut bit := u32(0)
   mut value := u64(0)
   if C.strcmp(token, c'boot') == 0 {
    bit = 32; if boot_id(equals) != 0 { return -1 }; C.strcpy(&snapshot.boot[0], equals)
   } else {
    if number(equals, &value) != 0 { return -1 }
    if C.strcmp(token, c'version') == 0 { bit = 1; if value != 1 { return -1 } }
    else if C.strcmp(token, c'capacity') == 0 { bit = 2; if value != 128 { return -1 } }
    else if C.strcmp(token, c'total') == 0 { bit = 4; snapshot.total = value }
    else if C.strcmp(token, c'retained') == 0 { bit = 8; snapshot.retained = value }
    else if C.strcmp(token, c'dropped') == 0 { bit = 16; snapshot.dropped = value }
    else { return -1 }
   }
   if (seen & bit) != 0 { return -1 }; seen |= bit
  }
  if (seen & 31) != 31 || snapshot.retained != (if snapshot.total < 128 { snapshot.total } else { u64(128) })
   || snapshot.dropped != snapshot.total - snapshot.retained { return -1 }
  line = C.vka_token(nil, c'\n', &line_save)
  if usize(line) == 0 || C.strcmp(line, c'# sequence ns arch syscall ip pid tid uid euid gid egid action completed result errno') != 0 { return -1 }
  for i := u64(0); i < snapshot.retained; i++ {
   line = C.vka_token(nil, c'\n', &line_save)
   if usize(line) == 0 { return -1 }
   for j := 0; j < 15; j++ {
    token := C.vka_token(if j == 0 { line } else { &char(nil) }, c' ', &token_save)
    if usize(token) == 0 || number(token, &snapshot.records[i].v[j]) != 0 { return -1 }
   }
   if usize(C.vka_token(nil, c' ', &token_save)) != 0 { return -1 }
   v := &snapshot.records[i].v[0]
   if v[0] != snapshot.total - snapshot.retained + i + 1 || v[12] > 1 || v[2] > u32(-1)
    || v[5] > 0x7fffffff || v[6] > 0x7fffffff || v[7] > u32(-1) || v[8] > u32(-1)
    || v[9] > u32(-1) || v[10] > u32(-1) || v[11] > u32(-1) || (v[12] == 0 && (v[13] != 0 || v[14] != 0)) { return -1 }
  }
  return if usize(C.vka_token(nil, c'\n', &line_save)) != 0 { -1 } else { 0 }
 }
}
fn put(output &C.output, text &char) i32 {
 unsafe {
  length := C.strlen(text)
  if length >= 139264 - output.used { C.vka_set_errno(3); return -1 }
  C.memcpy(&output.bytes[output.used], text, length + 1); output.used += length; return 0
 }
}
fn decimal(output &C.output, value u64) i32 {
 unsafe {
  mut digits := [21]char{}
  mut index := usize(20); mut n := value
  for { index--; digits[index] = char(48 + n % 10); n /= 10; if n == 0 { break } }
  return put(output, &digits[index])
 }
}
fn prefix(output &C.output, collector &C.collector, kind &char) i32 {
 unsafe {
  return if put(output, kind) != 0 || put(output, c' session=') != 0 || put(output, &collector.session[0]) != 0
   || put(output, c' epoch=') != 0 || decimal(output, collector.epoch) != 0 { -1 } else { 0 }
 }
}
fn unavailable(output &C.output, collector &C.collector, sequence u64, reason &char) i32 {
 return if prefix(output, collector, c'outcome_unavailable') != 0 || put(output, c' sequence=') != 0
  || decimal(output, sequence) != 0 || put(output, c' reason=') != 0 || put(output, reason) != 0 || put(output, c'\n') != 0 { -1 } else { 0 }
}
@[export: 'vka_end_pending']
pub fn end_pending(output &C.output, collector &C.collector, reason &char) i32 {
 unsafe {
  for i := usize(0); i < collector.pending_count; i++ { if unavailable(output, collector, collector.pending[i].v[0], reason) != 0 { return -1 } }
  return 0
 }
}
fn row(output &C.output, collector &C.collector, record &C.record, kind &char) i32 {
 unsafe {
  keys := [&char(c' sequence='), &char(c' ns='), &char(c' arch='), &char(c' syscall='), &char(c' ip='), &char(c' pid='), &char(c' tid='), &char(c' uid='), &char(c' euid='), &char(c' gid='), &char(c' egid='), &char(c' action='), &char(c' completed='), &char(c' result='), &char(c' errno=')]!
  if prefix(output, collector, kind) != 0 { return -1 }
  for j := 0; j < 15; j++ { if put(output, keys[j]) != 0 || decimal(output, record.v[j]) != 0 { return -1 } }
  return put(output, c'\n')
 }
}
@[export: 'vka_collect']
pub fn collect(collector &C.collector, snapshot &C.snapshot, output &C.output) i32 {
 unsafe {
  output.used = 0
  reset := collector.started != 0 && (C.strcmp(&collector.boot[0], &snapshot.boot[0]) != 0 || snapshot.total < collector.total)
  if reset && end_pending(output, collector, c'source_reset') != 0 { return -1 }
  if collector.started == 0 || reset {
   collector.epoch++; C.strcpy(&collector.boot[0], &snapshot.boot[0]); collector.last = 0; collector.total = 0; collector.dropped = 0
   collector.pending_count = 0; collector.observed_count = 0
   if prefix(output, collector, c'boundary') != 0 || put(output, c' boot=') != 0 || put(output, &collector.boot[0]) != 0
    || put(output, c' reason=') != 0 || put(output, if reset { c'source_reset' } else { c'collector_start' }) != 0 || put(output, c'\n') != 0 { return -1 }
   collector.started = 1
  }
  first := snapshot.total - snapshot.retained + 1
  for i := usize(0); i < collector.observed_count; i++ {
   old := &collector.observed[i]; seq := old.v[0]
   if seq < first || seq > snapshot.total { continue }
   now := &snapshot.records[seq - first]
   if C.memcmp(&old.v[0], &now.v[0], 12 * sizeof(u64)) != 0 || (old.v[12] != 0 && C.memcmp(&old.v[12], &now.v[12], 3 * sizeof(u64)) != 0) { C.vka_set_errno(4); return -1 }
  }
  if snapshot.retained != 0 && first > collector.last && first - collector.last > 1 {
   if prefix(output, collector, c'loss') != 0 || put(output, c' first=') != 0 || decimal(output, collector.last + 1) != 0
    || put(output, c' last=') != 0 || decimal(output, first - 1) != 0 || put(output, c' count=') != 0
    || decimal(output, first - collector.last - 1) != 0 || put(output, c' reason=not_observed\n') != 0 { return -1 }
  }
  for i := usize(0); i < collector.pending_count; i++ {
   old := &collector.pending[i]; seq := old.v[0]
   if seq < first || seq > snapshot.total { if unavailable(output, collector, seq, c'ring_eviction') != 0 { return -1 }; continue }
   now := &snapshot.records[seq - first]
   if C.memcmp(&old.v[0], &now.v[0], 12 * sizeof(u64)) != 0 { C.vka_set_errno(4); return -1 }
   if now.v[12] != 0 && row(output, collector, now, c'completion') != 0 { return -1 }
  }
  previous := collector.last; collector.pending_count = 0
  for i := u64(0); i < snapshot.retained; i++ {
   record := &snapshot.records[i]
   if record.v[0] > previous && row(output, collector, record, c'decision') != 0 { return -1 }
   if record.v[12] == 0 { collector.pending[collector.pending_count] = *record; collector.pending_count++ }
  }
  if output.used != 0 || snapshot.total != collector.total || snapshot.dropped != collector.dropped {
   if prefix(output, collector, c'snapshot') != 0 || put(output, c' total=') != 0 || decimal(output, snapshot.total) != 0
    || put(output, c' retained=') != 0 || decimal(output, snapshot.retained) != 0 || put(output, c' overwritten=') != 0
    || decimal(output, snapshot.dropped) != 0 || put(output, c'\n') != 0 { return -1 }
  }
  collector.last = snapshot.total; collector.total = snapshot.total; collector.dropped = snapshot.dropped
  collector.observed_count = usize(snapshot.retained)
  C.memcpy(&collector.observed[0], &snapshot.records[0], collector.observed_count * sizeof(C.record))
  return 0
 }
}
@[export: 'vka_log_stat']
pub fn log_stat(fd i32, owner u32) i32 {
 mut st := C.vka_stat{}
 if C.vka_stat(fd, &st) != 0 { return -1 }
 if st.regular == 0 || st.owner != owner || (st.mode & 0o7777) != 0o600 || st.links != 1 { C.vka_set_errno(5); return -1 }
 return 0
}
@[export: 'vka_directory_stat']
pub fn directory_stat(fd i32, owner u32) i32 {
 mut st := C.vka_stat{}
 if C.vka_stat(fd, &st) != 0 { return -1 }
 if st.directory == 0 || st.owner != owner || (st.mode & 0o22) != 0 { C.vka_set_errno(5); return -1 }
 return 0
}
fn close_error(fd i32) i32 { e := C.vka_errno(); C.vka_close(fd); C.vka_restore_errno(e); return -1 }
@[export: 'vka_open_log_at']
pub fn open_log_at(parent i32, name &char, owner u32, previous i32) i32 {
 unsafe {
  if directory_stat(parent, owner) != 0 { return -1 }
  if name[0] == 0 || usize(C.strchr(name, 47)) != 0 || C.strcmp(name, c'.') == 0 || C.strcmp(name, c'..') == 0 { C.vka_set_errno(6); return -1 }
  mut fd := C.vka_open_log_file(parent, name, 1); created := fd >= 0
  if fd < 0 && C.vka_is_error(1) != 0 { fd = C.vka_open_log_file(parent, name, 0) }
  if fd < 0 { return -1 }
  if created && C.vka_fsync(parent) != 0 { return close_error(fd) }
  if log_stat(fd, owner) != 0 { return close_error(fd) }
  if previous >= 0 {
   mut old := C.vka_stat{}; mut now := C.vka_stat{}
   if C.vka_stat(previous, &old) != 0 || C.vka_stat(fd, &now) != 0 { return close_error(fd) }
   if old.device == now.device && old.inode == now.inode { C.vka_close(fd); return C.vka_dup(previous) }
  }
  if C.vka_lock(fd) != 0 { return close_error(fd) }
  return fd
 }
}
@[export: 'vka_open_log']
pub fn open_log(path &char, previous i32) i32 {
 unsafe {
  if path[0] != 47 || C.strlen(path) >= C.vka_path_max() { C.vka_set_errno(6); return -1 }
  mut copy := [4096]char{}; C.strcpy(&copy[0], path + 1)
  mut dir := C.vka_open_root(); if dir < 0 { return -1 }
  mut save := &char(nil); mut part := C.vka_token(&copy[0], c'/', &save)
  if usize(part) == 0 { C.vka_close(dir); C.vka_set_errno(6); return -1 }
  for {
   next := C.vka_token(nil, c'/', &save)
   if directory_stat(dir, 0) != 0 { break }
   if C.strcmp(part, c'.') == 0 || C.strcmp(part, c'..') == 0 { C.vka_set_errno(6); break }
   if usize(next) == 0 { fd := open_log_at(dir, part, 0, previous); e := C.vka_errno(); C.vka_close(dir); C.vka_restore_errno(e); return fd }
   mut child := C.vka_open_dir(dir, part)
   if child < 0 && C.vka_is_error(2) != 0 {
    if C.vka_mkdir(dir, part) != 0 { break }
    if C.vka_fsync(dir) != 0 { break }
    child = C.vka_open_dir(dir, part)
   }
   if child < 0 { break }
   C.vka_close(dir); dir = child; part = next
  }
  if C.vka_errno() == 0 { C.vka_set_errno(6) }
  return close_error(dir)
 }
}
@[export: 'vka_append']
pub fn append(fd i32, output &C.output, owner u32) i32 {
 unsafe {
  if output.used == 0 { return 0 }
  if log_stat(fd, owner) != 0 { return -1 }
  for done := usize(0); done < output.used; {
   n := C.vka_write(fd, &output.bytes[done], output.used - done)
   if n < 0 && C.vka_is_error(0) != 0 { continue }
   if n <= 0 { if n == 0 { C.vka_set_errno(7) }; return -1 }
   done += usize(n)
  }
  return C.vka_fsync(fd)
 }
}
@[export: 'vka_read_snapshot']
pub fn read_snapshot(path &char, snapshot &C.snapshot) i32 {
 unsafe {
  fd := C.vka_open_read(path); if fd < 0 { return -1 }
  mut buffer := [65536]char{}; mut used := usize(0)
  for {
   n := C.vka_read(fd, &buffer[used], 65536 - used - 1)
   if n < 0 && C.vka_is_error(0) != 0 { continue }
   if n < 0 { return close_error(fd) }; if n == 0 { break }
   used += usize(n)
   if used == 65535 { C.vka_close(fd); C.vka_set_errno(3); return -1 }
  }
  if C.vka_close(fd) != 0 { return -1 }
  if used == 0 || buffer[used - 1] != 10 || usize(C.memchr(&buffer[0], 0, used)) != 0 { C.vka_set_errno(4); return -1 }
  buffer[used] = 0
  if parse_snapshot(&buffer[0], snapshot) != 0 { C.vka_set_errno(4); return -1 }
  return 0
 }
}
fn session_id(out &char) i32 {
 unsafe {
  fd := C.vka_open_read(c'/dev/urandom'); if fd < 0 { return -1 }
  mut bytes := [16]u8{}
  for done := usize(0); done < 16; {
   n := C.vka_read(fd, &bytes[done], 16 - done)
   if n < 0 && C.vka_is_error(0) != 0 { continue }
   if n <= 0 { if n == 0 { C.vka_set_errno(7) }; return close_error(fd) }; done += usize(n)
  }
  C.vka_close(fd); hex := &char(c'0123456789abcdef')
  for i := 0; i < 16; i++ { out[i * 2] = hex[bytes[i] >> 4]; out[i * 2 + 1] = hex[bytes[i] & 15] }
  out[32] = 0; return 0
 }
}
fn start_line(output &C.output, collector &C.collector) i32 {
 unsafe { return if put(output, c'\nsession_start session=') != 0 || put(output, &collector.session[0]) != 0 || put(output, c' wall_ns=') != 0
 || decimal(output, C.vka_wall_ns()) != 0 || put(output, c' pid=') != 0 || decimal(output, u64(C.vka_pid())) != 0 || put(output, c' source=seccomp\n') != 0 { -1 } else { 0 } }
}
fn reopen_line(output &C.output, collector &C.collector) i32 {
 unsafe { return if prefix(output, collector, c'\nlog_reopen') != 0 || put(output, c' boot=') != 0 || put(output, &collector.boot[0]) != 0 || put(output, c' last=') != 0
 || decimal(output, collector.last) != 0 || put(output, c' wall_ns=') != 0 || decimal(output, C.vka_wall_ns()) != 0 || put(output, c'\n') != 0 { -1 } else { 0 } }
}
fn end_line(output &C.output, collector &C.collector, once bool) i32 {
 unsafe { return if end_pending(output, collector, c'collector_stop') != 0 || put(output, c'session_end session=') != 0 || put(output, &collector.session[0]) != 0
 || put(output, c' wall_ns=') != 0 || decimal(output, C.vka_wall_ns()) != 0 || put(output, c' last=') != 0 || decimal(output, collector.last) != 0
 || put(output, c' reason=') != 0 || put(output, if once { c'one_shot' } else { c'signal' }) != 0 || put(output, c'\n') != 0 { -1 } else { 0 } }
}
@[export: 'vka_main']
pub fn audit_main(argc i32, argv &&char) i32 {
 unsafe {
  mut path := &char(c'/var/log/vinix-audit/seccomp.log'); mut source := &char(c'/proc/security_audit'); mut interval := u64(250); mut once := false
  for i := i32(1); i < argc; i++ {
   if C.strcmp(argv[i], c'--once') == 0 { once = true }
   else if C.strcmp(argv[i], c'--log') == 0 && i + 1 < argc { i++; path = argv[i] }
   else if C.strcmp(argv[i], c'--source') == 0 && i + 1 < argc { i++; source = argv[i] }
   else if C.strcmp(argv[i], c'--interval-ms') == 0 && i + 1 < argc {
    i++; if number(argv[i], &interval) != 0 || interval < 10 || interval > 60000 { C.vka_usage(); return 2 }
   } else { C.vka_usage(); return 2 }
  }
  if C.vka_uid() != 0 || C.vka_euid() != 0 { C.vka_root_required(); return 1 }
  C.vka_umask()
  if C.vka_signals() != 0 { C.vka_perror(c'vinix-security-audit: signals'); return 1 }
  mut collector := C.collector{}
  if session_id(&collector.session[0]) != 0 { C.vka_perror(c'vinix-security-audit: session entropy'); return 1 }
  mut snapshot := C.snapshot{}
  // Canonical authority is checked even for a diagnostic source override.
  if read_snapshot(c'/proc/security_audit', &snapshot) != 0 || (C.strcmp(source, c'/proc/security_audit') != 0 && read_snapshot(source, &snapshot) != 0) { C.vka_perror(c'vinix-security-audit: snapshot'); return 1 }
  mut fd := open_log(path, -1)
  if fd < 0 { C.vka_perror(c'vinix-security-audit: secure log'); return 1 }
  mut output := C.output{}
  mut failed := start_line(&output, &collector) != 0 || append(fd, &output, 0) != 0
  for !failed {
   mut next := collector
   if collect(&next, &snapshot, &output) != 0 || append(fd, &output, 0) != 0 { failed = true; break }
   collector = next
   if once || C.stopping != 0 { break }
   mut seconds := interval / 1000; mut nanoseconds := (interval % 1000) * 1000000
   for C.vka_sleep(&seconds, &nanoseconds) < 0 {
    if C.vka_is_error(0) == 0 { failed = true; break }
    if C.stopping != 0 || C.reopening != 0 { break }
   }
   if failed { break }
   if C.reopening != 0 {
    C.reopening = 0
    new_fd := open_log(path, fd); if new_fd < 0 { failed = true; break }
    C.vka_close(fd); fd = new_fd; output.used = 0
    if reopen_line(&output, &collector) != 0 || append(fd, &output, 0) != 0 { failed = true; break }
   }
   if read_snapshot(source, &snapshot) != 0 { failed = true; break }
  }
  if !failed { output.used = 0; failed = end_line(&output, &collector, once) != 0 || append(fd, &output, 0) != 0 }
  if failed {
   e := C.vka_errno(); C.vka_collection_error(e); output.used = 0
   if put(&output, c'\ncollector_error session=') == 0 && put(&output, &collector.session[0]) == 0 && put(&output, c' wall_ns=') == 0
    && decimal(&output, C.vka_wall_ns()) == 0 && put(&output, c' errno=') == 0 && decimal(&output, u64(e)) == 0 && put(&output, c'\n') == 0 { append(fd, &output, 0) }
  }
  if C.vka_close(fd) != 0 { C.vka_perror(c'vinix-security-audit: log close'); failed = true }
  return if failed { 1 } else { 0 }
 }
}
