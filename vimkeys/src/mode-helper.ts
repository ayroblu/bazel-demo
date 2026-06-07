import { Keymap, Mode } from "./types";

export const mode = modeHelper();
function modeHelper() {
  let mode: Mode = "normal";
  // There's two ways to think about state. Imagine 'party' and 'arts'. If you
  // type in `parts` what should happen? Either simply clear / single ref
  // state, aka nothing, or use a queue. Vim uses a queue, and will
  // "replay" keys that didn't match
  // In our design we didn't really want to have "overlaps" where you have "p"
  // and "parts", but maybe we should given vim mapping dsl
  // We can't "replay" events cause browser sandboxing, but for inuts
  // specifically we can simply update the input values
  // TODO: clear state based on (scroll, resize), click, focus change
  let state: null | Keymap = null;
  let insertState: string[] = [];
  return {
    get value() {
      return mode;
    },
    set value(newMode: Mode) {
      if (newMode === mode) return;
      state = null;
      insertState = [];
      mode = newMode;
    },
    getState: () => state,
    setState: (newState: Keymap | null) => {
      state = newState;
    },
    clearInsertState: () => {
      if (insertState.length) {
        insertState = [];
      }
    },
    get insertState() {
      return insertState.join("");
    },
    addInsertState: (key: string) => {
      insertState.push(key);
      // `p`, `pa` -> {p: {a: () => {}, default: () => paste}}
    },
  };
}
