module limine
pub const limine_memmap_usable = u64(0)
pub struct LimineMemmapEntry { pub mut: base u64 length u64 @type u64 }
pub struct LimineMemmapResponse { pub mut: entry_count u64 entries &&LimineMemmapEntry = unsafe { nil } }
pub struct LimineMemmapRequest { pub mut: response &LimineMemmapResponse = unsafe { nil } }
