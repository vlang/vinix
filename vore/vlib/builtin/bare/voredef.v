module builtin

#include <vore.h>

__global stdout_consumer fn (byte)
__global stderr_consumer fn (byte)

pub struct C.string {
pub:
	str byteptr
	len int
}

fn C.v_version() string

fn C.v_build_date() string

fn C.tos(s byteptr, len int) string

fn C.tos2(s byteptr) string

fn C.tos3(s byteptr) string

fn C.strlen(s byteptr) int

fn C.strstr(s byteptr) voidptr

fn C.memset(s voidptr, val byte, len int)

fn C.memput(s voidptr, off int, val byte)

fn C.memputd(s voidptr, off int, val u32)