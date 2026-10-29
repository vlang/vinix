// SPDX-License-Identifier: GPL-2.0-or-later
// Binder-style authenticator calls may block on services delivered by the main
// Looper. One bounded worker owns copied commands and a retained Binder; UI
// launches and the service lifetime pump remain on the main thread.
@[translated]
module atlframework

@[typedef]
struct C.pthread_cond_t {}

fn C.pthread_cond_init(&C.pthread_cond_t, voidptr) i32
fn C.pthread_cond_wait(&C.pthread_cond_t, &C.pthread_mutex_t) i32
fn C.pthread_cond_signal(&C.pthread_cond_t) i32
fn C.pthread_cond_destroy(&C.pthread_cond_t) i32

struct WsAuthWorker {
mut:
	vm voidptr
	binder voidptr
	wake C.pthread_cond_t
	commands [8]&WsAuthCommand
	count u32
	active_id u64
	active_cancelled bool
	stopping bool
	exited bool
}

__global ws_auth_worker &WsAuthWorker
__global ws_auth_worker_failure i32

// The caller holds ws_auth_mutex. No Java code or JNI references are released
// here. An active call owns its command until it returns.
fn ws_auth_worker_stop_locked(worker &WsAuthWorker) {
	unsafe {
		worker.stopping = true
		for i := u32(0); i < worker.count; i++ {
			ws_auth_command_free(worker.commands[i])
			worker.commands[i] = nil
		}
		worker.count = 0
		C.pthread_cond_signal(&worker.wake)
	}
}

fn ws_auth_worker_error() i32 {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		value := ws_auth_worker_failure
		C.pthread_mutex_unlock(&ws_auth_mutex)
		return value
	}
}

// Slot insertion runs under the same mutex as cancellation and shutdown.
fn ws_auth_worker_active_locked(id u64) bool {
	unsafe {
		return ws_auth_worker != nil && !ws_auth_worker.stopping
			&& ws_auth_worker.active_id == id && !ws_auth_worker.active_cancelled
	}
}

fn ws_auth_worker_release(e voidptr, worker &WsAuthWorker) {
	unsafe {
		Drop(slot(e,22))(e,worker.binder)
		C.pthread_cond_destroy(&worker.wake)
		C.free(worker)
	}
}

