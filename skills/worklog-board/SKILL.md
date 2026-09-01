---
name: worklog-board
description: Use to put a plan on the tracker board and move its card as work proceeds. Creates one card per plan with its units as subtasks, moves the card between sections on request, cancels or relinks it. Triggers on /plan-to-board, /board-move, /board-cancel, /board-relink.
---

# worklog-board

One card per plan. The plan's task headings become its subtasks. The card
travels Backlog → In Progress → Done as the work does, and **a human moves it,
never this skill on its own.**

## Non-negotiable

- **Nothing reaches the tracker before the human has read a preview and
  confirmed it.** Not a summary in chat — the preview file.
- **Never delete a card or a subtask.** Deleting destroys history that cannot
  be recovered. Orphans are reported, not cleaned up.
- **A card with no `Board:` line in a plan is not ours.** Do not touch it.
- **Announce the adapter out loud before acting:** "using the `<tracker>`
  adapter". Reading the wrong adapter is a silent failure otherwise.

## Step 0 — resolve and announce

```
scripts/resolve-config.sh <project-root>
```

Exit 3 means the configuration is not ready: say what is missing and stop.
Exit 2 is a hard error. Otherwise take `tracker` from the resolved config,
announce it, and read `references/adapters/<tracker>.md`. Every tracker call
below comes from that file — this skill names none of them.

## `/plan-to-board <plan>`

1. `scripts/plan-file.sh read <plan>` — the plan as JSON.
2. If `card` is already set, this is a top-up, not a creation: skip to step 7.
3. `scripts/board-preview.sh build <plan> backlog` — then **show the human the
   whole preview file** and wait. Make no tracker call until they confirm.
4. `scripts/board-preview.sh verify <plan>` — exit 4 means the plan changed
   after it was shown. Stop, say so, offer to rebuild the preview. Exit 2 means
   there is no preview: rebuild it.
5. Generate a nonce (`wl-` plus eight hex characters) and write it:
   `scripts/plan-file.sh set-origin <plan> <nonce>`. This happens **before**
   the first tracker call — it is what makes a lost response harmless.
6. `find_by_origin` with the marker, per the adapter.
   - **one match** — adopt it: take its id, create nothing.
   - **more than one** — stop. The marker is no longer unique, and picking one
     is how a second card quietly becomes the wrong one.
   - **none** — create the card and one subtask per unit. The card's
     description carries the marker: the plan path and the nonce.
7. Record what exists: `plan-file.sh set-board`, `plan-file.sh set-marker` for
   each unit, `board-state.sh map-init`, `board-state.sh map-set` per subtask.
   A unit already in the map is skipped, never recreated.
8. `scripts/board-state.sh place <plan> backlog`.
9. `scripts/board-journal.sh append create <plan> <tracker> ok <card>` — and on
   any failure above, the same call with `fail` and a one-line reason.

## `/board-move <plan> <section-key>`

Keys are `backlog`, `to_do`, `in_progress`, `review`, `done`.

1. Read the plan, then read the card with `find`.
2. Realign first (see below).
3. Show the intent next to the card's current state, wait for confirmation.
4. `place` per the adapter, then `scripts/board-state.sh place`.
5. Journal the outcome.

## `/board-cancel <plan>`

Closes the card with `Отменено:` prefixed to its name and places the plan in
`done`. Confirmation is required: this is not undoable by ordinary means.

## `/board-relink <plan>`

Rewrites the plan path inside the card's marker after the plan was renamed or
moved. **Keep the nonce** — replacing it would break idempotency.

## Three kinds of divergence

Telling these apart is the whole job. Conflating them either blocks on things
that already happened or writes over things that did not.

**Stale cache.** The tracker says one section, the plan file sits in another.
A human moved the card by hand — a fact, not a conflict. Move the file, print
one line, journal it. Do not ask.

**Intent against reality.** You were asked to move a card to `in_progress` and
it is already `done`. Stop and ask.

**The card is gone.** The plan has a `Board:` line and `find` returns
not-found. Stop. Offer to clear the `Board:` line so the plan can be put on the
board again. Never recreate silently: the deletion may have been deliberate.

Distinguish "not found" from a network failure. The first is a vanished card,
the second is a reason to try later.

## Repeating a command is safe

There is no separate recovery path. An interrupted run is fixed by running the
same command again: it finds whatever was created by its marker, adopts it, and
fills in what is missing. It passes the same preview and the same confirmation
as the first run.
