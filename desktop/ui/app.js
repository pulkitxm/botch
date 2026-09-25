const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);
let current = null;
let settingsOpen = false;

function selectedTab() {
  return current?.tabs.find((tab) => tab.id === current.selected) ?? null;
}

function displayUrl(url) {
  return url === "about:blank" ? "" : url;
}

function tabTitle(tab) {
  if (tab.title) return tab.title;
  const shown = displayUrl(tab.url);
  if (!shown) return "New Tab";
  try {
    return new URL(shown).host || shown;
  } catch {
    return shown;
  }
}

function initial(text) {
  return (text.trim()[0] || "?").toUpperCase();
}

function setOverlay() {
  invoke("set_overlay", { open: settingsOpen || !current?.profile });
}

function renderTabs() {
  const list = $("tabs");
  list.replaceChildren(
    ...current.tabs.map((tab) => {
      const item = document.createElement("div");
      item.className = "tab";
      item.classList.toggle("selected", tab.id === current.selected);
      item.classList.toggle("loading", tab.loading);
      item.title = displayUrl(tab.url);
      const title = document.createElement("span");
      title.className = "tab-title";
      title.textContent = tabTitle(tab);
      const close = document.createElement("button");
      close.className = "tab-close";
      close.textContent = "×";
      close.title = "Close tab";
      close.addEventListener("click", (event) => {
        event.stopPropagation();
        invoke("close_tab", { id: tab.id });
      });
      item.addEventListener("click", () => {
        settingsOpen = false;
        invoke("select_tab", { id: tab.id });
        render();
      });
      item.append(title, close);
      return item;
    }),
  );
}

function renderPicker() {
  const needsProfile = !current.profile;
  $("picker").classList.toggle("hidden", !needsProfile || settingsOpen);
  if (!needsProfile) return;
  const message = current.attaching
    ? current.status
    : current.chrome_error ??
      (current.profiles.length
        ? "Botch signs in with the cookies of one of your Google Chrome profiles."
        : "No Chrome profiles were found.");
  $("picker-message").textContent = message ?? "";
  $("download-chrome").classList.toggle("hidden", current.profiles.length > 0);
  $("profiles").replaceChildren(
    ...current.profiles.map((profile) => {
      const button = document.createElement("button");
      button.className = "profile";
      button.disabled = current.attaching;
      const avatar = document.createElement("span");
      avatar.className = "avatar";
      avatar.textContent = initial(profile.name);
      const text = document.createElement("span");
      text.textContent = profile.name;
      if (profile.email) {
        const email = document.createElement("span");
        email.className = "profile-email";
        email.textContent = profile.email;
        text.append(email);
      }
      button.append(avatar, text);
      button.addEventListener("click", () => invoke("choose_profile", { directory: profile.directory }));
      return button;
    }),
  );
}

function renderSettings() {
  $("settings").classList.toggle("hidden", !settingsOpen);
  const engine = $("engine");
  if (engine.options.length !== current.engines.length) {
    engine.replaceChildren(
      ...current.engines.map((option) => new Option(option.title, option.id)),
    );
  }
  engine.value = current.engine;
  $("settings-profile").textContent = current.profile
    ? `Signed in with ${current.profile.name}`
    : "No Chrome profile";
  $("detach").classList.toggle("hidden", !current.profile);
}

function render() {
  if (!current) return;
  $("pill").classList.toggle("hidden", current.expanded);
  $("panel").classList.toggle("hidden", !current.expanded);
  const tab = selectedTab();
  const hasProfile = Boolean(current.profile);
  $("profile-chip").classList.toggle("hidden", !hasProfile);
  $("profile-chip").textContent = current.profile?.name ?? "";
  for (const id of ["new-tab", "back", "forward", "reload", "address"]) {
    $(id).disabled = !hasProfile;
  }
  if (document.activeElement !== $("address")) {
    $("address").value = tab ? displayUrl(tab.url) : "";
  }
  $("status").textContent = settingsOpen || !hasProfile || !tab ? (current.status ?? "") : "";
  renderTabs();
  renderPicker();
  renderSettings();
}

function toggleSettings(open) {
  settingsOpen = open ?? !settingsOpen;
  setOverlay();
  render();
}

function withTab(command) {
  const tab = selectedTab();
  if (tab) invoke(command, { id: tab.id });
}

$("pill").addEventListener("click", () => invoke("expand"));
$("new-tab").addEventListener("click", () => invoke("new_tab", {}));
$("settings-toggle").addEventListener("click", () => toggleSettings());
$("profile-chip").addEventListener("click", () => toggleSettings(true));
$("back").addEventListener("click", () => withTab("go_back"));
$("forward").addEventListener("click", () => withTab("go_forward"));
$("reload").addEventListener("click", () => withTab("reload"));
$("engine").addEventListener("change", (event) => invoke("set_search_engine", { id: event.target.value }));
$("detach").addEventListener("click", () => {
  settingsOpen = false;
  invoke("detach_profile");
});
$("quit").addEventListener("click", () => invoke("quit"));
$("download-chrome").addEventListener("click", () => invoke("open_external", { url: current.download_url }));

$("address").addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    const input = event.target.value.trim();
    const tab = selectedTab();
    if (!input) return;
    settingsOpen = false;
    setOverlay();
    if (tab) invoke("navigate", { id: tab.id, input });
    else invoke("new_tab", { url: input });
    event.target.blur();
  } else if (event.key === "Escape") {
    event.target.blur();
    render();
  }
});
$("address").addEventListener("focus", (event) => event.target.select());

document.addEventListener("keydown", (event) => {
  if (!(event.ctrlKey || event.metaKey) || !current?.profile) return;
  const key = event.key.toLowerCase();
  const actions = {
    t: () => invoke("new_tab", {}),
    w: () => withTab("close_tab"),
    l: () => $("address").focus(),
    r: () => withTab("reload"),
  };
  if (actions[key]) {
    event.preventDefault();
    actions[key]();
  }
});

$("handle").addEventListener("pointerdown", (event) => {
  const handle = event.currentTarget;
  const start = { x: event.screenX, y: event.screenY, width: current.width, height: current.height };
  let latest = null;
  let scheduled = false;
  handle.setPointerCapture(event.pointerId);
  const move = (moveEvent) => {
    latest = {
      width: start.width + 2 * (moveEvent.screenX - start.x),
      height: start.height + (moveEvent.screenY - start.y),
    };
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      invoke("set_expanded_size", latest);
    });
  };
  const stop = () => {
    handle.removeEventListener("pointermove", move);
    handle.removeEventListener("pointerup", stop);
  };
  handle.addEventListener("pointermove", move);
  handle.addEventListener("pointerup", stop);
});

listen("state", (event) => {
  current = event.payload;
  if (!current.expanded) settingsOpen = false;
  render();
});
listen("open-settings", () => toggleSettings(true));
invoke("state");
