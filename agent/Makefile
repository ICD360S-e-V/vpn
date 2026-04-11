BINARY  := vpn-agent
PKG     := github.com/ICD360S-e-V/vpn/agent/cmd/vpn-agent
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.0.1-m1")
LDFLAGS := -s -w -X main.version=$(VERSION)
GOFLAGS := -trimpath -ldflags='$(LDFLAGS)'

.PHONY: all build clean install vet fmt test

all: build

build:
	CGO_ENABLED=0 go build $(GOFLAGS) -o $(BINARY) $(PKG)

vet:
	go vet ./...

fmt:
	gofmt -s -w .

test:
	go test ./...

clean:
	rm -f $(BINARY)

# Install assumes you are running on the target server (vpn.icd360s.de)
# as root, with the binary already built (`make build`).
install: build
	install -m 0755 $(BINARY) /usr/local/sbin/$(BINARY)
	install -m 0644 systemd/vpn-agent.service /etc/systemd/system/vpn-agent.service
	systemctl daemon-reload
	@echo
	@echo "Installed. Next steps:"
	@echo "  systemctl enable --now vpn-agent"
	@echo "  journalctl -u vpn-agent -f"
