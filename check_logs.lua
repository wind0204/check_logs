#!/usr/bin/env lua

--[[
	Writer		: Dewr<wind8702@gmail.com>
	Description	: a log checker searches text files while it's caring about
		the time range. I made it for my irc life with znc though it may work
		well with other logs as well.
]]
--FIXME: it heavily depends on the modification time of files, so the file
--	copied/modified by users will produce errors when this program is checking
--	time range
--TODO: increase portability

require "alt_getopt"
require "lfs"

local a_local_func

local version = "2013.03.23"
local help_msg = [[check_logs ]]..version.."\n\n"..[[
SYNOPSIS
    ]]..arg[0]..[[ [OPTIONS...]

OPTIONS
    -e PATTERN, --exp=PATTERN
        a vertical bar (|) separated list of lua patterns for which you want
        to search.  see LUA PATTERN for details.
    -x PATTERN_EXCEPT, --except=PATTERN_EXCEPT
        a vertical bar (|) separated list of lua patterns for which this
        program will not search. this program will try to match this pattern
        with timestamp excluded text. ( "[MM-dd mm:ss] blah" -> "] blah" I
        recommend you to use this like '-x "^[%p%s]*NICK[%p%s]"'. see
        LUA PATTERN for details.
    -n PATTERN_FNAME, --fname=PATTERN_FNAME
        a vertical bar (|) separated list of lua patterns that are the
        patterns for names of files in which you want to search. the default
        value is "%..*log$". see LUA PATTERN for details.
    -d DIRS, --dirs=DIRS
        a comma separated list of directories in which log files are saved.
        all log files are read recursively from the root directories. the
        default value is "~/.znc/users/".
    -X DIRS_EXCLUDE, --exclude=DIRS_EXCLUDE
        a comma separated list of directories that are excluded in search.
    -t TO, --to=TO
        the default value is = "now", see TIME FORMAT for details.
    -f FROM, --from=FROM
        the default value is = "TO - 24 hours", see TIME FORMAT for details.
    -v, --verbose
        be more verbose.
    -h, --help
        print this help and exit.

LUA PATTERN
    Lua patterns are somehow same but a little different with the regular
    expressions, and lua patterns are way less powerful. e.g. no support for
    {n1,n2}, (?i)foobar and (foo|bar). And, you can't do some trick other than
    just 1:1 match for UTF-8 characters.

TIME FORMAT
    yyyyMMddhh | yyMMddhh | MMddhh | ddhh | hh | yyyy-MM-dd hh:mm:ss |
    yy-MM-dd mm:ss | yyyy-MM-dd hh | yy-MM-dd | hh:mm | now | TO |
    .+\s*[+-]\s*(\d+|an?)\s*(years?|months?|weeks?|days?|hours?|minutes?|seconds?)

FILES
    $HOME/.config/check_logs.conf
        main configuration file]]

-- getopt options
local long_opts = {
	debug	= "b",
	exp		= "e",
	except	= "x",
	fname	= "n",
	dirs	= "d",
	exclude	= "X",
	to		= "t",
	from	= "f",
	verbose	= "v",
	help	= "h"
}

-- in vim, try i_CTRL-R_=
local time_keywords = {}
time_keywords.second= 1
time_keywords.minute= 60
time_keywords.hour	= 3600
time_keywords.day	= 86400
time_keywords.week	= 604800
time_keywords.month	= 2592000
time_keywords.year	= 31536000
local now = os.time()
local date_now = os.date("*t", now)

-- default values
local def_vals = {
	x = "",
	n = "%..*log$",
	d = "~/.znc/users",
	X = "",
	t = {time=now},
	f = "TO-aday"
}

local optarg
local optind
optarg,optind = alt_getopt.get_opts (arg, "e:x:n:d:X:t:f:hvb", long_opts)

-- if h(help) is specified, print help_msg
if optarg.h then
	io.write(help_msg, "\n")
	return 0
end

--local read_conf_file
if not (optarg.f and optarg.t and optarg.d and optarg.X and optarg.n and optarg.x and optarg.e) then
	local conf_file
	local err
	--FIXME: would it work in Windows?
	conf_file,err = io.open(os.getenv("HOME").."/.config/check_logs.conf")
	if not conf_file then
		if optarg.v or optarg.b then io.write("# couldn't open the configuration file : ",err,"\n") end
	else
		for line in conf_file:lines() do
			if not string.find(line, "^%s*#") then
				local key,value
				key, value = string.match(line, "^%s*(%w+)%s*=%s*(.*)%s*$")
				if key then
					for k,v in pairs(long_opts) do
						if k == key then
							def_vals[v] = value
							break
						end
					end
				end
			end
		end
		conf_file.close(conf_file)
	end
end

-- if an option is not specified, use the default value
for k,v in pairs(def_vals) do
	if not optarg[k] then
		optarg[k] = v
	end
end

if not optarg.e then
	io.write("# No pattern is specified. Specify -h/--help for help message.", "\n")
	return -2
end

local function tokens(s,d,i)
	local state = {string=s, pattern="([^"..d.."]+)", cursor=i or 1}
	local function iter_tokens(state)
		local pos_b, pos_e, ret = string.find(state.string, state.pattern, state.cursor)
		if not pos_b then return nil end
		state.cursor=pos_e+1
		return ret
	end

	return iter_tokens, state
end
local function to_table(s,d)
	local t = {}
	for token in tokens(s,d) do
		table.insert(t,token)
	end
	return t
end

local function int_divide(v1, v2) v1=v1/v2 return v1-v1%1 end
-- calculate the time for s and return a date table in which date[time] is
-- Unix timestamp or just return false+error_string for an error
local function to_date(s, ref_date)
	local s1,l2 = string.find(s, "[+-].*%a.*$")
	if s1 then
		l2 = s1 --l2 = string.sub(s,s1,l2)
		s1 = s1-1
	else
		s1 = string.len(s)
	end
	s1 = string.sub(s,1,s1)

	if not ref_date then
		ref_date = {year=date_now.year,month=1,day=1,hour=0,min=0,sec=0}
	else
		if not ref_date.year then ref_date.year=date_now.year end
		if not ref_date.month then ref_date.month=1 end
		if not ref_date.day then ref_date.day=1 end
		if not ref_date.hour then ref_date.hour=0 end
		if not ref_date.min then ref_date.min=0 end
		if not ref_date.sec then ref_date.sec=0 end
	end

	local date
	if string.find(s1, "^%s*now%s*$") then
		date={time=now}
	else if string.find(s1, "^%s*TO%s*$") then
		date={time=optarg.t.time}
	else if string.find(s1, "^%s*%d+%s*$") then
		-- the format is like yyyyMMddhh
		local len = string.len(s1)
		s1=tonumber(s1)
		if len <= 2 then --hh
			date={}
			date.year = ref_date.year
			date.month = ref_date.month
			date.day = ref_date.day
			date.hour = s1
		else if len <= 4 then --ddhh
			date={}
			date.year = ref_date.year
			date.month = ref_date.month
			date.day = int_divide(s1,100)
			date.hour = s1%100
		else if len <= 6 then --MMddhh
			date={}
			date.year = ref_date.year
			date.month = int_divide(s1,10000)
			date.day = int_divide(s1%10000, 100)
			date.hour = s1%100
		else if len <= 12 then --yyyyMMddhh
			date={}
			date.year = int_divide(s1,1000000)
			if len == 8 then
				date.year = date.year + (ref_date.year - ref_date.year%100)
			end
			date.month = int_divide(s1%1000000,10000)
			date.day = int_divide(s1%10000,100)
			date.hour = s1%100
		else
			return false, "too long ("..s1..")"
		end end end end
		date.time = os.time{year=date.year, month=date.month, day=date.day, hour=date.hour}
	else
		local yday_string
		local l3,l4,time_string = string.find(s1, "(%d%d?:[%d:]*%d)")
		if l3 then
			yday_string = string.match(s1, "[%d-]+", l4+1)
			if not yday_string then
				yday_string = string.match(string.sub(s1,1,l3-1), "[%d-]+")
			end
		else
			yday_string = string.match(s1, "[%d-]+")
		end
		if not (time_string or yday_string) then
			return false, "wrong format ("..s1..")"
		end

		date={}
		date.year=ref_date.year
		date.month=ref_date.month
		date.day=ref_date.day
		date.hour=ref_date.hour
		date.min=ref_date.min
		date.sec=ref_date.sec
		if time_string then
			local indices={"sec","min","hour"}
			local tmp = to_table(time_string, ":")
			local j = 0
			if #tmp == 1 then
				date.hour = tmp[1]
			else
				for i=#tmp,1,-1 do
					j=j+1
					date[indices[j]]=tmp[i]
				end
			end
		end
		if yday_string then
			local indices={"day","month","year"}
			local tmp = to_table(yday_string, "-")
			local j = 0
			for i=#tmp,1,-1 do
				j=j+1
				date[indices[j]]=tmp[i]
			end
		end

		date.time=os.time(date)
	end end end

	-- if it is containing a modifier
	if l2 then
		local sign, number, unit = string.match(s,"^([+-])%s*([a%d][n%d]?%d*)%s*(%a+)%s*$",l2)

		if not sign then
			return false, "wrong format ("..string.sub(s,l2)..")"
		end
		if string.find(number,"^an?$") then
			number = 1
		end
		unit = string.match(unit,"^(.*[^s])s?$")
		if not time_keywords[unit] then
			return false, "unknown unit ("..unit..")"
		end

		number = time_keywords[unit]*number
		if string.find(sign,"-") then
			number = -number
		end

		date.time = date.time + number
		date.year=nil date.month=nil date.day=nil date.hour=nil date.min=nil date.sec=nil
	end

	return date
end

a_local_func = function(opt)
	local err
	if type(opt) ~= "table" then
		opt,err = to_date(opt, date_now)
		if not opt then
			io.write("# error! ", err, "\n")
			return false
		else
			return opt
		end
	else
		return opt
	end
end
optarg.t = a_local_func(optarg.t)
if not optarg.t then return -1 end
optarg.f = a_local_func(optarg.f)
if not optarg.f then return -1 end

if optarg.v or optarg.b then
	local l
	io.write("# exp = '",optarg.e,"'","\n")
	io.write("# except = '",optarg.x,"'","\n")
	io.write("# fname = '",optarg.n,"'","\n")
	io.write("# dirs = '",optarg.d,"'","\n")
	io.write("# exclude = '",optarg.X,"'","\n")
	if not optarg.f.sec then
		l = optarg.f.time
		optarg.f = os.date("*t", l)
		optarg.f.time = l
	end
	if not optarg.t.sec then
		l = optarg.t.time
		optarg.t = os.date("*t", l)
		optarg.t.time = l
	end
	io.write("# from = ",optarg.f.year,"-",optarg.f.month,"-",optarg.f.day," ",
		optarg.f.hour,":",optarg.f.min,":",optarg.f.sec," ","(",tostring(optarg.f.time),")","\n")
	io.write("# to = ",optarg.t.year,"-",optarg.t.month,"-",optarg.t.day,
		" ",optarg.t.hour,":",optarg.t.min,":",optarg.t.sec," ","(",tostring(optarg.t.time),")","\n")
end

optarg.e = to_table(optarg.e, "|")
optarg.x = to_table(optarg.x, "|")
optarg.X = to_table(optarg.X, ",")
optarg.n = to_table(optarg.n, "|")

local function search_in_a_file(file, lfs_data)
	local h_file, err, d, b, e
	h_file,err = io.open(file)
	if not h_file then
		io.write("# couldn't open '",file,"'","(",err,")","\n")
		return 0
	end

	if optarg.v then io.write("# searching in '",file,"'","\n") end
	local cnt = 0
	if not lfs_data then
		lfs_data,err = lfs.attributes(file)
		if not lfs_data then
			if optarg.v or optarg.b then io.write("# can't get attributes of the file : ", err, "\n") end
			return 0,err
		end
	end
	local ref_date = os.date("*t", lfs_data.modification)
	local basic_jmp_dist, short_dist_x2 = 4096, 192*2
	local last_jmp_dist = 0,0
	local is_backsearching
	local line, ret
	local cur = 0

	local line_checker = function(line)
		-- return false if it didn't find a meaningful string, 0 if it did, 1 if line is
		-- too old, -1 if line is too young
		b,e,d = string.find(line, "^%s*%p?(%d[%d-:%s]*%d)[^%d]")
		if d then
			d,err = to_date(d, ref_date)
			if not d then
				if optarg.b then io.write("# failed to_date : ", err, "\n") end
			else if d.time <= optarg.t.time and d.time >= optarg.f.time then
				b = false
				for i in next,optarg.e do
					if string.find(line, optarg.e[i], e) then
						b = true
						break
					end
				end
				if b then
					b = true
					for i in next,optarg.x do
						if string.find(line, optarg.x[i], e) then
							b = false
							break
						end
					end
					if b then
						return 0
					end
				end
			else
				if d.time < optarg.f.time then
					return 1
				else
					return -1
				end
			end end
		end
		return false
	end
	local date_checker = function(line)
		-- return false if it is in range or couldn't get a timestamp from it, 1 if
		-- the line is too old, -1 if it is too young
		b,e,d = string.find(line, "^%s*%p?(%d[%d-:%s]*%d)[^%d]")
		if d then
			d,err = to_date(d, ref_date)
			if d.time < optarg.f.time then
				return 1
			end
			if d.time > optarg.t.time then
				return -1
			end
		end
		return false
	end
	local len_text_chunk = 64
	local find_head = function(h_file, start_pos)
		-- has a side effect that is shifting file cursor backward
		local chunk
		local len
		d = start_pos
		while true do
			if d == 0 then return 0 end
			len = len_text_chunk
			d = d - len_text_chunk
			if d < 0 then len=len+d d = 0 end
			h_file:seek("set",d)
			chunk = h_file:read(len)
			b = string.find(chunk,"\n[^\n]*$")
			if b then
				return d+b
			end
		end
	end
	local jump_forward = function()
		if last_jmp_dist > 0 then
			if is_backsearching then
				d = last_jmp_dist/2
			else
				d = last_jmp_dist
			end
		else if last_jmp_dist < 0 then
			d = -last_jmp_dist/2
		else -- last_jmp_dist is 0
			d = basic_jmp_dist
		end end
		if cur+d >= lfs_data.size then
			d = (lfs_data.size-cur)/2
			if d < 1 then
				d = 1
			end
		end
		d = math.ceil(d)
		cur,err = h_file:seek("set", cur+d)
		last_jmp_dist = d
	end
	local jump_backward = function()
		if last_jmp_dist > 0 then
			d = -last_jmp_dist/2
		else
			d = last_jmp_dist/2
		end
		d = math.floor(d)
		cur,err = h_file:seek("set", cur+d)
		is_backsearching=true
		last_jmp_dist = d
	end
	local walk_backward = function (start_pos)
		-- stop jumping and find the head of lines
		local last_head = start_pos
		is_backsearching = false
		last_jmp_dist = 0
		while true do
			last_head = find_head(h_file, last_head)
			h_file:seek("set", last_head)
			b = date_checker(h_file:read())
			if b then
				return
			end
			last_head = last_head-1
			if last_head < 0 then
				last_head = 0
			end
		end
	end
	local check_back = function()
		-- return false if couldn't get a timestamp from it, 1 if the line is too
		-- old, -1 if it is too young, 0 if it is in time range
		local ori_pos = cur
		local last_head = cur
		while true do
			last_head = find_head(h_file, last_head)
			--[[if last_head == 0 then
				h_file:seek("set", ori_pos)
				return false, 0
			end]]
			h_file:seek("set", last_head)
			b,e,d = string.find(h_file:read(), "^%s*%p?(%d[%d-:%s]*%d)[^%d]")
			if d then
				d,err = to_date(d, ref_date)
				h_file:seek("set", ori_pos)
				if d.time < optarg.f.time then
					return 1, last_head
				end
				if d.time > optarg.t.time then
					return -1, last_head
				end
				return 0, last_head
			end
			last_head = last_head-1
			if last_head < 0 then
				last_head = 0
			end
		end
	end

	while true do
		if last_jmp_dist ~= 0 then
			h_file:seek("set", find_head(h_file, cur))
			line = h_file:read()
		else
			line = h_file:read()
			cur = h_file:seek() - 1
		end
		if not line then
			break
		end
		ret = line_checker(line)
		if ret then
			if ret == 0 then -- found some meaningful text
				if last_jmp_dist == 0 then
					if cnt == 0 then
						io.write("\n#@ ", file, "\n")
					end
					cnt = cnt+1
					io.write(" ", line, "\n")
				else
					if math.abs(last_jmp_dist) > short_dist_x2 then
						jump_backward()
					else
						walk_backward(cur)
					end
				end
			else if ret > 0 then -- older than optarg.f
				jump_forward()
			else -- younger than optarg.t
				if last_jmp_dist == 0 then
					break
				end
				jump_backward()
			end end
		else if last_jmp_dist ~= 0 then
			b,d = check_back(true)
			if b > 0 then -- older than optarg.f
				jump_forward()
			else if b < 0 then -- younger than optarg.t
				jump_backward()
			else if b == 0 then -- in time range
				walk_backward(d)
			end end end
		end end
	end
	h_file:close()
	return cnt
end

local function start_search(path, lfs_data)
	local len = string.len(path)
	if string.find(path,"/",len,true) then
		--FIXME: "\" will be used instead in Windows
		path = string.sub(path,1,len-1)
	end
	if not lfs_data then
		lfs_data,len = lfs.attributes(path)
		if not lfs_data then
			if optarg.v or optarg.b then io.write("# can't get attributes of the file : ", len, "\n") end
			return 0,len
		end
	end
	if lfs_data.mode ~= "directory" then
		return search_in_a_file(path, lfs_data)
	else
		for i in next,optarg.X do
			if optarg.X[i]==path then
				return 0
			end
		end
		if optarg.v then io.write("# searching in '",path,"'","\n") end
		local cnt = 0
		local b
		local files = {}
		for file in lfs.dir(path) do
			table.insert(files, file)
		end
		table.sort(files)
		for k,file in ipairs(files) do
			if file ~= "." and file ~= ".." then
				file = path.."/"..file
				lfs_data = lfs.attributes(file)
				if lfs_data.mode ~= "directory" then
					if lfs_data.modification >= optarg.f.time then
						b = false
						for i in next, optarg.n do
							if string.find(file, optarg.n[i]) then
								b = true
								break
							end
						end
						if b then
							cnt = cnt+search_in_a_file(file, lfs_data)
						else
							if optarg.v then io.write("# pattern is not matched for the file name : ", file, "\n") end
						end
					--[[else
						if optarg.b then io.write("# skipping old file '",file,"'","\n") end]]
					end
				else
					cnt = cnt+start_search(file, lfs_data)
				end
			end
		end
		return cnt
	end
end

local function decode_file_path(path)
	local new_path = false
	local len = string.len(path)

	if string.find(path,"/",len,true) then
		--FIXME: "\" will be used instead in Windows
		new_path = string.sub(path,1,len-1)
		path = new_path
	end

	if path == "~" then
		new_path = os.getenv("HOME")
	else
		new_path = string.gsub(path, "^~/", os.getenv("HOME").."/")
		new_path = string.gsub(new_path, "%$(%w+)", os.getenv)
	end
	--FIXME: would it work in Windows?

	return new_path
end

for i in next,optarg.X do
	local new_path
	local path = optarg.X[i]

	new_path = decode_file_path(path)
	if new_path then optarg.X[i] = new_path end
end

if optarg.v then print("# starting the search.") end
local total_cnt = 0
for path in tokens(optarg.d, ",") do
	local new_path
	new_path = decode_file_path(path)

	total_cnt = total_cnt+start_search(new_path or path)
end
io.write("\n","# the number of cases : ", tostring(total_cnt), "\n")
io.write("# elapsed time : about ",os.time()-now,"(±1) secs","\n")
return 0
