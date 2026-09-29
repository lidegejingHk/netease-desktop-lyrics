use crate::RawPlayback;
use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyInit};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde::Deserialize;

const MARKER: &[u8] = b"lastPlaying";
const KEY: [u8; 16] = *b")(13daqP@ssw0rd~";

#[derive(Debug)]
pub struct Inspection {
    pub marker_found: bool,
    pub latest: Option<RawPlayback>,
    pub missing_field: Option<&'static str>,
    pub invalid_value: bool,
    pub undecodable_latest: bool,
}

enum Payload {
    Valid(RawPlayback),
    Missing(&'static str),
    Invalid,
}

#[derive(Deserialize)]
struct State {
    #[serde(rename = "resourceId", default)]
    resource_id: String,
    #[serde(rename = "trackId")]
    track_id: Option<String>,
    current: Option<f64>,
    #[serde(rename = "resourceDuration")]
    duration: Option<f64>,
}

fn decode(encoded: &[u8]) -> Option<Payload> {
    let mut encrypted = STANDARD.decode(encoded).ok()?;
    if encrypted.is_empty() || encrypted.len() % 16 != 0 {
        return None;
    }
    let plaintext = ecb::Decryptor::<aes::Aes128>::new(&KEY.into())
        .decrypt_padded_mut::<Pkcs7>(&mut encrypted)
        .ok()?;
    let state: State = serde_json::from_slice(plaintext).ok()?;
    let id = if state.resource_id.is_empty() {
        match state.track_id.filter(|value| !value.is_empty()) {
            Some(id) => id,
            None => return Some(Payload::Missing("track_id")),
        }
    } else {
        state.resource_id
    };
    let current = match state.current {
        Some(value) => value,
        None => return Some(Payload::Missing("position_ms")),
    };
    if !current.is_finite() || current < 0.0 || current > (u64::MAX as f64 / 1_000.0) {
        return Some(Payload::Invalid);
    }
    let duration_ms = state
        .duration
        .filter(|n| n.is_finite() && *n > 0.0 && *n <= (u64::MAX as f64 / 1_000.0))
        .map(|n| (n * 1_000.0).round() as u64);
    Some(Payload::Valid(RawPlayback {
        track_id: id,
        position_ms: (current * 1_000.0).round() as u64,
        duration_ms,
    }))
}

fn base64_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'=')
}

pub fn inspect(data: &[u8]) -> Inspection {
    let mut out = Inspection {
        marker_found: false,
        latest: None,
        missing_field: None,
        invalid_value: false,
        undecodable_latest: false,
    };
    for (at, bytes) in data.windows(MARKER.len()).enumerate() {
        if bytes != MARKER {
            continue;
        }
        out.marker_found = true;
        let mut found_payload = false;
        let start = at + MARKER.len();
        let end = data.len().min(start + 1_024);
        let mut cursor = start;
        while cursor < end {
            while cursor < end && !base64_byte(data[cursor]) {
                cursor += 1;
            }
            let run_start = cursor;
            while cursor < end && base64_byte(data[cursor]) {
                cursor += 1;
            }
            let run_end = cursor;
            // A single encrypted AES block is 16 bytes => 24 Base64 characters.
            if run_end.saturating_sub(run_start) < 24 {
                continue;
            }
            let max_prefix = 16.min(run_end - run_start - 24);
            let max_suffix = 16.min(run_end - run_start - 24);
            'candidates: for prefix in 0..=max_prefix {
                for suffix in 0..=max_suffix {
                    let part = &data[run_start + prefix..run_end - suffix];
                    if part.len() >= 24 && part.len().is_multiple_of(4) {
                        match decode(part) {
                            Some(Payload::Valid(state)) => {
                                out.latest = Some(state);
                                out.missing_field = None;
                                out.invalid_value = false;
                                found_payload = true;
                                break 'candidates;
                            }
                            Some(Payload::Missing(field)) => {
                                out.latest = None;
                                out.missing_field = Some(field);
                                out.invalid_value = false;
                                found_payload = true;
                                break 'candidates;
                            }
                            Some(Payload::Invalid) => {
                                out.latest = None;
                                out.missing_field = None;
                                out.invalid_value = true;
                                found_payload = true;
                                break 'candidates;
                            }
                            None => {}
                        }
                    }
                }
            }
        }
        out.undecodable_latest = !found_payload;
        if out.undecodable_latest {
            out.latest = None;
            out.missing_field = None;
            out.invalid_value = false;
        }
    }
    out
}

