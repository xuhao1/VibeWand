import Foundation

/// What the speaker tends to say: terms to spell correctly and a subject hint.
/// Recognisers and the polisher receive it as bias, never as instructions.
public struct SpeechVocabulary: Codable, Equatable {
    /// Free-form subject, e.g. "新能源汽车、电池热管理".
    public var domain = ""
    public var terms: [String] = []
    /// Includes the built-in software-development terms.
    public var computing = true
    public init() {}

    /// User terms first, for recognisers that only honour the head of a list.
    public var allTerms: [String] { terms + (computing ? Self.computingTerms : []) }

    /// Bias text for recognisers that take free-form context. User terms come
    /// last because Whisper-style prompts keep only their tail.
    public var context: String? {
        let lines = [computing ? Self.computingTerms.joined(separator: ", ") : "", domain, terms.joined(separator: ", ")]
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// One term per line; commas and enumeration marks also separate terms.
    public static func terms(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n,，、;；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func validate() throws {
        // Qwen accepts 10,000 tokens of context; an oversized list would fail every session.
        guard domain.count + terms.reduce(0, { $0 + $1.count + 2 }) <= 4000 else { throw SpeechInputError.invalidConfiguration }
    }

    public static let computingTerms = """
    Claude, Claude Code, Anthropic, Codex, OpenAI, ChatGPT, GPT, Gemini, DeepSeek, Qwen, Cursor, Copilot, Ollama, \
    Hugging Face, LLM, RAG, MCP, agent, prompt, token, embedding, fine-tune, checkpoint, benchmark, \
    GitHub, GitLab, Git, commit, push, pull request, PR, merge, rebase, branch, diff, issue, repo, fork, stash, cherry-pick, CI, \
    Python, Swift, SwiftUI, Objective-C, TypeScript, JavaScript, Rust, Go, Java, Kotlin, C++, SQL, HTML, CSS, JSON, YAML, Markdown, regex, \
    Node.js, npm, pnpm, pip, conda, Docker, Kubernetes, Linux, macOS, Ubuntu, Xcode, VS Code, Vim, tmux, bash, zsh, Homebrew, \
    API, SDK, CLI, GUI, UI, UX, HTTP, HTTPS, WebSocket, SSH, URL, DNS, TCP, OAuth, JWT, async, await, callback, closure, thread, mutex, \
    cache, queue, hash, payload, schema, endpoint, middleware, frontend, backend, database, Redis, PostgreSQL, MySQL, SQLite, MongoDB, \
    debug, bug, log, deploy, build, release, refactor, lint, unit test, mock, timeout, rollback, hotfix, code review, \
    React, Vue, Next.js, Tailwind, PyTorch, TensorFlow, NumPy, pandas, CUDA, GPU, CPU, ROS, \
    VibeWand, VibeKey, DualSense, Typeless, WorkBuddy
    """.components(separatedBy: ", ")
}
