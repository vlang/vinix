module klock

pub struct Lock {
	l bool
}

fn C.__sync_bool_compare_and_swap(ptr &bool, old bool, new bool) bool

pub fn (l &Lock) acquire() {
	for {
		if C.__sync_bool_compare_and_swap(&l.l, false, true) == true {
			break
		}
	}
}

pub fn (l &Lock) release() {
	C.__sync_bool_compare_and_swap(&l.l, true, false)
}

pub fn (l &Lock) test_and_acquire() bool {
	return C.__sync_bool_compare_and_swap(&l.l, false, true)
}

pub fn new() Lock {
	return Lock{false}
}
