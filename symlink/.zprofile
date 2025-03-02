export PATH="/usr/local/opt/python/libexec/bin:$PATH"
if [[ "$(sysctl -n machdep.cpu.brand_string)" == *"Apple"* ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
