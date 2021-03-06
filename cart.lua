local __compression_map={
	'\n',
	' ',
	'0',
	'1',
	'2',
	'3',
	'4',
	'5',
	'6',
	'7',
	'8',
	'9',
	'a',
	'b',
	'c',
	'd',
	'e',
	'f',
	'g',
	'h',
	'i',
	'j',
	'k',
	'l',
	'm',
	'n',
	'o',
	'p',
	'q',
	'r',
	's',
	't',
	'u',
	'v',
	'w',
	'x',
	'y',
	'z',
	'!',
	'#',
	'%',
	'(',
	')',
	'{',
	'}',
	'[',
	']',
	'<',
	'>',
	'+',
	'=',
	'/',
	'*',
	':',
	';',
	'.',
	',',
	'~',
	'_',
	'"',
}

local api=require("api")

local function decompress(code)
	-- decompress code
	local lua=""
	local mode=0
	local copy=nil
	local i=8
	local codelen=bit.lshift(code:byte(5, 5), 8)+code:byte(6, 6)
	log('codelen', codelen)
	while #lua<codelen do
		i=i+1
		local byte=string.byte(code, i, i)
		if byte==nil then
			error('reached end of code')
		else
			if mode==1 then
				lua=lua..code:sub(i, i)
				mode=0
			elseif mode==2 then
				-- copy from buffer
				local offset=(copy-0x3c)*16+bit.band(byte, 0xf)
				local length=bit.rshift(byte, 4)+2
					local offset=#lua-offset
				local buffer=lua:sub(offset+1, offset+length)
				lua=lua..buffer
				mode=0
			elseif byte==0x00 then
				-- output next byte
				mode=1
			elseif byte>=0x01 and byte<=0x3b then
				-- output this byte from map
				lua=lua..__compression_map[byte]
			elseif byte>=0x3c then
				-- copy previous bytes
				mode=2
				copy=byte
			end
		end
	end
	return lua
end

local cart={}

