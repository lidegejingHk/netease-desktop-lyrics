use netease_lyrics_rs::{
    audio, process,
    reader::{ReadError, Reader},
    timeline::Timeline,
    Diagnostic, Snapshot,
};
use std::{
    env,
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

fn parse(args: &[String]) -> Result<(u64, u64), String> {
    let (mut samples, mut interval) = (u64::MAX, 500);
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--once" => samples = 1,
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
    Ok((samples, interval))
}

fn sample(
    reader: &mut Reader,
    timeline: &mut Timeline,
    origin: Instant,
    active_pid: &mut Option<i32>,
) -> Result<Snapshot, Diagnostic> {
    let pids = process::discover().map_err(|_| Diagnostic::MissingField("process_list"))?;
    let Some(&pid) = pids.first() else {
        *active_pid = None;
        reader.reset();
        timeline.reset();
        return Err(Diagnostic::NotRunning);
    };
    if *active_pid != Some(pid) {
        *active_pid = Some(pid);
        reader.reset();
        timeline.reset();
    }
    let raw = match reader.read() {
        Ok(Some(raw)) => raw,
        Ok(None) => {
            timeline.reset();
            return Err(Diagnostic::NoSong);
        }
        Err(error) => {
            timeline.reset();
            return Err(match error {
                ReadError::MissingDirectory => Diagnostic::MissingDirectory,
                ReadError::MissingField(field) => Diagnostic::MissingField(field),
                ReadError::PermissionDenied => Diagnostic::PermissionDenied,
                ReadError::FormatChanged => Diagnostic::FormatChanged,
                ReadError::Io(_) => Diagnostic::MissingField("local_log_io"),
            });
        }
    };
    let Some(is_playing) = audio::is_running_output(&pids) else {
        timeline.reset();
        return Err(Diagnostic::MissingField("is_playing"));
    };
    let observed_at = Instant::now();
    let estimated_position_ms = timeline.update(
        &raw.track_id,
        raw.position_ms,
        is_playing,
        observed_at.duration_since(origin).as_millis() as u64,
    );
    Ok(Snapshot {
        raw,
        estimated_position_ms,
        is_playing,
        observed_at,
    })
}

fn main() {
    let (samples, interval) = match parse(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(values) => values,
        Err(error) => {
            eprintln!("{error}\nusage: netease-lyrics-rs [--once | --samples N] [--interval-ms N]");
            std::process::exit(2);
        }
    };
    let Some(home) = env::var_os("HOME") else {
        eprintln!("HOME is not set");
        std::process::exit(2);
    };
    let path = PathBuf::from(home).join("Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb");
    let mut reader = Reader::new(path);
    let mut timeline = Timeline::default();
    let mut active_pid = None;
    let origin = Instant::now();
    for index in 0..samples {
        match sample(&mut reader, &mut timeline, origin, &mut active_pid) {
            Ok(snapshot) => println!(
                "track={} raw_ms={} estimated_ms={} playing={} observed_t+{}ms",
                snapshot.raw.track_id,
                snapshot.raw.position_ms,
                snapshot.estimated_position_ms,
                snapshot.is_playing,
                snapshot.observed_at.duration_since(origin).as_millis()
            ),
            Err(diagnostic) => println!("unavailable: {diagnostic:?}"),
        }
        if index + 1 < samples {
            thread::sleep(Duration::from_millis(interval));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse;
    #[test]
    fn arguments_are_bounded() {
        assert_eq!(parse(&["--once".into()]).unwrap(), (1, 500));
        assert_eq!(
            parse(&[
                "--samples".into(),
                "4".into(),
                "--interval-ms".into(),
                "200".into()
            ])
            .unwrap(),
            (4, 200)
        );
        assert!(parse(&["--interval-ms".into(), "0".into()]).is_err());
    }
}
