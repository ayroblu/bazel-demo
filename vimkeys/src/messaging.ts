import { Actions, MessageListener } from "./background";

export function addMessageListener<K extends keyof Actions>(
  cb: MessageListener<K>
) {
  const callback = cb as browser.runtime.onMessageEvent;
  browser.runtime.onMessage.addListener(callback);
  return () => {
    browser.runtime.onMessage.removeListener(callback);
  };
}
export function sendMessage<K extends keyof Actions>(
  req: Parameters<Actions[K]>[0]
): Promise<Parameters<Parameters<Actions[K]>[2]>[0]> {
  return browser.runtime.sendMessage(req);
}
