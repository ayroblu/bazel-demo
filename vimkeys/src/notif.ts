function createNotif(text: string) {
  const element = document.createElement("div");
  element.innerText = text;
  Object.assign(element.style, {
    padding: "4px 8px",
    position: "fixed",
    bottom: 0,
    right: "20px",
    background: "black",
    color: "white",
    borderRadius: "8px 8px 0 0",
    zIndex: 9999,
    border: "1px solid #ffffff",
    borderBottom: "0px solid #ffffff",
    fontFamily: "monospace",
  });
  document.body.appendChild(element);
  return element;
}
let notifElement: HTMLElement | null = null;
export function notif(text: string) {
  if (notifElement) {
    notifElement.innerText = text;
    delayTimeout?.();
    return;
  }
  notifElement = createNotif(text);
  setClearNotif();
}

let delayTimeout: void | (() => void);
function setClearNotif() {
  let timeoutId = setTimeout(() => {
    notifElement?.remove();
    notifElement = null;
    delayTimeout = undefined;
  }, 3000);
  delayTimeout = () => {
    clearTimeout(timeoutId);
    setClearNotif();
  };
}
