module boothost

import androidhost as ah

pub fn constants() map[string]ah.Value {
	return {
		'BASE_URL':           ah.Value('https://dl-cdn.alpinelinux.org/alpine/edge/testing/aarch64/')
		'INPUTS':             ah.Value([
			ah.Value({
				'filename': ah.Value('art_standalone-0_git20251009-r2.apk')
				'url':      ah.Value('https://dl-cdn.alpinelinux.org/alpine/edge/testing/aarch64/art_standalone-0_git20251009-r2.apk')
				'sha256':   ah.Value('92f37ff68bff7e3d9f89ac4da0f7e0474aeccd9d77df7360a128ad76093aad99')
			}),
			ah.Value({
				'filename': ah.Value('art_standalone-dev-0_git20251009-r2.apk')
				'url':      ah.Value('https://dl-cdn.alpinelinux.org/alpine/edge/testing/aarch64/art_standalone-dev-0_git20251009-r2.apk')
				'sha256':   ah.Value('0486502b242290d0f8b270205e726230ba1d9d57c04ed54f16bacef8ff829e99')
			}),
			ah.Value({
				'filename': ah.Value('r8-8.3.37.jar')
				'url':      ah.Value('https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar')
				'sha256':   ah.Value('900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199')
			}),
		])
		'JAVA_CLASS_JAR':     ah.Value('usr/lib/java/core-all_classes.jar')
		'BOOT_JARS':          ah.Value([ah.Value('core-oj-hostdex.jar'),
			ah.Value('core-libart-hostdex.jar')])
		'BOOT_DIRECTORY':     ah.Value('usr/lib/java/dex/art')
		'COMPILER_ARGUMENTS': ah.Value([ah.Value('--release'), ah.Value('--min-api'), ah.Value('26'),
			ah.Value('--android-platform-build'), ah.Value('--force-passthrough-assertions')])
		'BOOT_ORIGINAL':      ah.Value({
			'core-oj-hostdex.jar':     ah.Value({
				'original_sha256':            ah.Value('ce272a51212558a609e364e527bf8f548b56a1284899c398a74183c12c4f45a6')
				'classes_before':             ah.Value(3296)
				'bootstrap_callsites_before': ah.Value(339)
			})
			'core-libart-hostdex.jar': ah.Value({
				'original_sha256':            ah.Value('5db335098d4f779c55deb1fe63ff3becf37e39228b242c366a4ad809dd3cd132')
				'classes_before':             ah.Value(1686)
				'bootstrap_callsites_before': ah.Value(3)
			})
		})
	}
}
