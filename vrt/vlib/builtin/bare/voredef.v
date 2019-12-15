module builtin

#include <vrt.h>

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

fn C.atomic_load(ptr voidptr) byte

fn C.atomic_store(ptr voidptr, val byte)