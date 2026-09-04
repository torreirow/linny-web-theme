{ config, lib, pkgs, ... }:

# linny-web — a reusable NixOS module that serves a private Linny notebook as a
# searchable static site built with the linny-web-theme Hugo module.
#
# Minimal one-time config is three fields: gitRepo, gitTokenFile, baseURL.
#
# Design (see the add-linny-web-module OpenSpec change / epic nixos-dhh8):
#  - STATIC build (no `hugo server`): clone -> `hugo mod get` -> `hugo` build ->
#    ATOMIC symlink-swap of `webRoot` -> a web server serves it. Keep-last-good
#    on failure, prune old builds.
#  - AUTH via a fine-grained token: HTTPS clone with a git credential helper that
#    reads the token from `gitTokenFile` at auth time, so the token never lands in
#    the repo URL, the process list, or the on-disk git config.
#  - WEBSERVER-AGNOSTIC: the rendered output is world-readable and `webRoot` is
#    published as an option value; the private checkout stays 0700 so the raw
#    notes do not leak. An optional thin nginx helper can wire the vhost for you.

with lib;

let
  cfg = config.services.linny-web;

  buildScript = pkgs.writeShellScript "linny-web-build" ''
    set -euo pipefail

    WORK="${cfg.stateDir}"
    CHECKOUT="$WORK/checkout"
    BUILDS="$WORK/builds"
    LIVE="${cfg.webRoot}"
    RECIPE="hugo=${pkgs.hugo.version};go=${pkgs.go.version};theme=${cfg.themeModule}"
    FORCE="''${1:-}"

    export HOME="$WORK"

    # Go / Hugo module cache in the (persistent) work dir. GOPROXY=direct fetches
    # the theme straight from its host; the notebook's go.sum guards integrity, so
    # GOSUMDB is off (no external sumdb dependency).
    export GOPATH="$WORK/go"
    export GOMODCACHE="$WORK/go/pkg/mod"
    export GOCACHE="$WORK/gocache"
    export GOPROXY=direct
    export GOSUMDB=off
    export HUGO_CACHEDIR="$WORK/hugo_cache"

    mkdir -p "$BUILDS" "$GOPATH" "$GOCACHE" "$HUGO_CACHEDIR"

    # git wrapper that authenticates via a fine-grained token WITHOUT exposing it.
    # The credential helper runs `cat <gitTokenFile>` only when git asks for a
    # password, so the token is never in argv (ps) nor written to .git/config.
    git_auth() {
      git \
        -c credential.helper='!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$(cat ${cfg.gitTokenFile})"; }; f' \
        -c credential.useHttpPath=false \
        "$@"
    }

    ## 1. sync (FULL clone for enableGitInfo/.Lastmod) + change detection
    if [ ! -d "$CHECKOUT/.git" ]; then
      rm -rf "$CHECKOUT"
      git_auth clone --branch "${cfg.branch}" "${cfg.gitRepo}" "$CHECKOUT"
    else
      git_auth -C "$CHECKOUT" fetch origin "${cfg.branch}"
      LOCAL="$(git -C "$CHECKOUT" rev-parse HEAD)"
      REMOTE="$(git -C "$CHECKOUT" rev-parse "origin/${cfg.branch}")"
      # Skip only when content (git HEAD) AND the build recipe (hugo/go/theme) are
      # unchanged vs. the last successful build.
      if [ "$LOCAL" = "$REMOTE" ] && [ -e "$LIVE" ] && [ "$FORCE" != "--force" ] \
         && [ "$(cat "$WORK/last-build-recipe" 2>/dev/null)" = "$RECIPE" ]; then
        echo "linny-web: no change ($LOCAL), build skipped"
        exit 0
      fi
      git -C "$CHECKOUT" reset --hard "origin/${cfg.branch}"
      git -C "$CHECKOUT" clean -fdx
    fi
    # Private notes stay private even though the rendered output is world-readable.
    chmod 700 "$CHECKOUT"
    REV="$(git -C "$CHECKOUT" rev-parse --short HEAD)"

    ## 2. fetch the theme module (pinned in the notebook's go.mod/go.sum)
    ( cd "$CHECKOUT" && ${pkgs.hugo}/bin/hugo mod get "${cfg.themeModule}" )

    ## 3. optional fence preprocessing: wrap CLI output containing box-drawing
    ##    characters in a ```text fence so it renders as a clean monospace table.
    ##    Only runs when the notebook ships a fence.py. In-place on the (throwaway)
    ##    checkout so .git stays intact (enableGitInfo/.Lastmod keeps working).
    if [ -f "$CHECKOUT/fence.py" ]; then
      find "$CHECKOUT/content" -name '*.md' -exec ${pkgs.bash}/bin/bash -c \
        'for f; do ${pkgs.python3}/bin/python3 "'"$CHECKOUT"'/fence.py" < "$f" > "$f.pf" && mv "$f.pf" "$f"; done' _ {} +
    fi

    ## 4. build with the notebook web config (imports the theme; configDir=
    ##    doesnotexist keeps the Linny JSON indexer out). Fresh dir for atomic swap.
    DEST="$BUILDS/$REV-$(date +%s)"
    rm -rf "$DEST"
    ${pkgs.hugo}/bin/hugo --source "$CHECKOUT" \
      --config "${cfg.configFile}" --configDir doesnotexist \
      --baseURL "${cfg.baseURL}" \
      --minify --destination "$DEST" --logLevel error
    # Rendered output world-readable so any web server user can serve it.
    chmod -R a+rX "$DEST"

    ## 5. atomic swap. If the build failed, set -e stopped us above -> LIVE (the
    ##    previous good build) is untouched (keep-last-good).
    ln -sfn "$DEST" "$LIVE.new"
    mv -Tf "$LIVE.new" "$LIVE"
    echo "$RECIPE" > "$WORK/last-build-recipe"
    echo "linny-web: published rev $REV -> $DEST"

    ## 6. prune: keep the 3 newest builds
    find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
      | sort -rn | tail -n +4 | cut -d' ' -f2- | xargs -r rm -rf
  '';

