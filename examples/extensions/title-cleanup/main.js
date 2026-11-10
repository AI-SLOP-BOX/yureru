Yureru.on("library.write.mediaImport", ({ items, settings }) => {
  if (settings.enabled === false) return items;
  const prefix = settings.prefix ?? "曲：";
  return items.map((item) => ({
    ...item,
    title: item.title.startsWith(prefix)
      ? item.title.slice(prefix.length).trim()
      : item.title,
  }));
});

Yureru.register({
  settings: [
    { type: "section", label: "Import behavior" },
    { id: "enabled", label: "Clean imported titles", description: "Remove a leading label during import.", type: "toggle", default: true },
    { id: "prefix", label: "Leading text to remove", type: "text", default: "曲：" },
    { id: "mode", label: "Cleanup mode", type: "select", options: ["Preview", "Apply"], default: "Apply" },
    { id: "strength", label: "Match strength", type: "slider", min: 0, max: 1, default: 0.8 },
    { id: "delay", label: "Timing adjustment (seconds)", type: "number", min: -30, max: 30, default: 0 }
  ],
  commands: [
    { id: "status", title: "Title cleanup status", action: "status", icon: "library" }
  ],
  pages: [{
    id: "about",
    title: "Title cleanup",
    blocks: [
      { type: "text", text: "This extension removes a leading 曲： label from imported titles." },
      { type: "input", id: "prefix", label: "Leading text", value: "曲：" },
      { type: "toggle", id: "enabled", label: "Enable cleanup", value: true },
      { type: "divider" },
      { type: "button", label: "Show status", action: "status" }
    ]
  }],
  themes: [{
    id: "coral-night",
    name: "Coral Night",
    accent: "#E88F72",
    darkBackground: "#15171D",
    lightBackground: "#F7F2EF",
    darkSurface: "#222630",
    lightSurface: "#FFF9F5",
    darkText: "#F4F1F0",
    lightText: "#292321",
    cornerRadius: 20,
    fontScale: 1.05
  }]
});

Yureru.on("extension.action.status", () => "Title cleanup is ready.");
