bundle, minify = open("bundled.lua", "a"), open("minified.lua", "a")
licenses = "\n--[[\nOBSI 2 LICENSE:\n\n" + open("LICENSE", "r").read() + "\n]]" + \
"\n--[[\nPIXELBOX LICENSE:\n\n" + open("LICENSES/PIXELBOX", "r").read() + "\n]]" + \
"\n--[[\nNBSTUNES LICENSE:\n\n" + open("LICENSES/NBSTUNES", "r").read() + "\n]]"

bundle.write(licenses)
bundle.close()

minify.write(licenses)
minify.close()