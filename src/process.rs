use std::{io, process::Command};

pub fn discover() -> io::Result<Vec<i32>> {
    let output = Command::new("/bin/ps")
        .args(["-axo", "pid=,comm="])
        .output()?;
    if !output.status.success() {
        return Err(io::Error::other("ps failed"));
    }
    Ok(parse_ps(&String::from_utf8_lossy(&output.stdout)))
}

pub fn parse_ps(text: &str) -> Vec<i32> {
    let mut main = None;
    let mut helpers = Vec::new();
    for line in text.lines() {
        let mut parts = line.split_whitespace();
        let Some(pid) = parts.next().and_then(|p| p.parse::<i32>().ok()) else {
            continue;
        };
        let path = line
            .trim_start()
            .trim_start_matches(|c: char| c.is_ascii_digit())
            .trim();
        if path.ends_with("/NeteaseMusic.app/Contents/MacOS/NeteaseMusic") {
            main = Some(pid);
        } else if path.contains("/NeteaseMusic.app/Contents/Frameworks/") {
            helpers.push(pid);
        }
    }
    match main {
        Some(pid) => {
            let mut out = vec![pid];
            out.extend(helpers);
            out
        }
        None => vec![],
    }
}

#[cfg(test)]
mod tests {
    use super::parse_ps;
    #[test]
    fn select_only_netease_bundle() {
        let text = "8 /Applications/Other.app/Contents/MacOS/Other\n10 /Applications/NeteaseMusic.app/Contents/MacOS/NeteaseMusic\n11 /Applications/NeteaseMusic.app/Contents/Frameworks/NeteaseMusic Helper (GPU).app/Contents/MacOS/NeteaseMusic Helper (GPU)\n";
        assert_eq!(parse_ps(text), vec![10, 11]);
        assert!(parse_ps("9 /Applications/Other.app/Contents/MacOS/Other\n").is_empty());
    }
}
