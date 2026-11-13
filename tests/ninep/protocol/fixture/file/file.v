module file

// The real Handle owns one Resource reference across dup/fork and passes its
// original status flags to unref on final close or construction rollback.
pub struct Handle {
pub mut:
	flags int
}
