const supportedHosts = new Set([
  "git.sr.ht",
  "hg.sr.ht",
  "todo.sr.ht",
  "builds.sr.ht",
  "lists.sr.ht",
  "meta.sr.ht",
  "sr.ht",
]);

const browserAPI = globalThis.browser ?? globalThis.chrome;

function isOwnerRootPath(path) {
  const components = path.split("/").filter(Boolean);
  return components.length === 1 && components[0].startsWith("~");
}

function normalizedPath(pathname) {
  return pathname.split("/").filter(Boolean).join("/");
}

function deepLinkPath(hostname, path) {
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

function deepLinkService(hostname, path) {
  if (isOwnerRootPath(path)) {
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

function hutchDeepLinkFor(rawURL) {
  let url;
  try {
    url = new URL(rawURL);
  } catch {
    return null;
  }

  if (url.protocol !== "https:" || !supportedHosts.has(url.hostname)) {
    return null;
  }

  const path = deepLinkPath(url.hostname, normalizedPath(url.pathname));
  const service = deepLinkService(url.hostname, path);
  const pathSegment = path ? `/${path}` : "";
  return `hutch://${service}${pathSegment}${url.search}${url.hash}`;
}

function showUnsupportedMessage(tabId) {
  if (!tabId) {
    return;
  }

  const message = "Open in Hutch supports git, hg, todo, builds, lists, meta, and sr.ht pages.";

  if (browserAPI?.scripting?.executeScript) {
    browserAPI.scripting.executeScript({
      target: { tabId },
      func: (text) => {
        window.alert(text);
      },
      args: [message],
    });
    return;
  }

  browserAPI?.tabs?.sendMessage?.(tabId, { type: "hutchUnsupportedPage", message });
}

function openURL(tabId, url) {
  if (browserAPI?.tabs?.update && tabId) {
    browserAPI.tabs.update(tabId, { url });
    return;
  }

  if (browserAPI?.tabs?.create) {
    browserAPI.tabs.create({ url });
  }
}

browserAPI.action.onClicked.addListener((tab) => {
  const hutchURL = tab?.url ? hutchDeepLinkFor(tab.url) : null;
  if (!hutchURL) {
    showUnsupportedMessage(tab?.id);
    return;
  }

  console.debug("[Hutch] Opening deep link", { sourceURL: tab.url, hutchURL });
  openURL(tab.id, hutchURL);
});
