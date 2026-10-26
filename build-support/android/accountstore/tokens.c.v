// SPDX-License-Identifier: GPL-2.0-or-later
module accountstore

const max_token_scalar = 4096

// AccountManagerService.setPasswordInternal clears tokens in the password
// transaction (AOSP android-8.0.0_r4). A failed purge must retain both old values.
fn delete_account_tokens(db voidptr, id i64) ! {
	statement := prepare(db, 'DELETE FROM authtokens WHERE account=?')!
	defer { C.sqlite3_finalize(statement) }
	if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
		return error('cannot bind account identity')
	}
	if C.sqlite3_step(statement) != C.SQLITE_DONE {
		return error('cannot clear account tokens')
	}
}

// These are only values explicitly supplied by the selected authenticator via
// setAuthToken. Authenticator responses, including custom tokens, are not cached.
// Like other store reads, the returned value is an owned clone.
pub fn (mut s Store) auth_token(account Account, token_type string) !NullableString {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	s.check_account(account)!
	if !valid_text(token_type, max_token_scalar, false) {
		return error('account token type is invalid')
	}
	statement := prepare(s.db, 'SELECT t.token FROM authtokens t JOIN accounts a ON a.id=t.account WHERE a.name=? AND a.type=? AND t.token_type=?')!
	defer { C.sqlite3_finalize(statement) }
	bind_text(statement, 1, account.name)!
	bind_text(statement, 2, account.account_type)!
	bind_text(statement, 3, token_type)!
	status := C.sqlite3_step(statement)
	if status == C.SQLITE_DONE { return NullableString{} }
	if status != C.SQLITE_ROW { return error('cannot read account token') }
	return NullableString{ value: column_text(statement, 0, max_token_scalar)! }
}

pub fn (mut s Store) set_auth_token(account Account, token_type string, value ?string) ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	if !valid_text(token_type, max_token_scalar, false) {
		return error('account token type is invalid')
	}
	if text := value {
		if !valid_text(text, max_token_scalar, true) {
			return error('account token value is invalid')
		}
	}
	execute(s.db, 'BEGIN IMMEDIATE')!
	mut committed := false
	defer { if !committed { execute(s.db, 'ROLLBACK') or {} } }
	id := s.account_id(account)!
	if text := value {
		count := prepare(s.db, 'SELECT count(*),coalesce(sum(length(CAST(token_type AS BLOB))+length(CAST(token AS BLOB))),0) FROM authtokens WHERE account=? AND token_type!=?')!
		if C.sqlite3_bind_int64(count, 1, id) != C.SQLITE_OK {
			C.sqlite3_finalize(count)
			return error('cannot bind account identity')
		}
		bind_text(count, 2, token_type) or {
			C.sqlite3_finalize(count)
			return err
		}
		if C.sqlite3_step(count) != C.SQLITE_ROW {
			C.sqlite3_finalize(count)
			return error('cannot bound account tokens')
		}
		entries := C.sqlite3_column_int64(count, 0)
		bytes := C.sqlite3_column_int64(count, 1)
		C.sqlite3_finalize(count)
		if entries >= max_entries || bytes + token_type.len + text.len > max_payload {
			return error('account token limit exceeded')
		}
		statement := prepare(s.db, 'INSERT OR REPLACE INTO authtokens(account,token_type,token) VALUES(?,?,?)')!
		if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
			C.sqlite3_finalize(statement)
			return error('cannot bind account identity')
		}
		bind_text(statement, 2, token_type) or {
			C.sqlite3_finalize(statement)
			return err
		}
		bind_text(statement, 3, text) or {
			C.sqlite3_finalize(statement)
			return err
		}
		status := C.sqlite3_step(statement)
		C.sqlite3_finalize(statement)
		if status != C.SQLITE_DONE { return error('cannot store account token') }
	} else {
		statement := prepare(s.db, 'DELETE FROM authtokens WHERE account=? AND token_type=?')!
		if C.sqlite3_bind_int64(statement, 1, id) != C.SQLITE_OK {
			C.sqlite3_finalize(statement)
			return error('cannot bind account identity')
		}
		bind_text(statement, 2, token_type) or {
			C.sqlite3_finalize(statement)
			return err
		}
		status := C.sqlite3_step(statement)
		C.sqlite3_finalize(statement)
		if status != C.SQLITE_DONE { return error('cannot delete account token') }
	}
	execute(s.db, 'COMMIT')!
	committed = true
}

// Invalidation matches the complete token value across accounts of this one
// authenticator type. It does not touch passwords, user data, or visibility.
pub fn (mut s Store) invalidate_auth_token(account_type string, token string) ! {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	s.require_open()!
	if account_type != s.allowed_type || !valid_text(token, max_token_scalar, true) {
		return error('account token invalidation is invalid')
	}
	statement := prepare(s.db, 'DELETE FROM authtokens WHERE token=? AND account IN (SELECT id FROM accounts WHERE type=?)')!
	defer { C.sqlite3_finalize(statement) }
	bind_text(statement, 1, token)!
	bind_text(statement, 2, account_type)!
	if C.sqlite3_step(statement) != C.SQLITE_DONE {
		return error('cannot invalidate account token')
	}
}
