use crate::directory::WorkspaceError;
use serde::Serialize;

pub const MAX_TEXT_BYTES: usize = 8 * 1024 * 1024;

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TextEncoding {
    Utf8,
    Utf16Le,
    Utf16Be,
}

#[derive(Serialize)]
pub struct TextSnapshot<'a> {
    pub text: &'a str,
    pub encoding: TextEncoding,
    pub has_bom: bool,
    pub line_ending: &'static str,
    pub byte_count: usize,
}

/// The sole committed text/revision owner. Native IME/undo supplies ordered
/// UTF-16 edits; this document has no second undo stack or filesystem access.
pub struct TextDocument {
    text: String,
    encoding: TextEncoding,
    bom: bool,
    revision: u64,
    utf16_len: usize,
    hint: (usize, usize),
    syntax: Option<crate::syntax::SyntaxState>,
}

impl TextDocument {
    pub fn open(bytes: &[u8]) -> Result<Self, WorkspaceError> {
        if bytes.len() > MAX_TEXT_BYTES {
            return Err(error("text_too_large", "当前文本编辑上限为 8 MiB"));
        }
        if bytes.starts_with(b"%PDF-") || bytes.starts_with(b"PK\x03\x04") {
            return Err(error("binary_file", "此文件不是可编辑的纯文本"));
        }
        let (text, encoding, bom) = if bytes.starts_with(&[0xff, 0xfe, 0, 0])
            || bytes.starts_with(&[0, 0, 0xfe, 0xff])
        {
            return Err(error("unsupported_encoding", "暂不支持 UTF-32 文本"));
        } else if bytes.starts_with(&[0xff, 0xfe]) || bytes.starts_with(&[0xfe, 0xff]) {
            if !bytes.len().is_multiple_of(2) {
                return Err(error("invalid_encoding", "UTF-16 文件长度无效"));
            }
            let little = bytes[0] == 0xff;
            let units: Vec<u16> = bytes[2..]
                .chunks_exact(2)
                .map(|b| {
                    if little {
                        u16::from_le_bytes([b[0], b[1]])
                    } else {
                        u16::from_be_bytes([b[0], b[1]])
                    }
                })
                .collect();
            let text = String::from_utf16(&units)
                .map_err(|_| error("invalid_encoding", "UTF-16 文本包含无效字符"))?;
            (
                text,
                if little {
                    TextEncoding::Utf16Le
                } else {
                    TextEncoding::Utf16Be
                },
                true,
            )
        } else {
            let bom = bytes.starts_with(&[0xef, 0xbb, 0xbf]);
            let content = if bom { &bytes[3..] } else { bytes };
            let text = std::str::from_utf8(content)
                .map_err(|_| error("unsupported_encoding", "不是 UTF-8 或带 BOM 的 UTF-16 文本"))?
                .to_owned();
            (text, TextEncoding::Utf8, bom)
        };
        if text.contains('\0') {
            return Err(error("binary_file", "包含二进制数据，未进入编辑模式"));
        }
        if text.len() > MAX_TEXT_BYTES {
            return Err(error("text_too_large", "解码后的文本超过 8 MiB"));
        }
        let utf16_len = text.encode_utf16().count();
        Ok(Self {
            text,
            encoding,
            bom,
            revision: 0,
            utf16_len,
            hint: (0, 0),
            syntax: None,
        })
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn snapshot(&self) -> TextSnapshot<'_> {
        let crlf = self.text.matches("\r\n").count();
        let lf = self.text.bytes().filter(|b| *b == b'\n').count();
        let cr = self.text.bytes().filter(|b| *b == b'\r').count();
        let line_ending = if crlf > 0 && lf == crlf && cr == crlf {
            "CRLF"
        } else if cr > 0 && lf == 0 {
            "CR"
        } else if cr == 0 {
            "LF"
        } else {
            "Mixed"
        };
        TextSnapshot {
            text: &self.text,
            encoding: self.encoding,
            has_bom: self.bom,
            line_ending,
            byte_count: self.text.len(),
        }
    }

    pub fn replace(
        &mut self,
        expected: u64,
        start: usize,
        length: usize,
        replacement: &str,
    ) -> Result<(), WorkspaceError> {
        self.check_revision(expected)?;
        let end = start
            .checked_add(length)
            .ok_or_else(|| error("invalid_range", "编辑范围溢出"))?;
        let a = self.byte_index(start)?;
        let b = self.byte_index(end)?;
        let new_bytes = self.text.len() - (b - a) + replacement.len();
        let replacement_units = replacement.encode_utf16().count();
        let units = self.utf16_len - length + replacement_units;
        let encoded_bytes = match self.encoding {
            TextEncoding::Utf8 => new_bytes + usize::from(self.bom) * 3,
            _ => units * 2 + 2,
        };
        if new_bytes > MAX_TEXT_BYTES || encoded_bytes > MAX_TEXT_BYTES {
            return Err(error("text_too_large", "编辑结果超过当前 8 MiB 文本上限"));
        }
        if replacement.contains('\0') {
            return Err(error("binary_file", "纯文本编辑不接受空字符"));
        }
        let revision = self
            .revision
            .checked_add(1)
            .ok_or_else(|| error("revision_exhausted", "文档修订已达上限"))?;
        if let Some(syntax) = &mut self.syntax {
            syntax.edit(&self.text, a, b, replacement);
        }
        self.text.replace_range(a..b, replacement);
        self.utf16_len = units;
        self.hint = (start + replacement_units, a + replacement.len());
        self.revision = revision;
        Ok(())
    }

