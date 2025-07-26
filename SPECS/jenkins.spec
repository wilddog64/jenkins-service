Name:           jenkins-service
Version:        1.0
Release:        1%{?dist}
Summary:        Jenkins Service wrapper + custom RPM
License:        MIT
URL:            https://jenkins.io

# Your source tarball excludes .git by design
Source0:        jenkins-dist-%{version}.tar.gz
Source1:        plugins.txt

BuildArch:      noarch
Requires:       service, curl

%description
Installs a Docker-based Jenkins service:
• puts jenkins.sh in /usr/local/bin
• drops /etc/systemd/system/jenkins.service
• creates a 'jenkins' system user (no shell)
• at build time, fetches plugins from updates.jenkins.io into
  /var/lib/jenkins/plugins
• excludes any .git directories from SOURCES
• provides a basic %check to verify plugin files exist in the RPM

%prep
# un-tar jenkins.sh, jenkins.service, plugins.txt (no .git here)
%setup -q -c -T
tar xzf %{SOURCE0}
# bring in the plugins list
cp %{SOURCE1} .

%build
# no compilation

%install
# 1) binaries & service unit
install -d %{buildroot}/usr/local/bin
install -m0755 jenkins.sh %{buildroot}/usr/local/bin/jenkins.sh

install -d %{buildroot}/etc/systemd/system
install -m0644 jenkins.service %{buildroot}/etc/systemd/system/

# 2) jenkins data & plugin dir
install -d %{buildroot}/var/lib/jenkins/plugins

# 3) download each plugin HPI
while read -r line; do
  # split by colon → name + optional version
  IFS=: read -r name ver <<<"$line"
  if [[ -n "$ver" ]]; then
    url="https://updates.jenkins.io/download/plugins/${name}/${ver}/${name}.hpi"
  else
    url="https://updates.jenkins.io/latest/${name}.hpi"
  fi
  curl -sSL "$url" -o \
    %{buildroot}/var/lib/jenkins/plugins/${name}.hpi
done < plugins.txt

# 4) ensure perms for Jenkins (runtime)
install -d %{buildroot}/var/lib/jenkins
chmod 700   %{buildroot}/var/lib/jenkins
chmod 600   %{buildroot}/var/lib/jenkins/plugins/*.hpi

%pre
# create jenkins user & group if needed
getent group jenkins >/dev/null || groupadd --system jenkins
getent passwd jenkins >/dev/null || \
  useradd --system --gid jenkins \
          --home-dir /var/lib/jenkins \
          --shell /usr/sbin/nologin jenkins

# add to docker group so service can start containers
getent group docker >/dev/null || groupadd docker
usermod -aG docker jenkins

%post
# enable & start via systemd
%systemd_post jenkins.service

%preun
%systemd_preun jenkins.service

%postun
%systemd_postun_with_restart jenkins.service

%check
# sanity check: each plugin listed must be in the RPM
cd %{buildroot}/var/lib/jenkins/plugins
for line in $(cat %{SOURCE1}); do
  name=${line%%:*}
  test -f "${name}.hpi" || { echo "Missing plugin ${name}.hpi"; exit 1; }
done

%files
%defattr(-,root,root,-)
# your control scripts & unit
/usr/local/bin/jenkins.sh
/etc/systemd/system/jenkins.service

# the data dir (owner at runtime is jenkins)
%attr(0755,jenkins,jenkins) /var/lib/jenkins
%attr(0755,jenkins,jenkins) /var/lib/jenkins/plugins
%attr(0644,jenkins,jenkins) /var/lib/jenkins/plugins/*.hpi

%changelog
* Wed Jul 30 2025 You <you@example.com> - 1.0-1
- Initial packaging of jenkins.sh & jenkins.service
- Excluded .git, bundled plugins via plugins.txt, and added %check

