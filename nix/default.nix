{ src
, pkgs
, system
, inputs
, self
}:

let
  ps-lib = import ./lib.nix {
    inherit pkgs easy-ps spagoPkgs nodejs nodeModules;
  };
  # We should try to use a consistent version of node across all
  # project components
  nodejs = pkgs.nodejs-12_x;
  easy-ps = import inputs.easy-purescript-nix { inherit pkgs; };
  spagoPkgs = import ../spago-packages.nix { inherit pkgs; };
  nodeModules =
    let
      modules = pkgs.callPackage
        (_:
          let
            nodePkgs = import ../node2nix.nix {
              inherit pkgs system nodejs;
            };
          in
          nodePkgs // {
            shell = nodePkgs.shell.override {
              # see https://github.com/svanderburg/node2nix/issues/198
              buildInputs = [ pkgs.nodePackages.node-gyp-build ];
            };
          });
    in
    (modules { }).shell.nodeDependencies;
in
{
  defaultPackage = self.packages.${system}.cardano-browser-tx;

  packages = {
    cardano-browser-tx = ps-lib.buildPursProject {
      name = "cardano-browser-tx";
      inherit src;
    };
  };

  # NOTE
  # Since we depend on two haskell.nix projects, `nix flake check`
  # is currently broken because of IFD issues
  checks = {
    cardano-browser-tx = ps-lib.runPursTest {
      name = "cardano-browser-tx";
      subdir = builtins.toString src;
      inherit src;
    };
  };

  # TODO
  # Once we have a public ogmios instance to test against,
  # add `self.checks.${system}` to the `buildInputs`
  check = pkgs.runCommand "combined-check"
    {
      nativeBuildInputs = builtins.attrValues self.packages.${system};

    } "touch $out";

  devShell = import ./dev-shell.nix {
    inherit pkgs system inputs nodeModules easy-ps nodejs;
  };
}