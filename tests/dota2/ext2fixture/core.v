// SPDX-License-Identifier: GPL-2.0-or-later
module ext2fixture

import androidhost as ah
import json2

fn field(self string, name string) !string { return attribute(self, name)! }

fn unit(self string, name string, args []ah.Value) !string {
	return method(self, name, args, {})!
}

fn equal(self string, actual string, expected ah.Value) ! {
	unit(self, 'assertEqual', [o(actual), expected])!
}

fn executable(name string) !string {
	mut candidate := call('shutil.which', o(name))!
	if !truth(candidate)! {
		candidate = literal(ah.Value('/opt/homebrew/opt/e2fsprogs/sbin/' + text(name)!))!
	}
	if !truth(method(call('Path', o(candidate))!, 'is_file', [], {})!)! {
		failed('unittest.SkipTest', v(ah.Value(text(name)! + ' is required')))!
	}
	return candidate
}

fn client_initialize(self string, port string) ! {
	endpoint := collection('tuple', [literal(ah.Value('127.0.0.1'))!, port])!
	connection := invoke('socket.create_connection', [o(endpoint)], {
		'timeout': v(ah.Value(10))
	})!
	set_attr(self, 'connection', o(connection))!
	method(connection, 'settimeout', [v(ah.Value(10))], {})!
	magic := call('struct.unpack', v(ah.Value('>QQH')), o(call('EXPORTER.receive', o(connection), v(ah.Value(18)))!))!
	set_attr(self, 'assert_magic', o(magic))!
	expected := collection('tuple', [call('EXPORTER.NBD_MAGIC')!, call('EXPORTER.OPTION_MAGIC')!,
		literal(ah.Value(3))!])!
	callback('assertion', {
		'value': o(call('operator.eq', o(magic), o(expected))!)
	})!
	method(connection, 'sendall', [o(call('struct.pack', v(ah.Value('>I')), v(ah.Value(3)))!)], {})!
	method(connection, 'sendall', [o(call('struct.pack', v(ah.Value('>QII')), o(call('EXPORTER.OPTION_MAGIC')!), v(ah.Value(1)), v(ah.Value(0)))!)], {})!
	response := call('struct.unpack', v(ah.Value('>QH')), o(call('EXPORTER.receive', o(connection), v(ah.Value(10)))!))!
	set_attr(self, 'size', o(item(response, v(ah.Value(0)))!))!
	set_attr(self, 'flags', o(item(response, v(ah.Value(1)))!))!
}

fn client_request(self string, command string, offset string, length string, data string) !string {
	connection := field(self, 'connection')!
	packet := call('struct.pack', v(ah.Value('>IHH8sQI')), o(call('EXPORTER.REQUEST_MAGIC')!), v(ah.Value(0)), o(command), b('testcase'.bytes().hex()), o(offset), o(length))!
	method(connection, 'sendall', [o(call('operator.add', o(packet), o(data))!)], {})!
	reply := call('struct.unpack', v(ah.Value('>II8s')), o(call('EXPORTER.receive', o(connection), v(ah.Value(16)))!))!
	magic := item(reply, v(ah.Value(0)))!
	error_code := item(reply, v(ah.Value(1)))!
	handle := item(reply, v(ah.Value(2)))!
	mut condition := call('operator.eq', o(magic), v(ah.Value(0x67446698)))!
	if truth(condition)! {
		condition = call('operator.eq', o(handle), b('testcase'.bytes().hex()))!
	}
	callback('assertion', {
		'value': o(condition)
	})!
	response := if compare('eq', command, literal(ah.Value(0))!)! && !truth(error_code)! {
		call('EXPORTER.receive', o(connection), o(length))!
	} else {
		callback('literal', {
			'value': b('')
		})!.text()
	}
	return collection('tuple', [error_code, response])!
}

