--[[ WoW 1.14.2 (Classic, Lua 5.1) compatibility shim for this vanilla 1.12 addon ]]
do
    -- Removed/renamed string & math library functions
    if not strsub then strsub = string.sub end
    if not strlen then strlen = string.len end
    if not strfind then strfind = string.find end
    if not strupper then strupper = string.upper end
    if not strlower then strlower = string.lower end
    if not mod then mod = math.fmod end

    -- table.getn / getn
    if not table.getn then
        table.getn = function(t)
            local n = 0
            while t[n + 1] ~= nil do
                n = n + 1
            end
            return n
        end
    end
    if not getn then getn = table.getn end

    -- PlaySound: map removed vanilla sound names to SOUNDKIT constants
    if type(PlaySound) == "function" then
        local PLAY_SOUND_MAP = {
            UChatScrollButton             = SOUNDKIT and (SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_MAINMENU_OPEN),
            igMainMenuOptionCheckBoxOn    = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
            igMainMenuOptionCheckBoxOff   = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF,
            igCharacterInfoTab            = SOUNDKIT and SOUNDKIT.CHARACTER_INFO_TAB_SELECTED,
        }
        local originalPlaySound = PlaySound
        PlaySound = function(soundName, ...)
            if type(soundName) == "string" then
                local kit = PLAY_SOUND_MAP[soundName]
                if kit then
                    originalPlaySound(kit, ...)
                    return
                end
            end
            originalPlaySound(soundName, ...)
        end
    end
end

-- AchieverUtils = {}

-- AchieverUtils.split = function(str, sep)
--     if sep == nil then
--         sep = '%s'
--     end

--     local res = {}
--     local func = function(w)
--         table.insert(res, w)
--     end

--     string.gsub(str, '[^'..sep..']+', func)
--     return res
-- end





-- AchieverUtils.tablelength = function(T)
--     local count = 0
--     for _ in pairs(T) do count = count + 1 end
--     return count
-- end