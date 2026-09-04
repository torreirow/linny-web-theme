# Changelog

All notable changes to linny-web-theme. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## NEXT VERSION

### Added
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
