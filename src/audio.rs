use std::{ffi::c_void, mem::size_of};

#[repr(C)]
struct Address {
    selector: u32,
    scope: u32,
    element: u32,
}

#[link(name = "CoreAudio", kind = "framework")]
unsafe extern "C" {
    fn AudioObjectGetPropertyData(
        id: u32,
        address: *const Address,
        qualifier_size: u32,
        qualifier: *const c_void,
        data_size: *mut u32,
        data: *mut c_void,
    ) -> i32;
}

const fn fourcc(bytes: [u8; 4]) -> u32 {
    u32::from_be_bytes(bytes)
}
const GLOBAL: u32 = fourcc(*b"glob");
const TRANSLATE_PID: u32 = fourcc(*b"id2p");
const IS_RUNNING_OUTPUT: u32 = fourcc(*b"piro");

fn state(pid: i32) -> Option<bool> {
    let address = Address {
        selector: TRANSLATE_PID,
        scope: GLOBAL,
        element: 0,
    };
    let mut object_id = 0_u32;
    let mut size = size_of::<u32>() as u32;
    // SAFETY: 参数长度与类型匹配 SDK 的 AudioObjectGetPropertyData 声明；指针只在调用期间有效。
    let result = unsafe {
        AudioObjectGetPropertyData(
            1,
            &address,
            size_of::<i32>() as u32,
            (&pid as *const i32).cast(),
            &mut size,
            (&mut object_id as *mut u32).cast(),
        )
    };
    if result != 0 || object_id == 0 || size != size_of::<u32>() as u32 {
        return None;
    }
    let address = Address {
        selector: IS_RUNNING_OUTPUT,
        scope: GLOBAL,
        element: 0,
    };
    let mut running = 0_u32;
    size = size_of::<u32>() as u32;
    // SAFETY: CoreAudio 给出的有效 object_id 与 UInt32 输出缓冲区；空 qualifier 用 null。
    let result = unsafe {
        AudioObjectGetPropertyData(
            object_id,
            &address,
            0,
            std::ptr::null(),
            &mut size,
            (&mut running as *mut u32).cast(),
        )
    };
    if result == 0 && size == size_of::<u32>() as u32 {
        Some(running != 0)
    } else {
        None
    }
}

pub fn merge(values: impl IntoIterator<Item = Option<bool>>) -> Option<bool> {
    let mut seen = false;
    let mut unknown = false;
    for value in values {
        seen = true;
        match value {
            Some(true) => return Some(true),
            Some(false) => {}
            None => unknown = true,
        }
    }
    if seen && !unknown {
        Some(false)
    } else {
        None
    }
}

pub fn is_running_output(pids: &[i32]) -> Option<bool> {
    merge(pids.iter().copied().map(state))
}

#[cfg(test)]
mod tests {
    use super::merge;
    #[test]
    fn any_output_wins_unknown_is_not_false() {
        assert_eq!(merge([None, None]), None);
        assert_eq!(merge([Some(false), None]), None);
        assert_eq!(merge([Some(false), Some(false)]), Some(false));
        assert_eq!(merge([Some(false), Some(true)]), Some(true));
        assert_eq!(merge([None, Some(true)]), Some(true));
    }
}
