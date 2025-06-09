local ipairs,loadfile,pairs,pcall,tonumber,tostring = ipairs,loadfile,pairs,pcall,tonumber,tostring
local debug,io,math,os,string,table,utf8 = debug,io,math,os,string,table,utf8
local min,max,floor,ceil,huge = math.min,math.max,math.floor,math.ceil,math.huge
local mp		= require "mp"
local assdraw	= require "mp.assdraw"
local msg		= require "mp.msg"
local opt		= require "mp.options"
local utils		= require "mp.utils"

--
-- Parameters
--

local user_opts = {
	showwindowed = true,				-- show OSC when windowed?
	showfullscreen = true,				-- show OSC when fullscreen?
	idlescreen = false,					-- show mpv logo on idle
	--scalewindowed = 1.4,				-- scaling of the controller when windowed (vidscale true 4K)
	--scalefullscreen = 0.9,			-- scaling of the controller when fullscreen (vidscale true 4K)
	--scaleforcedwindow = 1,			-- scaling when rendered on a forced window (vidscale true 4K)
	scalewindowed = 2.0,				-- scaling of the controller when windowed (vidscale false 4K)
	scalefullscreen = 2.8,				-- scaling of the controller when fullscreen (vidscale false 4K)
	scaleforcedwindow = 1,				-- scaling when rendered on a forced window (vidscale false 4K)
	vidscale = false,					-- scale the controller with the video?
	boxalpha = 80,						-- opacity of the background box (thumbnail), 0 (opaque) to 255 (transparent)
	alphaUntoggledButton = 120,			-- opacity untoggled button, 0 (opaque) to 255 (transparent)
	alphaWinCtrl = 60,					-- opacity windows controls, 0 (opaque) to 255 (transparent)
	seekrangealpha = 64,				-- transparency of seekranges
	seekbarhandlesize = 0,				-- size ratio of the knob handle
	seekbarkeyframes = true,			-- use keyframes when dragging the seekbar
	hidetimeout = 0,					-- duration in ms until the OSC hides (case "don't show on mouse move")
	fadeduration = 0,					-- duration of fade out in ms, 0 = no fade (case "don't show on mouse move")
	hidetimeoutMouseMove = 1000,		-- duration in ms until the OSC hides (case "show on mouse move")
	fadedurationMouseMove = 500,		-- duration of fade out in ms, 0 = no fade (case "show on mouse move")
	minmousemove = -1,					-- min amount of pixels for OSC to show up (Don't show < 0, show >= 0)
	layout = "modernx",					-- set thumbnail layout
	title = "${filename}",				-- string compatible with property-expansion to be shown as OSC title
	timetotal = false,					-- display total time instead of remaining time?
	visibility = "auto",				-- only used at init to set visibility_mode(...)
	windowcontrols = "auto",			-- whether to show window controls
	windowcontrols_title = false,		-- whether to show the title with the window controls
	livemarkers = true,					-- update seekbar chapter markers on duration change
	chapters_osd = false,				-- whether to show chapters OSD on next/prev
	playlist_osd = false,				-- whether to show playlist OSD on next/prev
	chapter_fmt = "Chapter: %s",		-- chapter print format for seekbar-hover. "no" to disable
	showonpause = false,				-- show OSC on pause
	showonstart = false,				-- show OSC on startup or when the next file in playlist starts playing
	showonseek = false,					-- show OSC when seeking
	oscFont = "Play",					-- font for OSC
	tick_delay = 1 / 60,				-- minimum interval between OSC redraws in seconds
	seekrangestyle = "none",			-- display demuxer cache in seekbar
	tick_delay_follow_display_fps = false, -- use display fps as the minimum interval

	-- tog4in1

	modernTog = true,					-- Default UI (true) or PotPlayer-like UI (false)
	minimalUI = false,					-- Minimal UI (chapters disabled)
	UIAllWhite = false,					-- UI all white (no grey buttons / text)
	saveFile = true,					-- Minimal UI (chapters disabled)
	minimalSeekY = 30,					-- Height minimal UI
	jumpValue = 5,						-- Default jump value in s (From OSC only)
	smallIcon = 20,						-- Dimensions in px of small icons
	seekbarColorIndex = 4,				-- Default OSC seekbar color (osc_palette)
	seekbarHeight = 0,					-- seekbar height offset
	seekbarBgHeight = true,				-- seekbar background height follow seekbar height
	bgBarAlpha = 220,					-- seekbar background opacity
	showCache = false,					-- Show cache
	showInfos = false,					-- Toggle Statistics
	showThumbfast = true,				-- Toggle Thumbfast
	showTooltip = true,					-- Toggle Tooltips
	showChapters = false, 				-- Toggle chapters on / off
	showTitle = false,					-- show title in OSC
	showIcons = true,					-- show extra buttons
	onTopWhilePlaying = true, 			-- Toggle On top while playing
	oscMode = "default",				-- Toggle OSC Modes default / onpause / always
	heightoscShowHidearea = 120,		-- Height show / hide osc area
	heightwcShowHidearea = 30,			-- Height show / hide window controls area
	visibleButtonsW = 300,				-- Max width for bottom OSC side buttons visible
}

-- read options from config and command-line
opt.read_options(user_opts, "osc", function(list) update_options(list) end)

-- deus0ww - 2021-11-26

-----------
-- Utils --
-----------

local OS_MAC, OS_WIN, OS_NIX = "MAC", "WIN", "NIX"
local function get_os()
	if jit and jit.os then
		if jit.os == "Windows" then return OS_WIN
		elseif jit.os == "OSX" then return OS_MAC
		else return OS_NIX end
	end
	if (package.config:sub(1,1) ~= "/") then return OS_WIN end
	local res = mp.command_native({ name = "subprocess", args = {"uname", "-s"}, playback_only = false, capture_stdout = true, capture_stderr = true, })
	return (res and res.stdout and res.stdout:lower():find("darwin") ~= nil) and OS_MAC or OS_NIX
end
local OPERATING_SYSTEM = get_os()

local function format_json(tab)
	local json, err = utils.format_json(tab)
	if err then msg.error("Formatting JSON failed:", err) end
	if json then return json else return "" end
end

local function parse_json(json)
	local tab, err = utils.parse_json(json, true)
	if err then msg.error("Parsing JSON failed:", err) end
	if tab then return tab else return {} end
end

local function join_paths(...)
	local sep = OPERATING_SYSTEM == OS_WIN and "\\" or "/"
	local result = ""
	for _, p in ipairs({...}) do
		result = (result == "") and p or result .. sep .. p
	end
	return result
end

--------------------
-- Data Structure --
--------------------

local tn_state, tn_osc, tn_osc_options, tn_osc_stats
local tn_thumbnails_indexed, tn_thumbnails_ready
local tn_gen_time_start, tn_gen_duration

local function reset_all()
	tn_state			  = nil
	tn_osc = {
		cursor				= {},
		position			= {},
		scale				= {},
		osc_scale			= {},
		spacer				= {},
		osd					= {},
		background			= {text = "︎✇",},
		font_scale			= {},
		display_progress  	= {},
		progress			= {},
		mini				= {text = "⚆",},
		thumbnail = {
			visible	  		= false,
			path_last		= nil,
			x_last	   		= nil,
			y_last	   		= nil,
		},
	}
	tn_osc_options		= nil
	tn_osc_stats = {
		queued				= 0,
		processing			= 0,
		ready				= 0,
		failed				= 0,
		total				= 0,
		total_expected		= 0,
		percent				= 0,
		timer				= 0,
	}
	tn_thumbnails_indexed 	= {}
	tn_thumbnails_ready   	= {}
	tn_gen_time_start	 	= nil
	tn_gen_duration	   		= nil
end

-------------------
-- Thumbnail OSC --
-------------------

local message = {
	osc = {
		registration	= "tn_osc_registration",
		reset			= "tn_osc_reset",
		update			= "tn_osc_update",
		finish			= "tn_osc_finish",
	},
	debug = "Thumbnailer-debug",

	queued		= 1,
	processing	= 2,
	ready		= 3,
	failed		= 4,
}

local osc_reg = {
	script_name = mp.get_script_name(),
	osc_opts = {
		scalewindowed   = user_opts.scalewindowed,
		scalefullscreen = user_opts.scalefullscreen,
	},
}
mp.command_native({"script-message", message.osc.registration, format_json(osc_reg)})

local tn_palette = {
	black			= "000000",
	white			= "FFFFFF",
	alpha_opaque 	= 0,
	alpha_clear  	= 255,
	alpha_black  	= min(255, user_opts.boxalpha),
	alpha_white  	= min(255, user_opts.boxalpha + (255 - user_opts.boxalpha) * 0.8),
}

local tn_style_format = {
	background		= "{\\bord0\\1c&H%s&\\1a&H%X&}",
	subbackground	= "{\\bord0\\1c&H%s&\\1a&H%X&}",
	spinner 		= "{\\bord0\\fs%d\\fscx%f\\fscy%f",
	spinner2		= "\\1c&%s&\\1a&H%X&\\frz%d}",
	closest_index	= "{\\1c&H%s&\\1a&H%X&\\3c&H%s&\\3a&H%X&\\xbord%d\\ybord%d}",
	progress_mini	= "{\\bord0\\1c&%s&\\1a&H%X&\\fs18\\fscx%f\\fscy%f",
	progress_mini2	= "\\frz%d}",
	progress_block	= "{\\bord0\\1c&H%s&\\1a&H%X&}",
	progress_text   = "{\\1c&%s&\\3c&H%s&\\1a&H%X&\\3a&H%X&\\blur0.25\\fs18\\fscx%f\\fscy%f\\xbord%f\\ybord%f}",
	text_timer		= "%.2ds",
	text_progress	= "%.3d/%.3d",
	text_progress2	= "[%d]",
	text_percent	= "%d%%",
}

local tn_style = {
	background		= (tn_style_format.background):format(tn_palette.black, tn_palette.alpha_black),
	subbackground	= (tn_style_format.subbackground):format(tn_palette.white, tn_palette.alpha_white),
	spinner			= (tn_style_format.spinner):format(0, 1, 1),
	closest_index	= (tn_style_format.closest_index):format(tn_palette.white, tn_palette.alpha_black, tn_palette.black, tn_palette.alpha_black, -1, -1),
	progress_mini	= (tn_style_format.progress_mini):format(tn_palette.white, tn_palette.alpha_opaque, 1, 1),
	progress_block	= (tn_style_format.progress_block):format(tn_palette.white, tn_palette.alpha_white),
	progress_text	= (tn_style_format.progress_text):format(tn_palette.white, tn_palette.black, tn_palette.alpha_opaque, tn_palette.alpha_black, 1, 1, 2, 2),
}

local function set_thumbnail_above(offset)
	local tn_osc = tn_osc
	tn_osc.background.bottom	= tn_osc.position.y - offset - tn_osc.spacer.bottom
	tn_osc.background.top		= tn_osc.background.bottom - tn_osc.background.h
	tn_osc.thumbnail.top		= tn_osc.background.bottom - tn_osc.thumbnail.h
	tn_osc.progress.top			= tn_osc.background.bottom - tn_osc.background.h
	tn_osc.progress.mid			= tn_osc.progress.top + tn_osc.progress.h * 0.5
	tn_osc.background.rotation	= -1
end

local function set_thumbnail_below(offset)
	local tn_osc = tn_osc
	tn_osc.background.top		= tn_osc.position.y + offset + tn_osc.spacer.top
	tn_osc.thumbnail.top		= tn_osc.background.top
	tn_osc.progress.top			= tn_osc.background.top + tn_osc.thumbnail.h + tn_osc.spacer.y
	tn_osc.progress.mid			= tn_osc.progress.top + tn_osc.progress.h * 0.5
	tn_osc.background.rotation	= 1
end

local function set_mini_above() tn_osc.mini.y = (tn_osc.background.top - 12 * tn_osc.osc_scale.y) end
local function set_mini_below() tn_osc.mini.y = (tn_osc.background.bottom + 12 * tn_osc.osc_scale.y) end

local set_thumbnail_layout = {
	topbar	= function()	tn_osc.spacer.top = 0.25
							set_thumbnail_below(38.75)
							set_mini_above() end,
	bottombar = function()  tn_osc.spacer.bottom = 0.25
							set_thumbnail_above(38.75)
							set_mini_below() end,
	box	   = function()		set_thumbnail_above(15)
							set_mini_above() end,
	slimbox   = function()  set_thumbnail_above(12)
							set_mini_above() end,
	modernx   = function()  set_thumbnail_above(20)
							set_mini_below() end,
}

local function update_tn_osc_params(seek_y)
	local tn_state, tn_osc_stats, tn_osc, tn_style, tn_style_format = tn_state, tn_osc_stats, tn_osc, tn_style, tn_style_format
	tn_osc.scale.x, tn_osc.scale.y		= get_virt_scale_factor()
	tn_osc.osd.w, tn_osc.osd.h			= mp.get_osd_size()
	tn_osc.cursor.x, tn_osc.cursor.y	= get_virt_mouse_pos()
	tn_osc.position.y					= seek_y

	local osc_changed = false
	if	 tn_osc.scale.x_last ~= tn_osc.scale.x or tn_osc.scale.y_last ~= tn_osc.scale.y
		or tn_osc.w_last ~= tn_state.width or tn_osc.h_last ~= tn_state.height
		or tn_osc.osd.w_last ~= tn_osc.osd.w or tn_osc.osd.h_last ~= tn_osc.osd.h
	then
		tn_osc.scale.x_last, tn_osc.scale.y_last = tn_osc.scale.x, tn_osc.scale.y
		tn_osc.w_last, tn_osc.h_last			 = tn_state.width, tn_state.height
		tn_osc.osd.w_last, tn_osc.osd.h_last	 = tn_osc.osd.w, tn_osc.osd.h
		osc_changed = true
	end

	if osc_changed then
		tn_osc.osc_scale.x, tn_osc.osc_scale.y   = 1, 1
		tn_osc.spacer.x, tn_osc.spacer.y		 = tn_osc_options.spacer, tn_osc_options.spacer
		tn_osc.font_scale.x, tn_osc.font_scale.y = 100, 100
		tn_osc.progress.h						 = (16 + tn_osc_options.spacer)
		if not user_opts.vidscale then
			tn_osc.osc_scale.x  = tn_osc.scale.x * tn_osc_options.scale
			tn_osc.osc_scale.y  = tn_osc.scale.y * tn_osc_options.scale
			tn_osc.spacer.x	 = tn_osc.osc_scale.x * tn_osc.spacer.x
			tn_osc.spacer.y	 = tn_osc.osc_scale.y * tn_osc.spacer.y
			tn_osc.font_scale.x = tn_osc.osc_scale.x * tn_osc.font_scale.x
			tn_osc.font_scale.y = tn_osc.osc_scale.y * tn_osc.font_scale.y
			tn_osc.progress.h   = tn_osc.osc_scale.y * tn_osc.progress.h
		end
		tn_osc.spacer.top, tn_osc.spacer.bottom  = tn_osc.spacer.y, tn_osc.spacer.y
		tn_osc.thumbnail.w, tn_osc.thumbnail.h   = tn_state.width * tn_osc.scale.x, tn_state.height * tn_osc.scale.y
		tn_osc.osd.w_scaled, tn_osc.osd.h_scaled = tn_osc.osd.w * tn_osc.scale.x, tn_osc.osd.h * tn_osc.scale.y
		tn_style.spinner						 = (tn_style_format.spinner):format(min(tn_osc.thumbnail.w, tn_osc.thumbnail.h) * 0.6667, tn_osc.font_scale.x, tn_osc.font_scale.y)
		tn_style.closest_index					 = (tn_style_format.closest_index):format(tn_palette.white, tn_palette.alpha_black, tn_palette.black, tn_palette.alpha_black, -1 * tn_osc.scale.x, -1 * tn_osc.scale.y)
		if tn_osc_stats.percent < 1 then
			tn_style.progress_text = (tn_style_format.progress_text):format(tn_palette.white, tn_palette.black, tn_palette.alpha_opaque, tn_palette.alpha_black, tn_osc.font_scale.x, tn_osc.font_scale.y, 2 * tn_osc.scale.x, 2 * tn_osc.scale.y)
			tn_style.progress_mini = (tn_style_format.progress_mini):format(tn_palette.white, tn_palette.alpha_opaque, tn_osc.font_scale.x, tn_osc.font_scale.y)
		end
	end

	if not tn_osc.position.y then return end
	if (osc_changed or tn_osc.cursor.x_last ~= tn_osc.cursor.x) and tn_osc.osd.w_scaled >= (tn_osc.thumbnail.w + 2 * tn_osc.spacer.x) then
		tn_osc.cursor.x_last  = tn_osc.cursor.x
		if tn_osc_options.centered then
			tn_osc.position.x = tn_osc.osd.w_scaled * 0.5
		else
			local limit_left  = tn_osc.spacer.x + tn_osc.thumbnail.w * 0.5
			local limit_right = tn_osc.osd.w_scaled - limit_left
			tn_osc.position.x = min(max(tn_osc.cursor.x, limit_left), limit_right)
		end
		tn_osc.thumbnail.left, tn_osc.thumbnail.right = tn_osc.position.x - tn_osc.thumbnail.w * 0.5, tn_osc.position.x + tn_osc.thumbnail.w * 0.5
		tn_osc.mini.x = tn_osc.thumbnail.right - 6 * tn_osc.osc_scale.x
	end

	if (osc_changed or tn_osc.display_progress.last ~= tn_osc.display_progress.current) then
		tn_osc.display_progress.last = tn_osc.display_progress.current
		tn_osc.background.h = tn_osc.thumbnail.h + (tn_osc.display_progress.current and (tn_osc.progress.h + tn_osc.spacer.y) or 0)
		set_thumbnail_layout[user_opts.layout]()
	end
end

local function find_closest(seek_index, round_up)
	local tn_state, tn_thumbnails_indexed, tn_thumbnails_ready = tn_state, tn_thumbnails_indexed, tn_thumbnails_ready
	if not (tn_thumbnails_indexed and tn_thumbnails_ready) then return nil, nil end
	local time_index = floor(seek_index * tn_state.delta)
	if tn_thumbnails_ready[time_index] then return seek_index + 1, tn_thumbnails_indexed[time_index] end
	local direction, index = round_up and 1 or -1
	for i = 1, tn_osc_stats.total_expected do
		index		= seek_index + (i * direction)
		time_index	= floor(index * tn_state.delta)
		if tn_thumbnails_ready[time_index] then return index + 1, tn_thumbnails_indexed[time_index] end
		index		= seek_index + (i * -direction)
		time_index	= floor(index * tn_state.delta)
		if tn_thumbnails_ready[time_index] then return index + 1, tn_thumbnails_indexed[time_index] end
	end
	return nil, nil
end

local draw_cmd = { name = "overlay-add",	id = 9, offset = 0, fmt = "bgra" }
local hide_cmd = { name = "overlay-remove", id = 9}

local function draw_thumbnail(x, y, path)
	draw_cmd.x = x
	draw_cmd.y = y
	draw_cmd.file = path
	mp.command_native(draw_cmd)
	tn_osc.thumbnail.visible = true
end

local function hide_thumbnail()
	if tn_osc and tn_osc.thumbnail and tn_osc.thumbnail.visible then
		mp.command_native(hide_cmd)
		tn_osc.thumbnail.visible = false
	end
end

local function show_thumbnail(seek_percent)
	if not seek_percent then return nil, nil end
	local scale, thumbnail, total_expected, ready = tn_osc.scale, tn_osc.thumbnail, tn_osc_stats.total_expected, tn_osc_stats.ready
	local seek = seek_percent * (total_expected - 1)
	local seek_index = floor(seek + 0.5)
	local closest_index, path = thumbnail.closest_index_last, thumbnail.path_last
	if	 thumbnail.seek_index_last		 ~= seek_index
		or thumbnail.ready_last			 ~= ready
		or thumbnail.total_expected_last ~= tn_osc_stats.total_expected
	then
		closest_index, path = find_closest(seek_index, seek_index < seek)
		thumbnail.closest_index_last, thumbnail.total_expected_last, thumbnail.ready_last, thumbnail.seek_index_last = closest_index, total_expected, ready, seek_index
	end
	local x, y = floor((thumbnail.left or 0) / scale.x + 0.5), floor((thumbnail.top or 0) / scale.y + 0.5)
	if path and not (thumbnail.visible and thumbnail.x_last == x and thumbnail.y_last == y and thumbnail.path_last == path) then
		thumbnail.x_last, thumbnail.y_last, thumbnail.path_last  = x, y, path
		draw_thumbnail(x, y, path)
	end
	return closest_index, path
end

local function ass_new(ass, x, y, align, style, text)
	ass:new_event()
	ass:pos(x, y)
	if align then ass:an(align)		end
	if style then ass:append(style) end
	if text  then ass:append(text)  end
end

local function ass_rect(ass, x1, y1, x2, y2)
	ass:draw_start()
	ass:rect_cw(x1, y1, x2, y2)
	ass:draw_stop()
end

local draw_progress = {
	[message.queued]	 = function(ass, index, block_w, block_h) ass:rect_cw((index - 1) * block_w,			 0, index * block_w, block_h) end,
	[message.processing] = function(ass, index, block_w, block_h) ass:rect_cw((index - 1) * block_w, block_h * 0.2, index * block_w, block_h * 0.8) end,
	[message.failed]	 = function(ass, index, block_w, block_h) ass:rect_cw((index - 1) * block_w, block_h * 0.4, index * block_w, block_h * 0.6) end,
}

local function display_tn_osc(seek_y, seek_percent, ass)
	if not (seek_y and seek_percent and ass and tn_state and tn_osc_stats and tn_osc_options and tn_state.width and tn_state.height and tn_state.duration and tn_state.cache_dir) or not tn_osc_options.visible then hide_thumbnail() return end

	update_tn_osc_params(seek_y)
	local tn_osc_stats, tn_osc, tn_style, tn_style_format, ass_new, ass_rect, seek_percent = tn_osc_stats, tn_osc, tn_style, tn_style_format, ass_new, ass_rect, seek_percent * 0.01
	local closest_index, path = show_thumbnail(seek_percent)

	-- Background
	ass_new(ass, tn_osc.thumbnail.left, tn_osc.background.top, 7, tn_style.background)
	ass_rect(ass, -tn_osc.spacer.x, -tn_osc.spacer.top, tn_osc.thumbnail.w + tn_osc.spacer.x, tn_osc.background.h + tn_osc.spacer.bottom)

	local spinner_color, spinner_alpha = tn_palette.white, tn_palette.alpha_white
	if not path then
		ass_new(ass, tn_osc.thumbnail.left, tn_osc.thumbnail.top, 7, tn_style.subbackground)
		ass_rect(ass, 0, 0, tn_osc.thumbnail.w, tn_osc.thumbnail.h)
		spinner_color, spinner_alpha = tn_palette.black, tn_palette.alpha_black
	end
	ass_new(ass, tn_osc.position.x, tn_osc.thumbnail.top + tn_osc.thumbnail.h * 0.5, 5, tn_style.spinner .. (tn_style_format.spinner2):format(spinner_color, spinner_alpha, tn_osc.background.rotation * seek_percent * 1080), tn_osc.background.text)

	-- Mini Progress Spinner
	if tn_osc.display_progress.current ~= nil and not tn_osc.display_progress.current and tn_osc_stats.percent < 1 then
		ass_new(ass, tn_osc.mini.x, tn_osc.mini.y, 5, tn_style.progress_mini .. (tn_style_format.progress_mini2):format(tn_osc_stats.percent * -360 + 90), tn_osc.mini.text)
	end

	-- Progress Bar
	if tn_osc.display_progress.current then
		local block_w, index = tn_osc_stats.total_expected > 0 and tn_state.width * tn_osc.scale.y / tn_osc_stats.total_expected or 0, 0
		if tn_thumbnails_indexed and block_w > 0 then
			-- Loading bar
			ass_new(ass, tn_osc.thumbnail.left, tn_osc.progress.top, 7, tn_style.progress_block)
			ass:draw_start()
			for time_index, status in pairs(tn_thumbnails_indexed) do
				index = floor(time_index / tn_state.delta) + 1
				if index ~= closest_index and not tn_thumbnails_ready[time_index] and index <= tn_osc_stats.total_expected and draw_progress[status] ~= nil then
					draw_progress[status](ass, index, block_w, tn_osc.progress.h)
				end
			end
			ass:draw_stop()

			if closest_index and closest_index <= tn_osc_stats.total_expected then
				ass_new(ass, tn_osc.thumbnail.left, tn_osc.progress.top, 7, tn_style.closest_index)
				ass_rect(ass, (closest_index - 1) * block_w, 0, closest_index * block_w, tn_osc.progress.h)
			end
		end

		-- Text: Timer
		ass_new(ass, tn_osc.thumbnail.left + 3 * tn_osc.osc_scale.y, tn_osc.progress.mid, 4, tn_style.progress_text, (tn_style_format.text_timer):format(tn_osc_stats.timer))

		-- Text: Number or Index of Thumbnail
		local temp = tn_osc_stats.percent < 1 and tn_osc_stats.ready or closest_index
		local processing = tn_osc_stats.processing > 0 and (tn_style_format.text_progress2):format(tn_osc_stats.processing) or ""
		ass_new(ass, tn_osc.position.x, tn_osc.progress.mid, 5, tn_style.progress_text, (tn_style_format.text_progress):format(temp and temp or 0, tn_osc_stats.total_expected) .. processing)

		-- Text: Percentage
		ass_new(ass, tn_osc.thumbnail.right - 3 * tn_osc.osc_scale.y, tn_osc.progress.mid, 6, tn_style.progress_text, (tn_style_format.text_percent):format(min(100, tn_osc_stats.percent * 100)))
	end
end

---------------
-- Listeners --
---------------

mp.register_script_message(message.osc.reset, function()
	hide_thumbnail()
	reset_all()
end)

local text_progress_format = { two_digits = "%.2d/%.2d", three_digits = "%.3d/%.3d" }

mp.register_script_message(message.osc.update, function(json)
	local new_data = parse_json(json)
	if not new_data then return end
	if new_data.state then
		tn_state = new_data.state
		if tn_state.is_rotated then tn_state.width, tn_state.height = tn_state.height, tn_state.width end
		draw_cmd.w = tn_state.width
		draw_cmd.h = tn_state.height
		draw_cmd.stride = tn_state.width * 4
	end
	if new_data.osc_options then tn_osc_options = new_data.osc_options end
	if new_data.osc_stats then
		tn_osc_stats = new_data.osc_stats
		if tn_osc_options and tn_osc_options.show_progress then
			if	 tn_osc_options.show_progress == 0 then tn_osc.display_progress.current = false
			elseif tn_osc_options.show_progress == 1 then tn_osc.display_progress.current = tn_osc_stats.percent < 1
			else										  tn_osc.display_progress.current = true end
		end
		tn_style_format.text_progress = tn_osc_stats.total > 99 and text_progress_format.three_digits or text_progress_format.two_digits
		if tn_osc_stats.percent >= 1 then mp.command_native({"script-message", message.osc.finish}) end
	end
	if new_data.thumbnails and tn_state then
		local index, ready
		for time_string, status in pairs(new_data.thumbnails) do
			index, ready = tonumber(time_string), (status == message.ready)
			tn_thumbnails_indexed[index] = ready and join_paths(tn_state.cache_dir, time_string) .. tn_state.cache_extension or status
			tn_thumbnails_ready[index]   = ready
		end
	end
	request_tick()
end)

mp.register_script_message(message.debug, function()
	msg.info("Thumbnailer OSC Internal States:")
	msg.info("tn_state:", tn_state and utils.to_string(tn_state) or "nil")
	msg.info("tn_thumbnails_indexed:", tn_thumbnails_indexed and utils.to_string(tn_thumbnails_indexed) or "nil")
	msg.info("tn_thumbnails_ready:", tn_thumbnails_ready and utils.to_string(tn_thumbnails_ready) or "nil")
	msg.info("tn_osc_options:", tn_osc_options and utils.to_string(tn_osc_options) or "nil")
	msg.info("tn_osc_stats:", tn_osc_stats and utils.to_string(tn_osc_stats) or "nil")
	msg.info("tn_osc:", tn_osc and utils.to_string(tn_osc) or "nil")
end)

-------------
-- tog4in1 --
-------------

--https://github.com/mpv-player/mpv/issues/3201#issuecomment-2016505146

local saveParamsFile = mp.command_native({"expand-path", "~~/saveparams.ini"})
local savefile

local function save_file()
	if not user_opts.saveFile then return end
	savefile = io.open(saveParamsFile, "w+")

	savefile:write(
		"showThumbfast="			.. utils.to_string(user_opts.showThumbfast) .. "\n"..
		"showTooltip="				.. utils.to_string(user_opts.showTooltip) .. "\n"..
		"showChapters="				.. utils.to_string(user_opts.showChapters) .. "\n"..
		"showTitle="				.. utils.to_string(user_opts.showTitle) .. "\n"..
		"showIcons="				.. utils.to_string(user_opts.showIcons) .. "\n"..
		"oscMode="					.. user_opts.oscMode .. "\n"..
		"seekbarColorIndex="	  	.. utils.to_string(user_opts.seekbarColorIndex) .. "\n"..
		"seekbarHeight="		  	.. utils.to_string(user_opts.seekbarHeight) .. "\n"..
		"modernTog="			  	.. utils.to_string(user_opts.modernTog) .. "\n"..
		"minimalUI="			  	.. utils.to_string(user_opts.minimalUI) .. "\n"..
		"hidetimeout="				.. utils.to_string(user_opts.hidetimeout) .. "\n"..
		"fadeduration="				.. utils.to_string(user_opts.fadeduration) .. "\n"..
		"hidetimeoutMouseMove="		.. utils.to_string(user_opts.hidetimeoutMouseMove) .. "\n"..
		"fadedurationMouseMove="	.. utils.to_string(user_opts.fadedurationMouseMove) .. "\n"..
		"volume="					.. mp.get_property_native("volume") .. "\n"..
		"windowcontrols_title="		.. utils.to_string(user_opts.windowcontrols_title) .. "\n" ..
		"timetotal="				.. utils.to_string(user_opts.timetotal) .. "\n" ..
		"ontop="					.. mp.get_property("ontop")  .. "\n" ..
		"onTopWhilePlaying="		.. utils.to_string(user_opts.onTopWhilePlaying) .. "\n"
	)
	savefile:close()
end

local function load_file()

	local loadfile = io.open(saveParamsFile, "r")
	if loadfile then
		local state_data = loadfile:read("*all")
		loadfile:close()

		local modernTog = state_data:match("modernTog=(%a+)")
		if modernTog then
			user_opts.modernTog = true
			if modernTog == "false" then
				user_opts.modernTog = false
			end
		end

		local minimalUI = state_data:match("minimalUI=(%a+)")
		if minimalUI then
			user_opts.minimalUI = true
			if minimalUI == "false" then
				user_opts.minimalUI = false
			end
		end

		local showThumbfast = state_data:match("showThumbfast=(%a+)")
		if showThumbfast then
			user_opts.showThumbfast = true
			if showThumbfast == "false" then
				user_opts.showThumbfast = false
			end
		end

		local showTooltip = state_data:match("showTooltip=(%a+)")
		if showTooltip then
			user_opts.showTooltip = true
			if showTooltip == "false" then
				user_opts.showTooltip = false
			end
		end

		local showChapters = state_data:match("showChapters=(%a+)")
		if showChapters then
			user_opts.showChapters = true
			if showChapters == "false" then
				user_opts.showChapters = false
			end
		end

		local showTitle = state_data:match("showTitle=(%a+)")
		if showTitle then
			user_opts.showTitle = true
			if showTitle == "false" then
				user_opts.showTitle = false
			end
		end

		local showIcons = state_data:match("showIcons=(%a+)")
		if showIcons then
			user_opts.showIcons = true
			if showIcons == "false" then
				user_opts.showIcons = false
			end
		end

		local oscMode = state_data:match("oscMode=(%a+)")
		if oscMode then
			user_opts.oscMode = oscMode
		end

		local seekbarColorIndex = state_data:match("seekbarColorIndex=(%d+)")
		if seekbarColorIndex then
			user_opts.seekbarColorIndex = tonumber(seekbarColorIndex)
		end

		local seekbarHeight = state_data:match("seekbarHeight=(%d+)")
		if seekbarHeight then
			user_opts.seekbarHeight = tonumber(seekbarHeight)
		end

		local hidetimeout = state_data:match("hidetimeout=(%d+)")
		if hidetimeout then
			user_opts.hidetimeout = tonumber(hidetimeout)
		end

		local fadeduration = state_data:match("fadeduration=(%d+)")
		if fadeduration then
			user_opts.fadeduration = tonumber(fadeduration)
		end

		local hidetimeoutMouseMove = state_data:match("hidetimeoutMouseMove=(%d+)")
		if hidetimeoutMouseMove then
			user_opts.hidetimeoutMouseMove = tonumber(hidetimeoutMouseMove)
		end

		local fadedurationMouseMove = state_data:match("fadedurationMouseMove=(%d+)")
		if fadedurationMouseMove then
			user_opts.fadedurationMouseMove = tonumber(fadedurationMouseMove)
		end

		local volume = state_data:match("volume=(%d+)")
		if volume then
			mp.set_property("volume", tonumber(volume))
		end

		local windowcontrols_title = state_data:match("windowcontrols_title=(%a+)")
		if windowcontrols_title then
			user_opts.windowcontrols_title = true
			if windowcontrols_title == "false" then
				user_opts.windowcontrols_title = false
			end
		end

		local timetotal = state_data:match("timetotal=(%a+)")
		if timetotal then
			user_opts.timetotal = true
			if timetotal == "false" then
				user_opts.timetotal = false
			end
		end

		local ontop = state_data:match("ontop=(%a+)")
		if ontop then
			mp.set_property("ontop",ontop)
		end

		local onTopWhilePlaying = state_data:match("onTopWhilePlaying=(%a+)")
		if onTopWhilePlaying then
			user_opts.onTopWhilePlaying = true
			if onTopWhilePlaying == "false" then
				user_opts.onTopWhilePlaying = false
			end
		end
	end
end

-- Load params file at startup
if user_opts.saveFile then
	load_file()
end

-- create style
function createStyle(blur, bord, color1, color2, font, icon)
	local style =  "{\\blur"..blur.."\\bord"..bord.."\\1c&H" .. color1 .. "&\\3c&H" .. color2 .. "&"
	if font
	then
		style = style.."\\fs"..font.."\\fn"..icon
	end
	return style.."}"
end
 
-----------------
-- modernx.lua --
-----------------

local osc_param = { -- calculated by osc_init()
	playresy = 0,
	playresx = 0,
	display_aspect = 1,
	unscaled_y = 0,
	areas = {},
}

-- alignments

-- 1 > from left, up
-- 2 > from center, up
-- 3 > from right, up

-- 4 > from left, center
-- 5 > from center, center
-- 6 > from right, center

-- 7 > from left, down
-- 8 > from center, down
-- 9 > from right, down

local alignments = {
  [1] = function () return x, y-h, x+w, y end,
  [2] = function () return x-(w/2), y-h, x+(w/2), y end,
  [3] = function () return x-w, y-h, x, y end,

  [4] = function () return x, y-(h/2), x+w, y+(h/2) end,
  [5] = function () return x-(w/2), y-(h/2), x+(w/2), y+(h/2) end,
  [6] = function () return x-w, y-(h/2), x, y+(h/2) end,

  [7] = function () return x, y, x+w, y+h end,
  [8] = function () return x-(w/2), y, x+(w/2), y+h end,
  [9] = function () return x-w, y, x, y+h end,
}

-- osc colors : seekbar / hover (BGR > ABCDEF becomes EFCDAB)
local osc_palette = {
	[1] 	= "7f7f00", -- cyan
	[2]		= "E39C42", -- blue
	[3]		= "23a08e", -- green apple
	[4]		= "859b2f", -- green
	[5]		= "38b3ce", -- yellow past
	[6]		= "1190cf", -- orange past
	[7]		= "0261ec", -- orange
	[8]		= "3333ff", -- red past
	[9]		= "cc66ff", -- pink
	[10]	= "e9e9e9", -- white
}

-- osc colors : background / buttons (GBR)
local black = "000000"	-- OSC background color
local white = "E9E9E9"	-- Play / time left color
local grey 	= "808080"	-- Other buttons color (grey)
if user_opts.UIAllWhite then
	grey = white					-- Other button color (white)
	user_opts.alphaWinCtrl = 0		-- Window control buttons max opacity (white)
end

-- osc styles - params : blur, bord, color1, color2, font size, icon
local osc_styles = {
	transBg				= createStyle(75, 100, black, black, nil, nil),
	transBgMini			= createStyle(75, 75, black, black, nil, nil),
	transBgPot			= createStyle(0, 70, black, black, nil, nil),
	transBgPotMini		= createStyle(0, 30, black, black, nil, nil),
	seekbarBg			= createStyle(0, 0, white, white, nil, nil),
	seekbarFg			= createStyle(0, 0, osc_palette[user_opts.seekbarColorIndex], white, nil, nil),
	elementHover		= createStyle(0, 0, osc_palette[user_opts.seekbarColorIndex], black, nil, nil),

	bigButtons			= createStyle(0, 0, white, white, 30, ""),
	bigButtonsPot		= createStyle(0, 0, white, white, 24, ""),
	miniButtonsPot		= createStyle(0, 0, white, white, 19, ""),
	mediumButtons		= createStyle(0, 0, grey, white, 16, ""),
	mediumButtonsBig	= createStyle(0, 0, grey, white, 24, ""),
	speedButton			= createStyle(0, 0, grey, white, 11, ""),
	togIcon				= createStyle(0, 0, grey, white, 16, ""),
	togIconBig			= createStyle(0, 0, grey, white, 20, ""),

	timecodeL			= createStyle(0, 0, white, white, 13, user_opts.oscFont),
	timecodeR			= createStyle(0, 0, grey, white, 13, user_opts.oscFont),
	titlePotMini		= createStyle(0, 0, grey, white, 14, user_opts.oscFont),
	tooltip				= createStyle(0, 0, white, black, 10, user_opts.oscFont),
	vidTitle			= createStyle(0, 0, white, white, 12, user_opts.oscFont),

	wcButtons			= createStyle(0, 0, white, white, 15, ""),
	wcTitle				= createStyle(0, 0, white, white, 14, user_opts.oscFont),
	wcBar				= createStyle(0, 0, black, black, nil, nil),
	
	elementDown = "{\\1c&H" .. black .. "&}",
}

local osc_icons = {
	close			= "󰛉",
	minimize		= "󰍵",
	restore			= "󱅁",
	maximize		= "󱇿",

	play			= "󰼛",
	pause			= "󰏤",
	skipback		= "󱇹",
	skipforward		= "󱇸",
	chapter_prev	= "󰜊",
	chapter_next	= "󰛒",
	playlist_prev	= "󰼨",
	playlist_next	= "󰼧",

	audio			= "󰲹",
	subtitle		= "󱅰",
	ontop			= "󰌨",
	onTopWP			= "󰹍",
	loop			= "󰑖",
	loop1			= "󰑘",
	loopPL			= "󰙝",
	info			= "",
	tooltipOn		= "",
	tooltipOff		= "",
	thumb			= "󱤇",
	oscmode			= "󰍾",
	oscmodeOnPause	= "󰍽",
	oscmodeAlways	= "󱕒",
	switch			= "󰯍",
	fullscreen		= "󰊓",
	fullscreen_exit	= "󰊔",

	volume_mute		= "󰝟",
	volume			= "󰕾",
}

-- internal states, do not touch
local state = {
	showtime,								-- time of last invocation (last mouse move)
	osc_visible = false,					-- OSC visible
	anistart,								-- time when the animation started
	anitype,								-- current type of animation
	animation,								-- current animation alpha
	mouse_down_counter = 0,					-- used for softrepeat
	active_element = nil,					-- nil = none, 0 = background, 1+ = see elements[]
	active_event_source = nil,				-- the "button" that issued the current event
	mp_screen_sizeX, mp_screen_sizeY,		-- last screen-resolution, to detect resolution changes to issue reINITs
	initREQ = false,						-- is a re-init request pending?
	marginsREQ = false,						-- is a margins update pending?
	last_mouseX, last_mouseY,				-- last mouse position, to detect significant mouse movement
	mouse_in_window = false,
	message_text,
	message_hide_timer,
	fullscreen = false,
	tick_timer = nil,
	tick_last_time = 0,						-- when the last tick() was run
	hide_timer = nil,
	cache_state = nil,
	idle = false,
	enabled = true,
	input_enabled = true,
	showhide_enabled = false,
	dmx_cache = 0,
	border = true,
	maximized = false,
	osd = mp.create_osd_overlay("ass-events"),
	chapter_list = {},						-- sorted by time
	lastvisibility = user_opts.visibility,	-- save last visibility on pause if showonpause
}

local thumbfast = {
	width = 0,
	height = 0,
	disabled = true,
	available = false
}

local tick_delay = 1 / 60

-- Automatically disable OSC
local builtin_osc_enabled = mp.get_property_native("osc")
if builtin_osc_enabled then
	mp.set_property_native("osc", false)
end

--
-- Helper functions
--

function kill_animation()
	state.anistart = nil
	state.animation = nil
	state.anitype =  nil
end

function set_osd(res_x, res_y, text)
	if state.osd.res_x == res_x and
	   state.osd.res_y == res_y and
	   state.osd.data == text then
		return
	end
	state.osd.res_x = res_x
	state.osd.res_y = res_y
	state.osd.data = text
	state.osd.z = 1000
	state.osd:update()
end

-- scale factor for translating between real and virtual ASS coordinates
function get_virt_scale_factor()
	local w, h = mp.get_osd_size()
	if w <= 0 or h <= 0 then
		return 0, 0
	end
	return osc_param.playresx / w, osc_param.playresy / h
end

-- return mouse position in virtual ASS coordinates (playresx/y)
function get_virt_mouse_pos()
	if state.mouse_in_window then
		local sx, sy = get_virt_scale_factor()
		local x, y = mp.get_mouse_pos()
		return x * sx, y * sy
	else
		return -1, -1
	end
end

function set_virt_mouse_area(x0, y0, x1, y1, name)
	local sx, sy = get_virt_scale_factor()
	mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name)
