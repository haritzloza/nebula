PACKAGES ?= hypr waybar rofi kitty nvim tmux zsh starship hyprpaper swaync claude
TARGET   ?= $(HOME)
STOW     ?= stow

.PHONY: help install link unlink relink check gaming hardening

help:
	@echo "Targets:"
	@echo "  install     Run ./install.sh (base packages + stow)"
	@echo "  link        stow PACKAGES -> \$$HOME"
	@echo "  unlink      stow -D PACKAGES"
	@echo "  relink      unlink + link"
	@echo "  check       stow -n -v (dry-run)"
	@echo "  gaming      ./install.sh --gaming"
	@echo "  hardening   ./install.sh --hardening"
	@echo ""
	@echo "Vars: PACKAGES=\"$(PACKAGES)\" TARGET=$(TARGET)"

install:
	./install.sh

link:
	$(STOW) -t $(TARGET) $(PACKAGES)

unlink:
	$(STOW) -D -t $(TARGET) $(PACKAGES)

relink: unlink link

check:
	$(STOW) -n -v -t $(TARGET) $(PACKAGES)

gaming:
	./install.sh --gaming

hardening:
	./install.sh --hardening
