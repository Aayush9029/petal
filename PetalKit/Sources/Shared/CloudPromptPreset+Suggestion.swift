extension CloudPromptPreset {
    /// The style a new route starts with, so adding Mail gives email formatting without another tap.
    public static func suggested(for trigger: CleanupRoute.Trigger) -> Self {
        switch trigger {
        case let .app(app):
            appSuggestions.first { $0.bundleIDs.contains(app.bundleID) }?.preset ?? .cleanUp
        case let .website(domain):
            websiteSuggestions.first { $0.domains.contains { CleanupRoute.host(domain, isOn: $0) } }?.preset ?? .cleanUp
        }
    }

    private static let appSuggestions: [(preset: Self, bundleIDs: Set<String>)] = [
        (.email, [
            "com.apple.mail", "com.microsoft.Outlook", "com.readdle.SparkDesktop", "com.readdle.smartemail-Mac",
            "com.mimestream.Mimestream", "com.superhuman.electron", "com.freron.MailMate", "it.bloop.airmail2",
        ]),
        (.aiPrompt, [
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "com.apple.dt.Xcode",
            "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
            "com.exafunction.windsurf", "com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex",
        ]),
        (.notes, [
            "com.apple.Notes", "md.obsidian", "notion.id", "net.shinyfrog.bear", "com.agiletortoise.Drafts-OSX",
            "com.culturedcode.ThingsMac",
        ]),
        (.professional, [
            "com.microsoft.Word", "com.apple.iWork.Pages", "com.microsoft.teams2", "com.linear",
            "com.microsoft.Powerpoint", "com.apple.iWork.Keynote",
        ]),
    ]

    private static let websiteSuggestions: [(preset: Self, domains: [String])] = [
        (.email, ["mail.google.com", "outlook.live.com", "outlook.office.com", "mail.proton.me", "app.hey.com"]),
        (.aiPrompt, ["chatgpt.com", "claude.ai", "gemini.google.com", "perplexity.ai", "v0.dev", "lovable.dev", "bolt.new"]),
        (.notes, ["notion.so", "notion.site"]),
        (.professional, ["github.com", "linkedin.com", "docs.google.com", "linear.app", "atlassian.net"]),
    ]
}
