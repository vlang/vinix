// Run a standalone independent fixture as PID1 in a disposable native guest.
module fixturedriver

#include <fixture-driver-native-abi.h>
fn C.vinix_independent_fixture() i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
	if C.vinix_independent_fixture() != 0 {
		C.puts(c'INDEPENDENT FIXTURE FAIL')
	} else {
		C.puts(c'INDEPENDENT FIXTURE PASS')
	}
	C.fflush(unsafe { nil })
	for { C.pause() }
	return 0
}
