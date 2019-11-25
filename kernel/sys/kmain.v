module sys

import mm

const (
	PHYS_BASE = 0xfffffeff00000000
)

enum BootloaderType {
	multiboot
}

struct BootloaderInfo {
	btype BootloaderType
}

pub fn kmain(bootloader_info &BootloaderInfo, magic int) {
	printk('Hello from bare-metal V world!')

	printk('info: $bootloader_info magic: $magic')

	mm.paging_init()
	printk('Paging initialized')

	printk('init exited, stalling...')
	for {
	}
}