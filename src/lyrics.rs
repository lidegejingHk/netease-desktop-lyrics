//! Read-only lyric provider. Test fixtures never contain a real playback record.

use crate::lrc::TimedLyrics;
use serde::Deserialize;
use std::{
    io::Read,
    process::{Command, Stdio},
};

const MAX_RESPONSE_BYTES: usize = 256 * 1024;

/// A song title is a separate, much smaller same-origin request.
pub const TITLE_MAX_RESPONSE_BYTES: usize = 64 * 1024;
/// One display line; longer names are cut here, never in the JSON stream.
pub const MAX_TITLE_CHARS: usize = 120;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LyricsError {
    InvalidTrackId,
    Network,
    InvalidResponse,
    NoLyrics,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TitleError {
    InvalidTrackId,
    Network,
    InvalidResponse,
    EmptyTitle,
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

enum FetchFailure {
    Network,
    TooLarge,
}

/// The single outbound path: the system `curl` binary, never a shell, HTTPS only,
/// a fixed endpoint and bounded time and size. Callers pass verified numeric IDs.
fn curl_bytes(
    query: &[(&str, String)],
    endpoint: &str,
    max_bytes: usize,
) -> Result<Vec<u8>, FetchFailure> {
    let mut command = Command::new("/usr/bin/curl");
    command.args([
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
        &max_bytes.to_string(),
    ]);
    for (key, value) in query {
        command.args(["--data-urlencode", &format!("{key}={value}")]);
    }
    command
        .arg(endpoint)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());

    let mut child = command.spawn().map_err(|_| FetchFailure::Network)?;
    let mut result = Vec::new();
    let read = child
        .stdout
        .take()
        .ok_or(FetchFailure::Network)?
        .take((max_bytes + 1) as u64)
        .read_to_end(&mut result);
    if read.is_err() {
        let _ = child.kill();
        let _ = child.wait();
        return Err(FetchFailure::Network);
    }
    if result.len() > max_bytes {
        let _ = child.kill();
        let _ = child.wait();
        return Err(FetchFailure::TooLarge);
    }
    let status = child.wait().map_err(|_| FetchFailure::Network)?;
    if status.success() {
        Ok(result)
    } else {
        Err(FetchFailure::Network)
    }
}

fn request(track_id: &str) -> Result<Vec<u8>, LyricsError> {
    let query = [
        ("id", track_id.to_owned()),
        ("lv", "-1".to_owned()),
        ("tv", "-1".to_owned()),
    ];
    curl_bytes(
        &query,
        "https://music.163.com/api/song/lyric",
        MAX_RESPONSE_BYTES,
    )
    .map_err(|failure| match failure {
        FetchFailure::Network => LyricsError::Network,
        FetchFailure::TooLarge => LyricsError::InvalidResponse,
    })
}

#[derive(Deserialize)]
struct DetailResponse {
    code: Option<i32>,
    songs: Option<Vec<DetailSong>>,
}

#[derive(Deserialize)]
struct DetailSong {
    id: u64,
    name: Option<String>,
}

/// Publish a title only for the exact song ID that was asked for, and only when it
/// is a real name: the local playback record never contains one.
pub fn decode_title_response(track_id: &str, body: &[u8]) -> Result<String, TitleError> {
    validate_track_id(track_id).map_err(|_| TitleError::InvalidTrackId)?;
    if body.len() > TITLE_MAX_RESPONSE_BYTES {
        return Err(TitleError::InvalidResponse);
    }
    let response: DetailResponse =
        serde_json::from_slice(body).map_err(|_| TitleError::InvalidResponse)?;
    if response.code != Some(200) {
        return Err(TitleError::InvalidResponse);
    }
    let mut songs = response.songs.unwrap_or_default();
    if songs.len() != 1 {
        return Err(TitleError::InvalidResponse);
    }
    let song = songs.remove(0);
    if song.id.to_string() != track_id {
        return Err(TitleError::InvalidResponse);
    }
    let name = song.name.unwrap_or_default();
    let name = name.trim();
    if name.is_empty() {
        return Err(TitleError::EmptyTitle);
    }
    Ok(name.chars().take(MAX_TITLE_CHARS).collect())
}

/// One title request for the current song; the session keeps the only copy.
pub fn fetch_title(track_id: &str) -> Result<String, TitleError> {
    let query = [("ids", format!("[{track_id}]"))];
    let body = curl_bytes(
        &query,
        "https://music.163.com/api/song/detail",
        TITLE_MAX_RESPONSE_BYTES,
    )
    .map_err(|failure| match failure {
        FetchFailure::Network => TitleError::Network,
        FetchFailure::TooLarge => TitleError::InvalidResponse,
    })?;
    decode_title_response(track_id, &body)
}

#[cfg(test)]
mod tests {
    use super::{
        decode_response, decode_title_response, validate_track_id, LyricsError, LyricsProvider,
        TitleError, MAX_TITLE_CHARS, TITLE_MAX_RESPONSE_BYTES,
    };

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
    fn title_decodes_one_verified_song_and_rejects_anything_else() {
        let payload = r#"{"songs":[{"name":"晴天","id":186016}],"code":200}"#;
        assert_eq!(
            decode_title_response("186016", payload.as_bytes()),
            Ok("晴天".to_owned())
        );

        for rejected in [
            r#"{"code":403}"#,
            r#"{"songs":[],"code":200}"#,
            r#"{"songs":[{"name":"a","id":1},{"name":"b","id":2}],"code":200}"#,
            r#"{"songs":[{"name":"另一首","id":1}],"code":200}"#,
            r#"{"songs":[{"name":"晴天","id":186016}]}"#,
        ] {
            assert_eq!(
                decode_title_response("186016", rejected.as_bytes()),
                Err(TitleError::InvalidResponse)
            );
        }
        assert_eq!(
            decode_title_response("186016", b"not json"),
            Err(TitleError::InvalidResponse)
        );
        for empty in [
            r#"{"songs":[{"name":"   ","id":186016}],"code":200}"#,
            r#"{"songs":[{"id":186016}],"code":200}"#,
        ] {
            assert_eq!(
                decode_title_response("186016", empty.as_bytes()),
                Err(TitleError::EmptyTitle)
            );
        }
        assert_eq!(
            decode_title_response("186016", &vec![b'x'; TITLE_MAX_RESPONSE_BYTES + 1]),
            Err(TitleError::InvalidResponse)
        );
        assert_eq!(
            decode_title_response("1/../../etc", payload.as_bytes()),
            Err(TitleError::InvalidTrackId)
        );
    }

    #[test]
    fn title_is_trimmed_and_bounded_to_one_display_line() {
        let long = format!(
            r#"{{"songs":[{{"name":"  {}  ","id":186016}}],"code":200}}"#,
            "很".repeat(400)
        );
        let title = decode_title_response("186016", long.as_bytes()).unwrap();
        assert_eq!(title, "很".repeat(MAX_TITLE_CHARS));
        let padded = r#"{"songs":[{"name":"  晴天  ","id":186016}],"code":200}"#;
        assert_eq!(
            decode_title_response("186016", padded.as_bytes()),
            Ok("晴天".to_owned())
        );
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
