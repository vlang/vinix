// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub struct MirrorReview {
pub:
	format int
	input_destination string
	destination string // canonical destination on the reviewed filesystem
	review Review
	cache_needed u64
	cache_available u64
	shared_disk bool // destination disk_needed already includes cache_needed
}


pub fn (mirror &MirrorReview) validate() ! {
	mirror.review.validate()!
	if mirror.format != 1 || mirror.review.operation != 'mirror'
		|| !printable(mirror.input_destination, 4096) || mirror.input_destination == ''
		|| !printable(mirror.destination, 4096) || !mirror.destination.starts_with('/')
		|| !mirror_destination_valid(mirror.destination)
		|| (mirror.shared_disk && mirror.cache_needed > mirror.review.disk_needed)
		|| mirror.review.generation != 0 || mirror.review.requested.len == 0
		|| mirror.review.names.len != mirror.review.requested.len
		|| mirror.review.names.any(it !in mirror.review.requested)
		|| mirror.review.requested.any(it !in mirror.review.names) {
		return error('invalid offline mirror review')
	}
	mut previous := ''
	for id in mirror.review.requested {
		if id <= previous { return error('invalid offline mirror roots') }
		previous = id
	}
}

fn mirror_destination_valid(path string) bool {
	if path.len < 2 || path[0] != `/` || path.contains('\\') { return false }
	mut start := 1
	for i := 1; i <= path.len; i++ {
		if i < path.len && path[i] != `/` { continue }
		length := i - start
		if length == 0 || (length == 1 && path[start] == `.`)
			|| (length == 2 && path[start] == `.` && path[start + 1] == `.`) { return false }
		start = i + 1
	}
	return true
}


pub fn (mut mirror MirrorReview) close() {
	unsafe { mirror.input_destination.free(); mirror.destination.free() }
	mirror.review.close()
	mirror = MirrorReview{}
}
