obs           = obslua
source_name   = ""

stop_text     = ""
mode          = ""
a_mode        = ""
format        = ""
activated     = false
global        = false
timer_active  = false
settings_     = nil
orig_time     = 0
cur_time      = 0
cur_ns        = 0
up_when_finished = false
up            = false
paused        = false

hotkey_id_reset     = obs.OBS_INVALID_HOTKEY_ID
hotkey_id_pause     = obs.OBS_INVALID_HOTKEY_ID

function delta_time(year, month, day, hour, minute, second)
	local now = os.time()

	if (year == -1) then
		year = os.date("%Y", now)
	end

	if (month == -1) then
		month = os.date("%m", now)
	end

	if (day == -1) then
		day = os.date("%d", now)
	end

	local future = os.time{year=year, month=month, day=day, hour=hour, min=minute, sec=second}
	local seconds = os.difftime(future, now)

	if (seconds < 0) then
		seconds = seconds + 84600
	end

	return seconds * 1000000000
end

function set_time_text(ns, text)
    local ms = math.floor(ns / 1000000) -- Convert nanoseconds to milliseconds
    local total_seconds = math.floor(ms / 1000)

    -- Calculate individual time components
    local days = math.floor(total_seconds / 86400)
    local hours = math.floor((total_seconds % 86400) / 3600)
    local minutes = math.floor((total_seconds % 3600) / 60)
    local seconds = total_seconds % 60

    -- Replace placeholders in the format string
    if string.match(text, "%%d") then
        text = string.gsub(text, "%%d", tostring(days))
    end

    if string.match(text, "%%0h") then
        text = string.gsub(text, "%%0h", string.format("%02d", hours))
    end

    if string.match(text, "%%h") then
        text = string.gsub(text, "%%h", tostring(hours))
    end

    if string.match(text, "%%0m") then
        text = string.gsub(text, "%%0m", string.format("%02d", minutes))
    end

    if string.match(text, "%%m") then
        text = string.gsub(text, "%%m", tostring(minutes))
    end

    if string.match(text, "%%0s") then
        text = string.gsub(text, "%%0s", string.format("%02d", seconds))
    end

    if string.match(text, "%%s") then
        text = string.gsub(text, "%%s", tostring(seconds))
    end

    local source = obs.obs_get_source_by_name(source_name)
    if source ~= nil then
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", text)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)
    end
end


function script_tick(sec)
	if timer_active == false then
		return
	end

	local delta = obs.os_gettime_ns() - orig_time

	if mode == "Countup" or mode == "Streaming timer" or mode == "Recording timer" or up == true then
		cur_ns = cur_time + delta
	else
		cur_ns = cur_time - delta
	end

	if cur_ns < 1 and (mode == "Countdown" or mode == "Specific time" or mode == "Specific date and time") then
		if up_when_finished == false then
			set_time_text(cur_ns, stop_text)
			stop_timer()
			return
		else
			cur_time = 0
			up = true
			start_timer()
			return
		end
	end

	set_time_text(cur_ns, format)
end

function start_timer()
	timer_active = true
	orig_time = obs.os_gettime_ns()
end

function stop_timer()
	timer_active = false
end

function on_event(event)
	if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
		if mode == "Streaming timer" then
			cur_time = 0
			stop_timer()
			start_timer()
		end
	elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
		if mode == "Streaming timer" then
			stop_timer()
		end
	elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
		if mode == "Recording timer" then
			cur_time = 0
			stop_timer()
			start_timer()
		end
	elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
		if mode == "Recording timer" then
			stop_timer()
		end
	end
end

function activate(activating)
	if activated == activating then
		return
	end

	if (mode == "Streaming timer" or mode == "Recording timer") then
		return
	end

	activated = activating

	if activating then
		if global then
			return
		end

		script_update(settings_)
	end
end

function activate_signal(cd, activating)
	local source = obs.calldata_source(cd, "source")
	if source ~= nil then
		local name = obs.obs_source_get_name(source)
		if (name == source_name) then
			activate(activating)
		end
	end
end

function source_activated(cd)
	activate_signal(cd, true)
end

function source_deactivated(cd)
	activate_signal(cd, false)
end

function reset(pressed)
	if not pressed then
		return
	end

	if mode == "Streaming timer" or mode == "Recording timer" then
		return
	end

	script_update(settings_)
end

