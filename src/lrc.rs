//! Pure, timestamped LRC parsing and original/translation alignment.

const MAX_TEXT_BYTES: usize = 128 * 1024;
const MAX_ROWS: usize = 4_096;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TimedLine {
    pub time_ms: u64,
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActiveLine {
    pub current: String,
    pub translation: Option<String>,
    pub next: Option<String>,
    pub line_start_ms: u64,
    pub next_start_ms: Option<u64>,
}

#[derive(Clone, Debug, Default)]
pub struct TimedLyrics {
    lines: Vec<ActiveLine>,
}

impl TimedLyrics {
    pub fn new(original: &str, translated: &str) -> Self {
        let source = parse_lrc(original);
        let target = parse_lrc(translated);
        let mut lines = Vec::with_capacity(source.len());
        for (index, row) in source.iter().enumerate() {
            let translation = target
                .iter()
                .filter(|candidate| candidate.time_ms.abs_diff(row.time_ms) <= 250)
                .min_by_key(|candidate| candidate.time_ms.abs_diff(row.time_ms))
                .map(|candidate| candidate.text.clone());
            let next = source.get(index + 1);
            lines.push(ActiveLine {
                current: row.text.clone(),
                translation,
                next: next.map(|entry| entry.text.clone()),
                line_start_ms: row.time_ms,
                next_start_ms: next.map(|entry| entry.time_ms),
            });
        }
        Self { lines }
    }

    pub fn is_empty(&self) -> bool {
        self.lines.is_empty()
    }

    pub fn first(&self) -> Option<&ActiveLine> {
        self.lines.first()
    }

    pub fn at(&self, position_ms: u64) -> Option<&ActiveLine> {
        let index = self
            .lines
            .partition_point(|line| line.line_start_ms <= position_ms);
        if index == 0 {
            None
        } else {
            self.lines.get(index - 1)
        }
    }
}

fn timestamp(tag: &str) -> Option<u64> {
    let (minutes, seconds) = tag.split_once(':')?;
    if minutes.is_empty() || minutes.len() > 3 || !minutes.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    let (seconds, fraction) = match seconds.split_once('.') {
        Some((seconds, fraction))
            if (1..=3).contains(&fraction.len())
                && fraction.bytes().all(|byte| byte.is_ascii_digit()) =>
        {
            (seconds, Some(fraction))
        }
        None => (seconds, None),
        _ => return None,
    };
    if seconds.len() != 2 || !seconds.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let second = seconds.parse::<u64>().ok()?;
    if second >= 60 {
        return None;
    }
    let millis = fraction.map_or(Some(0), |fraction| {
        fraction
            .parse::<u64>()
            .ok()
            .map(|n| n * 10_u64.pow(3 - fraction.len() as u32))
    })?;
    minutes
        .parse::<u64>()
        .ok()?
        .checked_mul(60_000)?
        .checked_add(second * 1_000 + millis)
}

pub fn parse_lrc(text: &str) -> Vec<TimedLine> {
    if text.len() > MAX_TEXT_BYTES {
        return Vec::new();
    }
    let offset = text
        .lines()
        .filter_map(|line| {
            line.strip_prefix("[offset:")
                .and_then(|tail| tail.split_once(']'))
                .and_then(|(value, _)| value.parse::<i64>().ok())
        })
        .next_back()
        .unwrap_or(0);
    let mut rows = Vec::new();
    for line in text.lines().take(MAX_ROWS) {
        let mut rest = line;
        let mut stamps = Vec::new();
        while let Some(tail) = rest.strip_prefix('[') {
            let Some((tag, suffix)) = tail.split_once(']') else {
                break;
            };
            let Some(time) = timestamp(tag) else {
                break;
            };
            if stamps.len() >= 8 {
                break;
            }
            stamps.push(time);
            rest = suffix;
        }
        let words = rest.trim();
        if words.is_empty() || words.len() > 512 {
            continue;
        }
        for time in stamps {
            let adjusted = (time as i128 + offset as i128).clamp(0, u64::MAX as i128) as u64;
            rows.push(TimedLine {
                time_ms: adjusted,
                text: words.to_owned(),
            });
        }
    }
    rows.sort_by_key(|row| row.time_ms);
    rows.dedup_by(|a, b| a == b);
    rows.truncate(MAX_ROWS);
    rows
}

#[cfg(test)]
mod tests {
    use super::{parse_lrc, TimedLyrics};

    #[test]
    fn multiple_tags_and_fractional_precision() {
        let rows = parse_lrc("[00:01]once\n[00:02.4][00:03.45]twice\n[00:04.567]end");
        assert_eq!(
            rows.iter()
                .map(|r| (r.time_ms, r.text.as_str()))
                .collect::<Vec<_>>(),
            vec![
                (1_000, "once"),
                (2_400, "twice"),
                (3_450, "twice"),
                (4_567, "end")
            ]
        );
    }

    #[test]
    fn offset_metadata_and_unordered_duplicates() {
        let rows = parse_lrc("[ar:Synthetic]\n[ti:Demo]\n[offset:+250]\nplain\n[00:02.00]later\n[00:01.00]early\n[00:01.00]early");
        assert_eq!(
            rows.iter()
                .map(|r| (r.time_ms, r.text.as_str()))
                .collect::<Vec<_>>(),
            vec![(1_250, "early"), (2_250, "later")]
        );
        let negative = parse_lrc("[offset:-2000]\n[00:01.00]start");
        assert_eq!(negative[0].time_ms, 0);
    }

    #[test]
    fn lookup_handles_before_first_after_last_and_seek() {
        let lyrics = TimedLyrics::new(
            "[00:01.0]alpha\n[00:03.0]beta",
            "[00:01.1]甲\n[00:04.0]unpaired",
        );
        assert!(lyrics.at(999).is_none());
        let first = lyrics.at(1_150).unwrap();
        assert_eq!(
            (
                first.current.as_str(),
                first.translation.as_deref(),
                first.next.as_deref()
            ),
            ("alpha", Some("甲"), Some("beta"))
        );
        let last = lyrics.at(5_000).unwrap();
        assert_eq!(
            (
                last.current.as_str(),
                last.translation.as_deref(),
                last.next.as_deref()
            ),
            ("beta", None, None)
        );
        assert_eq!(lyrics.at(1_100).unwrap().current, "alpha");
    }

    #[test]
    fn malformed_input_is_bounded_and_not_a_lyric() {
        assert!(parse_lrc("[99:99.999999999999999999]bad\n[xx:01]bad").is_empty());
        assert!(parse_lrc("[00:02.00]  ").is_empty());
    }
}
