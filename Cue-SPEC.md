# Cue — Product Specification

> **Build target:** A small, production-quality iOS app that demonstrates an in-app AI agent which turns natural language into real actions via function calling, with a human-in-the-loop confirmation step. Intended as a portfolio/demo piece — it must *look* polished and *work* flawlessly, but it is not an App Store release.

> **Instruction to the implementer (Claude Code):** Build the complete, working Xcode project from this spec. Follow current Anthropic API documentation for the exact Messages API tool-use wire format — the contract below is authoritative for *behavior*, but confirm field names against live docs before finalizing the networking layer. Do not hardcode any secret. Produce clean, documented, testable Swift. Deliver something that compiles and runs on first build.

---

## 1. Goal & context

Cue lets the user type a plain-language request ("schedule a call with Marko Tuesday at 3pm", "move it to Wednesday", "mark the call done") and an AI agent performs the corresponding action inside the app. The point of the demo is to show three things at once:

1. Native, refined iOS craft (SwiftUI, smooth, HIG-aligned).
2. A real agentic loop — the model selects among multiple tools, not just chats.
3. Senior judgment — a confirmation/guardrail step and graceful handling of ambiguity, errors, and offline state.

The recorded demo (see §12) is the actual deliverable that goes into a portfolio. The app must make the "it understood me and *did* it" moment obvious and visually satisfying.

---

## 2. Scope

**In scope**
- Single-screen task/agenda manager driven by a conversational agent.
- Four agent tools: create, update, complete, delete a task.
- Human-in-the-loop confirmation before any mutating action.
- Clarifying questions when the request is ambiguous.
- Local persistence, full light/dark mode, accessibility, subtle animation + haptics.

**Out of scope (do not build)**
- Authentication, accounts, multi-user, sync, backend of any kind.
- Push notifications, calendar/EventKit integration, widgets.
- App Store metadata, onboarding flows, analytics.
- Any secret committed to the repo.

---

## 3. Tech stack & constraints

- **Platform:** iOS 17.0+. iPhone only (portrait). 
- **Language:** Swift 5.9+, fully `async/await`. No completion-handler APIs in new code.
- **UI:** SwiftUI only. No UIKit except where unavoidable (e.g. haptics).
- **Architecture:** MVVM + a thin service layer. Clear separation: Views ⟶ ViewModel ⟶ Services (Agent, API client, ToolExecutor) ⟶ Store.
- **Persistence:** SwiftData (`@Model`). 
- **Dependencies:** None. No SPM packages. Networking via `URLSession`. 
- **Model provider:** Anthropic Messages API with tool use. Default model `claude-sonnet-4-6` (configurable; `claude-haiku-4-5` acceptable as a faster alternative). The client must be isolated behind a protocol so the provider can be swapped.
- **Concurrency/state:** ViewModels are `@MainActor`, `@Observable` (Observation framework). Networking off the main actor.

---

## 4. Agent behavior

### 4.1 Interaction model
A persistent composer at the bottom of the screen reads: *"Ask Cue to add, change, or complete anything…"*. The user submits free text. The agent processes it and either (a) proposes an action for confirmation, or (b) asks a short clarifying question, or (c) replies conversationally if no action is needed.

### 4.2 The loop
Each turn:
1. The app builds the request: the running conversation history + a **system prompt** that includes (a) the agent's role and rules, (b) the **current date, time, and timezone**, and (c) a compact JSON snapshot of all current tasks (`id`, `title`, `datetime`, `status`).
2. The app sends the message with the four tool definitions (§5).
3. Model responds. Possible outcomes:
   - **`tool_use` block** → the agent wants to mutate state. The app does **not** execute immediately. It renders a **confirmation card** (§8.4) summarizing the action in plain language. Execution is paused awaiting the user.
   - **Text only** → display as the agent's message (e.g. a clarifying question or a conversational reply). No mutation.
4. On **Confirm**, the app executes the tool via `ToolExecutor`, mutates the SwiftData store, then sends a `tool_result` back to the model to let it produce a short natural confirmation ("Done — added 'Call with Marko' for Tue 3:00 PM."). On **Cancel**, the app sends a `tool_result` indicating the user declined, and the agent acknowledges.
5. Context is preserved across turns so "move it to Wednesday" resolves against the previous action.

