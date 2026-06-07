export async function getCurrentTab(): Promise<browser.tabs.Tab | undefined> {
  let queryOptions = { active: true, lastFocusedWindow: true };
  let [tab] = await browser.tabs.query(queryOptions);
  return tab;
}
