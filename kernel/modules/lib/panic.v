module lib

fn C.kpanic(message charptr)

pub fn kpanic(message string) {
	C.kpanic(message.str)
}