end

function scale_value(x0, x1, y0, y1, val)
	local m = (y1 - y0) / (x1 - x0)
	local b = y0 - (m * x0)
	return (m * val) + b
end

-- returns hitbox spanning coordinates (top left, bottom right corner) according to alignment

-- 1 > from left, up
-- 2 > from center, up
-- 3 > from right, up

-- 4 > from left, center
-- 5 > from center, center
-- 6 > from right, center

-- 7 > from left, down
-- 8 > from center, down
-- 9 > from right, down

function get_hitbox_coords(x, y, an, w, h)

	local alignments = {
	  [1] = function () return x, y-h, x+w, y end,
	  [2] = function () return x-(w/2), y-h, x+(w/2), y end,
	  [3] = function () return x-w, y-h, x, y end,

	  [4] = function () return x, y-(h/2), x+w, y+(h/2) end,
	  [5] = function () return x-(w/2), y-(h/2), x+(w/2), y+(h/2) end,
	  [6] = function () return x-w, y-(h/2), x, y+(h/2) end,

	  [7] = function () return x, y, x+w, y+h end,
	  [8] = function () return x-(w/2), y, x+(w/2), y+h end,
	  [9] = function () return x-w, y, x, y+h end,
	}

	return alignments[an]()
end

function get_hitbox_coords_geo(geometry)
	return get_hitbox_coords(geometry.x, geometry.y, geometry.an,
		geometry.w, geometry.h)
