{ lib
, stdenvNoCC
, makeWrapper
, bash
, coreutils
, gnutar
, zstd
, gnupg
, gnugrep
, gnused
, gawk
, findutils
, pv
}:

stdenvNoCC.mkDerivation {
  pname = "tarzst";
  version = "3.1";

  src = ../tarzst-project;

  nativeBuildInputs = [ makeWrapper bash ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 tarzst.sh "$out/bin/tarzst"
    ln -s tarzst "$out/bin/zstar"

    patchShebangs "$out/bin/tarzst"

    wrapProgram "$out/bin/tarzst" \
      --prefix PATH : ${lib.makeBinPath [
        bash
        coreutils
        gnutar
        zstd
        gnupg
        gnugrep
        gnused
        gawk
        findutils
        pv
      ]}

    runHook postInstall
  '';

  meta = {
    description = "A professional utility for creating secure, verifiable, and automated tar archives";
    longDescription = ''
      tarzst is a powerful, robust command-line wrapper script for creating
      compressed, verifiable, splittable, and secure tar archives. It integrates
      tar, zstd, and GPG into a seamless workflow with advanced features including
      strict error checking, automatic dependency checking, password protection,
      GPG signing/encryption, file splitting, and self-contained decompression
      script generation.
    '';
    homepage = "https://github.com/8r4n/utility-scripts";
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = lib.platforms.unix;
    mainProgram = "tarzst";
  };
}
