module inet

import lib

// Include attached interfaces before DHCP assigns an address. ifconfig uses
// this list because SIOCGIFCONF deliberately lists IPv4 addresses only.
fn proc_net_dev_text() string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(768) }
	text.add('Inter-|   Receive                                                |  Transmit\n face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n')
	mut fields := [16]u64{}
	net_lock.acquire()
	for index in 1 .. 3 {
		if C.vinix_net_counters(i32(index), unsafe { &fields[0] }) == 0 { continue }
		text.add(if index == 1 { '    lo:' } else { '  eth0:' })
		for field in fields {
			text.add_byte(` `)
			text.add_unsigned(field)
		}
		text.add_byte(`\n`)
	}
	net_lock.release()
	return lib.finish_text(*text)
}