end

function get_element_hitbox(element)
	return element.hitbox.x1, element.hitbox.y1,
		element.hitbox.x2, element.hitbox.y2
end

function mouse_hit(element)
	return mouse_hit_coords(get_element_hitbox(element))
end

function mouse_hit_coords(bX1, bY1, bX2, bY2)
	local mX, mY = get_virt_mouse_pos()
	return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2)
end

function limit_range(min, max, val)
	if val > max then
		val = max
	elseif val < min then
		val = min
	end
	return val
end

-- translate value into element coordinates
function get_slider_ele_pos_for(element, val)

	local ele_pos = scale_value(
		element.slider.min.value, element.slider.max.value,
		element.slider.min.ele_pos, element.slider.max.ele_pos,
		val)

	return limit_range(
		element.slider.min.ele_pos, element.slider.max.ele_pos,
		ele_pos)
end

-- translates global (mouse) coordinates to value
function get_slider_value_at(element, glob_pos)

	local val = scale_value(
		element.slider.min.glob_pos, element.slider.max.glob_pos,
		element.slider.min.value, element.slider.max.value,
		glob_pos)

	return limit_range(
		element.slider.min.value, element.slider.max.value,
		val)
end

-- get value at current mouse position
function get_slider_value(element)
	return get_slider_value_at(element, get_virt_mouse_pos())
end

-- multiplies two alpha values, formular can probably be improved
function mult_alpha(alphaA, alphaB)
	return 255 - (((1-(alphaA/255)) * (1-(alphaB/255))) * 255)
end

function add_area(name, x1, y1, x2, y2)
	-- create area if needed
	if (osc_param.areas[name] == nil) then
		osc_param.areas[name] = {}
	end
	table.insert(osc_param.areas[name], {x1=x1, y1=y1, x2=x2, y2=y2})
end

function ass_append_alpha(ass, alpha, modifier)
	local ar = {}

	for ai, av in pairs(alpha) do
		av = mult_alpha(av, modifier)
		if state.animation then
			av = mult_alpha(av, state.animation)
		end
		ar[ai] = av
	end

	ass:append(string.format("{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}",
			   ar[1], ar[2], ar[3], ar[4]))
end

function ass_draw_cir_cw(ass, x, y, r)
	ass:round_rect_cw(x-r, y-r, x+r, y+r, r)
end

function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
	if hexagon then
		ass:hexagon_cw(x0, y0, x1, y1, r1, r2)
	else
		ass:round_rect_cw(x0, y0, x1, y1, r1, r2)
	end
end

function ass_draw_rr_h_ccw(ass, x0, y0, x1, y1, r1, hexagon, r2)
	if hexagon then
		ass:hexagon_ccw(x0, y0, x1, y1, r1, r2)
	else
		ass:round_rect_ccw(x0, y0, x1, y1, r1, r2)
	end
end

function round(number, decimals)
	local power = 10^(decimals or 1)
	return math.floor(number * power + 0.5) / power
end

--
-- Tracklist Management
--

local nicetypes = {video = "Video", audio = "Audio", sub = "Subtitle"}

-- updates the OSC internal playlists, should be run each time the track-layout changes
function update_tracklist()
	local tracktable = mp.get_property_native("track-list", {})

	-- by osc_id
	tracks_osc = {}
	tracks_osc.video, tracks_osc.audio, tracks_osc.sub = {}, {}, {}
	-- by mpv_id
	tracks_mpv = {}
	tracks_mpv.video, tracks_mpv.audio, tracks_mpv.sub = {}, {}, {}
	for n = 1, #tracktable do
		if not (tracktable[n].type == "unknown") then
			local type = tracktable[n].type
			local mpv_id = tonumber(tracktable[n].id)

			-- by osc_id
			table.insert(tracks_osc[type], tracktable[n])

			-- by mpv_id
			tracks_mpv[type][mpv_id] = tracktable[n]
			tracks_mpv[type][mpv_id].osc_id = #tracks_osc[type]
		end
	end
end

-- return a nice list of tracks of the given type (video, audio, sub)
function get_tracklist(type)
	local msg = "Available " .. nicetypes[type] .. " Tracks: "
	if not tracks_osc or #tracks_osc[type] == 0 then
		msg = msg .. "none"
	else
		for n = 1, #tracks_osc[type] do
			local track = tracks_osc[type][n]
			local lang, title, selected, codec = "unknown", "", "○", ""
			if not(track.lang == nil) then lang = track.lang end
			if not(track.title == nil) then title = track.title end
			if not(track.codec == nil) then codec = track.codec end
			if (track.id == tonumber(mp.get_property(type))) then
				selected = "●"
			end
			msg = msg.."\n"..selected.." "..n.." : ["..lang.."] "..codec.." "..title
		end
	end
	return msg
end

-- relatively change the track of given <type> by <next> tracks
	--(+1 -> next, -1 -> previous)
