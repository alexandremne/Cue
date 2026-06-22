# Cue

**Cue is a small, polished iOS task manager driven by an in-app AI agent.** You type a plain-language request — *“schedule a call with Marko next Tuesday at 3pm”*, *“move it to Wednesday”*, *“mark the Marko call done”* — and the agent turns it into a real action inside the app via Anthropic tool calling, always pausing for a one-tap **confirmation** before it changes anything. It’s a portfolio/demo piece built to show native iOS craft, a genuine agentic loop (the model picks among four tools, it doesn’t just chat), and senior judgment: a human-in-the-loop guardrail plus graceful handling of ambiguity, errors, and offline state.

## Demo

📹 **Screen recording:** [`docs/demo/cue-demo.mov`](docs/demo/cue-demo.mov) — the full [demo script](#demo-script) driven end to end against the live Anthropic API.

The flow below was captured automatically by the `CueUITests` UI test (it types each request, waits for the model, and confirms each action). All stills live in [`docs/demo/`](docs/demo).

| Empty state | Confirmation card | Two tasks added | Completed |
| --- | --- | --- | --- |
| ![Empty](docs/demo/01-empty-state.png) | ![Confirm add](docs/demo/02-confirm-add.png) | ![Two tasks](docs/demo/08-tasks-added.png) | ![Completed](docs/demo/10-completed.png) |

| Reschedule | Multi-action | Clarifying question | Dark mode |
| --- | --- | --- | --- |
| ![Reschedule](docs/demo/04-confirm-reschedule.png) | ![Multi](docs/demo/06-confirm-multi.png) | ![Clarify](docs/demo/11-clarifying-question.png) | ![Dark](docs/demo/12-dark-mode.png) |

---

## Tech stack

- **iOS 17+, iPhone, portrait.** Swift 5.9+ with full `async/await` (Swift 6 language mode, builds clean under strict concurrency).
- **SwiftUI** only (UIKit touched in exactly one place — haptics).
- **SwiftData** (`@Model`) for local persistence.
- **MVVM + a thin service layer**: Views → `AgentService` → Services (`AnthropicClient`, `ToolExecutor`) → SwiftData store.
- **No dependencies, no SPM packages.** Networking is plain `URLSession`.
- **Model provider:** Anthropic Messages API with tool use, isolated behind the `AnthropicClient` protocol so the provider can be swapped or mocked. Default model `claude-sonnet-4-6` (configurable; `claude-haiku-4-5` is a fine faster alternative).

---

## Setup — add your API key

The API key is **never hardcoded and never committed**. It’s read from an xcconfig that is gitignored, surfaced into `Info.plist` at build time, and read at runtime (`AppConfig`).

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# then open Config/Secrets.xcconfig and paste your key:
#   ANTHROPIC_API_KEY = sk-ant-...
```

- `Config/Secrets.xcconfig` is listed in `.gitignore` — it will not be committed.
- Get a key at <https://console.anthropic.com/>.
- If no key is set, the app still launches and shows a friendly in-app setup hint instead of crashing.
- For previews and tests, the key can also come from the `ANTHROPIC_API_KEY` environment variable.

## Run

```sh
open Cue.xcodeproj
# select an iPhone simulator (iOS 17+) and press ⌘R
```

Or from the command line:

```sh
xcodebuild build -scheme Cue -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme Cue -destination 'platform=iOS Simulator,name=iPhone 17'
```

To replay the recorded acceptance demo (drives the live agent through the whole [demo script](#demo-script) and captures a screenshot per step — requires a configured key):

```sh
xcodebuild test -scheme CueUITests -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## The agent design (four tools)

Each turn, the app sends the model: the running conversation, the four tool definitions, and a **system prompt** containing the agent’s role and rules, the **current date / time / timezone**, and a compact JSON snapshot of every task (`id`, `title`, `datetime`, `status`). The model replies with either a `tool_use` block or plain text.

The four tools are:

| Tool | What it does |
| --- | --- |
| `create_task` | Add a task (`title` required; optional `datetime`, `notes`). |
| `update_task` | Edit a task — reschedule or retitle (targets a `task_id`). |
| `complete_task` | Mark a task done (`task_id`). |
| `delete_task` | Delete a task (`task_id`). |

The loop is human-in-the-loop: a `tool_use` block is **not executed immediately**. The app renders a **confirmation card** summarizing the action in plain language. On **Confirm**, `ToolExecutor` applies the change to the SwiftData store and a `tool_result` is sent back so the model can produce a short natural confirmation (“Done — added ‘Call with Marko’ for Tue 3:00 PM.”). On **Cancel**, the model is told the user declined and acknowledges. Context is preserved across turns, so *“move it to Wednesday”* resolves against the previous task. The model maps natural references (“the Marko call”) to an `id` using the snapshot — and when zero or several tasks match, it asks a clarifying question instead of guessing. Relative dates (“next Tuesday at 3”) resolve to absolute ISO 8601 because the system prompt carries the current date; a dated task with no time defaults to 9:00 AM, surfaced on the card so it can be adjusted.

The wire contract (`x-api-key` / `anthropic-version` headers, `tool_use` / `tool_result` content-block shapes) lives in `Networking/APIModels.swift` and is exercised by the `APIModelsTests`.

---

## Demo script

This is the end-to-end sequence the app is built to pass (and the one to screen-record):

1. Launch on the empty state.
2. *“schedule a call with Marko next Tuesday at 3pm”* → confirmation card **Add — Call with Marko, Tue [date] 3:00 PM** → Confirm → the row animates in and the agent confirms.
3. *“actually move it to Wednesday same time”* → **Reschedule** to Wed 3:00 PM referencing the same task → Confirm → the row updates in place.
4. *“add buy groceries and finish the report by Friday”* → two tasks created (or confirmed); “finish the report” carries Friday’s date.
5. *“mark the Marko call done”* → **Complete** confirmation → Confirm → the row moves to Completed, struck through.
6. Something ambiguous, e.g. *“move my meeting”* with no meeting → the agent asks a clarifying question instead of acting.
7. Toggle the device to dark mode mid-demo → everything stays clean and legible.

Plus: light/dark both first-class, Dynamic Type up to accessibility sizes without breakage, VoiceOver labels on every control, and graceful airplane-mode handling (a non-blocking “I couldn’t reach the model — check your connection” message with input preserved).

---

## Project structure

```
Cue/
├── App/            CueApp.swift — @main, SwiftData container
├── Models/         TaskItem.swift (@Model), ChatMessage.swift
├── Agent/          AgentService, ToolExecutor, ToolDefinitions, PendingAction
├── Networking/     AnthropicClient (protocol + URLSession impl), APIModels, APIError
├── Views/          HomeView, TaskRowView, ComposerView, ConfirmationCardView,
│                   AssistantBubbleView, EmptyStateView
├── Support/        Haptics, DateParsing, Theme, PreviewSupport (DEBUG)
└── Resources/      Assets.xcassets (AccentColor light/dark, AppIcon)
CueTests/           ToolExecutor, DateParsing, APIModels (Codable), and live-API tests
CueUITests/         End-to-end UI test that drives + captures the demo
Config/             Config.xcconfig, Secrets.example.xcconfig, Info.plist
docs/demo/          Recorded demo video + per-step screenshots
```

> **Note on naming:** the persisted model is `TaskItem`, not `Task`, to avoid shadowing Swift Concurrency’s `Task`. The field set matches the spec exactly.

---

## Tests

Unit tests cover the parts worth locking down:

- **`ToolExecutorTests`** — each of the four tools mutates the store correctly, plus the guardrails (missing title, missing/unknown `task_id`, no-op update).
- **`DateParsingTests`** — relative/ISO parsing, the 9:00 AM date-only default, and the ISO round-trip used in the snapshot.
- **`APIModelsTests`** — decoding a representative `tool_use` response, encoding a `tool_result`, snake-case request keys, and graceful handling of unknown content blocks.
- **`AgentLiveTests`** — an opt-in (`CUE_LIVE=1`) live check that sends a real request and asserts the model returns a `create_task` tool call; skipped by default.
- **`CueUITests`** — an end-to-end UI test (separate `CueUITests` scheme) that drives the full demo script against the live agent and captures the screenshots in `docs/demo/`.

> The project also has a `docs/demo/cue-demo.mov` screen recording and per-step PNGs produced by `CueUITests`.