function on_pause(pressed)
	if not pressed then
		return
	end

	if mode == "Streaming timer" or mode == "Recording timer" then
		return
	end

	if cur_ns < 1 then
		reset(true)
	end

	if timer_active then
		stop_timer()
		cur_time = cur_ns
		paused = true
	else
		stop_timer()
		start_timer()
		paused = false
	end
end

function pause_button_clicked(props, p)
	on_pause(true)
	return true
end

function reset_button_clicked(props, p)
	reset(true)
	return true
end

function settings_modified(props, prop, settings)
	local mode_setting = obs.obs_data_get_string(settings, "mode")
	local p_duration = obs.obs_properties_get(props, "duration")
	local p_year = obs.obs_properties_get(props, "year")
	local p_month = obs.obs_properties_get(props, "month")
	local p_day = obs.obs_properties_get(props, "day")
	local p_hour = obs.obs_properties_get(props, "hour")
	local p_minutes = obs.obs_properties_get(props, "minutes")
	local p_seconds = obs.obs_properties_get(props, "seconds")
	local p_stop_text = obs.obs_properties_get(props, "stop_text")
	local p_a_mode = obs.obs_properties_get(props, "a_mode")
	local button_pause = obs.obs_properties_get(props, "pause_button")
	local button_reset = obs.obs_properties_get(props, "reset_button")
	local up_finished = obs.obs_properties_get(props, "countup_countdown_finished")

	if (mode_setting == "Countdown") then
		obs.obs_property_set_visible(p_duration, true)
		obs.obs_property_set_visible(p_year, false)
		obs.obs_property_set_visible(p_month, false)
		obs.obs_property_set_visible(p_day, false)
		obs.obs_property_set_visible(p_hour, false)
		obs.obs_property_set_visible(p_minutes, false)
		obs.obs_property_set_visible(p_seconds, false)
		obs.obs_property_set_visible(p_stop_text, true)
		obs.obs_property_set_visible(button_pause, true)
		obs.obs_property_set_visible(button_reset, true)
		obs.obs_property_set_visible(p_a_mode, true)
		obs.obs_property_set_visible(up_finished, true)
	elseif (mode_setting == "Countup") then
		obs.obs_property_set_visible(p_duration, false)
		obs.obs_property_set_visible(p_year, false)
		obs.obs_property_set_visible(p_month, false)
		obs.obs_property_set_visible(p_day, false)
		obs.obs_property_set_visible(p_hour, false)
		obs.obs_property_set_visible(p_minutes, false)
		obs.obs_property_set_visible(p_seconds, false)
		obs.obs_property_set_visible(p_stop_text, false)
		obs.obs_property_set_visible(button_pause, true)
		obs.obs_property_set_visible(button_reset, true)
		obs.obs_property_set_visible(p_a_mode, true)
		obs.obs_property_set_visible(up_finished, false)
	elseif (mode_setting == "Specific time") then
		obs.obs_property_set_visible(p_duration, false)
		obs.obs_property_set_visible(p_year, false)
		obs.obs_property_set_visible(p_month, false)
		obs.obs_property_set_visible(p_day, false)
		obs.obs_property_set_visible(p_hour, true)
		obs.obs_property_set_visible(p_minutes, true)
		obs.obs_property_set_visible(p_seconds, true)
		obs.obs_property_set_visible(p_stop_text, true)
		obs.obs_property_set_visible(button_pause, true)
		obs.obs_property_set_visible(button_reset, true)
		obs.obs_property_set_visible(p_a_mode, true)
		obs.obs_property_set_visible(up_finished, true)
	elseif (mode_setting == "Specific date and time") then
		obs.obs_property_set_visible(p_duration, false)
		obs.obs_property_set_visible(p_year, true)
		obs.obs_property_set_visible(p_month, true)
		obs.obs_property_set_visible(p_day, true)
		obs.obs_property_set_visible(p_hour, true)
		obs.obs_property_set_visible(p_minutes, true)
		obs.obs_property_set_visible(p_seconds, true)
		obs.obs_property_set_visible(p_stop_text, true)
		obs.obs_property_set_visible(button_pause, true)
		obs.obs_property_set_visible(button_reset, true)
		obs.obs_property_set_visible(p_a_mode, true)
		obs.obs_property_set_visible(up_finished, true)
	elseif (mode_setting == "Streaming timer") then
		obs.obs_property_set_visible(p_duration, false)
		obs.obs_property_set_visible(p_year, false)
		obs.obs_property_set_visible(p_month, false)
		obs.obs_property_set_visible(p_day, false)
		obs.obs_property_set_visible(p_hour, false)
		obs.obs_property_set_visible(p_minutes, false)
		obs.obs_property_set_visible(p_seconds, false)
		obs.obs_property_set_visible(p_stop_text, false)
		obs.obs_property_set_visible(button_pause, false)
		obs.obs_property_set_visible(button_reset, false)
		obs.obs_property_set_visible(p_a_mode, false)
		obs.obs_property_set_visible(up_finished, false)
	elseif (mode_setting == "Recording timer") then
		obs.obs_property_set_visible(p_duration, false)
		obs.obs_property_set_visible(p_year, false)
		obs.obs_property_set_visible(p_month, false)
		obs.obs_property_set_visible(p_day, false)
		obs.obs_property_set_visible(p_hour, false)
		obs.obs_property_set_visible(p_minutes, false)
		obs.obs_property_set_visible(p_seconds, false)
		obs.obs_property_set_visible(p_stop_text, false)
		obs.obs_property_set_visible(button_pause, false)
		obs.obs_property_set_visible(button_reset, false)
		obs.obs_property_set_visible(p_a_mode, false)
		obs.obs_property_set_visible(up_finished, false)
	end

	return true
