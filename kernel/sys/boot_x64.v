module sys

const (
	PHYS_BASE = u64(0xFFFFFEFF00000000)
)

const (
	BOOTLOADER_MAGIC_MB2 = u32(0x36D76289)
	EARLY_BOOTINFO_BASE = u64(0xE00000)
)

struct EarlyBootInfo {
	magic u32
	boot_info u32
}

struct MultibootInfoHeader {
	total_size u32
	reserved u32
}

struct MultibootTag {
	_type u32
	size u32
}

struct MultibootTagCmdline {
	_type u32
	size u32
	_cmdline [0]byte
}

fn (tag &MultibootTagCmdline) command_line() string {
	return tos3(&tag._cmdline)
}

pub fn banner() {
	build_date := v_build_date()
	v_ver := v_version()
	printk('vOS/x86_64 [v${KERNEL_VERSION} ${build_date}, V ${v_ver}]')
}

pub fn parse_bootinfo() {
	early_info := &EarlyBootInfo(voidptr(PHYS_BASE + EARLY_BOOTINFO_BASE))

	if early_info.magic == BOOTLOADER_MAGIC_MB2 {
		printk('Booted using Multiboot2-compliant bootloader.')
		
		mut ptr := voidptr(PHYS_BASE + u64(early_info.boot_info))
		boot_info := &MultibootInfoHeader(ptr)
		printk('addr: $boot_info')
		printk('size: $boot_info.total_size')

		ptr = voidptr(u64(ptr) + u64(8))
		mut tag := &MultibootTag(ptr)
		mut end := false

		for !end {
			printk('[tag] type=$tag._type size=$tag.size')

			match tag._type {
				0 {
					end = true
				}
			}
			ptr = voidptr(u64(ptr) + u64(tag.size + u32(7) & u32(0xfffffff8)))
			tag = &MultibootTag(ptr)
		}

		//cmdline := tos(byteptr(PHYS_BASE + u64(early_info.boot_info) + u64(16)), boot_info._size)
		//printk('kernel command line: $cmdline')
	} else {
		panic('Unknown bootloader version!')
	}
}