module alpinecore

import encoding.utf8
import os

fn starts_at(text string, index int, delimiter string) bool {
	if index > text.len - delimiter.len { return false }
	for offset, character in delimiter {
		if text[index + offset] != character { return false }
	}
	return true
}

// Python's Unicode whitespace and splitlines sets, applied to owned UTF-8.
// Preserve every other byte, including WTF-8 supplied by a mocked reader.
pub fn space_width(text string, index int) int {
	c := text[index]
	if c == 0x20 || (c >= 9 && c <= 13) || (c >= 0x1c && c <= 0x1f) { return 1 }
	if c < 0x80 { return 0 }
	for delimiter in ['\u0085', '\u00a0', '\u1680', '\u2000', '\u2001', '\u2002', '\u2003', '\u2004',
		'\u2005', '\u2006', '\u2007', '\u2008', '\u2009', '\u200a', '\u2028', '\u2029', '\u202f',
		'\u205f', '\u3000'] {
		if starts_at(text, index, delimiter) { return delimiter.len }
	}
	return 0
}

fn words(text string) []string {
	mut result := []string{}
	mut index := 0
	for index < text.len {
		width := space_width(text, index)
		if width != 0 {
			index += width
			continue
		}
		start := index
		for index < text.len && space_width(text, index) == 0 { index++ }
		result << text[start..index]
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
		if c >= 0x80 {
			for delimiter in ['\u0085', '\u2028', '\u2029'] {
				if starts_at(text, index, delimiter) { width = delimiter.len }
			}
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

pub fn parse_index(path string, repository string) ![]Package {
	return parse_text(os.read_file(path)!, repository)!
}

pub fn parse_text(text string, repository string) ![]Package {
	if !utf8.validate_str(text) { return error('APKINDEX is not valid UTF-8') }
	// Text-mode reads in the original command normalize both CRLF and CR.
	contents := text.replace('\r\n', '\n').replace('\r', '\n')
	blocks := contents.split('\n\n')
	mut packages := []Package{}
	for block in blocks {
		mut fields := map[string]string{}
		for line in lines(block) {
			if line.len >= 2 && line[1] == `:` { fields[line[..1]] = line[2..] }
		}
		if 'P' !in fields || 'V' !in fields { continue }
		packages << Package{
			name:         fields['P']
			version:      fields['V']
			dependencies: words(fields['D'])
			provides:     words(fields['p'])
			repository:   repository
		}
	}
	return packages
}

pub fn dependency_key(specification string) string {
	for index, character in specification {
		if character in [`<`, `>`, `=`, `~`] { return specification[..index] }
	}
	return specification
}
