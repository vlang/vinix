// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import json2
import encoding.hex

struct DesktopWire {
	sources  []string
	in_place []string
	layers   []string
	tools    []DesktopTool
}

pub fn desktop_encode(input DesktopInputs) string {
	return json2.encode(DesktopWire{
		sources:  input.sources.map(it.bytes().hex())
		in_place: input.in_place.map(it.bytes().hex())
		layers:   input.layers.map(it.bytes().hex())
		tools:    input.tools.map(DesktopTool{it.name, it.path.bytes().hex()})
	})
}

fn decoded(values []string) ![]string {
	mut result := []string{}
	for value in values { result << hex.decode(value)!.bytestr() }
	return result
}

pub fn desktop_decode(text string) !DesktopInputs {
	input := json2.decode[DesktopWire](text)!
	mut tools := []DesktopTool{}
	for item in input.tools { tools << DesktopTool{item.name, hex.decode(item.path)!.bytestr()} }
	return DesktopInputs{decoded(input.sources)!, decoded(input.in_place)!, decoded(input.layers)!, tools}
}