fn setup(self string) ! {
	temporary := invoke('tempfile.TemporaryDirectory', [], {
		'prefix': v(ah.Value('vinix-export-test-'))
	})!
	set_attr(self, 'temporary', o(temporary))!
	base := call('Path', o(attribute(temporary, 'name')!))!
	set_attr(self, 'base', o(base))!
	source := join(base, 'source')!
	set_attr(self, 'source', o(source))!
	method(source, 'mkdir', [], {})!
	method(join(source, 'nested')!, 'mkdir', [], {})!
	method(join(source, 'empty')!, 'touch', [], {})!
	method(join(source, 'short-link')!, 'symlink_to', [v(ah.Value('nested/package.vpk'))], {})!
	method(join(source, 'long-link')!, 'symlink_to', [v(ah.Value('nested/' + 'x'.repeat(90)))], {})!
	method(join(source, 'a "quoted" café')!, 'write_bytes', [b('filename test'.bytes().hex())], {})!
	package := join(source, 'nested/package.vpk')!
	set_attr(self, 'package', o(package))!
	patterns := literal(ah.Value([
		ah.Value([ah.Value(0), ah.Value(0xa5)]),
		ah.Value([ah.Value(12 * 4096 - 127), ah.Value(0xb6)]),
		ah.Value([ah.Value((12 + 1024) * 4096 - 127), ah.Value(0xc7)]),
		ah.Value([ah.Value(128 * 1024 * 1024 - 127), ah.Value(0xd8)]),
	]))!
	// Preserve the original list of tuples for public callers.
	mut pairs := []string{}
	for index in 0 .. 4 { pairs << call('builtins.tuple', o(item(patterns, v(ah.Value(index)))!))! }
	set_attr(self, 'patterns', o(collection('list', pairs)!))!
	manager := method(package, 'open', [v(ah.Value('wb'))], {})!
	output := enter(manager)!
	mut retired := false
	setup_package(self, output) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	overlay := join(base, 'overlay')!
	method(join(overlay, 'nested')!, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
	method(join(overlay, 'nested/loader')!, 'write_bytes', [b('overlay executable'.bytes().hex())], {})!
	method(join(overlay, 'nested/loader')!, 'chmod', [v(ah.Value(0o755))], {})!
	method(join(overlay, 'empty')!, 'write_bytes', [b('replaced'.bytes().hex())], {})!
	state := join(base, 'state')!
	set_attr(self, 'state', o(state))!
	set_attr(self, 'manifest', o(call('EXPORTER.build', o(source), o(state), o(collection('list', [overlay])!))!))!
	set_attr(self, 'export', o(call('EXPORTER.Export', o(state))!))!
}

fn setup_package(self string, output string) ! {
	method(output, 'truncate', [v(ah.Value(130 * 1024 * 1024 + 13))], {})!
	iter := iterator(field(self, 'patterns')!)!
	for {
		row := next(iter)!
		if row.done { break }
		fields := unpack2(row.value)!
		method(output, 'seek', [o(fields[0])], {})!
		data := call('builtins.bytes', o(collection('list', [fields[1]])!))!
		method(output, 'write', [o(call('operator.mul', o(data), v(ah.Value(8192)))!)], {})!
	}
	method(output, 'seek', [v(ah.Value(-13)), o(call('os.SEEK_END')!)], {})!
	method(output, 'write', [b('partial block'.bytes().hex())], {})!
}

fn bmap(self string, path string, block string) !string {
	text_command := 'bmap /' + text(path)! + ' ' + text(block)!
	args := collection('list', [call('executable', v(ah.Value('debugfs')))!, literal(ah.Value('-R'))!,
		literal(ah.Value(text_command))!,
		call('builtins.str', o(join(field(self, 'state')!, 'metadata.ext2')!))!])!
	output := invoke('subprocess.check_output', [o(args)], {
		'text':   v(ah.Value(true))
		'stderr': o(call('subprocess.DEVNULL')!)
	})!
	return call('builtins.int', o(method(output, 'strip', [], {})!))!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'executable' { return ah.Value(executable(args[0])!) }
		'client_initialize' { client_initialize(args[0], args[1])! }
		'client_request' {
			return ah.Value(client_request(args[0], args[1], args[2], args[3], args[4])!)
		}
		'client_close' { method(field(args[0], 'connection')!, 'close', [], {})! }
		'setUp' { setup(args[0])! }
		'tearDown' {
			method(field(args[0], 'export')!, 'close', [], {})!
			method(field(args[0], 'temporary')!, 'cleanup', [], {})!
		}
		'bmap' { return ah.Value(bmap(args[0], args[1], args[2])!) }
		'valid_layout' { valid_layout(args[0])! }
		'partial_overlay' { partial_overlay(args[0])! }
		'readonly_change' { readonly_change(args[0])! }
		'remounted_volume' { remounted_volume(args[0])! }
		'idle_timeout' { idle_timeout(args[0], args[1], args[2])! }
		'refuse_oversized' { refuse_oversized(args[0])! }
		else { return error('unknown independent ext2 fixture operation') }
	}
	return ah.Value(json2.Null{})
}
