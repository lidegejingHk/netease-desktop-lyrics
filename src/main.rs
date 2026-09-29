use netease_lyrics_rs::{
    accessibility::{self, AxError},
    lyrics::{validate_track_id, LyricsError, LyricsProvider},
    lyrics_stream::{Event, LoadRequest, LyricsSession},
    playback::PlaybackTracker,
    process,
    reader::Reader,
    Diagnostic, Snapshot,
};
use std::{
    env,
    io::{self, Write},
    path::PathBuf,
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant},
};

fn parse(args: &[String]) -> Result<(u64, u64, bool), String> {
    let (mut samples, mut interval, mut lyrics_json) = (u64::MAX, 500, false);
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--once" => samples = 1,
            "--lyrics-json" => lyrics_json = true,
            "--samples" | "--interval-ms" => {
                let flag = &args[i];
                i += 1;
                let value = args
                    .get(i)
                    .ok_or_else(|| format!("missing value for {flag}"))?
                    .parse::<u64>()
                    .map_err(|_| format!("invalid value for {flag}"))?;
                if value == 0 {
                    return Err(format!("{flag} must be positive"));
                }
                if flag == "--samples" {
                    samples = value;
                } else {
                    interval = value;
                }
            }
            flag => return Err(format!("unknown option: {flag}")),
        }
        i += 1;
    }
    Ok((samples, interval, lyrics_json))
}

fn on_process_discovery_error(
    reader: &mut Reader,
    tracker: &mut PlaybackTracker,
    active_pid: &mut Option<i32>,
) -> Diagnostic {
    *active_pid = None;
    reader.reset();
    tracker.reset();
    Diagnostic::ProcessQueryFailed
}

fn ax_diagnostic(error: AxError) -> Diagnostic {
    match error {
        AxError::PermissionDenied => Diagnostic::AccessibilityPermissionDenied,
        AxError::Unavailable => Diagnostic::MissingField("is_playing"),
    }
}

fn sample(
    reader: &mut Reader,
    tracker: &mut PlaybackTracker,
    origin: Instant,
    active_pid: &mut Option<i32>,
) -> Result<Snapshot, Diagnostic> {
    let pids =
        process::discover().map_err(|_| on_process_discovery_error(reader, tracker, active_pid))?;
    let Some(&pid) = pids.first() else {
        *active_pid = None;
        reader.reset();
        tracker.reset();
        return Err(Diagnostic::NotRunning);
    };
    if *active_pid != Some(pid) {
        *active_pid = Some(pid);
        reader.reset();
        tracker.set_pid(pid);
    }
    let state = accessibility::playback_state(pid).map_err(|error| {
        tracker.reset();
        ax_diagnostic(error)
    })?;
    let observed = reader.read_observation();
    let observed_at = Instant::now();
    let update = tracker.update(
        state,
        observed,
        observed_at.duration_since(origin).as_millis() as u64,
    )?;
    Ok(Snapshot {
        raw: update.raw,
        estimated_position_ms: update.estimated_position_ms,
        is_playing: update.is_playing,
        held_paused: update.held_paused,
        observed_at,
    })
}

fn format_snapshot(snapshot: &Snapshot, origin: Instant) -> String {
    format!(
        "track={} raw_ms={} estimated_ms={} playing={} held_paused={} observed_t+{}ms",
        snapshot.raw.track_id,
        snapshot.raw.position_ms,
        snapshot.estimated_position_ms,
        snapshot.is_playing,
        snapshot.held_paused,
        snapshot.observed_at.duration_since(origin).as_millis()
    )
}

fn report_event(event: &Event) {
    if let Ok(json) = serde_json::to_string(event) {
        println!("{json}");
        let _ = io::stdout().flush();
    }
}

fn diagnostic_reason(error: &Diagnostic) -> &'static str {
    match error {
        Diagnostic::NotRunning => "not_running",
        Diagnostic::NoSong => "no_song",
        Diagnostic::AccessibilityPermissionDenied => "accessibility_permission_denied",
        Diagnostic::PermissionDenied => "permission_denied",
        Diagnostic::MissingDirectory => "missing_directory",
        Diagnostic::MissingField(_) => "missing_field",
        Diagnostic::ProcessQueryFailed => "process_query_failed",
        Diagnostic::ReadFailed => "read_failed",
        Diagnostic::FormatChanged => "format_changed",
    }
}

type LyricsResult = (
    LoadRequest,
    Result<netease_lyrics_rs::lrc::TimedLyrics, LyricsError>,
);

fn take_completed(session: &mut LyricsSession, receiver: &Receiver<LyricsResult>, now_ms: u64) {
    while let Ok((request, result)) = receiver.try_recv() {
        session.receive(&request, result, now_ms);
    }
}

fn start_request(request: LoadRequest, sender: Sender<LyricsResult>) {
    thread::spawn(move || {
        let result = if let Err(error) = validate_track_id(&request.track_id) {
            Err(error)
        } else {
            let mut provider = LyricsProvider::new();
            provider.fetch(&request.track_id).cloned()
        };
        let _ = sender.send((request, result));
    });
}

