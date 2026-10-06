// Native kmod metadata; no benchmark algorithms are implemented here.
@[has_globals]
module kmodmeta

fn C.kmod_alloc_start(voidptr, voidptr) i32
fn C.kmod_alloc_stop(voidptr, voidptr) i32

// Every original four-byte-packed offset also matches packed+aligned(4).
// The generator checks each offset before building the Darwin descriptor.
@[aligned: 4]
@[packed]
struct Info {
	next            voidptr
	info_version    i32
	id              u32
	name            [64]u8
	version         [64]u8
	reference_count i32
	reference_list  voidptr
	address         usize
	size            usize
	hdr_size        usize
	start           fn (voidptr, voidptr) i32 @[required]
	stop            fn (voidptr, voidptr) i32 @[required]
}

@[export: 'kmod_info']
__global kmod_info = Info{
	info_version:    1
	id:              0xffffffff
	name:            [u8(111), 114, 103, 46, 118, 105, 110, 105, 120, 46, 65, 108, 108, 111, 99,
		75, 101, 114, 110, 101, 108, 66, 101, 110, 99, 104, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
	version:         [u8(49), 46, 48, 46, 48, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
	reference_count: -1
	start:           C.kmod_alloc_start
	stop:            C.kmod_alloc_stop
}