end

function script_properties()
	local props = obs.obs_properties_create()

	local p_mode = obs.obs_properties_add_list(props, "mode", "Mode", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	obs.obs_property_list_add_string(p_mode, "Countdown", "countdown")
	obs.obs_property_list_add_string(p_mode, "Countup", "countup")
	obs.obs_property_list_add_string(p_mode, "Specific time", "specific_time")
	obs.obs_property_list_add_string(p_mode, "Specific date and time", "specific_date_and_time")
	obs.obs_property_list_add_string(p_mode, "Streaming timer", "stream")
	obs.obs_property_list_add_string(p_mode, "Recording timer", "recording")
	obs.obs_property_set_modified_callback(p_mode, settings_modified)

	obs.obs_properties_add_int(props, "duration", "Countdown duration (seconds)", 1, 100000000, 1)
	obs.obs_properties_add_int(props, "year", "Year", 1971, 100000000, 1)
	obs.obs_properties_add_int(props, "month", "Month (1-12)", 1, 12, 1)
	obs.obs_properties_add_int(props, "day", "Day (1-31)", 1, 31, 1)
	obs.obs_properties_add_int(props, "hour", "Hour (0-24)", 0, 24, 1)
	obs.obs_properties_add_int(props, "minutes", "Minutes (0-59)", 0, 59, 1)
	obs.obs_properties_add_int(props, "seconds", "Seconds (0-59)", 0, 59, 1)
	obs.obs_properties_add_int(props, "start_day", "Start Days", 0, 365, 1)
	obs.obs_properties_add_int(props, "start_hour", "Start Hours", 0, 23, 1)
	obs.obs_properties_add_int(props, "start_minute", "Start Minutes", 0, 59, 1)
	obs.obs_properties_add_int(props, "start_second", "Start Seconds", 0, 59, 1)

	local f_prop = obs.obs_properties_add_text(props, "format", "Format", obs.OBS_TEXT_DEFAULT)
	obs.obs_property_set_long_description(f_prop, "%d - days\n%0h - hours with leading zero (00..23)\n%h - hours (0..23)\n%0H - hours with leading zero (00..infinity)\n%H - hours (0..infinity)\n%0m - minutes with leading zero (00..59)\n%m - minutes (0..59)\n%0M - minutes with leading zero (00..infinity)\n%M - minutes (0..infinity)\n%0s - seconds with leading zero (00..59)\n%s - seconds (0..59)\n%0S - seconds with leading zero (00..infinity)\n%S - seconds (0..infinity)\n%t - tenths\n%2t - hundredths\n%3t - thousandths")

	local p = obs.obs_properties_add_list(props, "source", "Text source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			source_id = obs.obs_source_get_unversioned_id(source)
			if source_id == "text_gdiplus" or source_id == "text_ft2_source" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(p, name, name)
			end
		end
	end
	obs.source_list_release(sources)

	obs.obs_properties_add_text(props, "stop_text", "Countdown final text", obs.OBS_TEXT_DEFAULT)

	local p_a_mode = obs.obs_properties_add_list(props, "a_mode", "Activation mode", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	obs.obs_property_list_add_string(p_a_mode, "Global (timer always active)", "global")
	obs.obs_property_list_add_string(p_a_mode, "Start timer on activation", "start_reset")
	obs.obs_properties_add_bool(props, "countup_countdown_finished", "Countup when done")

	obs.obs_properties_add_button(props, "pause_button", "Start/Stop", pause_button_clicked)
	obs.obs_properties_add_button(props, "reset_button", "Reset", reset_button_clicked)

	settings_modified(props, nil, settings_)

	return props
end

function script_description()
	return "Sets a text source to act as a timer with advanced options. Hotkeys can be set for starting/stopping and to the reset timer."
end

function script_update(settings)
    stop_timer()
    up = false

    mode = obs.obs_data_get_string(settings, "mode")
    a_mode = obs.obs_data_get_string(settings, "a_mode")
    source_name = obs.obs_data_get_string(settings, "source")
    stop_text = obs.obs_data_get_string(settings, "stop_text")
    format = obs.obs_data_get_string(settings, "format")
    up_when_finished = obs.obs_data_get_bool(settings, "countup_countdown_finished")

    -- Get custom start time
    local start_days = obs.obs_data_get_int(settings, "start_day")
    local start_hours = obs.obs_data_get_int(settings, "start_hour")
    local start_minutes = obs.obs_data_get_int(settings, "start_minute")
    local start_seconds = obs.obs_data_get_int(settings, "start_second")

    -- Convert custom start time to nanoseconds
    local start_time_ns = (start_days * 86400 * 1000000000) +
                      (start_hours * 3600 * 1000000000) +
                      (start_minutes * 60 * 1000000000) +
                      (start_seconds * 1000000000)


    if mode == "Countdown" then
        cur_time = obs.obs_data_get_int(settings, "duration") * 1000000000 + start_time_ns
    elseif mode == "Specific time" then
        cur_time = delta_time(-1, -1, -1, hour, minute, second) + start_time_ns
    elseif mode == "Specific date and time" then
        cur_time = delta_time(year, month, day, hour, minute, second) + start_time_ns
    else
        cur_time = start_time_ns -- Use the starting point directly for other modes
    end

    global = a_mode == "Global (timer always active)"
    if mode == "Streaming timer" or mode == "Recording timer" then
        global = true
    end

    set_time_text(cur_time, format)
    if global == false and paused == false then
        start_timer()
    end
end


function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "duration", 5)
	obs.obs_data_set_default_int(settings, "year", os.date("%Y", os.time()))
	obs.obs_data_set_default_int(settings, "month", os.date("%m", os.time()))
	obs.obs_data_set_default_int(settings, "day", os.date("%d", os.time()))
	obs.obs_data_set_default_int(settings, "start_day", 0)
	obs.obs_data_set_default_int(settings, "start_hour", 0)
	obs.obs_data_set_default_int(settings, "start_minute", 0)
	obs.obs_data_set_default_int(settings, "start_second", 0)

	obs.obs_data_set_default_string(settings, "stop_text", "Starting soon (tm)")
	obs.obs_data_set_default_string(settings, "mode", "Countdown")
	obs.obs_data_set_default_string(settings, "a_mode", "Global (timer always active)")
	obs.obs_data_set_default_string(settings, "format", "%0H:%0m:%0s")
end

function script_save(settings)
	local hotkey_save_array_reset = obs.obs_hotkey_save(hotkey_id_reset)
	local hotkey_save_array_pause = obs.obs_hotkey_save(hotkey_id_pause)
	obs.obs_data_set_array(settings, "reset_hotkey", hotkey_save_array_reset)
	obs.obs_data_set_array(settings, "pause_hotkey", hotkey_save_array_pause)
	obs.obs_data_array_release(hotkey_save_array_pause)
	obs.obs_data_array_release(hotkey_save_array_reset)
end

function script_load(settings)
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_show", source_activated)
	obs.signal_handler_connect(sh, "source_hide", source_deactivated)

	hotkey_id_reset = obs.obs_hotkey_register_frontend("reset_timer_thingy", "Reset Timer", reset)
	hotkey_id_pause = obs.obs_hotkey_register_frontend("pause_timer", "Start/Stop Timer", on_pause)
	local hotkey_save_array_reset = obs.obs_data_get_array(settings, "reset_hotkey")
	local hotkey_save_array_pause = obs.obs_data_get_array(settings, "pause_hotkey")
	obs.obs_hotkey_load(hotkey_id_reset, hotkey_save_array_reset)
	obs.obs_hotkey_load(hotkey_id_pause, hotkey_save_array_pause)
	obs.obs_data_array_release(hotkey_save_array_reset)
	obs.obs_data_array_release(hotkey_save_array_pause)

	obs.obs_frontend_add_event_callback(on_event)

	settings_ = settings

	script_update(settings)
end
