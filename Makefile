.PHONY: fetch-zim up down logs deploy-keys dist-certs test-deploy

# Which ZIM to serve locally. Matches the KIWIX_BOOK env var the platform
# reads, so the two stay in sync without either side hardcoding the other.
#
# wikipedia_en_100_nopic (~15 MB) has almost no real inter-article links.
# Most link targets aren't in its ~5,200-entry archive, so they get pruned
# during ZIM generation. wikipedia_en_top_nopic (~2.2 GB) has real linking
# (928K entries) and is a fast stand-in; wikipedia_en_all_nopic (~52 GB) is
# the full encyclopedia and the default, for content parity with competition
# day. The tiny book is still there for a fast smoke test that the wiring
# works, not for testing crawler search logic.
KIWIX_BOOK ?= wikipedia_en_all_nopic

ZIM_DIR := .data/zim
ZIM_PATH := $(ZIM_DIR)/$(KIWIX_BOOK).zim

# The upstream mirror publishes ZIMs with a build date in the filename, which
# changes over time. Pin the dated source URL per book here; the fetched file
# is saved WITHOUT the date (see ZIM_PATH above) so docker-compose and
# KIWIX_BOOK config never need to know the current date, only the book name.
ifeq ($(KIWIX_BOOK),wikipedia_en_100_nopic)
ZIM_SOURCE := wikipedia_en_100_nopic_2026-07.zim
else ifeq ($(KIWIX_BOOK),wikipedia_en_top_nopic)
ZIM_SOURCE := wikipedia_en_top_nopic_2026-06.zim
else ifeq ($(KIWIX_BOOK),wikipedia_en_all_nopic)
ZIM_SOURCE := wikipedia_en_all_nopic_2026-06.zim
else
$(error Unknown KIWIX_BOOK '$(KIWIX_BOOK)'; add its dated filename to the Makefile)
endif

ZIM_URL := https://download.kiwix.org/zim/wikipedia/$(ZIM_SOURCE)

# Downloads the configured ZIM snapshot if it isn't already present.
fetch-zim:
	@if [ -f "$(ZIM_PATH)" ]; then \
		echo "$(ZIM_PATH) already present, skipping download"; \
	else \
		mkdir -p "$(ZIM_DIR)"; \
		echo "Fetching $(ZIM_URL)"; \
		curl -fL --progress-bar -o "$(ZIM_PATH).tmp" "$(ZIM_URL)" || { \
			echo "Download failed. If the dated filename moved, check the current" \
				"listing at https://download.kiwix.org/zim/wikipedia/ and update" \
				"ZIM_SOURCE in the Makefile."; \
			rm -f "$(ZIM_PATH).tmp"; \
			exit 1; \
		}; \
		mv "$(ZIM_PATH).tmp" "$(ZIM_PATH)"; \
		echo "Saved $(ZIM_PATH)"; \
	fi

up: fetch-zim
	KIWIX_BOOK=$(KIWIX_BOOK) docker compose up -d

down:
	docker compose down

build: fetch-zim
	KIWIX_BOOK=$(KIWIX_BOOK) docker compose up --build -d

logs:
	docker compose logs -f

# A dev-only keypair the platform uses to SSH into the simulated player VMs
# (player_vm1/player_vm2). Never committed; regenerate per checkout.
DEPLOY_KEY := deploy/keys/id_ed25519

deploy-keys:
	@if [ -f "$(DEPLOY_KEY)" ]; then \
		echo "$(DEPLOY_KEY) already present, skipping"; \
	else \
		mkdir -p deploy/keys; \
		ssh-keygen -t ed25519 -N "" -C "wikirace-deploy-dev" -f "$(DEPLOY_KEY)"; \
	fi

# TLS distribution: a dev-only CA plus one certificate per role (web,
# harness, player), all signed by it. Never committed, regenerated per
# checkout. A node started without a certificate this CA signed can't join
# distribution at all, not just fail a cookie check. See RUNNING.md for how
# Deploy.Server wires this into a real deploy when
# :wiki_race_platform, :deploy, :tls is enabled.
CERTS_DIR := deploy/certs

dist-certs:
	@if [ -f "$(CERTS_DIR)/ca.pem" ]; then \
		echo "$(CERTS_DIR)/ca.pem already present, skipping"; \
	else \
		mkdir -p "$(CERTS_DIR)"; \
		openssl genrsa -out "$(CERTS_DIR)/ca.key" 2048 2>/dev/null; \
		openssl req -x509 -new -nodes -key "$(CERTS_DIR)/ca.key" -sha256 -days 3650 \
			-out "$(CERTS_DIR)/ca.pem" -subj "/CN=WikiRace Dev CA" 2>/dev/null; \
		printf '[SAN]\nsubjectAltName = DNS:web, DNS:harness, DNS:player, DNS:platform, DNS:player_vm1, DNS:player_vm2, DNS:localhost, IP:127.0.0.1\n' \
			> "$(CERTS_DIR)/san.cnf"; \
		for role in web harness player; do \
			openssl genrsa -out "$(CERTS_DIR)/$$role.key" 2048 2>/dev/null; \
			openssl req -new -key "$(CERTS_DIR)/$$role.key" -subj "/CN=$$role" \
				-out "$(CERTS_DIR)/$$role.csr" 2>/dev/null; \
			openssl x509 -req -in "$(CERTS_DIR)/$$role.csr" -CA "$(CERTS_DIR)/ca.pem" \
				-CAkey "$(CERTS_DIR)/ca.key" -CAcreateserial -out "$(CERTS_DIR)/$$role.pem" \
				-days 365 -sha256 -extfile "$(CERTS_DIR)/san.cnf" -extensions SAN 2>/dev/null; \
			printf '[\n  {server, [\n    {certfile, "%s/%s.pem"},\n    {keyfile, "%s/%s.key"},\n    {cacertfile, "%s/ca.pem"},\n    {verify, verify_peer},\n    {fail_if_no_peer_cert, true}\n  ]},\n  {client, [\n    {certfile, "%s/%s.pem"},\n    {keyfile, "%s/%s.key"},\n    {cacertfile, "%s/ca.pem"},\n    {verify, verify_peer}\n  ]}\n].\n' \
				"$(CURDIR)/$(CERTS_DIR)" "$$role" "$(CURDIR)/$(CERTS_DIR)" "$$role" "$(CURDIR)/$(CERTS_DIR)" \
				"$(CURDIR)/$(CERTS_DIR)" "$$role" "$(CURDIR)/$(CERTS_DIR)" "$$role" "$(CURDIR)/$(CERTS_DIR)" \
				> "$(CERTS_DIR)/$$role.conf"; \
		done; \
		echo "Generated CA and web/harness/player certs under $(CERTS_DIR)/"; \
	fi

# Runs the deploy integration suite against the docker-simulated player VMs
# instead of real hardware. `mix test` on its own stays Docker-free (see
# platform/test/test_helper.exs). Runs under `--name` (long-name
# distribution, matching Deploy.Server's own choice for a real-IP-reachable
# player VM) so the test node can genuinely Node.connect/1 into the
# deployed release.
test-deploy: deploy-keys
	docker compose build release_builder
	docker compose up -d --build player_vm1
	cd platform && elixir --name tester@127.0.0.1 --cookie wikirace -S mix test --only integration
	docker compose stop player_vm1
