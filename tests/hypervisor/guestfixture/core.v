// Independent public hypervisor ABI fixture; physical VMX remains conditional.
@[has_globals]
module guestfixture

#include <hypervisor-guest-native-abi.h>
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stdout &C.FILE
struct C.vinix_hv_create { memory_size u64 }
struct C.vinix_hv_registers { rax u64 rdx u64 }
struct C.vinix_hv_entry { rip u64 rsp u64 rflags u64 }
struct C.vinix_hv_exit { reason u32 instruction_length u32 qualification u64 }
fn C.open(&char, i32, ...) i32
fn C.ioctl(i32, usize, ...) i32
fn C.pwrite(i32, voidptr, usize, isize) isize
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.fflush(&C.FILE) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.pause() i32

fn check(condition bool, original_line i32) {
	if !condition {
		unsafe { C.printf(c'HYPERVISOR FAIL: line %d errno %d\n', original_line, *C.__errno_location()) }
		C.fflush(C.stdout)
		C._exit(1)
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		mut fd := C.open(c'/dev/hypervisor', C.O_RDWR)
		if fd < 0 {
			check(*C.__errno_location() == C.ENOENT || *C.__errno_location() == C.ENODEV, 22)
			C.puts(c'HYPERVISOR UNAVAILABLE: device absent; VM entry was not exercised')
		} else {
			for iteration := u32(0); iteration < 5; iteration++ {
				if iteration != 0 { fd = C.open(c'/dev/hypervisor', C.O_RDWR) }
				check(fd >= 0 && C.ioctl(fd, usize(C.VINIX_HV_GET_API_VERSION), nil) == C.VINIX_HV_API_VERSION, 29)
				mut create := C.vinix_hv_create{memory_size: 0x10000}
				check(C.ioctl(fd, usize(C.VINIX_HV_CREATE_VM), &create) == 0, 31)
				code := [u8(0xba), 0xe9, 0, 0xb0, 0x56, 0xee, 0xf4]!
				check(C.pwrite(fd, &code[0], 7, 0x1000) == 7, 34)
				mut seed := [15]u64{}
				for i := u32(0); i < 15; i++ { seed[i] = u64(0x1234567800000000) | u64(i + iteration) }
				mut expected := C.vinix_hv_registers{}
				mut actual := C.vinix_hv_registers{}
				C.memcpy(&expected, &seed[0], sizeof(C.vinix_hv_registers))
				check(C.ioctl(fd, usize(C.VINIX_HV_SET_REGISTERS), &expected) == 0, 39)
				mut entry := C.vinix_hv_entry{rip: 0x1000, rsp: 0x8000, rflags: 2}
				check(C.ioctl(fd, usize(C.VINIX_HV_SET_ENTRY), &entry) == 0, 41)
				mut exit := C.vinix_hv_exit{}
				check(C.ioctl(fd, usize(C.VINIX_HV_RUN), &exit) == 0, 43)
				check(exit.reason == C.VINIX_HV_EXIT_IO && exit.instruction_length == 1, 44)
				check(u16(exit.qualification >> 16) == 0xe9, 45)
				expected.rax = (expected.rax & ~u64(0xff)) | 0x56
				expected.rdx = (expected.rdx & ~u64(0xffff)) | 0xe9
				check(C.ioctl(fd, usize(C.VINIX_HV_GET_REGISTERS), &actual) == 0, 48)
				check(C.memcmp(&actual, &expected, sizeof(C.vinix_hv_registers)) == 0, 49)
				check(C.ioctl(fd, usize(C.VINIX_HV_ADVANCE_RIP), &exit.instruction_length) == 0, 50)
				check(C.ioctl(fd, usize(C.VINIX_HV_RUN), &exit) == 0 && exit.reason == C.VINIX_HV_EXIT_HLT, 51)
				check(C.close(fd) == 0, 52)
			}
			C.puts(c'HYPERVISOR EXECUTION PASS: five guests, IO/HLT exits and all GPRs')
		}
		fd = C.open(c'/proc/meminfo', C.O_RDONLY)
		mut memory := [128]char{}
		check(fd >= 0 && C.read(fd, &memory[0], 128) > 0 && C.close(fd) == 0, 59)
		C.puts(c'HYPERVISOR GUEST PASS')
		for { C.pause() }
		return 0
	}
}