in {
  options.services.linny-web = {
    enable = mkEnableOption "linny-web — serve a Linny notebook as a static site (Hugo + linny-web-theme)";

    gitRepo = mkOption {
      type = types.str;
      example = "https://github.com/you/your-notebook.git";
      description = "HTTPS URL of the (private) Linny notebook repo to clone and build.";
    };

    gitTokenFile = mkOption {
      type = types.str;
      example = "/run/agenix/linny-notes-token";
      description = ''
        Path to a file containing a fine-grained access token (scope: Contents
        read-only) for the notebook repo. Read at auth time via a git credential
        helper, so the token never appears in argv or the git config. You choose
        how it gets there (agenix, sops-nix, plain file, ...).
      '';
    };

    baseURL = mkOption {
      type = types.str;
      example = "https://notes.example.com/";
      description = "Canonical base URL, passed to `hugo --baseURL` (links, sitemap, RSS, assets).";
    };

    webRoot = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/live";
      defaultText = literalExpression ''"''${config.services.linny-web.stateDir}/live"'';
      description = ''
        Path of the live build (an atomically-swapped symlink), world-readable.
        Point your web server's root here, e.g.
        `services.nginx.virtualHosts.X.root = config.services.linny-web.webRoot;`.
      '';
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/linny-web";
      description = "Working directory: checkout, builds and the Go/Hugo module cache.";
    };

    user = mkOption {
      type = types.str;
      default = "linny-web";
      description = "System user that runs the sync + build.";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Git branch of the notebook repo to track.";
    };

    configFile = mkOption {
      type = types.str;
      default = "hugo-web.yaml";
      description = "The notebook's Hugo web config file (imports the theme), passed to `hugo --config`.";
    };

    themeModule = mkOption {
      type = types.str;
      default = "github.com/torreirow/linny-web-theme";
      description = "Hugo module path of the web theme, fetched with `hugo mod get` (bumpable).";
    };

    interval = mkOption {
      type = types.str;
      default = "3min";
      description = "Poll interval of the rebuild timer (change detection avoids needless builds).";
    };

    nginx = {
      enable = mkEnableOption "a thin nginx virtualHost helper that serves webRoot";

      virtualHost = mkOption {
        type = types.str;
        default = "";
        example = "notes.example.com";
        description = "server_name for the generated nginx virtualHost (required when nginx.enable).";
      };

      useACMEHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "example.com";
        description = "ACME host for the TLS certificate; when set, forceSSL is enabled.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.nginx.enable || cfg.nginx.virtualHost != "";
        message = "services.linny-web.nginx.enable requires services.linny-web.nginx.virtualHost.";
      }
    ];

    ###### User + working directory ######
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.stateDir;
      createHome = false;
      description = "linny-web build user";
    };
    users.groups.${cfg.user} = { };

    # stateDir 0751: traversable so a web server can reach builds/, but not
    # listable (the private checkout inside stays 0700). builds/ 0755 + the build
    # dirs get a+rX in the script -> rendered output is world-readable.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0751 ${cfg.user} ${cfg.user} -"
      "d ${cfg.stateDir}/builds 0755 ${cfg.user} ${cfg.user} -"
    ];

    ###### Build service (oneshot) ######
    systemd.services.linny-web-build = {
      description = "linny-web: sync + hugo mod get + Hugo build (atomic swap)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # go: needed for `hugo mod get` (Hugo modules resolve via the Go toolchain).
      path = with pkgs; [ git openssh coreutils findutils go ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = "${buildScript}";

        # Security hardening — read-only view of the system apart from our own paths.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = unique [ cfg.stateDir (builtins.dirOf cfg.webRoot) ];
      };
    };

    ###### Timer with change detection ######
    systemd.timers.linny-web-build = {
      description = "linny-web periodic rebuild (change detection)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
        Unit = "linny-web-build.service";
      };
    };

    ###### Optional thin nginx helper ######
    services.nginx.virtualHosts = mkIf cfg.nginx.enable {
      ${cfg.nginx.virtualHost} = {
        forceSSL = cfg.nginx.useACMEHost != null;
        useACMEHost = mkIf (cfg.nginx.useACMEHost != null) cfg.nginx.useACMEHost;
        root = cfg.webRoot;
        locations."/".tryFiles = "$uri $uri/ =404";
      };
    };
  };
}