### 4.3 Task resolution
Mutating tools target an existing task by `task_id`. The model maps natural references ("the Marko call") to an `id` using the task snapshot in context. If **zero or multiple** plausible matches exist, the model must **not** guess — it asks a clarifying question instead (e.g. "You have two calls on Tuesday — the one with Marko or with Ana?").

### 4.4 Date/time
The model returns datetimes as ISO 8601 strings. Because the system prompt carries the current date/time + timezone, relative expressions ("tomorrow", "next Tuesday at 3") must resolve to absolute datetimes. The app parses ISO 8601 → `Date`. If the model omits a time for a dated task, default to 9:00 AM local and surface that in the confirmation card so the user can adjust.

---

## 5. Tool contract (function calling)

Four tools. Each `input_schema` is JSON Schema. Descriptions are written *for the model* — keep them in the implementation verbatim or close.

### `create_task`
Creates a new task. 
- `title` (string, **required**) — short imperative title.
- `datetime` (string, optional) — ISO 8601 local datetime. Omit if the user gave no date.
- `notes` (string, optional).

### `update_task`
Edits an existing task (covers rescheduling and retitling). 
- `task_id` (string, **required**) — id from the provided task snapshot.
- `title` (string, optional)
- `datetime` (string, optional) — ISO 8601.
- `notes` (string, optional).
At least one of `title`/`datetime`/`notes` must be present.

### `complete_task`
Marks a task complete. 
- `task_id` (string, **required**).

### `delete_task`
Deletes a task. 
- `task_id` (string, **required**).

**Rules baked into the system prompt:**
- Prefer a single tool call per user turn. Only chain if the user clearly asked for multiple actions.
- Never invent a `task_id` — only use ids present in the snapshot. If unsure which task, ask.
- For destructive actions (`delete_task`), the confirmation card copy must be unambiguous.

---

## 6. Data model

```swift
@Model
final class Task {
    var id: UUID
    var title: String
    var datetime: Date?          // nil = no scheduled time
    var notes: String?
    var isComplete: Bool
    var createdAt: Date
}
```

A separate, non-persisted `ChatMessage` value type drives the conversation UI: `id`, `role` (`.user` / `.assistant`), `text`, optional `pendingAction` payload, `timestamp`.

---

## 7. Anthropic API integration

- **Endpoint:** Messages API. Send `model`, `max_tokens`, `system`, `messages`, and `tools`.
- **Tools:** array of `{ name, description, input_schema }` per §5.
- **Assistant tool use:** when the response contains a `tool_use` content block, capture its `id`, `name`, and `input`. Hold it pending confirmation.
- **Returning results:** after the user confirms/cancels and the app executes, append a `user` message containing a `tool_result` block referencing the original `tool_use_id`, with a short content string describing the outcome (e.g. `"created task <uuid>"` or `"user cancelled"`). Then call the API again to get the agent's closing line.
- **System prompt** must include: role + rules (§4, §5), current ISO 8601 datetime and timezone identifier, and the compact tasks snapshot JSON.
- **Model:** `claude-sonnet-4-6` default, injected via config.
- **Networking:** `URLSession`, `async/await`, typed `Codable` request/response models, explicit error enum. No force-unwraps. Timeouts set. 

> Confirm exact header names, version header, and block shapes against current Anthropic API docs at build time.

---

## 8. UI / UX specification

The bar is: it should look like something a senior iOS engineer shipped. Restrained, native, confident. No clutter, generous whitespace, one accent color, motion that feels physical.

### 8.1 Design system
- **Typography:** system font (SF). Use semantic text styles (`.largeTitle`, `.headline`, `.body`, `.subheadline`, `.caption`) so Dynamic Type works. Never hardcode point sizes for body text.
- **Accent color:** a single calm indigo/violet accent defined in the asset catalog with light + dark variants. Everything interactive uses it; nothing else competes.
- **Spacing scale:** 4 / 8 / 12 / 16 / 24 / 32. Screen horizontal padding 16.
- **Corner radius:** 12 for cards, 16 for the composer and confirmation card, continuous (`.rounded(...). continuous`).
- **Surfaces:** use system materials (`.regularMaterial`) for the composer and confirmation card so they sit naturally over content. System grouped background for the screen.
- **Iconography:** SF Symbols only. 
- **Dark mode:** mandatory and first-class. Verify every surface and text color in both modes.

