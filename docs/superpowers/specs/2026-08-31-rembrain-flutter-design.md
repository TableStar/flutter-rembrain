# Rembrain (Flutter) — Design

> **Rembrain** = Remember + Brain. Personal note app for short attention spans. Dump thoughts, let the app resurface what you forgot.
>
> This is a Flutter/Dart learning project. Purpose: learn idiomatic Flutter by rebuilding the Rembrain concept (originally specced as Laravel+Inertia in `lara-test`) as a local-only Android app.

---

## 1. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Purpose | Learning Flutter | Every feature maps to a Flutter/Dart concept |
| Platform | Android only | The real use case (dump on the go) |
| Backend | None — local only | Personal single-user app; no server needed |
| State management | Riverpod (`flutter_riverpod` + `riverpod_annotation` codegen) | React-like mental model, compile-safe, community standard. BLoC rejected: boilerplate teaches BLoC, not Flutter |
| Database | drift (SQLite) | Typed ORM, codegen, `watch()` streams push DB changes into UI |
| Routing | go_router | Flutter's standard declarative router |
| Codegen | build_runner | Generates drift + Riverpod code (like Prisma generate) |
| Structure | Feature-first, 2 layers | Per docs.flutter.dev/app-architecture; `domain/` layer skipped at this scale — logic lives in Riverpod providers + drift queries |
| AI processing | Deferred | DeepSeek pricing in flux; may swap endpoint/service. Build behind an interface later. Not in this spec's scope |

## 2. Out of Scope (future phases)

- **AI cleanup** (title generation, text cleanup, tag suggestions) — later phase, endpoint-agnostic service interface. The schema reserves `ai_title` / `ai_content` columns now so no migration later.
- **Voice input** — later (`speech_to_text` package).
- **Full-text search beyond a simple LIKE query**, weekly digest, export — not planned.
- **Auth / multi-user** — single local user.

## 3. Data Model

```
notes: id (PK), content TEXT (raw, as typed), title TEXT?,
       ai_title TEXT?, ai_content TEXT?,
       is_archived BOOL (default false),
       resurface_count INT (default 0),
       last_resurfaced_at DATETIME?,
       created_at, updated_at

tags: id (PK), name TEXT, UNIQUE(name)

note_tags: note_id FK → notes ON DELETE CASCADE,
           tag_id FK → tags ON DELETE CASCADE,
           PRIMARY KEY(note_id, tag_id)
```

- `content` is preserved verbatim; `#hashtag` tokens are parsed out for the tag relation, never stripped from `content`.
- No soft delete: hard delete + confirm dialog. Original Laravel plan used softDeletes for a web multi-user context; unnecessary here.
- `ai_*` columns nullable, unused until the AI phase.

## 4. Screens (bottom navigation)

```
🏠 Home     → Resurface card ("You wrote this 17 days ago — still relevant?")
              with Keep / Archive / Forget actions
              + quick dump box pinned at top
              + FAB alternative for dump
📝 Notes    → card list, search field, filter chips by tag
Note detail → full text, tags, created/updated dates,
              edit / archive-unarchive / delete actions
Create/Edit → title (optional), content, tag editor
⚙ Settings → theme toggle, (future: AI endpoint config), export stub
```

Mobile-first rules (inherited from original plan): all primary actions thumb-reachable, ≥ 44px tap targets, must work at 375px viewport, no horizontal scrolling.

## 5. Project Structure

```
lib/
  main.dart
  core/
    db/           database.dart, tables/ (drift table + DAO definitions)
    router/       app_router.dart
    theme/        dark-first Material 3 theme
    utils/        generic helpers only (formatDate etc.)
  features/
    notes/
      data/       note_repository.dart (drift queries)
      ui/         notes_list_screen.dart, note_detail_screen.dart,
                  note_edit_screen.dart, note_card.dart, tag_chip.dart,
                  quick_dump_box.dart
      notes_providers.dart
    resurface/
      ui/         resurface_card.dart
      resurface_providers.dart   ← weighted pick logic lives here
    settings/
      ui/         settings_screen.dart
test/             mirrors lib/ structure
```

Layer vocabulary:

- `data/` = drift tables, DAOs, repositories (all DB access).
- `ui/` = screens and widgets.
- `*_providers.dart` = Riverpod providers — state + orchestration. Equivalent of React custom hooks / Laravel service classes for app-specific rules.
- `core/utils/` = generic helpers only. No `helpers/` dumping ground.

## 6. Key Flows

### Dump
Type → enter/send → repository inserts note → dump box clears → confirmation snackbar. Notes list updates live via drift `watch()` (StreamProvider). Empty content = disabled send button.

### Resurface (app-specific rule, the heart of the app)
1. Query eligible notes: `is_archived = false`, not the last resurfaced note.
2. Weight by age: older = more likely. Exact weighting: linear weight `w = days_since_created + 1`, weighted random selection. Unit-tested pure function.
3. Increment `resurface_count`, set `last_resurfaced_at`.
4. User decides: **Keep** (dismiss until next app open), **Archive** (sets `is_archived`), **Forget** (delete, confirm dialog).

### Tags
- Parsed from `#hashtag` tokens anywhere in `content` at insert/update time. Rule: `#` followed by `[a-zA-Z0-9_]+`, up to 32 chars.
- Tag list syncs to `note_tags` on every note save (create orphans on demand; orphan tags with zero notes are pruned on save).
- Filter chips on Notes screen come from the tags table.

## 7. Error Handling

- Empty dump → send disabled (no error path).
- DB insert/update failure → error snackbar, dump box text preserved (no data loss).
- Delete → confirm dialog always (no soft delete to fall back on).
- Tag parse edge cases (`#` alone, trailing `#`) → ignored silently, never crash.

## 8. Testing

- **Unit:** resurface weighting function (distribution + eligibility), tag parsing.
- **DAO:** drift tests against in-memory SQLite (insert, watch, archive, tag sync, prune).
- **Widget:** dump box inserts note + clears; notes list renders rows; resurface card actions call providers.
- Runner: `flutter test`. Widget tests are the equivalent of Pest feature tests.

## 9. Build Order (phases = learning map)

| Phase | Build | Flutter concepts learned |
|---|---|---|
| 0 | Project setup: deps, drift schema, codegen pipeline, theme, go_router + bottom nav skeleton | pubspec, build_runner, Material 3, go_router, NavigationBar |
| 1 | Dump + notes list + live updates | Stateful widgets, TextEditingController, drift basics, StreamProvider/`watch()` |
| 2 | Resurface card | FutureProvider/async logic, pure Dart logic + unit tests |
| 3 | Tags | drift relations/joins, string parsing, filter chips |
| 4 | Note detail + edit + archive/delete | Forms, validation, navigation with args, dialogs |
| 5 | Settings | SharedPreferences, ThemeMode, light/dark |
| 6 | (later) AI behind service interface | http, JSON DTOs, background work, key storage — separate spec when started |

Each phase ends: `flutter analyze` clean + `flutter test` green + runs on device.

## 10. Success Criteria

- App runs on an Android phone; dump → list → resurface → tag → edit → archive → delete all work offline.
- Data survives app restart (real SQLite file, not in-memory).
- All tests green, `flutter analyze` clean.
- The author can explain every file in `lib/` — this is a learning project; no copied-in code that isn't understood.