// Fixture 使用测试本地生成的密文，禁止读取真实用户播放记录。
#[cfg(test)]
pub(crate) fn fixture_json(json: serde_json::Value) -> Vec<u8> {
    use aes::cipher::{block_padding::Pkcs7, BlockEncryptMut, KeyInit};
    use base64::{engine::general_purpose::STANDARD, Engine};
    let ct = ecb::Encryptor::<aes::Aes128>::new(&KEY.into())
        .encrypt_padded_vec_mut::<Pkcs7>(json.to_string().as_bytes());
    let mut record = b"lastPlaying\x00\x01\x00".to_vec();
    record.extend_from_slice(STANDARD.encode(ct).as_bytes());
    record.push(0);
    record
}

#[cfg(test)]
pub(crate) fn fixture(id: &str, current: f64) -> Vec<u8> {
    fixture_json(serde_json::json!({"resourceId":id,"current":current,"resourceDuration":180.0}))
}

#[cfg(test)]
mod tests {
    use super::{fixture, fixture_json, inspect};
    #[test]
    fn latest_valid_record_wins() {
        let mut log = fixture("11", 1.25);
        log.extend(fixture("22", 2.5));
        let result = inspect(&log);
        assert!(result.marker_found);
        let raw = result.latest.unwrap();
        assert_eq!((raw.track_id.as_str(), raw.position_ms), ("22", 2_500));
        assert_eq!(raw.duration_ms, Some(180_000));
    }
    #[test]
    fn missing_required_fields_are_explicit() {
        assert_eq!(
            inspect(&fixture_json(serde_json::json!({"resourceId":"12"}))).missing_field,
            Some("position_ms")
        );
        assert_eq!(
            inspect(&fixture_json(serde_json::json!({"current":3.0}))).missing_field,
            Some("track_id")
        );
    }
    #[test]
    fn invalid_progress_is_not_a_snapshot() {
        let negative = inspect(&fixture_json(
            serde_json::json!({"resourceId":"12", "current":-1}),
        ));
        assert!(negative.latest.is_none());
        assert!(negative.invalid_value);
        assert!(inspect(&fixture_json(
            serde_json::json!({"resourceId":"12", "current":"NaN"})
        ))
        .latest
        .is_none());
    }
    #[test]
    fn invalid_record_is_distinct_from_missing_marker() {
        assert!(!inspect(b"nothing").marker_found);
        let bad = inspect(b"lastPlaying\x00not-base64\x00");
        assert!(bad.marker_found);
        assert!(bad.latest.is_none());
    }
    #[test]
    fn complete_undecodable_marker_blocks_old_song() {
        let mut log = fixture("11", 1.0);
        log.extend_from_slice(b"lastPlaying\x00not-base64\x00");
        let result = inspect(&log);
        assert!(result.latest.is_none());
        assert!(result.undecodable_latest);
    }
    #[test]
    fn missing_required_field_in_latest_record_blocks_old_song() {
        let mut log = fixture("11", 1.0);
        log.extend(fixture_json(serde_json::json!({"resourceId":"new"})));
        let result = inspect(&log);
        assert!(result.latest.is_none());
        assert_eq!(result.missing_field, Some("position_ms"));
    }
    #[test]
    fn invalid_complete_record_blocks_old_song() {
        let mut log = fixture("11", 1.0);
        log.extend(fixture_json(
            serde_json::json!({"resourceId":"new","current":-1}),
        ));
        let result = inspect(&log);
        assert!(result.latest.is_none());
        assert!(result.invalid_value);
    }
}
