use crate::{decoder, leveldb_log, RawPlayback};
use std::{
    fs::{self, File},
    io::{self, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime},
};

const MAX_TAIL_BYTES: u64 = 128 * 1_024;
const LOG_BLOCK_BYTES: u64 = 32 * 1_024;
const FRESHNESS: Duration = Duration::from_secs(6);

#[derive(Debug)]
pub enum ReadError {
    MissingDirectory,
    MissingField(&'static str),
    PermissionDenied,
    FormatChanged,
    Io(io::Error),
}

#[derive(PartialEq, Eq)]
struct RecordKey {
    path: PathBuf,
    end_offset: u64,
}

pub struct Reader {
    dir: PathBuf,
    cached: Option<RawPlayback>,
    cached_at: Option<Instant>,
    last_seen: Option<RecordKey>,
}

impl Reader {
    pub fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            cached: None,
            cached_at: None,
            last_seen: None,
        }
    }

    pub fn reset(&mut self) {
        self.cached = None;
        self.cached_at = None;
        self.last_seen = None;
    }

    fn recent_cache(&mut self) -> Option<RawPlayback> {
        if self.cached_at.is_some_and(|at| at.elapsed() <= FRESHNESS) {
            return self.cached.clone();
        }
        self.cached = None;
        self.cached_at = None;
        // Retain the record identity: an old disk record must not become fresh again.
        None
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
        let now = SystemTime::now();
        for (modified, path) in logs {
            let (bytes, start) = match read_tail(&path) {
                Ok(read) => read,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(classify(error, false)),
            };
            let parsed = leveldb_log::parse(&bytes, start).map_err(|_| ReadError::FormatChanged)?;
            // The latest complete record is the only evidence of current state.
            // Older records can have a recent file mtime due to unrelated writes.
            let Some(record) = parsed.records.last().filter(|_| !parsed.incomplete_tail) else {
                return Ok(self.recent_cache());
            };
            let result = decoder::inspect(&record.payload);
            if !result.marker_found {
                return Ok(self.recent_cache());
            }
            if let Some(field) = result.missing_field {
                return Err(ReadError::MissingField(field));
            }
            if result.invalid_value || result.undecodable_latest {
                return Err(ReadError::FormatChanged);
            }
            let raw = result.latest.ok_or(ReadError::FormatChanged)?;
            let key = RecordKey {
                path,
                end_offset: record.end_offset,
            };
            if self.last_seen.as_ref() == Some(&key) {
                return Ok(self.recent_cache());
            }
            self.last_seen = Some(key);
            if !fresh(modified, now) {
                self.cached = None;
                self.cached_at = None;
                return Ok(None);
            }
            self.cached = Some(raw.clone());
            self.cached_at = Some(Instant::now());
            return Ok(Some(raw));
        }
        Ok(self.recent_cache())
    }
}

fn fresh(modified: SystemTime, now: SystemTime) -> bool {
    now.duration_since(modified)
        .is_ok_and(|age| age <= FRESHNESS)
}

