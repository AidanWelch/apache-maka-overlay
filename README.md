# apache-maka-overlay
Nix flake for Apache Maka

Using as an overlay in a flake based system is as simple as

```nix
{
  # flake.nix
  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  
  # ...

  inputs.maka-overlay = {
    url = "github:AidanWelch/apache-maka-overlay";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    {
      nixosConfigurations.your_system = nixpkgs.lib.nixosSystem {
        modules = [
          {nixpkgs.overlays = [
            # ...
            inputs.maka-overlay.overlays.default
            # ...
          ];}
          ./configuration.nix
          # ...
        ];
      };
    };
}
```

And then you will find it in your nixpkgs as `apache-maka`
