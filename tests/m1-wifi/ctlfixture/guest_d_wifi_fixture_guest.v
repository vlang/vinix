// SPDX-License-Identifier: ISC
@[translated]
module ctlfixture

@[typedef]
struct C.FILE {}

fn C.snprintf(&char, usize, &char, ...) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fputc(i32, &C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.fflush(&C.FILE) i32
fn C.fork() i32
fn C.exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.mkdir(&char, u32) i32
fn C.pause() i32

@[c_extern]
__global (
	C.EOF    i32
	C.stdout &C.FILE
)

fn bundle_file(name &char, size usize, value u8) {
	unsafe {
		mut path := [128]char{}
		C.snprintf(&path[0], sizeof(path), c'/tmp/wifi-ctl-fixture/%s', name)
		file := C.fopen(&path[0], c'wb')
		C.assert(file != nil)
		for i := usize(0); i < size; i++ { C.assert(C.fputc(value, file) != C.EOF) }
		C.assert(C.fclose(file) == 0)
	}
}

fn scenario(name &char, expected i32) {
	unsafe {
		C.fflush(nil)
		child := C.fork()
		C.assert(child >= 0)
		if child == 0 {
			mut args := [&char(c'fixture'), name, &char(c'/tmp/wifi-ctl-fixture'), &char(nil)]!
			result := fixture_main(if C.strncmp(name, c'load', 4) == 0 { i32(3) } else { i32(2) }, &&char(&args[0]))
			C.exit(result)
		}
		mut status := i32(0)
		C.assert(C.waitpid(child, &status, 0) == child)
		C.assert(C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == expected)
	}
}

fn guest_main() i32 {
	unsafe {
		cases := [&char(c'status'), &char(c'on'), &char(c'off'), &char(c'networks'), &char(c'invalid'),
			&char(c'scan'), &char(c'join'), &char(c'join-timeout'), &char(c'stop')]!
		for i := usize(0); i < sizeof(cases) / sizeof(cases[0]); i++ { scenario(cases[i], 0) }
		C.assert(C.mkdir(c'/tmp/wifi-ctl-fixture', 0o700) == 0)
		bundle_file(c'manifest.bin', 128, 0)
		manifest := C.fopen(c'/tmp/wifi-ctl-fixture/manifest.bin', c'r+b')
		C.assert(manifest != nil)
		C.assert(C.fputc(3, manifest) != C.EOF)
		C.assert(C.fclose(manifest) == 0)
		names := [&char(c'firmware.bin'), &char(c'nvram.txt'), &char(c'clm.blob'),
			&char(c'txcap.blob')]!
		for i := u32(0); i < 4; i++ {
			bundle_file(names[i], if i != 0 { usize(100) } else { usize(5000) }, u8(i + 1))
		}
		scenario(c'load', 0)
		bundle_file(c'txcap.blob', 0, 0)
		scenario(c'load-bad', 1)
		C.puts(c'VINIX_WIFI_CTL_VM_PASS')
		C.fflush(C.stdout)
		for { C.pause() }
		return 0
	}
}
