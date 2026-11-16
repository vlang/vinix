module g13contract

import g13layout

fn test_reservation_guard_rejects_lost_lock_visible_slot_or_stale_borrowed_link() {
	repo := g13layout.repo_root()
	nodes := read(repo + '/kernel/file/reservation.v')!
	files := read(repo + '/kernel/file/file.v')!
	process := read(repo + '/kernel/proc/proc.v')!
	check_fd_reservation_contract(nodes, files, process)!
	for token in ['process.fds_lock.acquire()', 'process.fds_lock.release()', 'node.number = -1;',
		'previous.next = node.next', 'process.fds_reserved = voidptr(reservation)',
		'!remove_fd_reservation_locked(process, reservation)', 'fd.unref(); return none'] {
		if _ := check_fd_reservation_contract(nodes.replace(token, ''), files, process) { assert false, token }
	}
	for token in ['&& !fd_number_reserved_locked(process, i)', 'if fd_number_reserved_locked(process, oldfd) {',
		'if fd_number_reserved_locked(process, number) { continue }'] {
		if _ := check_fd_reservation_contract(nodes, files.replace(token, ''), process) { assert false, token }
	}
	if _ := check_fd_reservation_contract(nodes.replace('node.number = number', 'process.fds[number] = voidptr(node); node.number = number'), files, process) { assert false }
}
