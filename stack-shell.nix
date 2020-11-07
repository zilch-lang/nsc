{
  pkgs ? import <nixpkgs> {}
, ghc ? pkgs.ghc
}:

pkgs.haskell.lib.buildStackProject {
  inherit ghc;

  nativeBuildInputs = with pkgs; [
    haskellPackages.c2hs
    glibc  # for the <elf.h> header
  ];

  name = "nstar-shell";
}
