module lib

fn C.kprint(message charptr, len u64)

pub fn kprint(message string) {
	C.kprint(message.str, message.len)
}
