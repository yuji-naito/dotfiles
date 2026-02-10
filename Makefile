.DEFAULT_GOAL := help

.PHONY: init update help

init: ## Homebrew のインストールと Brewfile のパッケージをセットアップ
	@bash scripts/init.sh

update: ## Homebrew の更新・アップグレードと Brewfile の同期
	@bash scripts/update.sh

help: ## 使用可能なコマンド一覧を表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
