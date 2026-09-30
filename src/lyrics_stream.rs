//! Convert verified playback into bounded local JSON-line events for the UI.

use crate::{lrc::TimedLyrics, lyrics::LyricsError, Snapshot};
use serde::Serialize;

const RETRY_MS: u64 = 10_000;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Event {
    Loading,
    Intro {
        next: String,
        playing: bool,
        held_paused: bool,
        position_ms: u64,
        duration_ms: Option<u64>,
    },
    Line {
        text: String,
        translation: Option<String>,
        next: Option<String>,
        playing: bool,
        held_paused: bool,
        position_ms: u64,
        duration_ms: Option<u64>,
        line_start_ms: u64,
        next_start_ms: Option<u64>,
    },
    Unavailable {
        reason: String,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LoadRequest {
    pub track_id: String,
    pub epoch: u64,
}

#[derive(Default)]
pub struct LyricsSession {
    track_id: Option<String>,
    lyrics: Option<TimedLyrics>,
    error: Option<(String, u64)>,
    loading: bool,
    request_taken: bool,
    epoch: u64,
}

impl LyricsSession {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn observe(&mut self, snapshot: &Snapshot, now_ms: u64) -> Event {
        if self.track_id.as_deref() != Some(&snapshot.raw.track_id) {
            self.epoch = self.epoch.wrapping_add(1);
            self.track_id = Some(snapshot.raw.track_id.clone());
            self.lyrics = None;
            self.error = None;
            self.loading = true;
            self.request_taken = false;
        }
        if let Some(lyrics) = &self.lyrics {
            if let Some(line) = lyrics.at(snapshot.estimated_position_ms) {
                return Event::Line {
                    text: line.current.clone(),
                    translation: line.translation.clone(),
                    next: line.next.clone(),
                    playing: snapshot.is_playing,
                    held_paused: snapshot.held_paused,
                    position_ms: snapshot.estimated_position_ms,
                    // Whole-song progress comes from the same verified snapshot;
                    // a missing duration is reported as missing, never guessed.
                    duration_ms: snapshot.raw.duration_ms,
                    line_start_ms: line.line_start_ms,
                    next_start_ms: line.next_start_ms,
                };
            }
            return Event::Intro {
                next: lyrics
                    .first()
                    .map(|line| line.current.clone())
                    .unwrap_or_default(),
                playing: snapshot.is_playing,
                held_paused: snapshot.held_paused,
                position_ms: snapshot.estimated_position_ms,
                duration_ms: snapshot.raw.duration_ms,
            };
        }
        if let Some((reason, retry_at)) = &self.error {
            if now_ms < *retry_at {
                return Event::Unavailable {
                    reason: reason.clone(),
                };
            }
            self.error = None;
            self.loading = true;
            self.request_taken = false;
        }
        Event::Loading
    }

    /// Id and epoch stay in-process; the returned request must not go to UI JSON.
    pub fn take_request(&mut self) -> Option<LoadRequest> {
        if !self.loading || self.request_taken || self.error.is_some() || self.lyrics.is_some() {
            return None;
        }
        let track_id = self.track_id.clone()?;
        self.request_taken = true;
        Some(LoadRequest {
            track_id,
            epoch: self.epoch,
        })
    }

    pub fn receive(
        &mut self,
        request: &LoadRequest,
        result: Result<TimedLyrics, LyricsError>,
        now_ms: u64,
    ) -> bool {
        if self.epoch != request.epoch || self.track_id.as_deref() != Some(&request.track_id) {
            return false;
        }
        match result {
            Ok(lyrics) => {
                self.lyrics = Some(lyrics);
                self.error = None;
                self.loading = false;
            }
            Err(error) => {
                let (reason, retry) = match error {
                    LyricsError::InvalidTrackId => ("invalid_track_id", u64::MAX),
                    LyricsError::NoLyrics => ("no_lyrics", u64::MAX),
                    LyricsError::InvalidResponse => ("lyrics_invalid", RETRY_MS),
                    LyricsError::Network => ("network", RETRY_MS),
                };
                self.fail(
                    reason,
                    if retry == u64::MAX {
                        u64::MAX
                    } else {
                        now_ms.saturating_add(retry)
                    },
                );
            }
        }
        true
    }

    pub fn unavailable(&mut self, reason: &str) -> Event {
        if self.track_id.is_some() || self.lyrics.is_some() || self.loading {
            self.epoch = self.epoch.wrapping_add(1);
        }
        self.track_id = None;
        self.lyrics = None;
        self.error = None;
        self.loading = false;
        self.request_taken = false;
        Event::Unavailable {
            reason: reason.to_owned(),
        }
    }

    fn fail(&mut self, reason: &str, retry_at: u64) {
        self.lyrics = None;
        self.error = Some((reason.to_owned(), retry_at));
        self.loading = false;
        self.request_taken = false;
    }

    #[cfg(test)]
    fn install_response(
        &mut self,
        track_id: &str,
        payload: &[u8],
        now_ms: u64,
    ) -> Result<(), LyricsError> {
        let lyrics = crate::lyrics::decode_response(payload)?;
        let request = LoadRequest {
            track_id: track_id.to_owned(),
            epoch: self.epoch,
        };
        if self.receive(&request, Ok(lyrics), now_ms) {
            Ok(())
        } else {
            Err(LyricsError::InvalidTrackId)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{Event, LyricsSession};
    use crate::{RawPlayback, Snapshot};
    use std::time::Instant;

    fn snapshot(id: &str, ms: u64, playing: bool, held_paused: bool) -> Snapshot {
        Snapshot {
            raw: RawPlayback {
                track_id: id.into(),
                position_ms: ms,
                duration_ms: None,
            },
            estimated_position_ms: ms,
            is_playing: playing,
            held_paused,
            observed_at: Instant::now(),
        }
    }

    fn playing_with_duration(id: &str, ms: u64, duration_ms: Option<u64>) -> Snapshot {
        Snapshot {
            raw: RawPlayback {
                track_id: id.into(),
                position_ms: ms,
                duration_ms,
            },
            estimated_position_ms: ms,
            is_playing: true,
            held_paused: false,
            observed_at: Instant::now(),
        }
    }

    #[test]
    fn load_line_pause_seek_track_change_and_unavailable() {
        let mut session = LyricsSession::new();
        let a = snapshot("1", 1_100, true, false);
        assert!(matches!(session.observe(&a, 0), Event::Loading));
        session
            .install_response(
                "1",
                br#"{"code":200,"lrc":{"lyric":"[00:01]first\n[00:04]second"}}"#,
                1,
            )
            .unwrap();
        assert!(matches!(session.observe(&a, 2), Event::Line { text, .. } if text == "first"));
        assert!(matches!(
            session.observe(&snapshot("1", 1_100, false, true), 3),
            Event::Line { playing: false, .. }
        ));
        assert!(
            matches!(session.observe(&snapshot("1", 4_200, true, false), 4), Event::Line { text, .. } if text == "second")
        );
        assert!(matches!(
            session.observe(&snapshot("2", 0, true, false), 5),
            Event::Loading
        ));
        assert!(matches!(
            session.unavailable("no_song"),
            Event::Unavailable { .. }
        ));
        assert!(matches!(
            session.observe(&snapshot("2", 0, true, false), 6),
            Event::Loading
        ));
    }

    #[test]
    fn error_retries_at_bounded_interval_without_old_lyrics() {
        let mut session = LyricsSession::new();
        let a = snapshot("1", 1_100, true, false);
        assert!(matches!(session.observe(&a, 0), Event::Loading));
        session.fail("network", 10_000);
        assert!(
            matches!(session.observe(&a, 9_999), Event::Unavailable { reason } if reason == "network")
        );
        assert!(matches!(session.observe(&a, 10_000), Event::Loading));
    }

    #[test]
    fn events_carry_whole_song_progress_without_leaking_the_track_id() {
        let mut session = LyricsSession::new();
        let playing = playing_with_duration("4821969", 1_100, Some(215_000));
        assert!(matches!(session.observe(&playing, 0), Event::Loading));
        session
            .install_response(
                "4821969",
                br#"{"code":200,"lrc":{"lyric":"[00:01]first\n[00:04]second"}}"#,
                1,
            )
            .unwrap();
        let line = session.observe(&playing, 2);
        match &line {
            Event::Line {
                position_ms,
                duration_ms,
                ..
            } => {
                assert_eq!(*position_ms, 1_100);
                assert_eq!(*duration_ms, Some(215_000));
            }
            other => panic!("expected a synced line, got {other:?}"),
        }
        let json = serde_json::to_string(&line).unwrap();
        assert!(json.contains("\"position_ms\":1100"));
        assert!(json.contains("\"duration_ms\":215000"));
        assert!(!json.contains("4821969"));
        assert!(!json.contains("track_id"));

        let intro = session.observe(&playing_with_duration("4821969", 0, Some(215_000)), 3);
        match &intro {
            Event::Intro {
                position_ms,
                duration_ms,
                ..
            } => {
                assert_eq!(*position_ms, 0);
                assert_eq!(*duration_ms, Some(215_000));
            }
            other => panic!("expected an intro, got {other:?}"),
        }
        assert!(serde_json::to_string(&intro)
            .unwrap()
            .contains("\"position_ms\":0"));
    }

    #[test]
    fn unknown_duration_is_null_instead_of_a_fabricated_position() {
        let mut session = LyricsSession::new();
        let playing = playing_with_duration("4821969", 1_100, None);
        assert!(matches!(session.observe(&playing, 0), Event::Loading));
        session
            .install_response(
                "4821969",
                br#"{"code":200,"lrc":{"lyric":"[00:01]first"}}"#,
                1,
            )
            .unwrap();
        let line = session.observe(&playing, 2);
        match &line {
            Event::Line {
                position_ms,
                duration_ms,
                ..
            } => {
                assert_eq!(*position_ms, 1_100);
                assert_eq!(*duration_ms, None);
            }
            other => panic!("expected a synced line, got {other:?}"),
        }
        assert!(serde_json::to_string(&line)
            .unwrap()
            .contains("\"duration_ms\":null"));
    }

    #[test]
    fn json_never_sends_track_id_or_raw_playback() {
        let mut session = LyricsSession::new();
        let event = session.observe(&snapshot("secret-987654", 1234, true, false), 0);
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("loading"));
        assert!(!json.contains("secret"));
        assert!(!json.contains("track_id"));
    }
}
