--[[

快捷指令增强

input.conf 示例：

 Ctrl+a               script-binding input_plus/adevice_back        # 上一个音频输出设备
#                     script-binding input_plus/adevice_next        # 下...
#                     script-binding input_plus/adevice_all_back    # 上...（包括不属于当前 --ao 的设备）
#                     script-binding input_plus/adevice_all_next    # 下...

#                     script-binding input_plus/chap_skip_toggle    # 启用/禁用强制自动跳过章节（片头片尾）

#                     script-binding input_plus/info_toggle         # 启用/禁用仿Pot的OSD常驻显示简要信息

 Ctrl+v               script-binding input_plus/load_cbd            # 加载剪贴板地址
#                     script-binding input_plus/load_cbd_add        # ...（追加到列表）
#                     script-binding input_plus/load_cbd_alt        # 加载主缓冲区地址（仅Linux可用）
#                     script-binding input_plus/load_cbd_alt_add    # ...（追加到列表）

#                     script-binding input_plus/mark_aid_A          # 标记当前音轨为A
#                     script-binding input_plus/mark_aid_B          # 标记当前音轨为B
#                     script-binding input_plus/mark_aid_merge      # 合并AB音轨
#                     script-binding input_plus/mark_aid_reset      # 取消AB并轨和标记
 m                    script-binding input_plus/mark_aid_fin        # （单键实现上述四项命令）

#                     script-binding input_plus/ostime_display      # 临时显示系统时间
#                     script-binding input_plus/ostime_toggle       # 启用/禁用显示系统时间

#                     script-binding input_plus/pip_dummy           # 画中画（伪）/小窗化

 Alt+p                script-binding input_plus/playlist_order_0    # 播放列表的洗牌与撤销
#                     script-binding input_plus/playlist_order_0r   # ...（重定向至首个文件）
#                     script-binding input_plus/playlist_order_1    # 播放列表连续洗牌（可用上两项命令恢复）
#                     script-binding input_plus/playlist_order_1r   # ...
#                     script-binding input_plus/playlist_tmp_save   # 保存当前播放列表为临时列表（位于主设置目录 playlist_temp.mpl ）
#                     script-binding input_plus/playlist_tmp_load   # 打开临时播放列表

 CLOSE_WIN            script-binding input_plus/quit_real           # 对执行退出命令前的确认（防止误触）
#                     script-binding input_plus/quit_wait           # 延后退出命令的执行（执行前再次触发可取消）

#                     script-binding input_plus/sids_sec_swap       # 双字幕的主次交换

 b                    script-binding input_plus/speed_auto          # [按住/松开] 两倍速/一倍速
#                     script-binding input_plus/speed_auto_bullet   # [按住/松开] 子弹时间/一倍速
#                     script-binding input_plus/speed_recover       # 仿Pot的速度重置与恢复
#                     script-binding input_plus/speed_sync_toggle   # 启用/禁用自适应速度偏移（补偿显示刷新率）

#                     script-binding input_plus/stats_1_2           # 单键浏览统计数据第1至2页
#                     script-binding input_plus/stats_0_4           # 单键浏览统计数据第0至4页

#                     script-binding input_plus/trackA_back         # 上一个音频轨道（自动跳过无轨道）
#                     script-binding input_plus/trackA_next         # 下...
#                     script-binding input_plus/trackS_back         # 上一个字幕轨道...
#                     script-binding input_plus/trackS_next         # 下...
#                     script-binding input_plus/trackV_back         # 上一个视频轨道...
#                     script-binding input_plus/trackV_next         # 下...

#                     script-binding input_plus/trackA_refresh      # 刷新当前轨道（音频）
#                     script-binding input_plus/trackS_refresh      # ...（字幕）
#                     script-binding input_plus/trackV_refresh      # ...（视频）


#                     script-message-to input_plus cycle-cmds "cmd1" "cmd2"   # 循环触发命令

]]


local utils = require("mp.utils")

function check_plat()
	if mp.get_property_native("platform") == "windows" then
		return "windows"
	elseif string.sub((os.getenv("HOME")), 1, 6) == "/Users" then
		return "macos"
	elseif os.getenv("WAYLAND_DISPLAY") then
		return "wayland"
	end
	return "x11"
