mkdir /tmp/files
mkdir /tmp/lua
mkdir /tmp/bzmoon
cd /tmp/lua
curl -O https://raw.githubusercontent.com/bjornbytes/RxLua/master/rx.lua
cd /tmp/bzmoon
curl -O https://media.faavne.no/bzmoon/bzmoon_latest.zip
unzip bzmoon_latest.zip
mv ./bzutils.lua /tmp/lua
find /bz-community/halloween-pack -type f \( -name "*.lua" -o -name "*.squish" \) -exec cp {} /tmp/lua \;
find /bz-community/shared -type f -exec cp {} /tmp/lua \;
python3 /bztools/luaSquish.py /tmp/lua -r
find /bz-community/halloween-pack -not -ipath '*/\.*' -not -name '*.lua' -not -name '*.bin' -type f -exec cp {} /tmp/files \;
find /tmp/lua -name '*.lua' -type f -exec mv {} /tmp/files \;
python3 /bztools/crlf_fixer.py /tmp/files
mkdir -p /bz-community/bz-halloween/output
zip -j -r /bz-community/bz-halloween/output/bundle.zip /tmp/files