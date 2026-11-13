SHELL := /bin/bash

SCRIPTS := get.sh install.sh uninstall.sh \
           scripts/warp-keeper.sh scripts/zen-lane.sh scripts/zen-guard.sh \
           scripts/zen-hop.sh scripts/doctor.sh scripts/desktop-patch.sh

.PHONY: check install uninstall doctor hop

check:
	@for f in $(SCRIPTS); do \
		printf 'bash -n %s ... ' "$$f"; \
		bash -n "$$f" && echo ok || exit 1; \
	done

install:
	./install.sh

uninstall:
	./uninstall.sh

doctor:
	opencode-unlimited-doctor

hop:
	opencode-unlimited-hop