end
local plat = check_plat()

function lock_prop(prop_c, type_c, value_c, prop_l, value_l)
	mp.observe_property(prop_c, type_c, function(_, value)
		if value == value_c then
			mp.set_property(prop_l, value_l)
		end
	end)
end



--
-- 变量预设
--

local adevicelist = {}
local target_ao = nil

local chap_skip = false
local chap_keywords = { 
	"OP$", "opening$", "オープニング$",
	"ED$", "ending$", "エンディング$",
}

local cmds_sqnum = {}

local osm = mp.create_osd_overlay("ass-events")
local osm_showing = false
local style_generic = "{\\rDefault\\fnConsolas\\fs20\\blur1\\bord2\\1c&HFFFFFF\\3c&H000000}"

local text_pasted = nil

local marked_aid_A = nil
local marked_aid_B = nil
local merged_aid = false

local ostime_msg = mp.create_osd_overlay("ass-events")
local ostime_showing = false
local ostime_style = "{\\rDefault\\fnmpv-osd-symbols\\fs30\\bord2\\an9\\alpha&H80\\1c&H01DBF1\\3c&H000000}"

local shuffled = false
local shuffling = false
local save_path = mp.command_native({"expand-path", "~~/"}) .. "/playlist_temp.mpl"

local pre_quit = false

local bak_speed = nil
local spd_adapt = false
local spd_iters_max = 10
local spd_delta_max = 0.5
local spd_delta_min = 0.0005

local show_page = 0



--
-- 函数设定
--

function adevicelist_pre(start)
	mp.set_property("audio-device", adevicelist[start].name)
	adevicelist[start].description = "■ " .. adevicelist[start].description
	local adevice_content = tostring("音频输出设备：\n")
	for items = 1, #adevicelist do
		if string.find(adevicelist[items].name, target_ao, 1, true) then
			if adevicelist[items].name ~= adevicelist[start].name then
				adevice_content = adevice_content .. "□ "
			end
			adevice_content = adevice_content .. adevicelist[items].description .. "\n"
		end
	end
	mp.osd_message(adevice_content, 2)
end
function adevicelist_pass(start, fin, step)
	while start ~= fin + step do
		if string.find(mp.get_property_native("audio-device"), adevicelist[start].name, 1, true) then
			while true do
				if start + step == 0 then
					start = #adevicelist + 1
				elseif start + step == #adevicelist + 1 then
					start = 0
				end
				start = start + step
				if string.find(adevicelist[start].name, target_ao, 1, true) then
					adevicelist_pre(start)
					return
				end
			end
		end
		start = start + step
	end
end
function adevicelist_fin(start, fin, step, dynamic)
	if dynamic then
		target_ao = ""
	else
		target_ao = mp.get_property_native("current-ao", "")
	end
	adevicelist_pass(start, fin, step)
end


function chap_skip_toggle()
	if chap_skip then
		chap_skip = false
		mp.osd_message("已禁用跳过片头片尾", 1)
		return
	end
	chap_skip = true
	mp.osd_message("已启用跳过片头片尾", 1)
end
function chapter_change(_, value)
	if not value then
		return
	end
	for _, words in pairs(chap_keywords) do
		if string.match(value, words) and chap_skip then
			mp.commandv("add", "chapter", 1)
		end
	end
end


function cycle_cmds(...)
	local cmds_list = {...}
	local cur_cmd = table.concat(cmds_list, "|")
	cmds_sqnum[cur_cmd] = (cmds_sqnum[cur_cmd] or 0) % #cmds_list + 1
	mp.command(cmds_list[cmds_sqnum[cur_cmd]])
end


