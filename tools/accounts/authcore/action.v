// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Actions: the privileged things the authentication service will do for
// someone who is not root. Each is a file in a directory only root can
// write, naming one program, its fixed arguments, and what the caller may
// add to them. There is no way to ask for a command that is not listed, and
// no argument reaches a program unchecked.
//
//	description = Restart the computer
//	auth = session
//	exec = /usr/sbin/vinix-system
//	arg = power
//	arg = restart
//
// `auth` is who may ask:
//
//	admin    a member of the admin group, with their own password
//	session  the person at the machine without a password; anyone else as
//	         `admin`
//	self     any person, with their own password
//	account  any ordinary account, identified by the kernel, without a
//	         password; only for explicitly public, bounded service actions
//
// `param` lines say what the caller supplies, in order, after the fixed
// arguments: `name` (an account name), `hostname`, `number`, `text` (one
// line of printable text that does not start with a hyphen) or
// `choice:a,b,c`. `input = secret` lets the caller send up to 4096 bytes
// that the program reads from standard input: a new password, which must
// not be on a command line.
module authcore

import accountcore

pub const max_action_name = 48
pub const max_params = 6
pub const max_text = 256

pub enum AuthRule {
	admin
	session
	self
	account
}

pub enum ParamKind {
	name
	hostname
	number
	text
	choice
}

pub struct Param {
pub:
	kind    ParamKind
	choices []string
}

pub struct Action {
pub:
	name        string
	description string
	auth        AuthRule
	exec        string
	args        []string
	params      []Param
	input       bool
}

pub fn valid_action_name(name string) bool {
	if name.len == 0 || name.len > max_action_name || name[0] < `a` || name[0] > `z` {
		return false
	}
	for i in 1 .. name.len {
		ch := name[i]
		if !((ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) || ch == `-`) {
			return false
		}
	}
	return true
}

fn valid_hostname(text string) bool {
	if text.len == 0 || text.len > 63 || text[0] == `-` || text[text.len - 1] == `-` {
		return false
	}
	for i in 0 .. text.len {
		ch := text[i]
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
			|| ch == `-`) {
			return false
		}
	}
	return true
}

fn valid_number(text string) bool {
	if text.len == 0 || text.len > 10 {
		return false
	}
	for i in 0 .. text.len {
		if text[i] < `0` || text[i] > `9` {
			return false
		}
	}
	return true
}

fn valid_fixed_argument(text string) bool {
	if text.len == 0 || text.len > max_text {
		return false
	}
	for i in 0 .. text.len {
		if text[i] < 0x20 || text[i] == 0x7f {
			return false
		}
	}
	return true
}

// Whether `value` is something the caller may put in this position.
pub fn (p Param) accepts(value string) bool {
	return match p.kind {
		.name { accountcore.valid_name(value) }
		.hostname { valid_hostname(value) }
		.number { valid_number(value) }
		.text { value.len > 0 && value.len <= max_text && value[0] != `-`
				&& accountcore.valid_field(value.replace(':', ' '), max_text) }
		.choice { value in p.choices }
	}
}

fn parse_param(value string) !Param {
	match value {
		'name' {
			return Param{
				kind: .name
			}
		}
		'hostname' {
			return Param{
				kind: .hostname
			}
		}
		'number' {
			return Param{
				kind: .number
			}
		}
		'text' {
			return Param{
				kind: .text
			}
		}
		else {}
	}
	if value.starts_with('choice:') {
		choices := value[7..].split(',')
		if choices.len < 2 || choices.len > 16 {
			return error('a choice needs between 2 and 16 values')
		}
		for choice in choices {
			if !valid_action_name(choice) {
				return error('invalid choice "${choice}"')
			}
		}
		return Param{
			kind:    .choice
			choices: choices
		}
	}
	return error('unknown parameter kind "${value}"')
}

// An action from the text of its file. A line that is not understood makes
// the whole action unusable: half an action is not a narrower one.
pub fn parse_action(name string, text string) !Action {
	if !valid_action_name(name) {
		return error('invalid action name')
	}
	if text.len > 4096 {
		return error('action file too large')
	}
	mut description := ''
	mut exec := ''
	mut auth := AuthRule.admin
	mut have_auth := false
	mut args := []string{}
	mut params := []Param{}
	mut input := false
	for number, raw in text.split_into_lines() {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		eq := line.index('=') or { return error('line ${number + 1}: expected key = value') }
		key := line[..eq].trim_space()
		value := line[eq + 1..].trim_space()
		match key {
			'description' {
				if description != '' || !valid_fixed_argument(value) {
					return error('line ${number + 1}: invalid description')
				}
				description = value
			}
			'auth' {
				if have_auth {
					return error('line ${number + 1}: auth given twice')
				}
				have_auth = true
				auth = match value {
					'admin' { AuthRule.admin }
					'session' { AuthRule.session }
					'self' { AuthRule.self }
					'account' { AuthRule.account }
					else { return error('line ${number + 1}: unknown auth rule "${value}"') }
				}
			}
			'exec' {
				if exec != '' || !accountcore.valid_path(value) {
					return error('line ${number + 1}: exec must be one absolute path')
				}
				exec = value
			}
			'arg' {
				if !valid_fixed_argument(value) || args.len >= 16 {
					return error('line ${number + 1}: invalid argument')
				}
				args << value
			}
			'param' {
				if params.len >= max_params {
					return error('line ${number + 1}: too many parameters')
				}
				params << parse_param(value) or { return error('line ${number + 1}: ${err.msg()}') }
			}
			'input' {
				if value != 'secret' || input {
					return error('line ${number + 1}: input must be "secret"')
				}
				input = true
			}
			else {
				return error('line ${number + 1}: unknown key "${key}"')
			}
		}
	}
	if description == '' || exec == '' || !have_auth {
		return error('an action needs a description, an auth rule and an exec')
	}
	return Action{
		name:        name
		description: description
		auth:        auth
		exec:        exec
		args:        args
		params:      params
		input:       input
	}
}

// The argument vector for a call, or why the caller's arguments will not do.
pub fn (a Action) arguments(supplied []string) ![]string {
	if supplied.len != a.params.len {
		return error('${a.name} takes ${a.params.len} arguments')
	}
	mut argv := [a.exec]
	argv << a.args
	for i, value in supplied {
		if !a.params[i].accepts(value) {
			return error('argument ${i + 1} of ${a.name} is not acceptable')
		}
		argv << value
	}
	return argv
}
