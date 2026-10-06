// Independent x86 SMT topology/policy fixture; native SDK macros stay upstream.
@[has_globals]
module guestfixture

#include <smt-native-abi.h>
@[typedef]
struct C.FILE {}
@[typedef]
struct C.cpu_set_t {}
@[c_extern]
__global C.stdout &C.FILE
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgetc(&C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.__get_cpuid_count(u32, u32, &u32, &u32, &u32, &u32) i32
fn C.CPU_ZERO(&C.cpu_set_t)
fn C.CPU_COUNT(&C.cpu_set_t) i32
fn C.sched_getaffinity(i32, usize, &C.cpu_set_t) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.reboot(i32) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		console := C.open(c'/dev/com1', C.O_WRONLY)
		if console >= 0 { C.dup2(console, 1); C.dup2(console, 2); C.close(console) }
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		request := C.fopen(c'/smt-request', c'r')
		enabled := if request != nil { C.fgetc(request) == i32(`1`) } else { true }
		if request != nil { C.fclose(request) }
		mut a := u32(0)
		mut b := u32(0)
		mut c := u32(0)
		mut d := u32(0)
		mut threads := u32(0)
		leaves := [u32(0x1f), 0xb]!
		for leaf := 0; leaf < 2 && threads == 0; leaf++ {
			for level in u32(0) .. u32(32) {
				if C.__get_cpuid_count(leaves[leaf], level, &a, &b, &c, &d) == 0 || (b & 65535) == 0 { break }
				if ((c >> 8) & 255) == 1 && (b & 65535) <= (u32(1) << (a & 31)) {
					threads = b & 65535
					break
				}
			}
		}
		expected := if enabled { i32(4) } else if threads != 0 { i32(4) / i32(threads) } else { i32(1) }
		mut mask := C.cpu_set_t{}
		C.CPU_ZERO(&mask)
		result := C.sched_getaffinity(0, sizeof(mask), &mask)
		count := if result != 0 { i32(-1) } else { C.CPU_COUNT(&mask) }
		C.printf(c'SMT POLICY: enabled=%d topology_threads=%u online=%d expected=%d\n', i32(enabled), threads, count, expected)
		C.puts(if count == expected { &char(c'SMT POLICY: PASS') } else { &char(c'SMT POLICY: FAIL') })
		C.reboot(C.RB_POWER_OFF)
		for { C.pause() }
		return 0
	}
}
