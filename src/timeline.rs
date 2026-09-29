#[derive(Default)]
pub struct Timeline {
    current: Option<State>,
}
struct State {
    id: String,
    exact: u64,
    shown: u64,
    observed_at: u64,
    playing: bool,
    pending_backward: Option<u64>,
}
impl Timeline {
    pub fn reset(&mut self) {
        self.current = None;
    }
    pub fn update(&mut self, id: &str, exact: u64, playing: bool, now_ms: u64) -> u64 {
        if self.current.as_ref().is_none_or(|old| old.id != id) {
            self.current = Some(State {
                id: id.to_owned(),
                exact,
                shown: exact,
                observed_at: now_ms,
                playing,
                pending_backward: None,
            });
            return exact;
        }
        let state = self.current.as_mut().expect("track exists");
        let advancing = if state.playing && playing {
            now_ms.saturating_sub(state.observed_at)
        } else {
            0
        };
        let mut shown = state.shown.saturating_add(advancing);
        if exact < state.exact {
            if !playing
                || state
                    .pending_backward
                    .is_some_and(|pending| exact > pending)
            {
                shown = exact;
                state.exact = exact;
                state.pending_backward = None;
            } else if state.pending_backward.is_none() {
                state.pending_backward = Some(exact);
            }
        } else {
            state.exact = exact;
            shown = shown.max(exact);
            state.pending_backward = None;
        }
        state.shown = shown;
        state.playing = playing;
        state.observed_at = now_ms;
        shown
    }
}

#[cfg(test)]
mod tests {
    use super::Timeline;
    #[test]
    fn advances_only_when_playing() {
        let mut t = Timeline::default();
        assert_eq!(t.update("a", 1_000, true, 0), 1_000);
        assert_eq!(t.update("a", 1_000, true, 500), 1_500);
        assert_eq!(t.update("a", 1_000, false, 500), 1_500);
        assert_eq!(t.update("a", 1_000, false, 5_000), 1_500);
    }
    #[test]
    fn a_second_advancing_lower_sample_confirms_seek() {
        let mut t = Timeline::default();
        t.update("a", 60_000, true, 0);
        assert_eq!(t.update("a", 10_000, true, 500), 60_500);
        assert_eq!(t.update("a", 11_000, true, 1_000), 11_000);
        assert_eq!(t.update("b", 0, false, 1_000), 0);
    }
    #[test]
    fn paused_backward_seek_is_immediate() {
        let mut t = Timeline::default();
        t.update("a", 60_000, false, 0);
        assert_eq!(t.update("a", 10_000, false, 500), 10_000);
    }
    #[test]
    fn one_stale_backward_sample_does_not_seek() {
        let mut t = Timeline::default();
        t.update("a", 60_000, true, 0);
        assert_eq!(t.update("a", 10_000, true, 500), 60_500);
        assert_eq!(t.update("a", 60_000, true, 1_000), 61_000);
    }
}
