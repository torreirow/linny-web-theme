# Changelog

All notable changes to linny-web-theme. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## 0.1.5 - 2026-09-08

### Added
- **In-page note editor** (`params.linnyEdit`, off by default): a pencil in the page-header row of a
  note swaps the rendered article for a textarea holding the note's **raw Markdown** (front matter
  included); saving re-renders it through Hugo, so code fences, shortcodes and front matter survive
  — an HTML-to-Markdown round-trip would not.
  - The save endpoint lives in the **notebook**, not here (a theme only sees parsed content):
    `GET`/`PUT /api/note?path=<note>.md`, advertised to the client via the `linny-source` and
    `linny-edit-api` meta tags. `linny-notebook-template` ships a conforming `edit-server.py`.
  - Configurable with `linnyEditPort` (localhost) or `linnyEditApi` (full URL).
  - **Never reaches a published site**: emitted only when the param is on *and* `hugo.Environment`
    is `"development"`, so a plain `hugo` build — including `services.linny-web` — omits it.
  - Reloads the page the moment Hugo finishes rebuilding, by polling the rendered page rather than
    guessing a delay.

## 0.1.4 - 2026-09-07

### Added
- **Starred notes overview**: a third overview page (`/notes-starred/`) listing every note whose
  front matter has `starred: true`, linked from the "Overviews" sidebar block.
  - Reuses the shared `noteslist` layout via a new optional `filter: starred` front-matter param —
    pagination and sorting come for free; the two existing overviews are unaffected.
  - Renders a friendly empty state ("No starred notes yet.") when no note is starred.
- **SSH deploy-key auth** for the NixOS module (`gitSshKeyFile`), alongside the fine-grained token
  (`gitTokenFile`) — set exactly one. Lets a notebook keep an existing read-only SSH deploy key.
- **Reusable NixOS module** (`nixosModules.linny-web`, via the new `flake.nix`): serve a private
  Linny notebook as a searchable static site with minimal one-time config.
  - Minimal config is **three fields**: `gitRepo`, `gitTokenFile`, `baseURL`.
  - **Static build** (no `hugo server`): clone → `hugo mod get` → `hugo` build → **atomic
    symlink-swap** of `webRoot`, with **keep-last-good** on failure and pruning of old builds.
  - **Private-repo auth via a fine-grained token** (`gitTokenFile`), read through a git credential
    helper at auth time — the token never lands in the process list or the git config.
  - **Webserver-agnostic**: publishes a world-readable `webRoot` while keeping the notes checkout
    private (`0700`); plus an optional thin **nginx helper** (`services.linny-web.nginx`).
  - **Timer with change detection** (git `HEAD` + build recipe) so unchanged content is not rebuilt.
  - `flake check` eval-test that instantiates the module in a NixOS config.

## 0.1.0

### Added
- Initial release: a reusable **Hugo Module theme** for the Linny notebook web-view.
  - Bundles the prebuilt **hugo-geekdoc v4.1.2** (MIT) — one `hugo mod get`, no npm/submodules.
  - Linny layouts: per-note **Created (`crdate`) + Updated (git `.Lastmod`)** on one line; a
    "Overzichten" sidebar block; two paginated **overview pages** (all notes by title / by date)
    delivered via the theme's own content mount.
  - Config defaults (`hugo.yaml`): taxonomies (customer/project/type/tags), top menu,
    `crdate → .Date` front-matter mapping, and sensible geekdoc params.
