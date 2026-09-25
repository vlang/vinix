module userland

import pagecache
import proc

// A filesystem change a thread made goes to the device before the program
// learns it was made: on the way back to userspace from the call that made it,
// or, for what closing a dying process' descriptors changed, before its
// parent hears of the exit. The thread holds no lock at either; see
// flush_on_return in fs/ext2. A failure leaves the pages dirty, for the next
// fsync or sync to report.
pub fn flush_owed_sync() {
	mut thread := proc.current_thread()
	if thread != unsafe { nil } && thread.owes_sync {
		thread.owes_sync = false
		pagecache.sync_all()
	}
}
