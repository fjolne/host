{ diskDevices, lib, config, ... }:

let
  cfg = config.hetzner.cloud-ext4;
in
{
  options = {
    hetzner.cloud-ext4 = {
      mountOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Mount options for the ext4 filesystem";
      };
      journalMode = lib.mkOption {
        type = lib.types.enum [ "data=ordered" "data=writeback" "data=journal" ];
        default = "data=ordered";
        description = "Journal mode for the ext4 filesystem";
      };
    };
  };

  config = {
    disko.devices = {
      disk = {
        x0 = {
          device = builtins.elemAt diskDevices 0;
          type = "disk";
          content = {
            type = "table";
            format = "gpt";
            partitions = [
              {
                name = "boot";
                start = "0";
                end = "1M";
                part-type = "primary";
                flags = [ "bios_grub" ];
              }
              {
                name = "ESP";
                start = "1MiB";
                end = "900MiB";
                bootable = true;
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              }
              {
                name = "root";
                start = "900MiB";
                end = "100%";
                part-type = "primary";
                bootable = true;
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = [ cfg.journalMode ] ++ cfg.mountOptions;
                };
              }
            ];
          };
        };
      };
    };
  };
}
