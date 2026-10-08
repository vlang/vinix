module runnercore

import androidhost as ah
import runtimebuild as rb

fn optional(args ah.Value, name string, fallback string) !ah.Value {
	value := attr(args, name)!
	return method(if rb.bool_object(value)! { value } else { join(attr(args, 'repo')!, fallback)! }, 'resolve', [])!
}

fn setattr(args ah.Value, name string, value ah.Value) ! {
	rb.callback('setattr', {
		'id':    args
		'name':  ah.Value(name)
		'value': o(value)
	})!
}

fn parser_error(parser ah.Value, message string) ! {
	rb.method('invoke', parser, 'error', [v(message)], {})!
}

fn main_workflow(args ah.Value, parser ah.Value) ! {
	if rb.bool_object(rb.call('acquire', 'operator', 'lt', [o(attr(args, 'rounds')!),
		rb.ordinary(ah.Value(1))], {})!)! || rb.bool_object(rb.call('acquire', 'operator', 'lt', [
		o(attr(args, 'timeout')!),
		rb.ordinary(ah.Value(1)),
	], {})!)! {
		parser_error(parser, '--rounds and --timeout must be positive')!
	}
	setattr(args, 'repo', method(attr(args, 'repo')!, 'resolve', [])!)!
	setattr(args, 'build', optional(args, 'build', 'build-aarch64-dhewm3')!)!
	setattr(args, 'kernel_dir', optional(args, 'kernel_dir', 'kernel')!)!
	selected := attr(args, 'os')!
	if (rb.eq_value(selected, ah.Value('debian'))! || rb.eq_value(selected, ah.Value('both'))!) && (!flag(args, 'debian_kernel')! || !flag(args, 'debian_root')!) {
		parser_error(parser, 'Debian runs require --debian-kernel and --debian-root')!
	}
	if flag(args, 'record')! && rb.eq_value(attr(args, 'os')!, ah.Value('both'))! {
		parser_error(parser, 'Record once on one OS, then replay the shared file on both')!
	}
	work := method(attr(args, 'work')!, 'resolve', [])!
	mkdir(work, true)!
	root := rb.api('prepare', [o(args), o(work)], {}, true)!
	results := rb.call('acquire', 'builtins', 'list', [], {})!
	mut names := []ah.Value{}
	if rb.eq_value(attr(args, 'os')!, ah.Value('both'))! {
		names = [literal('vinix')!, literal('debian')!]
	} else {
		names = [attr(args, 'os')!]
	}
	for name in names {
		append(results, rb.api('run_guest', [o(args), o(work), o(root), o(name)], {}, true)!)!
	}
	encoded := rb.call('acquire', 'json', 'dumps', [o(results)], {
		'indent': ah.Value(2)
	})!
	report := rb.call('acquire', 'operator', 'add', [o(encoded), v('\n')], {})!
	rb.method('invoke', join(work, 'results.json')!, 'write_text', [o(report)], {})!
	rb.callback('print', {
		'data': ah.Value(text(report)!)
	})!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	match ah.field(row, 'operation').text() {
		'copy_layer' { copy_layer(rb.borrow('source')!, rb.borrow('dest')!)! }
		'prepare' { return rb.result_object(prepare(rb.borrow('args')!, rb.borrow('work')!)!) }
		'image' {
			image(rb.borrow('root')!, rb.borrow('output')!, rb.bool_object(rb.borrow('linux')!)!)!
		}
		'result' {
			return rb.result_object(result(rb.borrow('args')!, rb.borrow('work')!, rb.borrow('transcript')!, rb.borrow('os_name')!)!)
		}
		'main' { main_workflow(rb.borrow('args')!, rb.borrow('parser')!)! }
		else { return error('Unknown dhewm3 runner operation') }
	}
	return rb.null()
}
