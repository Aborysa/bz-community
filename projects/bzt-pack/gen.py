from glob import glob
import json


with open("name_map", "r") as f:
  file_map = json.loads(f.read())

with open("ini_template") as f:
  ini_template = f.read()

with open("vxt_template") as f:
  vxt_template = f.read()

for file, name in file_map.items():
  with open("./maps/{}.ini".format(file), "w") as f:
    f.write(ini_template.format(name=name))

  with open("./maps/{}.vxt".format(file), "w") as f:
    f.write(vxt_template)

  with open("./maps/{}.lua".format(file), "w") as f:
    f.write("local _ = require('bzst17')")
