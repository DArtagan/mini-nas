{ lib, ... }:
{
  disko.devices = {
    disk = {
      data1 = {
        type = "disk";
        #device = "/dev/disk/by-id/sda";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";  # TODO: can this be added to the other esp partitions as a fallback?
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              #uuid = "52da0ec8-4a8e-499c-9e90-ee23819960c6";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data2 = {
        type = "disk";
        #device = "/dev/disk/by-id/sdb";
        device = "/dev/vdb";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              #uuid = "016d17e0-729b-46b5-8cc7-67f77f969c6b";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data3 = {
        type = "disk";
        #device = "/dev/disk/by-id/sdc";
        device = "/dev/vdc";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              #uuid = "c22a58ab-38ca-4787-9551-7b571ed20d54";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data4 = {
        type = "disk";
        #device = "/dev/disk/by-id/sdd";
        device = "/dev/vdd";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              #uuid = "69893c27-95a8-4b5e-a78e-9c01b11f4aea";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data5 = {
        type = "disk";
        #device = "/dev/disk/by-id/sde";
        device = "/dev/vde";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              #uuid = "d7ac7254-f437-45d3-a27e-fa61f1265cb4";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data6 = {
        type = "disk";
        #device = "/dev/disk/by-id/sdf";
        device = "/dev/vdf";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              #uuid = "f229d42e-818d-4c56-8da5-8d84023fd049";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data7 = {
        type = "disk";
        #device = "/dev/disk/by-id/sdg";
        device = "/dev/vdg";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              #uuid = "4a1da705-152f-4a5f-8e24-cb0ab66763e0";
              content = {
                type = "zfs";
                pool = "spool";
              };
            };
          };
        };
      };
      data8 = {
        type = "disk";
        #device = "/dev/disk/by-id/sdh";
        device = "/dev/vdh";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              #uuid = "edc8a4c6-cf29-4022-bf2b-ec2648c65af9";
              content = {
                type = "zfs";
                pool = "spool";
              };
            };
          };
        };
      };
    };
    zpool = {
      rpool = {
        type = "zpool";
        mountpoint = "/rpool";
        options = {
          ashift = "12";
          autoexpand = "on";
          cachefile = "none"; # Workaround for `I/O error` when importing zpool after restart
          #bootfs = "rpool/ROOT/pve-1";  # Cannot be set at creation time
        };
        rootFsOptions = {
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
            vdev = [
              {
                mode = "raidz1";
                members = [
                  #"/dev/disk/by-partuuid/52da0ec8-4a8e-499c-9e90-ee23819960c6"
                  #"/dev/disk/by-partuuid/016d17e0-729b-46b5-8cc7-67f77f969c6b"
                  #"/dev/disk/by-partuuid/c22a58ab-38ca-4787-9551-7b571ed20d54"
                  "/dev/disk/by-partlabel/disk-data1-zfs"
                  "/dev/disk/by-partlabel/disk-data2-zfs"
                  "/dev/disk/by-partlabel/disk-data3-zfs"
                  #"/dev/disk/by-id/sda" 
                  #"/dev/disk/by-id/sdb"
                  #"/dev/disk/by-id/sdc"
                ];
              }
              {
                mode = "raidz1";
                members = [
                  #"/dev/disk/by-partuuid/69893c27-95a8-4b5e-a78e-9c01b11f4aea"
                  #"/dev/disk/by-partuuid/d7ac7254-f437-45d3-a27e-fa61f1265cb4"
                  #"/dev/disk/by-partuuid/f229d42e-818d-4c56-8da5-8d84023fd049"
                  "/dev/disk/by-partlabel/disk-data4-zfs"
                  "/dev/disk/by-partlabel/disk-data5-zfs"
                  "/dev/disk/by-partlabel/disk-data6-zfs"
                  #"/dev/disk/by-id/sdd" 
                  #"/dev/disk/by-id/sde"
                  #"/dev/disk/by-id/sdf"
                ];
              }
            ];
          };
        };

        datasets = {
          "ROOT" = {
            type = "zfs_fs";
            mountpoint = "/rpool/ROOT";
          };
          "ROOT/pve-1" = {
            type = "zfs_fs";
            mountpoint = "/";
          };
          "data" = {
            type = "zfs_fs";
            mountpoint = "/rpool/data";
          };

          #rpool = {
          #  type = "zfs_fs";
          #  mountpoint = "/rpool";
          #};
          #"rpool/ROOT" = {
          #  type = "zfs_fs";
          #  mountpoint = "/rpool/ROOT";
          #};
          #"rpool/ROOT/pve-1" = {
          #  type = "zfs_fs";
          #  mountpoint = "/";
          #};
          #"rpool/data" = {
          #  type = "zfs_fs";
          #  mountpoint = "/rpool/data";
          #};
        };
      };

      spool = {
        type = "zpool";
        mountpoint = "/spool";
        options = {
          ashift = "12";
          autoexpand = "on";
        };
        rootFsOptions = {
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
            vdev = [
              {
                mode = "mirror";
                members = [
                  "/dev/disk/by-partlabel/disk-data7-zfs"
                  "/dev/disk/by-partlabel/disk-data8-zfs"
                  #"/dev/disk/by-partuuid/4a1da705-152f-4a5f-8e24-cb0ab66763e0"
                  #"/dev/disk/by-partuuid/edc8a4c6-cf29-4022-bf2b-ec2648c65af9"
                ];
              }
            ];
          };
        };

        datasets = { };
      };
    };
  };
}
