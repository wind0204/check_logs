#!/usr/bin/env lua

--[[
	Writer		: Dewr<wind8702@gmail.com>
	Description	: a log checker searches text files while it's caring the time
		range. I made it for my irc life with znc though it may work well with
		other logs as well.
]]
--FIXME: it heavily depends on the modification time of files, so the file copied/modified by users will produce errors when this program is checking time range
--TODO: optimization for speed

require "alt_getopt"
require "lfs"

-- run an anonymous function
local function run_it(func) return func() end
local f

local version = "2013.03.15"
local help_msg = [[check_logs.lua ]]..version.."\n\n"..[[
SYNOPSIS
	check_logs.lua [-e PATTERN] [-n PATTERN_FNAME] [-d DIRS] [-f FROM] [-t TO] [-v]

OPTIONS
	-e PATTERN, --exp=PATTERN
		a vertical bar (|) separated list of lua patterns for which you want
		to search.  see LUA PATTERN for details.
	-n PATTERN_FNAME, --fname=PATTERN_FNAME
		a vertical bar (|) separated list of lua patterns that is the pattern
		for names of files in which you want to search. the default value is
		"%..*log$". see LUA PATTERN for details.
	-d DIRS, --dirs=DIRS
		a comma separated list of directories in which log files are saved.
		all log files are read recursively from the root directories. the
		default value is "~/.znc/users/".
	-t TO, --to=TO
		the default value is = now, see TIME FORMAT for details.
	-f FROM, --from=FROM
		the default value is = TO - 24 hours, see TIME FORMAT for details.

LUA PATTERN
	Lua patterns are somehow same but a little different with the regular
	expressions, and lua patterns are way less powerful. e.g. no support for
	{n1,n2}, (?i)foobar and (foo|bar). And, you can't do some trick other than
	just 1:1 match for UTF-8 characters.

TIME FORMAT
	yyyymmddhh | yymmddhh | mmddhh | ddhh | hh | yyyy-mm-dd hh:mm:ss |
	yy-mm-dd hh:mm | yyyy-mm-dd hh | yy-mm-dd | hh:mm | now |
	.+\s*[+-]\s*(\d+|an?)\s*(years?|months?|weeks?|days?|hours?|minutes?|seconds?)

FILES
	$HOME/.config/check_logs.conf
		main configuration file]]

-- getopt options
local long_opts = {
	debug	= "b",
	exp		= "e",
	fname	= "n",
	dirs	= "d",
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
	d = "~/.znc/users",
	n = "%..*log$",
	t = {time=now}
}

local optarg
local optind
optarg,optind = alt_getopt.get_opts (arg, "e:n:d:t:f:hvb", long_opts)

-- if h(help) is specified, print help_msg
if optarg.h then
	io.write(help_msg, "\n")
	return
end

--[[
for i = optind,#arg do
	io.write (string.format ("ARGV [%s] = %s\n", i, arg [i]))
end
]]

--local read_conf_file
if not (optarg.f and optarg.t and optarg.d and optarg.n and optarg.e) then
	run_it( function()
		local conf_file
		local err
		--FIXME: would it work in Windows?
		conf_file,err = io.open(os.getenv("HOME").."/.config/check_logs.conf")
		if not conf_file then
			if optarg.v then io.write("# couldn't open the configuration file : ",err,"\n") end
			return
		end

		io.input(conf_file)
		for line in io.lines() do
			if not string.find(line, "^%s*#") then
				local key,value
				key, value = string.match(line, "^%s*(%w+)%s*=%s*(.*)%s*$")
				if key then
					for k,v in pairs(long_opts) do
						if k == key then
							def_vals[v] = value
						end
					end
				end
			end
		end
		conf_file.close(conf_file)
	end)
end

if not (def_vals.f or optarg.f) then
	local l
	if optarg.t then
		l = optarg.t
	else
		l = def_vals.t
	end

	if type(l) == "table" then
		def_vals.f = {time=l.time - time_keywords.day}
		if def_vals.f.time < 0 then
			def_vals.f.time = 0
		end
	else
		def_vals.f = l.."-aday"
	end
