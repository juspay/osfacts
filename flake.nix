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
    };
}
