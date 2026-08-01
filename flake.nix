# osfacts's own flake, now that the directory has moved and stands on its own:
#
#     nix run .#osfacts            # the binary
#
# ZERO inputs, still. The nixpkgs it builds against is npins-backed and reached
# through nix/each-system.nix — no flake input, no flake.lock, one pin. The
# build itself lives in ./default.nix, so this flake and a bare `nix-build` can
# never build two osfacts. The extraction gap the kolu copy of this file named
# is closed here: the pin came along with the directory (same revision), and
# the import is no longer relative to a repository above.
{
  outputs = { ... }:
    let
      platform = import ./nix/each-system.nix;
    in
    {
      packages = platform.withPkgs (pkgs:
        let
          osfacts = import ./default.nix { inherit pkgs; };
        in
        { inherit osfacts; default = osfacts; });

      # The toolchains the two non-sandboxed lanes need, from the same pin the
      # package builds against. `nix develop` evaluates purely — npins fetches
      # by hash — so nothing here needs `--impure`.
      devShells = platform.withPkgs (pkgs: {
        # Lane 2 (scripts/live-oracle.sh) drives cargo against a real host,
        # outside the build sandbox. It still gets the pinned toolchain, never
        # an ambient rustc. libiconv rides `buildInputs` rather than `packages`
        # so darwin's link path is set by the cc wrapper — `nix shell` only puts
        # binaries on PATH, which is why that form needed LIBRARY_PATH and
        # RUSTFLAGS wired by hand and this one does not.
        default = pkgs.mkShell {
          packages = [ pkgs.cargo pkgs.rustc ];
          buildInputs = pkgs.lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.libiconv;
        };

        # Lane 3 — the TypeScript client's own toolchain.
        client-ts = pkgs.mkShell {
          packages = [ pkgs.nodejs pkgs.pnpm ];
        };
      });
    };
}