### 8.2 Screen layout (single screen)
- **Nav bar:** large title "Cue". Trailing toolbar item: a subtle "clear conversation" button (does not delete tasks).
- **Content area:** the task list. Each row: leading completion circle (tap to toggle), title (`.body`), datetime as a soft `.caption` pill if present, trailing chevron-free. Completed tasks: title struck through + dimmed, sorted below active. Swipe actions: complete / delete. Sectioning optional (Today / Upcoming / No date) — implement if clean.
- **Empty state:** centered, friendly: a single SF Symbol, a line like "Nothing yet. Ask Cue below to add your first task." 
- **Composer (pinned bottom):** material background, rounded, a multiline-capable text field with the placeholder, and a send button (filled accent circle with `arrow.up`). Disabled when empty or while a request is in flight.

### 8.3 Agent activity indicator
While a request is in flight, show a tasteful inline "thinking" indicator near the composer — three pulsing dots or an animated shimmer on a slim assistant bubble. Never a blocking spinner over the whole screen.

### 8.4 Confirmation card (the centerpiece)
When the agent proposes an action, animate a card up from above the composer (spring). It contains:
- A one-line plain-language summary of the action, with the parsed details rendered as editable-looking fields where sensible (title, date/time). For the demo, fields can be read-only display + an "Edit" affordance that drops the text back into the composer; full inline editing is a nice-to-have, not required.
- Action verb made explicit: "Add", "Reschedule", "Complete", "Delete". Delete uses destructive (red) styling.
- Two buttons: **Confirm** (filled accent) and **Cancel** (plain). 
- On Confirm: success haptic (`.success`), the card collapses, and the corresponding row animates into/updates in the list with a smooth transition. A brief agent confirmation line appears, then settles.
- On Cancel: light haptic, card dismisses, agent acknowledges.

### 8.5 Clarifying questions
Rendered as an assistant message bubble above the composer; the composer stays focused so the user can answer immediately. The conversation thread (last few turns) is visible and scrollable above the task list when active, or as a compact overlay — choose the cleaner of the two and keep it consistent.

### 8.6 Motion & feel
- Spring animations for card present/dismiss and list insertion (`.snappy` / `.bouncy` interpolations, short durations).
- Haptics: `.success` on confirm-execute, `.light`/selection on toggles and cancel.
- Respect `Reduce Motion`.

### 8.7 Accessibility
- Full Dynamic Type up to accessibility sizes without layout breakage.
- VoiceOver labels on all controls (completion toggle states, send button, confirm/cancel, swipe actions).
- Contrast verified in both modes.

---

## 9. Architecture & file structure

```
Cue/
├── App/
│   └── CueApp.swift                 // @main, SwiftData ModelContainer setup
├── Models/
│   ├── Task.swift                   // @Model
│   └── ChatMessage.swift            // value type for conversation
├── Agent/
│   ├── AgentService.swift           // orchestrates the loop, holds conversation state (@MainActor, @Observable)
│   ├── ToolExecutor.swift           // applies create/update/complete/delete to the store
│   ├── ToolDefinitions.swift        // the four tool schemas + system-prompt builder
│   └── PendingAction.swift          // model of an awaiting-confirmation tool call
├── Networking/
│   ├── AnthropicClient.swift        // protocol + concrete URLSession impl
│   ├── APIModels.swift              // Codable request/response, content blocks, tool_use/tool_result
│   └── APIError.swift
├── Views/
│   ├── HomeView.swift               // list + composer + thread + confirmation card host
│   ├── TaskRowView.swift
│   ├── ComposerView.swift
│   ├── ConfirmationCardView.swift
│   ├── AssistantBubbleView.swift
│   └── EmptyStateView.swift
├── Support/
│   ├── Haptics.swift
│   ├── DateParsing.swift            // ISO8601 <-> Date, friendly formatting
│   └── Theme.swift                  // colors, spacing, radii constants
├── Resources/
│   └── Assets.xcassets              // AccentColor (light/dark), app icon placeholder
└── Config/
    └── Secrets.example.xcconfig     // template; real Secrets.xcconfig is gitignored
```

