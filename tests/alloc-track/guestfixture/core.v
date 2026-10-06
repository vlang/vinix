// Independent native frame-capture and live-site aggregation guest.
@[has_globals]
module guestfixture

#include <guest-native-abi.h>
@[typedef]
struct C.FILE {}
@[typedef]
struct C.vtrack_guest_ull {}
@[c_extern]
__global C.stdout &C.FILE
__global track_guest_output [1048576]char
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.pipe(&i32) i32
fn C.strncmp(&char, &char, usize) i32
fn C.strchr(&char, i32) &char
fn C.sscanf(&char, &char, ...) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32
fn C.puts(&char) i32
fn C._exit(i32)
fn C.pause() i32

fn check(condition bool, original_line i32) {
	if !condition {
		C.printf(c'ALLOC TRACK FAIL: line %d\n', original_line)
		C.fflush(C.stdout)
		C._exit(1)
	}
}

fn value(native &C.vtrack_guest_ull) u64 {
	mut word := u64(0)
	unsafe { C.memcpy(&word, native, sizeof(u64)) }
	return word
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		start := C.open(c'/proc/allocstart', C.O_RDONLY)
		check(start >= 0, 18)
		mut byte := char(0)
		check(C.read(start, &byte, 1) >= 0, 20)
		check(C.close(start) == 0, 21)
		mut pipes := [128][2]i32{}
		for i in 0 .. 128 { check(C.pipe(&pipes[i][0]) == 0, 23) }
		sites := C.open(c'/proc/allocsites', C.O_RDONLY)
		check(sites >= 0, 25)
		mut used := usize(0)
		for {
			n := C.read(sites, &track_guest_output[used], 1048575 - used)
			check(n >= 0, 30)
			if n == 0 { break }
			used += usize(n)
			check(used < 1048575, 33)
		}
		track_guest_output[used] = 0
		check(C.close(sites) == 0 && C.strncmp(&track_guest_output[0], c'live ', 5) == 0, 36)
		mut live := C.vtrack_guest_ull{}
		mut dropped := C.vtrack_guest_ull{}
		check(C.sscanf(&track_guest_output[0], c'live %llu dropped %llu', &live, &dropped) == 2, 38)
		check(value(&live) >= 128 && value(&dropped) == 0, 39)
		mut named := u32(0)
		mut line := C.strchr(&track_guest_output[0], i32(`\n`))
		check(line != nil, 42)
		line++
		for *line != 0 {
			mut count := C.vtrack_guest_ull{}
			mut size := C.vtrack_guest_ull{}
			mut pc := C.vtrack_guest_ull{}
			check(C.sscanf(line, c'%llu %llu %llx', &count, &size, &pc) == 3, 45)
			check(value(&count) >= 50 && value(&size) > 0 && value(&pc) != 0, 46)
			named++
			line = C.strchr(line, i32(`\n`))
			check(line != nil, 49)
			line++
		}
		check(named > 0, 52)
		for i in 0 .. 128 { check(C.close(pipes[i][0]) == 0 && C.close(pipes[i][1]) == 0, 54) }
		C.puts(c'ALLOC TRACK GUEST PASS')
		for { C.pause() }
		return 0
	}
}
