#!/usr/bin/env python3
"""End-to-end checks against real apps, through VibeWand's automation socket.

Start VibeWand with scripts/dev-run.sh first. Each check drives the same entry
points as the hardware and reads the result back from the target app. Nothing
is ever submitted: drafts typed by a check are removed again, pickers are
cancelled, and the automation channel refuses the Return key.

    python3 scripts/e2e-check.py            # every app that is running
    python3 scripts/e2e-check.py claude     # one target: overlay, textedit, codex, claude, harness
"""
import json, os, socket, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCKET = os.environ.get("VIBEWAND_SOCKET", os.path.join(ROOT, "dist/dev/vw.sock"))
APPS = {
    "codex": ("com.openai.codex", "Do anything"),
    "claude": ("com.anthropic.claudefordesktop", "Prompt"),
    "harness": ("com.deepseek.dsh", "发消息"),
}
results = []


def call(**request):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as link:
        link.settimeout(40)
        link.connect(SOCKET)
        link.sendall((json.dumps(request) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = link.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data or b"{}")


def check(name, passed, detail=""):
    results.append(passed)
    print(("PASS  " if passed else "FAIL  ") + name + (f"  ({detail})" if detail and not passed else ""))


def field():
    return call(cmd="field").get("value", "")


def clear_draft():
    call(cmd="key", code=0, flags=["cmd"])  # select all
    call(cmd="key", code=51)                # delete


def overlay():
    start = call(cmd="overlay", visible=True, mode="full")
    compact = call(cmd="overlay", toggle=True)
    full = call(cmd="overlay", toggle=True)
    check("overlay: toggle button keeps its place when collapsing", start["toggle"] == compact["toggle"], f'{start["toggle"]} vs {compact["toggle"]}')
    check("overlay: toggle button keeps its place when expanding", compact["toggle"] == full["toggle"])


def textedit():
    path = os.path.join(tempfile.gettempdir(), "vibewand-e2e.txt")
    with open(path, "w") as handle:
        handle.write("")
    subprocess.run(["open", "-a", "TextEdit", path], check=False)
    time.sleep(1.5)
    call(cmd="activate", bundle="com.apple.TextEdit")
    before = field()
    state = call(cmd="dictate", previews=["端到端", "端到端检查：", "端到端检查：原生输入框"], interval=250, wait=2200)
    check("TextEdit: live dictation writes into a native field", "端到端检查：原生输入框" in field() and before in field(),
          str(state.get("speech")))
    check("TextEdit: uses accessibility writes, not the clipboard", state.get("speech", {}).get("insertion") == "accessibility-live")
    clear_draft()


def assistant(key):
    bundle, composer = APPS[key]
    if not call(cmd="activate", bundle=bundle, settle=1500).get("ok"):
        print(f"SKIP  {key}: not running")
        return
    call(cmd="template", device="vibeKey")

    def focus_composer():
        call(cmd="ui", role="AXTextArea", text=composer, do="focus")
        time.sleep(0.6)

    focus_composer()
    time.sleep(1.2)  # first contact enables web accessibility in Electron apps
    focus_composer()
    state = call(cmd="state")
    check(f"{key}: empty composer keeps the dial scrolling", state.get("scope") == "reading", state.get("scope", ""))

    text = f"端到端检查 {key}（不发送）"
    state = call(cmd="dictate", previews=["端到端", text], interval=300, wait=3000)
    check(f"{key}: dictation reaches the composer", text in field(), str(state.get("speech")))
    clear_draft()
    time.sleep(0.4)
    check(f"{key}: draft removed again", text not in field())

    focus_composer()
    state = call(cmd="tap", control="dial", settle=1600)
    check(f"{key}: chat picker opens", state.get("scope") == "sessions", state.get("mode", ""))
    call(cmd="turn", control="right", count=2, settle=400)
    state = call(cmd="tap", control="escape", settle=900)
    if state.get("scope") == "sessions":  # a filter field may need a second Escape
        call(cmd="key", code=53)
        state = call(cmd="tap", control="escape", settle=900)
    focus_composer()
    check(f"{key}: chat picker cancels without switching", call(cmd="state").get("scope") in ("reading", "editing"))

    state = call(cmd="tap", control="settings", settle=1700)
    check(f"{key}: model / effort picker opens", state.get("scope") in ("models", "efforts"), state.get("mode", ""))
    for _ in range(3):
        if call(cmd="state").get("scope") not in ("models", "efforts"):
            break
        call(cmd="tap", control="escape", settle=800)
    check(f"{key}: model / effort picker cancels", call(cmd="state").get("scope") in ("reading", "editing"))


def main():
    wanted = sys.argv[1:] or ["overlay", "textedit", "codex", "claude", "harness"]
    try:
        ping = call(cmd="ping")
    except OSError:
        sys.exit("VibeWand is not listening; run scripts/dev-run.sh first")
    if not ping.get("trusted"):
        sys.exit("VibeWand has no Accessibility permission")
    for target in wanted:
        if target == "overlay":
            overlay()
        elif target == "textedit":
            textedit()
        elif target in APPS:
            assistant(target)
        else:
            sys.exit(f"unknown target: {target}")
    print(f"\n{sum(results)} of {len(results)} checks passed")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
