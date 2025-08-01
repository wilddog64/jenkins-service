# Makefile

JENKINS_TAG ?= 2.516.1
SOURCEDIR  := $(CURDIR)/SOURCES
TARBALL    := $(SOURCEDIR)/jenkins-service-$(JENKINS_TAG).tar.gz
SPEC       := SPECS/jenkins.spec

.PHONY: all tarball rpm clean

all: rpm

## 1) Create the tarball of your three source files
tarball: $(TARBALL)

$(TARBALL): jenkins.sh jenkins.service $(SOURCEDIR)/plugins.txt | $(SOURCEDIR)
	@echo "→ Packing $$@"
	tar czf $@ --exclude='.git' jenkins.sh jenkins.service $(SOURCEDIR)/plugins.txt

$(SOURCEDIR):
	@mkdir -p $@


## 2) Build the RPM, pointing rpmbuild at our SOURCES dir
rpm: tarball
	@echo "→ Building RPM"
	rpmbuild \
	  --define "_sourcedir $(SOURCEDIR)" \
	  -ba $(SPEC)

smoketest: rpm
	sudo dnf -y install ~/rpmbuild/RPMS/noarch/$(RPM)
	sudo systemctl daemon-reload
	sudo systemctl start jenkins.service
	@echo "Waiting 15s for container…"
	sleep 15
	sudo podman ps | grep -q $(JENKINS_TAG) && echo "✓ smoke test OK" || \
	  (echo "✗ container not running" && exit 1)

clean:
	@echo "→ Cleaning up"
	@rm -f $(TARBALL)

