rockspec_format = "3.0"
package = "assetry"
version = "1.0-1"

source = {
    url = "git+ssh://git@github.com/syhily/assetry.git"
}

description = {
    summary = "A self-host file server with image processing support.",
    detailed = [[
A self-host file server with image crop support. It's based on OpenResty
and libvips.
It supports resizing, cropping, rounding, format conversion, and more,
using libvips for fast operations.
]],
    homepage = "https://github.com/syhily/assetry",
    license = "MIT"
}

dependencies = {
    "lua == 5.1"
}

build_dependencies = {
}

build = {
    type = "builtin",
    modules = {
        ["resty.assetry"] = "lib/resty/assetry.lua",
        ["resty.assetry_http"] = "lib/resty/assetry_http.lua",
        ["resty.assetry_params"] = "lib/resty/assetry_params.lua",
        ["resty.assetry_stats"] = "lib/resty/assetry_stats.lua",
        ["resty.assetry_upload"] = "lib/resty/assetry_upload.lua",
        ["resty.assetry_util"] = "lib/resty/assetry_util.lua",
        ["resty.assetry_vips"] = "lib/resty/assetry_vips.lua"
    }
}

test = {
    type = "busted",
    flags = { "-o", "gtest" }
}

test_dependencies = {
    "busted"
}
