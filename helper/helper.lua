-- Achiever compatibility helpers for WoW Classic Era 1.14.x
-- This file is loaded first (see Achiever.toc): the XML references the backdrop tables below.

-- Backdrop definitions used by <KeyValue key="backdropInfo" type="global"> in the XML files
-- (the 1.12 <Backdrop> XML element no longer exists; frames inherit BackdropTemplate instead).
ACHIEVER_BACKDROP_1 = {
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	tile = true,
	edgeSize = 16,
}

ACHIEVER_BACKDROP_2 = {
	edgeFile = [[Interface\AddOns\Achiever\textures\UI-Achievement-WoodBorder]],
	tile = true,
	tileSize = 32,
	edgeSize = 64,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

ACHIEVER_BACKDROP_3 = {
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

ACHIEVER_BACKDROP_4 = {
	bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
	edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
	tile = true,
	tileSize = 32,
	edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 9 },
}

ACHIEVER_BACKDROP_5 = {
	bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 4 },
}

-- PlaySound() takes SOUNDKIT ids on the 1.14 client; the 1.12 string names are mapped here.
local SOUND_KEYS = {
    UChatScrollButton           = "U_CHAT_SCROLL_BUTTON",
    igMainMenuOptionCheckBoxOn  = "IG_MAINMENU_OPTION_CHECKBOX_ON",
    igMainMenuOptionCheckBoxOff = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
    igCharacterInfoTab          = "IG_CHARACTER_INFO_TAB",
}

function Achiever_PlaySound(name)
    local id = SOUNDKIT and SOUND_KEYS[name] and SOUNDKIT[SOUND_KEYS[name]]
    pcall(PlaySound, id or name)
end

-- Replacement for GameTooltip_AddNewbieTip, which is not available on every client.
function Achiever_AddNewbieTip(frame, normalText, r, g, b, newbieText, noNormalText)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    if (normalText) then
        GameTooltip:SetText(normalText, r or 1, g or 1, b or 1)
    end
    if (newbieText) then
        GameTooltip:AddLine(newbieText, 1, 1, 1, true)
    end
    GameTooltip:Show()
end
