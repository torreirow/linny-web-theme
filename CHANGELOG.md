# Changelog

All notable changes to linny-web-theme. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## 0.1.0

### Added
- Initial release: a reusable **Hugo Module theme** for the Linny notebook web-view.
  - Bundles the prebuilt **hugo-geekdoc v4.1.2** (MIT) — one `hugo mod get`, no npm/submodules.
  - Linny layouts: per-note **Created (`crdate`) + Updated (git `.Lastmod`)** on one line; a
    "Overzichten" sidebar block; two paginated **overview pages** (all notes by title / by date)
    delivered via the theme's own content mount.
  - Config defaults (`hugo.yaml`): taxonomies (customer/project/type/tags), top menu,
    `crdate → .Date` front-matter mapping, and sensible geekdoc params.
