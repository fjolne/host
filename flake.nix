{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    srvos.url = "github:numtide/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... }@inputs:
    let
      system = "x86_64-linux";
      host = {
        name = "FIXME";
        hostId = "FIXME"; # generate with: openssl rand -hex 4
        ipv6 = "FIXME";
        diskDevices = [ "/dev/nvme0n1" "/dev/nvme1n1" ];
        adminUser = {
          name = "FIXME";
          initialPassword = "change-me";
          extraGroups = [ "wheel" "docker" "systemd-journal" ];
          authorizedKeys = [
            "FIXME"
          ];
        };
        mdadm = {
          level = 0;
          fs = "ext4";
        };
      };

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };

      baseModule =
        { lib
        , pkgs
        , pkgs-unstable
        , inputs
        , isCloud
        , isArm
        , diskDevices
        , modulesPath
        , hostName
        , hostId
        , ipv6
        , nixpkgsFlake
        , adminUser
        , ...
        }:

        {
          imports = [
            inputs.srvos.nixosModules.server
            (if isCloud then
              if isArm then inputs.srvos.nixosModules.hardware-hetzner-cloud-arm
              else inputs.srvos.nixosModules.hardware-hetzner-cloud
            else inputs.srvos.nixosModules.hardware-hetzner-online-amd)
            "${modulesPath}/installer/scan/not-detected.nix"
            "${modulesPath}/profiles/all-hardware.nix"
            inputs.disko.nixosModules.disko
          ];

          systemd.network.networks."10-uplink".networkConfig.Address = ipv6;
          networking.hostName = hostName;
          networking.hostId = hostId;

          boot.loader.grub = {
            enable = if isCloud && isArm then lib.mkForce false else true;
            devices = diskDevices;
            efiSupport = true;
            efiInstallAsRemovable = true;
          };

          system.stateVersion = "24.11";

          # `nix run nixpkgs#hello` will use nixpkgs from this flake
          nix.registry.nixpkgs.flake = nixpkgsFlake;
          # <nixpkgs> will resolve to this flake
          nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];

          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.nvidia.acceptLicense = true;

          environment.systemPackages = with pkgs; [
            gettext
            lf
            ripgrep
            fd
            bottom
            cloud-utils
            lsof
            nil
            nixpkgs-fmt
            ncdu
            kitty.terminfo
            just
            openssl
            wget
            fio
          ];

          environment.shellAliases = {
            sctl = "systemctl --user";
            jctl = "journalctl --user";
          };

          environment.extraInit = ''
            export PATH="$HOME/.npm-global/bin:$PATH"
          '';

          services.journald.rateLimitBurst = 0;
          services.journald.rateLimitInterval = "0";
          services.journald.extraConfig = ''
            RuntimeMaxUse=1G
            SystemMaxUse=20G
            SystemKeepFree=15G
            MaxFileSec=1month
            SystemMaxFiles=10000
          '';

          networking.firewall = {
            enable = true;
            allowedTCPPorts = [ ];
            allowedUDPPorts = [ ];
            allowPing = true;
            trustedInterfaces = [ ];
          };

          services.openssh.enable = true;
          services.openssh.openFirewall = true;
          services.openssh.settings.PasswordAuthentication = false;
          services.openssh.settings.PermitRootLogin = "no";
          services.openssh.settings.MaxStartups = "20:30:100";
          programs.ssh.startAgent = true;
          programs.mosh.enable = false;

          services.fail2ban.enable = true;
          services.fail2ban.bantime-increment.enable = true;

          programs.direnv.enable = true;
          virtualisation.docker.enable = true;
          virtualisation.docker.package = pkgs-unstable.docker;

          programs.nix-ld.enable = true;
          programs.nix-ld.libraries = with pkgs; [
            rdkafka
          ];

          programs.git.enable = true;
          programs.git.lfs.enable = false;

          nix.gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 14d";
          };

          security.sudo.wheelNeedsPassword = lib.mkForce true;
          users.mutableUsers = lib.mkForce true;
          users.users.${adminUser.name} = {
            inherit (adminUser) initialPassword extraGroups;
            isNormalUser = true;
            openssh.authorizedKeys = {
              keys = adminUser.authorizedKeys;
            };
          };

          systemd.tmpfiles.rules = [
            "f /var/lib/systemd/linger/${adminUser.name}"
            "d /var/lib/socks 0700 root root"
          ];

          services.tailscale.enable = true;
          systemd.services.tailscaled = {
            before = [ "remote-fs-pre.target" ];
            wantedBy = [ "remote-fs-pre.target" ];
            serviceConfig = {
              ExecStartPost = ''${pkgs.bash}/bin/bash -c 'echo "Sleeping for 10 seconds to appear initialized for dependent units..." && sleep 10' '';
            };
          };
        };

      mkHost =
        { name
        , hostId
        , ipv6
        , diskDevices
        , adminUser
        , isCloud ? false
        , isArm ? false
        , mdadm ? null
        , extraModules ? [ ]
        ,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs isCloud isArm diskDevices hostId ipv6 adminUser;
            hostName = name;
            nixpkgsFlake = inputs.nixpkgs;
            pkgs-unstable = pkgs-unstable;
          };
          modules =
            [ baseModule ]
            ++ nixpkgs.lib.optional (mdadm != null) ./disk-configuration.nix
            ++ extraModules
            ++ nixpkgs.lib.optional (mdadm != null) {
              hetzner.mdadm = mdadm;
            };
        };
    in
    {
      nixosConfigurations.${host.name} = mkHost host;
    };
}
