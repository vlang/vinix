// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// Cleanup removes only these obsolete generation directories. Cached objects,
// interrupted stages and personal application data are outside this review.
pub struct CleanupReview {
pub:
	format int = 1
	architecture string
	generation u64
	previous u64
	fingerprint string
	generations []u64
}

pub fn (review &CleanupReview) validate() ! {
	if review.format != 1 || review.architecture !in ['aarch64', 'x86_64']!
		|| !digest(review.fingerprint) || review.generations.len > 4096
		|| (review.generation == 0 && review.previous != 0)
		|| (review.generation != 0 && review.previous >= review.generation) {
		return error('invalid obsolete generation cleanup review')
	}
	mut last := u64(0)
	for generation in review.generations {
		if generation <= last || generation in [review.generation, review.previous]! {
			return error('invalid or retained generation in cleanup review')
		}
		last = generation
	}
}

pub fn (mut review CleanupReview) close() {
	unsafe { review.architecture.free(); review.fingerprint.free(); (&array(&review.generations)).free() }
	review = CleanupReview{}
}

const cleanup_keys = ['format', 'architecture', 'generation', 'previous', 'fingerprint', 'generations']

fn (mut r MetadataReader) cleanup_generations() ![]u64 {
	r.expect(`[` )!
	mut values := []u64{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { values.free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('too many obsolete generations in cleanup review') }
		values << r.unsigned(~u64(0))!
	}
	accepted = true
	return values
}

pub fn decode_cleanup_review(text string) !CleanupReview {
	if text.len > 128 * 1024 { return error('cleanup review exceeds its bound') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut review := CleanupReview{}
	mut accepted := false
	defer { if !accepted { review.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(cleanup_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { r.expect(`1`)! }
			1 { review = CleanupReview{ ...review, architecture: r.quoted(16)! } }
			2 { review = CleanupReview{ ...review, generation: r.unsigned(~u64(0))! } }
			3 { review = CleanupReview{ ...review, previous: r.unsigned(~u64(0))! } }
			4 { review = CleanupReview{ ...review, fingerprint: r.quoted(64)! } }
			5 { review = CleanupReview{ ...review, generations: r.cleanup_generations()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 63 || r.position != text.len { return error('incomplete or trailing cleanup review') }
	review.validate()!
	accepted = true
	return review
}
