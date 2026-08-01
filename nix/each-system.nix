# The systems osfacts supports.
#
# Keep this list and the npins-backed nixpkgs import in one place so nothing
# grows a second platform or pin source of truth. `mapSystems` deliberately
# does not import nixpkgs; output projections that already have a per-system
# package set can reuse it without evaluating the pin a second time.
let
  systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
  mapSystems = f:
    builtins.listToAttrs (map
      (system: {
        name = system;
        value = f system;
      })
      systems);
in
{
  inherit mapSystems;
  withPkgs = f:
    mapSystems
      (system: f (import ./nixpkgs.nix { inherit system; }));
}
