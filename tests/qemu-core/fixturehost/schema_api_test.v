// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import hosttest

fn test_public_receipt_preserves_original_json_formatting() {
	work := hosttest.work_dir("", "vinix-receipt-test-") or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	path := work + "/receipt.json"
	write_receipt(path, hosttest.decode_json("{}") or { panic(err) }) or { panic(err) }
	assert (read(path) or { panic(err) }) == "{}\n"
	write_receipt(path, hosttest.decode_json("{\"scope\": \"unchanged production G17 policy and original independent encoder oracle\", \"arch\": \"aarch64\", \"inputs\": {\"lib/core.v\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}, \"init_sha256\": \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}") or { panic(err) }) or { panic(err) }
	assert (read(path) or { panic(err) }) == "{\n  \"scope\": \"unchanged production G17 policy and original independent encoder oracle\",\n  \"arch\": \"aarch64\",\n  \"inputs\": {\n    \"lib/core.v\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n  },\n  \"init_sha256\": \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"\n}\n"
	write_receipt(path, hosttest.decode_json("{\"nested\": [true, null, 0, -1, 18446744073709551615, {\"x\": []}], \"unicode\": \"\\u00e9\\u96ea\\ud83d\\ude00\\u007f\", \"quoted\": \"\\\"\\\\\\n\\t\"}") or { panic(err) }) or { panic(err) }
	assert (read(path) or { panic(err) }) == "{\n  \"nested\": [\n    true,\n    null,\n    0,\n    -1,\n    18446744073709551615,\n    {\n      \"x\": []\n    }\n  ],\n  \"unicode\": \"\\u00e9\\u96ea\\ud83d\\ude00\\u007f\",\n  \"quoted\": \"\\\"\\\\\\n\\t\"\n}\n"
	write_receipt(path, hosttest.decode_json("{\"path\\\\literal/\\u00e9.v\": \"abc\", \"empty\": {}, \"array\": []}") or { panic(err) }) or { panic(err) }
	assert (read(path) or { panic(err) }) == "{\n  \"path\\\\literal/\\u00e9.v\": \"abc\",\n  \"empty\": {},\n  \"array\": []\n}\n"
	write_receipt(work, hosttest.decode_json("{}") or { panic(err) }) or {
		assert err is FileError && err.filename == work && err.number == 21
		return
	}
	assert false
}
