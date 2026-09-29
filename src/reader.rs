use crate::{decoder, RawPlayback};
use std::{
    fs::{self, File},
    io::{self, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime},
};

#[derive(Debug)]
pub enum ReadError {
    MissingDirectory,
    MissingField(&'static str),
    PermissionDenied,
    FormatChanged,
    Io(io::Error),
}

pub struct Reader {
    dir: PathBuf,
    cached: Option<RawPlayback>,
    cached_at: Option<Instant>,
}
impl Reader {
    pub fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            cached: None,
            cached_at: None,
        }
    }
    pub fn reset(&mut self) {
        self.cached = None;
        self.cached_at = None;
    }

    pub fn read(&mut self) -> Result<Option<RawPlayback>, ReadError> {
        let entries = fs::read_dir(&self.dir).map_err(|error| classify(error, true))?;
        let mut logs = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|error| classify(error, false))?;
            let path = entry.path();
            if path.extension().is_none_or(|ext| ext != "log") {
                continue;
            }
            let metadata = match entry.metadata() {
                Ok(metadata) => metadata,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(classify(error, false)),
            };
            if metadata.is_file() {
                logs.push((metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH), path));
            }
        }
        logs.sort_by(|a, b| b.cmp(a));
        for (_, path) in logs {
            let bytes = match read_tail(&path) {
                Ok(bytes) => bytes,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(classify(error, false)),
            };
            let result = decoder::inspect(&bytes);
            if let Some(field) = result.missing_field {
                return Err(ReadError::MissingField(field));
            }
            if result.invalid_value {
                return Err(ReadError::FormatChanged);
            }
            if let Some(raw) = result.latest {
                self.cached = Some(raw.clone());
                self.cached_at = Some(Instant::now());
                return Ok(Some(raw));
            }
            if result.marker_found {
                if self
                    .cached_at
                    .is_some_and(|t| t.elapsed() <= Duration::from_secs(6))
                {
                    return Ok(self.cached.clone()); // 可能是轮转文件中的半写记录
                }
                return Err(ReadError::FormatChanged);
            }
        }
        if self
            .cached_at
            .is_some_and(|t| t.elapsed() <= Duration::from_secs(6))
        {
            return Ok(self.cached.clone());
        }
        self.reset();
        Ok(None)
    }
}

fn read_tail(path: &Path) -> io::Result<Vec<u8>> {
    let mut file = File::open(path)?;
    let len = file.metadata()?.len();
    file.seek(SeekFrom::Start(len.saturating_sub(128 * 1_024)))?;
    let mut bytes = Vec::new();
    file.take(128 * 1_024).read_to_end(&mut bytes)?;
    Ok(bytes)
}

fn classify(error: io::Error, directory: bool) -> ReadError {
    match error.kind() {
        io::ErrorKind::NotFound if directory => ReadError::MissingDirectory,
        io::ErrorKind::PermissionDenied => ReadError::PermissionDenied,
        _ => ReadError::Io(error),
    }
}

#[cfg(test)]
mod tests {
    use super::{ReadError, Reader};
    use crate::decoder::fixture;
    use std::fs;
    #[test]
    fn missing_directory_is_explicit() {
        let dir = tempfile::tempdir().unwrap();
        let mut reader = Reader::new(dir.path().join("missing"));
        assert!(matches!(reader.read(), Err(ReadError::MissingDirectory)));
    }
    #[test]
    fn last_log_record_wins_and_reset_drops_stale_track() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("000001.log");
        let mut log = fixture("10", 3.0);
        log.extend(fixture("11", 4.0));
        fs::write(&file, log).unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert_eq!(reader.read().unwrap().unwrap().track_id, "11");
        fs::rename(file, dir.path().join("old.bak")).unwrap();
        assert_eq!(reader.read().unwrap().unwrap().track_id, "11");
        reader.cached_at = Some(std::time::Instant::now() - std::time::Duration::from_secs(10));
        assert!(reader.read().unwrap().is_none());
        reader.reset();
        assert!(reader.read().unwrap().is_none());
    }
    #[test]
    fn undecodable_marker_is_format_change_not_no_song() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), b"lastPlaying\x00bad\x00").unwrap();
        assert!(matches!(
            Reader::new(dir.path().to_path_buf()).read(),
            Err(ReadError::FormatChanged)
        ));
    }
    #[test]
    fn missing_position_is_explicit() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            crate::decoder::fixture_json(serde_json::json!({"resourceId":"11"})),
        )
        .unwrap();
        assert!(matches!(
            Reader::new(dir.path().to_path_buf()).read(),
            Err(ReadError::MissingField("position_ms"))
        ));
    }
    #[test]
    fn newer_invalid_log_must_not_use_older_song() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), fixture("11", 1.0)).unwrap();
        fs::write(
            dir.path().join("2.log"),
            crate::decoder::fixture_json(serde_json::json!({"resourceId":"new","current":-1})),
        )
        .unwrap();
        assert!(matches!(
            Reader::new(dir.path().to_path_buf()).read(),
            Err(ReadError::FormatChanged)
        ));
    }
    #[test]
    fn fresh_newer_log_without_marker_may_use_older_log_with_valid_record() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), fixture("11", 1.0)).unwrap();
        fs::write(dir.path().join("2.log"), b"still rotating").unwrap();
        assert_eq!(
            Reader::new(dir.path().to_path_buf())
                .read()
                .unwrap()
                .unwrap()
                .track_id,
            "11"
        );
    }
}
