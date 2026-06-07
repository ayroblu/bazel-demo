import { mode } from "./mode-helper";
import { Highlight } from "./types";

let highlights: Highlight[] = [];
let typedState = "";
// https://gist.github.com/iiLaurens/81b1b47f6259485c93ce6f0cdd17490a
export function showLinkTags() {
  const bodyRect = document.body.getBoundingClientRect();

  let items = [...document.querySelectorAll("*")]
    .filter(
      (el): el is HTMLElement =>
        el instanceof HTMLElement &&
        isElementInViewport(el) &&
        !isHidden(el) &&
        (["BUTTON", "A", "INPUT"].includes(el.tagName) ||
          el.role === "button" ||
          !!el.onclick ||
          window.getComputedStyle(el).cursor == "pointer")
    )
    .map(function (element) {
      var rect = element.getBoundingClientRect();
      return {
        element: element,
        rect: {
          left: Math.max(rect.left - bodyRect.x, 0),
          top: Math.max(rect.top - bodyRect.y, 0),
          right: Math.min(rect.right - bodyRect.x, document.body.clientWidth),
          bottom: Math.min(
            rect.bottom - bodyRect.y,
            document.body.clientHeight
          ),
        },
        text: element.textContent?.trim().replace(/\s{2,}/g, " "),
      };
    })
    .filter(
      (item) =>
        (item.rect.right - item.rect.left) *
          (item.rect.bottom - item.rect.top) >=
        20
    );

  // Only keep inner clickable items
  items = items.filter(
    (x) => !items.some((y) => x.element.contains(y.element) && !(x == y))
  );

  // Lets create a floating border on top of these elements that will always be visible
  highlights.forEach(({ el }) => el.remove());
  highlights = items.map((item, i) => {
    const newElement = document.createElement("div");
    newElement.style.outline = "2px dashed rgba(255,0,0,.75)";
    newElement.style.position = "absolute";
    newElement.style.left = item.rect.left + "px";
    newElement.style.top = item.rect.top + "px";
    newElement.style.width = item.rect.right - item.rect.left + "px";
    newElement.style.height = item.rect.bottom - item.rect.top + "px";
    newElement.style.pointerEvents = "none";
    newElement.style.boxSizing = "border-box";
    newElement.style.zIndex = "2147483647";
    const labelElement = document.createElement("div");
    newElement.appendChild(labelElement);
    Object.assign(labelElement.style, {
      top: "0",
      left: "0",
      backgroundColor: "#fcba03",
      borderRadius: "4px",
      fontWeight: "bold",
      fontSize: "1.15rem",
      fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
      padding: "4px 8x",
      display: "inline-block",
      color: "black",
      border: "1px solid #553300",
    });
    const iLabel =
      i +
      Math.pow(10, Math.max((items.length - 1).toString().length - 1, 0)) +
      "";
    labelElement.innerText = iLabel;

    document.body.appendChild(newElement);
    return {
      el: newElement,
      rect: item.rect,
      text: item.text,
      originalEl: item.element,
      numLabel: iLabel,
      setEligible: (eligible: boolean) => {
        if (!eligible) {
          Object.assign(newElement.style, {
            opacity: "0.2",
          });
        } else {
          Object.assign(newElement.style, {
            opacity: "1",
          });
        }
      },
    };
  });
  if (highlights.length) {
    mode.value = "links";
  }
}

export function clearLinks() {
  highlights.forEach(({ el }) => el.remove());
  highlights = [];
  mode.value = "normal";
  typedState = "";
}
// How to handle links, there's a few different ways
// 1. sequential, e.g. a, b, aa, ab etc
// 2. spacial: where a link at the top of the page is always a, and the link at the bottom is always z
// 3. by link contents: (only works with href / text content links) by the hash value of the link
// 4. by "search": filter by link href and text (doesn't work for icons? - accessibility label)
// Also, can be omni bar style menu or tabbable
export function handleLinkFn(char: string) {
  return () => {
    const resultText =
      char === "Backspace" ? typedState.slice(0, -1) : typedState + char;
    const eligibleHighlights = highlights.filter(
      ({ numLabel, setEligible }) => {
        const isEligible = numLabel.startsWith(resultText);
        setEligible(isEligible);
        return isEligible;
      }
    );
    if (eligibleHighlights.length === 0) {
      clearLinks();
    } else if (eligibleHighlights.length === 1) {
      // eligibleHighlights[0].originalEl.click();
      const clickEvent = new MouseEvent("click", {
        view: window,
        bubbles: true,
        cancelable: false,
      });
      eligibleHighlights[0].originalEl.dispatchEvent(clickEvent);
      clearLinks();
    } else {
      typedState = resultText;
    }
  };
}

function isElementInViewport(el: HTMLElement) {
  var rect = el.getBoundingClientRect();

  return (
    rect.top >= 0 &&
    rect.left >= 0 &&
    rect.bottom <=
      (window.innerHeight || document.documentElement.clientHeight) &&
    rect.right <= (window.innerWidth || document.documentElement.clientWidth)
  );
}
function isHidden(el: HTMLElement) {
  const style = window.getComputedStyle(el);
  return (
    style.display === "none" ||
    style.visibility === "hidden" ||
    style.pointerEvents === "none"
  );
}
export function nextInput() {
  let inputs = [
    ...document.querySelectorAll("input[type=text],textarea"),
  ].filter(filterInputs);
  if (!inputs.length) {
    inputs = getAllInputsIncludingWebComponents();
    if (!inputs.length) {
      return;
    }
  }
  const activeElement = document.activeElement;
  let nextIndex = 0;
  if (activeElement instanceof HTMLInputElement) {
    const index = inputs.indexOf(activeElement);
    if (index !== -1) {
      nextIndex = index + (1 % inputs.length);
    }
  }
  inputs[nextIndex].focus();
}
function getAllInputsIncludingWebComponents(
  root: Document | ShadowRoot = document
): (HTMLInputElement | HTMLTextAreaElement)[] {
  const inputs = [];

  inputs.push(...root.querySelectorAll("input[type=text],textarea"));

  root.querySelectorAll("*").forEach((element) => {
    if (element.shadowRoot) {
      inputs.push(...getAllInputsIncludingWebComponents(element.shadowRoot));
    }
  });

  return inputs.filter(filterInputs);
}
function filterInputs(
  element: Element
): element is HTMLInputElement | HTMLTextAreaElement {
  return (
    (element instanceof HTMLInputElement ||
      element instanceof HTMLTextAreaElement) &&
    isElementInViewport(element) &&
    !isHidden(element) &&
    !element.disabled
  );
}
