//! Read NetEase's menu labels without opening menus or invoking AX actions.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PlaybackState {
    Playing,
    PausedOrIdle,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AxError {
    PermissionDenied,
    Unavailable,
}

/// Classify the action exposed by the menu, not the audio process activity.
fn classify_actions<'a>(
    items: impl IntoIterator<Item = (&'a str, &'a str, bool)>,
) -> Result<PlaybackState, AxError> {
    let mut state = None;
    for (role, title, enabled) in items {
        if role != "AXMenuItem" {
            continue;
        }
        let action = match title {
            "暂停" | "Pause" => PlaybackState::Playing,
            "播放" | "Play" => PlaybackState::PausedOrIdle,
            _ => continue,
        };
        if !enabled || state.is_some() {
            return Err(AxError::Unavailable);
        }
        state = Some(action);
    }
    state.ok_or(AxError::Unavailable)
}

use std::{
    ffi::{c_char, c_void, CStr},
    ptr::{self, NonNull},
};

type CFRef = *const c_void;
const UTF8: u32 = 0x0800_0100; // kCFStringEncodingUTF8
const AX_API_DISABLED: i32 = -25211;
const AX_ATTRIBUTE_UNSUPPORTED: i32 = -25205;
const AX_NO_VALUE: i32 = -25212;

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    fn AXIsProcessTrusted() -> u8;
    fn AXUIElementCreateApplication(pid: i32) -> CFRef;
    fn AXUIElementGetTypeID() -> usize;
    fn AXUIElementSetMessagingTimeout(element: CFRef, seconds: f32) -> i32;
    fn AXUIElementCopyAttributeValue(element: CFRef, name: CFRef, value: *mut CFRef) -> i32;
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(value: CFRef);
    fn CFRetain(value: CFRef) -> CFRef;
    fn CFGetTypeID(value: CFRef) -> usize;
    fn CFStringGetTypeID() -> usize;
    fn CFArrayGetTypeID() -> usize;
    fn CFBooleanGetTypeID() -> usize;
    fn CFStringCreateWithCString(allocator: CFRef, value: *const c_char, encoding: u32) -> CFRef;
    fn CFStringGetCString(value: CFRef, buffer: *mut c_char, size: isize, encoding: u32) -> u8;
    fn CFArrayGetCount(array: CFRef) -> isize;
    fn CFArrayGetValueAtIndex(array: CFRef, index: isize) -> CFRef;
    fn CFBooleanGetValue(value: CFRef) -> u8;
}

/// One +1 CoreFoundation reference. Borrowed array elements must be retained before wrapping.
struct OwnedCF(NonNull<c_void>);

impl OwnedCF {
    fn from_created(value: CFRef) -> Option<Self> {
        NonNull::new(value.cast_mut()).map(Self)
    }

    fn as_ref(&self) -> CFRef {
        self.0.as_ptr().cast_const()
    }

    fn has_type(&self, expected: usize) -> bool {
        // SAFETY: A live +1 reference is always a valid CoreFoundation object.
        unsafe { CFGetTypeID(self.as_ref()) == expected }
    }
}

impl Drop for OwnedCF {
    fn drop(&mut self) {
        // SAFETY: OwnedCF holds exactly one +1 reference from Create/Copy/Retain.
        unsafe { CFRelease(self.as_ref()) };
    }
}

fn attribute(element: &OwnedCF, name: &'static CStr) -> Result<Option<OwnedCF>, AxError> {
    // SAFETY: Every AX element reference is live; no UI action is performed.
    unsafe {
        let _ = AXUIElementSetMessagingTimeout(element.as_ref(), 0.3);
        let key =
            OwnedCF::from_created(CFStringCreateWithCString(ptr::null(), name.as_ptr(), UTF8))
                .ok_or(AxError::Unavailable)?;
        let mut value = ptr::null();
        let error = AXUIElementCopyAttributeValue(element.as_ref(), key.as_ref(), &mut value);
        match error {
            0 => OwnedCF::from_created(value)
                .map(Some)
                .ok_or(AxError::Unavailable),
            AX_ATTRIBUTE_UNSUPPORTED | AX_NO_VALUE => Ok(None),
            AX_API_DISABLED => Err(AxError::PermissionDenied),
            _ => Err(AxError::Unavailable),
        }
    }
}

fn string(element: &OwnedCF, name: &'static CStr) -> Result<Option<String>, AxError> {
    let Some(value) = attribute(element, name)? else {
        return Ok(None);
    };
    // SAFETY: Type is checked before using the CFString API, and buffer is writable.
    unsafe {
        if !value.has_type(CFStringGetTypeID()) {
            return Err(AxError::Unavailable);
        }
        let mut buffer = [0 as c_char; 128];
        if CFStringGetCString(
            value.as_ref(),
            buffer.as_mut_ptr(),
            buffer.len() as isize,
            UTF8,
        ) == 0
        {
            return Err(AxError::Unavailable);
        }
        let text = CStr::from_ptr(buffer.as_ptr())
            .to_str()
            .map_err(|_| AxError::Unavailable)?;
        Ok(Some(text.to_owned()))
    }
}

