module ninep

struct Server {
mut:
	calls     int
	mode      int
	last_kind u8
	last_fid  u32
	last_mode u32
}

fn exchange_fake(context voidptr, tx &u8, length u32, rx &u8, capacity u32) int {
	mut s := unsafe { &Server(context) }
	s.calls++
	mut request := reader(tx, length)
	assert request.dword() == length
	kind := request.byte()
	tag := request.word()
	s.last_kind = kind
	mut response := writer(rx, capacity, if s.mode == 1 { u8(7) } else { kind + 1 }, tag)
	if s.mode == 1 {
		response.dword(13)
		return int(response.finish())
	}
	if s.mode == 2 { return -110 }
	if s.mode == 3 {
		response.dword(0xffffffff)
		return int(response.finish())
	}
	match kind {
		tversion {
			assert request.dword() == 65536
			response.dword(if s.mode == 4 { u32(65537) } else { u32(4096) })
			response.text('9P2000.L')
		}
		tattach {
			s.last_fid = request.dword()
			response.byte(0x80)
			response.dword(0)
			response.qword(1)
		}
		twalk {
			request.dword()
			s.last_fid = request.dword()
			n := request.word()
			response.word(n)
			if n != 0 {
				response.byte(0)
				response.dword(0)
				response.qword(2)
			}
		}
		tlopen {
			response.byte(0)
			response.dword(0)
			response.qword(2)
			response.dword(0)
		}
		tgetattr { client_attr_frame(mut response) }
		tread {
			request.dword()
			request.qword()
			count := request.dword()
			response.dword(if count < 3 { count } else { u32(3) })
			for i in 0 .. int(if count < 3 { count } else { u32(3) }) { response.byte(u8(`a` + i)) }
		}
		twrite {
			request.dword()
			request.qword()
			count := request.dword()
			response.dword(count)
		}
		treaddir { response.dword(0) }
		tlcreate {
			request.dword()
			n := request.word()
			assert request.take(n)
			request.dword()
			s.last_mode = request.dword()
			response.byte(0)
			response.dword(0)
			response.qword(3)
			response.dword(0)
		}
		tmkdir {
			request.dword()
			n := request.word()
			assert request.take(n)
			s.last_mode = request.dword()
			response.byte(0x80)
			response.dword(0)
			response.qword(3)
		}
		tsetattr {
			request.dword()
			request.dword()
			s.last_mode = request.dword()
		}
		else {}
	}
	return int(response.finish())
}

fn test_real_client_rpc_subset_and_fid_reuse() {
	mut tx := [max_msize]u8{}
	mut rx := [max_msize]u8{}
	mut server := Server{}
	mut c := Client{ context: unsafe { &server }, exchange: exchange_fake, tx: unsafe { &tx[0] }, rx: unsafe { &rx[0] } }
	c.negotiate() or { assert false }
	assert c.msize == 4096
	root := c.attach(0) or { panic('attach') }
	fid := c.walk(root, 'file') or { panic('walk') }
	assert root == 0 && fid == 1
	assert c.lopen(fid, 2) or { u32(0) } == 4072
	mut attr := Attr{}
	c.getattr(fid, unsafe { &attr }) or { assert false }
	assert attr.size == 3
	mut bytes := [8]u8{}
	assert c.read(fid, 0, &bytes[0], 8) or { u32(0) } == 3
	assert bytes[0] == `a` && bytes[2] == `c`
	assert c.write(fid, 4, &bytes[0], 8) or { u32(0) } == 8
	c.setattr(fid, 8, &Attr{ size: 0 }) or { assert false }
	mut entry := DirEntry{}
	assert !(c.readdir_one(root, 0, 4072, unsafe { &entry }) or { true })
	c.mkdir(root, 'dir', 0o755, 0) or { assert false }
	assert server.last_mode == 0o40755
	c.lcreate(fid, 'new', 0o644, 0) or { assert false }
	assert server.last_mode == 0o100644
	c.setattr(fid, 1, &Attr{ mode: 0o100600 }) or { assert false }
	assert server.last_mode == 0o100600
	c.renameat(root, 'a', root, 'b') or { assert false }
	c.unlinkat(root, 'b', false) or { assert false }
	c.fsync(fid) or { assert false }
	c.clunk(fid) or { assert false }
	assert c.allocate_fid() or { u32(-1) } == fid
}

fn test_server_error_timeout_malformed_poison_and_bad_negotiation() {
	mut tx := [max_msize]u8{}
	mut rx := [max_msize]u8{}
	mut server := Server{ mode: 1 }
	mut c := Client{ context: unsafe { &server }, exchange: exchange_fake, tx: unsafe { &tx[0] }, rx: unsafe { &rx[0] } }
	c.attach(0) or { assert c.fault == 13 }
	assert !c.dead && !c.fids[0]
	server.mode = 2
	c.attach(0) or { assert c.fault == 110 }
	assert c.dead
	calls := server.calls
	// The timeout transport may already have freed these mappings. Nil them
	// explicitly, and give call() a formerly valid writer: even finish()
	// must not run when dead.
	c.tx = unsafe { nil }
	c.rx = unsafe { nil }
	mut stale := Writer{ data: unsafe { nil }, capacity: 16, pos: 7, ok: true }
	mut ignored := Reader{}
	assert !c.call(mut stale, unsafe { &ignored })
	mut inert := c.begin(tclunk)
	inert.dword(0)
	assert inert.finish() == 0
	c.negotiate() or {}
	c.release(0)
	c.clunk(0) or {}
	c.attach(0) or {}
	assert server.calls == calls
	server.mode = 3
	c.dead = false
	c.tx = unsafe { &tx[0] }
	c.rx = unsafe { &rx[0] }
	mut data := [4]u8{}
	c.read(0, 0, &data[0], 4) or { assert c.fault == eproto }
	assert c.dead
	server.mode = 4
	c.dead = false
	c.negotiate() or { assert c.fault == eproto }
	assert c.dead
}

fn test_exhaustion_and_range_rejection_do_not_send() {
	mut tx := [max_msize]u8{}
	mut rx := [max_msize]u8{}
	mut server := Server{}
	mut c := Client{ context: unsafe { &server }, exchange: exchange_fake, tx: unsafe { &tx[0] }, rx: unsafe { &rx[0] } }
	for _ in 0 .. max_fids { c.allocate_fid() or { assert false } }
	c.allocate_fid() or { assert c.fault == enospc }
	mut data := [4]u8{}
	c.read(0, u64(-1), &data[0], 4) or { assert c.fault == einval }
	c.write(0, 0, &data[0], 65536) or { assert c.fault == einval }
	assert server.calls == 0
}

fn client_attr_frame(mut w Writer) {
	w.qword(0x7ff)
	w.byte(0)
	w.dword(1)
	w.qword(99)
	w.dword(0o100644)
	w.dword(1000)
	w.dword(1000)
	w.qword(1)
	w.qword(0)
	w.qword(3)
	w.qword(4096)
	w.qword(8)
	for _ in 0 .. 10 { w.qword(0) }
}
