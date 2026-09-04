# linny-web-theme

A searchable, static **HTML web-view for [Linny](https://github.com/linden-project/linny-notebook-template) markdown notebooks**, packaged as a **Hugo Module theme**.

It is what the [`torrlinny`](https://linny.toorren.net) notebook uses, made reusable for any Linny notebook:

- **[hugo-geekdoc](https://github.com/thegeeklab/hugo-geekdoc)** look & feel — sidebar file-tree, built-in full-text search, taxonomy menus — **bundled** (prebuilt, MIT), so you import **one** module and it just works (no npm/webpack, no submodules).
- **Linny layouts on top**: each note shows **Created** (`crdate`) + **Updated** (git `.Lastmod`) on one line; two paginated **overview pages** (all notes by title / by date) delivered via the theme's own content.
- **Config defaults**: taxonomies (customer/project/type/tags), the top menu, the `crdate → .Date` mapping and sensible geekdoc params — so a notebook needs only a tiny `hugo-web.yaml`.

## Requirements

- Hugo **extended**, ≥ 0.100 (tested on 0.163).
- **Go** ≥ 1.21 on `PATH` (Hugo Modules use `go` to fetch dependencies).

## Use it in a notebook

From your notebook root:

```bash
# 1. one-time: make the notebook a Hugo module and add this theme
hugo mod init github.com/you/your-notebook
hugo mod get github.com/torreirow/linny-web-theme
```

Create a `hugo-web.yaml`. Hugo only merges **`params`** from a theme (so the
geekdoc options come from the theme automatically), but **site-level config —
taxonomies, menu, markup, frontmatter, pagination, `enableGitInfo` — is not
merged from a theme** and must live here:

```yaml
title: "My Notes"
baseURL: "http://localhost:9999/"
languageCode: "nl-nl"
enableGitInfo: true            # git "Updated on …" date

taxonomies:
  tags: "tags"
  project: "project"
  customer: "customer"
  type: "type"

menu:
  main:
    - {identifier: customers, name: Customers, url: /customer/, weight: 10}
    - {identifier: projects,  name: Projects,  url: /project/,  weight: 20}
    - {identifier: types,     name: Types,     url: /type/,     weight: 30}
    - {identifier: tags,      name: Tags,      url: /tags/,     weight: 40}

pagination: {pagerSize: 20}
markup:
  goldmark: {renderer: {unsafe: true}}
  highlight: {style: monokai, lineNos: true}
frontmatter:
  date: [crdate, date, publishDate, lastmod]   # map Linny's crdate to .Date

module:
  imports:
    - path: github.com/torreirow/linny-web-theme
```

The [linny-notebook-template](https://github.com/linden-project/linny-notebook-template) ships this file ready-made — copy it into any notebook.

Serve it — keeping the notebook's Linny `config/` (the linny.vim JSON indexer) out of the web build with `--configDir doesnotexist`:

```bash
hugo server --config hugo-web.yaml --configDir doesnotexist --bind 0.0.0.0 --port 9999
```

The [linny-notebook-template](https://github.com/linden-project/linny-notebook-template) ships a ready-made `hugo-web.yaml` + `start-web.sh` so a fresh notebook has the web-view out of the box.

## Serve it on NixOS (`services.linny-web`)

This repo also ships a **reusable NixOS module** (`nixosModules.linny-web`) that clones a
**private** notebook repo, builds it with this theme and publishes it as a robust static site —
**atomic swap + keep-last-good**, auto-rebuilt on a timer. It is the generic, webserver-agnostic
form of what powers [`linny.toorren.net`](https://linny.toorren.net).

The minimal one-time config is **three fields**: `gitRepo`, an auth secret
(`gitTokenFile` **or** `gitSshKeyFile`) and `baseURL`.

```nix
# flake.nix
{
  inputs.linny-web.url = "github:torreirow/linny-web-theme";
  # … your other inputs (nixpkgs, …)
}
```

```nix
# configuration.nix
{ config, inputs, ... }:
{
  imports = [ inputs.linny-web.nixosModules.linny-web ];

  services.linny-web = {
    enable       = true;
    gitRepo      = "https://github.com/you/your-notebook.git";
    gitTokenFile = "/run/agenix/linny-notes-token";  # fine-grained PAT, Contents: read
    baseURL      = "https://notes.example.com/";
  };
}
```

- **Auth** — set **exactly one**:
  - **`gitTokenFile`** (HTTPS `gitRepo`): a file with a GitHub **fine-grained token** (scope
    *Contents: read-only*). Read through a git credential helper at auth time, so the token never
    appears in the process list or the on-disk git config.
  - **`gitSshKeyFile`** (`git@`/`ssh://` `gitRepo`): a private **SSH deploy key** (read-only), used
    via `GIT_SSH_COMMAND` with `IdentitiesOnly` (no ssh-agent).

  You decide how the secret file gets there (agenix, sops-nix, a plain root-only file).
- The rendered site is published (world-readable) at **`config.services.linny-web.webRoot`**
  (default `/var/lib/linny-web/live`); the raw notes checkout stays private (`0700`).

### Point your web server at it

The module is **webserver-agnostic** — it just publishes `webRoot`:

```nix
# nginx
services.nginx.virtualHosts."notes.example.com".root = config.services.linny-web.webRoot;
# or apache
services.httpd.virtualHosts."notes.example.com".documentRoot = config.services.linny-web.webRoot;
```

Prefer nginx and want it wired for you (incl. TLS)? Use the optional helper:

```nix
services.linny-web.nginx = {
  enable      = true;
  virtualHost = "notes.example.com";
  useACMEHost = "example.com";   # forceSSL with this ACME certificate
};
```

### Options

| Option         | Required | Default                                 | Role                                   |
|----------------|:--------:|-----------------------------------------|----------------------------------------|
| `gitRepo`      | ✅       | –                                       | URL of the private notebook repo (HTTPS or SSH) |
| `gitTokenFile` | ⬥        | –                                       | fine-grained PAT (HTTPS); or use `gitSshKeyFile` |
| `gitSshKeyFile`| ⬥        | –                                       | SSH deploy key (SSH); or use `gitTokenFile`      |
| `baseURL`      | ✅       | –                                       | `hugo --baseURL`                       |
| `webRoot`      | –        | `${stateDir}/live`                      | live dir your web server serves        |
| `stateDir`     | –        | `/var/lib/linny-web`                    | checkout / builds / module cache       |
| `user`         | –        | `linny-web`                             | service user                           |
| `branch`       | –        | `main`                                  | notebook branch to track               |
| `configFile`   | –        | `hugo-web.yaml`                         | notebook web config (imports the theme)|
| `themeModule`  | –        | `github.com/torreirow/linny-web-theme`  | theme module (`hugo mod get`, bumpable)|
| `interval`     | –        | `3min`                                  | rebuild-timer poll (change-detected)   |
| `nginx.*`      | –        | disabled                                | optional native nginx helper           |

⬥ = set **exactly one** of `gitTokenFile` / `gitSshKeyFile`.

**Requires** `go` (fetched by the service) and `hugo`; a fresh notebook also needs a
`hugo-web.yaml` (see *Use it in a notebook* above). If the notebook ships a `fence.py`, the module
runs it as a pre-Hugo pass automatically.

## Box-drawing CLI tables (`fence.py`)

Notes that paste box-drawing CLI output (e.g. `aws … --output table`, U+2500–U+259F) render as broken paragraphs because Markdown collapses them. The fix runs **before** Hugo (a theme only sees already-parsed content), so it lives in the **runner**, not here: the template's `start-web.sh` runs `fence.py` over a staging copy of the content (source untouched, idempotent) to wrap contiguous box-drawing runs in a ` ```text ` fence. See the template repo.

## Updating the bundled geekdoc

geekdoc is vendored from its **prebuilt release tarball** (current: see `GEEKDOC_VERSION`). To bump:

```bash
ver=v4.1.3
curl -fsSL -o /tmp/geekdoc.tar.gz \
  https://github.com/thegeeklab/hugo-geekdoc/releases/download/$ver/hugo-geekdoc.tar.gz
tmp=$(mktemp -d); tar -xzf /tmp/geekdoc.tar.gz -C "$tmp"
# refresh the vendored dirs …
for d in archetypes assets data i18n images layouts static; do rm -rf "$d"; cp -r "$tmp/$d" .; done
# … then re-apply the Linny overrides that live on top of geekdoc:
#   layouts/partials/page-metadata.html, layouts/partials/menu.html,
#   layouts/_default/noteslist.html   (restore these from git after the copy)
cp "$tmp/LICENSE" LICENSE.geekdoc; cp "$tmp/VERSION" GEEKDOC_VERSION
git checkout -- layouts/partials/page-metadata.html layouts/partials/menu.html layouts/_default/noteslist.html
```

## What's Linny-specific vs vendored

| Path | Origin |
|------------------------------------------------|-----------------------------|
| `layouts/partials/page-metadata.html`          | Linny override (Created + Updated) |
| `layouts/partials/menu.html`                   | Linny override ("Overzichten" block) |
| `layouts/_default/noteslist.html`              | Linny (paginated overview) |
| `content/notes-by-{title,date}/_index.md`      | Linny (overview pages, content-mounted) |
| `hugo.yaml`                                     | Linny config defaults |
| everything else (`layouts/`, `static/`, `assets/`, `data/`, `i18n/`, `archetypes/`) | vendored geekdoc v4.x (MIT) |

## License

MIT — see [`LICENSE`](LICENSE). Bundled geekdoc is MIT — see [`LICENSE.geekdoc`](LICENSE.geekdoc).
