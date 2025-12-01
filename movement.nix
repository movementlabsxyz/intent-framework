{ stdenv, fetchurl, lib, gnutar, gzip }:

let
  # Movement CLI for testnet (Move 2 support)
  # Reference: https://docs.movementnetwork.xyz/devs/movementcli
  
  platform = 
    if stdenv.isDarwin && stdenv.isAarch64 then "macos-arm64"
    else if stdenv.isDarwin then "macos-x86_64"
    else if stdenv.isLinux && stdenv.isAarch64 then "linux-arm64"
    else if stdenv.isLinux then "linux-x86_64"
    else throw "Unsupported platform ${stdenv.system}";

  # Movement CLI testnet (Move 2) release URLs
  urls = {
    "macos-arm64" = "https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-macos-arm64.tar.gz";
    "macos-x86_64" = "https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-macos-x86_64.tar.gz";
    # Linux binaries - using same release tag, adjust if different
    "linux-arm64" = "https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-linux-arm64.tar.gz";
    "linux-x86_64" = "https://github.com/movementlabsxyz/homebrew-movement-cli/releases/download/bypass-homebrew/movement-move2-testnet-linux-x86_64.tar.gz";
  };

  # SHA256 hashes for each platform
  hashes = {
    "macos-arm64" = "sha256-lZAnkdRhf7VUz3vRkn/EqkYf20jEsFkyJ4qRIGi+FPg=";
    "macos-x86_64" = lib.fakeSha256;  # TODO: get hash when needed
    "linux-arm64" = lib.fakeSha256;   # TODO: get hash when needed
    "linux-x86_64" = "sha256-R8iOnVPWqnxGh6IiaHH9jA4tx4SjaW9WVZs+CGorVqU=";
  };

in stdenv.mkDerivation rec {
  pname = "movement-cli";
  version = "move2-testnet";

  src = fetchurl {
    url = urls.${platform};
    sha256 = hashes.${platform};
  };

  nativeBuildInputs = [ gnutar gzip ];

  unpackPhase = ''
    tar -xzf $src
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp movement $out/bin/movement
    chmod +x $out/bin/movement
  '';

  meta = with lib; {
    description = "Movement CLI for Move 2 testnet";
    homepage = "https://docs.movementnetwork.xyz/devs/movementcli";
    platforms = [ "x86_64-darwin" "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
  };
}

