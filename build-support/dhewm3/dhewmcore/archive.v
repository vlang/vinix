module dhewmcore

import androidhost as ah
import runtimebuild as rb

fn index_body(tar ah.Value, index ah.Value) ! {
	stream := method(tar, 'extractfile', [v('APKINDEX')])!
	rb.method('invoke', index, 'write_bytes', [o(method(stream, 'read', [])!)], {})!
}

fn unpack_index(archive ah.Value, index ah.Value) ! {
	tar := rb.call('enter', 'tarfile', 'open', [o(archive), v('r:gz')], {})!
	mut failed := false
	mut cause := IError(none)
	index_body(tar, index) or {
		failed = true
		cause = err
	}
	suppressed := exit(tar, failed, cause)!
	if failed && !suppressed { return cause }
}

fn demo_body(tar ah.Value, demo ah.Value) ! {
	iter := rb.iter_object(tar)!
	for {
		member := rb.next(iter)!
		if member == rb.null() { break }
		if rb.eq_value(rb.attribute(member, 'name', true)!, ah.Value('demo/demo00.pk4'))! {
			stream := method(tar, 'extractfile', [o(member)])!
			rb.method('invoke', demo, 'write_bytes', [o(method(stream, 'read', [])!)], {})!
			break
		}
	}
}

fn stream_demo(stream ah.Value, demo ah.Value) ! {
	for _ in 0 .. 373 { rb.method('invoke', stream, 'readline', [], {})! }
	tar := rb.callback('enter', {
		'module':          ah.Value('tarfile')
		'name':            ah.Value('open')
		'options':         ah.Value(map[string]ah.Value{})
		'keyword_objects': ah.Value({
			'fileobj': stream
			'mode':    literal('r|gz')!
		})
	})!
	mut failed := false
	mut cause := IError(none)
	demo_body(tar, demo) or {
		failed = true
		cause = err
	}
	suppressed := exit(tar, failed, cause)!
	if failed && !suppressed { return cause }
}

fn install_demo(installer ah.Value, demo ah.Value) ! {
	stream := rb.method('enter', installer, 'open', [v('rb')], {})!
	mut failed := false
	mut cause := IError(none)
	stream_demo(stream, demo) or {
		failed = true
		cause = err
	}
	suppressed := exit(stream, failed, cause)!
	if failed && !suppressed { return cause }
}
