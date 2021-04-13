module klock

struct Lock {
	l bool
}

fn C.__sync_bool_compare_and_swap(ptr &bool, old bool, new bool) bool

pub fn acquire(lock_ptr &Lock) {
	for {
		if C.__sync_bool_compare_and_swap(&lock_ptr.l, false, true) == true {
			break
		}
	}
}

pub fn release(lock_ptr &Lock) {
	C.__sync_bool_compare_and_swap(&lock_ptr.l, true, false)
}

pub fn test_and_acquire(lock_ptr &Lock) bool {
	return C.__sync_bool_compare_and_swap(&lock_ptr.l, false, true)
}
