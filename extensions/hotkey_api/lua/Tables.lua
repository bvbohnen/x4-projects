
local L = {}

-- Ego style config. Copying over needed consts.
-- TODO: move to separate lua file.
local config = {
    optionsLayer = 3,
    topLevelLayer = 4,

    backarrow = "table_arrow_inv_left",
    backarrowOffsetX = 3,

    sliderCellValueColor = { r = 71, g = 136, b = 184, a = 100 },
    greySliderCellValueColor = { r = 55, g = 55, b = 55, a = 100 },

    font = "Zekton outlined",
    fontBold = "Zekton bold outlined",

    headerFontSize = 13,
    infoFontSize = 9,
    standardFontSize = 10,

    headerTextHeight = 34,
    subHeaderTextHeight = 22,
    standardTextHeight = 19,
    infoTextHeight = 16,

    headerTextOffsetX = 5,
    standardTextOffsetX = 5,
    infoTextOffsetX = 5,

    vrIntroDelay = 32,
    vrIntroFadeOutTime = 2,

    idleTime = 10,
}
config.headerTextProperties = {
    font = config.fontBold,
    fontsize = config.headerFontSize,
    x = config.headerTextOffsetX,
    y = 6,
    minRowHeight = config.headerTextHeight,
    titleColor = Helper.defaultSimpleBackgroundColor,
}
config.subHeaderTextProperties = {
    font = config.fontBold,
    fontsize = config.standardFontSize,
    x = config.standardTextOffsetX,
    y = 2,
    minRowHeight = config.subHeaderTextHeight,
    halign = "center",
    titleColor = Helper.defaultSimpleBackgroundColor,
}
config.infoTextProperties = {
    font = config.font,
    fontsize = config.infoFontSize,
    x = config.infoTextOffsetX,
    y = 2,
    wordwrap = true,
    minRowHeight = config.infoTextHeight,
    titleColor = Helper.defaultSimpleBackgroundColor,
}
config.standardTextProperties = {
    font = config.font,
    fontsize = config.standardFontSize,
    x = config.standardTextOffsetX,
    y = 2,
}
-- Custom subheader punched up a bit.
-- Basically Header with center alignment.
config.subHeaderTextProperties_2 = {
    font = config.fontBold,
    fontsize = config.headerFontSize,
    x = config.headerTextOffsetX,
    y = 6,
    minRowHeight = config.headerTextHeight,
    halign = "center",
    titleColor = Helper.defaultSimpleBackgroundColor,
}


-- Include config in the return.
L.config = config
-- Return data to require() calls.
return L