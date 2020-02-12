module sys

import sync

const (
	CallbackPoolSize = 1024
)

struct Callback {
mut:
	cb_type int
	handler fn(voidptr)
}

struct CallbackPool {
mut:
	mutex sync.Mutex
	callbacks [1024]sys.Callback
}

pub fn emit_callback(cb_type int, cb_data voidptr) {
	//printk('Callback emit: $cb_type')
	for i := 0; i < 512; i++ {
		if (kernel.callback_pool.callbacks[i].cb_type == cb_type) {
			handler := kernel.callback_pool.callbacks[i].handler
			handler(cb_data)
		}
	}
}

pub fn register_callback(cb_type int, handler fn(voidptr)) int {
	//printk('Callback register: $cb_type')
	for i := 0; i < 512; i++ {
		if (kernel.callback_pool.callbacks[i].cb_type == 0) {
			kernel.callback_pool.callbacks[i].cb_type = cb_type
			kernel.callback_pool.callbacks[i].handler = handler
			return i + 1
		}
	}
	return 0
}

pub fn unregister_callback(id int) {

}