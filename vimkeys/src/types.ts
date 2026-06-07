export type Mode = "insert" | "normal" | "links" | "search";
export type Keymap = { [key: string]: (() => void) | Keymap };
export type Highlight = {
  el: HTMLElement;
  text: string | undefined;
  originalEl: HTMLElement;
  rect: {
    top: number;
    bottom: number;
    left: number;
    right: number;
  };
  numLabel: string;
  setEligible: (eligible: boolean) => void;
};
