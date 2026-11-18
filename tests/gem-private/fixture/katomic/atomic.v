module katomic

pub fn inc[T](mut value T) T { old := value; value++; return old }
pub fn load[T](value &T) T { return unsafe { *value } }
pub fn dec[T](mut value T) bool {
	// Compare scalar snapshots: this host compiler treats a direct comparison
	// of a generic mutable parameter with zero as a pointer comparison.
	before := value
	assert before > 0
	value--
	after := value
	return after != 0
}
