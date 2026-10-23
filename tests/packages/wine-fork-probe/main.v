// Local unsigned translator discriminator: fork, distinct new code in both
// branches, wait, no exec. This is not a Wine or graphical execution proof.
module main

#include <unistd.h>
#include <sys/wait.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.write(int, voidptr, usize) isize

fn emit(text string) {
	if C.write(1, text.str, usize(text.len)) != text.len { C._exit(90) }
}

const child_expected = [u64(0xb466aaeae3780b1c), 0x759c933dc6930e71,
	0x7c91cddb1fbcf4d6, 0x3dd69d4c037426f1, 0x8b4aa85720844a17, 0x912506965009b842,
	0x991f7803b6b0de76, 0x4e1dfc429067307e, 0xf9e9a6f2891e327e, 0x53e45dcc07e3a4db,
	0x4ff44ae122d1b915, 0xfa054fbf633f1610, 0x702b7c6bc76eefef, 0x4d4446d54f4485fb,
	0xf3b2923b6abdf280, 0xc851ed8102951327, 0xec6d4aadba040883, 0xed30f62895fc3292,
	0x90b04d7441401f7d, 0xb2c8ada69e6235a1, 0xcf907f93179b6522, 0x713968c8bdba3009,
	0x444a3cd8b531c54c, 0x5894b10675d71bb5, 0x4399a528ef556db4, 0xd5f929d8825ddd71,
	0x8bf9c2dd7a984d3f, 0xfb7f0fe097141e39, 0xee204b4fdc22bbb8, 0xf18bf4c48210d967,
	0x63d2d94067b38ba4, 0xd85b9ad2ae63ff03]!

const parent_expected = [u64(0x708db3450649c883), 0x2a28fc83e7f2e561,
	0x4c27422a9c7e5875, 0xc3efd7b5326f3118, 0x1dc7224406a2c96e, 0xd40a2db1111d298d,
	0xb296329b39c49cbf, 0x845c0cae1e7aa73f, 0xe8e8325f80c14770, 0x322cea215a5a10fe,
	0x919778c6dc2a81a1, 0xc1c64b168c64050a, 0x72cda63d58533aca, 0xb085f2865637eacc,
	0x219fb07775bd7493, 0x5fc4d32ab872315a, 0xba3ce3eb7aa7519e, 0x914eece7975c9dd3,
	0x6fddf5278490e40b, 0x4acedb683578704a, 0xf7a4e201f7677dee, 0x5f59bc91e75b3bac,
	0x35f2c826c90e9670, 0x85b6b6b1beabe74a, 0x5a7354199580aacf, 0x27fd8466ebe25773,
	0x249c0439277bc3ee, 0xafcf2dd53a0afb94, 0x2f9de7587aca1c1a, 0xc363bc23a4f14edd,
	0xdb5746be8cd0990c, 0xb3413bc6e6d26798]!

@[noinline]
fn child_loop(seed u64) u64 {
	mut value := u64(0x9e3779b97f4a7c15) ^ seed
	for i := u64(0); i < 20000 + seed; i++ {
		value ^= value << 13
		value ^= value >> 7
		value ^= value << 17
		value += i
	}
	return value
}

@[noinline]
fn parent_loop(seed u64) u64 {
	mut value := u64(0xd1b54a32d192ed03) ^ seed
	for i := u64(0); i < 30000 + seed; i++ {
		value ^= value >> 12
		value ^= value << 25
		value ^= value >> 27
		value = value * u64(0x2545f4914f6cdd1d) + i
	}
	return value
}

fn main() {
	emit('VINIX QEMU FORK NOEXEC START\n')
	for index in 0 .. 32 {
		pid := C.fork()
		if pid < 0 { emit('VINIX QEMU FORK NOEXEC FAIL fork\n'); exit(1) }
		if pid == 0 {
			if child_loop(u64(index + 1)) != child_expected[index] { C._exit(91) }
			emit('VINIX QEMU FORK NOEXEC CHILD PASS\n')
			C._exit(0)
		}
		parent_ok := parent_loop(u64(index + 1)) == parent_expected[index]
		mut status := int(0)
		if C.waitpid(pid, unsafe { &status }, 0) != pid || status != 0 {
			emit('VINIX QEMU FORK NOEXEC FAIL child status\n')
			exit(1)
		}
		if !parent_ok { emit('VINIX QEMU FORK NOEXEC FAIL parent\n'); exit(1) }
	}
	emit('VINIX QEMU FORK NOEXEC 32 CHILDREN REAPED PASS\n')
}
