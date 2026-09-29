//! Read-only lyric provider. Test fixtures never contain a real playback record.

use crate::lrc::TimedLyrics;
use serde::Deserialize;
use std::{
    io::Read,
    process::{Command, Stdio},
};

const MAX_RESPONSE_BYTES: usize = 256 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LyricsError {
    InvalidTrackId,
    Network,
    InvalidResponse,
    NoLyrics,
}

pub fn validate_track_id(id: &str) -> Result<&str, LyricsError> {
    if id.is_empty()
        || id.len() > 20
        || !id.bytes().all(|byte| byte.is_ascii_digit())
        || id.parse::<u64>().ok().filter(|value| *value > 0).is_none()
    {
        return Err(LyricsError::InvalidTrackId);
    }
    Ok(id)
}

#[derive(Deserialize)]
struct LyricSection {
    lyric: Option<String>,
}

#[derive(Deserialize)]
struct Response {
    code: i32,
    lrc: Option<LyricSection>,
    tlyric: Option<LyricSection>,
}

pub fn decode_response(body: &[u8]) -> Result<TimedLyrics, LyricsError> {
    if body.len() > MAX_RESPONSE_BYTES {
        return Err(LyricsError::InvalidResponse);
    }
    let response: Response =
        serde_json::from_slice(body).map_err(|_| LyricsError::InvalidResponse)?;
    if response.code != 200 {
        return Err(LyricsError::InvalidResponse);
    }
    let original = response
        .lrc
        .and_then(|section| section.lyric)
        .unwrap_or_default();
    let translation = response
        .tlyric
        .and_then(|section| section.lyric)
        .unwrap_or_default();
    let lyrics = TimedLyrics::new(&original, &translation);
    if lyrics.is_empty() {
        Err(LyricsError::NoLyrics)
    } else {
        Ok(lyrics)
    }
}

/// Only the last successful track is cached, in memory for this process lifetime.
#[derive(Default)]
pub struct LyricsProvider {
    cached: Option<(String, TimedLyrics)>,
}

impl LyricsProvider {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cached(&self, track_id: &str) -> Option<&TimedLyrics> {
        self.cached
            .as_ref()
            .and_then(|(id, lyrics)| (id == track_id).then_some(lyrics))
    }

    fn insert_response(
        &mut self,
        track_id: &str,
        body: &[u8],
    ) -> Result<&TimedLyrics, LyricsError> {
        validate_track_id(track_id)?;
        let lyrics = decode_response(body)?;
        self.cached = Some((track_id.to_owned(), lyrics));
        Ok(&self.cached.as_ref().expect("just cached").1)
    }

    pub fn fetch(&mut self, track_id: &str) -> Result<&TimedLyrics, LyricsError> {
        validate_track_id(track_id)?;
        if self.cached(track_id).is_none() {
            let response = request(track_id)?;
            self.insert_response(track_id, &response)?;
        }
        self.cached(track_id).ok_or(LyricsError::InvalidResponse)
    }
}

fn request(track_id: &str) -> Result<Vec<u8>, LyricsError> {
    // The ID is numeric-only. `curl` is the system binary, never a shell; it
    // receives only this ID and a fixed HTTPS endpoint, not local user data.
    let mut child = Command::new("/usr/bin/curl")
        .args([
            "--fail",
            "--silent",
            "--show-error",
            "--get",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--connect-timeout",
            "3",
            "--max-time",
            "8",
            "--max-filesize",
            "262144",
            "--data-urlencode",
        ])
        .arg(format!("id={track_id}"))
        .args([
            "--data-urlencode",
            "lv=-1",
            "--data-urlencode",
            "tv=-1",
            "https://music.163.com/api/song/lyric",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| LyricsError::Network)?;

    let mut result = Vec::new();
    let read = child
        .stdout
        .take()
        .ok_or(LyricsError::Network)?
        .take((MAX_RESPONSE_BYTES + 1) as u64)
        .read_to_end(&mut result);
    if read.is_err() || result.len() > MAX_RESPONSE_BYTES {
        let _ = child.kill();
        let _ = child.wait();
        return Err(if read.is_err() {
            LyricsError::Network
        } else {
            LyricsError::InvalidResponse
        });
    }
    let status = child.wait().map_err(|_| LyricsError::Network)?;
    if status.success() {
        Ok(result)
    } else {
        Err(LyricsError::Network)
    }
}

#[cfg(test)]
mod tests {
    use super::{decode_response, validate_track_id, LyricsError, LyricsProvider};

    #[test]
    fn track_id_is_decimal_and_bounded() {
        assert_eq!(validate_track_id("186016"), Ok("186016"));
        for id in [
            "",
            "1/../../etc",
            "a",
            "0&x=2",
            "1111111111111111111111111111111",
        ] {
            assert_eq!(validate_track_id(id), Err(LyricsError::InvalidTrackId));
        }
    }

    #[test]
    fn decode_valid_original_and_translation() {
        let payload =
            br#"{"code":200,"lrc":{"lyric":"[00:01.0]hello"},"tlyric":{"lyric":"[00:01.0]world"}}"#;
        let parsed = decode_response(payload).unwrap();
        assert_eq!(parsed.at(1_000).unwrap().current, "hello");
        assert_eq!(
            parsed.at(1_000).unwrap().translation.as_deref(),
            Some("world")
        );
    }

    #[test]
    fn no_timed_lyric_is_distinct_from_invalid_api() {
        assert!(matches!(
            decode_response(br#"{"code":200,"nolyric":true}"#),
            Err(LyricsError::NoLyrics)
        ));
        assert!(matches!(
            decode_response(br#"{"code":200,"lrc":{"lyric":"[ar:demo]"}}"#),
            Err(LyricsError::NoLyrics)
        ));
        assert!(matches!(
            decode_response(br#"{"code":403}"#),
            Err(LyricsError::InvalidResponse)
        ));
        assert!(matches!(
            decode_response(b"not json"),
            Err(LyricsError::InvalidResponse)
        ));
        assert!(matches!(
            decode_response(&vec![b'x'; 256 * 1024 + 1]),
            Err(LyricsError::InvalidResponse)
        ));
    }

    #[test]
    fn memory_cache_is_keyed_only_by_current_track() {
        let mut provider = LyricsProvider::new();
        let fixture = br#"{"code":200,"lrc":{"lyric":"[00:01]alpha"}}"#;
        let first = provider.insert_response("1", fixture).unwrap();
        assert_eq!(first.at(1_000).unwrap().current, "alpha");
        assert!(provider.cached("1").is_some());
        provider
            .insert_response("2", br#"{"code":200,"lrc":{"lyric":"[00:01]beta"}}"#)
            .unwrap();
        assert!(provider.cached("1").is_none());
        assert_eq!(
            provider.cached("2").unwrap().at(1_000).unwrap().current,
            "beta"
        );
    }
}
