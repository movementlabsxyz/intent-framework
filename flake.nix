{
  description = "Intent Framework dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        aptosCli = pkgs.callPackage ./aptos.nix {};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.rustc
            pkgs.cargo
            pkgs.rustfmt
            pkgs.clippy
            pkgs.jq
            pkgs.curl
            pkgs.bash
            pkgs.coreutils
            pkgs.openssl
            pkgs.pkg-config
            pkgs.nodejs
            pkgs.nodePackages.npm
            aptosCli
          ];

          shellHook = ''
            echo "[nix] Dev shell ready: rustc $(rustc --version | awk '{print $2}') | cargo $(cargo --version | awk '{print $2}') | aptos $(aptos --version 2>/dev/null || echo 'unknown') | node $(node --version 2>/dev/null || echo 'unknown')"
            export OPENSSL_DIR=${pkgs.openssl.dev}
            export OPENSSL_LIB_DIR=${pkgs.openssl.out}/lib
            export OPENSSL_INCLUDE_DIR=${pkgs.openssl.dev}/include
          '';
        };
      }
    );
}
