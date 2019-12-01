module sys

import mm

pub fn kmain() {
	banner()
	parse_bootinfo()
	
	mm.paging_init()
	printk('Paging initialized')

	panic('No init service found.')
}