fn stream(
    reader: &mut Reader,
    tracker: &mut PlaybackTracker,
    active_pid: &mut Option<i32>,
    origin: Instant,
    samples: u64,
    interval: u64,
) {
    let mut session = LyricsSession::new();
    let (sender, receiver) = mpsc::channel();
    for index in 0..samples {
        let snapshot = sample(reader, tracker, origin, active_pid);
        let now_ms = origin.elapsed().as_millis() as u64;
        match snapshot {
            Ok(snapshot) => {
                take_completed(&mut session, &receiver, now_ms);
                let event = session.observe(&snapshot, now_ms);
                report_event(&event);
                if let Some(request) = session.take_request() {
                    start_request(request, sender.clone());
                }
            }
            Err(diagnostic) => {
                take_completed(&mut session, &receiver, now_ms);
                report_event(&session.unavailable(diagnostic_reason(&diagnostic)));
            }
        }
        if index + 1 < samples {
            thread::sleep(Duration::from_millis(interval));
        }
    }
}

fn main() {
    let (samples, interval, lyrics_json) = match parse(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(values) => values,
        Err(error) => {
            eprintln!("{error}\nusage: netease-lyrics-rs [--once | --samples N] [--interval-ms N] [--lyrics-json]");
            std::process::exit(2);
        }
    };
    let Some(home) = env::var_os("HOME") else {
        eprintln!("HOME is not set");
        std::process::exit(2);
    };
    let path = PathBuf::from(home).join("Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb");
    let mut reader = Reader::new(path);
    let mut tracker = PlaybackTracker::default();
    let mut active_pid = None;
    let origin = Instant::now();
    if lyrics_json {
        stream(
            &mut reader,
            &mut tracker,
            &mut active_pid,
            origin,
            samples,
            interval,
        );
        return;
    }
    for index in 0..samples {
        match sample(&mut reader, &mut tracker, origin, &mut active_pid) {
            Ok(snapshot) => println!("{}", format_snapshot(&snapshot, origin)),
            Err(diagnostic) => println!("unavailable: {diagnostic:?}"),
        }
        if index + 1 < samples {
            thread::sleep(Duration::from_millis(interval));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{on_process_discovery_error, parse};
    use netease_lyrics_rs::{playback::PlaybackTracker, reader::Reader, Diagnostic};
    use std::path::PathBuf;
    #[test]
    fn arguments_are_bounded() {
        assert_eq!(parse(&["--once".into()]).unwrap(), (1, 500, false));
        assert_eq!(
            parse(&[
                "--samples".into(),
                "4".into(),
                "--interval-ms".into(),
                "200".into()
            ])
            .unwrap(),
            (4, 200, false)
        );
        assert!(parse(&["--interval-ms".into(), "0".into()]).is_err());
        assert_eq!(
            parse(&["--once".into(), "--lyrics-json".into()]).unwrap(),
            (1, 500, true)
        );
    }

    #[test]
    fn ax_permission_is_not_a_generic_read_error() {
        assert_eq!(
            super::ax_diagnostic(netease_lyrics_rs::accessibility::AxError::PermissionDenied),
            Diagnostic::AccessibilityPermissionDenied
        );
        assert_eq!(
            super::ax_diagnostic(netease_lyrics_rs::accessibility::AxError::Unavailable),
            Diagnostic::MissingField("is_playing")
        );
    }

    #[test]
    fn paused_line_discloses_held_observation() {
        let snapshot = netease_lyrics_rs::Snapshot {
            raw: netease_lyrics_rs::RawPlayback {
                track_id: "fixture-id".into(),
                position_ms: 1_000,
                duration_ms: None,
            },
            estimated_position_ms: 1_000,
            is_playing: false,
            held_paused: true,
            observed_at: std::time::Instant::now(),
        };
        let line = super::format_snapshot(&snapshot, snapshot.observed_at);
        assert!(line.contains("playing=false"));
        assert!(line.contains("held_paused=true"));
    }

    #[test]
    fn process_query_failure_resets_old_timeline_and_pid() {
        let mut reader = Reader::new(PathBuf::from("unused"));
        let mut tracker = PlaybackTracker::default();
        let mut active_pid = Some(42);
        tracker.set_pid(42);
        tracker
            .update(
                netease_lyrics_rs::accessibility::PlaybackState::Playing,
                Ok(Some(netease_lyrics_rs::reader::ReadObservation {
                    raw: netease_lyrics_rs::RawPlayback {
                        track_id: "a".into(),
                        position_ms: 1_000,
                        duration_ms: None,
                    },
                    fresh: true,
                })),
                0,
            )
            .unwrap();
        assert_eq!(
            on_process_discovery_error(&mut reader, &mut tracker, &mut active_pid),
            Diagnostic::ProcessQueryFailed
        );
        assert_eq!(active_pid, None);
        assert_eq!(
            tracker
                .update(
                    netease_lyrics_rs::accessibility::PlaybackState::PausedOrIdle,
                    Ok(None),
                    5_000,
                )
                .unwrap_err(),
            Diagnostic::NoSong
        );
    }
}
