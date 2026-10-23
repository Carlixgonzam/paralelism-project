.PHONY: fetch-zim images up down build logs deploy-keys deploy-images dist-certs test-deploy

# The Wikipedia snapshot to serve. The platform reads the same KIWIX_BOOK.
#
# wikipedia_en_top_nopic (~2.2 GB, 928K entries) has real links between
#   articles. It is the default for local work.
# wikipedia_en_all_nopic (~52 GB) is the full encyclopedia, used on
#   competition day.
# wikipedia_en_100_nopic (~15 MB) has almost no links between articles. It
#   only checks that the setup works.
KIWIX_BOOK ?= wikipedia_en_top_nopic

ZIM_DIR := .data/zim
ZIM_PATH := $(ZIM_DIR)/$(KIWIX_BOOK).zim

# The download site puts a date in each file name. The dated name of each book
# is pinned here. The file is saved without the date (see ZIM_PATH), so the
# rest of the setup only needs the book name.
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

# Builds the images through bake, since `docker compose build` cannot grant
# the network.host privilege the builds need (see docker-compose.yml). player1
# and player2 share one image, so building player1 is enough.
BAKE := docker buildx bake --allow=network.host -f docker-compose.yml

images:
	$(BAKE) platform player1

up: fetch-zim images
	KIWIX_BOOK=$(KIWIX_BOOK) docker compose up -d

down:
	docker compose down

# Rebuilds the images from scratch, without the build cache.
build: fetch-zim
	$(BAKE) --no-cache platform player1
	KIWIX_BOOK=$(KIWIX_BOOK) docker compose up -d

logs:
	docker compose logs -f

# Professor only (see DEPLOY.md). A dev keypair the platform uses to log in to
# the simulated player VMs (player_vm1, player_vm2). Never committed.
DEPLOY_KEY := deploy/keys/id_ed25519

deploy-keys:
	@if [ -f "$(DEPLOY_KEY)" ]; then \
		echo "$(DEPLOY_KEY) already present, skipping"; \
	else \
		mkdir -p deploy/keys; \
		ssh-keygen -t ed25519 -N "" -C "wikirace-deploy-dev" -f "$(DEPLOY_KEY)"; \
	fi

# Professor only (see DEPLOY.md). The image of the simulated player VMs, also
# used by release_builder.
deploy-images:
	$(BAKE) player_vm1

# Professor only (see DEPLOY.md). A dev CA and one certificate for each role
# (web, harness, player), for TLS distribution. Never committed. A node
# without a certificate signed by this CA cannot join the cluster.
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

# Professor only (see DEPLOY.md). Runs the deploy integration test against the
# simulated player_vm1. It uses a long node name (--name), like a deployed
# release, so the test node can connect to it.
test-deploy: deploy-keys deploy-images
	docker compose up -d player_vm1
	cd platform && elixir --name tester@127.0.0.1 --cookie wikirace -S mix test --only integration
	docker compose stop player_vm1
