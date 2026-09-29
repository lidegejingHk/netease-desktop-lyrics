//! Combine a verified track observation and a read-only playback-state signal.

use crate::{
    accessibility::PlaybackState,
    reader::{ReadError, ReadObservation},
    timeline::Timeline,
    Diagnostic, RawPlayback,
};

#[derive(Clone, Debug)]
pub struct PlaybackUpdate {
    pub raw: RawPlayback,
    pub estimated_position_ms: u64,
    pub is_playing: bool,
    /// The track and position are held from a previous observation, not a current log entry.
    pub held_paused: bool,
}

#[derive(Default)]
pub struct PlaybackTracker {
    pid: Option<i32>,
    last_state: Option<PlaybackState>,
    last_good: Option<PlaybackUpdate>,
    timeline: Timeline,
    /// After an error or an expired playing record, don't accept old cache as new evidence.
    needs_fresh_record: bool,
}

impl PlaybackTracker {
    pub fn reset(&mut self) {
        self.pid = None;
        self.clear_track();
    }

    fn clear_track(&mut self) {
        self.last_state = None;
        self.last_good = None;
        self.timeline.reset();
        self.needs_fresh_record = true;
    }

    pub fn set_pid(&mut self, pid: i32) {
        if self.pid != Some(pid) {
            self.clear_track();
            self.pid = Some(pid);
        }
    }

    pub fn update(
        &mut self,
        state: PlaybackState,
        observed: Result<Option<ReadObservation>, ReadError>,
        now_ms: u64,
    ) -> Result<PlaybackUpdate, Diagnostic> {
        let observed = match observed {
            Ok(value) => value,
            Err(error) => {
                self.clear_track();
                return Err(match error {
                    ReadError::MissingDirectory => Diagnostic::MissingDirectory,
                    ReadError::MissingField(field) => Diagnostic::MissingField(field),
                    ReadError::PermissionDenied => Diagnostic::PermissionDenied,
                    ReadError::FormatChanged => Diagnostic::FormatChanged,
                    ReadError::Io(_) => Diagnostic::ReadFailed,
                });
            }
        };

        if state == PlaybackState::Playing {
            let transitioning = self.last_state == Some(PlaybackState::PausedOrIdle);
            let Some(observation) = observed else {
                self.clear_track();
                return Err(Diagnostic::NoSong);
            };
            if !observation.fresh && (transitioning || self.needs_fresh_record) {
                self.clear_track();
                return Err(Diagnostic::NoSong);
            }
            if transitioning {
                self.timeline.reset();
            }
            let raw = observation.raw;
            let position_ms = self
                .timeline
                .update(&raw.track_id, raw.position_ms, true, now_ms);
            let update = PlaybackUpdate {
                raw,
                estimated_position_ms: position_ms,
                is_playing: true,
                held_paused: false,
            };
            self.last_good = Some(update.clone());
            self.last_state = Some(state);
            self.needs_fresh_record = false;
            return Ok(update);
        }

        // Idle and paused have the same menu label. Only retain a track that this
        // tracker observed with a valid PID; never bootstrap from an old disk log.
        if let Some(observation) = observed.filter(|entry| entry.fresh) {
            let raw = observation.raw;
            let position_ms = self
                .timeline
                .update(&raw.track_id, raw.position_ms, false, now_ms);
            let update = PlaybackUpdate {
                raw,
                estimated_position_ms: position_ms,
                is_playing: false,
                held_paused: false,
            };
            self.last_good = Some(update.clone());
            self.last_state = Some(state);
            self.needs_fresh_record = false;
            return Ok(update);
        }
        let Some(previous) = self.last_good.as_ref() else {
            self.last_state = Some(state);
            return Err(Diagnostic::NoSong);
        };
        // Pass the last verified raw position to freeze the timeline. This is
        // intentionally NOT interpreted as a new observation.
        let position_ms = self.timeline.update(
            &previous.raw.track_id,
            previous.raw.position_ms,
            false,
            now_ms,
        );
        let update = PlaybackUpdate {
            raw: previous.raw.clone(),
            estimated_position_ms: position_ms,
            is_playing: false,
            held_paused: true,
        };
        self.last_good = Some(update.clone());
        self.last_state = Some(state);
        Ok(update)
    }
}

#[cfg(test)]
mod tests {
    use super::PlaybackTracker;
    use crate::{
        accessibility::PlaybackState::{PausedOrIdle, Playing},
        reader::{ReadError, ReadObservation},
        Diagnostic, RawPlayback,
    };

    fn observed(id: &str, position_ms: u64, fresh: bool) -> Option<ReadObservation> {
        Some(ReadObservation {
            raw: RawPlayback {
                track_id: id.to_owned(),
                position_ms,
                duration_ms: Some(180_000),
            },
            fresh,
        })
    }

