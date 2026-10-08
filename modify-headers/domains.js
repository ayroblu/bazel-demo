function defaultDomains() {
  return [{ name: "*", enabled: true }];
}

function domainPermission(name) {
  return name === "*" ? "*://*/*" : `*://*.${name}/*`;
}
