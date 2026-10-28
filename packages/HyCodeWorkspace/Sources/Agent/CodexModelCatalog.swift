import Foundation

/// Offline provider metadata, reviewed against DeepSeek's official Codex guide
/// on 2026-10-26. No provider script, global catalog or remote instruction is loaded.
public enum CodexModelCatalog {
    public static let deepSeekModels = ["deepseek-v4-pro", "deepseek-flash"]
    public static let deepSeekContextWindow = 1_048_576

    public static func deepSeekData() throws -> Data {
        let models: [[String: Any]] = deepSeekModels.enumerated().map { index, slug in
            [
                "slug": slug, "display_name": slug == "deepseek-flash" ? "DeepSeek Flash" : "DeepSeek V4 Pro",
                "description": "DeepSeek Responses API", "default_reasoning_level": "max",
                "supported_reasoning_levels": [
                    ["effort": "none", "description": "关闭思考"],
                    ["effort": "low", "description": "低"], ["effort": "high", "description": "高"],
                    ["effort": "max", "description": "最高"],
                ],
                "shell_type": "unified_exec", "visibility": "list", "supported_in_api": true,
                "priority": index, "support_verbosity": true, "default_verbosity": "low",
                "apply_patch_tool_type": "freeform", "default_reasoning_summary": "none",
                "truncation_policy": ["mode": "tokens", "limit": 10_000],
                "context_window": deepSeekContextWindow, "max_context_window": deepSeekContextWindow,
                "effective_context_window_percent": 95, "experimental_supported_tools": [],
                "input_modalities": slug == "deepseek-flash" ? ["text", "image"] : ["text"],
                "supports_image_detail_original": slug == "deepseek-flash",
                "include_apps_usage_instructions": false, "include_skills_usage_instructions": false,
                "include_plugin_usage_instructions": false, "use_responses_lite": false,
                "model_messages": [
                    "instructions_template": """
                    You are a coding agent running inside HyCode, using a model provided by DeepSeek.
                    Work toward the user's requested outcome with the available tools. Follow applicable
                    AGENTS.md files and the user's instructions. Inspect relevant source before editing,
                    preserve unrelated changes, and explain the result and verification limits. Do not
                    claim a tool ran or a change was verified without evidence. Use the user's language.
                    Ask for clarification only when it is needed to proceed.
                    Reply in concise, natural prose. Do not turn greetings into a catalog of abilities.
                    Avoid decorative emoji and section labels unless requested or useful for the task.
                    Describe only tools and app features actually available in this session. HyCode's
                    current integration has project reading, editing, command execution and chat;
                    it has no dedicated image-generation UI, voice UI, skill/plugin marketplace or
                    autonomous cross-chat controls. Do not present those as installed capabilities.
                    """
                ],
            ]
        }
        return try JSONSerialization.data(withJSONObject: ["models": models], options: [.sortedKeys])
    }

    static func prepare(home: URL, configuration: CodexConfiguration) throws {
        guard configuration.isDeepSeekModel else { return }
        let destination = home.appendingPathComponent("models.json")
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw LanguageServiceFailure("Codex 模型目录不是普通文件")
            }
        }
        try deepSeekData().write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
