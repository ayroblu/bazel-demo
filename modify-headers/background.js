importScripts("headers.js", "domains.js");

const RESOURCE_TYPES = [
  "main_frame",
  "sub_frame",
  "stylesheet",
  "script",
  "image",
  "font",
  "object",
  "xmlhttprequest",
  "ping",
  "csp_report",
  "media",
  "websocket",
  "other",
];

async function syncRules() {
  const { headers = [], domains = defaultDomains() } = await chrome.storage.local.get(["headers", "domains"]);
  const requestHeaders = buildRequestHeaders(headers);
  const enabledDomains = domains.filter((domain) => domain.enabled).map((domain) => domain.name);
  const active = requestHeaders.length > 0 && enabledDomains.length > 0;
  const condition = { resourceTypes: RESOURCE_TYPES };
  if (!enabledDomains.includes("*")) condition.requestDomains = enabledDomains;
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: existing.map((rule) => rule.id),
    addRules: active
      ? [
          {
            id: 1,
            priority: 1,
            action: { type: "modifyHeaders", requestHeaders },
            condition,
          },
        ]
      : [],
  });
  await chrome.action.setIcon({ imageData: { 16: drawIcon(16, active), 32: drawIcon(32, active) } });
}

chrome.runtime.onInstalled.addListener(syncRules);
chrome.runtime.onStartup.addListener(syncRules);
chrome.storage.onChanged.addListener(syncRules);

function drawIcon(size, active) {
  const ctx = new OffscreenCanvas(size, size).getContext("2d");
  ctx.fillStyle = active ? "#1d9bf0" : "#9e9e9e";
  ctx.beginPath();
  ctx.roundRect(0, 0, size, size, size / 4);
  ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.font = `bold ${Math.round(size * 0.7)}px Arial, Helvetica, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("H", size / 2, size / 2 + size / 16);
  return ctx.getImageData(0, 0, size, size);
}
