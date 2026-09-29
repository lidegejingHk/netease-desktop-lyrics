pub mod audio;
pub mod decoder;
pub mod process;
pub mod reader;
pub mod timeline;

use std::time::Instant;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RawPlayback {
    pub track_id: String,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct Snapshot {
    pub raw: RawPlayback,
    pub estimated_position_ms: u64,
    pub is_playing: bool,
    pub observed_at: Instant,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Diagnostic {
    NotRunning,
    NoSong,
    MissingDirectory,
    MissingField(&'static str),
    ProcessQueryFailed,
    ReadFailed,
    PermissionDenied,
    FormatChanged,
}

#[cfg(test)]
mod tests {
    use super::{Diagnostic, RawPlayback};

    #[test]
    fn raw_progress_is_not_inferred_from_a_diagnostic() {
        let observed = RawPlayback {
            track_id: "123".into(),
            position_ms: 1_250,
            duration_ms: Some(10_000),
        };
        assert_eq!(observed.position_ms, 1_250);
        assert_ne!(Diagnostic::MissingField("is_playing"), Diagnostic::NoSong);
    }
}
