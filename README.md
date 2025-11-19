# Assetry

[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-supported-blue)](https://www.docker.com/)
[![Lua](https://img.shields.io/badge/Lua-5.4-lightgrey)](https://www.lua.org/)
[![libvips](https://img.shields.io/badge/libvips-8.x-orange)](https://libvips.github.io/libvips/)

A self-host file server with img crop support. It's based on the [Openresty](https://github.com/openresty/openresty)
and [libvips](https://github.com/libvips/libvips).
It supports resizing, cropping, rounding, format conversion, and more, using **libvips** for fast operations.

> 🔒 Local-only processing for better security and simpler deployment.

## Features

* ✅ Resize images with modes: `fit`, `fill`, `crop`
* ✅ Crop with gravity: `n`, `ne`, `center`, `smart`, etc.
* ✅ Circular avatars with `round`
* ✅ Format conversion (jpeg, png, webp…) with quality control
* ✅ Gaussian blur
* ✅ Named operations for reusable pipelines
* ✅ Fast, local-only image processing

## Quick Start

### 1. Clone & Build

```bash
git clone https://github.com/yourusername/assetry.git
cd assetry
docker-compose build
```

### 2. Run

```bash
docker-compose up
```

By default:

* **Port 8080** → Cached access
* **Port 8081** → Direct processing
* **Port 8082** → File serving

## Environment Variables

| Variable                        | Default                 | Description                     |
| ------------------------------- | ----------------------- | ------------------------------- |
| `ASSETRY_MAX_WIDTH`             | `4096`                  | Maximum width of output image   |
| `ASSETRY_MAX_HEIGHT`            | `4096`                  | Maximum height of output image  |
| `ASSETRY_MAX_OPERATIONS`        | `10`                    | Max operations per request      |
| `ASSETRY_DEFAULT_QUALITY`       | `90`                    | JPEG/PNG quality                |
| `ASSETRY_DEFAULT_STRIP`         | `true`                  | Strip metadata                  |
| `ASSETRY_DEFAULT_FORMAT`        | `webp`                  | Output format if none specified |
| `ASSETRY_MAX_CONCURRENCY`       | `4`                     | Max libvips concurrency         |
| `ASSETRY_NAMED_OPERATIONS_FILE` | `null`                  | Predefined operations file      |

**Example `named_ops.txt`:**

```text
thumbnail: resize/w=500,h=500,m=fit/crop/w=200,h=200,g=sw/format/t=webp
avatar: resize/w=100,h=100,m=crop/round/p=100/format/t=jpg
```

## URL Usage

```text
http://localhost:8080/path/to/local/image.jpg?<operation>/<params>
```

Operations can be chained:

### Supported Operations

**1. resize** — Change image dimensions

| Param | Description                 |
| ----- | --------------------------- |
| `w`   | Width (px)                  |
| `h`   | Height (px)                 |
| `m`   | Mode: `fit`, `fill`, `crop` |

**2. crop** — Crop a portion of the image

| Param | Description                                                            |
| ----- | ---------------------------------------------------------------------- |
| `w`   | Width (px)                                                             |
| `h`   | Height (px)                                                            |
| `g`   | Gravity: `n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`, `center`, `smart` |

**3. round** — Make circular images

| Param | Description         |
| ----- | ------------------- |
| `p`   | Percentage to round |
| `x`   | Optional x-radius   |
| `y`   | Optional y-radius   |

**4. format** — Convert image format

| Param | Description                           |
| ----- | ------------------------------------- |
| `t`   | Output format (jpeg, png, webp, etc.) |
| `q`   | Quality (1-100)                       |
| `s`   | Strip metadata (`true`/`false`)       |

**5. named** — Apply predefined operation from `ASSETRY_NAMED_OPERATIONS_FILE`

| Param | Description           |
| ----- | --------------------- |
| `n`   | Name of the operation |

**6. blur** — Apply Gaussian blur

| Param | Description                   |
| ----- | ----------------------------- |
| `s`   | Sigma value for gaussian blur |

---

### Examples

#### Resize + Crop

```text
http://localhost:8080/images/original.jpg?resize/w=500,h=500,m=crop
```

#### Chained Operations

```text
http://localhost:8080/images/original.jpg?resize/w=500,h=500,m=fit/crop/w=200,h=200,g=center/format/t=png
```

#### Named Operation

```text
http://localhost:8080/images/user.jpg?named/n=avatar
```

## Credits

* Uses [libvips](https://libvips.github.io/libvips) for fast image operations
* Some C++ routines influenced by [Sharp](https://github.com/lovell/sharp)