function set_track(type, next)
	local current_track_mpv, current_track_osc
	if (mp.get_property(type) == "no") then
		current_track_osc = 0
	else
		current_track_mpv = tonumber(mp.get_property(type))
		current_track_osc = tracks_mpv[type][current_track_mpv].osc_id
	end
	local new_track_osc = (current_track_osc + next) % (#tracks_osc[type] + 1)
	local new_track_mpv
	if new_track_osc == 0 then
		new_track_mpv = "no"
	else
		new_track_mpv = tracks_osc[type][new_track_osc].id
	end

	mp.commandv("set", type, new_track_mpv)
end

function get_track_name(type)
	if type == "sub" then
		local msg = "Subtitle : Off"
		if not (get_track("sub") == 0) then
			msg = "Subtitle ["..get_track("sub").."∕"..#tracks_osc.sub.."] "
			local lang = mp.get_property("current-tracks/sub/lang") or "N/A"
			local title = mp.get_property("current-tracks/sub/title") or ""
			msg = msg .. "(" .. lang .. ")" .. " " .. title
		end
		if not user_opts.showTooltip then
			mp.osd_message(utils.to_string(msg))
		end
		return msg
	else
		local msg = "Audio :  Off"
		if not (get_track("audio") == 0) then
			msg = "Audio ["..get_track("audio").."∕"..#tracks_osc.audio.."] "
			local lang = mp.get_property("current-tracks/audio/lang") or "N/A"
			local title = mp.get_property("current-tracks/audio/title") or ""
			msg = msg .. "(" .. lang .. ")" .. " " .. title
		end
		if not user_opts.showTooltip then
			mp.osd_message(utils.to_string(msg))
		end
		return msg
	end
end

-- get the currently selected track of <type>, OSC-style counted
function get_track(type)
	local track = mp.get_property(type)
	if track ~= "no" and track ~= nil then
		local tr = tracks_mpv[type][tonumber(track)]
		if tr then
			return tr.osc_id
		end
	end
	return 0
end

-- WindowControl helpers
function window_controls_enabled()
	val = user_opts.windowcontrols
	if val == "auto" then
		return not state.border
	elseif val == "fullscreen_only" then
		return (not state.border) or state.fullscreen
	else
		return val ~= "no"
	end
end

--
-- Element Management
--

local elements = {}

function prepare_elements()

	-- remove elements without layout or invisble
	local elements2 = {}
	for n, element in pairs(elements) do
		if not (element.layout == nil) and (element.visible) then
			table.insert(elements2, element)
		end
	end
	elements = elements2

	function elem_compare (a, b)
		return a.layout.layer < b.layout.layer
	end

	table.sort(elements, elem_compare)

	for _,element in pairs(elements) do

		local elem_geo = element.layout.geometry

		-- Calculate the hitbox
		local bX1, bY1, bX2, bY2 = get_hitbox_coords_geo(elem_geo)
		element.hitbox = {x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2}

		local style_ass = assdraw.ass_new()

		-- prepare static elements
		style_ass:append("{}") -- hack to troll new_event into inserting a \n
		style_ass:new_event()
		style_ass:pos(elem_geo.x, elem_geo.y)
		style_ass:an(elem_geo.an)
		style_ass:append(element.layout.style)

		element.style_ass = style_ass

		local static_ass = assdraw.ass_new()

		if (element.type == "box") then
			--draw box
			static_ass:draw_start()
			ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h,
							 element.layout.box.radius, element.layout.box.hexagon)
			static_ass:draw_stop()

		elseif (element.type == "slider") then
			--draw static slider parts
			local slider_lo = element.layout.slider
			-- calculate positions of min and max points
			element.slider.min.ele_pos = user_opts.seekbarhandlesize * elem_geo.h / 2
			element.slider.max.ele_pos = elem_geo.w - element.slider.min.ele_pos
			element.slider.min.glob_pos = element.hitbox.x1 + element.slider.min.ele_pos
			element.slider.max.glob_pos = element.hitbox.x1 + element.slider.max.ele_pos

			static_ass:draw_start()
			-- a hack which prepares the whole slider area to allow center placements such like an=5
			static_ass:rect_cw(0, 0, elem_geo.w, elem_geo.h)
			static_ass:rect_ccw(0, 0, elem_geo.w, elem_geo.h)
			-- marker nibbles
			if not (element.slider.markerF == nil) and (slider_lo.gap > 0) then
				local markers = element.slider.markerF()
				for _,marker in pairs(markers) do
					if (marker >= element.slider.min.value) and
						(marker <= element.slider.max.value) then

						local s = get_slider_ele_pos_for(element, marker)

						if (slider_lo.gap > 5) then -- draw triangles

							--top
							if (slider_lo.nibbles_top) then
								static_ass:move_to(s - 1, slider_lo.gap - 5)
								static_ass:line_to(s + 1, slider_lo.gap - 5)
								static_ass:line_to(s, slider_lo.gap - 1)
							end

							--bottom
							if (slider_lo.nibbles_bottom) then
								static_ass:move_to(s - 1, elem_geo.h - slider_lo.gap + 5)
								static_ass:line_to(s, elem_geo.h - slider_lo.gap + 1)
								static_ass:line_to(s + 1, elem_geo.h - slider_lo.gap + 5)
							end

						else -- draw 2x1px nibbles

							--top
							if (slider_lo.nibbles_top) then
								static_ass:rect_cw(s - 1, 0, s + 1, slider_lo.gap);
							end

							--bottom
							if (slider_lo.nibbles_bottom) then
								static_ass:rect_cw(s - 1,
									elem_geo.h - slider_lo.gap,
									s + 1, elem_geo.h);
							end
						end
					end
				end
			end
		end

		element.static_ass = static_ass

		-- if the element is supposed to be disabled,
		-- style it accordingly and kill the eventresponders
		if not (element.enabled) then
			element.layout.alpha[1] = user_opts.alphaUntoggledButton
			element.eventresponder = nil
		end

		-- gray out the element if it is toggled off
		if (element.off) then
			element.layout.alpha[1] = user_opts.alphaUntoggledButton
		end
	end
end

--
-- Element Rendering
--

-- returns nil or a chapter element from the native property chapter-list
function get_chapter(possec)
	local cl = state.chapter_list  -- sorted, get latest before possec, if any

	for n=#cl,1,-1 do
		if possec >= cl[n].time then
			return cl[n]
		end
	end
end

