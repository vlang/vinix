// The original fault fixture models the non-journaled filesystem branch.
// Keep current production signatures without substituting production bodies.
module ext2

struct Journal {}

fn (_journal Journal) write(_load IO, _buffer voidptr, _location u64, _count u64) ?i64 {
 panic('journal writes are outside this non-journaled host fixture')
}

fn journal_base_load(_context voidptr, _buffer voidptr, _location u64, _count u64) ?i64 {
 panic('journal loads are outside this non-journaled host fixture')
}

fn (mut filesystem EXT2Filesystem) begin_transaction() ? {
 assert filesystem.l.depth == 1
 assert filesystem.journal == unsafe { nil }
 if filesystem.read_only { return none }
}

fn (mut filesystem EXT2Filesystem) commit_transaction() ? {
 assert filesystem.l.depth == 1
 assert filesystem.journal == unsafe { nil }
}

fn (mut filesystem EXT2Filesystem) abort_transaction() {
 assert filesystem.l.depth == 1
 assert filesystem.journal == unsafe { nil }
}
