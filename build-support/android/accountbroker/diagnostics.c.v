// SPDX-License-Identifier: GPL-2.0-or-later
// Public diagnostics contain only this finite schema. Request IDs, peer
// identities, tickets, component names and option values never enter records.
module accountbroker

import accountipc
import accounthandoff
import nativeaccountauth

#include <stdio.h>
#include <unistd.h>

fn C.snprintf(&char, usize, &char, ...) i32
fn C.write(i32, voidptr, usize) isize

fn handoff_write(record accounthandoff.HandoffDiagnostic) {
	if !accounthandoff.valid_handoff(record) { return }
	mut buffer := [128]char{}
	length := C.snprintf(&buffer[0], 128,
		c'ANDROID-ACCOUNT-HANDOFF stage=%d operation=%d event=%d code=%d\n',
		record.stage, record.operation, record.event, record.code)
	if length > 0 && length < 128 { C.write(2, &buffer[0], usize(length)) }
}

fn handoff_stage(stage accounthandoff.Stage, operation nativeaccountauth.Operation) {
	handoff_write(accounthandoff.HandoffDiagnostic{stage: int(stage), operation: int(operation)})
}

// Only Android's small public error-code domain is reported. Malformed,
// missing, duplicate or extension codes collapse to one unknown value.
fn handoff_error_code(event accountipc.Event) int {
	mut code := -1
	mut found := false
	for option in event.options {
		if option.key != 'errorCode' { continue }
		if found || option.value.kind != .int32 || option.value.number < 1
			|| option.value.number > 9 { return -1 }
		found = true
		code = int(option.value.number)
	}
	return code
}

fn handoff_terminal(operation nativeaccountauth.Operation, event accountipc.Event) {
	if event.kind !in [.result, .failure] { return }
	handoff_write(accounthandoff.HandoffDiagnostic{
		stage: int(accounthandoff.Stage.terminal)
		operation: int(operation)
		event: int(event.kind)
		code: if event.kind == .failure { handoff_error_code(event) } else { 0 }
	})
}