function cart.load_p8(filename)
	log("Loading", filename)

	local lua=""
	pico8.map={}
	pico8.quads={}
	pico8.spritesheet_data=love.image.newImageData(128, 128)
	for y=0, 63 do
		pico8.map[y]={}
		for x=0, 127 do
			pico8.map[y][x]=0
		end
	end
	pico8.spriteflags={}
	pico8.sfx={}
	for i=0, 63 do
		pico8.sfx[i]={
			speed=16,
			loop_start=0,
			loop_end=0
		}
		for j=0, 31 do
			pico8.sfx[i][j]={0, 0, 0, 0}
		end
	end
	pico8.music={}
	for i=0, 63 do
		pico8.music[i]={
			loop=0,
			[0]=64,
			[1]=64,
			[2]=64,
			[3]=64
		}
	end

	local header=love.filesystem.read(filename, 8)
	if header=="\137PNG\r\n\26\n" then
		local img=love.graphics.newImage(filename)
		if img:getWidth()~=160 or img:getHeight()~=205 then
			error("Image is the wrong size")
		end
		local data=img:getData()

		local outX=0
		local outY=0
		local inbyte=0
		local lastbyte=nil
		local mapY=32
		local mapX=0
		local version=nil
		local compressed=false
		local sprite=0
		for y=0, 204 do
			for x=0, 159 do
				local r, g, b, a=data:getPixel(x, y)
				-- extract lowest bits
				r=bit.band(r, 0x0003)
				g=bit.band(g, 0x0003)
				b=bit.band(b, 0x0003)
				a=bit.band(a, 0x0003)
				local byte=bit.lshift(a, 6)+bit.lshift(r, 4)+bit.lshift(g, 2)+b
				local lo=bit.band(byte, 0x0f)
				local hi=bit.rshift(byte, 4)
				if inbyte<0x2000 then
					-- spritesheet
					if outY>=64 then
						pico8.map[mapY][mapX]=byte
						mapX=mapX+1
						if mapX==128 then
							mapX=0
							mapY=mapY+1
						end
					end
					pico8.spritesheet_data:setPixel(outX, outY, lo, 0, 0, 255)
					outX=outX+1
					pico8.spritesheet_data:setPixel(outX, outY, hi, 0, 0, 255)
					outX=outX+1
					if outX==128 then
						outY=outY+1
						outX=0
						if outY==128 then
							-- end of spritesheet, generate quads
							pico8.spritesheet=love.graphics.newImage(pico8.spritesheet_data)
							local sprite=0
							for yy=0, 15 do
								for xx=0, 15 do
									pico8.quads[sprite]=love.graphics.newQuad(xx*8, yy*8, 8, 8, pico8.spritesheet:getDimensions())
									sprite=sprite+1
								end
							end
							mapY=0
							mapX=0
						end
					end
				elseif inbyte<0x3000 then
					-- map data
					pico8.map[mapY][mapX]=byte
					mapX=mapX+1
					if mapX==128 then
						mapX=0
						mapY=mapY+1
					end
				elseif inbyte<0x3100 then
					-- sprite flags
					pico8.spriteflags[sprite]=byte
					sprite=sprite+1
				elseif inbyte<0x3200 then
					-- music
					local _music=math.floor((inbyte-0x3100)/4)
					pico8.music[_music][inbyte%4]=bit.band(byte, 0x7F)
					pico8.music[_music].loop=bit.bor(bit.rshift(bit.band(byte, 0x80), 7-inbyte%4), pico8.music[_music].loop)
				elseif inbyte<0x4300 then
					-- sfx
					local _sfx=math.floor((inbyte-0x3200)/68)
					local step=(inbyte-0x3200)%68
					if step<64 and inbyte%2==1 then
						local note=bit.lshift(byte, 8)+lastbyte
						pico8.sfx[_sfx][(step-1)/2]={bit.band(note, 0x3f), bit.rshift(bit.band(note, 0x1c0), 6), bit.rshift(bit.band(note, 0xe00), 9), bit.rshift(bit.band(note, 0x7000), 12)}
					elseif step==65 then
						pico8.sfx[_sfx].speed=byte
					elseif step==66 then
						pico8.sfx[_sfx].loop_start=byte
					elseif step==67 then
						pico8.sfx[_sfx].loop_end=byte
					end
				elseif inbyte<0x8000 then
					-- code, possibly compressed
					if inbyte==0x4300 then
						compressed=(byte==58)
					end
					lua=lua..string.char(byte)
				elseif inbyte==0x8000 then
					version=byte
				end
				lastbyte=byte
				inbyte=inbyte+1
			end
		end

		-- decompress code
		log('version', version)
		if version>7 then
			error(string.format('unknown file version %d', version))
		end

		if compressed then
			lua=decompress(lua)
		elseif lua:find("\0", nil, true) then
			lua=lua:match("(.-)%z")
		end
	else
		local f=love.filesystem.newFile(filename, 'r')
		if not f then
			error(string.format("Unable to open: %s", filename))
		end
		local data, size=f:read()
		f:close()
		if not data then
			error("invalid cart")
		end
		local header="pico-8 cartridge // http://www.pico-8.com\nversion "
		local start=data:find("pico%-8 cartridge // http://www.pico%-8%.com\nversion ")
		if start==nil then
			error("invalid cart")
		end
		local next_line=data:find("\n", start+#header)
		local version_str=data:sub(start+#header, next_line-1)
		local version=tonumber(version_str)
		log("version", version)
		-- extract the lua
		local lua_start=data:find("__lua__")+8
		local lua_end=data:find("__gfx__")-1

		lua=data:sub(lua_start, lua_end)

		-- load the sprites into an imagedata
		-- generate a quad for each sprite index
		local gfx_start=data:find("__gfx__")+8
		local gfx_end=data:find("__gff__")-1
		local gfxdata=data:sub(gfx_start, gfx_end)

		local row=0
		local tile_row=32
		local tile_col=0
		local col=0
		local sprite=0
		local tiles=0
		local shared=0

		local next_line=1
		while next_line do
			local end_of_line=gfxdata:find("\n", next_line)
			if end_of_line==nil then break end
			end_of_line=end_of_line-1
			local line=gfxdata:sub(next_line, end_of_line)
			for i=1, #line do
				local v=line:sub(i, i)
				v=tonumber(v, 16)
				pico8.spritesheet_data:setPixel(col, row, v, 0, 0, 255)

				col=col+1
				if col==128 then
					col=0
					row=row+1
				end
			end
			next_line=gfxdata:find("\n", end_of_line)+1
		end

		if version>3 then
			local tx, ty=0, 32
			for sy=64, 127 do
				for sx=0, 127, 2 do
					-- get the two pixel values and merge them
					local lo=pico8.spritesheet_data:getPixel(sx, sy)
					local hi=pico8.spritesheet_data:getPixel(sx+1, sy)
					local v=bit.bor(bit.lshift(hi, 4), lo)
					pico8.map[ty][tx]=v
					shared=shared+1
					tx=tx+1
					if tx==128 then
						tx=0
						ty=ty+1
					end
				end
			end
			assert(shared==128*32, shared)
		end

		for y=0, 15 do
			for x=0, 15 do
				pico8.quads[sprite]=love.graphics.newQuad(8*x, 8*y, 8, 8, 128, 128)
				sprite=sprite+1
			end
		end

		assert(sprite==256, sprite)

		pico8.spritesheet=love.graphics.newImage(pico8.spritesheet_data)

		-- load the sprite flags

		local gff_start=data:find("__gff__")+8
		local gff_end=data:find("__map__")-1
		local gffdata=data:sub(gff_start, gff_end)

		local sprite=0

		local next_line=1
		while next_line do
			local end_of_line=gffdata:find("\n", next_line)
			if end_of_line==nil then break end
			end_of_line=end_of_line-1
			local line=gffdata:sub(next_line, end_of_line)
			if version<=2 then
				for i=1, #line do
					local v=line:sub(i)
					v=tonumber(v, 16)
					pico8.spriteflags[sprite]=v
					sprite=sprite+1
				end
			else
				for i=1, #line, 2 do
					local v=line:sub(i, i+1)
					v=tonumber(v, 16)
					pico8.spriteflags[sprite]=v
					sprite=sprite+1
				end
			end
			next_line=gfxdata:find("\n", end_of_line)+1
		end

		assert(sprite==256, "wrong number of spriteflags: "..sprite)

		-- convert the tile data to a table

		local map_start=data:find("__map__")+8
		local map_end=data:find("__sfx__")-1
		local mapdata=data:sub(map_start, map_end)

		local row=0
		local col=0

		local next_line=1
		while next_line do
			local end_of_line=mapdata:find("\n", next_line)
			if end_of_line==nil then
				break
			end
			end_of_line=end_of_line-1
			local line=mapdata:sub(next_line, end_of_line)
			for i=1, #line, 2 do
				local v=line:sub(i, i+1)
				v=tonumber(v, 16)
				if col==0 then
				end
				pico8.map[row][col]=v
				col=col+1
				tiles=tiles+1
				if col==128 then
					col=0
					row=row+1
				end
			end
			next_line=mapdata:find("\n", end_of_line)+1
		end
		assert(tiles+shared==128*64, string.format("%d + %d != %d", tiles, shared, 128*64))

		-- load sfx
		local sfx_start=data:find("__sfx__")+8
		local sfx_end=data:find("__music__")-1
		local sfxdata=data:sub(sfx_start, sfx_end)

		local _sfx=0
		local step=0

		local next_line=1
		while next_line do
			local end_of_line=sfxdata:find("\n", next_line)
			if end_of_line==nil then break end
			end_of_line=end_of_line-1
			local line=sfxdata:sub(next_line, end_of_line)
			local editor_mode=tonumber(line:sub(1, 2), 16)
			pico8.sfx[_sfx].speed=tonumber(line:sub(3, 4), 16)
			pico8.sfx[_sfx].loop_start=tonumber(line:sub(5, 6), 16)
			pico8.sfx[_sfx].loop_end=tonumber(line:sub(7, 8), 16)
			for i=9, #line, 5 do
				local v=line:sub(i, i+4)
				assert(#v==5)
				local note =tonumber(line:sub(i, i+1), 16)
				local instr=tonumber(line:sub(i+2, i+2), 16)
				local vol  =tonumber(line:sub(i+3, i+3), 16)
				local fx   =tonumber(line:sub(i+4, i+4), 16)
				pico8.sfx[_sfx][step]={note, instr, vol, fx}
				step=step+1
			end
			_sfx=_sfx+1
			step=0
			next_line=sfxdata:find("\n", end_of_line)+1
		end

		assert(_sfx==64)

		-- load music
		local music_start=data:find("__music__")+10
		local music_end=#data-1
		local musicdata=data:sub(music_start, music_end)

		local _music=0

		local next_line=1
		while next_line do
			local end_of_line=musicdata:find("\n", next_line)
			if end_of_line==nil then break end
			end_of_line=end_of_line-1
			local line=musicdata:sub(next_line, end_of_line)
			local music=pico8.music[_music]
			music.loop=tonumber(line:sub(1, 2), 16)
			music[0]=tonumber(line:sub(4, 5), 16)
			music[1]=tonumber(line:sub(6, 7), 16)
			music[2]=tonumber(line:sub(8, 9), 16)
			music[3]=tonumber(line:sub(10, 11), 16)
			_music=_music+1
			next_line=musicdata:find("\n", end_of_line)+1
		end
	end

	-- patch the lua
	lua=lua:gsub("!=", "~=")
	-- rewrite shorthand if statements eg. if (not b) i=1 j=2
	lua=lua:gsub("if%s*(%b())%s*([^\n]*)\n", function(a, b)
		local nl=a:find('\n', nil, true)
		local th=b:find('%f[%w]then%f[%W]')
		local an=b:find('%f[%w]and%f[%W]')
		local o=b:find('%f[%w]or%f[%W]')
		local ce=b:find('--', nil, true)
		if not (nl or th or an or o) then
			if ce then
				local c, t=b:match("(.-)(%s-%-%-.*)")
				return "if "..a:sub(2, -2).." then "..c.." end"..t.."\n"
			else
				return "if "..a:sub(2, -2).." then "..b.." end\n"
			end
		end
	end)
	-- rewrite assignment operators
	lua=lua:gsub("(%S+)%s*([%+-%*/%%])=", "%1 = %1 %2 ")

	local cart_G={}
	for k, v in pairs(api) do
		cart_G[k]=v
	end

	local ok, f, e=pcall(load, lua, filename)
	if not ok or f==nil then
		log('=======8<========')
		log(lua)
		log('=======>8========')
		error("Error loading lua: "..tostring(e))
	else
		local result
		setfenv(f, cart_G)
		love.graphics.setShader(pico8.draw_shader)
		love.graphics.setCanvas(pico8.screen)
		love.graphics.origin()
		restore_clip()
		ok, result=pcall(f)
		if not ok then
			error("Error running lua: "..tostring(result))
		else
			log("lua completed")
		end
	end
	log("finished loading cart", filename)

	return cart_G
end

return cart
