import { log } from "./log";

// There two parts
// 1. List all "scrollable" elements
// 2. Update scrollable element based on last scrolled
export function getScrollable(): Window | HTMLElement {
  if (lastTarget) {
    log("lastTarget", lastTarget);
    return lastTarget;
  }
  if (
    document.documentElement.scrollHeight >
    document.documentElement.clientHeight
  ) {
    lastTarget = window;
    return lastTarget;
  }
  if (document.body.scrollHeight > document.body.clientHeight) {
    lastTarget = document.body;
    return lastTarget;
  }
  const items = [...document.querySelectorAll("*")].filter(
    (el): el is HTMLElement =>
      el instanceof HTMLElement &&
      el.clientHeight > 0 &&
      el.scrollHeight > el.clientHeight &&
      (() => {
        const overflowY = window.getComputedStyle(el).overflowY;
        return overflowY !== "visible" && overflowY !== "hidden";
      })()
  );
  if (items.length === 0) {
    return window;
  }
  let maxArea = 0;
  let maxItem = items[0];
  for (const item of items) {
    const area = item.clientWidth * item.clientHeight;
    if (area > maxArea) {
      maxArea = area;
      maxItem = item;
    }
  }
  lastTarget = maxItem;
  return maxItem;
}
let lastTarget: null | HTMLElement | Window = null;

const eventListener = (event: Event) => {
  if (event.target === document) {
    lastTarget = window;
  }
  if (event.target instanceof HTMLElement) {
    lastTarget = event.target;
  }
};
export const scrollHalfPage = (direction: "up" | "down") => {
  const scrollable = getScrollable();
  const scrollableHeight =
    scrollable instanceof HTMLElement
      ? scrollable.clientHeight
      : window.innerHeight;
  getScrollable().scrollBy(
    0,
    ((direction === "up" ? -1 : 1) *
      Math.min(window.innerHeight, scrollableHeight)) /
      2
  );
};
export function handleScrollToBottom() {
  const scrollable = getScrollable();
  const scrollElement =
    scrollable instanceof HTMLElement ? scrollable : document.body;
  scrollable.scrollTo(0, scrollElement.scrollHeight);
}
export function setupScrollListener() {
  addEventListener("scroll", eventListener, { passive: true, capture: true });
  return () => {
    removeEventListener("scroll", eventListener, { capture: true });
  };
}
export function resetScrollable() {
  lastTarget = window;
}
