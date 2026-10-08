// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import json2
import math.big

pub fn validate_mesa(inputs Value, path string) ! {
	missing := Value(json2.Null{})
	empty := Value(map[string]Value{})
	files := [get(inputs, 'source', empty)!, get(inputs, 'debian_diff', empty)!]
	mut valid := equal(get(inputs, 'format', missing)!, Value(Number{'2', true, ''}))
	if valid { valid = get(inputs, 'debian_version', missing)! is string }
	if valid { valid = starts(get(inputs, 'mirror', Value(''))!, 'https://')! }
	if valid {
		for file in files {
			filename := get(file, 'filename', missing)!
			if filename !is string || !safe_relative(filename) || length(get(file, 'sha256', Value(''))!)! != 64 {
				valid = false
				break
			}
		}
	}
	if valid {
		patches := get(inputs, 'patches', missing)!
		valid = patches is map[string]Value && truth(patches)
		if valid && patches is map[string]Value {
			for name, value in patches {
				if name.contains('/') || length(value)! != 64 {
					valid = false
					break
				}
			}
		}
	}
	if valid { valid = get(inputs, 'packages', missing)! is []Value }
	if !valid { return PolicyError{'SystemExit', 'invalid pinned Mesa inputs: ' + path} }
}

pub fn validate_glibc(pin Value, path string) ! {
	missing := Value(json2.Null{})
	mut valid := equal(get(pin, 'package', missing)!, Value('libc6'))
	if valid { valid = equal(get(pin, 'architecture', missing)!, Value('amd64')) }
	if valid {
		version := get(pin, 'version', missing)!
		valid = version is string && truth(version)
	}
	if valid {
		size := get(pin, 'size', missing)!
		valid = size is bool || (size is Number && size.integer)
		if valid { valid = numeric_int(size)! > big.integer_from_int(0) }
	}
	if valid {
		hash := get(pin, 'sha256', missing)!
		valid = hash is string && scalar_length(hash) == 64
		if valid && hash is string {
			for ch in hash.bytes() { if ch !in '0123456789abcdef'.bytes() { valid = false; break } }
		}
	}
	if valid {
		mirror := get(pin, 'mirror', missing)!
		valid = mirror is string && mirror.starts_with('https://')
	}
	if valid {
		filename := get(pin, 'filename', missing)!
		valid = filename is string && truth(filename) && safe_relative(filename)
	}
	if !valid { return PolicyError{'SystemExit', 'invalid pinned amd64 libc6 package: ' + path} }
}
