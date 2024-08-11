import os
from pathlib import PosixPath
import subprocess

bundle = open("bundled.lua", "w")
def pathToPackage(s: str):
    s = s[:-4].replace("/", ".")
    if s[-5:] == ".init":
        s = s[:-5]
    return s

def writeLuaFiles(path: PosixPath):
    lsdir = os.listdir(path)
    for name in lsdir:
        p = PosixPath.joinpath(path, name)
        if name[0] != "." and name != "node_modules" and name != "bundled.lua":
            if PosixPath.is_dir(p):
                writeLuaFiles(p)
            elif name[-4:] == ".lua":
                print(p)
                f = open(p)
                bundle.write('package.preload["')
                bundle.write(pathToPackage('obsi2.' + str(p)))
                bundle.write('"] = function()\n')
                bundle.write(f.read())
                bundle.write("\nend\n")
writeLuaFiles(PosixPath(""))
bundle.write('return package.preload["obsi2"]()\n')
bundle.close()
