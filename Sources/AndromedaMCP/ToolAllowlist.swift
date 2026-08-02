import Foundation

/// Starter slim allowlists for Slack/GitHub MCP tools (option-1 prep on option-2 path).
///
/// Pass-through mode still proxies only names on these lists so guest discovery
/// stays focused while host auth injection remains the MVP win.
public struct ToolAllowlist: Sendable, Equatable {
    public let capability: MCPCapabilityID
    public let allowedTools: Set<String>

    public init(capability: MCPCapabilityID, allowedTools: Set<String>) {
        self.capability = capability
        self.allowedTools = allowedTools
    }

    public func allows(_ toolName: String) -> Bool {
        allowedTools.contains(toolName)
    }

    public static let slackDefault = ToolAllowlist(
        capability: .slackProxy,
        allowedTools: [
            "slack_list_channels",
            "slack_post_message",
            "slack_reply_to_thread",
            "slack_add_reaction",
            "slack_get_channel_history",
            "slack_get_thread_replies",
            "slack_get_users",
            "slack_get_user_profile",
            // Common alternate names from community Slack MCP servers:
            "conversations_list",
            "conversations_history",
            "chat_postMessage",
            "reactions_add",
            "users_info",
        ]
    )

    public static let githubDefault = ToolAllowlist(
        capability: .githubProxy,
        allowedTools: [
            "create_or_update_file",
            "push_files",
            "search_repositories",
            "create_repository",
            "get_file_contents",
            "create_issue",
            "create_pull_request",
            "fork_repository",
            "create_branch",
            "list_commits",
            "list_issues",
            "update_issue",
            "add_issue_comment",
            "search_code",
            "search_issues",
            "list_pull_requests",
            "get_pull_request",
            "get_pull_request_files",
            "create_pull_request_review",
            "merge_pull_request",
            "get_issue",
        ]
    )

    public static let defaults: [MCPCapabilityID: ToolAllowlist] = [
        .slackProxy: .slackDefault,
        .githubProxy: .githubDefault,
    ]
}

/// Maps a guest-visible tool name to the owning capability curtain.
public enum ToolCapabilityRouter {
    /// Prefer explicit prefixes, then fall back to known allowlist membership.
    public static func capability(for toolName: String) -> MCPCapabilityID? {
        let lower = toolName.lowercased()
        if lower.hasPrefix("slack_") || lower.hasPrefix("conversations_") || lower.hasPrefix("chat_")
            || lower.hasPrefix("reactions_") || lower.hasPrefix("users_")
        {
            return .slackProxy
        }
        if lower.hasPrefix("github_") {
            return .githubProxy
        }
        for (capability, allowlist) in ToolAllowlist.defaults {
            if allowlist.allows(toolName) {
                return capability
            }
        }
        return nil
    }
}
