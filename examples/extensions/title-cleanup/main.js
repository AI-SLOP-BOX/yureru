Yureru.on("library.write.mediaImport", ({ items }) =>
  items.map((item) => ({
    ...item,
    title: item.title.replace(/^曲：\s*/, ""),
  })),
);

Yureru.register({
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
    lightBackground: "#F7F2EF"
  }]
});

Yureru.on("extension.action.status", () => "Title cleanup is ready.");
