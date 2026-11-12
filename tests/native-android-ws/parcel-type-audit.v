// SPDX-License-Identifier: GPL-2.0-or-later
// Locate parcel-shaped types whose superclass chain lacks Parcelable.
module main
import os
import json2

struct Shape {
	parent string
	parcelable bool
	describe bool
	write bool
	creator bool
}

fn main() {
	if os.args.len != 2 { panic('usage: parcel-type-audit SMALI_ROOT') }
	if !os.is_dir(os.args[1]) { panic('smali directory required') }
	mut types := map[string]Shape{}
	for path in os.walk_ext(os.args[1], '.smali') {
		text := os.read_file(path)!
		mut name := ''
		mut parent := ''
		for line in text.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed.starts_with('.class ') { name = trimmed.fields().last() }
			if trimmed.starts_with('.super ') { parent = trimmed.fields().last() }
		}
		if name == '' || name == 'Landroid/os/Parcelable;' { continue }
		types[name] = Shape{parent: parent, parcelable: text.contains('.implements Landroid/os/Parcelable;'),
			describe: text.contains(' describeContents()I'), write: text.contains(' writeToParcel(Landroid/os/Parcel;I)V'),
			creator: text.contains(' CREATOR:Landroid/os/Parcelable$Creator;')}
	}
	if types.len == 0 { panic('no class declarations found') }
	mut missing := map[string]Shape{}
	for name, shape in types {
		if !shape.describe || shape.parcelable { continue }
		mut current := shape.parent
		mut inherited := false
		for _ in 0 .. 100 {
			parent := types[current] or { break }
			if parent.parcelable { inherited = true; break }
			current = parent.parent
		}
		if !inherited { missing[name] = shape }
	}
	println(json2.encode(missing, prettify: true))
}
