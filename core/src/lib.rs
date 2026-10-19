//! hc_core：与界面无关的核心处理层（压缩包、格式解析、编码处理等）。
//! 通过 UniFFI 以 proc-macro 方式导出，Swift 侧绑定由 scripts/build-core.sh 生成。

use std::fs::File;
use std::sync::Mutex;
use zip::ZipArchive;

uniffi::setup_scaffolding!();

/// 压缩包内单个条目的信息。
#[derive(uniffi::Record, Debug, Clone)]
pub struct ArchiveEntry {
    pub name: String,
    pub size: u64,
    pub compressed_size: u64,
    pub is_dir: bool,
}

#[derive(uniffi::Error, Debug)]
pub enum CoreError {
    OpenFailed { path: String, reason: String },
    ReadFailed { reason: String },
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreError::OpenFailed { path, reason } => {
                write!(f, "无法打开 {path}: {reason}")
            }
            CoreError::ReadFailed { reason } => write!(f, "读取失败: {reason}"),
        }
    }
}

impl std::error::Error for CoreError {}

/// 按需读取压缩包的目录结构。骨架阶段仅实现列目录，后续在此扩展按需提取等能力。
#[derive(uniffi::Object)]
pub struct ZipReader {
    archive: Mutex<ZipArchive<File>>,
}

#[uniffi::export]
impl ZipReader {
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<Self, CoreError> {
        let file = File::open(&path)
            .map_err(|e| CoreError::OpenFailed { path: path.clone(), reason: e.to_string() })?;
        let archive = ZipArchive::new(file)
            .map_err(|e| CoreError::OpenFailed { path, reason: e.to_string() })?;
        Ok(Self { archive: Mutex::new(archive) })
    }

    pub fn entry_count(&self) -> u32 {
        self.archive.lock().unwrap().len() as u32
    }

    /// 列出全部条目。by_index_raw 不做解压，目录浏览保持轻量。
    pub fn entries(&self) -> Vec<ArchiveEntry> {
        let mut archive = self.archive.lock().unwrap();
        let mut result = Vec::with_capacity(archive.len());
        for i in 0..archive.len() {
            if let Ok(entry) = archive.by_index_raw(i) {
                // zip 9 的 name() 返回 Result：文件名解码失败时保留原字节串，不让单条坏名拖垮整个目录列表。
                let name = entry.name().map(|n| n.into_owned()).unwrap_or_default();
                result.push(ArchiveEntry {
                    name,
                    size: entry.size(),
                    compressed_size: entry.compressed_size(),
                    is_dir: entry.is_dir(),
                });
            }
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use zip::write::SimpleFileOptions;

    fn write_sample_zip(path: &std::path::Path) {
        let file = File::create(path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default();
        zip.start_file("hello.txt", options).unwrap();
        zip.write_all(b"hello").unwrap();
        zip.start_file("中文名.txt", options).unwrap();
        zip.write_all(b"utf-8 name").unwrap();
        zip.add_directory("sub", options).unwrap();
        zip.start_file("sub/nested.txt", options).unwrap();
        zip.write_all(b"nested").unwrap();
        zip.finish().unwrap();
    }

    #[test]
    fn lists_entries_with_utf8_names() {
        let dir = std::env::temp_dir().join("hc_core_test_sample.zip");
        write_sample_zip(&dir);

        let reader = ZipReader::open(dir.to_string_lossy().into_owned()).unwrap();
        assert_eq!(reader.entry_count(), 4);

        let entries = reader.entries();
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"hello.txt"));
        assert!(names.contains(&"中文名.txt"));
        assert!(names.contains(&"sub/nested.txt"));
        assert!(entries.iter().find(|e| e.name == "sub/").unwrap().is_dir);
        assert_eq!(
            entries.iter().find(|e| e.name == "hello.txt").unwrap().size,
            5
        );

        std::fs::remove_file(&dir).ok();
    }
}
