// SPDX-License-Identifier: GPL-2.0-or-later
module wallpaperhost

import encoding.binary
import math
import os

$if !wallpaper_jpeg_custom ? {
	#pkgconfig libturbojpeg
}

#include <turbojpeg.h>
#include <math.h>

fn C.tjInitDecompress() voidptr
fn C.tjDestroy(voidptr) i32
fn C.tjDecompressHeader3(voidptr, &u8, usize, &i32, &i32, &i32, &i32) i32
fn C.tjDecompress2(voidptr, &u8, usize, &u8, i32, i32, i32, i32, i32) i32
fn C.tjGetErrorStr2(voidptr) &char
fn C.sin(f64) f64

pub struct Image {
pub:
	width  int
	height int
	pixels []u8
}

fn jpeg_error(handle voidptr) IError {
	return error(unsafe { C.tjGetErrorStr2(handle).vstring().clone() })
}

pub fn jpeg(path string) !Image {
	bytes := os.read_bytes(path)!
	handle := C.tjInitDecompress()
	if handle == unsafe { nil } { return error('could not initialize JPEG decoder') }
	defer { C.tjDestroy(handle) }
	mut width := i32(0)
	mut height := i32(0)
	mut sampling := i32(0)
	mut colour := i32(0)
	if C.tjDecompressHeader3(handle, bytes.data, usize(bytes.len), &width, &height, &sampling, &colour) != 0 {
		return jpeg_error(handle)
	}
	if width <= 0 || height <= 0 || u64(width) * u64(height) > u64(max_int) / 4 {
		return error('invalid JPEG dimensions')
	}
	components := if colour in [C.TJCS_CMYK, C.TJCS_YCCK] { 4 } else { 3 }
	mut pixels := []u8{len: int(width) * int(height) * components}
	format := if components == 4 { C.TJPF_CMYK } else { C.TJPF_RGB }
	if C.tjDecompress2(handle, bytes.data, usize(bytes.len), pixels.data, width, 0, height, format, C.TJFLAG_ACCURATEDCT) != 0 {
		return jpeg_error(handle)
	}
	if components == 4 {
		mut rgb := []u8{len: int(width) * int(height) * 3}
		for index in 0 .. int(width) * int(height) {
			for channel in 0 .. 3 {
				rgb[index * 3 + channel] = u8((int(pixels[index * 4 + channel]) * int(pixels[index * 4 + 3]) + 127) / 255)
			}
		}
		return Image{int(width), int(height), rgb}
	}
	return Image{int(width), int(height), pixels}
}

pub fn crop(image Image) !Image {
	if image.width <= 0 || image.height <= 0 || image.pixels.len != image.width * image.height * 3 {
		return error('invalid RGB image')
	}
	ratio := f64(512) / 384
	width := if f64(image.width) / f64(image.height) > ratio {
		int(f64(image.height) * ratio)
	} else {
		image.width
	}
	height := if f64(image.width) / f64(image.height) > ratio {
		image.height
	} else {
		int(f64(image.width) / ratio)
	}
	if width <= 0 || height <= 0 { return error('empty wallpaper crop') }
	left := (image.width - width) / 2
	top := (image.height - height) / 2
	mut pixels := []u8{len: width * height * 3}
	for y in 0 .. height {
		start := ((y + top) * image.width + left) * 3
		copy(mut pixels[y * width * 3..(y + 1) * width * 3], image.pixels[start..start + width * 3])
	}
	return Image{width, height, pixels}
}

struct Filter {
	start   int
	weights []i64
}

fn sinc(value f64) f64 {
	if value == 0 { return 1 }
	angle := value * math.pi
	return C.sin(angle) / angle
}

fn coefficients(input int, output int) []Filter {
	scale := f64(input) / f64(output)
	factor := if scale < 1 { f64(1) } else { scale }
	support := 3 * factor
	mut filters := []Filter{cap: output}
	for position in 0 .. output {
		center := (f64(position) + 0.5) * scale
		lower := int(center - support + 0.5)
		upper := int(center + support + 0.5)
		start := if lower < 0 { 0 } else { lower }
		end := if upper > input { input } else { upper }
		mut samples := []f64{cap: end - start}
		mut sum := f64(0)
		for index in start .. end {
			distance := (f64(index) - center + 0.5) * (1 / factor)
			weight := if distance >= -3 && distance < 3 {
				sinc(distance) * sinc(distance / 3)
			} else {
				f64(0)
			}
			samples << weight
			sum += weight
		}
		mut weights := []i64{cap: samples.len}
		for sample in samples {
			normalized := if sum != 0 { sample / sum } else { sample }
			scaled := normalized * f64(1 << 22)
			weights << i64(if normalized < 0 { -0.5 + scaled } else { 0.5 + scaled })
		}
		filters << Filter{start, weights}
	}
	return filters
}

fn clipped(sum i64) u8 {
	value := sum >> 22
	return u8(if value < 0 {
		0
	} else if value > 255 {
		255
	} else {
		value
	})
}

pub fn resize(image Image, width int, height int) !Image {
	if width <= 0 || height <= 0 || image.width <= 0 || image.height <= 0 || image.pixels.len != image.width * image.height * 3 {
		return error('invalid resample dimensions')
	}
	mut horizontal := image.pixels.clone()
	if width != image.width {
		filters := coefficients(image.width, width)
		horizontal = []u8{len: width * image.height * 3}
		for y in 0 .. image.height {
			for x, filter in filters {
				for channel in 0 .. 3 {
					mut total := i64(1 << 21)
					for index, weight in filter.weights {
						total += i64(image.pixels[(y * image.width + filter.start + index) * 3 + channel]) * weight
					}
					horizontal[(y * width + x) * 3 + channel] = clipped(total)
				}
			}
		}
	}
	if height == image.height { return Image{width, height, horizontal} }
	filters := coefficients(image.height, height)
	mut pixels := []u8{len: width * height * 3}
	for y, filter in filters {
		for x in 0 .. width {
			for channel in 0 .. 3 {
				mut total := i64(1 << 21)
				for index, weight in filter.weights {
					total += i64(horizontal[((filter.start + index) * width + x) * 3 + channel]) * weight
				}
				pixels[(y * width + x) * 3 + channel] = clipped(total)
			}
		}
	}
	return Image{width, height, pixels}
}

pub fn convert(source string, destination string) ! {
	image := resize(crop(jpeg(source)!)!, 512, 384)!
	mut bytes := 'VWP1'.bytes()
	mut dimensions := []u8{len: 5}
	binary.little_endian_put_u16(mut dimensions[..2], 512)
	binary.little_endian_put_u16(mut dimensions[2..4], 384)
	bytes << dimensions
	bytes << image.pixels
	os.write_file_array(destination, bytes)!
}
