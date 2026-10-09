// SPDX-License-Identifier: MIT
module robloxhost

import androidhost as ah

fn main_policy(args string) ! {
	repo := attribute(args, 'repo')!
	kernel_arg := attribute(args, 'kernel_dir')!
	kernel := if truth(kernel_arg)! { kernel_arg } else { join(repo, 'kernel')! }
	callback('set_attribute', {
		'owner': ah.Value(args)
		'name':  ah.Value('kernel_dir')
		'value': o(kernel)
	})!
	translation_arg := attribute(args, 'translation')!
	translation := if truth(translation_arg)! {
		translation_arg
	} else {
		join(repo, 'build-aarch64-x86-translation/staging')!
	}
	callback('set_attribute', {
		'owner': ah.Value(args)
		'name':  ah.Value('translation')
		'value': o(translation)
	})!
	work := method(attribute(args, 'work')!, 'resolve', [], {})!
	mkdir(work, true)!
	fetched := public_host('fetch', [work, attribute(args, 'version')!])!
	pair := callback('unpack_pair', {
		'owner': ah.Value(fetched)
	})!.items().map(it.text())
	deployment, downloads := pair[0], pair[1]
	client := call('operator.truediv', o(join(work, 'client')!), o(deployment))!
	public_host('stage', [downloads, client])!
	root := public_host('prepare', [args, work, client, deployment])!
	uploads := join(work, 'uploads')!
	if exists(uploads)! { call('shutil.rmtree', o(uploads))! }
	server := public_host('serve_uploads', [uploads, attribute(args, 'port')!])!
	own(server, 'shutdown', {}, '')!
	transcript := public_host('run_guest', [args, work, root]) or {
		cause := err
		close(server, cause)!
		return cause
	}
	close(server, none)!
	if truth(attribute(args, 'shell')!)! { return }
	verdict(args, work, uploads, deployment, transcript)!
}

fn verdict(args string, work string, uploads string, deployment string, transcript string) ! {
	mut drawn := literal(ah.Value(false))!
	frames := iterator(call('sorted', o(method(uploads, 'glob', [v(ah.Value('*.xwd'))], {})!))!)!
	for {
		frame := next(frames)!
		if frame.done { break }
		candidate := public_host('xwd_to_png', [frame.value,
			method(frame.value, 'with_suffix', [v(ah.Value('.png'))], {})!])!
		drawn = if truth(candidate)! { candidate } else { drawn }
	}
	if truth(call('operator.contains', o(transcript), o(byte('KERNEL PANIC')!))!)! {
		failed('SystemExit', 'The kernel panicked; inspect ' + text(work)! + '/vinix.log', none)!
	}
	if truth(call('operator.contains', o(transcript), o(byte('ROBLOX-WINDOWS-FAIL')!))!)! {
		failed('SystemExit', 'Wine did not run in the guest, so the client was never started; inspect ' + text(work)! + '/vinix.log', none)!
	}
	if !truth(call('operator.contains', o(transcript), o(byte('ROBLOX-WINDOWS-DONE')!))!)! {
		failed('SystemExit', 'The guest never finished its observation; inspect ' + text(work)! + '/vinix.log', none)!
	}
	report := join(uploads, 'wine.log')!
	lines := if exists(report)! {
		method(method(report, 'read_text', [], {
			'errors': v(ah.Value('replace'))
		})!, 'splitlines', [], {})!
	} else {
		list([])!
	}
	if truth(attribute(args, 'strace')!)! {
		numbers := list([])!
		iter := iterator(lines)!
		for {
			line := next(iter)!
			if line.done { break }
			method(numbers, 'append', [o(take(method(line.value, 'rsplit', [
				v(ah.Value(' ')),
				v(ah.Value(1)),
			], {})!, 1)!)], {})!
		}
		extra := if truth(numbers)! {
			', first ' + text(method(lit(', ')!, 'join', [o(slice(numbers, null()!, value_int(4)!)!)], {})!)!
		} else {
			''
		}
		call('print', v(ah.Value('The client made ' + text(length(numbers)!)! + ' system calls of its own that Linux does not have' + extra)))!
	} else {
		iter := iterator(slice(lines, value_int(-12)!, null()!)!)!
		for {
			line := next(iter)!
			if line.done { break }
			call('print', o(call('operator.add', v(ah.Value('  ')), o(line.value))!))!
		}
	}
	last := take(method(transcript, 'rsplit', [o(byte('ROBLOX-WINDOWS-TICK')!), v(ah.Value(1))], {})!, -1)!
	alive := truth(call('operator.contains', o(last), o(byte('ROBLOX-WINDOWS-ALIVE')!))!)!
	call('print', v(ah.Value('Deployment ' + text(deployment)! + ': client ' + if alive {
		'still running'
	} else {
		'gone'
	} + ' at the end of the observation, ' + if truth(drawn)! { 'a drawn' } else { 'an empty' } + ' display. Transcript: ' + text(work)! + '/vinix.log, uploads: ' + text(uploads)!)))!
	if !alive || !truth(drawn)! {
		callback('raise', {
			'kind': ah.Value('SystemExit')
			'args': ah.Value([v(ah.Value(1))])
		})!
	}
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'download' { download(args[0], args[1])! }
		'md5' { return ah.Value(md5(args[0])!) }
		'fetch' { return ah.Value(fetch(args[0], args[1])!) }
		'stage' { stage(args[0], args[1])! }
		'copy_layer' { copy_layer(args[0], args[1], args[2], args[3])! }
		'prepare' { return ah.Value(prepare(args[0], args[1], args[2], args[3])!) }
		'xwd_to_png' { return ah.Value(image(args[0], args[1])!) }
		'serve_uploads' { return ah.Value(serve(args[0], args[1])!) }
		'upload' { upload(args[0], args[1])! }
		'main' { main_policy(args[0])! }
		else { return error('unknown Roblox Windows host policy') }
	}
	return ah.Value(null()!)
}
