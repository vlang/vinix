module alpinecore

import androidhost as ah
import runtimebuild as rb

// Python's Unicode whitespace and splitlines sets, applied to owned UTF-8.
// Preserve every other byte, including WTF-8 supplied by a mocked reader.
pub fn space_width(text string, index int) int {
	c := text[index]
	if c == 0x20 || (c >= 9 && c <= 13) || (c >= 0x1c && c <= 0x1f) { return 1 }
	for delimiter in ['\u0085', '\u00a0', '\u1680', '\u2000', '\u2001', '\u2002', '\u2003', '\u2004',
		'\u2005', '\u2006', '\u2007', '\u2008', '\u2009', '\u200a', '\u2028', '\u2029', '\u202f',
		'\u205f', '\u3000'] {
		if text[index..].starts_with(delimiter) { return delimiter.len }
	}
	return 0
}

fn words(text string) []ah.Value {
	mut result := []ah.Value{}
	mut index := 0
	for index < text.len {
		width := space_width(text, index)
		if width != 0 {
			index += width
			continue
		}
		start := index
		for index < text.len && space_width(text, index) == 0 { index++ }
		result << ah.Value(text[start..index])
	}
	return result
}

pub fn lines(text string) []string {
	mut result := []string{}
	mut start := 0
	mut index := 0
	for index < text.len {
		mut width := 0
		c := text[index]
		if c == 10 || c == 11 || c == 12 || c == 13 || (c >= 0x1c && c <= 0x1e) { width = 1 }
		if c == 13 && index + 1 < text.len && text[index + 1] == 10 { width = 2 }
		for delimiter in ['\u0085', '\u2028', '\u2029'] {
			if text[index..].starts_with(delimiter) { width = delimiter.len }
		}
		if width == 0 {
			index++
			continue
		}
		result << text[start..index]
		index += width
		start = index
	}
	if start < text.len { result << text[start..] }
	return result
}

fn parse_index(path ah.Value) !ah.Value {
	contents := rb.method('acquire', path, 'read_text', [], {
		'encoding': ah.Value('utf-8')
	})!
	// This library split also retains original errors for a non-string reader.
	blocks := rb.method('invoke', contents, 'split', [rb.ordinary(ah.Value('\n\n'))], {})!.items()
	mut packages := []ah.Value{}
	for block in blocks {
		mut fields := map[string]string{}
		for line in lines(block.text()) {
			if line.len >= 2 && line[1] == `:` { fields[line[..1]] = line[2..] }
		}
		if 'P' !in fields || 'V' !in fields { continue }
		packages << ah.Value({
			'name':         ah.Value(fields['P'])
			'version':      ah.Value(fields['V'])
			'dependencies': ah.Value(words(fields['D']))
			'provides':     ah.Value(words(fields['p']))
		})
	}
	return ah.Value(packages)
}

fn dependency_key(specification ah.Value) !ah.Value {
	result := rb.call('acquire', 're', 'split', [rb.ordinary(ah.Value(r'[<>=~]')),
		rb.object(specification)], {
		'maxsplit': ah.Value(1)
	})!
	return rb.method('acquire', result, '__getitem__', [rb.ordinary(ah.Value(0))], {})!
}
