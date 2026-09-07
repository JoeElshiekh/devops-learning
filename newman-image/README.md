# Custom Newman Docker Image

## Purpose

This task extends the `postman/newman:5.3-alpine` image with troubleshooting utilities and a CSV reporter while preserving Newman as the container's main command.

## Image requirements

- Base image: `postman/newman:5.3-alpine`
- Updated/upgraded Alpine packages
- `curl`, `zip`, and `iputils`
- Globally installed `newman-reporter-csvallinone`
- `NODE_PATH=/usr/local/lib/node_modules` for globally installed npm packages
- Working directory: `/etc/newman`
- Entrypoint: `newman`
- Package cache removed after installation

## Build

From the directory containing the `Dockerfile`:

```bash
docker build -t custom-newman:1.0 .
```

## Run

Check the Newman version while explicitly configuring the required DNS servers:

```bash
docker run --rm \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  custom-newman:1.0 --version
```

Run a Postman collection from the current host directory with bind mount:

```bash
docker run --rm \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  -v "$PWD:/etc/newman" \
  custom-newman:1.0 run collection.json
```

## Verification

```bash
docker run --rm --entrypoint sh custom-newman:1.0 -c \
  'pwd; which curl zip ping; echo "$NODE_PATH"; npm list -g --depth=0'
```

Expected highlights include `/etc/newman`, all three utilities, `/usr/local/lib/node_modules`, and `newman-reporter-csvallinone`.

## Concepts practiced

Base images, image layers, build context, `FROM`, `RUN`, `ENV`, `WORKDIR`, `ENTRYPOINT`, Alpine `apk`, Node.js `npm`, global modules, image tagging, bind mounts, build-time versus runtime configuration, and image verification.

## Key notes

DNS is container runtime configuration, not a Dockerfile instruction. Docker generates `/etc/resolv.conf` when a container starts, so the DNS requirement is correctly supplied with `docker run --dns` (or the equivalent Compose `dns` setting).