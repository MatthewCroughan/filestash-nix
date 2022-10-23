{ nixosTest, pkgs, nixosModule }:
nixosTest {
  name = "filestash";
  nodes = {
    client = { ... }: {
      environment.systemPackages = with pkgs; [ curl jq ];
    };
    server = { ... }: {
      imports = [ nixosModule ];
      networking.firewall.allowedTCPPorts = [ 8334 ];
      services.filestash.enable = true;
    };
  };
  testScript = ''
    start_all()
    client.wait_for_unit("multi-user.target")
    server.wait_for_unit("multi-user.target")

    server.wait_for_unit("filestash.service")

    with subtest("Check that the Filestash webserver can be reached."):
        assert "Filestash" in client.succeed(
            "curl -sSf http:/server:8334/manifest.json | jq '.name'"
        )
    # Test that the endpoint 'admin/setup' does not 404, if it does, we've done
    # something wrong, or the program has changed substantially
    client.succeed("curl --fail http://server:8334/admin/setup --fail")
  '';
}
