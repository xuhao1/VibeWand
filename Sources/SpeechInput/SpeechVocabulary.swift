import Foundation

/// What the speaker tends to say: terms to spell correctly and a subject hint.
/// Recognisers and models receive it as bias, never as instructions.
public struct SpeechVocabulary: Codable, Equatable {
    /// Free-form subject, e.g. "新能源汽车、电池热管理".
    public var domain = ""
    public var terms: [String] = []
    /// Includes the default AI-coding terms. The stored key predates that list.
    public var computing = true
    public init() {}

    /// User terms first, for recognisers that only honour the head of a list.
    public var allTerms: [String] { terms + (computing ? Self.defaultTerms : []) }

    /// Bias text for recognisers that take free-form context. Whisper-style
    /// prompts keep only their tail, so user terms come last and the default
    /// terms run from least to most important.
    public var context: String? {
        let lines = [computing ? Self.defaultTerms.reversed().joined(separator: ", ") : "", domain, terms.joined(separator: ", ")]
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The same bias as lines of a model's system prompt; empty without any.
    public var guidance: String {
        var text = ""
        let subjects = [computing ? Self.defaultSubject : "", domain].filter { !$0.isEmpty }
        if !subjects.isEmpty {
            text += "说话者经常谈论：\(subjects.joined(separator: "；"))。同音或近音的词按这些领域的常用写法写，技术名词使用通行的英文拼写。\n"
        }
        if !allTerms.isEmpty {
            text += "说话者的专用词汇：\(allTerms.joined(separator: "、"))。与它们同音、近音或拼写相近的词按这里的写法写；没有说到的不要添加。\n"
        }
        return text
    }

    /// One term per line; commas and enumeration marks also separate terms.
    public static func terms(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n,，、;；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func validate() throws {
        // An oversized list would lengthen every request's prompt and can exceed a provider's limit.
        guard domain.count + terms.reduce(0, { $0 + $1.count + 2 }) <= 4000 else { throw SpeechInputError.invalidConfiguration }
    }

    public static let defaultSubject = "AI 编程、软件开发"

    /// The project default: what people say while programming with AI agents,
    /// most important first. Models and coding tools, agent concepts, Git,
    /// languages, tooling, engineering, frameworks, then Chinese terms.
    public static let defaultTerms = """
    Claude, Claude Code, Anthropic, Codex, OpenAI, ChatGPT, GPT, Gemini, Gemini CLI, DeepSeek, Qwen, Kimi, GLM, Grok, Llama, Mistral, \
    Opus, Sonnet, Haiku, Fable, Cursor, Copilot, Windsurf, Cline, Aider, Trae, Kiro, Qoder, CodeBuddy, WorkBuddy, Antigravity, \
    OpenCode, OpenClaw, Devin, Replit, Lovable, Zed, Warp, Ghostty, iTerm, OpenRouter, Ollama, LM Studio, vLLM, Hugging Face, ModelScope, \
    DashScope, LangChain, LangGraph, LlamaIndex, Dify, VibeWand, VibeKey, DualSense, Typeless, \
    LLM, agent, subagent, agentic, multi-agent, MCP, MCP server, tool use, tool call, function calling, skill, hook, plugin, \
    slash command, plan mode, system prompt, prompt, prompt injection, prompt caching, context, context window, token, compact, \
    CLAUDE.md, AGENTS.md, vibe coding, RAG, embedding, fine-tune, LoRA, checkpoint, inference, reasoning, thinking, hallucination, \
    eval, benchmark, SWE-bench, streaming, multimodal, temperature, rate limit, API key, structured output, guardrail, jailbreak, \
    sandbox, worktree, harness, workflow, pipeline, transformer, tokenizer, quantization, distillation, \
    GitHub, GitLab, Git, commit, push, pull request, PR, merge, rebase, branch, checkout, diff, issue, repo, fork, stash, \
    cherry-pick, revert, tag, release, changelog, CI, CD, GitHub Actions, code review, \
    Python, Swift, SwiftUI, Objective-C, TypeScript, JavaScript, Rust, Go, Java, Kotlin, C++, SQL, HTML, CSS, JSON, YAML, TOML, \
    Markdown, regex, \
    Node.js, npm, pnpm, Bun, pip, uv, conda, Docker, Kubernetes, Linux, macOS, Ubuntu, WSL, Xcode, VS Code, JetBrains, Vim, Neovim, \
    tmux, bash, zsh, Homebrew, Vercel, Cloudflare, Supabase, AWS, \
    API, SDK, CLI, GUI, UI, UX, HTTP, HTTPS, WebSocket, SSE, SSH, URL, DNS, TCP, OAuth, JWT, async, await, callback, closure, thread, \
    mutex, cache, queue, hash, payload, schema, endpoint, middleware, frontend, backend, database, Redis, PostgreSQL, MySQL, SQLite, \
    MongoDB, debug, bug, log, deploy, build, refactor, lint, unit test, mock, timeout, rollback, hotfix, stack trace, localhost, \
    React, Vue, Next.js, Tailwind, Vite, FastAPI, Django, pytest, PyTorch, TensorFlow, NumPy, pandas, Jupyter, CUDA, GPU, CPU, ROS, \
    大模型, 智能体, 提示词, 上下文, 微调, 幻觉, 多模态, 通义千问, 豆包, 智谱, 百炼
    """.components(separatedBy: ", ")
}
