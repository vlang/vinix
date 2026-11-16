module drm

import drm.gem

struct GemPrimeResource { mut: obj &gem.GemObject = unsafe { nil } }
pub fn prime_cache_attributes(object &gem.GemObject) u64 {
	mut resource := GemPrimeResource{obj: unsafe { object }}
	return resource.mapping_attributes(unsafe { nil }, 0)
}
