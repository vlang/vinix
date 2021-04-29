module x86

fn atomic_inc<T>(var &T) {
	$if T is u64 {
		asm volatile amd64 {
			lock
			incq [var]
			;
			; r (var)
			; memory
		}
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_inc not supported for type ${typestr}')
	}
}

fn atomic_store<T>(var &T, value T) {
	$if T is u64 {
		asm volatile amd64 {
			lock
			xchgq [var], value
			;
			; r (var)
			  ri (value)
			; memory
		}
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_store not supported for type ${typestr}')
	}
}

fn atomic_load<T>(var &T) T {
	$if T is u64 {
		mut ret := u64(0)
		asm volatile amd64 {
			lock
			xaddq [var], ret
			; +r (ret)
			; r (var)
			; memory
		}
		return ret
	} $else {
		typestr := unsafe { typeof(var[0]).name }
		panic('atomic_load not supported for type ${typestr}')
	}
}
