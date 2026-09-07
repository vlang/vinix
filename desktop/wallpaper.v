// Wallpapers: a flat gradient, or one of the photographs the build downloaded.
//
// Vinix has no JPEG or PNG decoder, so the photographs arrive already decoded:
// desktop/tools/fetch_wallpapers.py turns each into a `.vwp`, which is a nine
// byte header and packed RGB at half the display's resolution. Drawing one is
// then a scale and a blit, with no format to parse beyond that header.
//
// The scaled result is kept, because it only changes when the setting does.
// Rescaling three quarters of a million pixels on every frame to paint a
// backdrop that has not moved would cost more than everything else the
// compositor does put together.
module main

const wallpaper_dir = '/usr/share/vinix/wallpapers'
const wallpaper_index = '${wallpaper_dir}/index.txt'

// 'VWP1', then width and height as little-endian u16, then one reserved byte.
const vwp_magic = 'VWP1'
const vwp_header_size = 9

struct WallpaperImage {
	name string
	file string
}

struct RawImage {
	width  int
	height int
	pixels []u8 // RGB, row-major
}

// list_wallpapers reads the index the build wrote. A missing index is not an
// error: it means the build had no network and no cache, and the desktop
// offers its colours alone.
fn list_wallpapers() []WallpaperImage {
	info := desktop_stat(wallpaper_index) or { return [] }
	size := info.size
	if size == 0 {
		return []
	}
	mut buffer := []u8{len: int(size) + 1}
	got := desktop_read_file(wallpaper_index, buffer.data, size)
	if got <= 0 {
		return []
	}
	text := unsafe { tos(buffer.data, int(got)) }

	mut out := []WallpaperImage{}
	for line in text.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		space := trimmed.index(' ') or { continue }
		out << WallpaperImage{
			name: trimmed[space + 1..]
			file: '${wallpaper_dir}/${trimmed[..space]}'
		}
	}
	return out
}

fn load_raw_image(path string) ?RawImage {
	info := desktop_stat(path) or { return none }
	size := info.size
	if size <= u64(vwp_header_size) {
		return none
	}
	mut buffer := []u8{len: int(size)}
	got := desktop_read_file(path, buffer.data, size)
	if got < i64(vwp_header_size) {
		return none
	}
	for i in 0 .. vwp_magic.len {
		if buffer[i] != vwp_magic[i] {
			return none
		}
	}
	width := int(u16(buffer[4]) | u16(buffer[5]) << 8)
	height := int(u16(buffer[6]) | u16(buffer[7]) << 8)
	if width <= 0 || height <= 0 {
		return none
	}
	needed := vwp_header_size + width * height * 3
	if int(got) < needed {
		return none
	}
	return RawImage{
		width: width
		height: height
		pixels: buffer[vwp_header_size..needed].clone()
	}
}

// scale_into stretches the image over the whole of `out`, which is one screen's
// worth of pixels. The sampling is bilinear: an image stored at half the
// display's resolution doubled with nearest neighbour shows its blocks, and a
// backdrop is exactly where that is most visible.
//
// Coordinates are 16.16 fixed point. The source step is computed once per axis
// and accumulated, so the inner loop has no division in it.
fn (image &RawImage) scale_into(mut out []u32, width int, height int) {
	if width <= 0 || height <= 0 {
		return
	}
	step_x := if width > 1 { (image.width - 1) * 65536 / (width - 1) } else { 0 }
	step_y := if height > 1 { (image.height - 1) * 65536 / (height - 1) } else { 0 }

	for y in 0 .. height {
		fixed_y := y * step_y
		src_y := fixed_y >> 16
		fraction_y := u32(fixed_y & 0xffff) >> 8 // 0..255
		next_y := if src_y + 1 < image.height { src_y + 1 } else { src_y }
		row0 := src_y * image.width * 3
		row1 := next_y * image.width * 3
		out_row := y * width

		mut fixed_x := 0
		for x in 0 .. width {
			src_x := fixed_x >> 16
			fraction_x := u32(fixed_x & 0xffff) >> 8
			next_x := if src_x + 1 < image.width { src_x + 1 } else { src_x }
			fixed_x += step_x

			a := row0 + src_x * 3
			b := row0 + next_x * 3
			c := row1 + src_x * 3
			d := row1 + next_x * 3

			mut channels := [3]u32{}
			for channel in 0 .. 3 {
				top := blend_channel(image.pixels[a + channel], image.pixels[b + channel],
					fraction_x)
				bottom := blend_channel(image.pixels[c + channel], image.pixels[d + channel],
					fraction_x)
				channels[channel] = blend_channel(u8(top), u8(bottom), fraction_y)
			}
			out[out_row + x] = channels[0] << 16 | channels[1] << 8 | channels[2]
		}
	}
}

@[inline]
fn blend_channel(from u8, to u8, fraction u32) u32 {
	return (u32(from) * (255 - fraction) + u32(to) * fraction) / 255
}
