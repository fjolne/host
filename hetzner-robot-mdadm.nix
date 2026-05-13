{ diskDevices, lib, config, pkgs, ... }:

let
  cfg = config.hetzner."robot-mdadm";
in
{
  options = {
    hetzner."robot-mdadm" = {
      level = lib.mkOption {
        type = lib.types.enum [ 0 1 10 5 6 7 ];
        default = 0;
      };
      fs = lib.mkOption {
        type = lib.types.enum [ "ext4" "xfs" ];
        default = "ext4";
      };
    };
  };

  config = {
    # Provide an explicit monitor target so mdadm does not start with a
    # known-bad default configuration on RAID hosts.
    boot.swraid.mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";

    disko.devices = {
      disk = lib.listToAttrs
        (map
          (i: {
            name = "x${toString i}";
            value = {
              type = "disk";
              device = builtins.elemAt diskDevices i;
              content = {
                type = "table";
                format = "gpt";
                partitions = [
                  {
                    name = "boot";
                    start = "0";
                    end = "1MiB";
                    part-type = "primary";
                    flags = [ "bios_grub" ];
                  }
                  {
                    name = "ESP";
                    start = "1MiB";
                    end = "900MiB";
                    bootable = true;
                    content = {
                      type = "mdraid";
                      name = "boot";
                    };
                  }
                  {
                    name = "data";
                    start = "900MiB";
                    end = "100%";
                    part-type = "primary";
                    bootable = true;
                    content = {
                      type = "mdraid";
                      name = "data";
                    };
                  }
                ];
              };
            };
          })
          (lib.range 0 (lib.length diskDevices - 1)));
      mdadm = {
        boot = {
          type = "mdadm";
          level = 1;
          metadata = "1.0";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        data = {
          type = "mdadm";
          level = cfg.level;
          content = {
            type = "gpt";
            partitions.primary = {
              size = "100%";
              content = {
                type = "filesystem";
                format = cfg.fs;
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
