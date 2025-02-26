{
  description = "Nix Flake for ironbar";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    ...
  }: let
    inherit (nixpkgs) lib;
    genSystems = lib.genAttrs [
      "aarch64-linux"
      "x86_64-linux"
    ];
    pkgsFor = system:
      import nixpkgs {
        inherit system;

        overlays = [
          self.overlays.default
          rust-overlay.overlays.default
        ];
      };
    mkRustToolchain = pkgs: pkgs.rust-bin.stable.latest.default;
  in {
    overlays.default = final: prev: let
      rust = mkRustToolchain final;

      rustPlatform = prev.makeRustPlatform {
        cargo = rust;
        rustc = rust;
      };
      props = builtins.fromTOML (builtins.readFile ./Cargo.toml);
      mkDate = longDate: (lib.concatStringsSep "-" [
        (builtins.substring 0 4 longDate)
        (builtins.substring 4 2 longDate)
        (builtins.substring 6 2 longDate)
      ]);
    in {
      ironbar = prev.callPackage ./nix/default.nix {
        version = props.package.version + "+date=" + (mkDate (self.lastModifiedDate or "19700101")) + "_" + (self.shortRev or "dirty");
        inherit rustPlatform;
      };
    };
    packages = genSystems (
      system: let
        pkgs = pkgsFor system;
      in
        (self.overlays.default pkgs pkgs)
        // {
          default = self.packages.${system}.ironbar;
        }
    );
    apps = genSystems (system: let
      pkgs = pkgsFor system;
    in {
      default = {
        type = "app";
        program = "${pkgs.ironbar}/bin/ironbar";
      };
      ironbar = {
        type = "app";
        program = "${pkgs.ironbar}/bin/ironbar";
      };
    });
    devShells = genSystems (system: let
      pkgs = pkgsFor system;
      rust = mkRustToolchain pkgs;
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          rust
          rust-analyzer-unwrapped
          gcc
          gtk3
          gtk-layer-shell
          pkg-config
          openssl
        ];

        RUST_SRC_PATH = "${rust}/lib/rustlib/src/rust/library";
      };
    });
    homeManagerModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.programs.ironbar;
      defaultIronbarPackage = self.packages.${pkgs.hostPlatform.system}.default;
      jsonFormat = pkgs.formats.json {};
    in {
      options.programs.ironbar = {
        enable = lib.mkEnableOption "ironbar status bar";
        package = lib.mkOption {
          type = with lib.types; package;
          default = defaultIronbarPackage;
          description = "The package for ironbar to use.";
        };
        systemd = lib.mkOption {
          type = lib.types.bool;
          default = pkgs.stdenv.isLinux;
          description = "Whether to enable to systemd service for ironbar.";
        };
        style = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "The stylesheet to apply to ironbar.";
        };
        config = lib.mkOption {
          type = jsonFormat.type;
          default = {};
          description = "The config to pass to ironbar.";
        };
        features = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [];
          description = "The features to be used.";
        };
      };
      config = let
        pkg = cfg.package.override {features = cfg.features;};
      in
        lib.mkIf cfg.enable {
          home.packages = [pkg];
          xdg.configFile = {
            "ironbar/config.json" = lib.mkIf (cfg.config != "") {
              source = jsonFormat.generate "ironbar-config" cfg.config;
            };
            "ironbar/style.css" = lib.mkIf (cfg.style != "") {
              text = cfg.style;
            };
          };
          systemd.user.services.ironbar = lib.mkIf cfg.systemd {
            Unit = {
              Description = "Systemd service for Ironbar";
              Requires = ["graphical-session.target"];
            };
            Service = {
              Type = "simple";
              ExecStart = "${pkg}/bin/ironbar";
            };
            Install.WantedBy = [
              (lib.mkIf config.wayland.windowManager.hyprland.systemdIntegration "hyprland-session.target")
              (lib.mkIf config.wayland.windowManager.sway.systemdIntegration "sway-session.target")
            ];
          };
        };
    };
  };
  nixConfig = {
    extra-substituters = ["https://jakestanger.cachix.org"];
    extra-trusted-public-keys = ["jakestanger.cachix.org-1:VWJE7AWNe5/KOEvCQRxoE8UsI2Xs2nHULJ7TEjYm7mM="];
  };
}
