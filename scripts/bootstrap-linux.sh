#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: bootstrap-linux.sh [--check|--install]

--check    Verify that the required native dependencies are present.
--install  Install and build the dependencies on Debian/Ubuntu systems.
USAGE
}

MODE="check"
if [[ $# -gt 0 ]]; then
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --install)
            MODE="install"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
fi

if [[ $# -gt 0 ]]; then
    echo "Unexpected argument: $1" >&2
    usage >&2
    exit 1
fi

REQUIRED_MODULES=(
    libimobiledevice-1.0
    libimobiledevice-glue-1.0
    libusbmuxd-2.0
    libplist-2.0
)

APT_PACKAGES=(
    build-essential
    autoconf
    automake
    libtool
    libtool-bin
    pkg-config
    git
    curl
    unzip
    libcurl4-openssl-dev
    libssl-dev
    libxml2-dev
    libusb-1.0-0-dev
    liblzma-dev
    zlib1g-dev
    libplist-dev
    libusbmuxd-dev
    libimobiledevice-dev
    ldc
    dub
)

check_modules() {
    local missing=()
    if ! command -v pkg-config >/dev/null 2>&1; then
        echo "pkg-config is not installed." >&2
        return 1
    fi

    for module in "${REQUIRED_MODULES[@]}"; do
        if ! pkg-config --exists "$module"; then
            missing+=("$module")
        fi
    done

    if [[ ! -f /usr/lib/libxadi.so ]]; then
        missing+=("libxadi")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "All required Linux dependencies are present."
        return 0
    fi

    echo "Missing Linux build dependencies:" >&2
    for module in "${missing[@]}"; do
        echo "  - $module" >&2
    done
    echo >&2
    echo "Install them with ./scripts/bootstrap-linux.sh --install" >&2
    return 1
}

run_with_sudo() {
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo "$@"
        else
            echo "Need root privileges to run: $*" >&2
            exit 1
        fi
    else
        "$@"
    fi
}

install_packages() {
    local missing=()
    for pkg in "${APT_PACKAGES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "[info] Required apt packages already installed."
        return
    fi

    echo "[info] Installing packages: ${missing[*]}"
    run_with_sudo apt-get update
    DEBIAN_FRONTEND=noninteractive run_with_sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

build_from_source() {
    local name=$1
    local url=$2
    local ref=$3
    shift 3
    local extra_config=("$@")

    local workdir
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' RETURN

    echo "[info] Building $name ($ref)"
    git clone --depth 1 --branch "$ref" "$url" "$workdir/$name" >/dev/null
    pushd "$workdir/$name" >/dev/null
    ./autogen.sh --prefix=/usr "${extra_config[@]}"
    make -j"$(nproc)"
    run_with_sudo make install
    popd >/dev/null
    rm -rf "$workdir"
    trap - RETURN
}

sync_pkgconfig() {
    local pc_file=$1
    local src="/usr/lib/pkgconfig/${pc_file}"
    local dst_dir="/usr/lib/x86_64-linux-gnu/pkgconfig"
    if [[ -f "$src" ]]; then
        run_with_sudo install -Dm644 "$src" "${dst_dir}/${pc_file}"
    fi
}

sync_library() {
    local pattern=$1
    local src_dir="/usr/lib"
    local dst_dir="/usr/lib/x86_64-linux-gnu"
    shopt -s nullglob
    for file in "$src_dir"/$pattern; do
        local base=$(basename "$file")
        run_with_sudo cp -af "$file" "$dst_dir/$base"
        if [[ "$base" =~ ^(.+\.so)\.([0-9]+)(.*)$ ]]; then
            local root="${BASH_REMATCH[1]}"
            local major="${BASH_REMATCH[2]}"
            run_with_sudo rm -f "$dst_dir/$root."
            run_with_sudo ln -sf "$base" "$dst_dir/$root"
            run_with_sudo ln -sf "$base" "$dst_dir/$root.$major"
        fi
    done
    shopt -u nullglob
}

update_imobiledevice_links() {
    local dst_dir="/usr/lib/x86_64-linux-gnu"
    local latest
    latest=$(find "$dst_dir" -maxdepth 1 -type f -name 'libimobiledevice-1.0.so.*.*.*' | sort -V | tail -n1 || true)
    if [[ -z "$latest" ]]; then
        return
    fi

    local base=$(basename "$latest")
    local major
    if [[ $base =~ \.so\.([0-9]+) ]]; then
        major=${BASH_REMATCH[1]}
    else
        major=6
    fi

    run_with_sudo find "$dst_dir" -maxdepth 1 \( -type l -o -type f \) -name 'libimobiledevice-1.0.so.*' ! -name "$base" -exec rm -f {} \;
    run_with_sudo find "$dst_dir" -maxdepth 1 -type l -name 'libimobiledevice.so.*' ! -name "libimobiledevice.so.$major" -exec rm -f {} \;

    run_with_sudo ln -sf "$base" "$dst_dir/libimobiledevice-1.0.so"
    run_with_sudo ln -sf "$base" "$dst_dir/libimobiledevice-1.0.so.$major"
    run_with_sudo ln -sf libimobiledevice-1.0.so "$dst_dir/libimobiledevice.so"
    run_with_sudo ln -sf libimobiledevice-1.0.so.$major "$dst_dir/libimobiledevice.so.$major"
}

build_imobiledevice_stack() {
    if ! pkg-config --exists "libplist-2.0 >= 2.6.0"; then
        build_from_source libplist https://github.com/libimobiledevice/libplist.git 2.6.0 --without-cython
    else
        echo "[info] libplist >= 2.6.0 already installed"
    fi
    sync_pkgconfig libplist-2.0.pc
    sync_pkgconfig libplist++-2.0.pc
    sync_library "libplist-2.0.so*"
    sync_library "libplist++-2.0.so*"

    if ! pkg-config --exists "libimobiledevice-glue-1.0 >= 1.3.1"; then
        build_from_source libimobiledevice-glue https://github.com/libimobiledevice/libimobiledevice-glue.git 1.3.1
    else
        echo "[info] libimobiledevice-glue >= 1.3.1 already installed"
    fi
    sync_pkgconfig libimobiledevice-glue-1.0.pc
    sync_library "libimobiledevice-glue-1.0.so*"

    if ! pkg-config --exists "libusbmuxd-2.0 >= 2.1.0"; then
        build_from_source libusbmuxd https://github.com/libimobiledevice/libusbmuxd.git 2.1.0
    else
        echo "[info] libusbmuxd >= 2.1.0 already installed"
    fi
    sync_pkgconfig libusbmuxd-2.0.pc
    sync_library "libusbmuxd-2.0.so*"
    sync_library "libusbmuxd.so*"

    if ! pkg-config --exists "libtatsu-1.0"; then
        build_from_source libtatsu https://github.com/libimobiledevice/libtatsu.git 1.0.4
    else
        echo "[info] libtatsu already installed"
    fi
    sync_pkgconfig libtatsu-1.0.pc || true
    sync_library "libtatsu.so*"

    if ! grep -q "idevice_events_subscribe" /usr/include/libimobiledevice/libimobiledevice.h 2>/dev/null; then
        build_from_source libimobiledevice https://github.com/libimobiledevice/libimobiledevice.git master --without-cython
    else
        echo "[info] libimobiledevice headers provide subscription APIs"
    fi
    sync_pkgconfig libimobiledevice-1.0.pc
    sync_library "libimobiledevice-1.0.so*"
    sync_library "libimobiledevice.so*"
    update_imobiledevice_links

    run_with_sudo ldconfig
}

build_xadi() {
    if [[ -f /usr/lib/libxadi.so ]]; then
        echo "[info] libxadi already installed"
        return
    fi

    local workdir
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' RETURN

    echo "[info] Building xadi"
    git clone --depth 1 --branch main https://github.com/xtool-org/xadi.git "$workdir/xadi" >/dev/null
    pushd "$workdir/xadi" >/dev/null
    dub build --build=release
    run_with_sudo install -Dm755 bin/libxadi.so /usr/lib/libxadi.so
    popd >/dev/null
    rm -rf "$workdir"
    trap - RETURN

    run_with_sudo ldconfig
}

if [[ $MODE == "check" ]]; then
    check_modules
    exit $?
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "Automatic installation only supports Debian/Ubuntu (apt-get not found)." >&2
    exit 1
fi

install_packages
build_imobiledevice_stack
build_xadi

if check_modules; then
    echo "Linux dependencies installed."
else
    echo "Linux dependencies were installed, but pkg-config still cannot find every module. Check PKG_CONFIG_PATH." >&2
    exit 1
fi
