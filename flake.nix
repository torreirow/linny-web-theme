{
  description = "linny-web-theme — Hugo module + reusable NixOS module (services.linny-web) to serve a Linny notebook as a searchable static site";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      # Plain-nix architecture handling (no flake-utils).
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      # The reusable NixOS module. Import as:
      #   imports = [ inputs.linny-web.nixosModules.linny-web ];
      nixosModules.linny-web = import ./nix/linny-web.nix;
      nixosModules.default = self.nixosModules.linny-web;

      # `nix flake check`: evaluate the module in a minimal NixOS config and force
      # the build-service unit (its ExecStart script), the webRoot option and the
      # optional nginx helper to fully evaluate/build.
      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Instantiate the module in a minimal NixOS config with the given
          # linny-web settings, and return the build-script store path + webRoot.
          mkMachine = extra: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.linny-web
              ({ ... }: {
                # Minimal bootable stub so the NixOS eval succeeds.
                boot.loader.grub.enable = false;
                fileSystems."/" = { device = "nodev"; fsType = "tmpfs"; };
                system.stateVersion = "26.05";
                services.linny-web = { enable = true; baseURL = "https://notes.example.test/"; } // extra;
              })
            ];
          };
          # HTTPS token auth + the optional nginx helper.
          tokenM = mkMachine {
            gitRepo = "https://example.com/notebook.git";
            gitTokenFile = "/run/secrets/linny-token";
            nginx = { enable = true; virtualHost = "notes.example.test"; useACMEHost = "example.test"; };
          };
          # SSH deploy-key auth (no nginx helper).
          sshM = mkMachine {
            gitRepo = "git@example.com:you/notebook.git";
            gitSshKeyFile = "/run/secrets/linny-deploy-key";
          };
          tokenExec = tokenM.config.systemd.services.linny-web-build.serviceConfig.ExecStart;
          sshExec = sshM.config.systemd.services.linny-web-build.serviceConfig.ExecStart;
          webRoot = tokenM.config.services.linny-web.webRoot;
          vhosts = builtins.concatStringsSep "," (builtins.attrNames tokenM.config.services.nginx.virtualHosts);
        in
        {
          # Interpolating the ExecStart store paths realizes the build-script
          # derivations, so this check fails if the module (either auth mode) or its
          # shell script break.
          eval = pkgs.runCommand "linny-web-eval" { } ''
            echo "tokenExec=${tokenExec}" > "$out"
            echo "sshExec=${sshExec}"    >> "$out"
            echo "webRoot=${webRoot}"    >> "$out"
            echo "vhosts=${vhosts}"      >> "$out"
            test "${webRoot}" = "/var/lib/linny-web/live"
            test "${tokenExec}" != "${sshExec}"
            echo "${vhosts}" | grep -q "notes.example.test"
          '';
        });
    };
}
