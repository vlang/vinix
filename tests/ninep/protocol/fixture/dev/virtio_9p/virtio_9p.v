@[has_globals]
module virtio_9p

import fs.ninep

pub struct Channel {
pub mut:
	tx &u8 = unsafe { nil }
	rx &u8 = unsafe { nil }
}

struct Object {
mut:
	present bool
	parent  u32
	name    string
	mode    u32
	uid     u32
	gid     u32
	atime_sec u64
	atime_nsec u64
	mtime_sec u64
	mtime_nsec u64
	size    u64
	data    [8192]u8
}

__global (
	channel          Channel
	ninep_fixture_tx [65536]u8
	ninep_fixture_rx [65536]u8
	objects          [32]Object
	fids             [2048]u32
	connected        bool
	calls            int
	closes           int
	setattr_mask     u32
)

pub fn connect(tag string) ?&Channel {
	if connected || tag != 'share' { return none }
	connected = true
	channel.tx = &ninep_fixture_tx[0]
	channel.rx = &ninep_fixture_rx[0]
	for i in 0 .. 2048 { fids[i] = 0 }
	for i in 0 .. 32 { objects[i] = Object{} }
	objects[1] = Object{ present: true, mode: 0o40755, name: '/', parent: 1 }
	objects[2] = Object{ present: true, mode: 0o100644, name: 'alpha', parent: 1, size: 3 }
	objects[2].data[0] = `o`
	objects[2].data[1] = `l`
	objects[2].data[2] = `d`
	return &channel
}

pub fn (mut _ Channel) close() {
	connected = false
	closes++
}

pub fn host_edit() {
	objects[2].size = 5
	for i, c in 'fresh' { objects[2].data[i] = c }
}

pub fn host_size() u64 { return objects[2].size }

pub fn host_mode() u32 { return objects[2].mode }

pub fn host_chmod(mode u32) { objects[2].mode = 0x8000 | mode }

pub fn last_setattr_mask() u32 { return setattr_mask }

pub fn host_present(name string, present bool) {
	for i in 2 .. 32 { if objects[i].name == name { objects[i].present = present; return } }
	assert false
}

pub fn call_count() int { return calls }

pub fn close_count() int { return closes }

pub fn live_fids() int {
	mut count := 0
	for f in fids { if f != 0 { count++ } }
	return count
}

fn qid(mut w ninep.Writer, id u32) {
	w.byte(if objects[id].mode & 0xf000 == 0x4000 { u8(0x80) } else { u8(0) })
	w.dword(0)
	w.qword(id)
}

fn text(mut r ninep.Reader) string {
	n := r.word()
	start := r.pos
	assert r.take(n)
	return unsafe { tos(r.data + start, int(n)) }
}

fn lookup(parent u32, name string) u32 {
	for i in 1 .. 32 {
		if objects[i].present && objects[i].parent == parent && objects[i].name == name {
			return u32(i)
		}
	}
	return 0
}

