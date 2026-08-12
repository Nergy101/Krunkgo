# BLOCKSHOT — single-player voxel arena FPS in Godot 4.7
#
# Everything here drives the same project; there is no build step for a debug
# run because Godot interprets the GDScript directly. "release" means a real
# exported native binary, which needs the matching export templates installed.
#
#   make            list targets
#   make run        play it (debug)
#   make release    export a native binary and play that
#
# Override the engine path if yours lives elsewhere:
#   make run GODOT=/path/to/Godot

GODOT      ?= /Applications/Godot_mono.app/Contents/MacOS/Godot
RES        ?= 1600x900
PRESET     ?= macOS
BUILD_DIR  ?= build
APP        := $(BUILD_DIR)/blockshot.app
BIN        := $(APP)/Contents/MacOS/blockshot
ROUND      ?= dev
SEED       ?= 7
GODOT_VER  := $(shell $(GODOT) --version 2>/dev/null | cut -d. -f1-3)
TEMPLATES  := $(HOME)/Library/Application Support/Godot/export_templates
TEMPLATE   := $(TEMPLATES)/$(GODOT_VER).stable.mono/macos.zip

.DEFAULT_GOAL := help
.PHONY: help run debug release export play import check probes movetest bottest \
        hittest bench shots round templates templates-install clean distclean

## ---------------------------------------------------------------- meta

help: ## list targets
	@printf '\nBLOCKSHOT — make targets\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'
	@printf '\nengine: $(GODOT)\n\n'

## ---------------------------------------------------------------- running

run: debug ## play the game (alias for debug)

debug: import ## play from source with the debugger attached
	$(GODOT) --path . --resolution $(RES)

release: $(BIN) ## export a native binary and run it
	@printf '\n>> running exported binary: $(BIN)\n\n'
	"$(BIN)" --resolution $(RES)

export: $(BIN) ## export a native binary without running it

$(BIN): import check
	@if [ ! -f "$(TEMPLATE)" ]; then \
		printf '\nERROR: no Godot export templates installed.\n\n'; \
		printf 'A release build is a real compiled binary, so it needs the\n'; \
		printf 'export templates for Godot $(GODOT_VER). Either:\n\n'; \
		printf '  - run: make templates-install   (downloads ~1.3 GB), or\n  - open the editor and use Editor > Manage Export Templates, or\n'; \
		printf '  - download Godot_v$(GODOT_VER)-stable_mono_export_templates.tpz from\n'; \
		printf '    https://github.com/godotengine/godot/releases and unzip it into\n'; \
		printf '    %s/$(GODOT_VER).stable.mono/\n\n' "$(TEMPLATES)"; \
		printf 'Use "make run" meanwhile — it plays the identical project.\n\n'; \
		exit 1; \
	fi
	@mkdir -p $(BUILD_DIR)
	$(GODOT) --headless --path . --export-release "$(PRESET)" "$(APP)"

templates-install: ## download + unpack the export templates (~1.3 GB)
	@mkdir -p "$(TEMPLATES)"
	@tmp=$$(mktemp -d); \
	url=https://github.com/godotengine/godot/releases/download/$(GODOT_VER)-stable/Godot_v$(GODOT_VER)-stable_mono_export_templates.tpz; \
	printf 'downloading %s\n' "$$url"; \
	curl -fL --progress-bar -o "$$tmp/t.tpz" "$$url" || { printf 'download failed\n'; exit 1; }; \
	unzip -q "$$tmp/t.tpz" -d "$$tmp"; \
	rm -rf "$(TEMPLATES)/$(GODOT_VER).stable.mono"; \
	mv "$$tmp/templates" "$(TEMPLATES)/$(GODOT_VER).stable.mono"; \
	rm -rf "$$tmp"; \
	printf 'installed to %s\n' "$(TEMPLATES)/$(GODOT_VER).stable.mono"

templates: ## report whether export templates are installed
	@printf 'Godot version: $(GODOT_VER)\n'
	@printf 'Expected at:   %s\n' "$(TEMPLATE)"
	@if [ -f "$(TEMPLATE)" ]; then printf 'Status:        present\n'; \
		else printf 'Status:        MISSING — see "make release" for instructions\n'; fi

## ---------------------------------------------------------------- project

import: ## build the class cache (runs itself on a fresh checkout)
	@test -d .godot/global_script_class_cache.cfg || { \
		printf 'first run: building Godot class cache...\n'; \
		$(GODOT) --headless --path . --import >/dev/null 2>&1 || true; }

check: import ## fail on any GDScript parse error
	@err=$$($(GODOT) --headless --path . --quit 2>&1 \
		| grep -E "SCRIPT ERROR|Parse Error|Failed to load script" || true); \
	if [ -n "$$err" ]; then printf '%s\n' "$$err"; printf '\nPARSE FAILED\n'; exit 1; fi
	@printf 'parse clean\n'

## ---------------------------------------------------------------- evidence

round: ## full evidence round: parse, bench, every screenshot (ROUND=name)
	tools/round.sh $(ROUND)

bench: import ## frame timings as JSON, vsync off, full bot fight
	@$(GODOT) --path . --resolution $(RES) -- bench=8 botfight seed=$(SEED) 2>&1 | grep -E '^BENCH'

shots: import ## fixed-angle map screenshots into shots/$(ROUND)
	@$(GODOT) --path . --resolution $(RES) -- shots=res://shots/$(ROUND) shotset=map seed=$(SEED) 2>&1 | grep -E '^SHOT'

probes: movetest bottest hittest ## run all three measurement probes

movetest: import ## movement envelope: slide-hop gain, strafe bonus, wall-jump
	@$(GODOT) --path . --resolution 1280x720 -- movetest seed=$(SEED) 2>&1 | grep -E '^MOVETEST'

bottest: import ## bot behaviour: idle, engagement, retreat, cover, slide
	@$(GODOT) --path . --resolution 1280x720 -- bottest seed=$(SEED) 2>&1 | grep -E '^BOTTEST'

hittest: import ## hit registration: shots-to-kill, falloff, first-shot accuracy
	@$(GODOT) --path . --resolution 1280x720 -- hittest seed=$(SEED) 2>&1 | grep -E '^HITTEST'

## ---------------------------------------------------------------- cleaning

clean: ## remove build output and captured screenshots
	rm -rf $(BUILD_DIR) shots

distclean: clean ## also drop Godot's import cache
	rm -rf .godot