fn read_tail(path: &Path) -> io::Result<(Vec<u8>, u64)> {
    let mut file = File::open(path)?;
    let len = file.metadata()?.len();
    let minimum = len.saturating_sub(MAX_TAIL_BYTES);
    let start = minimum.div_ceil(LOG_BLOCK_BYTES) * LOG_BLOCK_BYTES;
    file.seek(SeekFrom::Start(start))?;
    let mut bytes = Vec::new();
    file.take(MAX_TAIL_BYTES).read_to_end(&mut bytes)?;
    Ok((bytes, start))
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
    use crate::{decoder::fixture, leveldb_log::fixture_record};
    use std::fs;
    #[test]
    fn missing_directory_is_explicit() {
        let dir = tempfile::tempdir().unwrap();
        let mut reader = Reader::new(dir.path().join("missing"));
        assert!(matches!(reader.read(), Err(ReadError::MissingDirectory)));
    }
    #[test]
    fn empty_directory_has_no_song() {
        let dir = tempfile::tempdir().unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert!(reader.read().unwrap().is_none());
    }
    #[test]
    fn inaccessible_directory_reports_permission_denied() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let original = fs::metadata(dir.path()).unwrap().permissions();
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o000)).unwrap();
        let result = Reader::new(dir.path().to_path_buf()).read();
        fs::set_permissions(dir.path(), original).unwrap();
        assert!(matches!(result, Err(ReadError::PermissionDenied)));
    }
    #[test]
    fn last_log_record_wins_and_reset_drops_stale_track() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("000001.log");
        let mut log = fixture_record(1, &fixture("10", 3.0));
        log.extend(fixture_record(1, &fixture("11", 4.0)));
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
    fn unchanged_log_does_not_extend_its_six_second_freshness() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, &fixture("old", 1.0)),
        )
        .unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert_eq!(reader.read().unwrap().unwrap().track_id, "old");
        reader.cached_at = Some(std::time::Instant::now() - std::time::Duration::from_secs(10));
        assert!(reader.read().unwrap().is_none());
    }

    #[test]
    fn newer_log_without_song_does_not_replay_old_song_forever() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, &fixture("old", 1.0)),
        )
        .unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert_eq!(reader.read().unwrap().unwrap().track_id, "old");
        fs::write(
            dir.path().join("2.log"),
            fixture_record(1, b"unrelated-key"),
        )
        .unwrap();
        assert_eq!(reader.read().unwrap().unwrap().track_id, "old");
        reader.cached_at = Some(std::time::Instant::now() - std::time::Duration::from_secs(10));
        assert!(reader.read().unwrap().is_none());
    }

    #[test]
    fn cold_start_does_not_trust_older_record_after_unrelated_write() {
        let dir = tempfile::tempdir().unwrap();
        let mut log = fixture_record(1, &fixture("old", 1.0));
        log.extend(fixture_record(1, b"unrelated-key"));
        fs::write(dir.path().join("1.log"), log).unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert!(reader.read().unwrap().is_none());
    }

    #[test]
    fn hot_cache_is_not_refreshed_by_unrelated_writes() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("1.log");
        fs::write(&path, fixture_record(1, &fixture("old", 1.0))).unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert_eq!(reader.read().unwrap().unwrap().track_id, "old");
        let mut log = fs::read(&path).unwrap();
        log.extend(fixture_record(1, b"unrelated-key"));
        fs::write(&path, log).unwrap();
        reader.cached_at = Some(std::time::Instant::now() - std::time::Duration::from_secs(10));
        assert!(reader.read().unwrap().is_none());
    }

    #[test]
    fn complete_newer_record_with_undecodable_value_is_format_change() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, &fixture("old", 1.0)),
        )
        .unwrap();
        fs::write(
            dir.path().join("2.log"),
            fixture_record(1, b"lastPlaying\x00not-base64\x00"),
        )
        .unwrap();
        assert!(matches!(
            Reader::new(dir.path().to_path_buf()).read(),
            Err(ReadError::FormatChanged)
        ));
    }

    #[test]
    fn undecodable_marker_is_format_change_not_no_song() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, b"lastPlaying\x00bad\x00"),
        )
        .unwrap();
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
            fixture_record(
                1,
                &crate::decoder::fixture_json(serde_json::json!({"resourceId":"11"})),
            ),
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
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, &fixture("11", 1.0)),
        )
        .unwrap();
        fs::write(
            dir.path().join("2.log"),
            fixture_record(
                1,
                &crate::decoder::fixture_json(serde_json::json!({"resourceId":"new","current":-1})),
            ),
        )
        .unwrap();
        assert!(matches!(
            Reader::new(dir.path().to_path_buf()).read(),
            Err(ReadError::FormatChanged)
        ));
    }
    #[test]
    fn corrupted_complete_record_must_not_replay_older_song() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, &fixture("old", 1.0)),
        )
        .unwrap();
        let mut damaged = fixture_record(1, &fixture("new", 2.0));
        damaged[7] ^= 1;
        fs::write(dir.path().join("2.log"), damaged).unwrap();
        assert!(matches!(
            Reader::new(dir.path().to_path_buf()).read(),
            Err(ReadError::FormatChanged)
        ));
    }

    #[test]
    fn incomplete_tail_does_not_replay_old_song_on_cold_start() {
        let dir = tempfile::tempdir().unwrap();
        let mut log = fixture_record(1, &fixture("old", 1.0));
        log.extend_from_slice(&fixture_record(1, &fixture("new", 2.0))[..20]);
        fs::write(dir.path().join("1.log"), log).unwrap();
        assert!(Reader::new(dir.path().to_path_buf())
            .read()
            .unwrap()
            .is_none());
    }

    #[test]
    fn same_log_new_record_becomes_available_after_unrelated_write() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("1.log");
        fs::write(&path, fixture_record(1, b"unrelated-key")).unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert!(reader.read().unwrap().is_none());
        let mut log = fs::read(&path).unwrap();
        log.extend(fixture_record(1, &fixture("new", 2.0)));
        fs::write(&path, log).unwrap();
        assert_eq!(reader.read().unwrap().unwrap().track_id, "new");
    }

    #[test]
    fn incomplete_new_record_uses_recent_verified_cache_only() {
        let dir = tempfile::tempdir().unwrap();
        let old = dir.path().join("1.log");
        fs::write(&old, fixture_record(1, &fixture("old", 1.0))).unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert_eq!(reader.read().unwrap().unwrap().track_id, "old");
        let incomplete = fixture_record(1, &fixture("new", 2.0));
        fs::write(dir.path().join("2.log"), &incomplete[..20]).unwrap();
        assert_eq!(reader.read().unwrap().unwrap().track_id, "old");
        reader.cached_at = Some(std::time::Instant::now() - std::time::Duration::from_secs(10));
        assert!(reader.read().unwrap().is_none());
    }

    #[test]
    fn cold_start_does_not_bootstrap_from_previous_log() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("1.log"),
            fixture_record(1, &fixture("11", 1.0)),
        )
        .unwrap();
        fs::write(
            dir.path().join("2.log"),
            fixture_record(1, b"unrelated-key"),
        )
        .unwrap();
        assert!(Reader::new(dir.path().to_path_buf())
            .read()
            .unwrap()
            .is_none());
    }
}
