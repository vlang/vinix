// SPDX-License-Identifier: GPL-2.0-or-later
module runnercore

import androidhost as ah
import boothost
import json2
import os

pub struct BindingError {
pub:
	value map[string]ah.Value
}

pub fn (e BindingError) msg() string { return ah.field(e.value, 'message').text() }

pub fn (e BindingError) code() int { return 0 }

pub struct PolicyError {
pub:
	kind    string
	message string
}

pub fn (e PolicyError) msg() string { return e.message }

pub fn (e PolicyError) code() int { return 0 }

fn failed(kind string, message string) IError { return PolicyError{kind, message} }

fn callback(operation string, arguments map[string]ah.Value) !ah.Value {
	println(ah.encode(boothost.pack(ah.Value({
		'callback':  ah.Value(operation)
		'arguments': ah.Value(arguments)
	}))))
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line())!)!.object()
	if 'error' in row { return BindingError{ah.field(row, 'error').object()} }
	return ah.field(row, 'value')
}

fn null() ah.Value { return ah.Value(json2.Null{}) }

fn strings(values []string) ah.Value { return ah.Value(values.map(ah.Value(it))) }

fn boolean(value ah.Value) bool { return value is bool && value }

fn arg(kind string, value ah.Value) ah.Value { return ah.Value([ah.Value(kind), value]) }

fn value_arg(value ah.Value) ah.Value { return arg('value', value) }

fn path_arg(value string) ah.Value { return arg('path', ah.Value(value)) }

fn invoke(module_name string, name string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('invoke', {
		'module':    ah.Value(module_name)
		'name':      ah.Value(name)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn public(name string, arguments []ah.Value) !ah.Value {
	return invoke('', name, arguments, map[string]ah.Value{})!
}

fn library(module_name string, name string, arguments []ah.Value) !ah.Value {
	return invoke(module_name, name, arguments, map[string]ah.Value{})!
}

fn constant(name string) !ah.Value {
	return callback('constant', {
		'name': ah.Value(name)
	})!
}

fn option(name string) !ah.Value {
	return callback('argument', {
		'name': ah.Value(name)
	})!
}

fn path(value string, name string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('path', {
		'path':      ah.Value(value)
		'name':      ah.Value(name)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn join(parent string, child string) !string {
	return callback('join', {
		'parent': ah.Value(parent)
		'child':  ah.Value(child)
	})!.text()
}

fn mkdir(value string, parents bool, exist_ok bool) ! {
	path(value, 'mkdir', []ah.Value{}, {
		'parents':  ah.Value(parents)
		'exist_ok': ah.Value(exist_ok)
	})!
}

fn string_value(value ah.Value) !string {
	return callback('str', {
		'value': value
	})!.text()
}

fn arithmetic(name string, left ah.Value, right ah.Value) !ah.Value {
	return callback('operator', {
		'name':      ah.Value(name)
		'arguments': ah.Value([value_arg(left), value_arg(right)])
	})!
}

fn compare(name string, left ah.Value, right ah.Value) !bool {
	return boolean(arithmetic(name, left, right)!)
}

fn print_message(message string, flush bool) ! {
	callback('print', {
		'message': ah.Value(message)
		'options': ah.Value({
			'flush': ah.Value(flush)
		})
	})!
}

fn parser_error(message string) ! {
	callback('parser_error', {
		'message': ah.Value(message)
	})!
}

fn failure_value(cause IError) ah.Value {
	if cause is BindingError { return ah.Value(cause.value) }
	if cause is PolicyError {
		return ah.Value({
			'kind':    ah.Value(cause.kind)
			'message': ah.Value(cause.message)
		})
	}
	return ah.Value({
		'kind':    ah.Value('RuntimeError')
		'message': ah.Value(cause.msg())
	})
}

fn exit_owner(owner string, cause ?IError) !bool {
	return boolean(callback('exit', {
		'id':    ah.Value(owner)
		'error': if failure := cause { failure_value(failure) } else { null() }
	})!)
}
