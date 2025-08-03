# Makefile

JENKINS_TAG ?= 2.516.1
SOURCEDIR  := $(CURDIR)/SOURCES
TARBALL    := $(SOURCEDIR)/jenkins-service-$(JENKINS_TAG).tar.gz
SPEC       := SPECS/jenkins.spec
PLUGINS_LIST := $(SOURCEDIR)/plugins.txt
# config at top, same as above
SSH_USER   := admin
SSH_HOST   := localhost
SSH_PORT   := 2233

.PHONY: all tarball rpm clean

all: rpm

## 1) Create the tarball of your three source files
tarball: $(TARBALL)

$(TARBALL): jenkins.sh jenkins.service $(SOURCEDIR)/plugins.txt | $(SOURCEDIR)
	@echo "→ Packing $$@"
	tar czf $@ --exclude='.git' jenkins.sh jenkins.service $(SOURCEDIR)/plugins.txt

$(SOURCEDIR):
	@mkdir -p $@

require-corejenkins-for-plugins:
	@generate-jenkins-plugins-installlist.sh $(JENKINS_TAG)

find-plugins-upgrade-for:
	@find-plugins-upgrade-for.sh $(JENKINS_TAG) $(PLUGINS_LIST)

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

jenkins-cli:
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if [ -z "$$args" ]; then \
		echo "Usage: make jenkins-cli <jenkins-cli args…>"; \
		exit 1; \
	fi; \
	ssh -p $(SSH_PORT) $(SSH_USER)@$(SSH_HOST) $$args

clean:
	@echo "→ Cleaning up"
	@rm -f $(TARBALL)

%::
	@:
