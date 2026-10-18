// SPDX-License-Identifier: GPL-2.0-or-later
module anscore

// Exercise the real Identify submission/PRPs, NVMMU, completion validation,
// namespace parsing and enumeration. The model implements only CNS 0/1.
struct NamespaceModel {
mut:
	dma        &u8 = unsafe { nil }
	head       u32
	phase      u32 = 1
	commands   u32
	clock      u64
	missing    u32
	inactive   u32
	bad_format u32
	fail_id    u32
	status     u16
	wrong_cid  bool
	stall      bool
}

fn namespace_setup() &NamespaceModel {
	mut memory := unsafe { nil }
	assert C.posix_memalign(&memory, 16384, 4587520) == 0
	mut model := unsafe { &NamespaceModel(C.calloc(1, sizeof(NamespaceModel))) }
	unsafe {
		C.memset(memory, 0, 4587520)
		C.memset(&ans_controller, 0, sizeof(Ans))
	}
	model.dma = memory
	model.phase = 1
	ans_controller.dma = model.dma
	ans_controller.physical = 0x800000000
	ans_controller.cookie = model
	ans_controller.nvme = 0x100000
	ans_controller.mailbox = 0x200000
	ans_controller.queues[0].phase = 1
	ans_controller.ops = Ans_ops{
		read32:  namespace_read32
		read64:  namespace_read64
		write32: namespace_write32
		write64: namespace_write64
		now:     namespace_now
		delay:   namespace_delay
		sync:    namespace_sync
	}
	return model
}

fn namespace_free(model &NamespaceModel) {
	unsafe {
		C.free(model.dma)
		C.free(model)
		C.memset(&ans_controller, 0, sizeof(Ans))
	}
}

fn namespace_read32(_ voidptr, address u64) u32 {
	if address == 0x200114 { return 1 << 17 }
	if address == 0x10001c { return 1 }
	assert address == 0x128120
	return 0
}

fn namespace_read64(_ voidptr, _ u64) u64 {
	assert false
	return 0
}

fn namespace_write64(_ voidptr, _ u64, _ u64) {
	assert false
}

fn namespace_delay(_ voidptr, _ u32) {}

fn namespace_now(cookie voidptr) u64 {
	mut m := unsafe { &NamespaceModel(cookie) }
	m.clock += 1000000
	return m.clock
}

fn namespace_sync(cookie voidptr, pointer voidptr, bytes usize, _ i32) {
	m := unsafe { &NamespaceModel(cookie) }
	assert usize(pointer) >= usize(m.dma) && usize(pointer) - usize(m.dma) + bytes <= 4587520
}

fn namespace_write32(cookie voidptr, address u64, value u32) {
	unsafe {
		mut m := &NamespaceModel(cookie)
		if address == 0x101004 {
			assert value == m.head
			return
		}
		if address == 0x128118 {
			assert value == 0
			return
		}
		assert address == 0x12490c && value == 0
		c := m.dma
		id := a_le32(c + 4)
		cns := a_le32(c + 40)
		assert c[0] == 6 && cns <= 1 // CNS=2 must never reach hardware.
		assert a_le64(c + 24) == 0x800020000 && a_le64(c + 32) == 0
		assert m.dma[32769] == 1 && a_le64(m.dma + 32792) == 0x800020000
		m.commands++
		if m.stall { return }
		mut status := u16(0)
		if id == 0 || id == m.missing { status = 0xb }
		if id == m.fail_id { status = m.status }
		if status == 0 && id != m.inactive {
			p := m.dma + 131072
			a_put64(p, 4096)
			a_put64(p + 8, 4096)
			p[130] = if id == m.bad_format { u8(31) } else { u8(12) }
		}
		e := m.dma + 16384 + m.head * 16
		a_zero(e, 16)
		a_put16(e + 12, u16(m.wrong_cid))
		a_put16(e + 14, (status << 1) | u16(m.phase))
		m.head++
		if m.head == 2 {
			m.head = 0
			m.phase ^= 1
		}
	}
}

fn test_ans_enumerates_with_only_supported_identify_selectors() {
	for absent in 1 .. 3 {
		m := namespace_setup()
		defer { namespace_free(m) }
		unsafe {
			if absent == 1 { m.missing = 2 } else { m.inactive = 2 }
		}
		assert a_enumerate_namespaces(unsafe { &ans_controller }, 3) == 0
		assert m.commands == 3 && ans_controller.nns == 2 && ans_controller.dead == 0
		assert ans_controller.ns[0].id == 1 && ans_controller.ns[1].id == 3
		assert ans_controller.ns[1].sector == 4096 && ans_controller.last_status == 0
	}
}

fn test_ans_namespace_work_and_slot_limits() {
	for nn in [u32(0), 1025, 0xffffffff, 9] {
		m := namespace_setup()
		assert a_enumerate_namespaces(unsafe { &ans_controller }, nn) == -ans_namespace
		assert ans_controller.dead != 0
		assert m.commands == if nn == 9 { u32(9) } else { u32(0) }
		namespace_free(m)
	}
	m := namespace_setup()
	assert a_enumerate_namespaces(unsafe { &ans_controller }, 8) == 0
	assert ans_controller.nns == 8 && m.commands == 8
	namespace_free(m)
}

fn test_ans_namespace_faults_are_not_hidden_as_absent_ids() {
	for kind in 0 .. 5 {
		mut m := namespace_setup()
		if kind == 0 { m.bad_format = 1 }
		if kind == 1 {
			m.fail_id = 1
			m.status = 2
		}
		if kind == 2 { m.wrong_cid = true }
		if kind == 3 { m.stall = true }
		if kind == 4 { m.missing = 1 }
		result := a_enumerate_namespaces(unsafe { &ans_controller }, 1)
		assert result < 0 && ans_controller.dead != 0 && ans_controller.nns == 0
		assert m.commands == 1
		namespace_free(m)
	}
}

fn test_ans_rejects_active_namespace_list_before_submission() {
	m := namespace_setup()
	assert a_identify(unsafe { &ans_controller }, 0, 2) == -ans_read_only
	assert m.commands == 0
	namespace_free(m)
}
