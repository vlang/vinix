@[has_globals]
module cpu

pub struct Event {
pub:
	kind string
	address u64
	pte u64
}

__global events [65536]Event
__global event_count int
__global ctr = u64(5) << 16
__global root = u64(0x4000)
__global probe fn (u64) u64 = unsafe { nil }
__global watched u64
pub fn watch(address u64) { watched = address }
pub fn reset() { event_count = 0 }
pub fn set_ctr(value u64) { ctr = value }
pub fn set_root(value u64) { root = value }
pub fn set_probe(callback fn (u64) u64) { probe = callback }
pub fn count() int { return event_count }
pub fn at(index int) Event { assert index >= 0 && index < event_count; return events[index] }
pub fn read_ctr_el0() u64 { return ctr }
pub fn read_ttbr1_el1() u64 { return root }
pub fn record(kind string, address u64) {
	assert event_count < events.len
	observed := if kind in ['dsb_sy', 'dsb_ishst', 'dsb_ish', 'isb'] { watched } else { address }
	pte := if probe != unsafe { nil } { probe(observed) } else { u64(0) }
	events[event_count] = Event{kind, observed, pte}
	event_count++
}
pub fn clean_invalidate_data_cache_line(address u64) { record('civac', address) }
pub fn dsb_sy() { record('dsb_sy', 0) }
pub fn dsb_ishst() { record('dsb_ishst', 0) }
pub fn dsb_ish() { record('dsb_ish', 0) }
pub fn isb() { record('isb', 0) }
pub fn tlbi_vaae1(address u64) { record('tlbi', address << 12) }
