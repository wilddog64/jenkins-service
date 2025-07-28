# Makefile

VERSION    := 1.0
SOURCEDIR  := $(CURDIR)/SOURCES
TARBALL    := $(SOURCEDIR)/jenkins-dist-$(VERSION).tar.gz
SPEC       := SPECS/jenkins.spec

.PHONY: all tarball rpm clean

all: rpm

## 1) Create the tarball of your three source files
tarball: $(TARBALL)

$(TARBALL): jenkins.sh jenkins.service plugins.txt | $(SOURCEDIR)
	@echo "→ Packing $$@"
	tar czf $@ --exclude='.git' jenkins.sh jenkins.service plugins.txt

$(SOURCEDIR):
	@mkdir -p $@

## 2) Build the RPM, pointing rpmbuild at our SOURCES dir
rpm: tarball
	@echo "→ Building RPM"
	rpmbuild \
	  --define "_sourcedir $(SOURCEDIR)" \
	  -ba $(SPEC)

clean:
	@echo "→ Cleaning up"
	@rm -f $(TARBALL)

