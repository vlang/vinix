// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

const max_views = 32
const max_pending = 128

struct View {
	generation u64
mut:
	navigation u64
}

struct Pending {
	op         Op
	view       u64
	generation u64
	navigation u64
}

// One State belongs to one authenticated engine channel. It is confined to
// the Android main Looper; the IO thread only submits validated bounded frames.
pub struct State {
mut:
	views        map[u64]View
	pending      map[u64]Pending
	last_request u64
	last_view    u64
	closed       bool
}

// Reserve before sending. Request and view IDs are monotonic for the entire
// channel so a delayed callback cannot become valid after destroy/recreate.
pub fn (mut s State) submit(h Header, payload []u8) ! {
	h.validate(.client_to_engine)!
	validate_payload(h, payload)!
	if s.closed { return error('browser channel is closed') }
	if h.request <= s.last_request { return error('browser request replay') }
	if s.pending.len >= max_pending { return error('browser pending request limit') }
	if h.op == .create {
		if s.views.len >= max_views || h.view <= s.last_view || h.navigation != 0 {
			return error('browser view identity/limit')
		}
		s.views[h.view] = View{ generation: h.generation }
		s.last_view = h.view
	} else if h.view != 0 {
		mut view := s.views[h.view] or { return error('unknown browser view') }
		if view.generation != h.generation { return error('stale browser generation') }
		if h.op == .navigate {
			if h.navigation <= view.navigation { return error('browser navigation replay') }
			view.navigation = h.navigation
			s.views[h.view] = view
		} else if h.navigation != view.navigation {
			return error('stale browser navigation')
		}
		if h.op == .destroy {
			s.views.delete(h.view)
			mut removed := []u64{}
			for id, request in s.pending {
				if request.view == h.view { removed << id }
			}
			for id in removed { s.pending.delete(id) }
			unsafe { removed.free() }
		}
	}
	s.pending[h.request] = Pending{
		op:         h.op
		view:       h.view
		generation: h.generation
		navigation: h.navigation
	}
	s.last_request = h.request
}

// Returning false discards an event from a destroyed view, old generation, or
// old navigation. Malformed frames, mismatched replies and replayed completions
// are protocol errors and close the transport at its caller.
pub fn (mut s State) receive(h Header, payload []u8) !bool {
	h.validate(.engine_to_client)!
	validate_payload(h, payload)!
	if s.closed { return false }
	if h.op in [.ack, .cookie_result] || (h.op == .failure && h.request != 0) {
		p := s.pending[h.request] or {
			// Destroy cancels outstanding work. Replies already queued by the
			// engine may still arrive, but a never-created view is a violation.
			if h.view != 0 && h.view <= s.last_view && h.view !in s.views { return false }
			return error('unknown/replayed browser completion')
		}
		if p.view != h.view || p.generation != h.generation || p.navigation != h.navigation {
			return error('browser completion identity mismatch')
		}
		if (h.op == .cookie_result) != (p.op == .cookie_get) && h.op != .failure {
			return error('browser completion operation mismatch')
		}
		s.pending.delete(h.request)
		if p.op == .create && h.op == .failure {
			s.views.delete(h.view)
			return true
		}
		if p.op == .destroy { return true }
		if h.view == 0 { return true }
	}
	view := s.views[h.view] or { return false }
	return view.generation == h.generation && view.navigation == h.navigation
}

// Called on EOF, timeout, helper death or any protocol violation. No outstanding
// request may survive a helper restart; a fresh State uses a fresh channel.
pub fn (mut s State) close() {
	s.closed = true
	s.views.clear()
	s.pending.clear()
}

// Final disposal is separate from close because callers may inspect a closed
// state until their owning channel is released.
pub fn (mut s State) dispose() {
	s.close()
	unsafe {
		s.views.free()
		s.pending.free()
	}
}
