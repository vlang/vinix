// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Vinix has no account authenticator installed. Keep listener registrations
// and dispatch the real (empty) account snapshot on the requested Handler.
fn ws_accounts_add(e voidptr, manager voidptr, listener voidptr, handler voidptr, immediately u8) {
	unsafe {
		if listener == nil {
			throw(e, c'java/lang/IllegalArgumentException', c'listener is null')
			return
		}
		listeners := get_object(e, manager, c'android/accounts/AccountManager', c'vinixListeners', c'Ljava/util/HashMap;')
		args := [Value{ l: listener }, Value{ l: handler }]!
		if boolean(e, listeners, c'java/util/HashMap', c'containsKey', c'(Ljava/lang/Object;)Z', &args[0]) != 0 {
			throw(e, c'java/lang/IllegalStateException', c'this listener is already added')
			return
		}
		obj(e, listeners, c'java/util/HashMap', c'put', c'(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', &args[0])
		if pending(e) || immediately == 0 { return }
		mut target := handler
		if target == nil {
			looper := static_obj(e, c'android/os/Looper', c'getMainLooper', c'()Landroid/os/Looper;', nil)
			looper_args := [Value{ l: looper }]!
			target = new_object(e, c'android/os/Handler', c'(Landroid/os/Looper;)V', &looper_args[0])
		}
		if pending(e) { return }
		task := new_object(e, c'android/atl/VinixAccountUpdate', c'()V', nil)
		put_object(e, task, c'android/atl/VinixAccountUpdate', c'listener', c'Landroid/accounts/OnAccountsUpdateListener;', listener)
		post := [Value{ l: task }]!
		boolean(e, target, c'android/os/Handler', c'post', c'(Ljava/lang/Runnable;)Z', &post[0])
	}
}

fn ws_accounts_remove(e voidptr, manager voidptr, listener voidptr) {
	unsafe {
		if listener == nil {
			throw(e, c'java/lang/IllegalArgumentException', c'listener is null')
			return
		}
		listeners := get_object(e, manager, c'android/accounts/AccountManager', c'vinixListeners', c'Ljava/util/HashMap;')
		args := [Value{ l: listener }]!
		obj(e, listeners, c'java/util/HashMap', c'remove', c'(Ljava/lang/Object;)Ljava/lang/Object;', &args[0])
	}
}

fn ws_accounts_notify(e voidptr, task voidptr) {
	unsafe {
		listener := get_object(e, task, c'android/atl/VinixAccountUpdate', c'listener', c'Landroid/accounts/OnAccountsUpdateListener;')
		accounts := ObjectArrayNew(slot(e, 172))(e, 0, cls(e, c'android/accounts/Account'), nil)
		args := [Value{ l: accounts }]!
		call(e, listener, c'android/accounts/OnAccountsUpdateListener', c'onAccountsUpdated', c'([Landroid/accounts/Account;)V', &args[0])
	}
}
