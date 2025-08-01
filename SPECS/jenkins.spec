Name:           jenkins-service
Version:        1.0
Release:        2%{?dist}
Summary:        Jenkins in Docker + RPM wrapper

License:        MIT
URL:            https://github.com/wilddog64/jenkins-service
Source0:        %{name}-%{version}.tar.gz
Source1:        jenkins-sudoers
Source2:        jenkins.sysconfig

# ---- Runtime ----
# Jenkins is started via podman; docker is an acceptable alternative
Requires:       (podman or docker)

# ---- Build-time smoke test ----
BuildRequires:  podman
Requires(pre):  shadow-utils

BuildArch:      noarch
Requires:       docker

%undefine _source_date_epoch_from_changelog 0

%description
• Installs your jenkins.sh and your unmodified jenkins.service
• Creates a non-root 'jenkins' user in docker group
• Drops plugins.txt into /etc/jenkins for in-container install
• Grants that user passwordless reload/restart rights via sudoers
• Optionally lets you override image and ports via sysconfig

%pre
# groupadd/useradd run as root during rpm -i/-U
getent group  jenkins >/dev/null || groupadd -r jenkins
getent passwd jenkins >/dev/null || \
    useradd -r -g jenkins -d /var/lib/jenkins \
            -s /sbin/nologin -c "Jenkins CI service user" jenkins

%prep
# unpack your three files
%setup -q -c -T
tar xzf %{SOURCE0}

%build
# no build needed

%install
# 1) control script
install -d %{buildroot}/usr/local/bin
install -m0755 jenkins.sh %{buildroot}/usr/local/bin/jenkins.sh

# 2) systemd unit (exact copy)
install -d %{buildroot}/etc/systemd/system
install -m0644 jenkins.service %{buildroot}/etc/systemd/system/jenkins.service

install -d %{buildroot}%{_sysconfdir}/sudoers.d
install -m 440 %{SOURCE1} %{buildroot}%{_sysconfdir}/sudoers.d/jenkins-sudoers

# 3) optional sysconfig
install -d %{buildroot}/etc/sysconfig
install -m0644 %{SOURCE2} %{buildroot}/etc/sysconfig/jenkins.sysconfig

# 4) plugin list for container
install -d %{buildroot}/etc/jenkins
install -m0644 plugins.txt %{buildroot}/etc/jenkins/plugins.txt

# create /var/lib/jenkins directory
install -d %{buildroot}%{_localstatedir}/lib/jenkins
# 5) sudoers fragment
# getent group docker >/dev/null || groupadd docker
# usermod -aG docker jenkins

%post
chown -R jenkins:jenkins /var/lib/jenkins 2>/dev/null || :
%systemd_post jenkins.service

%preun
%systemd_preun jenkins.service

%postun
%systemd_postun_with_restart jenkins.service

%files
%defattr(-,root,root,-)
/usr/local/bin/jenkins.sh
/etc/systemd/system/jenkins.service
/etc/sysconfig/jenkins.sysconfig
/etc/jenkins/plugins.txt
/etc/sudoers.d/jenkins-sudoers
%attr(0700,jenkins,jenkins) /var/lib/jenkins
%attr(0440,root,root) %config(noreplace) %{_sysconfdir}/sudoers.d/jenkins-sudoers

%check
 # 1) Podman is present
 podman info --format '{{ .Host.OCIRuntime.Name }} {{ .Version.Version }}'

 # 2) sudoers entry parses cleanly
 visudo -cf %{buildroot}%{_sysconfdir}/sudoers.d/jenkins-sudoers

 sleep 3
 podman ps | grep -q 'jenkins-lts'
 # sudo -u jenkins %{buildroot}%{_bindir}/jenkins.sh stop
 podman ps -a | grep -v 'jenkins-lts'

%changelog
* Thu Jul 31 2025 You <ckm.liang@gmail.com> - 1.0-1
- Initial RPM: packages jenkins.sh, jenkins.service (untouched), plugins.txt
- Creates non-root jenkins user, docker group membership, sudoers for reload/restart

