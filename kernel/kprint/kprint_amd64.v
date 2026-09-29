module kprint

import dev.serial
import term

pub fn kwrite(message charptr, msglen u64) {
	kprint_lock.acquire()

	$if !prod {
		unsafe {
			for i := 0; i < msglen; i++ {
				serial.out(message[i])
			}
		}
	}

	term.print(message, msglen)

	kprint_lock.release()
}
