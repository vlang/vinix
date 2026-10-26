// SPDX-License-Identifier: GPL-2.0-or-later
// Source-generated NIBArchive fixtures. No application archive bytes are embedded.
module nibfixture

pub struct Value {
pub mut:
	key string
	kind u8
	bytes []u8
}

pub struct Object {
pub mut:
	class_name string
	values []Value
}

pub fn little(value u64, count int) []u8 {
	mut result := []u8{len: count}
	for i in 0 .. count { result[i] = u8(value >> (i * 8)) }
	return result
}

pub fn variable(value int) []u8 {
	mut result := []u8{}
	mut number := u32(value)
	for number >= 128 { result << u8(number & 127); number >>= 7 }
	result << u8(number | 128)
	return result
}

pub fn ref(key string, object int) Value { return Value{key, 10, little(u64(object), 4)} }
pub fn int_value(key string, value u64) Value { return Value{key, 3, little(value, 8)} }
pub fn flag(key string, value bool) Value { return Value{key, if value { u8(5) } else { u8(4) }, []u8{}} }
pub fn data(key string, bytes []u8) Value { return Value{key, 8, bytes} }
pub fn real(key string, number f64) Value {
	bits := unsafe { *(&u64(&number)) }
	return Value{key, 7, little(bits, 8)}
}
pub fn text(text string) Object { return Object{'NSString', [data('NS.bytes', text.bytes())]} }
pub fn list(items []int) Object {
	mut object := Object{'NSArray', [flag('NSInlinedValue', true)]}
	for item in items { object.values << ref('UINibEncoderEmptyKey', item) }
	return object
}
pub fn geometry(key string, numbers []f64) Value {
	mut bytes := [u8(7)]
	for number in numbers { bits := unsafe { *(&u64(&number)) }; bytes << little(bits, 8) }
	return data(key, bytes)
}

pub fn encode(objects []Object) []u8 {
	mut keys := []string{}
	mut classes := []string{}
	mut values := []Value{}
	mut ranges := []u8{}
	for object in objects {
		if object.class_name !in classes { classes << object.class_name }
		ranges << variable(classes.index(object.class_name))
		ranges << variable(values.len)
		ranges << variable(object.values.len)
		for value in object.values { if value.key !in keys { keys << value.key }; values << value }
	}
	mut bytes := []u8{len: 50}
	for i, b in 'NIBArchive'.bytes() { bytes[i] = b }
	mut header := [u32(1), 9, u32(objects.len), 50]
	bytes << ranges
	header << [u32(keys.len), u32(bytes.len)]
	for key in keys { bytes << variable(key.len); bytes << key.bytes() }
	header << [u32(values.len), u32(bytes.len)]
	for value in values {
		bytes << variable(keys.index(value.key)); bytes << value.kind
		if value.kind == 8 { bytes << variable(value.bytes.len) }
		bytes << value.bytes
	}
	header << [u32(classes.len), u32(bytes.len)]
	for name in classes { bytes << variable(name.len + 1); bytes << u8(128); bytes << name.bytes(); bytes << u8(0) }
	for i, word in header { for b in 0 .. 4 { bytes[10 + i * 4 + b] = u8(word >> (b * 8)) } }
	return bytes
}

fn root() Object {
	return Object{'NSObject', [ref('UINibTopLevelObjectsKey', 1), ref('UINibObjectsKey', 1),
		ref('UINibConnectionsKey', 2), ref('UINibVisibleWindowsKey', 3),
		ref('UINibAccessibilityConfigurationsKey', 3), ref('UINibTraitStorageListsKey', 3), ref('UINibKeyValuePairsKey', 3)]}
}

pub fn controller() []Object {
	return [root(), list([4, 5, 6]), list([7, 8]), list([]int{}),
		Object{'UIClassSwapper', [ref('UIExternalObjectsTableForViewLoading', 9), ref('UINibName', 10),
			ref('UIStoryboardIdentifier', 11), ref('UIRestorationIdentifier', 11), ref('UIClassName', 12), ref('UIOriginalClassName', 12)]},
		Object{'UIProxyObject', [ref('UIProxiedObjectIdentifier', 13)]},
		Object{'UIProxyObject', [ref('UIProxiedObjectIdentifier', 14)]},
		Object{'UIRuntimeOutletConnection', [ref('UILabel', 15), ref('UISource', 5), ref('UIDestination', 4)]},
		Object{'UIRuntimeOutletConnection', [ref('UILabel', 16), ref('UISource', 4), ref('UIDestination', 6)]},
		Object{'NSDictionary', [flag('NSInlinedValue', true)]}, text('View'), text('LaunchScreen'), text('UIViewController'),
		text('IBFilesOwner'), text('UIStoryboardPlaceholder'), text('sceneViewController'), text('storyboard')]
}

pub fn view() []Object {
	bounds := geometry('UIBounds', [f64(0), 0, 64, 48])
	center := geometry('UICenter', [f64(32), 24])
	return [root(), list([4, 5, 6]), list([7]), list([]int{}),
		Object{'UIView', [bounds, center, int_value('UIAutoresizingMask', 18), ref('UISubviews', 8), ref('UIBackgroundColor', 9)]},
		Object{'UIProxyObject', [ref('UIProxiedObjectIdentifier', 10)]},
		Object{'UIImageView', [bounds, center, int_value('UIAutoresizingMask', 18), int_value('UIContentMode', 2),
			flag('UIClipsToBounds', true), flag('UIOpaque', true), flag('UIUserInteractionDisabled', true), ref('UIImage', 11)]},
		Object{'UIRuntimeOutletConnection', [ref('UILabel', 12), ref('UISource', 5), ref('UIDestination', 4)]},
		list([6]), Object{'UIColor', [int_value('UIColorComponentCount', 4), int_value('NSColorSpace', 2),
			real('UIRed', 1), real('UIGreen', 1), real('UIBlue', 1), real('UIAlpha', 1)]},
		text('IBFilesOwner'), Object{'UIImageNibPlaceholder', [real('UIImageWidth', 1), real('UIImageHeight', 1), ref('UIResourceName', 13)]},
		text('view'), text('Pixel.png'), text(''),
		Object{'UILayoutGuide', [Value{'UILayoutGuideOwningView', 9, []u8{}},
			ref('UILayoutGuideIdentifier', 14)]}]
}

pub const index = '<?xml version="1.0"?><plist version="1.0"><dict><key>UIStoryboardVersion</key><integer>1</integer><key>UIStoryboardDesignatedEntryPointIdentifier</key><string>LaunchScreen</string><key>UIViewControllerIdentifiersToNibNames</key><dict><key>LaunchScreen</key><string>LaunchScreen</string></dict></dict></plist>'

fn chunk(name string, data []u8) []u8 {
	mut result := little(u64(data.len), 4)
	result.reverse_in_place()
	result << name.bytes(); result << data
	mut crc := u32(0xffffffff)
	for b in result[4..] {
		crc ^= b
		for _ in 0 .. 8 { crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
	}
	mut checksum := little(u64(crc ^ 0xffffffff), 4); checksum.reverse_in_place(); result << checksum
	return result
}

pub fn cgbi_png() []u8 {
	mut bytes := [u8(137), 80, 78, 71, 13, 10, 26, 10]
	bytes << chunk('CgBI', []u8{})
	bytes << chunk('IHDR', [u8(0), 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0])
	// Raw DEFLATE stored block: filter zero, premultiplied BGRA red/half alpha.
	bytes << chunk('IDAT', [u8(1), 5, 0, 250, 255, 0, 0, 0, 128, 128])
	bytes << chunk('IEND', []u8{})
	return bytes
}