end

-- if an option is not specified, use the default value
for k,v in pairs(def_vals) do
	if not optarg[k] then
		optarg[k] = v
	end
end

if not optarg.e then
	io.write("# No pattern is specified. specify -h/--help for help message.", "\n")
	return
end

local function tokens(s,d,i)
	state = {string=s, pattern="([^"..d.."]+)", cursor=i or 1}
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
-- calculate the time for s, or false for an error
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
	else if string.find(s1, "^%s*%d+%s*$") then
		-- the format is like yyyymmddhh
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
		else if len <= 6 then --mmddhh
			date={}
			date.year = ref_date.year
			date.month = int_divide(s1,10000)
			date.day = int_divide(s1%10000, 100)
			date.hour = s1%100
		else if len <= 12 then --yyyymmddhh
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
			for i=#tmp,1,-1 do
				j=j+1
				date[indices[j]]=tmp[i]
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
	end end

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

f = function(a)
	local l
	if type(a) ~= "table" then
		a,l = to_date(a, date_now)
		if not a then
			io.write("# error! ", l, "\n")
			return false
		else
			return a
		end
	else
		return a
	end
end
optarg.f = f(optarg.f)
optarg.t = f(optarg.t)
if (not optarg.f) or (not optarg.t) then
	return
end

if optarg.v then
	local l
	io.write("# exp = '",optarg.e,"'","\n")
	io.write("# fname = '",optarg.n,"'","\n")
	io.write("# dirs = '",optarg.d,"'","\n")
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
optarg.n = to_table(optarg.n, "|")

local function search_in_a_file(file, lfs_data)
	local h_file, err, d, b, c
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
			if optarg.v then io.write("# can't get attributes of the file : ", err, "\n") end
			return 0,err
		end
	end
	local ref_date = os.date("*t", lfs_data.modification)
	io.input(h_file)
	for line in io.lines() do
		b,e,d = string.find(line, "^%s*%p?(%d[%d-:%s]*%d)[^%d]")
		if d then
			d,err = to_date(d, ref_date)
			if not d then
				if optarg.b then print(err) end
			else if d.time <= optarg.t.time and d.time >= optarg.f.time then
				b = false
				for i in next,optarg.e do
					if string.find(line, optarg.e[i], e) then
						b = true
						break
					end
				end
				if b then
					if cnt == 0 then
						io.write("\n# @", file, "\n")
					end
					cnt = cnt+1
					io.write(" ", line, "\n")
				end
			--[[else if optarg.b then
				io.write("# out of time range : ", line, "\n")]]
			end end
		end
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
			if optarg.v then io.write("# can't get attributes of the file : ", len, "\n") end
			return 0,len
		end
	end
	if lfs_data.mode ~= "directory" then
		return search_in_a_file(path, lfs_data)
	else
		if optarg.v then io.write("# searching in '",path,"'","\n") end
		local cnt = 0
		local b
		for file in lfs.dir(path) do
			if file ~= "." and file ~= ".." then
				file = path.."/"..file
				lfs_data = lfs.attributes(file)
				if lfs_data.mode ~= "directory" then
					if lfs_data.modification >= optarg.f.time then
						b = false
						for i in next, optarg.n do
							if string.find(file, optarg.n[i]) then
								b = true
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
if optarg.v then print("# starting the search.") end
local total_cnt = 0
for path in tokens(optarg.d, ",") do
	if path == "~" then
		patn = os.getenv("HOME")
	else
		path = string.gsub(path, "^~/", os.getenv("HOME").."/")
		path = string.gsub(path, "%$(%w+)", os.getenv)
	end
	--FIXME: would it work in Windows?

	total_cnt = total_cnt+start_search(path)
end
if optarg.v then io.write("# the number of cases : ", tostring(total_cnt), "\n") end
return 0