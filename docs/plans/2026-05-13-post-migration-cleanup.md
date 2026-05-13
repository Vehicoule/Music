# Implementation Plan — Streambox Fixes
## 2026-05-13

---

### Bug: "Backend looks stale (0.1.0). Restart FastAPI."

**Root cause:** Rust core reports `CORE_API_VERSION = "0.1.0"` (lib.rs:13) but Flutter frontend expects `expectedApiVersion = '0.3.0'` (home_screen.dart:33). Version mismatch triggers stale-diagnostic warning. FastAPI is already deleted — the message is wrong in all cases.

**Fix:** Bump Rust version + clean stale messages.

---

## Phase 1 — Immediate Fix (blocking the user)

### Task 1: Bump Rust API version to 0.3.0

**File:** `native/streambox_core/src/lib.rs`

Change:
```
pub const CORE_API_VERSION: &str = "0.1.0";
```
To:
```
pub const CORE_API_VERSION: &str = "0.3.0";
```

**Affected tests:**
- `tests/health.rs` — update assertions: `"0.1.0"` → `"0.3.0"` (lines 19, 28)
- Re-run `cargo test` to confirm

**Commit:** `fix: bump core API version to 0.3.0 to match frontend expectation`

---

### Task 2: Remove stale FastAPI messages from Flutter frontend

**File:** `frontend/lib/src/screens/home_screen.dart`

Three messages need updating:

1. **Line 145** — Replace:
   ```dart
   'Backend looks stale (${runtime.apiVersion}). Restart FastAPI.';
   ```
   With:
   ```dart
   'Native core version mismatch (got ${runtime.apiVersion}, expected $expectedApiVersion).';
   ```

2. **Line 159** — Replace:
   ```dart
   'Backend diagnostics are missing. Restart FastAPI if search fails.';
   ```
   With:
   ```dart
   'Native core diagnostics are missing. Check Rust build output.';
   ```

3. **Line 398** — Replace:
   ```dart
   'Backend is not running. Start FastAPI and try again.';
   ```
   With:
   ```dart
   'Native core is unreachable. Check that streambox_core.dll is built.';
   ```

**Commit:** `fix: remove stale FastAPI messages from diagnostics`

---

## Phase 2 — Safety & Correctness

### Task 3: Enforce yt-dlp timeout

**File:** `native/streambox_core/src/services/ytdlp.rs`

**Issue:** `_timeout` parameter is accepted but never enforced. `Command::output()` blocks indefinitely if the yt-dlp process hangs.

**Fix:** Replace `Command::output()` wait with a timed wait:

1. Spawn the process with `Command::spawn()`
2. Wait with `child.wait_timeout(30s)` (or configured timeout)
3. If timeout expires, `child.kill()` and return `Err("yt-dlp timed out after 30s")`

**Implementation steps:**
```rust
let mut child = command.spawn()?;
let status = child.wait_timeout(timeout)?;
match status {
    Some(exit) => { /* read output */ }
    None => {
        child.kill()?;
        return Err(CoreError { code: "ytdlp_timeout", message: format!("yt-dlp timed out after {:?}", timeout) });
    }
}
```

**Test:** Verify timeout fires when yt-dlp stalled (can mock with `sleep 999` or nonexistent binary).

**Commit:** `fix: enforce yt-dlp subprocess timeout`

---

### Task 4: Update stale documentation

**Files to update:**

**README.md (lines 24–28):**
- Remove "three cooperating runtimes" language  
- Replace with "two-layer architecture" (Flutter + Rust)
- Remove `uv run uvicorn` dev commands
- Remove "Current FastAPI-backed features" section (line 36)
- Update architecture diagram to show FFI path only

**docs/api-contracts.md (line 193):**
- Remove "FastAPI is a legacy fallback backend during this migration"
- Update to reflect current Rust-only architecture

**docs/rust-core-migration.md:**
- Mark all remaining items as complete
- Add completion date (2026-05-13)
- Note that FastAPI/backend/ directory is deleted

**docs/plans/2026-05-13-remove-fastapi-rust-migration.md:**
- Add completion notes at top
- Mark Phase 4 as done

**Commit:** `docs: update documentation to reflect all-Rust architecture`

---

## Phase 3 — Code Quality

### Task 5: Extract shared ranking logic

**Issue:** `db.rs::rank_source_entries()` and `musicbrainz.rs::rank_tracks()` have independent implementations of token-based scoring. Both define cue words, soft words, compute overlap scores, apply penalties.

**Fix:** Create `src/ranking.rs` with shared structs/functions:

```rust
pub struct RankingConfig {
    pub base_score: i32,
    pub artist_overlap_bonus: i32,
    pub cue_penalty: i32,
    pub ideal_duration_min: f64,
    pub ideal_duration_max: f64,
    pub min_similarity: f64,
}

pub fn rank_candidates(candidates: Vec<Rankable>, query: &Query) -> Vec<Ranked>;
pub fn token_overlap(query_tokens: &[String], target_tokens: &[String]) -> Overlap;
pub fn compute_penalty(title: &str, cue_words: &[&str]) -> i32;
```

