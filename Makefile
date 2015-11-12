PREFIX=/usr/local
BINDIR=$(PREFIX)/bin

all:
	@echo "Run \"sudo make install\" to install"

install:
	install -m 0755 cqemu.sh $(BINDIR)/cqemu