function info_get()
	local conf_dir = mp.get_property_bool("config") and mp.command_native({"expand-path", "~~/"}) or "no"
	local osd_dims = mp.get_property_native("osd-dimensions")
	local w_s, h_s = osd_dims["w"] - osd_dims["ml"] - osd_dims["mr"], osd_dims["h"] - osd_dims["mt"] - osd_dims["mb"]
	local cur_name = mp.get_property_osd("media-title") or mp.get_property_osd("filename")
	local vid_params = mp.get_property_native("video-params") or "..."
	local w_raw, h_raw, pix_fmt, color_lv = vid_params["w"] or 0, vid_params["h"] or 0, vid_params["hw-pixelformat"] or vid_params["pixelformat"] or "...", vid_params["colorlevels"] or "..."
	local fps_o, fps_t = string.format("%0.3f", mp.get_property_number("container-fps", 0)), string.format("%0.3f", mp.get_property_number("estimated-vf-fps", 0))
	local bitrateV, bitrateA = mp.get_property_number("video-bitrate", 0) / 1000, mp.get_property_number("audio-bitrate", 0) / 1000
	local txt = (
	style_generic.."设置目录： ".."{\\fs18\\1c&H0099FF}"..conf_dir:gsub("\\", "/").."\n"..
	style_generic.."输出尺寸： ".."{\\1c&H0099FF}".."["..w_s.."] x ["..h_s.."]".."\n"..
	style_generic.."解码模式： ".."{\\1c&H0099FF}"..mp.get_property_native("hwdec-current", "...").."\n"..
	style_generic.."显示同步： ".."{\\1c&H0099FF}"..mp.get_property_native("video-sync", "...").."\n"..
	style_generic.."丢帧暂计： ".."{\\1c&H0099FF}"..mp.get_property_number("frame-drop-count", 0).."\n"..
	style_generic.."当前文件： ".."{\\fs18\\1c&H0099FF}"..cur_name:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{").."\n"..
	style_generic.."视频 ┓".."\n"..
	style_generic.."-   输出： ".."{\\1c&H03A89E}"..mp.get_property_native("current-vo", "...").."\n"..
	style_generic.."-   编码： ".."{\\1c&H03A89E}"..mp.get_property_native("video-codec", "...").."\n"..
	style_generic.."-   尺寸： ".."{\\1c&H03A89E}".."["..w_raw.."] x ["..h_raw.."]".."\n"..
	style_generic.."-   像素： ".."{\\1c&H03A89E}"..pix_fmt.."\n"..
	style_generic.."-   动态： ".."{\\1c&H03A89E}"..color_lv.."\n"..
	style_generic.."-   帧率： ".."{\\1c&H03A89E}"..fps_o.." FPS（原始） "..fps_t.." FPS（目标）".."\n"..
	style_generic.."-   码率： ".."{\\1c&H03A89E}"..bitrateV.." kbps（当前）".."\n"..
	style_generic.."音频 ┓".."\n"..
	style_generic.."-   输出： ".."{\\1c&H9EA803}"..mp.get_property_native("current-ao", "...").."【设备】"..mp.get_property_native("audio-device", "...").."\n"..
	style_generic.."-   编码： ".."{\\1c&H9EA803}"..mp.get_property_native("audio-codec", "...").."\n"..
	style_generic.."-   码率： ".."{\\1c&H9EA803}"..bitrateA.." kbps（当前）".."\n"..
	style_generic.."着色器列： ".."{\\fs18\\1c&HFF8821}"..mp.get_property_osd("glsl-shaders"):gsub(":\\", "/"):gsub(":/", "/"):gsub("\\", "/"):gsub(";", " "):gsub(",", " "):gsub(":", " ").."\n"..
	style_generic.."视频滤镜： ".."{\\fs18\\1c&HFF8821}"..mp.get_property_osd("vf"):gsub("%(empty%)", ""):gsub(" %[", "%["):gsub("%]\n", "%] "):gsub(" %(disabled%)", "（禁用）").."\n"..
	style_generic.."音频滤镜： ".."{\\fs18\\1c&HFF8821}"..mp.get_property_osd("af"):gsub("%(empty%)", ""):gsub(" %[", "%["):gsub("%]\n", "%] "):gsub(" %(disabled%)", "（禁用）")
	)
	return tostring(txt)
end
function info_toggle()
	if osm_showing then
		osm:remove()
		osm_timer:kill()
		osm_showing = false
		return
	end
	osm.data = info_get()
	osm:update()
	osm_showing = true
	osm_timer = mp.add_periodic_timer(0.5, function()
		if not osm_showing then
			osm_timer:kill()
		else
			osm.data = info_get()
			osm:update()
		end
	end)
end


function copy_clipboard(clip)
	if plat == "windows" then
		local res = utils.subprocess({
			args = { 'powershell', '-NoProfile', '-Command', [[& {
				Trap {
					Write-Error -ErrorRecord $_
					Exit 1
				}
				$clip = ""
				if (Get-Command "Get-Clipboard" -errorAction SilentlyContinue) {
					$clip = Get-Clipboard -Raw -Format Text -TextFormatType UnicodeText
				} else {
					Add-Type -AssemblyName PresentationCore
					$clip = [Windows.Clipboard]::GetText()
				}
				$clip = $clip -Replace "`r",""
				$u8clip = [System.Text.Encoding]::UTF8.GetBytes($clip)
				[Console]::OpenStandardOutput().Write($u8clip, 0, $u8clip.Length)
			}]] },
			playback_only = false,
		})
		if not res.error then
			return res.stdout
		end
	elseif plat == "macos" then
		local res = utils.subprocess({args = { 'pbpaste' }, playback_only = false,})
		if not res.error then
			return res.stdout
		end
	elseif plat == "x11" then
		local res = utils.subprocess({args = { 'xclip', '-selection', clip and 'clipboard' or 'primary', '-out' }, playback_only = false,})
		if not res.error then
			return res.stdout
		end
	elseif plat == "wayland" then
		local res = utils.subprocess({args = { 'wl-paste', clip and '-n' or  '-np' }, playback_only = false,})
		if not res.error then
			return res.stdout
		end
	end
	return ""
end
function load_clipboard(action, clip)
	if not clip and (plat == "windows" or plat == "macos") then
		return
	end
	local text = copy_clipboard(clip):gsub("^%s*", ""):gsub("%s*$", "")
	if text == text_pasted and action == "replace" then
		mp.osd_message("剪贴板内容无变动", 1)
		return
	end
	mp.commandv("loadfile", text, action)
	text_pasted = text
end


function mark_aid_A()
	marked_aid_A = mp.get_property_number("aid", 0)
	if marked_aid_A == 0
	then
		mp.osd_message("当前音轨无效", 1)
		marked_aid_A = nil
	else
		mp.osd_message("预标记当前音轨序列 " .. marked_aid_A .. " 为并行轨A", 1)
	end
end
function mark_aid_B()
	marked_aid_B = mp.get_property_number("aid", 0)
	if marked_aid_B == 0
	then
		mp.osd_message("当前音轨无效", 1)
		marked_aid_B = nil
	else
		mp.osd_message("预标记当前音轨序列 " .. marked_aid_B .. " 为并行轨B", 1)
	end
end
function mark_aid_merge()
	if marked_aid_A == marked_aid_B or marked_aid_A == nil or marked_aid_B == nil
	then
		mp.osd_message("无效的AB音轨", 1)
		marked_aid_A, marked_aid_B = nil, nil
	else
		mp.command("set lavfi-complex \"[aid" .. marked_aid_A .. "] [aid" .. marked_aid_B .. "] amix [ao]\"")
		mp.osd_message("已合并AB音轨", 1)
		merged_aid = true
	end
end
function mark_aid_reset()
	mp.command("set lavfi-complex \"\"")
	merged_aid = false
	marked_aid_A, marked_aid_B = nil, nil
end
function mark_aid_fin()
	if merged_aid then
		mark_aid_reset()
		mp.osd_message("已取消并轨和标记", 1)
		mp.commandv("set", "aid", "auto")
		return
	end
	if marked_aid_A == nil then
		mark_aid_A()
		return
	end
	if marked_aid_B == nil then
		mark_aid_B()
		return
	end
	mark_aid_merge()
end


function draw_ostime()
	local ostime = os.date("*t")
	ostime_msg.data = ostime_style .. "\238\128\134 " .. string.format("%02d:%02d:%02d", ostime.hour, ostime.min, ostime.sec)
	ostime_msg:update()
end
function ostime_toggle()
	if ostime_showing then
		ostime_timer:kill()
		ostime_msg:remove()
		ostime_showing = false
	else
		ostime_timer = mp.add_periodic_timer(1, draw_ostime)
		ostime_showing = true
	end
end
function ostime_display()
	if ostime_showing then
		return
	end
	draw_ostime()
	mp.add_timeout(1, function()
		ostime_msg:remove()
		draw_ostime()
	end)
	mp.add_timeout(2, function()
		ostime_msg:remove()
	end)
end


function pip_dummy()
	if mp.get_property_native("idle-active") or not mp.get_property_native("vid") then
		mp.msg.warn("pip_dummy 无法在当前状态使用")
		return
	end
	local w_dp, h_dp = mp.get_property_number("display-width", 0), mp.get_property_number("display-height", 0)
	local w_vf, h_vf = mp.get_property_number("dwidth", 0), mp.get_property_number("dheight", 0)
	local scale_win = mp.get_property_number("current-window-scale", 0)
	local scale_shift = mp.get_property_number("display-hidpi-scale", 1)
	if w_dp == 0 or w_vf == 0 or scale_win == 0 then
		mp.msg.warn("pip_dummy 缺乏必要条件")
		return
	end
	local scale_target = tonumber(string.format("%.3f", math.sqrt((w_dp * h_dp * 0.10) / (w_vf * h_vf)) / scale_shift))
	mp.set_property_bool("fullscreen", false)
	mp.set_property_bool("border", false)
	mp.set_property_number("current-window-scale", scale_target)
	mp.set_property_bool("auto-window-resize", false)
	mp.set_property_bool("keepaspect-window", false)
	mp.set_property_bool("ontop", true)
	mp.msg.info("pip_dummy 已尝试应用")
end


function show_playlist_shuffle()
	mp.add_timeout(0.1, function()
		local shuffle_msg = mp.command_native({"expand-text", "${playlist}"})
		shuffling = false
		mp.osd_message(shuffle_msg, 2)
	end)
end
function playlist_order(mode, re)
	if shuffling then
		mp.msg.info("playlist_order 已阻止高频洗牌")
		return
	end
	if mp.get_property_number("playlist-count") <= 2 then
		mp.osd_message("播放列表中的条目数量不足", 1)
		return
	end
	shuffling = true
	if mode == 0 then
		if not shuffled then
			mp.command("playlist-shuffle")
			shuffled = true
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		else
			mp.command("playlist-unshuffle")
			shuffled = false
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		end
	elseif mode == 1 then
		if shuffled then
			mp.command("playlist-unshuffle")
			mp.command("playlist-shuffle")
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		else
			mp.command("playlist-shuffle")
			shuffled = true
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		end
	end
end
function playlist_tmp_save()
	local item_num = mp.get_property_number("playlist-count", 0)
	if item_num == 0 then
		mp.osd_message("播放列表中无文件", 1)
		return
	end
	local file, err = io.open(save_path, "w")
	file:write("#EXTM3U\n\n")
	local Nn = 0
	while Nn < item_num do
		local save_item = mp.get_property("playlist/"..Nn.."/filename")
		file:write(save_item, "\n")
		Nn = Nn+1
	end
	local save_info = tostring("已保存至临时播放列表")
	mp.osd_message(save_info, 1)
	mp.msg.info("playlist_tmp_save 主设置文件夹/playlist_temp.mpl")
	file:close()
end
function playlist_tmp_load()
	mp.commandv("loadlist", save_path, "replace")
	if mp.get_property_number("playlist-count", 0) == 0 then
		mp.osd_message("临时播放列表加载失败", 1)
	else
		mp.osd_message(mp.command_native({"expand-text", "${playlist}"}), 2)
	end
end


function quit_real()
	if pre_quit then
		mp.command("quit")
	else
		mp.osd_message("再次执行以确认退出", 1.5)
		pre_quit = true
		mp.add_timeout(1.5, function()
			pre_quit = false
			mp.msg.verbose("quit_real 检测到误触退出键")
		end)
	end
end
function quit_wait()
	if pre_quit then
		pre_quit = false
		return
	else
		pre_quit = true
		mp.osd_message("即将退出，再次执行以取消", 3)
		mp.add_timeout(3, function()
			if pre_quit then
				mp.command("quit")
			else
				mp.osd_message("已取消退出", 0.5)
				return
			end
		end)
	end
end


function sids_sec_swap()
	local sid_main = mp.get_property_number("sid", 0)
	local sid_sec = mp.get_property_number("secondary-sid", 0)
	if sid_main == 0 and sid_sec == 0 then
		return
	end
	mp.set_property_number("sid", 0)
	mp.set_property_number("secondary-sid", 0)
	mp.set_property_number("sid", sid_sec)
	mp.set_property_number("secondary-sid", sid_main)
end


function speed_auto(tab)
	if tab.event == "down" then
		mp.set_property_number("speed", 2)
		mp.msg.verbose("speed_auto 加速播放中")
	elseif tab.event == "up" then
		mp.set_property_number("speed", 1)
		mp.msg.verbose("speed_auto 已恢复常速")
	end
end
function speed_auto_bullet(tab)
	if tab.event == "down" then
		mp.set_property_number("speed", 0.5)
		mp.msg.verbose("speed_auto_bullet 子弹时间中")
	elseif tab.event == "up" then
		mp.set_property_number("speed", 1)
		mp.msg.verbose("speed_auto_bullet 已恢复常速")
	end
end
function speed_recover()
	if mp.get_property_number("speed") ~= 1 then
		bak_speed = mp.get_property_number("speed")
		mp.command("set speed 1")
	else
		if bak_speed == nil then
			bak_speed = 1
		end
		mp.command("set speed " .. bak_speed)
	end
end
function speed_scale(rat, fact)
	local spd_scale, spd_delta = nil, nil
	for _, i in ipairs({fact, fact-1, fact+1}) do
		spd_scale = rat * i / math.floor(i * rat + 0.5)
		spd_delta = math.abs(spd_scale - 1)
		if spd_delta < spd_delta_min then
			mp.msg.info("speed_sync_toggle 目标速度为1")
			return 1
		elseif spd_delta <= spd_delta_max then
			mp.msg.info("speed_sync_toggle 目标速度为" .. spd_scale)
			return spd_scale
		end
	end
end
function speed_adaptive()
	local fps_raw = mp.get_property_number("container-fps", 0)
	local fps_vf = mp.get_property_number("estimated-vf-fps", 0)
	local fps_dp = mp.get_property_number("display-fps", 0)
	local spd_cur = mp.get_property_number("speed", 1)
	if (fps_raw == 0 or fps_dp == 0 or fps_raw > 32 or math.abs(fps_vf - fps_raw) > 0.5) then
		mp.msg.warn("speed_sync_toggle 存在例外的FPS情况")
		return
	end
	for i = 1, spd_iters_max do
		local spd_target = speed_scale(fps_dp / fps_raw, i)
		if spd_target then
			if math.abs(spd_target - spd_cur) < 0.0001 then
				break
			else
				mp.set_property("speed", spd_target)
				mp.msg.info("speed_sync_toggle 设定当前速度为" .. spd_target)
				break
			end
		end
	end
end
function speed_sync_toggle()
	spd_adapt = not spd_adapt
	if spd_adapt then
		mp.osd_message("已启用速度自适应", 1)
		speed_adaptive()
	else
		mp.osd_message("已禁用速度自适应", 1)
		return
	end
end


function stats_cycle(num_init, num_end)
	if show_page < num_init then
		show_page = num_init - 1
	end
	if show_page >= num_end then
		show_page = num_init - 1
	end
	show_page = show_page + 1
	mp.command("script-binding display-page-" .. show_page)
end


function track_seek(id, num)
	mp.command("add " .. id .. " " .. num)
	if mp.get_property_number(id, 0) == 0 then
		mp.command("add " .. id .. " " .. num)
		if mp.get_property_number(id, 0) == 0 then
			mp.osd_message("无可用" .. id, 1)
		end
	end
end


function track_refresh(id)
	local current_id = mp.get_property_number(id, 0)
	if current_id == 0 then
		mp.msg.warn("track_refresh 当前" .. id .. "无效")
		return
	end
	mp.set_property_number(id, 0)
	mp.set_property_number(id, current_id)
end



--
-- 其它处理
--

mp.register_event("file-loaded", function() if chap_skip then mp.msg.info("chap_skip_toggle 当前文件正在使用") end end)
mp.observe_property("chapter-metadata/TITLE", "string", chapter_change)

mp.register_event("end-file", function() if marked_aid_A ~= nil or marked_aid_B ~= nil then mark_aid_reset() end end)

mp.register_event("playback-restart", function() if spd_adapt then speed_adaptive() end end)



--
-- 键位绑定
--

mp.add_key_binding(nil, "adevice_back", function() adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(#adevicelist, 1, -1) end)
mp.add_key_binding(nil, "adevice_next", function() adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(1, #adevicelist, 1) end)
mp.add_key_binding(nil, "adevice_all_back", function() adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(#adevicelist, 1, -1, true) end)
mp.add_key_binding(nil, "adevice_all_next", function() adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(1, #adevicelist, 1, true) end)

mp.add_key_binding(nil, "chap_skip_toggle", chap_skip_toggle)

mp.add_key_binding(nil, "info_toggle", info_toggle)

mp.add_key_binding(nil, "load_cbd", function() load_clipboard("replace", true) end)
mp.add_key_binding(nil, "load_cbd_alt", function() load_clipboard("replace") end)
mp.add_key_binding(nil, "load_cbd_add", function() load_clipboard("append-play", true) end)
mp.add_key_binding(nil, "load_cbd_alt_add", function() load_clipboard("append-play") end)

mp.add_key_binding(nil, "mark_aid_A", mark_aid_A)
mp.add_key_binding(nil, "mark_aid_B", mark_aid_B)
mp.add_key_binding(nil, "mark_aid_merge", mark_aid_merge)
mp.add_key_binding(nil, "mark_aid_reset", function() mark_aid_reset() mp.osd_message("已取消并轨和标记", 1) end)
mp.add_key_binding(nil, "mark_aid_fin", mark_aid_fin)

mp.add_key_binding(nil, "ostime_display", ostime_display)
mp.add_key_binding(nil, "ostime_toggle", ostime_toggle)

mp.add_key_binding(nil, "pip_dummy", pip_dummy)

mp.add_key_binding(nil, "playlist_order_0", function() playlist_order(0) end)
mp.add_key_binding(nil, "playlist_order_0r", function() playlist_order(0, true) end)
mp.add_key_binding(nil, "playlist_order_1", function() playlist_order(1) end)
mp.add_key_binding(nil, "playlist_order_1r", function() playlist_order(1, true) end)
mp.add_key_binding(nil, "playlist_tmp_save", playlist_tmp_save)
mp.add_key_binding(nil, "playlist_tmp_load", playlist_tmp_load)

mp.add_key_binding(nil, "quit_real", quit_real)
mp.add_key_binding(nil, "quit_wait", quit_wait)

mp.add_key_binding(nil, "sids_sec_swap", sids_sec_swap)

mp.add_key_binding(nil, "speed_auto", speed_auto, {complex = true})
mp.add_key_binding(nil, "speed_auto_bullet", speed_auto_bullet, {complex = true})
mp.add_key_binding(nil, "speed_recover", speed_recover)
mp.add_key_binding(nil, "speed_sync_toggle", speed_sync_toggle)

mp.add_key_binding(nil, "stats_1_2", function() stats_cycle(1, 2) end)
mp.add_key_binding(nil, "stats_0_4", function() stats_cycle(0, 4) end)

mp.add_key_binding(nil, "trackA_back", function() track_seek("aid", -1) end)
mp.add_key_binding(nil, "trackA_next", function() track_seek("aid", 1) end)
mp.add_key_binding(nil, "trackS_back", function() track_seek("sid", -1) end)
mp.add_key_binding(nil, "trackS_next", function() track_seek("sid", 1) end)
mp.add_key_binding(nil, "trackV_back", function() track_seek("vid", -1) end)
mp.add_key_binding(nil, "trackV_next", function() track_seek("vid", 1) end)

mp.add_key_binding(nil, "trackA_refresh", function() track_refresh("aid") end)
mp.add_key_binding(nil, "trackS_refresh", function() track_refresh("sid") end)
mp.add_key_binding(nil, "trackV_refresh", function() track_refresh("vid") end)

mp.register_script_message("cycle-cmds", cycle_cmds)
