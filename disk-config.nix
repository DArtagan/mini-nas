# NOTE: disko does not change partitions or zfs datasets after the initial deploy
# You'll have to make the changes manually and then update this file to reflect the new reality
{ lib, ... }:
{
  disko.devices =
    let
      # Note: keep these in sync with the `hddfancontrol` list of hard drives
      rpoolDisks = [
        [
          "/dev/disk/by-id/ata-ST4000DM005-2DP166_ZGY0B2SR"
          "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZGY8DP80"
          "/dev/disk/by-id/ata-ST4000DM005-2DP166_ZGY0B2RP"
        ]
        [
          "/dev/disk/by-id/ata-ST3000DM001-1CH166_Z1F48TA8"
          "/dev/disk/by-id/ata-Hitachi_HUA723030ALA641_YHHT74WA"
          "/dev/disk/by-id/ata-TOSHIBA_DT01ACA300_Z2L4RUPGS"
        ]
      ];
      spoolDisks = [
        [
          "/dev/disk/by-id/ata-TOSHIBA_DT01ACA200_67CVX8BAS"
          "/dev/disk/by-id/ata-TOSHIBA_DT01ACA200_67CVX7YAS"
        ]
      ];
    in
    {
      disk =
        (lib.listToAttrs (
          lib.imap0 (i: device: {
            name = device;
            value = {
              type = "disk";
              # Note: this convoluted system of passing the device name around at
              # every level, and using it to compose into partition names, is so
              # that the disks' serial numbers show up in zpool output - making
              # replacement & debugging easier.
              inherit device;
              content = {
                type = "gpt";
                partitions = {
                  esp = {
                    size = "5G";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot${toString (if i > 0 then i else "")}";
                      mountOptions = [
                        "umask=0077"
                        "nofail"
                      ];
                    };
                  };
                  zfs = {
                    size = "100%";
                    content = {
                      type = "zfs";
                      device = "${device}-part2";
                      pool = "rpool";
                    };
                  };
                };
              };
            };
          }) (lib.lists.flatten rpoolDisks)
        ))
        //

          lib.genAttrs (lib.lists.flatten spoolDisks) (device: {
            type = "disk";
            inherit device;
            content = {
              type = "gpt";
              partitions = {
                swap = {
                  size = "16G";
                  content = {
                    type = "swap";
                    device = "${device}-part1";
                  };
                };
                zfs = {
                  size = "100%";
                  content = {
                    type = "zfs";
                    device = "${device}-part2";
                    pool = "spool";
                  };
                };
              };
            };
          });

      zpool = {
        rpool = {
          type = "zpool";
          mountpoint = null;
          options = {
            ashift = "12";
            autoexpand = "on";
          };
          rootFsOptions = {
            acltype = "posixacl";
            atime = "off";
            checksum = "fletcher4";
            compression = "lz4";
            overlay = "on";
            primarycache = "all";
            recordsize = "128k";
            sync = "standard";
            xattr = "sa";
          };
          mode = {
            topology = {
              type = "topology";
              vdev = map (vdevDisks: {
                mode = "raidz1";
                members = map (d: "${d}-part2") vdevDisks;
              }) rpoolDisks;
            };
          };
          datasets = {
            "rpool/root" = {
              mountpoint = "/";
              type = "zfs_fs";
            };
            "rpool/nix" = {
              mountpoint = "/nix";
              type = "zfs_fs";
            };
            "rpool/var" = {
              mountpoint = "/var";
              type = "zfs_fs";
            };
            "rpool/home" = {
              mountpoint = "/home";
              type = "zfs_fs";
            };
          };
        };

        spool = {
          type = "zpool";
          mountpoint = null;
          options = {
            ashift = "12";
            autoexpand = "on";
          };
          rootFsOptions = {
            acltype = "posixacl";
            atime = "off";
            checksum = "fletcher4";
            compression = "lz4";
            overlay = "on";
            primarycache = "all";
            recordsize = "128k";
            sync = "standard";
            xattr = "sa";
          };
          mode = {
            topology = {
              type = "topology";
              vdev = map (vdevDisks: {
                mode = "raidz1";
                members = map (d: "${d}-part2") vdevDisks;
              }) spoolDisks;
            };
          };
          datasets = { };
        };
      };
    };
}
