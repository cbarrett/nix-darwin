{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.mysql;

  mysql = cfg.package;

  isMariaDB = lib.getName mysql == lib.getName pkgs.mariadb;

  mysqldOptions =
    "--defaults-file=/etc/my.cnf --datadir=${cfg.dataDir} --basedir=${mysql}";
  # For MySQL 5.7+, --insecure creates the root user without password
  # (earlier versions and MariaDB do this by default).
  installOptions =
    "${mysqldOptions} ${lib.optionalString (!isMariaDB) "--insecure"}";
in

{

  ###### interface

  options = {

    services.mysql = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "
          Whether to enable the MySQL server.
        ";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.mysql;
        description = "
          Which MySQL derivation to use. MariaDB packages are supported too.
        ";
      };

      bind = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = literalExample "0.0.0.0";
        description = "Address to bind to. The default is to bind to all addresses";
      };

      port = mkOption {
        type = types.int;
        default = 3306;
        description = "Port of MySQL";
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/mysql";
        description = "Location where MySQL stores its table files";
      };

      extraOptions = mkOption {
        type = types.lines;
        default = "";
        example = ''
          key_buffer_size = 6G
          table_cache = 1600
          log-error = /var/log/mysql_err.log
        '';
        description = ''
          Provide extra options to the MySQL configuration file.

          Please note, that these options are added to the
          <literal>[mysqld]</literal> section so you don't need to explicitly
          state it again.
        '';
      };
    };

  };


  ###### implementation

  config = mkIf config.services.mysql.enable {

    environment.systemPackages = [mysql];

    environment.etc."my.cnf".text =
    ''
      [mysqld]
      port = ${toString cfg.port}
      datadir = ${cfg.dataDir}
      ${optionalString (cfg.bind != null) "bind-address = ${cfg.bind}" }
      ${cfg.extraOptions}
    '';

    launchd.user.agents.mysql =
      { path = [
          mysql
          # Needed for the mysql_install_db command which calls
          # the hostname command.
          pkgs.nettools
        ];
        script = ''
          ${optionalString isMariaDB ''
            if ! test -e ${cfg.dataDir}/mysql; then
              ${mysql}/bin/mysql_install_db ${installOptions}
            fi
          ''}
          exec ${mysql}/bin/mysqld ${if isMariaDB then mysqldOptions else installOptions}
        '';
        serviceConfig.KeepAlive = true;
        serviceConfig.RunAtLoad = true;
      };
  };
}
