(function () {
  const SUPPORTED = /\.(txt|md|ini|conf|yaml|yml|toml|json|log)$/i;
  const POLL_MS = 5000;

  const state = {
    path: "",
    content: "",
    original: "",
    mtime: 0,
    dirty: false,
    saving: false,
    timer: null,
    theme: localStorage.getItem("local-editor-theme") || "light",
  };

  if (window.top !== window) {
    return;
  }

  const filePath = decodeURIComponent(new URL(location.href).pathname);
  if (!SUPPORTED.test(filePath)) {
    return;
  }

  const panel = document.createElement("div");
  panel.className = `local-editor-panel local-editor-theme-${state.theme} hidden`;
  panel.innerHTML = `
    <div class="local-editor-bar">
      <div class="local-editor-title"></div>
      <div class="local-editor-status"></div>
    </div>
    <textarea class="local-editor-textarea" spellcheck="false"></textarea>
    <div class="local-editor-actions">
      <button type="button" class="local-editor-btn local-editor-theme-toggle">切换深色</button>
      <button type="button" class="local-editor-btn local-editor-close">关闭</button>
      <button type="button" class="local-editor-btn local-editor-save">保存</button>
    </div>
    <div class="local-editor-banner hidden">
      文件已被外部程序修改
      <button type="button" class="local-editor-reload">重新加载</button>
    </div>
  `;

  const fab = document.createElement("button");
  fab.className = "local-editor-fab";
  fab.type = "button";
  fab.textContent = "✏ Edit";

  document.documentElement.appendChild(panel);
  document.documentElement.appendChild(fab);

  const title = panel.querySelector(".local-editor-title");
  const status = panel.querySelector(".local-editor-status");
  const textarea = panel.querySelector(".local-editor-textarea");
  const banner = panel.querySelector(".local-editor-banner");
  const themeToggle = panel.querySelector(".local-editor-theme-toggle");

  const setStatus = (text) => {
    status.textContent = text;
  };

  const native = async (payload) => {
    const result = await browser.runtime.sendMessage({
      type: "local-editor-native",
      payload,
    });
    if (!result || result.error) {
      throw new Error(result && result.error ? result.error : "native host failed");
    }
    return result;
  };

  const renderDirty = () => {
    setStatus(state.dirty ? "● 未保存" : "✓ 已保存");
  };

  const renderTheme = () => {
    panel.classList.toggle("local-editor-theme-light", state.theme === "light");
    panel.classList.toggle("local-editor-theme-dark", state.theme === "dark");
    themeToggle.textContent = state.theme === "light" ? "切换深色" : "切换亮色";
  };

  const openEditor = () => {
    panel.classList.remove("hidden");
    fab.classList.add("hidden");
    textarea.focus();
  };

  const closeEditor = (refresh = true) => {
    panel.classList.add("hidden");
    fab.classList.remove("hidden");
    if (refresh) {
      window.setTimeout(() => location.reload(), 0);
    }
  };

  const editorOpen = () => !panel.classList.contains("hidden");

  const loadFile = async () => {
    const result = await native({ action: "read", path: filePath });

    state.path = filePath;
    state.content = result.content || "";
    state.original = state.content;
    state.mtime = result.mtime || 0;
    state.dirty = false;

    title.textContent = filePath.split("/").pop() || filePath;
    textarea.value = state.content;
    renderDirty();
  };

  const saveFile = async () => {
    if (state.saving) {
      return;
    }
    state.saving = true;
    setStatus("保存中...");
    try {
      const result = await native({
        action: "save",
        path: state.path,
        content: textarea.value,
      });

      state.original = textarea.value;
      state.content = textarea.value;
      state.mtime = result.mtime || state.mtime;
      state.dirty = false;
      banner.classList.add("hidden");
      renderDirty();
      setTimeout(() => {
        if (!state.dirty) {
          renderDirty();
        }
      }, 2000);
    } catch (error) {
      setStatus(`保存失败: ${error.message}`);
    } finally {
      state.saving = false;
    }
  };

  const checkExternalChange = async () => {
    if (!state.path || state.dirty) {
      return;
    }
    try {
      const result = await native({ action: "stat", path: state.path });
      if ((result.mtime || 0) !== state.mtime) {
        banner.classList.remove("hidden");
      }
    } catch (error) {
      setStatus(`检测失败: ${error.message}`);
    }
  };

  textarea.addEventListener("input", () => {
    state.dirty = textarea.value !== state.original;
    renderDirty();
  });

  window.addEventListener("keydown", async (event) => {
    if (!editorOpen()) {
      return;
    }
    if (event.key.toLowerCase() === "s" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      await saveFile();
    }
    if (event.key === "Escape") {
      event.preventDefault();
      closeEditor();
    }
  }, true);

  fab.addEventListener("click", async () => {
    if (!state.path) {
      await loadFile();
    }
    openEditor();
  });

  panel.querySelector(".local-editor-close").addEventListener("click", () => closeEditor());
  panel.querySelector(".local-editor-save").addEventListener("click", saveFile);
  themeToggle.addEventListener("click", () => {
    state.theme = state.theme === "light" ? "dark" : "light";
    localStorage.setItem("local-editor-theme", state.theme);
    renderTheme();
  });
  panel.querySelector(".local-editor-reload").addEventListener("click", async () => {
    banner.classList.add("hidden");
    await loadFile();
    textarea.value = state.content;
  });

  renderTheme();

  loadFile().then(() => {
    setStatus("✓ 已保存");
    state.timer = window.setInterval(checkExternalChange, POLL_MS);
  }).catch(() => {
    fab.remove();
    panel.remove();
  });
})();
