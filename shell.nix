with (import <nixpkgs> { });

pkgs.mkShell {
  buildInputs = [
    pkgs.nasm
    pkgs.gcc
    pkgs.gcc.libc
    pkgs.gdb
  ];
}
