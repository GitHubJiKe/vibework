.PHONY: build run list app

# 在沙箱/受限环境中构建时需要的附加参数；普通终端里同样可用。
SWIFT_BUILD_FLAGS = --disable-sandbox -Xcc -fmodules-cache-path=/tmp/clang-module-cache

build:
	cd mac-stream && CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build -c release $(SWIFT_BUILD_FLAGS)

run:
	cd mac-stream && CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run -c release $(SWIFT_BUILD_FLAGS)

list:
	cd mac-stream && CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run -c release $(SWIFT_BUILD_FLAGS) -- --list

app:
	bash scripts/build-app.sh
