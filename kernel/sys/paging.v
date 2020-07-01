module sys

pub const (
	page_size = 0x1000
	large_page_size = 0x200000
	huge_page_size = 0x40000000

	pflag_present = (1 << 0)
	pflag_read_write = (1 << 1)
	pflag_user = (1 << 2)
	pflag_write_through = (1 << 3)
	pflag_cache_disabled = (1 << 4)
	pflag_accessed = (1 << 5)
	pflag_dirty = (1 << 6)
	pflag_page_size = (1 << 7)
	pflag_global = (1 << 8)
)

pub fn paging_init() {

}