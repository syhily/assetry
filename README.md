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

* ✅ API for uploading files, display the files details.
* ✅ Status page for showing the image processing status.
* 🏗️ Thumbhash query API for images.
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

## How to Contribute

To contribute your code. You need to be familiar with Lua, LuaJIT and Openresty.
The code is formatter by using [LuaFormatter](https://github.com/Koihik/LuaFormatter) and a git hook is added for linting
by using [luacheck](https://github.com/mpeterv/luacheck).

To simplify the develop environment configuration. LuaRocks is used only for local lua package installation.

```bash
luarocks install --only-deps assetry-1.0-1.rockspec
```

## Status API

**GET** `/status`

**Example Response:**

```json
{
  "upstream_http_success": 27,
  "avg_response_time": 0.079355987516939,
  "avg_response_length": 154676.42760087,
  "upstream_http_server_error": 0,
  "avg_image_processing_time": 0.076554648460342,
  "avg_http_fetch_image_time": 0.0027975888839513,
  "num_cache_hit": 0,
  "upstream_http_client_error": 0,
  "num_cache_miss": 27,
  "upstream_http_redirect": 0,
  "num_requests": 27
}
```

## File Upload API

This module provides file upload and listing functionality for OpenResty using `resty.upload`.
Files can be uploaded via HTTP POST, and existing files can be listed via HTTP GET. All requests require an API key.

### Endpoints

#### 1. List Uploaded Files

**GET** `/upload/{path}`

Lists all files in a given directory.

**Path Parameters:**

| Name   | Description                                                       |
| ------ | ----------------------------------------------------------------- |
| `path` | **(Optional)** Folder path to list files (e.g., `images/2025/11`) |

**Query Parameters:**

| Name      | Description                     |
| --------- | ------------------------------- |
| `api_key` | Your API key for authentication |

**Example Request:**

```bash
curl "http://localhost:8080/upload/images/2025/11?api_key=YOUR_API_KEY"
```

**Example Response:**

```json
{
  "path": "images/2025/11",
  "files": [
    {
      "name": "16",
      "type": "dir"
    },
    {
      "name": "2025110600183700.jpg",
      "type": "file",
      "sha256": "729b39216e35bf0bd926745382ee63ee7bfe9e746e100c284c19638cb586d607"
    },
    {
      "name": "2025110600201100.jpg",
      "type": "file",
      "sha256": "a68b6f1867ad720a2cc938543bb663435e9eb63e24e80f4daa3d167e4ba7e93f"
    }
  ]
}
```

#### 2. Upload a File

**POST** `/upload/{path}`

Uploads a file to a folder.

**Path Parameters:**

| Name   | Description                                                         |
| ------ | ------------------------------------------------------------------- |
| `path` | **Required.** Folder path to save the file (e.g., `images/2025/11`) |

**Query Parameters:**

| Name      | Description                     |
| --------- | ------------------------------- |
| `api_key` | Your API key for authentication |

**Form Data:**

| Name   | Type | Description        |
| ------ | ---- | ------------------ |
| `file` | file | The file to upload |

**Example Request:**

```bash
curl -X POST "http://localhost:8080/upload/images/2025/11?api_key=YOUR_API_KEY" \
     -F "file=@/path/to/file.jpg"
```

**Example Response:**

```json
{
  "path": "images/2025/11",
  "file": "file.jpg",
  "size": 123456
}
```

* `path` – the folder where the file was saved
* `file` – the uploaded filename
* `size` – the file size in bytes

### Authentication

All requests require an API key passed via the `api_key` query parameter:

```text
?api_key=YOUR_API_KEY
```

### Notes

* Files are stored under the `data_root` directory defined in the module (default `/data`).
* GET `/upload/{path}` lists all files with their names, type, and SHA256 hash.
* The API supports nested folders in the path (e.g., `images/2025/11`).

## Image Operation API

```text
http://localhost:8080/path/to/local/image.jpg?<operation>/<params>
```

Append image operations to the query string of the image URL. Multiple operations can be chained.

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
