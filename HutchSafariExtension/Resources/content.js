const hutchSupportedHosts = new Set([
  "git.sr.ht",
  "hg.sr.ht",
  "todo.sr.ht",
  "builds.sr.ht",
  "lists.sr.ht",
  "meta.sr.ht",
  "sr.ht",
]);

const hutchBrowserAPI = globalThis.browser ?? globalThis.chrome;
const bannerStorageKey = "showOpenInHutchBanner";
const dismissedStorageKey = `dismissedOpenInHutchBanner:${location.hostname}`;

function hutchIsOwnerRootPath(path) {
  const components = path.split("/").filter(Boolean);
  return components.length === 1 && components[0].startsWith("~");
}

function hutchNormalizedPath(pathname) {
  return pathname.split("/").filter(Boolean).join("/");
}

function hutchDeepLinkPath(hostname, path) {
  const components = path.split("/").filter(Boolean);
  if (
    hostname === "sr.ht" &&
    components.length === 2 &&
    components[0] === "projects" &&
    components[1].startsWith("~")
  ) {
    return components[1];
  }

  return path;
}

function hutchDeepLinkService(hostname, path) {
  if (hutchIsOwnerRootPath(path)) {
    return "lookup";
  }

  switch (hostname) {
    case "git.sr.ht":
      return "git";
    case "hg.sr.ht":
      return "hg";
    case "todo.sr.ht":
      return "todo";
    case "builds.sr.ht":
      return "builds";
    case "lists.sr.ht":
      return "lists";
    default:
      return "lookup";
  }
}

function hutchDeepLinkForLocation() {
  if (location.protocol !== "https:" || !hutchSupportedHosts.has(location.hostname)) {
    return null;
  }

  const path = hutchDeepLinkPath(location.hostname, hutchNormalizedPath(location.pathname));
  const service = hutchDeepLinkService(location.hostname, path);
  return `hutch://${service}${path ? `/${path}` : ""}${location.search}${location.hash}`;
}

function storageGet(defaults) {
  return new Promise((resolve) => {
    hutchBrowserAPI.storage.local.get(defaults, resolve);
  });
}

function storageSet(values) {
  return new Promise((resolve) => {
    hutchBrowserAPI.storage.local.set(values, resolve);
  });
}

function showNotice(message) {
  const existing = document.getElementById("hutch-open-notice");
  existing?.remove();

  const notice = document.createElement("div");
  notice.id = "hutch-open-notice";
  notice.textContent = message;
  notice.style.cssText = [
    "position:fixed",
    "left:50%",
    "bottom:18px",
    "z-index:2147483647",
    "transform:translateX(-50%)",
    "background:#1f2937",
    "color:white",
    "font:13px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
    "padding:8px 12px",
    "border-radius:8px",
    "box-shadow:0 8px 24px rgba(0,0,0,.24)",
  ].join(";");

  document.documentElement.appendChild(notice);
  setTimeout(() => notice.remove(), 3500);
}

async function injectBannerIfEnabled() {
  const hutchURL = hutchDeepLinkForLocation();
  if (!hutchURL || document.getElementById("hutch-open-banner")) {
    return;
  }

  const settings = await storageGet({
    [bannerStorageKey]: false,
    [dismissedStorageKey]: false,
  });
  if (!settings[bannerStorageKey] || settings[dismissedStorageKey]) {
    return;
  }

  const banner = document.createElement("div");
  banner.id = "hutch-open-banner";
  banner.style.cssText = [
    "position:fixed",
    "right:14px",
    "bottom:14px",
    "z-index:2147483647",
    "display:flex",
    "align-items:center",
    "gap:8px",
    "background:#111827",
    "color:white",
    "font:13px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
    "padding:8px 10px",
    "border-radius:8px",
    "box-shadow:0 8px 24px rgba(0,0,0,.22)",
  ].join(";");

  const button = document.createElement("button");
  button.type = "button";
  button.textContent = "Open in Hutch";
  button.style.cssText = [
    "appearance:none",
    "border:0",
    "background:transparent",
    "color:inherit",
    "font:inherit",
    "font-weight:600",
    "padding:0",
  ].join(";");
  button.addEventListener("click", () => {
    console.debug("[Hutch] Banner opening deep link", { sourceURL: location.href, hutchURL });
    location.href = hutchURL;
  });

  const dismiss = document.createElement("button");
  dismiss.type = "button";
  dismiss.textContent = "Close";
  dismiss.setAttribute("aria-label", "Dismiss Open in Hutch banner");
  dismiss.style.cssText = [
    "appearance:none",
    "border:0",
    "background:rgba(255,255,255,.14)",
    "color:inherit",
    "font:12px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
    "padding:3px 6px",
    "border-radius:6px",
  ].join(";");
  dismiss.addEventListener("click", async () => {
    await storageSet({ [dismissedStorageKey]: true });
    banner.remove();
  });

  banner.append(button, dismiss);
  document.documentElement.appendChild(banner);
}

hutchBrowserAPI.runtime.onMessage.addListener((message) => {
  if (message?.type === "hutchUnsupportedPage") {
    showNotice(message.message);
  }
});

injectBannerIfEnabled();
