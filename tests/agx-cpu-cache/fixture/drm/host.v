module drm

import drm.gem

struct GemPrimeResource { mut: obj &gem.GemObject = unsafe { nil } }
pub fn prime_cache_attributes(object &gem.GemObject) u64 {
	mut resource := GemPrimeResource{obj: unsafe { object }}
	return resource.mapping_attributes(unsafe { nil }, 0)
}

pub fn prime_admit(object &gem.GemObject, offset u64, length u64, flags int) bool {
	mut resource := GemPrimeResource{obj: unsafe { object }}
	return resource.admit_mapping_range(unsafe { nil }, offset, length, flags)
}

pub fn prime_mapping_can_grow(object &gem.GemObject) bool {
	mut resource := GemPrimeResource{obj: unsafe { object }}
	return resource.mapping_can_grow()
}