fn children(element: &OwnedCF, max: isize) -> Result<Vec<OwnedCF>, AxError> {
    let Some(values) = attribute(element, c"AXChildren")? else {
        return Err(AxError::Unavailable);
    };
    // SAFETY: Verify CFArray type and every borrowed entry's AX type before retaining it.
    unsafe {
        if !values.has_type(CFArrayGetTypeID()) {
            return Err(AxError::Unavailable);
        }
        let count = CFArrayGetCount(values.as_ref());
        if count < 1 || count > max {
            return Err(AxError::Unavailable);
        }
        (0..count)
            .map(|i| {
                let item = CFArrayGetValueAtIndex(values.as_ref(), i);
                if item.is_null() || CFGetTypeID(item) != AXUIElementGetTypeID() {
                    return Err(AxError::Unavailable);
                }
                OwnedCF::from_created(CFRetain(item)).ok_or(AxError::Unavailable)
            })
            .collect()
    }
}

fn role(element: &OwnedCF) -> Result<Option<String>, AxError> {
    string(element, c"AXRole")
}

fn enabled(element: &OwnedCF) -> Result<bool, AxError> {
    let Some(value) = attribute(element, c"AXEnabled")? else {
        return Ok(false);
    };
    // SAFETY: Verify CFBoolean type before querying its value.
    unsafe {
        if !value.has_type(CFBooleanGetTypeID()) {
            return Err(AxError::Unavailable);
        }
        Ok(CFBooleanGetValue(value.as_ref()) != 0)
    }
}

/// Query a single, direct transport menu item. Never open menus or press buttons.
pub fn playback_state(pid: i32) -> Result<PlaybackState, AxError> {
    // SAFETY: AXIsProcessTrusted has no arguments; query only (no authorization prompt).
    if unsafe { AXIsProcessTrusted() } == 0 {
        return Err(AxError::PermissionDenied);
    }
    // SAFETY: A valid pid is supplied by the caller's main-process discovery.
    let app = OwnedCF::from_created(unsafe { AXUIElementCreateApplication(pid) })
        .ok_or(AxError::Unavailable)?;
    let bar = attribute(&app, c"AXMenuBar")?.ok_or(AxError::Unavailable)?;
    // SAFETY: A returned AXMenuBar is expected to be an AXUIElement.
    if !bar.has_type(unsafe { AXUIElementGetTypeID() })
        || role(&bar)?.as_deref() != Some("AXMenuBar")
    {
        return Err(AxError::Unavailable);
    }
    let mut targets = Vec::new();
    for item in children(&bar, 16)? {
        if role(&item)?.as_deref() == Some("AXMenuBarItem")
            && matches!(
                string(&item, c"AXTitle")?.as_deref(),
                Some("控制" | "Controls")
            )
        {
            targets.push(item);
        }
    }
    if targets.len() != 1 {
        return Err(AxError::Unavailable);
    }
    let mut menus = Vec::new();
    for menu in children(&targets[0], 2)? {
        if role(&menu)?.as_deref() == Some("AXMenu") {
            menus.push(menu);
        }
    }
    if menus.len() != 1 {
        return Err(AxError::Unavailable);
    }
    let mut actions = Vec::new();
    for item in children(&menus[0], 32)? {
        let Some(item_role) = role(&item)? else {
            continue;
        };
        let Some(title) = string(&item, c"AXTitle")? else {
            continue;
        };
        if matches!(title.as_str(), "暂停" | "播放" | "Pause" | "Play") {
            actions.push((item_role, title, enabled(&item)?));
        }
    }
    classify_actions(
        actions
            .iter()
            .map(|(item_role, title, enabled)| (item_role.as_str(), title.as_str(), *enabled)),
    )
}

#[cfg(test)]
mod tests {
    use super::{classify_actions, AxError, PlaybackState};

    #[test]
    fn exact_transport_action_describes_current_state() {
        for title in ["暂停", "Pause"] {
            assert_eq!(
                classify_actions([("AXMenuItem", title, true)]),
                Ok(PlaybackState::Playing)
            );
        }
        for title in ["播放", "Play"] {
            assert_eq!(
                classify_actions([("AXMenuItem", title, true)]),
                Ok(PlaybackState::PausedOrIdle)
            );
        }
    }

    #[test]
    fn no_guessing_from_partial_disabled_conflicting_or_wrong_role() {
        assert_eq!(
            classify_actions([("AXMenuItem", "播放歌曲", true)]),
            Err(AxError::Unavailable)
        );
        assert_eq!(
            classify_actions([("AXMenuItem", "播放", false)]),
            Err(AxError::Unavailable)
        );
        assert_eq!(
            classify_actions([("AXButton", "暂停", true)]),
            Err(AxError::Unavailable)
        );
        assert_eq!(
            classify_actions([("AXMenuItem", "播放", true), ("AXMenuItem", "暂停", true)]),
            Err(AxError::Unavailable)
        );
        assert_eq!(
            classify_actions([("AXMenuItem", "暂停", true), ("AXMenuItem", "暂停", true)]),
            Err(AxError::Unavailable)
        );
        assert_eq!(
            classify_actions([("AXMenuItem", "下一个", true)]),
            Err(AxError::Unavailable)
        );
    }
}
