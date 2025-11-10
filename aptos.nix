{ stdenv, fetchurl, lib, unzip }:

let
  os =
    if stdenv.isDarwin then "MacOSX"
    else if stdenv.isLinux then "Ubuntu"
    else throw "Unsupported platform ${stdenv.system}";

  # Aptos CLI v7.10.2 release asset hashes (base64 Nix form)
  sha256 = if os == "MacOSX" then "sha256-cM/70SrBkBZB+hsyByAlHjBKVy6wFkjQ6jE6MaZauEI="
            else "sha256-ZS+tWYCKbBynbUua0jvhOv++a03Ho625kj3ldUJRB80=";

in stdenv.mkDerivation rec {
  pname = "aptos-cli";
  version = "7.10.2";

  src = fetchurl {
    url = if os == "MacOSX"
      then "https://github.com/aptos-labs/aptos-core/releases/download/${pname}-v${version}/${pname}-${version}-macOS-x86_64.zip"
      else "https://github.com/aptos-labs/aptos-core/releases/download/${pname}-v${version}/${pname}-${version}-Ubuntu-22.04-x86_64.zip";
    sha256 = sha256;
  };

  buildInputs = [ unzip ];

  unpackPhase = ''
    unzip $src
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp aptos $out/bin/aptos
  '';

  meta = with lib; {
    description = "Aptos CLI";
    homepage = "https://github.com/aptos-labs/aptos-core";
    platforms = [ "x86_64-darwin" "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
  };
}