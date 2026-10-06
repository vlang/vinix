module lib

type VoidCallback = fn ()

// The callback is borrowed and invoked synchronously before returning.
@[export: 'vinix_call_void_fn']
pub fn call_void_fn(callback voidptr) {
	unsafe { VoidCallback(callback)() }
}
