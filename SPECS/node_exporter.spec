%global debug_package %{nil}

Name:           prometheus-node-exporter
Version:        %{pkg_version}
Release:        %{rpm_release}%{?dist}
Summary:        Prometheus exporter for machine metrics.
License:        ASL 2.0
URL:            https://prometheus.io

Source0:        node_exporter-%{pkg_version}.linux-amd64.tar.gz
Source1:        %{name}.service
Source2:        logrotate.conf
Source3:        rsyslog.conf
Source4:        environment.conf

BuildRoot:      %{buildroot}
BuildRequires:  systemd-units
Requires:       systemd, logrotate, rsyslog > 7.2
Requires(pre):  shadow-utils

%description

Prometheus is a systems and service monitoring system. It collects metrics from
configured targets at given intervals, evaluates rule expressions, displays the
results, and can trigger alerts if some condition is observed to be true.

This package contains binary to export node metrics to prometheus.

%prep
%setup -q -n node_exporter-%{version}.linux-amd64

%install
# 0.15.0 = 0*50^2+15*50^1+0*50^0 = 750. See version_to_number()
BREAKING_VERSION_INT='750'
# 1.0.0 = 1*50^2+0*50^1+0*50^0 = 2500. See version_to_number()
BREAKING_VERSION_LOGGER_INT="2500"

function version_to_number() {
    # To see if we have package version greater than 0.15.0 we are going to replace '.' and '-'
    # in version string with ' ', then multiply each number with $base^exponent. Exponent starts off
    # as count of numbers in string obtained after substituting '.' and '-' with ' ', and decreases
    # by 1 each time it used. Numbers are processed from left to right. Therefore, most significant
    # digit on left (or in beginning of string) gets the highest exponent.
    # The $base value determines the range of versions for which this computation produces non-
    # overlapping results. E.g. $base=50 -> 0.0.0-49.49.49 range.

    version="$1"
    nums=$(echo "$version" | tr -s '.-' ' ')
    total_nums=$(echo "$nums" | wc -w)
    base=50
    ret_val=0
    exponent=$((total_nums - 1))
    for n in $nums; do
        ret_val=$(( ret_val + base**exponent * n ))
        exponent=$((--exponent))
    done
    echo $ret_val
}

current_version_int=$(version_to_number "%{version}")

# Directory for storing log files.
mkdir -p %{buildroot}%{_localstatedir}/log/prometheus

# Logrotate config
mkdir -p %{buildroot}%{_sysconfdir}/logrotate.d/
install -m 644 %{SOURCE2} %{buildroot}%{_sysconfdir}/logrotate.d/%{name}.conf

# RSyslog config to enable writing to a file.
mkdir -p %{buildroot}%{_sysconfdir}/rsyslog.d/
install -m 644 %{SOURCE3} %{buildroot}%{_sysconfdir}/rsyslog.d/%{name}.conf

# SystemD unit definition and environment settings to go alongside unit file.
systemd_unit_dir="%{buildroot}%{_unitdir}"
systemd_unit_file="$systemd_unit_dir/%{name}.service"
mkdir -p $systemd_unit_dir
install -m 644 %{SOURCE1} $systemd_unit_file

# Add another hyphen if package version is >= 0.15.0, else delete placeholder (RPM_EXTRA_HYPHEN)
if [ "$current_version_int" -ge "$BREAKING_VERSION_INT" ]; then
    sed -i'' 's|RPM_EXTRA_HYPHEN|-|g' $systemd_unit_file
else
    sed -i'' 's|RPM_EXTRA_HYPHEN||g' $systemd_unit_file
fi

# Make dependency directory for unit, and put environment file in there.
environment_conf_dir="$systemd_unit_dir/%{name}.service.d"
environment_conf_file="$environment_conf_dir/environment.conf"
mkdir -p $environment_conf_dir
install -m 644 %{SOURCE4} $environment_conf_file

# Apply new logging configuration if the package version is >= 1.0.0.
if [ "$current_version_int" -ge "$BREAKING_VERSION_LOGGER_INT" ]; then
    sed -i'' 's|RPM_LOG_FORMAT|logfmt|g' $environment_conf_file
else
    sed -i'' 's|RPM_LOG_FORMAT|logger:stderr|g' $environment_conf_file
fi

# Binaries
mkdir -p %{buildroot}%{_bindir}
install -m 755 node_exporter %{buildroot}%{_bindir}/node_exporter

# Copy over License and notice
mkdir -p %{buildroot}/usr/share/prometheus/node_exporter
install -m 644 LICENSE %{buildroot}/usr/share/prometheus/node_exporter/LICENSE
install -m 644 NOTICE %{buildroot}/usr/share/prometheus/node_exporter/NOTICE

%pre
getent group prometheus >/dev/null || groupadd -r prometheus
getent passwd prometheus >/dev/null || \
  useradd -r -g prometheus -s /sbin/nologin \
          -c "Prometheus services" prometheus

%post
%systemd_post %{name}.service

echo
echo "NOTES ##############################################################################"
echo "Please restart RSyslog so that logs are written to %{_localstatedir}/log/prometheus"
echo "    systemctl restart rsyslog.service"
echo "To have %{name} start automatically on boot:"
echo "    systemctl enable %{name}.service"
echo "Start %{name}:"
echo "    systemctl daemon-reload"
echo "    systemctl start %{name}.service"
echo "####################################################################################"
echo

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun %{name}.service

%files
%defattr(-,prometheus,prometheus,-)
%attr(755, root, root) %{_bindir}/node_exporter
%config(noreplace) %attr(644, root, root) %{_sysconfdir}/logrotate.d/%{name}.conf
%config(noreplace) %attr(644, root, root) %{_sysconfdir}/rsyslog.d/%{name}.conf
%config(noreplace) %{_unitdir}/%{name}.service
%config(noreplace) %{_unitdir}/%{name}.service.d/environment.conf
# Log directory
%dir %attr(755, prometheus, prometheus) %{_localstatedir}/log/prometheus

/usr/share/prometheus/node_exporter
/usr/share/prometheus/node_exporter/NOTICE
/usr/share/prometheus/node_exporter/LICENSE

%changelog

* Sun Feb 04 2019 talk@devghai.com
- Added support for handling breaking changes introduced in 0.15.0.

* Tue May 23 2017 talk@devghai.com
- Initial release for packaging Prometheus's Node Exporter.
  See https://github.com/meowtochondria/node_exporter-rpm/blob/master/README.md.

