module sys

import mm

const (
	PHYS_BASE = 0xfffffeff00000000
)

pub fn kmain() {
	printk('Hello from bare-metal V world!')

	mm.paging_init()
	printk('Paging initialized')

	printk('init exited, stalling...')
	for {
	}
}