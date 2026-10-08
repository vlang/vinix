// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import fixturehost
import hosttest
import json2
import os
import qemubuild

fn field(row map[string]json2.Any, name string) json2.Any { return row[name] or { json2.Null{} } }

fn path(row map[string]json2.Any, name string) string {
	return hex.decode(field(row, name).str()) or { []u8{} }.bytestr()
}

fn failure(err IError) map[string]json2.Any {
	if err is qemubuild.BuildError {
		return {
			'kind':    json2.Any(err.kind)
			'message': json2.Any(err.message)
		}
	}
	if err is qemubuild.FileError {
		return {
			'kind':     json2.Any('OSError')
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is qemubuild.RenameError {
		return {
			'kind':      json2.Any('OSError')
			'errno':     json2.Any(err.number)
			'filename':  json2.Any(err.source.bytes().hex())
			'filename2': json2.Any(err.destination.bytes().hex())
		}
	}
	if err is qemubuild.CopyError {
		return {
			'kind':    json2.Any('CopyError')
			'entries': json2.Any(err.entries.map(json2.Any([
				json2.Any(it.source.bytes().hex()),
				json2.Any(it.destination.bytes().hex()),
				json2.Any(it.message),
			])))
		}
	}
	if err is hosttest.ModuleFileError {
		return {
			'kind':     json2.Any('OSError')
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is fixturehost.FileError {
		return {
			'kind':     json2.Any('OSError')
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is hosttest.ModuleDecodeError {
		return {
			'kind':   json2.Any('UnicodeDecodeError')
			'data':   json2.Any(err.data.hex())
			'start':  json2.Any(err.start)
			'end':    json2.Any(err.end)
			'reason': json2.Any(err.reason)
		}
	}
	if err is qemubuild.ChildFailure {
		return {
			'kind':   json2.Any('CalledProcessError')
			'status': json2.Any(err.status)
			'argv':   json2.Any(err.argv.map(json2.Any(it.bytes().hex())))
		}
	}
	if err is fixturehost.CommandError {
		return {
			'kind':   json2.Any('CalledProcessError')
			'status': json2.Any(err.status)
			'argv':   json2.Any(err.argv.map(json2.Any(it.bytes().hex())))
			'output': json2.Any(err.output.bytes().hex())
		}
	}
	return {
		'kind':    json2.Any('ValueError')
		'message': json2.Any(err.msg())
	}
}

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: qemu_builder METADATA RECEIPT')
		exit(2)
	}
	row := hosttest.decode_json(qemubuild.read_text(os.args[1]) or {
		eprintln(err)
		exit(1)
	}) or {
		eprintln(err)
		exit(1)
	}
	metadata := row.as_map()
	mut environment := map[string]string{}
	mut inherited := map[string]string{}
	for entry in path(metadata, 'inherited_environment').split('\x00') {
		if entry == '' { continue }
		separator := entry.index('=') or { continue }
		inherited[entry[..separator]] = entry[separator + 1..]
	}
	for pair in field(metadata, 'environment').as_array() {
		values := pair.as_array()
		environment[hex.decode(values[0].str()) or { []u8{} }.bytestr()] = hex.decode(values[1].str()) or { []u8{} }.bytestr()
	}
	options := qemubuild.Options{
		repo:                  path(metadata, 'repo')
		support:               path(metadata, 'support')
		builder:               path(metadata, 'builder')
		work:                  path(metadata, 'work')
		staging:               path(metadata, 'staging')
		base:                  path(metadata, 'base')
		jobs:                  field(metadata, 'jobs').str()
		refresh:               field(metadata, 'refresh').bool()
		platform:              field(metadata, 'platform').str()
		host_arch:             field(metadata, 'host_arch').str()
		python:                path(metadata, 'python')
		python_version:        field(metadata, 'python_version').str()
		environment:           environment
		inherited_environment: inherited
	}
	qemubuild.build(options) or {
		qemubuild.write(os.args[2], json2.encode(failure(err), escape_unicode: true)) or {
			eprintln(err)
			exit(1)
		}
		exit(1)
	}
}