pub fn exchange(_ voidptr, request &u8, length u32, response &u8, capacity u32) int {
	assert connected
	calls++
	mut r := ninep.reader(request, length)
	assert r.dword() == length
	kind := r.byte()
	tag := r.word()
	mut w := ninep.writer(response, capacity, kind + 1, tag)
	match kind {
		ninep.tversion {
			m := r.dword()
			assert text(mut r) == '9P2000.L'
			w.dword(m)
			w.text('9P2000.L')
		}
		ninep.tattach {
			fid := r.dword()
			assert fid < 2048
			fids[fid] = 1
			qid(mut w, 1)
		}
		ninep.twalk {
			fid := r.dword()
			fresh := r.dword()
			n := r.word()
			assert fid < 2048 && fresh < 2048 && fids[fid] != 0
			mut id := fids[fid]
			if n != 0 {
				assert n == 1
				id = lookup(id, text(mut r))
				assert id != 0
			}
			fids[fresh] = id
			w.word(n)
			if n != 0 { qid(mut w, id) }
		}
		ninep.tgetattr {
			fid := r.dword()
			id := fids[fid]
			assert id != 0
			w.qword(0x7ff)
			qid(mut w, id)
			w.dword(objects[id].mode)
			w.dword(objects[id].uid)
			w.dword(objects[id].gid)
			w.qword(1)
			w.qword(0)
			w.qword(objects[id].size)
			w.qword(4096)
			w.qword(0)
			w.qword(objects[id].atime_sec)
			w.qword(objects[id].atime_nsec)
			w.qword(objects[id].mtime_sec)
			w.qword(objects[id].mtime_nsec)
			for _ in 0 .. 6 { w.qword(0) }
		}
		ninep.tlopen {
			fid := r.dword()
			assert fids[fid] != 0
			qid(mut w, fids[fid])
			w.dword(0)
		}
		ninep.tclunk {
			fid := r.dword()
			assert fids[fid] != 0
			fids[fid] = 0
		}
		ninep.tread {
			fid := r.dword()
			offset := r.qword()
			count := r.dword()
			id := fids[fid]
			n := if offset >= objects[id].size {
				u32(0)
			} else if objects[id].size - offset < count {
				u32(objects[id].size - offset)
			} else {
				count
			}
			w.dword(n)
			w.raw(unsafe { &objects[id].data[offset] }, n)
		}
		ninep.twrite {
			fid := r.dword()
			offset := r.qword()
			count := r.dword()
			id := fids[fid]
			assert offset <= 8192 && count <= 8192 - offset
			for i := u32(0); i < count; i++ { objects[id].data[offset + i] = r.byte() }
			if offset + count > objects[id].size { objects[id].size = offset + count }
			w.dword(count)
		}
		ninep.tsetattr {
			fid := r.dword()
			mask := r.dword()
			mode := r.dword()
			uid := r.dword()
			gid := r.dword()
			size := r.qword()
			atime_sec := r.qword()
			atime_nsec := r.qword()
			mtime_sec := r.qword()
			mtime_nsec := r.qword()
			id := fids[fid]
			setattr_mask = mask
			if mask & 1 != 0 { objects[id].mode = (objects[id].mode & 0xf000) | mode }
			if mask & 2 != 0 { objects[id].uid = uid }
			if mask & 4 != 0 { objects[id].gid = gid }
			if mask & 16 != 0 { objects[id].atime_sec = atime_sec; objects[id].atime_nsec = atime_nsec }
			if mask & 32 != 0 { objects[id].mtime_sec = mtime_sec; objects[id].mtime_nsec = mtime_nsec }
			if mask & 8 != 0 {
				assert size <= 8192
				objects[id].size = size
			}
		}
		ninep.treaddir {
			fid := r.dword()
			offset := r.qword()
			r.dword()
			dir := fids[fid]
			mut id := u32(0)
			for i := u32(2); i < 32; i++ {
				if i > offset && objects[i].present && objects[i].parent == dir {
					id = i
					break
				}
			}
			if id == 0 {
				w.dword(0)
			} else {
				w.dword(u32(24 + objects[id].name.len))
				qid(mut w, id)
				w.qword(id)
				w.byte(if objects[id].mode & 0xf000 == 0x4000 { u8(4) } else { u8(8) })
				w.text(objects[id].name)
			}
		}
		ninep.tmkdir, ninep.tlcreate {
			fid := r.dword()
			name := text(mut r)
			if kind == ninep.tlcreate { r.dword() }
			mode := r.dword()
			r.dword()
			mut id := u32(0)
			for i in 3 .. 32 {
				if !objects[i].present {
					id = u32(i)
					break
				}
			}
			assert id != 0 && lookup(fids[fid], name) == 0
			objects[id] = Object{ present: true, parent: fids[fid], name: name.clone(), mode: mode | if kind == ninep.tmkdir {
				u32(0x4000)
			} else {
				u32(0x8000)
			} }
			qid(mut w, id)
			if kind == ninep.tlcreate {
				fids[fid] = id
				w.dword(0)
			}
		}
		ninep.trenameat {
			old := r.dword()
			name := text(mut r)
			new := r.dword()
			target := text(mut r)
			id := lookup(fids[old], name)
			assert id != 0
			objects[id].parent = fids[new]
			objects[id].name = target.clone()
		}
		ninep.tunlinkat {
			dir := r.dword()
			name := text(mut r)
			id := lookup(fids[dir], name)
			assert id != 0
			objects[id].present = false
		}
		ninep.tfsync {}
		else {
			assert false, 'unhandled RPC'
		}
	}
	return int(w.finish())
}