Refactor both `db::rank_source_entries` and `musicbrainz::rank_tracks` to use the shared module.

**Note:** Keep cue/soft word constants in their respective modules — they differ slightly between source-index ranking and MusicBrainz ranking. Share the scoring framework, not the word lists.

**Commit:** `refactor: extract shared ranking logic into ranking.rs`

---

### Task 6: Wire ListenBrainz into discovery

**File:** `native/streambox_core/src/services/discovery.rs`

**Issue:** `listenbrainz.rs` exists with tested popularity API client but is never called.

**Fix:** Call ListenBrainz during the MusicBrainz fallback phase of `discover()` to enrich results with popularity data:

1. After `musicbrainz::search_tracks()` returns results, collect recording MBIDs
2. Call `listenbrainz::recording_popularity(ids)` for their popularity stats
3. Inject popularity scores into `rank_tracks()` (the scoring already accounts for it — see `PopularityStats::compute_score()`)

**FFI:** No new FFI endpoint needed (called internally during discovery).

**Commit:** `feat: wire ListenBrainz popularity into discovery scoring`

---

## Phase 4 (deferred — larger refactors)

### Task 7: Split HomeScreen (1054 lines)

**Problem:** Single StatefulWidget with ~20 mutable fields, `setState` everywhere, and ~1000 lines of UI/callback/search logic.

**Plan:**
- Extract `SearchSection` widget (search header + result list + detail views)
- Extract `LibrarySection` widget (playlists/favorites/history panels)
- Extract `NowPlayingSection` widget
- Extract `PlayerDockSection` widget
- HomeScreen becomes thin orchestrator: layout + section routing + shared state

**Risk:** Must preserve the `ResolvePrefetcher` and `PlayerController` passing to avoid regressions. Test with full `flutter test` after split.

---

### Task 8: Replace hand-rolled date parsing with chrono

**File:** `native/streambox_core/src/db.rs`

**Current:** ~200 lines of `civil_from_days`, `days_from_civil`, `parse_rfc3339_timestamp`, `timestamp_to_iso8601`, `iso8601_to_timestamp` — all hand-rolled.

**Proposal:** Replace with `chrono` crate:
- `chrono::NaiveDateTime::from_timestamp_opt()`
- `chrono::DateTime::to_rfc3339()`
- `chrono::DateTime::parse_from_rfc3339()`

**Trade-off:** Chrono adds ~2MB to binary and links libc timezone. Hand-rolled avoids this and is provably correct for the limited needs of ISO8601 ↔ Unix timestamps. Defer decision — keep hand-rolled unless chrono is needed for something else.

---

## Execution order

| Priority | Task | Approx Time | Dependencies |
|----------|------|-------------|--------------|
| P0 | Task 1: Bump API version | 5 min | None |
| P0 | Task 2: Clean stale messages | 10 min | None |
| P1 | Task 3: Enforce yt-dlp timeout | 20 min | None |
| P1 | Task 4: Update stale docs | 15 min | None |
| P2 | Task 5: Extract ranking module | 45 min | None |
| P2 | Task 6: Wire ListenBrainz | 30 min | None |
| P3 | Task 7: Split HomeScreen | 2 hrs | Tasks 1-6 done |
| P3 | Task 8: Chrono replacement | 30 min (or skip) | None |

---

## Test coverage after fixes

After each task:
```
cd native/streambox_core
CARGO_TARGET_DIR=/tmp/st-box cargo test
```

Key tests to run:
- `health.rs` — version assertions
- `json_contract.rs` — fixture shapes
- `migrations.rs` — schema upgrades
- `source_index.rs` — search/ranking
- `musicbrainz_browser_test.rs` — MB ranking

Flutter tests (if Flutter SDK available):
```
cd frontend
flutter test
```

All tests must pass before merging.

---

## Completion Notes (2026-05-13)

### Done (6 tasks, 6 commits on main)

All P0-P2 tasks complete. Merged to `main` via fast-forward from
`Vehicoule/fix/bump-api-version-and-cleanup`.

- **99/99 tests pass** (64 lib + 35 integration)
- 12 files changed, +880/-135 lines
- 5 clippy warnings auto-fixed
- Graphify refreshed: 943 nodes, 1351 edges

### Blocked / Deferred

| Task | Status | Reason |
|------|--------|--------|
| 7: Split HomeScreen | Blocked | Flutter SDK not installed on this host. Private widgets (lines 528-1054) already well-factored. Extracting _SearchCenter, _AlbumDetailView, _ArtistDetailView, _DetailHero, _QueueCenter to public widget files requires `flutter test` verification. |
| 8: Chrono replacement | Skipped | Hand-rolled date math is ~200 lines and avoids ~2MB chrono binary bloat. No functional benefit. Only reconsider if chrono needed for another dependency. |
