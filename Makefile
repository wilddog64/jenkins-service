VERSION := 1.0
TARBALL := SOURCES/jenkins-dist-$(VERSION).tar.gz

$(TARBALL): jenkins.sh jenkins.service plugins.txt
	tar czf $@ --exclude='.git' \
	  jenkins.sh jenkins.service plugins.txt

.PHONY: rpm
rpm: $(TARBALL)
	rpmbuild -ba SPECS/jenkins.spec

