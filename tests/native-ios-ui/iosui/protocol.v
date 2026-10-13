// SPDX-License-Identifier: GPL-2.0-or-later
module iosui

import cachecli
import encoding.binary
import hosttest
import math
import os
import sourcecommand

pub struct Element {
pub:
	kind     u8
	flags    u8
	align    u8
	frame    []f64
	id       string
	text     string
	children []Element
}

struct Decoder {
	data []u8
mut:
	offset int
	nodes  int
}

fn (mut decoder Decoder) number() !u32 {
	if decoder.offset + 4 > decoder.data.len { return error('short element length') }
	value := binary.little_endian_u32_at(decoder.data, decoder.offset)
	decoder.offset += 4
	return value
}

fn (mut decoder Decoder) element(depth int) !Element {
	if depth > 512 || decoder.nodes >= 100000 {
		return error('desktop tree exceeds decoder limits')
	}
	decoder.nodes++
	start := decoder.offset
	if start + 274 > decoder.data.len { return error('short element') }
	kind, flags, align := decoder.data[start], decoder.data[start + 1], decoder.data[start + 2]
	mut frame := []f64{cap: 4}
	for index in 0 .. 4 {
		frame << math.f64_from_bits(binary.little_endian_u64_at(decoder.data, start + 10 + index * 8))
	}
	decoder.offset += 274
	mut strings := []string{cap: 12}
	for _ in 0 .. 12 {
		length := u64(decoder.number()!)
		if u64(decoder.offset) + length > u64(decoder.data.len) {
			return error('short element string')
		}
		data := unsafe { decoder.data[decoder.offset..decoder.offset + int(length)] }
		hosttest.module_decode_utf8(data.bytestr())!
		strings << data.bytestr()
		decoder.offset += int(length)
	}
	if decoder.number()! != 0 { return error('unexpected desktop element menus') }
	count := u64(decoder.number()!)
	if count > u64(decoder.data.len) / 274 { return error('short element children') }
	mut children := []Element{cap: int(count)}
	for _ in 0 .. int(count) { children << decoder.element(depth + 1)! }
	return Element{kind, flags, align, frame, strings[0], strings[3], children}
}

pub fn decode_tree(data []u8) !Element {
	mut decoder := Decoder{ data: data }
	tree := decoder.element(0)!
	if decoder.offset != data.len { return error('desktop tree has trailing bytes') }
	return tree
}

pub struct Client {
pub mut:
	child sourcecommand.DuplexChild
mut:
	state []u8
}

pub fn client(runner string, binary_path string) !Client {
	mut client := Client{ child: sourcecommand.spawn_duplex([runner, binary_path], os.environ(), 'VINIX_REQUEST_FD', 'VINIX_RESPONSE_FD')!, state: []u8{len: 116} }
	client.reply() or {
		state := sourcecommand.child_exit(client.child.pid) or { sourcecommand.ChildExit{} }
		client.child.close() or {}
		return error(err.msg() + ': child=' + state.return_code.str() + ' exited=' + state.exited.str() + ' / ' + client.child.stdout.bytestr() + ' ' + client.child.stderr.bytestr())
	}
	if binary.little_endian_u32_at(client.state, 48) !in [u32(1), 2] {
		client.child.close() or {}
		return error('unsupported desktop state kind')
	}
	return client
}

fn (mut client Client) reply() ![]u8 {
	header := client.child.read_exact(128, cachecli.cancelled)!
	if header[..8] != [u8(0x50), 0x50, 0x41, 0x56, 10, 0, 0, 0] {
		return error('invalid UIKit desktop response header')
	}
	client.state = header[8..124].clone()
	length := binary.little_endian_u32_at(header, 124)
	if length > 1024 * 1024 { return error('UIKit desktop response exceeds 1 MiB') }
	return client.child.read_exact(int(length), cachecli.cancelled)!
}

pub fn (mut client Client) send(command u8, payload []u8) ![]u8 {
	return client.send_size(command, payload, 390, 680)!
}

pub fn (mut client Client) send_size(command u8, payload []u8, width int, height int) ![]u8 {
	mut data := [u8(0x50), 0x50, 0x41, 0x56, 10, command, 0, 0]
	for value in [width, height] {
		mut bytes := []u8{len: 4}
		binary.little_endian_put_u32(mut bytes, u32(i32(value)))
		data << bytes
	}
	data << client.state
	mut length := []u8{len: 4}
	binary.little_endian_put_u32(mut length, u32(payload.len))
	data << length
	data << payload
	client.child.write_all(data, cachecli.cancelled)!
	return client.reply()!
}

pub fn (mut client Client) build() !Element { return client.build_size(390, 680)! }

pub fn (mut client Client) build_size(width int, height int) !Element {
	return decode_tree(client.send_size(1, [], width, height)!)!
}

pub fn (mut client Client) close() ! {
	if client.child.is_retired() { return }
	client.send(6, []) or {
		client.child.close() or {}
		return err
	}
	status := client.child.wait(cachecli.cancelled)!
	if status != 0 || client.child.stderr.len != 0 {
		return error('UIKit desktop process failed: ' + status.str() + ' / ' + client.child.stderr.bytestr())
	}
}