Provide SwiftUI `#Preview`s for every view, including loading, empty, populated, confirmation-visible, and error states.

---

## 10. Error handling & edge cases

- **No network / request failure:** non-blocking inline assistant message ("I couldn't reach the model — check your connection and try again."), composer re-enabled, input preserved. No crash, no data loss.
- **Malformed/unparseable tool input:** do not mutate; surface a graceful assistant message and let the user rephrase.
- **Ambiguous task reference:** agent asks rather than guessing (§4.3).
- **Empty or whitespace input:** send disabled.
- **Rapid sends:** ignore new sends while a request is in flight (composer disabled).
- **Date with no time:** default 9:00 AM, shown in confirmation for adjustment.
- **Missing API key at launch:** show a clear, friendly setup message in-app pointing to the config step — never crash.

---

## 11. Configuration & secrets

- The API key is **never** hardcoded and **never** committed.
- Read it from `Secrets.xcconfig` (gitignored), surfaced into `Info.plist` and read at runtime, or from the environment for previews.
- Commit `Secrets.example.xcconfig` with `ANTHROPIC_API_KEY = ` empty as a template.
- Add `Secrets.xcconfig` to `.gitignore`.
- README documents the one-time setup.

---

## 12. Acceptance criteria — definition of done

The build is done when it compiles and runs on first try **and** passes this exact demo script end to end (this is the sequence that will be screen-recorded):

1. Launch on empty state.
2. Type: *"schedule a call with Marko next Tuesday at 3pm"* → confirmation card shows "Add — Call with Marko, Tue [date] 3:00 PM" → Confirm → row animates in, agent confirms.
3. Type: *"actually move it to Wednesday same time"* → confirmation shows a **Reschedule** to Wed 3:00 PM referencing the same task → Confirm → row updates in place.
4. Type: *"add buy groceries and finish the report by Friday"* → agent creates two tasks (or asks to confirm both) → Confirm → both appear; "finish the report" carries Friday's date.
5. Type: *"mark the Marko call done"* → **Complete** confirmation → Confirm → row moves to completed, struck through.
6. Type something ambiguous, e.g. *"delete the report"* when titles are similar enough to be unsure, OR *"move my meeting"* with no meeting → agent asks a clarifying question instead of acting.
7. Toggle device to dark mode mid-demo → everything remains clean and legible.

Plus:
- Light/dark both flawless. Dynamic Type at a large size doesn't break layout.
- No console warnings, no force-unwrap crashes, no main-thread networking.
- App handles airplane mode gracefully (step: turn it on, send, see the friendly error).

---

## 13. Code quality requirements

- Documented public types and non-obvious logic (`///` doc comments).
- No force unwraps / force try in production paths. Typed errors.
- `@MainActor` discipline; no data races (build clean under strict concurrency).
- Unit tests for: `ToolExecutor` (each of the four tools mutates the store correctly), `DateParsing` (relative-to-absolute + ISO round-trip), and the request/response `Codable` models (decode a representative `tool_use` response, encode a `tool_result`).
- Small, single-responsibility files matching §9.

---

## 14. README

Include a `README.md` with: one-paragraph product description, a screenshot/gif placeholder, the tech stack, the §11 secrets setup steps, how to run, the four-tool agent design explained in a short paragraph, and the demo script from §12. Write it so it doubles as the portfolio write-up.

---

## 15. Notes for Claude Code

- Scaffold the full project, then implement networking and the agent loop, then the UI, then tests. Keep the app runnable at each stage.
- Treat §5 (tool contract), §8.4 (confirmation card), and §12 (acceptance script) as the non-negotiable core. Everything else can be implemented in the cleanest way you see fit.
- Verify the live Anthropic Messages API tool-use shape before finalizing `APIModels.swift`.
- Optimize for "looks shipped by a senior engineer" over feature count. Polish the confirmation animation and the empty state — those carry the demo.
