// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_http_proxy_configuration_snapshots_and_ownership() {
	path := os.getenv('VINIX_IOS_PROXY_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
	}
}

fn test_http_proxy_uri_validation() {
	for text in ['http://proxy.vinix.test', 'http://proxy.vinix.test/', 'http://127.0.0.1:65535',
		'http://LOCALHOST:1', 'http://proxy.vinix.test.:3128/'] {
		proxy := cfnetwork_parse_proxy(text)?
		assert proxy.host.len > 0 && proxy.port > 0 && proxy.port <= 65535
	}
	for text in ['', 'http://', 'http://:80', 'https://proxy', 'socks://proxy:80',
		'http://proxy:0', 'http://proxy:65536', 'http://proxy:9999999999999999999999999',
		'http://proxy:', 'http://proxy:123x', 'http://user:pass@proxy:80', 'http://proxy/path',
		'http://proxy?query', 'http://proxy#fragment', 'http://[::1]:80', 'http://a..b:80',
		'http://-host', 'http://host-', 'http://space host', 'http://line\nhost',
		'http://utf8é', 'http://proxy:80:90'] {
		assert cfnetwork_parse_proxy(text) == none
	}
	long_label := 'http://' + 'x'.repeat(64)
	assert cfnetwork_parse_proxy(long_label) == none
	long_uri := 'http://' + 'x'.repeat(513)
	assert cfnetwork_parse_proxy(long_uri) == none
	unsafe { long_label.free(); long_uri.free() }
}
