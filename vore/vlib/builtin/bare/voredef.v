module builtin

#include <vore.h>

__global stdout_consumer fn (byte)
__global stderr_consumer fn (byte)

pub struct C.string {
pub:
	str byteptr
	len int
}