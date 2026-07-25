# static root for nginx — build with: npm ci && npm run build
{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "tharavad-web";
  version = "0.1.0";
  src = ./dist;

  dontUnpack = true;
  installPhase = ''
    mkdir -p $out
    cp -R $src/. $out/
  '';
}
