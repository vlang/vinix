// Minimal Linux AArch64 PID 1; host observes panics after the original verdict.
module armfixture

#include <pci-arm-fixture-native-abi.h>
fn C.vinix_pci_fixture_syscall3(isize, isize, isize, isize) isize

struct Delay { seconds isize nanoseconds isize }

@[export: '_start'; noreturn]
pub fn start() {
	unsafe {
		passed := &char(c'PCI ARM GUEST: Linux ABI PID1 PASS\n')
		failed := &char(c'PCI ARM GUEST: FAIL console write\n')
		if C.vinix_pci_fixture_syscall3(64, 1, isize(passed), 35) != 35 {
			C.vinix_pci_fixture_syscall3(64, 2, isize(failed), 34)
		}
		mut delay := Delay{1, 0}
		for { C.vinix_pci_fixture_syscall3(101, isize(&delay), 0, 0) }
	}
}