    fn byte_index(&self, position: usize) -> Result<usize, WorkspaceError> {
        let (mut units, byte) = if position >= self.hint.0 {
            self.hint
        } else {
            (0, 0)
        };
        for (offset, character) in self.text[byte..].char_indices() {
            if units == position {
                return Ok(byte + offset);
            }
            units += character.len_utf16();
            if units > position {
                break;
            }
        }
        if units == position && position == self.utf16_len {
            return Ok(self.text.len());
        }
        Err(error("invalid_range", "编辑范围越界或切分了 Unicode 字符"))
    }

    pub fn syntax(
        &mut self,
        expected: u64,
        path: &str,
        start: usize,
        end: usize,
    ) -> Result<crate::syntax::SyntaxSnapshot, WorkspaceError> {
        self.check_revision(expected)?;
        crate::syntax::snapshot(&mut self.syntax, &self.text, path, start, end)
    }

    pub fn bytes(&self, expected: u64) -> Result<Vec<u8>, WorkspaceError> {
        self.check_revision(expected)?;
        let mut bytes = Vec::new();
        match self.encoding {
            TextEncoding::Utf8 => {
                if self.bom {
                    bytes.extend_from_slice(&[0xef, 0xbb, 0xbf]);
                }
                bytes.extend_from_slice(self.text.as_bytes());
            }
            encoding => {
                let little = matches!(encoding, TextEncoding::Utf16Le);
                bytes.extend_from_slice(if little { &[0xff, 0xfe] } else { &[0xfe, 0xff] });
                for unit in self.text.encode_utf16() {
                    bytes.extend_from_slice(&if little {
                        unit.to_le_bytes()
                    } else {
                        unit.to_be_bytes()
                    });
                }
            }
        }
        Ok(bytes)
    }

    fn check_revision(&self, expected: u64) -> Result<(), WorkspaceError> {
        if expected == self.revision {
            Ok(())
        } else {
            Err(error(
                "stale_revision",
                "文档修订已变化，拒绝过期编辑或保存",
            ))
        }
    }
}

fn error(code: &'static str, message: &str) -> WorkspaceError {
    WorkspaceError::new(code, message)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unicode_edits_use_utf16_and_reject_split_surrogates_without_mutation() {
        let mut doc = TextDocument::open("a😀中\r\n".as_bytes()).unwrap();
        assert_eq!(doc.replace(0, 2, 1, "x").unwrap_err().code, "invalid_range");
        assert_eq!(doc.revision(), 0);
        doc.replace(0, 1, 2, "你好").unwrap();
        assert_eq!(doc.snapshot().text, "a你好中\r\n");
        assert_eq!(doc.snapshot().line_ending, "CRLF");
        doc.replace(1, 1, 2, "😀").unwrap();
        assert_eq!(doc.bytes(2).unwrap(), "a😀中\r\n".as_bytes());
    }
    #[test]
    fn original_encoding_bom_and_newlines_round_trip() {
        for bytes in [
            b"\xef\xbb\xbfhello\r\n".to_vec(),
            vec![0xff, 0xfe, 0x2d, 0x4e, 0x0a, 0],
            vec![0xfe, 0xff, 0x4e, 0x2d, 0, 0x0a],
            vec![],
        ] {
            let doc = TextDocument::open(&bytes).unwrap();
            assert_eq!(doc.bytes(0).unwrap(), bytes);
        }
    }
    #[test]
    fn binary_invalid_encoding_and_oversize_are_not_lossily_opened() {
        for bytes in [
            vec![0xff],
            vec![b'a', 0],
            b"%PDF-1.7".to_vec(),
            vec![0xff, 0xfe, 0],
        ] {
            assert!(TextDocument::open(&bytes).is_err());
        }
        assert!(TextDocument::open(&vec![b'a'; MAX_TEXT_BYTES + 1]).is_err());
    }
    #[test]
    fn revisions_protect_edits_and_exports_and_hint_handles_backward_edits() {
        let mut doc = TextDocument::open(b"abc").unwrap();
        doc.replace(0, 3, 0, "中").unwrap();
        assert!(doc.replace(0, 0, 0, "oops").is_err());
        assert!(doc.bytes(0).is_err());
        doc.replace(1, 0, 1, "😀").unwrap();
        assert_eq!(doc.snapshot().text, "😀bc中");
        doc.replace(2, 2, 3, "").unwrap();
        assert_eq!(doc.snapshot().text, "😀");
    }
}
