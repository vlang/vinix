// SPDX-License-Identifier: GPL-2.0-or-later
// Independent resource-open and exact retained-object regression.
@[translated]
@[has_globals]
module resourcefixture

#include <resource-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.vro_ull {}
@[typedef] struct C.vro_ll {}
@[typedef] struct C.dev_t {}
struct C.termios {}
struct C.stat { mut: st_rdev C.dev_t }
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global resource_trace [262144]char
struct Heap { mut: count u32 size [32]u64 live [32]u64 large u64 written_after_free u64 }

fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strtok(&char, &char) &char
fn C.posix_openpt(i32) i32
fn C.grantpt(i32) i32
fn C.unlockpt(i32) i32
fn C.ptsname_r(i32, &char, usize) i32
fn C.tcgetattr(i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.access(&char, i32) i32
fn C.dup(i32) i32
fn C.stat(&char, &C.stat) i32
fn C.mknod(&char, u32, C.dev_t) i32
fn C.unlink(&char) i32
fn C.pipe(&i32) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.usleep(u32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.pause() i32

fn check(ok bool, line i32, expression &char) bool {
 unsafe { if !ok { C.printf(c'FAIL: resource open line=%d %s errno=%d\n', line, expression, C.errno) }; return ok }
}
fn word(value C.vro_ull) u64 { unsafe { result := u64(0); C.memcpy(&result, &value, 8); return result } }
fn unsigned_native(value u64) C.vro_ull { unsafe { result := C.vro_ull{}; C.memcpy(&result, &value, 8); return result } }
fn signed_native(value i64) C.vro_ll { unsafe { result := C.vro_ll{}; C.memcpy(&result, &value, 8); return result } }

fn snapshot(out &Heap) i32 {
 unsafe {
  text := [65536]char{}
  C.memset(out, 0, sizeof(Heap))
  fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
  if !check(fd >= 0, 24, c'fd>=0') { return 1 }
  count := C.read(fd, &text[0], sizeof(text)-1)
  if !check(count > 0 && C.close(fd) == 0, 25, c'count>0&&close(fd)==0') { return 1 }
  text[count] = 0
  have_large := i32(0); have_frees := i32(0)
  for line := C.strtok(&text[0], c'\n'); line != nil; line = C.strtok(nil, c'\n') {
   size := C.vro_ull{}; live := C.vro_ull{}; pages := C.vro_ull{}
   large := C.vro_ull{}; frees := C.vro_ull{}
   if C.sscanf(line, c'size-%*u %llu %llu %llu', &size, &live, &pages) == 3 {
    if !check(out.count < 32, 30, c'out->count<32') { return 1 }
    i := out.count++; out.size[i] = word(size); out.live[i] = word(live)
   } else if C.sscanf(line, c'large - - %llu', &large) == 1 { out.large = word(large); have_large = 1
   } else if C.sscanf(line, c'# written after free %llu', &frees) == 1 { out.written_after_free = word(frees); have_frees = 1 }
  }
  $if arm64 { if !check(out.count == 18 && have_large != 0 && have_frees != 0, 35, c'out->count==18&&have_large&&have_frees') { return 1 } }
  $else { if !check(out.count == 14 && have_large != 0 && have_frees != 0, 37, c'out->count==14&&have_large&&have_frees') { return 1 } }
  return 0
 }
}
fn trace(start i32, window i32) i32 {
 unsafe {
  fd := C.open(if start != 0 { c'/proc/allocstart' } else { c'/proc/allocsites' }, C.O_RDONLY)
  if fd < 0 { if !check(C.errno == C.ENOENT, 44, c'errno==ENOENT') { return 1 }; return 0 }
  n := C.read(fd, &resource_trace[0], sizeof(resource_trace)-1)
  if !check(n > 0 && C.close(fd) == 0, 45, c'n>0&&close(fd)==0') { return 1 }
  resource_trace[n] = 0
  if start == 0 {
   for line := C.strtok(&resource_trace[0], c'\n'); line != nil; line = C.strtok(nil, c'\n') { C.printf(c'PERF-SITE resource-open window=%d %s\n', window, line) }
  }
  return 0
 }
}
fn pty_cycle(reverse_close i32) i32 {
 unsafe {
  master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
  if !check(master >= 0, 52, c'master>=0') { return 1 }
  if !check(C.grantpt(master) == 0 && C.unlockpt(master) == 0, 53, c'grantpt(master)==0&&unlockpt(master)==0') { return 1 }
  name := [64]char{}
  if !check(C.ptsname_r(master, &name[0], sizeof(name)) == 0, 54, c'ptsname_r(master,name,sizeof(name))==0') { return 1 }
  slave := C.open(&name[0], C.O_RDWR | C.O_NOCTTY)
  if !check(slave >= 0, 55, c'slave>=0') { return 1 }
  settings := C.termios{}
  if !check(C.tcgetattr(slave, &settings) == 0, 56, c'tcgetattr(slave,&settings)==0') { return 1 }
  C.cfmakeraw(&settings)
  if !check(C.tcsetattr(slave, C.TCSANOW, &settings) == 0, 57, c'tcsetattr(slave,TCSANOW,&settings)==0') { return 1 }
  byte := u8(0)
  if !check(C.write(master, c'm', 1) == 1 && C.read(slave, &byte, 1) == 1 && byte == `m`, 59, c'write(master,"m",1)==1&&read(slave,&byte,1)==1&&byte==\'m\'') { return 1 }
  if !check(C.write(slave, c's', 1) == 1 && C.read(master, &byte, 1) == 1 && byte == `s`, 60, c'write(slave,"s",1)==1&&read(master,&byte,1)==1&&byte==\'s\'') { return 1 }
  if reverse_close != 0 { if !check(C.close(master) == 0 && C.read(slave, &byte, 1) == 0 && C.close(slave) == 0, 62, c'close(master)==0&&read(slave,&byte,1)==0&&close(slave)==0') { return 1 }
  } else { if !check(C.close(slave) == 0 && C.close(master) == 0, 63, c'close(slave)==0&&close(master)==0') { return 1 } }
  C.errno = 0
  if !check(C.access(&name[0], C.F_OK) == -1 && C.errno == C.ENOENT, 64, c'access(name,F_OK)==-1&&errno==ENOENT') { return 1 }
  return 0
 }
}
fn semantics() i32 {
 unsafe {
  master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
  if !check(master >= 0, 69, c'master>=0') { return 1 }
  name := [64]char{}
  if !check(C.ptsname_r(master, &name[0], sizeof(name)) == 0, 70, c'ptsname_r(master,name,sizeof(name))==0') { return 1 }
  C.errno = 0
  if !check(C.open(&name[0], C.O_RDWR | C.O_NOCTTY) == -1 && C.errno == C.EIO, 71, c'open(name,O_RDWR|O_NOCTTY)==-1&&errno==EIO') { return 1 }
  if !check(C.unlockpt(master) == 0, 72, c'unlockpt(master)==0') { return 1 }
  slave := C.open(&name[0], C.O_RDWR | C.O_NOCTTY)
  if !check(slave >= 0, 73, c'slave>=0') { return 1 }
  duplicate := C.dup(slave)
  if !check(duplicate >= 0 && C.close(slave) == 0 && C.close(master) == 0, 74, c'duplicate>=0&&close(slave)==0&&close(master)==0') { return 1 }
  byte := u8(0)
  if !check(C.read(duplicate, &byte, 1) == 0 && C.close(duplicate) == 0, 75, c'read(duplicate,&byte,1)==0&&close(duplicate)==0') { return 1 }
  C.errno = 0
  if !check(C.access(&name[0], C.F_OK) == -1 && C.errno == C.ENOENT, 76, c'access(name,F_OK)==-1&&errno==ENOENT') { return 1 }
  C.errno = 0
  if !check(C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY) == -1 && C.errno == C.ENXIO, 77, c'open("/dev/tty",O_RDWR|O_NOCTTY)==-1&&errno==ENXIO') { return 1 }
  info := C.stat{}
  if !check(C.stat(c'/dev/ptmx', &info) == 0, 80, c'stat("/dev/ptmx",&info)==0') { return 1 }
  if !check(C.mknod(c'/tmp/open-ptmx', C.S_IFCHR | 0o600, info.st_rdev) == 0, 81, c'mknod("/tmp/open-ptmx",S_IFCHR|0600,info.st_rdev)==0') { return 1 }
  master = C.open(c'/tmp/open-ptmx', C.O_RDWR | C.O_NOCTTY)
  if !check(master >= 0 && C.unlockpt(master) == 0, 82, c'master>=0&&unlockpt(master)==0') { return 1 }
  if !check(C.ptsname_r(master, &name[0], sizeof(name)) == 0, 83, c'ptsname_r(master,name,sizeof(name))==0') { return 1 }
  slave = C.open(&name[0], C.O_RDWR | C.O_NOCTTY)
  if !check(slave >= 0 && C.close(slave) == 0 && C.close(master) == 0, 84, c'slave>=0&&close(slave)==0&&close(master)==0') { return 1 }
  if !check(C.unlink(c'/tmp/open-ptmx') == 0, 85, c'unlink("/tmp/open-ptmx")==0') { return 1 }
  if !check(C.stat(c'/dev/null', &info) == 0 && C.mknod(c'/tmp/open-null', C.S_IFCHR | 0o600, info.st_rdev) == 0, 88, c'stat("/dev/null",&info)==0&&mknod("/tmp/open-null",S_IFCHR|0600,info.st_rdev)==0') { return 1 }
  fd := C.open(c'/tmp/open-null', C.O_RDWR)
  if !check(fd >= 0, 89, c'fd>=0') { return 1 }
  if !check(C.read(fd, &byte, 1) == 0 && C.write(fd, c'x', 1) == 1 && C.close(fd) == 0 && C.unlink(c'/tmp/open-null') == 0, 90, c'read(fd,&byte,1)==0&&write(fd,"x",1)==1&&close(fd)==0&&unlink("/tmp/open-null")==0') { return 1 }
  fd = C.open(c'/tmp/open-regular', C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
  if !check(fd >= 0, 91, c'fd>=0') { return 1 }
  if !check(C.write(fd, c'f', 1) == 1 && C.lseek(fd, 0, C.SEEK_SET) == 0 && C.read(fd, &byte, 1) == 1 && byte == `f`, 92, c'write(fd,"f",1)==1&&lseek(fd,0,SEEK_SET)==0&&read(fd,&byte,1)==1&&byte==\'f\'') { return 1 }
  if !check(C.close(fd) == 0 && C.unlink(c'/tmp/open-regular') == 0, 93, c'close(fd)==0&&unlink("/tmp/open-regular")==0') { return 1 }
  pipefd := [2]i32{}
  if !check(C.pipe(&pipefd[0]) == 0, 96, c'pipe(pipefd)==0') { return 1 }
  C.snprintf(&name[0], sizeof(name), c'/proc/self/fd/%d', pipefd[0])
  fd = C.open(&name[0], C.O_RDONLY | C.O_NONBLOCK)
  if !check(fd >= 0 && C.close(pipefd[0]) == 0, 98, c'fd>=0&&close(pipefd[0])==0') { return 1 }
  if !check(C.write(pipefd[1], c'p', 1) == 1 && C.read(fd, &byte, 1) == 1 && byte == `p`, 99, c'write(pipefd[1],"p",1)==1&&read(fd,&byte,1)==1&&byte==\'p\'') { return 1 }
  if !check(C.close(pipefd[1]) == 0 && C.read(fd, &byte, 1) == 0 && C.close(fd) == 0, 100, c'close(pipefd[1])==0&&read(fd,&byte,1)==0&&close(fd)==0') { return 1 }
  C.printf(c'RESOURCE OPEN semantics PASS\n')
  return 0
 }
}
fn cohort() i32 {
 unsafe {
  for i := i32(0); i < 200; i++ { if !check(pty_cycle(i & 1) == 0, 105, c'pty_cycle(i&1)==0') { return 1 } }
  C.usleep(11000000)
  return 0
 }
}
@[export: 'main']
pub fn entry() i32 {
 unsafe {
  C.setvbuf(C.stdout, nil, C._IONBF, 0)
  if C.access(c'/proc/slabinfo', C.F_OK) != 0 { if !check(C.mount(c'proc', c'/proc', c'proc', 0, nil) == 0, 112, c'mount("proc","/proc","proc",0,0)==0') { return 1 } }
  if !check(semantics() == 0 && cohort() == 0, 113, c'semantics()==0&&cohort()==0') { return 1 }
  if !check(trace(1, -1) == 0 && trace(0, -1) == 0, 114, c'trace(1,-1)==0&&trace(0,-1)==0') { return 1 }
  before := Heap{}; after := Heap{}
  for i := i32(0); i < 5; i++ { if !check(snapshot(&before) == 0, 116, c'snapshot(&before)==0') { return 1 } }
  for window := i32(0); window < 2; window++ {
   if !check(trace(1, window) == 0 && snapshot(&before) == 0 && cohort() == 0 && snapshot(&after) == 0, 118, c'trace(1,window)==0&&snapshot(&before)==0&&cohort()==0&&snapshot(&after)==0') { return 1 }
   if !check(before.count == after.count, 119, c'before.count==after.count') { return 1 }
   flat := i32(1)
   for i := u32(0); i < after.count; i++ {
    if !check(before.size[i] == after.size[i], 121, c'before.size[i]==after.size[i]') { return 1 }
    delta := i64(after.live[i]) - i64(before.live[i])
    C.printf(c'RESOURCE-OPEN window=%d class=%llu objects=%+lld\n', window, unsigned_native(after.size[i]), signed_native(delta))
    if delta != 0 { flat = 0 }
   }
   large := i64(after.large) - i64(before.large)
   C.printf(c'RESOURCE-OPEN window=%d large_pages=%+lld written_after_free=%llu flat=%d\n', window, signed_native(large), unsigned_native(after.written_after_free-before.written_after_free), flat)
   if !check(trace(0, window) == 0, 129, c'trace(0,window)==0') { return 1 }
   if !check(flat != 0 && large == 0 && after.written_after_free == before.written_after_free, 130, c'flat&&large==0&&after.written_after_free==before.written_after_free') { return 1 }
  }
  C.printf(c'RESOURCE OPEN: PASS\n')
  for { C.pause() }
  return 0
 }
}
