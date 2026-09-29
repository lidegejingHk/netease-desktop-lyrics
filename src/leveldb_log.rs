//! Parse complete, checksum-verified LevelDB physical log records.

const BLOCK_SIZE: usize = 32_768;
const HEADER_SIZE: usize = 7;
const MASK_DELTA: u32 = 0xa282_ead8;

#[derive(Debug, PartialEq, Eq)]
pub enum LogError {
    Corrupt,
}

#[derive(Debug)]
pub struct Record {
    pub payload: Vec<u8>,
    pub end_offset: u64,
}

#[derive(Debug)]
pub struct ParsedLog {
    pub records: Vec<Record>,
    pub incomplete_tail: bool,
}

/// `start_offset` is the absolute file offset of the first supplied byte.
pub fn parse(bytes: &[u8], start_offset: u64) -> Result<ParsedLog, LogError> {
    if !start_offset.is_multiple_of(BLOCK_SIZE as u64) {
        return Err(LogError::Corrupt);
    }
    let mut parsed = ParsedLog {
        records: Vec::new(),
        incomplete_tail: false,
    };
    let mut cursor = 0;
    let mut fragments: Option<Vec<u8>> = None;
    let mut skip_orphaned = start_offset > 0;
    while cursor < bytes.len() {
        let within_block = cursor % BLOCK_SIZE;
        let block_left = BLOCK_SIZE - within_block;
        if block_left < HEADER_SIZE {
            let trailer_end = bytes.len().min(cursor + block_left);
            if bytes[cursor..trailer_end].iter().any(|&byte| byte != 0) {
                return Err(LogError::Corrupt);
            }
            cursor = trailer_end;
            continue;
        }
        if bytes.len() - cursor < HEADER_SIZE {
            parsed.incomplete_tail = true;
            break;
        }
        let header = &bytes[cursor..cursor + HEADER_SIZE];
        let length = u16::from_le_bytes([header[4], header[5]]) as usize;
        let kind = header[6];
        let end = cursor + HEADER_SIZE + length;
        if kind == 0 && length == 0 && header[..4] == [0; 4] {
            // LevelDB's mmap writer can preallocate the rest of a block.
            let zero_end = bytes.len().min(cursor + block_left);
            if bytes[cursor..zero_end].iter().any(|&byte| byte != 0) {
                return Err(LogError::Corrupt);
            }
            cursor = zero_end;
            continue;
        }
        if end > cursor + block_left {
            return Err(LogError::Corrupt);
        }
        if end > bytes.len() {
            parsed.incomplete_tail = true;
            break;
        }
        if !(1..=4).contains(&kind) {
            return Err(LogError::Corrupt);
        }
        let payload = &bytes[cursor + HEADER_SIZE..end];
        let expected = u32::from_le_bytes(header[..4].try_into().expect("checksum header"));
        let actual = crc32c::crc32c_append(crc32c::crc32c(&[kind]), payload)
            .rotate_right(15)
            .wrapping_add(MASK_DELTA);
        if expected != actual {
            return Err(LogError::Corrupt);
        }
        match kind {
            1 => {
                if fragments.is_some() {
                    return Err(LogError::Corrupt);
                }
                skip_orphaned = false;
                parsed.records.push(Record {
                    payload: payload.to_vec(),
                    end_offset: start_offset + end as u64,
                });
            }
            2 => {
                if fragments.is_some() {
                    return Err(LogError::Corrupt);
                }
                skip_orphaned = false;
                fragments = Some(payload.to_vec());
            }
            3 | 4 if skip_orphaned => {
                // The discarded prior block may contain the FIRST fragment.
                if kind == 4 {
                    skip_orphaned = false;
                }
            }
            3 | 4 => {
                let Some(pending) = fragments.as_mut() else {
                    return Err(LogError::Corrupt);
                };
                pending.extend_from_slice(payload);
                if kind == 4 {
                    parsed.records.push(Record {
                        payload: fragments.take().expect("pending fragments"),
                        end_offset: start_offset + end as u64,
                    });
                }
            }
            _ => unreachable!("record type validated"),
        }
        cursor = end;
    }
    if fragments.is_some() {
        parsed.incomplete_tail = true;
    }
    Ok(parsed)
}

#[cfg(test)]
pub(crate) fn fixture_record(kind: u8, payload: &[u8]) -> Vec<u8> {
    let mut bytes = vec![0_u8; 7];
    bytes[4..6].copy_from_slice(&(payload.len() as u16).to_le_bytes());
    bytes[6] = kind;
    let crc = crc32c::crc32c_append(crc32c::crc32c(&[kind]), payload);
    bytes[..4].copy_from_slice(&crc.rotate_right(15).wrapping_add(0xa282_ead8).to_le_bytes());
    bytes.extend_from_slice(payload);
    bytes
}

#[cfg(test)]
mod tests {
    use super::{fixture_record as physical, parse, LogError};

    #[test]
    fn reads_only_complete_checksum_verified_records() {
        let mut bytes = physical(1, b"old");
        let first_end = bytes.len();
        let mut bad = physical(1, b"new");
        bad[7] ^= 0x01;
        assert_eq!(
            parse(&bytes, 0).unwrap().records[0].end_offset,
            first_end as u64
        );
        bytes.extend(bad);
        assert!(matches!(parse(&bytes, 0), Err(LogError::Corrupt)));
    }

    #[test]
    fn ignores_only_incomplete_final_physical_record() {
        let mut bytes = physical(1, b"verified");
        bytes.extend_from_slice(&physical(1, b"unfinished")[..12]);
        let parsed = parse(&bytes, 0).unwrap();
        assert_eq!(parsed.records.len(), 1);
        assert_eq!(parsed.records[0].payload, b"verified");
        assert!(parsed.incomplete_tail);
    }

    #[test]
    fn reassembles_fragmented_record_across_blocks() {
        let mut bytes = physical(1, &vec![b'x'; 32_768 - 7 - 10]);
        bytes.extend(physical(2, b"abc"));
        assert_eq!(bytes.len(), 32_768);
        bytes.extend(physical(4, b"def"));
        let parsed = parse(&bytes, 0).unwrap();
        assert_eq!(parsed.records.len(), 2);
        assert_eq!(parsed.records[1].payload, b"abcdef");
        assert_eq!(parsed.records[1].end_offset, bytes.len() as u64);
    }

    #[test]
    fn skips_orphaned_fragments_when_tail_starts_at_later_block() {
        let mut bytes = physical(3, b"middle of older record");
        bytes.extend(physical(4, b"end of older record"));
        bytes.extend(physical(1, b"fresh record"));
        let parsed = parse(&bytes, 32_768).unwrap();
        assert_eq!(parsed.records.len(), 1);
        assert_eq!(parsed.records[0].payload, b"fresh record");
    }

    #[test]
    fn rejects_misaligned_read_start() {
        let bytes = physical(1, b"x");
        assert!(matches!(parse(&bytes, 1), Err(LogError::Corrupt)));
    }

    #[test]
    fn rejects_invalid_record_type() {
        let bytes = physical(9, b"a");
        assert!(matches!(parse(&bytes, 0), Err(LogError::Corrupt)));
    }

    #[test]
    fn boundary_trailer_is_ignored() {
        let mut bytes = physical(1, &vec![0_u8; 32_768 - 7 - 4]);
        bytes.extend_from_slice(&[0; 4]);
        bytes.extend(physical(1, b"next"));
        let parsed = parse(&bytes, 0).unwrap();
        assert_eq!(parsed.records.len(), 2);
        assert_eq!(parsed.records[1].payload, b"next");
    }
}
