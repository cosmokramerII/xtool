# xtool + Linux = <3

xtool currently uses AppImage to build its Linux CLI. It is possible to build and run the AppImage on a native Linux host, as well as through Docker (natively or through Docker Desktop on macOS).

## Setup

### Native prerequisites (Ubuntu / Debian)

xtool relies on the libimobiledevice stack when running on Linux. On Ubuntu or Debian hosts you can install everything with the
provided bootstrap script:

```
./scripts/bootstrap-linux.sh --install
```

This command installs the required `apt` packages, builds the latest `libplist`, `libimobiledevice-glue`, `libusbmuxd`, `libtatsu`,
and `libimobiledevice` releases from source, and ensures `pkg-config` can find them. You can re-run the script with `--check` to
confirm the dependencies are available.

### usbmuxd

Make sure `usbmuxd` is installed on your host machine. On macOS, `usbmuxd` is preinstalled.

### Using Docker

You can build and run a container with standard Docker Compose commands, for example:
```
docker compose run --rm xtool
``` 
This will spawn a shell inside the container. The xtool root directory will be bind-mounted at `/xtool`.

To actually access iOS devices from inside Docker, you'll also need to forward the host's `usbmuxd` to a port which the Docker container's libusbmuxd will connect to. Keep this command running on your host machine:
```
socat -dd TCP-LISTEN:27015,range=127.0.0.1/32,reuseaddr,fork UNIX-CLIENT:/var/run/usbmuxd
```

## Building

Simply run `./build.sh` in this directory. This will output an AppImage to `packages/xtool.AppImage`, which can directly be invoked.