fn ws_auth_worker_run(context voidptr) voidptr {
	unsafe {
		worker := &WsAuthWorker(context)
		mut e := voidptr(nil)
		if WsTextureAttach(slot(worker.vm,7))(worker.vm,&e,nil) != 0 || e == nil {
			C.pthread_mutex_lock(&ws_auth_mutex)
			ws_auth_worker_failure = -1
			ws_auth_worker_stop_locked(worker)
			// Only the main thread has a JNIEnv on attachment failure. It takes
			// this context during shutdown and releases the retained Binder.
			worker.exited = true
			C.pthread_mutex_unlock(&ws_auth_mutex)
			return nil
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		ws_auth_worker_thread = usize(C.pthread_self())
		C.pthread_mutex_unlock(&ws_auth_mutex)
		for {
			C.pthread_mutex_lock(&ws_auth_mutex)
			for worker.count == 0 && !worker.stopping {
				if C.pthread_cond_wait(&worker.wake,&ws_auth_mutex) != 0 {
					ws_auth_worker_failure = -2
					ws_auth_worker_stop_locked(worker)
				}
			}
			if worker.stopping { C.pthread_mutex_unlock(&ws_auth_mutex); break }
			command := worker.commands[0]
			worker.count--
			for i := u32(0); i < worker.count; i++ { worker.commands[i] = worker.commands[i + 1] }
			worker.commands[worker.count] = nil
			worker.active_id = command.id
			worker.active_cancelled = false
			C.pthread_mutex_unlock(&ws_auth_mutex)
			frame := FramePush(slot(e,19))(e,128) == 0
			C.pthread_mutex_lock(&ws_auth_mutex)
			live := !worker.stopping && !worker.active_cancelled && ws_auth_handle != nil
			C.pthread_mutex_unlock(&ws_auth_mutex)
			mut ok := frame && !pending(e) && (!live || ws_auth_dispatch(e,worker.binder,command))
			if !ok && !pending(e) {
				C.pthread_mutex_lock(&ws_auth_mutex)
				// A canceled store/token lookup can legitimately lose its native
				// session between the snapshot and the backend operation.
				ok = worker.stopping || worker.active_cancelled || ws_auth_handle == nil
				C.pthread_mutex_unlock(&ws_auth_mutex)
			}
			if !ok {
				// JNIEnv and pending exceptions are thread-local. Retain the trace
				// in private service stderr; the main pump sees only a failure code.
				ws_failure(e,c'ANDROID-SERVICE-FAIL authenticator worker')
				if pending(e) { WsApplicationClear(slot(e,17))(e) }
			}
			if frame { pop_frame(e) }
			ws_auth_command_free(command)
			C.pthread_mutex_lock(&ws_auth_mutex)
			worker.active_id = 0
			worker.active_cancelled = false
			if !ok { ws_auth_worker_failure = -3; ws_auth_worker_stop_locked(worker) }
			C.pthread_mutex_unlock(&ws_auth_mutex)
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		ws_auth_scope = false
		ws_auth_worker_thread = 0
		if voidptr(ws_auth_worker) == voidptr(worker) { ws_auth_worker = nil }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		vm := worker.vm
		ws_auth_worker_release(e,worker)
		WsTextureDetach(slot(vm,5))(vm)
		return nil
	}
}

fn ws_auth_worker_start(e voidptr, binder voidptr) bool {
	unsafe {
		C.pthread_mutex_lock(&ws_auth_mutex)
		existing := ws_auth_worker != nil
		allowed := ws_auth_handle != nil && ws_auth_worker_failure == 0
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if existing || !allowed { return existing && allowed }
		mut vm := voidptr(nil)
		if WsTextureGetVM(slot(e,219))(e,&vm) != 0 || vm == nil { return false }
		retained := WsRef(slot(e,21))(e,binder)
		if retained == nil || pending(e) {
			if retained != nil { Drop(slot(e,22))(e,retained) }
			return false
		}
		worker := &WsAuthWorker(C.calloc(1,sizeof(WsAuthWorker)))
		if worker == nil { Drop(slot(e,22))(e,retained); return false }
		worker.vm = vm
		worker.binder = retained
		if C.pthread_cond_init(&worker.wake,nil) != 0 {
			Drop(slot(e,22))(e,retained); C.free(worker); return false
		}
		C.pthread_mutex_lock(&ws_auth_mutex)
		if ws_auth_handle == nil || ws_auth_worker != nil || ws_auth_worker_failure != 0 {
			C.pthread_mutex_unlock(&ws_auth_mutex)
			ws_auth_worker_release(e,worker)
			return false
		}
		ws_auth_worker = worker
		mut worker_thread := C.pthread_t{}
		created := C.pthread_create(&worker_thread,nil,ws_auth_worker_run,worker)
		if created != 0 { ws_auth_worker = nil }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if created != 0 { ws_auth_worker_release(e,worker); return false }
		// One worker per service; failure to detach is terminal. Its context
		// remains owned by that thread until return/process exit.
		if C.pthread_detach(worker_thread) != 0 {
			C.pthread_mutex_lock(&ws_auth_mutex)
			ws_auth_worker_failure = -4
			if voidptr(ws_auth_worker) == voidptr(worker) { ws_auth_worker_stop_locked(worker) }
			C.pthread_mutex_unlock(&ws_auth_mutex)
			return false
		}
		return true
	}
}

// Success consumes the copied command, either by queueing it or replying busy.
// Failure leaves it with the pump. Never pass main-thread local JNI references.
fn ws_auth_worker_enqueue(e voidptr, binder voidptr, command &WsAuthCommand) bool {
	unsafe {
		if !ws_auth_worker_start(e,binder) { return false }
		C.pthread_mutex_lock(&ws_auth_mutex)
		worker := ws_auth_worker
		allowed := worker != nil && !worker.stopping && ws_auth_worker_failure == 0 && ws_auth_handle != nil
		full := allowed && worker.count >= 8
		busy := if full { ws_auth_response(ws_auth_handle,command.id,2) } else { voidptr(nil) }
		if allowed && !full { worker.commands[worker.count] = command; worker.count++; C.pthread_cond_signal(&worker.wake) }
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if full {
			if busy == nil { return false }
			sent := ws_auth_error_fields(busy,1,c'authenticator worker queue is full') && ws_auth_send(busy) == 0
			ws_auth_free(busy)
			if sent { ws_auth_command_free(command) }
			return sent
		}
		return allowed
	}
}

fn ws_auth_worker_cancel(id u64) {
	unsafe {
		mut removed := &WsAuthCommand(nil)
		C.pthread_mutex_lock(&ws_auth_mutex)
		worker := ws_auth_worker
		if worker != nil {
			if worker.active_id == id { worker.active_cancelled = true }
			for i := u32(0); i < worker.count; i++ {
				if worker.commands[i].id != id { continue }
				removed = worker.commands[i]
				worker.count--
				for j := i; j < worker.count; j++ { worker.commands[j] = worker.commands[j + 1] }
				worker.commands[worker.count] = nil
				break
			}
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if removed != nil { ws_auth_command_free(removed) }
	}
}

fn ws_auth_worker_shutdown(e voidptr) {
	unsafe {
		mut stopped := &WsAuthWorker(nil)
		C.pthread_mutex_lock(&ws_auth_mutex)
		worker := ws_auth_worker
		if worker != nil {
			ws_auth_worker_stop_locked(worker)
			if worker.exited { stopped = worker; ws_auth_worker = nil }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if stopped != nil { ws_auth_worker_release(e,stopped) }
		// Do not join an active Java call: it may need the main Looper to finish.
		// native-entry exits immediately when the service returns; the context,
		// Binder and daemon attachment survive until the call returns or exit.
	}
}