    #[test]
    fn pausing_without_new_log_freezes_same_track_beyond_reader_timeout() {
        let mut tracker = PlaybackTracker::default();
        tracker.set_pid(12);
        let playing = tracker
            .update(Playing, Ok(observed("a", 10_000, true)), 0)
            .unwrap();
        assert_eq!(playing.estimated_position_ms, 10_000);
        assert!(!playing.held_paused);
        let paused = tracker
            .update(PausedOrIdle, Ok(observed("a", 10_000, false)), 500)
            .unwrap();
        assert_eq!(paused.estimated_position_ms, 10_000);
        assert!(paused.held_paused);
        let long_paused = tracker.update(PausedOrIdle, Ok(None), 15_000).unwrap();
        assert_eq!(long_paused.raw.track_id, "a");
        assert_eq!(
            long_paused.estimated_position_ms,
            paused.estimated_position_ms
        );
        assert!(long_paused.held_paused);
        assert!(!long_paused.is_playing);
    }

    #[test]
    fn resume_must_await_new_record_not_guess_from_old_paused_song() {
        let mut tracker = PlaybackTracker::default();
        tracker.set_pid(12);
        tracker
            .update(Playing, Ok(observed("a", 10_000, true)), 0)
            .unwrap();
        tracker.update(PausedOrIdle, Ok(None), 9_000).unwrap();
        assert_eq!(
            tracker.update(Playing, Ok(None), 10_000).unwrap_err(),
            Diagnostic::NoSong
        );
        assert_eq!(
            tracker
                .update(Playing, Ok(observed("a", 10_000, false)), 10_500)
                .unwrap_err(),
            Diagnostic::NoSong
        );
        let resumed = tracker
            .update(Playing, Ok(observed("a", 11_000, true)), 11_000)
            .unwrap();
        assert_eq!(resumed.estimated_position_ms, 11_000);
        assert!(!resumed.held_paused);
    }

    #[test]
    fn paused_cold_start_without_new_record_is_not_previous_session() {
        let mut tracker = PlaybackTracker::default();
        tracker.set_pid(12);
        assert_eq!(
            tracker.update(PausedOrIdle, Ok(None), 0).unwrap_err(),
            Diagnostic::NoSong
        );
        assert_eq!(
            tracker
                .update(PausedOrIdle, Ok(observed("a", 1_000, false)), 0)
                .unwrap_err(),
            Diagnostic::NoSong
        );
    }

    #[test]
    fn paused_fresh_position_and_track_change_are_applied() {
        let mut tracker = PlaybackTracker::default();
        tracker.set_pid(12);
        tracker
            .update(Playing, Ok(observed("a", 60_000, true)), 0)
            .unwrap();
        tracker.update(PausedOrIdle, Ok(None), 500).unwrap();
        let seek = tracker
            .update(PausedOrIdle, Ok(observed("a", 10_000, true)), 600)
            .unwrap();
        assert_eq!(seek.estimated_position_ms, 10_000);
        assert!(!seek.held_paused);
        let changed = tracker
            .update(PausedOrIdle, Ok(observed("b", 0, true)), 700)
            .unwrap();
        assert_eq!(changed.raw.track_id, "b");
        assert_eq!(changed.estimated_position_ms, 0);
    }

    #[test]
    fn pid_change_and_read_error_discard_held_song() {
        let mut tracker = PlaybackTracker::default();
        tracker.set_pid(12);
        tracker
            .update(Playing, Ok(observed("a", 10_000, true)), 0)
            .unwrap();
        tracker.update(PausedOrIdle, Ok(None), 1_000).unwrap();
        tracker.set_pid(13);
        assert_eq!(
            tracker.update(PausedOrIdle, Ok(None), 2_000).unwrap_err(),
            Diagnostic::NoSong
        );
        tracker
            .update(Playing, Ok(observed("b", 4_000, true)), 3_000)
            .unwrap();
        assert_eq!(
            tracker
                .update(PausedOrIdle, Err(ReadError::FormatChanged), 4_000)
                .unwrap_err(),
            Diagnostic::FormatChanged
        );
        assert_eq!(
            tracker.update(PausedOrIdle, Ok(None), 12_000).unwrap_err(),
            Diagnostic::NoSong
        );
    }

    #[test]
    fn stale_in_playback_does_not_restart_after_expiry_or_error() {
        let mut tracker = PlaybackTracker::default();
        tracker.set_pid(12);
        tracker
            .update(Playing, Ok(observed("a", 10_000, true)), 0)
            .unwrap();
        let next = tracker
            .update(Playing, Ok(observed("a", 10_000, false)), 500)
            .unwrap();
        assert_eq!(next.estimated_position_ms, 10_500);
        assert_eq!(
            tracker.update(Playing, Ok(None), 9_000).unwrap_err(),
            Diagnostic::NoSong
        );
        assert_eq!(
            tracker
                .update(Playing, Ok(observed("a", 10_000, false)), 10_000)
                .unwrap_err(),
            Diagnostic::NoSong
        );
    }
}
