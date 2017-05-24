# prometheus-node-exporter

## Introduction

Code to package various versions of Prometheus project's node_exporter with minimum external dependencies.

## Features

* Includes logrotate and rsyslog config to manage and write logs to `/var/log/prometheus/node_exporter.log`.
* Has SystemD setup to restart node_exporter on failure.
* Tries to find a balance between practical conventions and file system hierarchy specification at http://www.pathname.com/fhs/pub/fhs-2.3.html.
* Creates its own user and group called `prometheus` with no interactive shell configured.
* Various paths that will appear after installation:
    * Bin path for `node_exporter`: `/usr/bin`
    * Path to store LICENSE and NOTICE: `/usr/share/prometheus/node_exporter`
    * Log file: `/var/log/prometheus/node_exporter.log`
    * Logrotate config: `/etc/logrotate.d/prometheus-node-exporter.conf`
    * RSyslog config: `/etc/rsyslog.d/prometheus-node-exporter.conf`
    * SystemD Unit definiton: `/usr/lib/systemd/system/prometheus-node-exporter.service`
    * Environment variables: `/usr/lib/systemd/system/prometheus-node-exporter.service.d/environment.conf`

## Pre-requisites

* RedHat or its derivatives like CentOS.
* Network connection to public internet to reach repositories and github.

## Limitations

* Script has been only tested on CentOS 7 to package latest available node_exporter. Please feel free to make pull requests if you want to add more nuanced support for older versions.
* No guarantees are being made for fitness of purpose or merchantabilities. Any results of usage of work herein is not author's or contributor's responsibility.

## Usage

* Clone the repo.
* Build with default settings (build tree in current directory, latest version of Prometheus)
    ```
    ./build.sh
    ```
* See various options available by looking at help:
    ```
    ./build.sh -h
    ```
* See versions available upstream (because there are huge number of releases upstream and there is no caching going, script takes a few seconds to execute)
    ```
    ./build.sh -l
    ```
* Because the new packages like prometheus should not make changes to systemd configuration, notice appears after installation that tells how to modify various services.
    ```
    NOTES ############################################################################
    Please restart RSyslog so that logs are written to /var/log/prometheus:
        systemctl restart rsyslog.service
    To have prometheus start automatically on boot:
        systemctl enable prometheus-node-exporter.service
    Start prometheus:
        systemctl daemon-reload
        systemctl start prometheus-node-exporter.service
    ##################################################################################
    ```

## License

Apache License 2.0