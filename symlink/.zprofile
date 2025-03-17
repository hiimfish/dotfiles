export PATH="/usr/local/opt/python/libexec/bin:$PATH"

# Apple 處理器的 Mac 才需要。
if [[ "$(sysctl -n machdep.cpu.brand_string)" == *"Apple"* ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
