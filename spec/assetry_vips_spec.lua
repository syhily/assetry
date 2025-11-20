package.path = package.path .. ";./lib/?.lua;"

local lib = require "resty.assetry_vips"
local Assetry = lib.Assetry

-- Helper to read a file
local function file_get_contents(name)
    local fp = io.open(name, "rb")
    assert(fp, "Could not open file: " .. name)
    local data = fp:read("*all")
    fp:close()
    return data
end

-- Helper to write test output files
local function test_write_files(name, image)
    local jpg_output, err = image:to_buffer("jpg", 100, true)
    assert(jpg_output, "Failed to get JPG buffer: " .. tostring(err))
    local op = io.open("spec/test_output_" .. name .. ".jpg", "wb")
    assert(op, "Failed to open JPG output file")
    op:write(jpg_output)
    op:close()

    local png_output, err = image:to_buffer("png", 100, true)
    assert(png_output, "Failed to get PNG buffer: " .. tostring(err))
    local op = io.open("spec/test_output_" .. name .. ".png", "wb")
    assert(op, "Failed to open PNG output file")
    op:write(png_output)
    op:close()
end

-- Initialize lib defaults
lib.init({
    default_format  = "png",
    default_quality = 100,
    default_strip   = false
})

-- Busted tests
describe("Assetry Image Manipulation", function()
    it("should set background color and resize correctly", function()
        local src = file_get_contents("spec/blog-poster.png")
        local image, err = Assetry.new_from_buffer(src, #src)
        assert.is_nil(err)

        local rc = image:set_background_color(255, 0, 255)
        assert.is_true(rc)
        test_write_files("background_color1", image)

        local rc = image:resize(200, 200, Assetry.ResizeMode.fill)
        assert.is_true(rc)
        test_write_files("background_color2", image)
    end)
end)