function render_elements(master_ass)

	-- when the slider is dragged or hovered and we have a target chapter name
	-- then we use it instead of the normal title. we calculate it before the
	-- render iterations because the title may be rendered before the slider.
	state.forced_title = nil
	local se, ae = state.slider_element, elements[state.active_element]
	if user_opts.chapter_fmt ~= "no" and se and (ae == se or (not ae and mouse_hit(se)))
		and user_opts.showChapters then
		local dur = mp.get_property_number("duration", 0)
		if dur > 0 then
			local possec = get_slider_value(se) * dur / 100 -- of mouse pos
			local ch = get_chapter(possec)
			if ch and ch.title and ch.title ~= "" then
				state.forced_title = string.format(user_opts.chapter_fmt, ch.title)
			end
		end
	end

	for n=1, #elements do
		local element = elements[n]

		local style_ass = assdraw.ass_new()
		style_ass:merge(element.style_ass)
		ass_append_alpha(style_ass, element.layout.alpha, 0)

		if element.eventresponder and (state.active_element == n) then

			-- run render event functions
			if not (element.eventresponder.render == nil) then
				element.eventresponder.render(element)
			end

			if mouse_hit(element) then
				-- mouse down styling
				if (element.styledown) then
					style_ass:append(osc_styles.elementDown)
				end

				if (element.softrepeat) and (state.mouse_down_counter >= 15
					and state.mouse_down_counter % 5 == 0) then

					element.eventresponder[state.active_event_source.."_down"](element)
				end
				state.mouse_down_counter = state.mouse_down_counter + 1
			end

		end

		local elem_ass = assdraw.ass_new()

		elem_ass:merge(style_ass)

		if not (element.type == "button") then
			elem_ass:merge(element.static_ass)
		end

		if (element.type == "slider") then

			local slider_lo = element.layout.slider
			local elem_geo = element.layout.geometry
			local s_min = element.slider.min.value
			local s_max = element.slider.max.value

			-- draw pos marker
			local pos = element.slider.posF()
			local seekRanges = element.slider.seekRangesF()
			local rh = user_opts.seekbarhandlesize * elem_geo.h / 2 -- Handle radius
			local xp

			if pos then
				xp = get_slider_ele_pos_for(element, pos)
				ass_draw_cir_cw(elem_ass, xp, elem_geo.h/2, rh)
				elem_ass:rect_cw(0, slider_lo.gap, xp, elem_geo.h - slider_lo.gap)
			end

			if seekRanges then
				elem_ass:draw_stop()
				elem_ass:merge(element.style_ass)
				ass_append_alpha(elem_ass, element.layout.alpha, user_opts.seekrangealpha)
				elem_ass:merge(element.static_ass)

				for _,range in pairs(seekRanges) do
					local pstart = get_slider_ele_pos_for(element, range["start"])
					local pend = get_slider_ele_pos_for(element, range["end"])
					elem_ass:rect_cw(pstart - rh, slider_lo.gap, pend + rh, elem_geo.h - slider_lo.gap)
				end
			end

			elem_ass:draw_stop()

			-- add tooltip
			if not (element.slider.tooltipF == nil) then

				if mouse_hit(element) then
					local sliderpos = get_slider_value(element)
					local tooltiplabel = element.slider.tooltipF(sliderpos)

					local an = slider_lo.tooltip_an

					local ty

					if (an == 2) then
						ty = element.hitbox.y1
					else
						ty = element.hitbox.y1 + elem_geo.h/2
					end

					local tx = get_virt_mouse_pos()
					if (slider_lo.adjust_tooltip) then
						if (an == 2) then
							if (sliderpos < (s_min + 3)) then
								an = an - 1
							elseif (sliderpos > (s_max - 3)) then
								an = an + 1
							end
						elseif (sliderpos > (s_max-s_min)/2) then
							an = an + 1
							tx = tx - 5
						else
							an = an - 1
							tx = tx + 10
						end
					end

					-- tooltip label
					elem_ass:new_event()
					elem_ass:pos(tx, ty)
					elem_ass:an(an)
					elem_ass:append(slider_lo.tooltip_style)
					ass_append_alpha(elem_ass, slider_lo.alpha, 0)
					elem_ass:append(tooltiplabel)

					-- thumbnail
					if thumbfast.available and user_opts.showThumbfast then
						local osd_w = mp.get_property_number("osd-width")
						if osd_w and not thumbfast.disabled then
							local r_w, r_h = get_virt_scale_factor()

							local thumbPad = 1
							local thumbMarginX = 18 / r_w
							local thumbMarginY = 15
							local tooltipBgColor = "000000"
							local tooltipBgAlpha = 80
							local thumbX = math.min(osd_w - thumbfast.width - thumbMarginX, math.max(thumbMarginX, tx / r_w - thumbfast.width / 2))
							local thumbY = ((ty - thumbMarginY) / r_h - thumbfast.height)

							elem_ass:new_event()
							elem_ass:pos(thumbX * r_w, ty - thumbMarginY - thumbfast.height * r_h)
							elem_ass:an(7)
							elem_ass:append(("{\\bord0\\1c&H%s&\\1a&H%X&}"):format(tooltipBgColor, tooltipBgAlpha))
							elem_ass:draw_start()
							elem_ass:rect_cw(-thumbPad * r_h, -thumbPad * r_h, (thumbfast.width + thumbPad) * r_w, (thumbfast.height + thumbPad) * r_h)
							elem_ass:draw_stop()

							mp.commandv("script-message-to", "thumbfast", "thumb",
								mp.get_property_number("duration", 0) * (sliderpos / 100),
								thumbX,
								thumbY
							)
						end
					else
						display_tn_osc(ty, sliderpos, elem_ass)
					end
				else
					if thumbfast.available then
						mp.commandv("script-message-to", "thumbfast", "clear")
					else
						hide_thumbnail()
					end
				end
			end

		elseif (element.type == "button") then

			local buttontext

			if type(element.content) == "function" then
				buttontext = element.content() -- function objects
			elseif not (element.content == nil) then
				buttontext = element.content -- text objects
			end

			local maxchars = element.layout.button.maxchars
			if not (maxchars == nil) and (#buttontext > maxchars) then
				local max_ratio = 1.25  -- up to 25% more chars while shrinking
				local limit = math.max(0, math.floor(maxchars * max_ratio) - 3)
				if (#buttontext > limit) then
					while (#buttontext > limit) do
						buttontext = buttontext:gsub(".[\128-\191]*$", "")
					end
					buttontext = buttontext .. "..."
				end
				local _, nchars2 = buttontext:gsub(".[\128-\191]*", "")
				local stretch = (maxchars/#buttontext)*100
				buttontext = string.format("{\\fscx%f}",
					(maxchars/#buttontext)*100) .. buttontext
			end

			elem_ass:append(buttontext)

			-- add tooltips
			if not (element.tooltipF == nil) and element.enabled then
				if mouse_hit(element) then
					local tooltiplabel = element.tooltipF
					local an = 1
					local ty = element.hitbox.y1
					local tx = get_virt_mouse_pos()

					if ty < osc_param.playresy / 2 then
						ty = element.hitbox.y2
						an = 7
					end

					-- tooltip label
					if type(element.tooltipF) == "function" then
						tooltiplabel = element.tooltipF()
					else
						tooltiplabel = element.tooltipF
					end
					elem_ass:new_event()
					elem_ass:pos(tx, ty)
					elem_ass:an(an)
					elem_ass:append(element.tooltip_style)
					elem_ass:append(tooltiplabel)
				end
			end

			-- add hover effect
			-- source: https://github.com/Zren/mpvz/issues/13
			local button_lo = element.layout.button
			if mouse_hit(element) and element.hoverable and element.enabled then
				local shadow_ass = assdraw.ass_new()
				shadow_ass:merge(style_ass)
				shadow_ass:append(button_lo.hoverstyle .. buttontext)
				elem_ass:merge(shadow_ass)
			end
		end

		master_ass:merge(elem_ass)
	end
end

--
-- Message display
--

-- pos is 1 based
function limited_list(prop, pos)
	local proplist = mp.get_property_native(prop, {})
	local count = #proplist
	if count == 0 then
		return count, proplist
	end

	local fs = tonumber(mp.get_property("options/osd-font-size"))
	local max = math.ceil(osc_param.unscaled_y*0.75 / fs)
	if max % 2 == 0 then
		max = max - 1
	end
	local delta = math.ceil(max / 2) - 1
	local begi = math.max(math.min(pos - delta, count - max + 1), 1)
	local endi = math.min(begi + max - 1, count)

	local reslist = {}
	for i=begi, endi do
		local item = proplist[i]
		item.current = (i == pos) and true or nil
		table.insert(reslist, item)
	end
	return count, reslist
end

function get_playlist()
	local pos = mp.get_property_number("playlist-pos", 0) + 1
	local count, limlist = limited_list("playlist", pos)
	if count == 0 then
		return "Empty playlist."
	end

	local message = string.format("Playlist [%d/%d]:\n", pos, count)
	for i, v in ipairs(limlist) do
		local title = v.title
		local _, filename = utils.split_path(v.filename)
		if title == nil then
			title = filename
		end
		message = string.format("%s %s %s\n", message, (v.current and "●" or "○"), title)
	end

	return message
end

-- Playlist data at pos delta (osc_tethys)
function getDeltaPlaylistItem(delta)
	local deltaIndex, deltaItem = getDeltaListItem("playlist", "playlist-pos", delta, false)
	if deltaItem == nil then
		return nil
	end
	deltaItem = {
		index = deltaIndex,
		filename = deltaItem.filename,
		title = deltaItem.title,
		label = nil,
	}
	local label = deltaItem.title
	if label == nil then
		local _, filename = utils.split_path(deltaItem.filename)
		label = filename
	end
	deltaItem.label = label
	return deltaItem
end

-- Chapters data at pos delta (osc_tethys)
function getDeltaChapter(delta)
	local deltaIndex, deltaChapter = getDeltaListItem("chapter-list", "chapter", delta, true)
	if deltaChapter == nil then -- Video Done
		return nil
	end
	deltaChapter = {
		index = deltaIndex,
		time = deltaChapter.time,
		title = deltaChapter.title,
		label = nil,
	}
	local label = deltaChapter.title
	if label == nil then
		label = string.format("Chapter %02d", deltaChapter.index)
	end
	deltaChapter.label = label
	return deltaChapter
end

-- (osc_tethys)
function getDeltaListItem(listKey, curKey, delta, clamp)
	local pos = mp.get_property_number(curKey, 0) + 1
	local count, limlist = limited_list(listKey, pos)
	if count == 0 then
		return nil
	end

	local curIndex = -1
	for i, v in ipairs(limlist) do
		if v.current then
			curIndex = i
			break
		end
	end

	local deltaIndex = curIndex + delta
	if curIndex == -1 then
		return nil
	elseif deltaIndex < 1 then
		if clamp then
			deltaIndex = 1
		else
			return nil
		end
	elseif deltaIndex > count then
		if clamp then
			deltaIndex = count
		else
			return nil
		end
	end

	local deltaItem = limlist[deltaIndex]
	return deltaIndex, deltaItem
end

function get_chapterlist()
	local pos = mp.get_property_number("chapter", 0) + 1
	local count, limlist = limited_list("chapter-list", pos)
	if count == 0 then
		return "No chapters."
	end

	local message = string.format("Chapters [%d/%d]:\n", pos, count)
	for i, v in ipairs(limlist) do
		local time = mp.format_time(v.time)
		local title = v.title
		if title == nil then
			title = string.format("Chapter %02d", i)
		end
		message = string.format("%s[%s] %s %s\n", message, time,
			(v.current and "●" or "○"), title)
	end
	return message
end

function show_message(text, duration)

	--print("text: "..text.."   duration: " .. duration)
	if duration == nil then
		duration = tonumber(mp.get_property("options/osd-duration")) / 1000
	elseif not type(duration) == "number" then
		print("duration: " .. duration)
	end

	-- cut the text short, otherwise the following functions
	-- may slow down massively on huge input
	text = string.sub(text, 0, 4000)

	-- replace actual linebreaks with ASS linebreaks
	text = string.gsub(text, "\n", "\\N")
	state.message_text = text

	--state.message_text = mp.command_native({"escape-ass", text})

	if not state.message_hide_timer then
		state.message_hide_timer = mp.add_timeout(0, request_tick)
	end
	state.message_hide_timer:kill()
	state.message_hide_timer.timeout = duration
	state.message_hide_timer:resume()
	request_tick()
end

function render_message(ass)
	if state.message_hide_timer and state.message_hide_timer:is_enabled() and
	   state.message_text
	then
		local _, lines = string.gsub(state.message_text, "\\N", "")

		local fontsize = tonumber(mp.get_property("options/osd-font-size"))
		local outline = tonumber(mp.get_property("options/osd-border-size"))
		local maxlines = math.ceil(osc_param.unscaled_y*0.75 / fontsize)
		local counterscale = osc_param.playresy / osc_param.unscaled_y

		if user_opts.vidscale then
			fontsize = fontsize * counterscale / math.max(1 + math.min(lines/maxlines, 1), 1)
			outline = outline * counterscale / math.max(1 + math.min(lines/maxlines, 1)/2, 1)
		else
			fontsize = fontsize * counterscale / math.max(0.65 + math.min(lines/maxlines, 1), 1)
			outline = outline * counterscale / math.max(0.75 + math.min(lines/maxlines, 1)/2, 1)
		end

		local style = "{\\bord" .. outline .. "\\fs" .. fontsize .. "}"

		ass:new_event()
		ass:append(style .. state.message_text)
	else
		state.message_text = nil
	end
end

--
-- Initialisation and Layout
--

function new_element(name, type)
	elements[name] = {}
	elements[name].type = type
	elements[name].name = name

	-- add default stuff
	elements[name].eventresponder = {}
	elements[name].visible = true
	elements[name].enabled = true
	elements[name].softrepeat = false
	elements[name].styledown = (type == "button")
	elements[name].hoverable = (type == "button")
	elements[name].state = {}

	if (type == "slider") then
		elements[name].slider = {min = {value = 0}, max = {value = 100}}
	end

	return elements[name]
end

function add_layout(name)

	if not (elements[name] == nil) then

		-- new layout
		elements[name].layout = {}

		-- set layout defaults
		elements[name].layout.layer = 50
		elements[name].layout.alpha = {[1] = 0, [2] = 255, [3] = 255, [4] = 255}

		-- If minimalUI no chapters display
		local nibbletop = false
		local nibblebottom = false
		if not user_opts.minimalUI then
			nibbletop = user_opts.showChapters
			nibblebottom = user_opts.showChapters
		end

		osc_styles.elementHover = createStyle(0, 0, osc_palette[user_opts.seekbarColorIndex], black, nil, nil)
	
		if (elements[name].type == "button") then
			elements[name].layout.button = {
				maxchars = nil,
				hoverstyle = osc_styles.elementHover
			}
		elseif (elements[name].type == "slider") then
			-- slider defaults
			elements[name].layout.slider = {
				border = 1,
				gap = 1,
				nibbles_top = nibbletop,
				nibbles_bottom = false,
				adjust_tooltip = true,
				tooltip_style = "",
				tooltip_an = 2,
				alpha = {[1] = 0, [2] = 255, [3] = 88, [4] = 255},
			}
		elseif (elements[name].type == "box") then
			elements[name].layout.box = {radius = 0, hexagon = false}
		end

		return elements[name].layout
	else
		msg.error("Can't add_layout to element \""..name.."\", doesn't exist.")
	end
end

-- Window Controls
function window_controls()

	local wc_geo = {
		x = 0,
		y = user_opts.heightwcShowHidearea,
		an = 1,
		w = osc_param.playresx,
		h = user_opts.heightwcShowHidearea,
	}
	local buttonWH = 24
	local controlbox_w = 100
	local titlebox_w = wc_geo.w - controlbox_w

	-- Default alignment is "right"
	local controlbox_left = wc_geo.w - controlbox_w
	local titlebox_left = wc_geo.x
	local titlebox_right = wc_geo.w - controlbox_w

	add_area("window-controls", get_hitbox_coords(wc_geo.x, wc_geo.y, wc_geo.an, wc_geo.w, wc_geo.h))

	local lo

	-- Background Bar
	new_element("wcbar", "box")
	lo = add_layout("wcbar")
	lo.geometry = wc_geo
	lo.layer = 10
	lo.style = osc_styles.wcBar
	lo.alpha[1] = 255 -- Invisible

	local button_y     = wc_geo.y - (wc_geo.h / 2)
	local first_geo    = {x = controlbox_left + 20, y = button_y, an = 4, w = buttonWH, h = buttonWH}
	local second_geo   = {x = controlbox_left + 50, y = button_y, an = 4, w = buttonWH, h = buttonWH}
	local third_geo    = {x = controlbox_left + 75, y = button_y, an = 4, w = buttonWH, h = buttonWH}

	-- Window control buttons use symbols in the custom mpv osd font
	-- because the official unicode codepoints are sufficiently
	-- exotic that a system might lack an installed font with them,
	-- and libass will complain that they are not present in the
	-- default font, even if another font with them is available.

	-- Minimize: 🗕
	ne = new_element("minimize", "button")
	ne.content = osc_icons.minimize
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("cycle", "window-minimized") end
	lo = add_layout("minimize")
	lo.geometry = first_geo
	lo.style = osc_styles.wcButtons
	lo.alpha[1] = user_opts.alphaWinCtrl

	-- Maximize: 🗖 /🗗
	ne = new_element("maximize", "button")
	if state.maximized or state.fullscreen then
		ne.content = osc_icons.restore
	else
		ne.content = osc_icons.maximize
	end
	ne.eventresponder["mbtn_left_up"] =
		function ()
			if state.fullscreen then
				mp.commandv("cycle", "fullscreen")
			else
				mp.commandv("cycle", "window-maximized")
			end
		end
	lo = add_layout("maximize")
	lo.geometry = second_geo
	lo.style = osc_styles.wcButtons
	lo.alpha[1] = user_opts.alphaWinCtrl

	-- Close: 🗙
	ne = new_element("close", "button")
	ne.content = osc_icons.close
	ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("quit") end
	lo = add_layout("close")
	lo.geometry = third_geo
	lo.style = osc_styles.wcButtons
	lo.alpha[1] = user_opts.alphaWinCtrl

	add_area("showhide_wc", get_hitbox_coords(wc_geo.x, wc_geo.y, wc_geo.an, wc_geo.w, wc_geo.h))

	if user_opts.windowcontrols_title then
		ne = new_element("wctitle", "button")
		ne.content = function ()
			local title = state.forced_title or mp.command_native({"expand-text", user_opts.title})
			title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
			if not user_opts.windowcontrols_title then
				title = ""
			end
			return not (title == "") and title or " "
		end
		ne.hoverable = false
		local left_pad = 10
		local right_pad = 10
		lo = add_layout("wctitle")
		lo.geometry = { x = titlebox_left + left_pad, y = 22, an = 1, w = titlebox_w, h = wc_geo.h }
		lo.style = string.format("%s{\\clip(%f,%f,%f,%f)}",
		osc_styles.wcTitle,
		titlebox_left + left_pad, wc_geo.y - wc_geo.h,
		titlebox_right - right_pad, wc_geo.y + wc_geo.h)	   
	end
end

--
-- Modernx Layout
--

function layout()

	local minimalUI = user_opts.minimalUI	

	local osc_geo = {
		w = osc_param.playresx,
		h = 120 -- Not too low to avoid Thumbnails not disappearing
	}
	if minimalUI then
		osc_geo.h = 90
	end
	user_opts.heightoscShowHidearea = osc_geo.h

	-- origin of the controllers, bottom left corner
	local posX = 0
	local posY = osc_param.playresy

	-- alignment
	local refX = osc_geo.w / 2
	local refY = posY

	osc_param.areas = {} -- delete areas

	-- area for active mouse input - OSC hover bottom
	add_area("input", get_hitbox_coords(posX, posY, 1, osc_geo.w, osc_geo.h))

	-- area for show/hide
	add_area("showhide", 0, 0, osc_param.playresx, osc_param.playresy)

	local lo, geo

	-- offsets minimal interface
	local minimalSeekY = 0
	local yMinimalSeekW = 0
	local xMinimalIcons = 0
	local yMinimalIcons = 0
	if minimalUI then
		minimalSeekY = user_opts.minimalSeekY
		yMinimalSeekW = osc_geo.w / 3
		yMinimalIcons = minimalSeekY - 30
	end

	local smallIconS = user_opts.smallIcon					-- size small icons
	local oscY = 30											-- osc y - Distance small buttons from the bottom
	local gapNavButton = 40									-- gap between navigation buttons
	local seekbarMarginX = 180 + yMinimalSeekW				-- seekbar margin with minimal offset
	local bgBarHeight = 1
	if user_opts.seekbarBgHeight then
		bgBarHeight = bgBarHeight + user_opts.seekbarHeight
	end
	local seekbarHeight = 15 + user_opts.seekbarHeight
	xMinimalIcons = (osc_geo.w - seekbarMarginX)/2

	-- Controller Background

	new_element("transBg", "box")
	lo = add_layout("transBg")
	lo.geometry = {x = posX, y = posY, an = 7, w = osc_geo.w, h = 10}
	if minimalUI then
		lo.style = osc_styles.transBgMini
	else
		lo.style = osc_styles.transBg
	end
	lo.layer = 10
	lo.alpha[3] = 0

	-- Seekbar

	new_element("bgBar", "box")
	lo = add_layout("bgBar")
	lo.geometry = {x = refX, y = refY - oscY - 30 + minimalSeekY, an = 5, w = osc_geo.w - seekbarMarginX, h = bgBarHeight}
	lo.style = osc_styles.seekbarBg
	lo.layer = 13
	lo.alpha[1] = user_opts.bgBarAlpha

	osc_styles.seekbarFg = createStyle(0, 0, osc_palette[user_opts.seekbarColorIndex], white, nil, nil)

	lo = add_layout("seekbar")
	lo.geometry = {x = refX, y = refY - oscY - 30 + minimalSeekY, an = 5, w = osc_geo.w - seekbarMarginX, h = seekbarHeight}
	lo.style = osc_styles.seekbarFg
	lo.slider.gap = 7
	lo.slider.tooltip_style = osc_styles.tooltip
	lo.slider.tooltip_an = 2

	-- Timecodes

	lo = add_layout("tc_left")
	if minimalUI then
		lo.geometry = {x = refX - xMinimalIcons - 95, y = refY - oscY - 37 + minimalSeekY, an = 7, w = 50, h = smallIconS}
	else
		lo.geometry = {x = 27, y = refY - oscY - 37 + minimalSeekY, an = 7, w = 50, h = smallIconS}
	end
	lo.style = osc_styles.timecodeL

	lo = add_layout("tc_right")
	if minimalUI then
		lo.geometry = {x = refX + xMinimalIcons + 50, y = refY - oscY - 37 + minimalSeekY, an = 7, w = 50, h = 200}
	else
		lo.geometry = {x = osc_geo.w - 25, y = refY - oscY - 37 + minimalSeekY, an = 9, w = 50, h = smallIconS}
	end
	lo.style = osc_styles.timecodeR

	-- Playlist control buttons

	local prevnextPos = (2 * gapNavButton)
	if user_opts.showChapters then
		prevnextPos = (3 * gapNavButton)
	end

	lo = add_layout("pl_prev")
	if minimalUI then
		lo.geometry = {x = refX - xMinimalIcons - 15, y = refY - oscY + yMinimalIcons, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = refX - prevnextPos, y = refY - oscY + yMinimalIcons, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.mediumButtonsBig

	lo = add_layout("pl_next")
	if minimalUI then
		lo.geometry = {x = refX + xMinimalIcons + 15, y = refY - oscY + yMinimalIcons, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = refX + prevnextPos, y = refY - oscY + yMinimalIcons, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.mediumButtonsBig

	-- Audio tracks
	lo = add_layout("cy_audio")
	if minimalUI then
		lo.geometry = {x = refX - xMinimalIcons - oscY - 5, y = refY - oscY + yMinimalIcons, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = 60, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.togIcon

	-- Subtitle tracks
	lo = add_layout("cy_sub")
	if minimalUI then
		lo.geometry = {x = refX + xMinimalIcons + oscY + 5, y = refY - oscY + yMinimalIcons, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = 85, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.togIcon

	-- If not minimal UI all other buttons
	if not minimalUI then

		-- Title
		geo = {x = 27, y = refY - oscY - 50, an = 1, w = osc_geo.w - 50, h = 48}
		lo = add_layout("title")
		lo.geometry = geo
		lo.style = string.format("%s{\\clip(%f,%f,%f,%f)}", osc_styles.vidTitle,
								 geo.x, geo.y - geo.h, geo.x + geo.w, geo.y)
		lo.alpha[3] = 0

		-- Playback control buttons

		lo = add_layout("playpause")
		lo.geometry = {x = refX, y = refY - oscY, an = 5, w = 45, h = 45}
		lo.style = osc_styles.bigButtons

		lo = add_layout("skipback")
		lo.geometry = {x = refX - gapNavButton, y = refY - oscY + yMinimalIcons + 1, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.mediumButtons

		lo = add_layout("skipfrwd")
		lo.geometry = {x = refX + gapNavButton, y = refY - oscY + yMinimalIcons + 1, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.mediumButtons

		if user_opts.showChapters then
			lo = add_layout("ch_prev")
			lo.geometry = {x = refX - (2 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.mediumButtonsBig
		end

		if user_opts.showChapters then
			lo = add_layout("ch_next")
			lo.geometry = {x = refX + (2 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.mediumButtonsBig
		end

		-- Volume
		lo = add_layout("volume")
		lo.geometry = {x = 35, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIcon

		-- Toggle tooltip
		if user_opts.showIcons then
			lo = add_layout("tog_tooltip")
			lo.geometry = {x = 110, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon
		end

		-- Playback speed
		if user_opts.showIcons then
			lo = add_layout("playback_speed")
			lo.geometry = {x = 140, y = refY - oscY - 0.5, an = 5, w = 30, h = smallIconS}
			lo.style = osc_styles.speedButton
		end

		-- Cache
		if user_opts.showIcons then
			if user_opts.showCache then
				lo = add_layout("cache")
				lo.geometry = {x = 185, y = refY - oscY - 1.5, an = 5, w = 30, h = smallIconS}
				lo.style = osc_styles.speedButton
			end
		end

		if user_opts.showIcons then

			-- Toggle loop
			lo = add_layout("tog_loop")
			lo.geometry = {x = osc_geo.w - 185, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Toggle thumbfast
			lo = add_layout("tog_thumb")
			lo.geometry = {x = osc_geo.w - 160, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Toggle OSC mode
			lo = add_layout("tog_oscmode")
			lo.geometry = {x = osc_geo.w - 135, y = refY - oscY - 1, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Toggle on top
			lo = add_layout("tog_ontop")
			lo.geometry = {x = osc_geo.w - 110, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

		end

		-- Toggle UI
		lo = add_layout("tog_ui")
		lo.geometry = {x = osc_geo.w - 85, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIcon

		-- Toggle info
		lo = add_layout("tog_info")
		lo.geometry = {x = osc_geo.w - 60, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIconBig

		-- Toggle fullscreen
		lo = add_layout("tog_fs")
		lo.geometry = {x = osc_geo.w - 35, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIconBig
	end
end

--
-- Pot Layout
--

function layoutPot()

	local minimalUI = user_opts.minimalUI

	local osc_geo = {
		w = osc_param.playresx,
		h = 120 -- Not too low to avoid Thumbnails not disapearing
	}
	if minimalUI then
		osc_geo.h = 70
	end
	user_opts.heightoscShowHidearea = osc_geo.h

	-- origin of the controllers, bottom left corner
	local posX = 0
	local posY = osc_param.playresy

	-- alignment
	local refX = osc_geo.w / 2
	local refY = posY

	osc_param.areas = {} -- delete areas

	-- area for active mouse input - OSC hover bottom
	add_area("input", get_hitbox_coords(posX, posY, 1, osc_geo.w, osc_geo.h))

	-- area for show/hide
	add_area("showhide", 0, 0, osc_param.playresx, osc_param.playresy)

	local lo, geo

	-- offsets
	local oscY = 30										-- y offset buttons
	local potRefX = 25									-- left x starting point
	local gapNavButton = 35								-- gap between navigation buttons
	local gapSmallButton = 25							-- gap between small buttons
	local smallIconS = user_opts.smallIcon				-- size small icons
	local bgBarHeight = 1
	if user_opts.seekbarBgHeight then
		bgBarHeight = bgBarHeight + user_opts.seekbarHeight
	end
	local seekbarHeight = 15 + user_opts.seekbarHeight 
	
	-- seekbar
	local offsetSeekbarLeft = (3 * gapNavButton) + 125	-- seekbar left offset
	if user_opts.showChapters and not minimalUI then
		offsetSeekbarLeft = (5 * gapNavButton) + 125
	end
	local seekbarWidth = osc_geo.w - 35					-- seekbar width
	local seekbarBgAlpha = user_opts.bgBarAlpha			-- seekbar background transparency
	
	-- offsets minimal interface
	if minimalUI then
		potRefX = 15
		gapNavButton = 20
		oscY = 15
		offsetSeekbarLeft = (3 * gapNavButton) + 150 - potRefX
		seekbarWidth = seekbarWidth - offsetSeekbarLeft - potRefX - gapNavButton
		seekbarBgAlpha = 255
	end

	-- Controller Background

	new_element("transBg", "box")
	lo = add_layout("transBg")
	lo.geometry = {x = posX, y = posY, an = 7, w = osc_geo.w, h = 10}
	if minimalUI then
		lo.style = osc_styles.transBgPotMini
		lo.alpha[3] = 100
	else
		lo.style = osc_styles.transBgPot
		lo.alpha[3] = 50
	end
	lo.layer = 10
	-- lo.alpha[3] = 255

	-- Seekbar

	new_element("bgBar", "box")
	lo = add_layout("bgBar")
	if minimalUI then
		lo.geometry = {x = potRefX + offsetSeekbarLeft, y = refY - oscY, an = 7, w = seekbarWidth, h = bgBarHeight}
	else
		lo.geometry = {x = refX, y = refY - oscY - 30, an = 5, w = seekbarWidth, h = bgBarHeight}
	end
	lo.style = osc_styles.seekbarBg
	lo.layer = 13
	lo.alpha[1] = seekbarBgAlpha

	osc_styles.seekbarFg = createStyle(0, 0, osc_palette[user_opts.seekbarColorIndex], white, nil, nil)

	lo = add_layout("seekbar")
	local hhh = refX - (refX - potRefX + offsetSeekbarLeft)
	if minimalUI then
		lo.geometry = {x = refX + 52, y = refY - oscY + 1, an = 5, w = seekbarWidth, h = seekbarHeight}
		lo.alpha[1] = 100
	else
		lo.geometry = {x = refX, y = refY - oscY - 30, an = 5, w = seekbarWidth, h = seekbarHeight}
		lo.alpha[1] = 50
	end
	lo.style = osc_styles.seekbarFg
	lo.slider.gap = 7
	lo.slider.tooltip_style = osc_styles.tooltip
	lo.slider.tooltip_an = 2
	-- lo.alpha[1] = 0

	-- Playback control buttons
	
	lo = add_layout("playpause")
	lo.geometry = {x = potRefX, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	if minimalUI then
		lo.style = osc_styles.miniButtonsPot
	else
		lo.style = osc_styles.bigButtonsPot
	end

	lo = add_layout("pl_prev")
	if user_opts.showChapters and not minimalUI then
		lo.geometry = {x = potRefX + (3 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	lo.style = osc_styles.bigButtonsPot
	else
		lo.geometry = {x = potRefX + gapNavButton, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.miniButtonsPot
	end

	lo = add_layout("pl_next")
	if user_opts.showChapters and not minimalUI then
		lo.geometry = {x = potRefX + (4 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	lo.style = osc_styles.bigButtonsPot
	else
		lo.geometry = {x = potRefX + (2 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.miniButtonsPot
	end
	
	if user_opts.showChapters and not minimalUI then
		lo = add_layout("ch_prev")
		lo.geometry = {x = potRefX + gapNavButton, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.bigButtonsPot
	end

	if user_opts.showChapters and not minimalUI then
		lo = add_layout("ch_next")
		lo.geometry = {x = potRefX + (2 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.bigButtonsPot
	end

	-- Timecodes

	lo = add_layout("tc_left")
	if user_opts.showChapters and not minimalUI then
		lo.geometry = {x = potRefX + (5 * gapNavButton), y = refY - oscY + 1, an = 4, w = 50, h = smallIconS}
	else
		lo.geometry = {x = potRefX + (3 * gapNavButton), y = refY - oscY + 1, an = 4, w = 50, h = smallIconS}
	end
	lo.style = osc_styles.timecodeL

	-- /
	lo = add_layout("tc_separator")
	if user_opts.showChapters and not minimalUI then
		lo.geometry = {x = potRefX + (5 * gapNavButton) + 48, y = refY - oscY + 1, an = 4, w = 50, h = smallIconS}
	else
		lo.geometry = {x = potRefX + (3 * gapNavButton) + 48, y = refY - oscY + 1, an = 4, w = 50, h = smallIconS}
	end
	lo.style = osc_styles.timecodeR

	lo = add_layout("tc_right")
	if user_opts.showChapters and not minimalUI then
		lo.geometry = {x = potRefX + (5 * gapNavButton) + 56, y = refY - oscY + 1, an = 4, w = 50, h = smallIconS}
	else
		lo.geometry = {x = potRefX + (3 * gapNavButton) + 56, y = refY - oscY + 1, an = 4, w = 50, h = smallIconS}
	end
	lo.style = osc_styles.timecodeR

	-- Toggle Ontop
	lo = add_layout("tog_ontop")
	if minimalUI then
		lo.geometry = {x = osc_geo.w - (3 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = osc_geo.w - (6 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.togIcon

	-- Audio / Subs

	lo = add_layout("cy_audio")
	if minimalUI then
		lo.geometry = {x = osc_geo.w - (2 * gapNavButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = osc_geo.w - (5 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.togIcon

	lo = add_layout("cy_sub")
	if minimalUI then
		lo.geometry = {x = osc_geo.w - gapNavButton, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	else
		lo.geometry = {x = osc_geo.w - (4 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
	end
	lo.style = osc_styles.togIcon

	-- If minimal UI disabled : add other buttons

	if not minimalUI then

		-- Title
		lo = add_layout("title")
		lo.geometry = {x = potRefX + offsetSeekbarLeft, y = refY - oscY + 1, an = 4, w = seekbarWidth, h = smallIconS}
		lo.style = osc_styles.titlePotMini
		lo.alpha[3] = 0
		lo.button.maxchars = 75
		if ((not user_opts.vidscale and not state.fullscreen) or not state.fullscreen) then
			lo.button.maxchars = 50
		end

		if user_opts.showIcons then

			-- Cache
			if user_opts.showCache then
				lo = add_layout("cache")
				lo.geometry = {x = osc_geo.w - (14 * gapSmallButton) - 5, y = refY - oscY - 1, an = 5, w = smallIconS, h = smallIconS}
				lo.style = osc_styles.speedButton
			end

			-- Playback speed
			lo = add_layout("playback_speed")
			lo.geometry = {x = osc_geo.w - (12 * gapSmallButton) - 5, y = refY - oscY + 1, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.speedButton

			-- Toggle tooltip
			lo = add_layout("tog_tooltip")
			lo.geometry = {x = osc_geo.w - (11 * gapSmallButton), y = refY - oscY + 1, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Toggle loop
			lo = add_layout("tog_loop")
			lo.geometry = {x = osc_geo.w - (10 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Toggle thumbfast
			lo = add_layout("tog_thumb")
			lo.geometry = {x = osc_geo.w - (9 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Toggle OSC mode
			lo = add_layout("tog_oscmode")
			lo.geometry = {x = osc_geo.w - (8 * gapSmallButton), y = refY - oscY - 1, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

			-- Volume
			lo = add_layout("volume")
			lo.geometry = {x = osc_geo.w - (7 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
			lo.style = osc_styles.togIcon

		end

		-- Toggle info
		lo = add_layout("tog_ui")
		lo.geometry = {x = osc_geo.w - (3 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIcon

		-- Toggle info
		lo = add_layout("tog_info")
		lo.geometry = {x = osc_geo.w - (2 * gapSmallButton), y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIconBig

		-- Toggle fullscreen
		lo = add_layout("tog_fs")
		lo.geometry = {x = osc_geo.w - gapSmallButton, y = refY - oscY, an = 5, w = smallIconS, h = smallIconS}
		lo.style = osc_styles.togIconBig

	end
end

-- Validate string type user options
function validate_user_opts()
	if user_opts.windowcontrols ~= "auto" and
	   user_opts.windowcontrols ~= "fullscreen_only" and
	   user_opts.windowcontrols ~= "yes" and
	   user_opts.windowcontrols ~= "no" then
		msg.warn("windowcontrols cannot be \"" ..
				user_opts.windowcontrols .. "\". Ignoring.")
		user_opts.windowcontrols = "auto"
	end
end

function update_options(list, changed)
	validate_user_opts()
	if changed.tick_delay or changed.tick_delay_follow_display_fps then
		set_tick_delay("display_fps", mp.get_property_number("display_fps", nil))
	end
	request_tick()
	set_tick_delay("display_fps", mp.get_property_number("display_fps", nil))
	visibility_mode(user_opts.visibility, true)
	update_duration_watch()
	request_init()
end

-- OSC INIT
function osc_init()

	-- set canvas resolution according to display aspect and scaling setting
	local baseResY = 720
	local display_w, display_h, display_aspect = mp.get_osd_size()
	local scale = 1
	
	local minimalUI = user_opts.minimalUI

	if (mp.get_property("video") == "no") then -- dummy/forced window
		scale = user_opts.scaleforcedwindow
	elseif state.fullscreen then
		scale = user_opts.scalefullscreen
	else
		scale = user_opts.scalewindowed
	end

	if user_opts.vidscale then
		osc_param.unscaled_y = baseResY
	else
		osc_param.unscaled_y = display_h
	end
	osc_param.playresy = osc_param.unscaled_y / scale
	if (display_aspect > 0) then
		osc_param.display_aspect = display_aspect
	end
	osc_param.playresx = osc_param.playresy * osc_param.display_aspect

	-- stop seeking with the slider to prevent skipping files
	state.active_element = nil

	elements = {}

	-- some often needed stuff
	local pl_count = mp.get_property_number("playlist-count", 0)
	local have_pl = (pl_count > 1)
	local pl_pos = mp.get_property_number("playlist-pos", 0) + 1
	local have_ch = (mp.get_property_number("chapters", 0) > 0)
	local loop = mp.get_property("loop-playlist", "no")

	local ne

	-- seekbar

	ne = new_element("seekbar", "slider")
	ne.enabled = not (mp.get_property("percent-pos") == nil)
	state.slider_element = ne.enabled and ne or nil  -- used for forced_title
	ne.slider.markerF = function ()
		local duration = mp.get_property_number("duration")
		if not (duration == nil) then
			local chapters = mp.get_property_native("chapter-list", {})
			local markers = {}
			for n = 1, #chapters do
				markers[n] = (chapters[n].time / duration * 100)
			end
			return markers
		else
			return {}
		end
	end
	ne.slider.posF =
		function () return mp.get_property_number("percent-pos") end
	ne.slider.tooltipF = function (pos)
		local duration = mp.get_property_number("duration")
		if not ((duration == nil) or (pos == nil)) then
			possec = duration * (pos / 100)
			return mp.format_time(possec)
		else
			return ""
		end
	end
	ne.slider.seekRangesF = function()
		if user_opts.seekrangestyle == "none" then
			return nil
		end
		local cache_state = state.cache_state
		if not cache_state then
			return nil
		end
		local duration = mp.get_property_number("duration")
		if (duration == nil) or duration <= 0 then
			return nil
		end
		local ranges = cache_state["seekable-ranges"]
		if #ranges == 0 then
			return nil
		end
		local nranges = {}
		for _, range in pairs(ranges) do
			nranges[#nranges + 1] = {
				["start"] = 100 * range["start"] / duration,
				["end"] = 100 * range["end"] / duration,
			}
		end
		return nranges
	end
	ne.eventresponder["mouse_move"] = --keyframe seeking when mouse is dragged
		function (element)
			-- mouse move events may pile up during seeking and may still get
			-- sent when the user is done seeking, so we need to throw away
			-- identical seeks
			local seekto = get_slider_value(element)
			if (element.state.lastseek == nil) or
				(not (element.state.lastseek == seekto)) then
					local flags = "absolute-percent"
					if not user_opts.seekbarkeyframes then
						flags = flags .. "+exact"
					end
					mp.commandv("seek", seekto, flags)
					element.state.lastseek = seekto
			end

		end
	ne.eventresponder["mbtn_left_down"] = --exact seeks on single clicks
		function (element) mp.commandv("seek", get_slider_value(element),
			"absolute-percent+exact") end
	ne.eventresponder["mbtn_right_up"] = function () -- right clic : switch chapter mode on / off
		if not minimalUI then
			user_opts.showChapters = not user_opts.showChapters
			request_init()
		end
	end
	ne.eventresponder["wheel_up_press"] = function () -- mouse wheel : bar height
		if user_opts.seekbarHeight <= 9 then
			user_opts.seekbarHeight = user_opts.seekbarHeight + 1
			request_init()
		end
	end
	ne.eventresponder["wheel_down_press"] = function () -- mouse wheel : bar height
		if user_opts.seekbarHeight > 0 then
			user_opts.seekbarHeight = user_opts.seekbarHeight - 1
			request_init()
		end
	end
	ne.eventresponder["reset"] = function
		(element) element.state.lastseek = nil 
	end

	-- title

	ne = new_element("title", "button")
	ne.visible = user_opts.showTitle
	ne.hoverable = false
	ne.content = function ()
		local title = state.forced_title or mp.command_native({"expand-text", user_opts.title})
		title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
		return title
	end

	-- tc_left (current pos)

	ne = new_element("tc_left", "button")
	ne.hoverable = false
	ne.styledown = minimalUI and user_opts.modernTog
	ne.content = function ()
		return (mp.get_property_osd("playback-time"))
	end
	if (minimalUI and not user_opts.windowcontrols_title) or (not user_opts.windowcontrols_title and not user_opts.showTitle) then
		if user_opts.showTooltip then
			ne.tooltip_style = osc_styles.tooltip
			ne.tooltipF = function ()
				local title = state.forced_title or mp.command_native({"expand-text", user_opts.title})
				title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
				return title
			end
		end
	end
	if minimalUI and user_opts.modernTog then
		ne.hoverable = true
		ne.eventresponder["mbtn_left_up"] = function () 
			mp.commandv("cycle", "pause") 
		end
	elseif not minimalUI then
		ne.eventresponder["mbtn_left_up"] = function ()
			user_opts.showTitle = not user_opts.showTitle 
			request_init()
		end
	end
	ne.eventresponder["mbtn_right_up"] =function () 
		user_opts.windowcontrols_title = not user_opts.windowcontrols_title 
		request_init()
	end
	ne.eventresponder["wheel_down_press"] = function ()
		mp.commandv("seek", -user_opts.jumpValue)
	end
	ne.eventresponder["wheel_up_press"] = function ()
		mp.commandv("seek", user_opts.jumpValue) 
	end
		
	-- separator /

	ne = new_element("tc_separator", "button")
	ne.hoverable = false
	ne.styledown = false
	ne.visible = not user_opts.modernTog
	ne.content = function () return "/" end

	-- tc_right (total/remaining time)

	ne = new_element("tc_right", "button")
	ne.hoverable = false
	ne.styledown = false
	ne.content = function ()
		if user_opts.timetotal then
			if user_opts.modernTog then
				return (mp.get_property_osd("playtime-remaining"))
			else
				return (mp.get_property_osd("playtime-remaining"))
			end
		end
		return (mp.get_property_osd("duration"))
	 end
	ne.eventresponder["mbtn_left_up"] = function ()
		user_opts.timetotal = not user_opts.timetotal
	end
	ne.eventresponder["mbtn_right_up"] = function () -- right clic : switch UI minimal / default
		user_opts.minimalUI = not user_opts.minimalUI
		request_init()
	end
	ne.eventresponder["wheel_up_press"] = function () -- wheel : move bar up / down in minimal UI mode
		if minimalUI and user_opts.modernTog then
			if user_opts.minimalSeekY > 0 then
				user_opts.minimalSeekY = user_opts.minimalSeekY - 1
			end
			request_init()
		end
	end
	ne.eventresponder["wheel_down_press"] = function () -- wheel : move bar up / down in minimal UI mode
		if minimalUI and user_opts.modernTog then
			if user_opts.minimalSeekY < 50 then
				user_opts.minimalSeekY = user_opts.minimalSeekY + 1
			end
			request_init()
		end
	end

	--
	-- playlist buttons
	--

	-- prev

	ne = new_element("pl_prev", "button")
	ne.content = osc_icons.playlist_prev
	ne.enabled = (pl_pos > 1) or (loop ~= "no")
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local file = getDeltaPlaylistItem(-1)
			return file.label
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("playlist-prev", "weak")
		if user_opts.playlist_osd then
			show_message(get_playlist(), 3)
		end
	end
	ne.eventresponder["shift+mbtn_left_up"] = function ()
		show_message(get_playlist(), 10) 
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		show_message(get_playlist(), 3)
	end

	-- next

	ne = new_element("pl_next", "button")
	ne.content = osc_icons.playlist_next
	ne.enabled = (have_pl and (pl_pos < pl_count)) or (loop ~= "no")
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local file = getDeltaPlaylistItem(1)
			return file.label
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("playlist-next", "weak")
		if user_opts.playlist_osd then
			show_message(get_playlist(), 3)
		end
	end
	ne.eventresponder["shift+mbtn_left_up"] = function ()
		show_message(get_playlist(), 10) 
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		show_message(get_playlist(), 3) 
	end

	--
	-- big buttons
	--

	-- playpause

	ne = new_element("playpause", "button")
	ne.content = function ()
		if mp.get_property("pause") == "yes" then
			return (osc_icons.play)
		else
			return (osc_icons.pause)
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("cycle", "pause") 
	end
	ne.eventresponder["mbtn_right_up"] = function () -- Right clic : cycle through colors
		if user_opts.seekbarColorIndex == #osc_palette then
			user_opts.seekbarColorIndex = 1
		else
			user_opts.seekbarColorIndex = user_opts.seekbarColorIndex + 1
		end
		request_init()
	end

	-- skipback

	ne = new_element("skipback", "button")
	ne.softrepeat = true
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return "Jump : -" .. utils.to_string(user_opts.jumpValue) .. "s, -1min"
		end
	end
	ne.content = osc_icons.skipback
	ne.eventresponder["mbtn_left_down"] = function ()
		mp.commandv("seek", -user_opts.jumpValue) 
	end
	ne.eventresponder["shift+mbtn_left_down"] = function ()
		mp.commandv("frame-back-step") 
	end
	ne.eventresponder["mbtn_right_down"] = function ()
		mp.commandv("seek", -60) 
	end

	-- skipfrwd

	ne = new_element("skipfrwd", "button")
	ne.softrepeat = true
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return "Jump : +" .. utils.to_string(user_opts.jumpValue) .. "s, +1min"
		end
	end
	ne.content = osc_icons.skipforward
	ne.eventresponder["mbtn_left_down"] = function ()
		mp.commandv("seek", user_opts.jumpValue) 
	end
	ne.eventresponder["shift+mbtn_left_down"] = function ()
		mp.commandv("frame-step") 
	end
	ne.eventresponder["mbtn_right_down"] = function ()
		mp.commandv("seek", 60) 
	end

	-- ch_prev

	ne = new_element("ch_prev", "button")
	ne.enabled = have_ch
	ne.content = osc_icons.chapter_prev
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local file = getDeltaChapter(-1)
			if file == nil then
				return "Chapter 1 not starting at 0. Who does that ?"
			else
				return file.label
			end
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("add", "chapter", -1)
		if user_opts.chapters_osd then
			show_message(get_chapterlist(), 3)
		end
	end
	ne.eventresponder["shift+mbtn_left_up"] = function ()
		show_message(get_chapterlist(), 3) 
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		show_message(get_chapterlist(), 3) 
	end

	-- ch_next

	ne = new_element("ch_next", "button")
	ne.enabled = have_ch
	ne.content = osc_icons.chapter_next
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local file = getDeltaChapter(1)
			if file == nil then
				return "Chapter 1 not starting at 0. Who does that ?"
			else
				return file.label
			end
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("add", "chapter", 1)
		if user_opts.chapters_osd then
			show_message(get_chapterlist(), 3)
		end
	end
	ne.eventresponder["shift+mbtn_left_up"] = function ()
		show_message(get_chapterlist(), 3) 
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		show_message(get_chapterlist(), 3) 
	end

	update_tracklist()

	-- cy_audio

	ne = new_element("cy_audio", "button")
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	ne.enabled = (#tracks_osc.audio > 0)
	ne.off = (get_track("audio") == 0)
	ne.content = osc_icons.audio
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return get_track_name("audio")
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		set_track("audio", 1)
		get_track_name("audio")
		show_message(get_tracklist("audio"), 2) 
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		set_track("audio", -1)
		get_track_name("audio")
		show_message(get_tracklist("audio"), 2) 
	end

	-- cy_sub

	ne = new_element("cy_sub", "button")
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	ne.enabled = (#tracks_osc.sub > 0)
	ne.off = (get_track("sub") == 0)
	ne.content = osc_icons.subtitle
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return get_track_name("sub")
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		set_track("sub", 1) 
		get_track_name("sub")
		show_message(get_tracklist("sub"), 2)
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		set_track("sub", -1) 
		get_track_name("sub")
		show_message(get_tracklist("sub"), 2)
	end
	ne.eventresponder["wheel_up_press"] = function () -- mouse wheel : subtitles position up / down
		local subPos = mp.get_property("sub-pos")
		subPos = subPos - 1
		mp.set_property("sub-pos", subPos)
	end
	ne.eventresponder["wheel_down_press"] = function () -- mouse wheel : subtitles position up / down
		local subPos = mp.get_property("sub-pos")
		subPos = subPos + 1
		mp.set_property("sub-pos", subPos)
	end

	-- tog_tooltip

	ne = new_element("tog_tooltip", "button")
	ne.content = osc_icons.tooltipOn
	if not user_opts.showTooltip then
		ne.content = osc_icons.tooltipOff
	end
	ne.off = not user_opts.showTooltip
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = "Tooltips : On"
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		user_opts.showTooltip = not user_opts.showTooltip
		request_init()
	end

	-- tog_oscmode
	ne = new_element("tog_oscmode", "button")
	ne.content = osc_icons.oscmode
	if user_opts.oscMode == "onpause" then
		ne.content = osc_icons.oscmodeOnPause
	elseif user_opts.oscMode == "always" then
		ne.content = osc_icons.oscmodeAlways
	end	
	ne.off = user_opts.oscMode == "default"
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local msg  = "OSC mode : default"
			if user_opts.oscMode == "onpause" then
				msg = "OSC mode : on pause"
			elseif user_opts.oscMode == "always" then
				msg = "OSC mode : always"
			end	
			return msg
		end
	end
	ne.eventresponder["mbtn_left_up"] = function () -- left click : show OSC > default / on pause / always

		if user_opts.oscMode == "default" then
			user_opts.oscMode = "onpause"
			user_opts.showonpause = true
		elseif user_opts.oscMode == "onpause" then
			user_opts.oscMode = "always"
			user_opts.showonpause = true
		else
			user_opts.oscMode = "default"
			user_opts.showonpause = false
		end

		if not user_opts.showTooltip then
			mp.osd_message("OSC mode : " .. utils.to_string(user_opts.oscMode))
		end

		request_init()
	end
	ne.eventresponder["mbtn_right_up"] = function () -- right clics : OSC show on mouse move on / off
		if user_opts.minmousemove < 0 then
			user_opts.minmousemove = 0
			mp.osd_message("OSC show on mouse move : On")
		else
			user_opts.minmousemove = -1
			mp.osd_message("OSC show on mouse move : Off")
		end
		request_init()
	end
	ne.eventresponder["wheel_up_press"] = function () -- wheel : increase / decrease hide time duration
		if user_opts.minmousemove < 0 then
			if user_opts.hidetimeout < 5000 then
				user_opts.hidetimeout = user_opts.hidetimeout + 100
			end
			mp.osd_message("Hide timeout duration : " .. utils.to_string(user_opts.hidetimeout) .. "ms")
		else
			if user_opts.hidetimeoutMouseMove < 5000 then
				user_opts.hidetimeoutMouseMove = user_opts.hidetimeoutMouseMove + 100
			end
			mp.osd_message("Hide timeout duration : " .. utils.to_string(user_opts.hidetimeoutMouseMove) .. "ms")
		end
		save_file()
	end
	ne.eventresponder["wheel_down_press"] = function () -- wheel : increase / decrease hide time duration
		if user_opts.minmousemove < 0 then
			if user_opts.hidetimeout > 0 then
				user_opts.hidetimeout = max(0, user_opts.hidetimeout - 100)
			end
			mp.osd_message("Hide timeout duration : " .. utils.to_string(user_opts.hidetimeout) .. "ms")
		else
			if user_opts.hidetimeoutMouseMove > 0 then
				user_opts.hidetimeoutMouseMove = max(0, user_opts.hidetimeoutMouseMove - 100)
			end
			mp.osd_message("Hide timeout duration : " .. utils.to_string(user_opts.hidetimeoutMouseMove) .. "ms")
		end
		save_file()
	end
	ne.eventresponder["shift+wheel_up_press"] = function () -- shift + wheel : increase / decrease fade time duration
		if user_opts.minmousemove < 0 then
			if user_opts.fadeduration < 5000 then
				user_opts.fadeduration = user_opts.fadeduration + 100
			end
			mp.osd_message("Fade duration : " .. utils.to_string(user_opts.fadeduration) .. "ms")
		else
			if user_opts.fadedurationMouseMove < 5000 then
				user_opts.fadedurationMouseMove = user_opts.fadedurationMouseMove + 100
			end
			mp.osd_message("Fade duration : " .. utils.to_string(user_opts.fadedurationMouseMove) .. "ms")
		end
		save_file()
	end
	ne.eventresponder["shift+wheel_down_press"] = function () -- shift + wheel : increase / decrease fade time duration
		if user_opts.minmousemove < 0 then
			if user_opts.fadeduration > 0 then
				user_opts.fadeduration = max(0, user_opts.fadeduration - 100)
			end
			mp.osd_message("Fade duration : " .. utils.to_string(user_opts.fadeduration) .. "ms")
		else
			if user_opts.fadedurationMouseMove > 0 then
				user_opts.fadedurationMouseMove = max(0, user_opts.fadedurationMouseMove - 100)
			end
			mp.osd_message("Fade duration : " .. utils.to_string(user_opts.fadedurationMouseMove) .. "ms")
		end
		save_file()
	end

	-- tog_thumb

	ne = new_element("tog_thumb", "button")
	ne.content = osc_icons.thumb
	ne.off = not user_opts.showThumbfast
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	ne.enabled = thumbfast.available
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local msg = "Thumbfast : Off"
			if user_opts.showThumbfast then
				msg = "Thumbfast : On"
			end
			return msg
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		user_opts.showThumbfast = not user_opts.showThumbfast
		request_init()
	end

	-- tog_ontop

	ne = new_element("tog_ontop", "button")
	ne.content = osc_icons.ontop
	if user_opts.onTopWhilePlaying then
		ne.content = osc_icons.onTopWP
	end
	ne.off = (mp.get_property("ontop") == "no") and not user_opts.onTopWhilePlaying
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local msg
			if user_opts.onTopWhilePlaying then
				msg = "OnTop : Wile playing"
			elseif mp.get_property("ontop") == "no" then
				msg = "OnTop : Off"
			else 
				msg = "OnTop : On"
			end
			return msg
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		user_opts.onTopWhilePlaying = false
		if mp.get_property("ontop") == "no" then
			was_ontop = false
			mp.set_property("ontop", "yes")
		else
			was_ontop = true
			mp.set_property("ontop", "no")
		end
		request_init()
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		user_opts.onTopWhilePlaying = true
		if mp.get_property("pause") == "no" then
			mp.set_property("ontop", "yes")
		else
			mp.set_property("ontop", "no")
		end
		request_init()
	end
  
	-- tog_loop

	ne = new_element("tog_loop", "button")
	ne.content = osc_icons.loop
	if mp.get_property("loop-file")=="inf" then
		ne.content = osc_icons.loop1
	elseif mp.get_property("loop-playlist")=="inf" then
		ne.content = osc_icons.loopPL
	end
	ne.off = mp.get_property("loop-file")=="no" and mp.get_property("loop-playlist")=="no"
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local msg = "Loop file : Off"
			if mp.get_property("loop-file")=="inf" then
				msg = "Loop file : On"
			elseif mp.get_property("loop-playlist")=="inf" then
				msg = "Loop playlist : On"
			end
			return msg
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		if mp.get_property("loop-file")=="inf" then
			mp.set_property("loop-file", "no")
			mp.set_property("loop-playlist", "no")
		else
			mp.set_property("loop-file", "inf")
			mp.set_property("loop-playlist", "no")
		end
		request_init()
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		if mp.get_property("loop-playlist")=="inf" then
			mp.set_property("loop-playlist", "no")
			mp.set_property("loop-file", "no")
		else
			mp.set_property("loop-playlist", "inf")
			mp.set_property("loop-file", "no")
		end
		request_init()
	end

	-- tog_ui

	ne = new_element("tog_ui", "button")
	ne.content = osc_icons.switch
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return "Switch UI"
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		user_opts.modernTog = not user_opts.modernTog
		user_opts.minimalUI = false
		request_init()
	end
	ne.eventresponder["mbtn_right_up"] = function () -- right clic : switch UI minimal / default
		user_opts.minimalUI = not user_opts.minimalUI
		request_init()
	end

	-- tog_info

	ne = new_element("tog_info", "button")
	ne.content = osc_icons.info
	ne.off = not user_opts.showInfos
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return "R : hide toggles"
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		if user_opts.showInfos then
			mp.commandv("script-binding", "stats/display-stats-toggle")
			user_opts.showInfos = false
		else
			mp.commandv("script-binding", "stats/display-stats-toggle")
			user_opts.showInfos = true
		end
		request_init()
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		user_opts.showIcons = not user_opts.showIcons
		request_init()
	end

	-- tog_fs

	ne = new_element("tog_fs", "button")
	ne.content = function ()
		if state.fullscreen then
			return osc_icons.fullscreen_exit
		else
			return osc_icons.fullscreen
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("cycle", "fullscreen") 
	end

	-- volume

	ne = new_element("volume", "button")
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			local msg = ""
			if mp.get_property_native("mute") then
				return "Mute : On"
			end
			return msg
		end
	end
	ne.content = function()
		local volume = mp.get_property_number("volume", 0)
		local mute = mp.get_property_native("mute")
		if volume == 0 or mute then
			return osc_icons.volume_mute
		else
			return osc_icons.volume
		end
	end
	ne.eventresponder["mbtn_left_up"] = function ()
		mp.commandv("cycle", "mute")
	end
	ne.eventresponder["wheel_up_press"] = function ()
		mp.commandv("osd-auto", "add", "volume", 5) 
	end
	ne.eventresponder["wheel_down_press"] = function ()
		mp.commandv("osd-auto", "add", "volume", -5) 
	end

	-- playback speed

	ne = new_element("playback_speed", "button")
	if user_opts.showTooltip then
		ne.tooltip_style = osc_styles.tooltip
		ne.tooltipF = function ()
			return "Speed"
		end
	end
	ne.content = function()
		local speed = mp.get_property_number("speed", 1.0)
		return string.format("%.2fx", speed)
	end
	ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
	ne.eventresponder["mbtn_left_up"] = function ()
		local speeds = {1.0, 1.25, 1.5, 1.75, 2.0}  -- List of playback speeds
		local current_speed = mp.get_property_number("speed", 1.0)
		local next_speed = speeds[1]  -- Default to the first speed in case current speed isn't found

		for i = 1, #speeds do
			if current_speed == speeds[i] then
				next_speed = speeds[(i % #speeds) + 1]
				break
			end
		end
		mp.set_property("speed", next_speed)
	end
	ne.eventresponder["mbtn_right_up"] = function ()
		mp.set_property("speed", 1.0)
	end
	ne.eventresponder["wheel_up_press"] = function () 
		mp.commandv("add", "speed", 0.25) 
	end
	ne.eventresponder["wheel_down_press"] = function () 
		mp.commandv("add", "speed", -0.25) 
	end

	-- cache

	if user_opts.showCache then
		ne = new_element("cache", "button")
		ne.visible = (osc_param.playresx >= user_opts.visibleButtonsW)
		ne.hoverable = false
		ne.content = function ()
			local cache_state = state.cache_state
			--if not (cache_state and cache_state["seekable-ranges"] and
			--	#cache_state["seekable-ranges"] > 0) then
				-- probably not a network stream
			   -- return ""
			--end
			local dmx_cache = cache_state and cache_state["cache-duration"]
			local thresh = math.min(state.dmx_cache * 0.05, 5)  -- 5% or 5s
			if dmx_cache and math.abs(dmx_cache - state.dmx_cache) >= thresh then
				state.dmx_cache = dmx_cache
			else
				dmx_cache = state.dmx_cache
			end
			local min = math.floor(dmx_cache / 60)
			local sec = math.floor(dmx_cache % 60) -- don't round e.g. 59.9 to 60
			return "Cache : " .. (min > 0 and
				string.format("%sm%02.0fs", min, sec) or
				string.format("%3.0fs", sec))
		end
	end

	-- save params external file
	save_file()

	-- load layout
	if user_opts.modernTog then
		layout()
	else
		layoutPot()
	end

	-- load window controls
	if window_controls_enabled() then
		window_controls()
	end

	-- do something with the elements
	prepare_elements()
end

--
-- Other important stuff
--

function show_osc()

	-- show when disabled can happen (e.g. mouse_move) due to async/delayed unbinding
	if not state.enabled then return end

	--remember last time of invocation (mouse move)
	state.showtime = mp.get_time()

	osc_visible(true)

	if get_fadeduration() > 0 then
		state.anitype = nil
	end
end

function hide_osc()
	if user_opts.oscMode == "always" then
		osc_visible(true)
	elseif not state.enabled then
		-- typically hide happens at render() from tick(), but now tick() is
		-- no-op and won't render again to remove the osc, so do that manually.
		state.osc_visible = false
		render_wipe()
	elseif get_fadeduration() > 0 then
		if state.osc_visible then
			state.anitype = "out"
			request_tick()
		end
	else
		osc_visible(false)
	end
end

function osc_visible(visible)
	if state.osc_visible ~= visible then
		state.osc_visible = visible
	end
	request_tick()
end

function pause_state(name, enabled)
	state.paused = enabled
	mp.add_timeout(0.1, function() state.osd:update() end)
	if user_opts.showonpause then
		if enabled then
			state.lastvisibility = user_opts.visibility
			visibility_mode("always", true)
			show_osc()
		else
			visibility_mode(state.lastvisibility, true)
		end
	end
	request_tick()
end

function cache_state(name, st)
	state.cache_state = st
	request_tick()
end

-- Request that tick() is called (which typically re-renders the OSC).
-- The tick is then either executed immediately, or rate-limited if it was
-- called a small time ago.
function request_tick()
	if state.tick_timer == nil then
		state.tick_timer = mp.add_timeout(0, tick)
	end

	if not state.tick_timer:is_enabled() then
		local now = mp.get_time()
		local timeout = tick_delay - (now - state.tick_last_time)
		if timeout < 0 then
			timeout = 0
		end
		state.tick_timer.timeout = timeout
		state.tick_timer:resume()
	end
end

function mouse_leave()
	if get_hidetimeout() >= 0 then
		hide_osc()
	end
	-- reset mouse position
	state.last_mouseX, state.last_mouseY = nil, nil
	state.mouse_in_window = false
end

function request_init()
	state.initREQ = true
	request_tick()
end

-- Like request_init(), but also request an immediate update
function request_init_resize()
	request_init()
	-- ensure immediate update
	state.tick_timer:kill()
	state.tick_timer.timeout = 0
	state.tick_timer:resume()
end

function render_wipe()
	msg.trace("render_wipe()")
	state.osd.data = "" -- allows set_osd to immediately update on enable
	state.osd:remove()
end

function render()
	msg.trace("rendering")
	local current_screen_sizeX, current_screen_sizeY, aspect = mp.get_osd_size()
	local mouseX, mouseY = get_virt_mouse_pos()
	local now = mp.get_time()

	-- check if display changed, if so request reinit
	if not (state.mp_screen_sizeX == current_screen_sizeX
		and state.mp_screen_sizeY == current_screen_sizeY) then

		request_init_resize()

		state.mp_screen_sizeX = current_screen_sizeX
		state.mp_screen_sizeY = current_screen_sizeY
	end

	-- init management
	if state.active_element then
		-- mouse is held down on some element - keep ticking and igore initReq
		-- till it's released, or else the mouse-up (click) will misbehave or
		-- get ignored. that's because osc_init() recreates the osc elements,
		-- but mouse handling depends on the elements staying unmodified
		-- between mouse-down and mouse-up (using the index active_element).
		request_tick()
	elseif state.initREQ then
		osc_init()
		state.initREQ = false

		-- store initial mouse position
		if (state.last_mouseX == nil or state.last_mouseY == nil)
			and not (mouseX == nil or mouseY == nil) then

			state.last_mouseX, state.last_mouseY = mouseX, mouseY
		end
	end

	-- fade animation
	if not(state.anitype == nil) then

		if (state.anistart == nil) then
			state.anistart = now
		end

		if (now < state.anistart + (get_fadeduration()/1000)) then
			if (state.anitype == "in") then --fade in
				osc_visible(true)
				state.animation = scale_value(state.anistart,
					(state.anistart + (get_fadeduration()/1000)),
					255, 0, now)
			elseif (state.anitype == "out") then --fade out
				state.animation = scale_value(state.anistart,
					(state.anistart + (get_fadeduration()/1000)),
					0, 255, now)
			end
		else
			if (state.anitype == "out") then
				osc_visible(false)
			end
			kill_animation()
		end
	else
		kill_animation()
	end

	-- mouse show/hide area
	for k,cords in pairs(osc_param.areas["showhide"]) do
		set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide")
	end
	if osc_param.areas["showhide_wc"] then
		for k,cords in pairs(osc_param.areas["showhide_wc"]) do
			set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide_wc")
		end
	else
		set_virt_mouse_area(0, 0, 0, 0, "showhide_wc")
	end
	do_enable_keybindings()

	-- mouse input area
	local mouse_over_osc = false

	for _,cords in ipairs(osc_param.areas["input"]) do
		if state.osc_visible then -- activate only when OSC is actually visible
			set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "input")
		end
		if state.osc_visible ~= state.input_enabled then
			if state.osc_visible then
				mp.enable_key_bindings("input")
			else
				mp.disable_key_bindings("input")
			end
			state.input_enabled = state.osc_visible
		end

		if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
			mouse_over_osc = true
		end
	end

	if osc_param.areas["window-controls"] then
		for _,cords in ipairs(osc_param.areas["window-controls"]) do
			if state.osc_visible then -- activate only when OSC is actually visible
				set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "window-controls")
				mp.enable_key_bindings("window-controls")
			else
				mp.disable_key_bindings("window-controls")
			end

			if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
				mouse_over_osc = true
			end
		end
	end

	-- autohide
	if not (state.showtime == nil) and (get_hidetimeout() >= 0) then
		local timeout = state.showtime + (get_hidetimeout()/1000) - now
		if timeout <= 0 then
			if (state.active_element == nil) and not (mouse_over_osc) then
				hide_osc()
			end
		else
			-- the timer is only used to recheck the state and to possibly run
			-- the code above again
			if not state.hide_timer then
				state.hide_timer = mp.add_timeout(0, tick)
			end
			state.hide_timer.timeout = timeout
			-- re-arm
			state.hide_timer:kill()
			state.hide_timer:resume()
		end
	end

	-- actual rendering
	local ass = assdraw.ass_new()

	-- Messages
	render_message(ass)

	-- actual OSC
	if state.osc_visible then
		render_elements(ass)
	else
		hide_thumbnail()
	end

	-- submit
	set_osd(osc_param.playresy * osc_param.display_aspect,
			osc_param.playresy, ass.text)
end

--
-- Event handling
--

local function element_has_action(element, action)
	return element and element.eventresponder and
		element.eventresponder[action]
end

function process_event(source, what)
	local action = string.format("%s%s", source,
		what and ("_" .. what) or "")

	if what == "down" or what == "press" then

		for n = 1, #elements do

			if mouse_hit(elements[n]) and
				elements[n].eventresponder and
				(elements[n].eventresponder[source .. "_up"] or
					elements[n].eventresponder[action]) then

				if what == "down" then
					state.active_element = n
					state.active_event_source = source
				end
				-- fire the down or press event if the element has one
				if element_has_action(elements[n], action) then
					elements[n].eventresponder[action](elements[n])
				end

			end
		end

	elseif what == "up" then

		if elements[state.active_element] then
			local n = state.active_element

			if n == 0 then
				--click on background (does not work)
			elseif element_has_action(elements[n], action) and
				mouse_hit(elements[n]) then

				elements[n].eventresponder[action](elements[n])
			end

			--reset active element
			if element_has_action(elements[n], "reset") then
				elements[n].eventresponder["reset"](elements[n])
			end

		end
		state.active_element = nil
		state.mouse_down_counter = 0

	elseif source == "mouse_move" then

		state.mouse_in_window = true
		
		local mouseX, mouseY = get_virt_mouse_pos()
		-- OSC hover Top / Bottom
		if (user_opts.minmousemove < 0) then
			if (mouseY >= (osc_param.playresy - user_opts.heightoscShowHidearea)) or (mouseY <= user_opts.heightwcShowHidearea)
			then
				show_osc()
			end
		-- OSC when mouse moves
		elseif (not ((state.last_mouseX == nil) or (state.last_mouseY == nil)) and
				((math.abs(mouseX - state.last_mouseX) >= user_opts.minmousemove)
					or (math.abs(mouseY - state.last_mouseY) >= user_opts.minmousemove))) then
			show_osc()
		end
		state.last_mouseX, state.last_mouseY = mouseX, mouseY

		local n = state.active_element
		if element_has_action(elements[n], action) then
			elements[n].eventresponder[action](elements[n])
		end
	end

	-- ensure rendering after any (mouse) event - icons could change etc
	request_tick()
end

-- called by mpv on every frame
function tick()
	if state.marginsREQ == true then
		state.marginsREQ = false
	end

	if (not state.enabled) then return end

	if (state.idle) then

		-- render idle message
		msg.trace("idle message")
		local icon_x, icon_y = 320 - 26, 140

		local ass = assdraw.ass_new()

		 if user_opts.idlescreen then
			ass:new_event()
			ass:pos(320, icon_y+65)
			ass:an(8)
			--ass:append("Drop files or URLs to play here.")
		end
		set_osd(640, 360, ass.text)

		if state.showhide_enabled then
			mp.disable_key_bindings("showhide")
			mp.disable_key_bindings("showhide_wc")
			state.showhide_enabled = false
		end

	elseif (state.fullscreen and user_opts.showfullscreen)
		or (not state.fullscreen and user_opts.showwindowed) then

		-- render the OSC
		render()
	else
		-- Flush OSD
		render_wipe()
	end

	state.tick_last_time = mp.get_time()

	if state.anitype ~= nil then
		-- state.anistart can be nil - animation should now start, or it can
		-- be a timestamp when it started. state.idle has no animation.
		if not state.idle and
		   (not state.anistart or
			mp.get_time() < 1 + state.anistart + get_fadeduration()/1000)
		then
			-- animating or starting, or still within 1s past the deadline
			request_tick()
		else
			kill_animation()
		end
	end
end

function do_enable_keybindings()
	if state.enabled then
		if not state.showhide_enabled then
			mp.enable_key_bindings("showhide", "allow-vo-dragging+allow-hide-cursor")
			mp.enable_key_bindings("showhide_wc", "allow-vo-dragging+allow-hide-cursor")
		end
		state.showhide_enabled = true
	end
end

function enable_osc(enable)
	state.enabled = enable
	if enable then
		do_enable_keybindings()
	else
		hide_osc() -- acts immediately when state.enabled == false
		if state.showhide_enabled then
			mp.disable_key_bindings("showhide")
			mp.disable_key_bindings("showhide_wc")
		end
		state.showhide_enabled = false
	end
end

-- duration is observed for the sole purpose of updating chapter markers
-- positions. live streams with chapters are very rare, and the update is also
-- expensive (with request_init), so it's only observed when we have chapters
-- and the user didn't disable the livemarkers option (update_duration_watch).
function on_duration() request_init() end

local duration_watched = false
function update_duration_watch()
	local want_watch = user_opts.livemarkers and
					   (mp.get_property_number("chapters", 0) or 0) > 0 and
					   true or false  -- ensure it's a boolean

	if (want_watch ~= duration_watched) then
		if want_watch then
			mp.observe_property("duration", nil, on_duration)
		else
			mp.unobserve_property(on_duration)
		end
		duration_watched = want_watch
	end
end

validate_user_opts()
update_duration_watch()

local function set_tick_delay(_, display_fps)
	-- may be nil if unavailable or 0 fps is reported
	if not display_fps or not user_opts.tick_delay_follow_display_fps then
		tick_delay = user_opts.tick_delay
		return
	end
	tick_delay = 1 / display_fps
end

-- Save params on exit
function shutdown()
	save_file()
end

mp.register_event("shutdown", shutdown)
mp.register_event("start-file", request_init)
if user_opts.showonstart then mp.register_event("file-loaded", show_osc) end
if user_opts.showonseek then mp.register_event("seek", show_osc) end

mp.observe_property("track-list", nil, request_init)
mp.observe_property("playlist", nil, request_init)
mp.observe_property("chapter-list", "native", function(_, list)
	list = list or {}  -- safety, shouldn't return nil
	table.sort(list, function(a, b) return a.time < b.time end)
	state.chapter_list = list
	update_duration_watch()
	request_init()
end)

mp.register_script_message("osc-message", show_message)
mp.register_script_message("osc-chapterlist", function(dur)
	show_message(get_chapterlist(), dur)
end)
mp.register_script_message("osc-playlist", function(dur)
	show_message(get_playlist(), dur)
end)
mp.register_script_message("osc-tracklist", function(dur)
	local msg = {}
	for k,v in pairs(nicetypes) do
		table.insert(msg, get_tracklist(k))
	end
	show_message(table.concat(msg, "\n\n"), dur)
end)

mp.observe_property("fullscreen", "bool", function(_, val)
	state.fullscreen = val
	state.marginsREQ = true
	request_init_resize()
end)
mp.observe_property("border", "bool", function(_, val)
	state.border = val
	request_init_resize()
end)
mp.observe_property("window-maximized", "bool", function(_, val)
	state.maximized = val
	request_init_resize()
end)
mp.observe_property("idle-active", "bool", function(_, val)
	state.idle = val
	request_tick()
end)

mp.observe_property("display-fps", "number", set_tick_delay)
mp.observe_property("pause", "bool", pause_state)
mp.observe_property("demuxer-cache-state", "native", cache_state)
mp.observe_property("vo-configured", "bool", function(name, val)
	request_tick()
end)
mp.observe_property("playback-time", "number", function(name, val)
	request_tick()
end)
mp.observe_property("osd-dimensions", "native", function(name, val)
	-- (we could use the value instead of re-querying it all the time, but then
	--  we might have to worry about property update ordering)
	request_init_resize()
end)

-- OnTop while playing
-- https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/ontop-playback.lua

mp.observe_property("pause", "bool", function(_, value)
	if user_opts.onTopWhilePlaying then
		local ontop = mp.get_property_native("ontop")
		if value then
			if ontop then
				mp.set_property_native("ontop", false)
				was_ontop = true
			end
		else
			if not ontop then
				mp.set_property_native("ontop", true) 
			end
		end
	end
end)

-- mouse show/hide bindings
mp.set_key_bindings({
	{"mouse_move",			function(e) process_event("mouse_move", nil) end},
	{"mouse_leave",			mouse_leave},
}, "showhide", "force")
mp.set_key_bindings({
	{"mouse_move",			function(e) process_event("mouse_move", nil) end},
	{"mouse_leave",			mouse_leave},
}, "showhide_wc", "force")
do_enable_keybindings()

--mouse input bindings
mp.set_key_bindings({
	{"mbtn_left",			function(e) process_event("mbtn_left", "up") end,
							function(e) process_event("mbtn_left", "down")  end},
	{"shift+mbtn_left",		function(e) process_event("shift+mbtn_left", "up") end,
							function(e) process_event("shift+mbtn_left", "down")  end},
	{"mbtn_right",			function(e) process_event("mbtn_right", "up") end,
							function(e) process_event("mbtn_right", "down")  end},
	-- alias to shift_mbtn_left for single-handed mouse use
	{"mbtn_mid",			function(e) process_event("shift+mbtn_left", "up") end,
							function(e) process_event("shift+mbtn_left", "down")  end},
	{"wheel_up",			function(e) process_event("wheel_up", "press") end},
	{"wheel_down",			function(e) process_event("wheel_down", "press") end},
	{"shift+wheel_up",		function(e) process_event("shift+wheel_up", "press") end},
	{"shift+wheel_down",	function(e) process_event("shift+wheel_down", "press") end},
	{"mbtn_left_dbl", 		"ignore"},
	{"shift+mbtn_left_dbl",	"ignore"},
	{"mbtn_right_dbl",		"ignore"},
}, "input", "force")
mp.enable_key_bindings("input")

mp.set_key_bindings({
	{"mbtn_left",			function(e) process_event("mbtn_left", "up") end,
							function(e) process_event("mbtn_left", "down")  end},
}, "window-controls", "force")
mp.enable_key_bindings("window-controls")

function get_hidetimeout()
	if user_opts.visibility == "always" then
		return -1 -- disable autohide
	end
	if user_opts.minmousemove < 0 then
		return user_opts.hidetimeout
	else
		return user_opts.hidetimeoutMouseMove
	end
end

function get_fadeduration()
	if user_opts.minmousemove < 0 then
		return user_opts.fadeduration
	else
		return user_opts.fadedurationMouseMove
	end
end

function always_on(val)
	if state.enabled then
		if val then
			show_osc()
		else
			hide_osc()
		end
	end
end

-- mode can be auto/always/never/cycle
-- the modes only affect internal variables and not stored on its own.
function visibility_mode(mode, no_osd)
	if mode == "cycle" then
		if not state.enabled then
			mode = "auto"
		elseif user_opts.visibility ~= "always" then
			mode = "always"
		else
			mode = "never"
		end
	end

	if mode == "auto" then
		always_on(false)
		enable_osc(true)
	elseif mode == "always" then
		enable_osc(true)
		always_on(true)
	elseif mode == "never" then
		enable_osc(false)
	else
		msg.warn("Ignoring unknown visibility mode '" .. mode .. "'")
		return
	end

	user_opts.visibility = mode

	-- Reset the input state on a mode change. The input state will be
	-- recalculated on the next render cycle, except in 'never' mode where it
	-- will just stay disabled.
	mp.disable_key_bindings("input")
	mp.disable_key_bindings("window-controls")
	state.input_enabled = false

	request_tick()
end

function idlescreen_visibility(mode, no_osd)
	if mode == "cycle" then
		if user_opts.idlescreen then
			mode = "no"
		else
			mode = "yes"
		end
	end

	if mode == "yes" then
		user_opts.idlescreen = true
	else
		user_opts.idlescreen = false
	end

	if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
		mp.osd_message("OSC logo visibility: " .. tostring(mode))
	end

	request_tick()
end

visibility_mode(user_opts.visibility, true)
mp.register_script_message("osc-visibility", visibility_mode)
mp.register_script_message("osc-show", show_osc)
mp.add_key_binding(nil, "visibility", function() visibility_mode("cycle") end)

mp.register_script_message("osc-idlescreen", idlescreen_visibility)

mp.register_script_message("thumbfast-info", function(json)
	local data = utils.parse_json(json)
	if type(data) ~= "table" or not data.width or not data.height then
		msg.error("thumbfast-info: received json didn't produce a table with thumbnail information")
	else
		thumbfast = data
		mp.command_native({"script-message", message.osc.finish, format_json(osc_reg)})
	end
end)

set_virt_mouse_area(0, 0, 0, 0, "input")
set_virt_mouse_area(0, 0, 0, 0, "window-controls")
