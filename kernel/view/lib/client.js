// VibeWand's view of command mode, browser half. Written by hand in the form the harness's own client
// bundles take: one module registered with the page's loader, React and the slot registry from the page.
window.__ModuleLoader__.load({
	id: "vibewand-view",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		const { jsx, jsxs } = require("react/jsx-runtime");
		const react = require("react");

		/** Every command VibeWand sends opens with its name, and so does the title of the conversation it started. */
		const MARK = "VibeWand · ";
		const RECORDING = /^Spoken, (\d+) s\. Recording (\d{8}-\d{6}-[0-9a-f]{6})$/;
		const CONTEXT = /^(\d\d:\d\d) \w{3} \d{4}-\d\d-\d\d(?:\. The user was in (.+?)(?:, window "(.*)")?)?$/;

		/**
		* Read a user message as a command of VibeWand's: the words, where they were said, and the recording kept of them.
		* @param content - the message as the harness holds it.
		* @returns the command, or null for any other message.
		*/
		function command(content) {
			const parts = typeof content === "string" ? [{ type: "text", text: content }] : Array.isArray(content) ? content : [];
			if (parts.length === 0 || parts.some((part) => part.type !== "text")) return null;
			const lines = parts.map((part) => part.text).join("").split("\n");
			if (!lines[0].startsWith(MARK)) return null;
			let match = lines.length > 1 ? RECORDING.exec(lines[lines.length - 1]) : null;
			const recording = match ? { seconds: Number(match[1]), task: match[2] } : null;
			if (match) lines.pop();
			match = lines.length > 1 ? CONTEXT.exec(lines[lines.length - 1]) : null;
			if (match) lines.pop();
			return { words: lines.join("\n").slice(MARK.length), recording, app: match?.[2] ?? "", window: match?.[3] ?? "" };
		}

		/** The page says which language the harness is shown in. */
		const say = (zh, en) => document.documentElement.lang.startsWith("zh") ? zh : en;
		const clock = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;

		function Wand({ size = 14 }) {
			return jsxs("svg", {
				width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": true,
				stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round", strokeLinejoin: "round",
				children: [
					jsx("path", { d: "M2.5 13.5 9.4 6.6" }),
					jsx("path", { d: "M11.6 1.8v2.6M10.3 3.1h2.6M13.4 7.2v1.8M12.5 8.1h1.8M6 2.6v1.4M5.3 3.3h1.4" })
				]
			});
		}

		const accent = "var(--dsw-alias-state-business-primary, #4d6bfe)";
		const quiet = "var(--dsw-alias-label-tertiary, #8a8f98)";

		/** The recording of a spoken command: played from VibeWand's own records through the harness that shows it. */
		function Voice({ task, seconds }) {
			const audio = react.useRef(null);
			const [playing, setPlaying] = react.useState(false);
			const [missing, setMissing] = react.useState(false);
			const [at, setAt] = react.useState(0);
			const length = audio.current?.duration > 0 && Number.isFinite(audio.current.duration) ? audio.current.duration : seconds;
			const toggle = () => {
				const sound = audio.current;
				if (sound === null) return;
				if (sound.paused) sound.play().catch(() => { setMissing(true); });
				else sound.pause();
			};
			return jsxs("div", {
				style: { display: "flex", alignItems: "center", gap: 10, minWidth: 220, paddingBottom: 6 },
				children: [
					jsx("audio", {
						ref: audio, preload: "none", src: `api/vibewand.recording?task=${task}`,
						onPlay: () => { setPlaying(true); },
						onPause: () => { setPlaying(false); },
						onEnded: () => { setPlaying(false); setAt(0); },
						onTimeUpdate: (event) => { setAt(event.currentTarget.currentTime); },
						onError: () => { setMissing(true); setPlaying(false); }
					}),
					jsx("button", {
						type: "button", onClick: toggle, disabled: missing,
						"aria-label": playing ? say("暂停", "Pause") : say("播放原声", "Play the recording"),
						title: missing ? say("录音已不在这台 Mac 上（VibeWand 保留 14 天）", "The recording is no longer on this Mac (VibeWand keeps it for 14 days)") : void 0,
						style: {
							width: 28, height: 28, flex: "none", borderRadius: "50%", border: "none", padding: 0,
							display: "grid", placeItems: "center", cursor: missing ? "default" : "pointer",
							background: missing ? quiet : accent, color: "#fff", opacity: missing ? .5 : 1
						},
						children: jsx("svg", {
							width: 12, height: 12, viewBox: "0 0 12 12", fill: "currentColor", "aria-hidden": true,
							children: playing ? jsx("path", { d: "M2.5 1.5h2.5v9H2.5zM7 1.5h2.5v9H7z" }) : jsx("path", { d: "M3 1.2 10.4 6 3 10.8z" })
						})
					}),
					jsx("div", {
						style: { flex: 1, height: 4, borderRadius: 2, background: "var(--dsw-alias-border-l2, rgba(128,128,128,.35))", overflow: "hidden" },
						children: jsx("div", { style: { width: `${Math.min(100, at / length * 100)}%`, height: "100%", background: accent } })
					}),
					jsx("span", {
						style: { flex: "none", fontVariantNumeric: "tabular-nums", fontSize: "var(--dsh-content-font-size-secondary, 13px)", color: quiet },
						children: missing ? say("录音已清理", "recording gone") : clock(playing || at > 0 ? at : seconds)
					})
				]
			});
		}

		/** A command as the user gave it: what they said, to be heard again when it was spoken, and where they were. */
		function Command({ said, time }) {
			const where = [said.app, said.window].filter((part) => part !== "").join(" · ");
			const when = new Date(time).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
			return jsxs("div", {
				style: { display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 6 },
				children: [
					jsxs("div", {
						style: {
							maxWidth: "min(calc(var(--dsh-chat-content-width, 748px) * .702), 82%)", minWidth: 0,
							background: "var(--dsw-specific-bubble)", borderRadius: "var(--dsw-radius-xl, 20px)", padding: "10px 16px",
							color: "var(--dsw-alias-label-primary)", fontSize: "var(--dsh-content-font-size, 14px)",
							lineHeight: "calc(22px + var(--dsh-content-font-delta, 0px))", whiteSpace: "pre-wrap", overflowWrap: "anywhere"
						},
						children: [said.recording ? jsx(Voice, { ...said.recording }) : null, said.words]
					}),
					jsxs("div", {
						style: { display: "flex", alignItems: "center", gap: 6, paddingRight: 12, color: quiet, fontSize: "var(--dsh-content-font-size-secondary, 13px)" },
						children: [
							jsx("span", { style: { display: "inline-flex", color: accent }, children: jsx(Wand, {}) }),
							jsx("span", { children: [said.recording ? say("VibeWand 语音命令", "VibeWand voice command") : say("VibeWand 命令", "VibeWand command"), where, when].filter((part) => part !== "").join(" · ") })
						]
					})
				]
			});
		}

		/** Whether a conversation is one command mode started: the harness titles it from the opening words of its first command. */
		const started = (props) => props.useSessions((sessions) => sessions.byId[props.sessionId]?.title?.startsWith(MARK) === true);

		function HeaderMark(props) {
			if (!started(props)) return null;
			return jsxs("span", {
				title: say("这段对话是 VibeWand 命令模式的：每条消息是你说的一句命令，模型用 VibeWand 的工具在这台 Mac 上执行。",
					"This conversation belongs to VibeWand's command mode: each message is a command you spoke, carried out on this Mac through VibeWand's tools."),
				style: {
					display: "inline-flex", alignItems: "center", gap: 5, padding: "2px 9px", borderRadius: 999, whiteSpace: "nowrap",
					border: `1px solid ${accent}`, color: accent, fontSize: 12, lineHeight: "18px"
				},
				children: [jsx(Wand, { size: 13 }), say("VibeWand 命令模式", "VibeWand command mode")]
			});
		}

		function RowMark(props) {
			if (!started(props)) return null;
			return jsx("span", { style: { display: "inline-flex", marginRight: 4, color: accent }, children: jsx(Wand, {}) });
		}

		/** Required service: the UI slot registry. */
		const inject = ["slots"];
		/**
		* Mark the conversations command mode started, and show its commands as what they are.
		* @param ctx - Client root context.
		*/
		function apply(ctx) {
			ctx.slots.inject("conversation.session.header.utilities", () => ctx.slots.register({
				name: "conversation.session.header.utilities", id: "vibewand-view"
			}, HeaderMark));
			ctx.slots.inject("sidebar.session.row.leading", () => ctx.slots.register({
				name: "sidebar.session.row.leading", id: "vibewand-view"
			}, RowMark));
			// The chat's own renderer of a user message keeps every message that is not a command of VibeWand's:
			// this one stands before it, and hands those on with what it was given.
			ctx.slots.inject("conversation.chat.node", () => {
				function UserNode(props) {
					const said = react.useMemo(() => command(props.node.data.content), [props.node.data.content]);
					if (said !== null) return jsx(Command, { said, time: props.node.data.time });
					const chat = ctx.slots.entries("conversation.chat.node").find((entry) => entry.options.key === "user" && entry.component !== UserNode);
					return chat === void 0 ? null : jsx(chat.component, { ...props });
				}
				return ctx.slots.register({ name: "conversation.chat.node", key: "user", priority: -1, locale: "chat" }, UserNode);
			});
		}
		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});
