# filestash-nix

filestash-nix implements a NixOS Module, VM Test and Package (Derivation) for
Mickael Kerjean's excellent piece of software
[Filestash](https://github.com/mickael-kerjean/filestash).

## Usage

To use `filestash-nix`, enable the filestash module on a nixosConfiguration in
your `flake.nix`:

```nix
{
  inputs.filestash-nix.url = "github:matthewcroughan/filestash-nix";

  outputs = { self, nixpkgs, filestash-nix }: {
    nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
      modules = [
        {
          services.filestash.enable = true;
        }
      ];
    };
  };
}
```

It is then up to you to reverse proxy to the service on port 8334, for example,
you might want to use [Traefik](https://traefik.io/) to reverse proxy to
`dummy.domain.com`, with automatic LetsEncrypt SSL and HTTPS redirects, which
can be achieved by adding the following configuration:

```nix
{
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.traefik = {
    enable = true;
    dynamicConfigOptions = {
      http.middlewares.redirect-to-https.redirectscheme = {
        scheme = "https";
        permanent = true;
      };
      http = {
        services = {
          filestash.loadBalancer.servers = [ { url = "http://127.0.0.1:8334"; } ];
        };
        routers = {
          filestash-insecure = {
            rule = "Host(`dummy.domain.com`)";
            entryPoints = [ "web" ];
            service = "filestash";
            middlewares = "redirect-to-https";
          };
          filestash = {
            rule = "Host(`dummy.domain.com`)";
            entryPoints = [ "websecure" ];
            service = "filestash";
            tls.certresolver = "letsencrypt";
          };
        };
      };
    };
    staticConfigOptions = {
      entryPoints = {
        web.address = ":80";
        websecure.address = ":443";
        certificatesResolvers = {
          letsencrypt.acme = {
            email = "letsencrypt@domain.com";
#            caServer = "https://acme-staging-v02.api.letsencrypt.org/directory";
            storage = "/var/lib/traefik/cert.json";
          };
        };
      };
    };
  };
}
```

# Why?

The original software packaging is not very reproducible, easy to
install/provision, or share, despite the author's best efforts to use
docker/docker-compose. This NixOS module allows anybody to use Filestash simply
by adding `services.filestash.enable = true;` to their NixOS config, and it will
produce the same result each time, invariably, thanks to Nix.

## VM Test

In order to build the QEMU VM integration test using the NixOS Testing
Framework, run `nix build .#checks.x86_64-linux.filestash`, this will
reproducibly:

1. Spawn two QEMU VMs, one with `environment.systemPackages = [ curl ]` and the
   other with `services.filestash.enable = true`
2. Wait for the filestash systemd service to become available
3. Test that Filestash responds correctly when a request is made with `curl`

The test could be expanded in the future to perform more functions and test the
software more thoroughly.

## Development

### Updating the Filestash flake input

This does not require any contributions, as it is automated by CI, but below is
an explanation of how it works.

Because upstream do not provide a `package-lock.json`, we cannot use dream2nix
directly on it. So, we use dream2nix to provide a `dream-lock.json` instead,
effectively vendoring the upstream's missing lock feature. I have added the
"resolve" script which dream2nix provides to the `passthru` set of the
`filestash` package in this flake, it is available at
`filestash.passthru.updateScript`

To update:

1. `nix flake lock --update-input filestash`
2. `nix run .#filestash.passthru.update`

