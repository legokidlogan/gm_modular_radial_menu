
-- Destroy old instances if this file reloads, for dev testing.
if ModularRadialMenu then
    function ModularRadialMenu.New()
        error( "Cannot create a ModularRadialMenu while the class is being rebuilt." )
    end

    local menus = ( ModularRadialMenu.static or {} )._menusByName or {}
    ModularRadialMenu.classIsReloading = true

    for name, menu in pairs( menus ) do
        if menu.Destroy then
            pcall( function()
                menu:Destroy()
            end )
        end

        menus[name] = nil -- Fully ensure it's gone
    end

    table.Empty( ModularRadialMenu.static or {} )
    table.Empty( ModularRadialMenu )
end



ModularRadialMenu = ModularRadialMenu or {}
ModularRadialMenu.static = {}
ModularRadialMenu.static._menusByName = {}
ModularRadialMenu.static.VARIABLE_DEFAULTS = {
    -- These can be changed per-instance at any time.
    HOVER_DURATION = 0.25, -- How long it takes for the (un)hover animation to complete, in seconds.
    NAME_ALIGN = TEXT_ALIGN_TOP, -- Whether to put the menu's name above, below, or in the center.
    NAME_OFFSET = 0.075, -- The distance from the center of the menu to the name, as a fraction of the menu radius. Does nothing for centered alignment.

    -- These can be changed per-instance, but only during instance init.
    FONT = "Roboto Mono",
    FONT_SIZE = 20 / 1080, -- Font size. Gets scaled by screen height.
    FONT_ANTIALIAS = true,
    FONT_OUTLINE = false,
    FONT_OUTLINE_THINNESS = 2, -- Larger values result in thinner outlines.
    FONT_WEIGHT = 400,

    RADIUS = 0.25, -- Radius of the menu as a fraction of the screen height. This is the largest radius, i.e. the radius when hovering a choice.
    DEADZONE_RADIUS = 0.35, -- Radius of the deadzone as a fraction of the menu radius.
    HOVER_EXPAND = 0.05, -- Expands the outside of the hovered choice by a fraction of the menu radius.
    HOVER_CONTRACT = 0.2, -- Contracts the inside of the hovered choice by a fraction of the menu radius.
    CHOICE_GAP = 0.03, -- Gap between choices as a fraction of the menu radius.

    -- These can be changed per-instance, and can be overridden per each choice of each menu page.
    CHOICE_GRADIENT_ENABLED = true, -- Whether to use an alpha gradient for the choice background, instead of a solid color.
    CHOICE_BAND_ENABLED = true, -- Whether to draw solid background bands behind choice names.
    CHOICE_GRADIENT_COLOR_UNHOVERED = { 180, 0.08, 0.19, 255 }, -- The color of the gradient when the choice is unhovered. Choice colors are in HSV.
    CHOICE_GRADIENT_COLOR_HOVERED = { 180, 1, 1, 255 }, -- The color of the gradient when the choice is hovered.
    CHOICE_BAND_COLOR_UNHOVERED = { 180, 0.08, 0.19, 255 }, -- The color of the band when the choice is unhovered.
    CHOICE_BAND_COLOR_HOVERED = { 180, 1, 1, 255 }, -- The color of the band when the choice is hovered.
    CHOICE_NAME_COLOR_UNHOVERED = { 0, 0, 1, 255 }, -- The color of the choice name when the choice is unhovered.
    CHOICE_NAME_COLOR_HOVERED = { 0, 0, 1, 255 }, -- The color of the choice name when the choice is hovered.
}


local function uniformVector( x ) return Vector( x, x, x ) end

local MRM = ModularRadialMenu
local menusByName = MRM.static._menusByName
local VARIABLE_DEFAULTS = MRM.static.VARIABLE_DEFAULTS

local MAIN_FONT_SIZE = 32 / 1080
local MAIN_FONT_OUTLINE = true
local MAIN_FONT_OUTLINE_THINNESS = 1
local PAGE_FONT_SIZE = 24 / 1080
local CHOICE_FRAME_COUNT = 100

local MATH_PI = math.pi
local MAIN_FONT_SIZE_EFF = MAIN_FONT_SIZE * ScrH()
local PAGE_FONT_SIZE_EFF = PAGE_FONT_SIZE * ScrH()
local VECTOR_MENU_NAME_SCALE = uniformVector( 1 / MAIN_FONT_OUTLINE_THINNESS )
local VECTOR_PAGE_NAME_SCALE = uniformVector( 1 / MAIN_FONT_OUTLINE_THINNESS )

local UNREMOVABLE_FUNCS = {
    __tostring = true,
    __index = true,
    __newindex = true,
    IsValid = true,
    ToStringInner = true,
}

local pageNumOffsetY = ( MAIN_FONT_SIZE_EFF + PAGE_FONT_SIZE_EFF ) * 0.5
local pageNameOffsetY = pageNumOffsetY + PAGE_FONT_SIZE_EFF
local fontHeights = {}
local mainFont = nil
local pageFont = nil
local matGradient = Material( "gui/gradient_up" )
local matWhite = Material( "vgui/white" )
local curMenu = nil
local prevMenu = nil
local hoveredInd = nil
local paintArgs = {}
local paintRadialArgs = {}

local choicePolySetsLookup = {}
local choiceGradientColorsLookup = {}
local choiceBandColorsLookup = {}
local choiceNameColorsLookup = {}

local matrCenter = Matrix()
matrCenter:Translate( Vector( ScrW() / 2, ScrH() / 2, 0 ) )

local destroyedFunc
local cloneHSVA
local applyVarOverrides
local addPolyUser
local removePolyUser
local addColorUser
local removeColorUser
local makePolyFrame
local getColorFrame
local moveColorUser
local nudgePolyUsers
local nudgeColorUsers
local getChoiceVisuals
local editChoice
local makeBlankChoice
local validatePolyUser
local handleChoiceClick
local resetHoverProgress
local getColorEff


----- STATIC FUNCTIONS -----

--[[
    name: string
        - The name of the menu.
        - Must be unique.
    displayName: string
        - The display name of the menu.
    pages: table
        - A sequential list of page details.
        - At least one page is required.
        - Each page should contain three or more choices.
        {
            [1] = { -- (page 1)
                name = STRING (optional), -- The name of the page.

                [1] = { -- (choice 1 of page 1)
                    name = STRING, -- The name of the choice. Supports newlines. Text automatically shrinks to fit.

                    -- These are mutually exclusive with each other. At least one must be set.
                    command = STRING, -- The concmd to run when the choice is selected. Only works on the owner, otherwise tries the other options.
                    menu = STRING, -- The name of the menu to open when the choice is selected.
                        menuPageInd = NUMBER (optional), -- The page to open when the choice is selected, if menu is used. nil to not force the page.
                    func = function( menu, pageInd, choiceInd ) end, -- A function to run when the choice is selected.

                    template = TABLE (optional), -- If provided, will be used to get defaults for all parameters below, before checking the menu's defaults.

                    -- See the CHOICE_ vars of ModularRadialMenu.static.VARIABLE_DEFAULTS for more info. Colors are HSVA tables (0-360, 0-1, 0-1, 0-255).
                    gradientEnabled = BOOLEAN (optional),
                    bandEnabled = BOOLEAN (optional),
                    gradientColorUnhovered = TABLE (optional),
                    gradientColorHovered = TABLE (optional),
                    bandColorUnhovered = TABLE (optional),
                    bandColorHovered = TABLE (optional),
                    nameColorUnhovered = TABLE (optional),
                    nameColorHovered = TABLE (optional),

                    -- This function allows for extra rendering.
                    -- Drawing at 0,0 will result in drawing at the center of the menu/screen.
                    -- Drawing at xDir * choiceRadius, yDir * choiceRadius will result in drawing at the outermost edge of the choice.
                    -- The render will be facing upright.
                    -- choiceWidth is the outermost width of the choice based on its current hover progress.
                    -- paintArgs is a read-only table with the following values:
                    --[==[
                        menu = ModularRadialMenu, -- The menu this choice is a part of.
                        xDir = VECTOR, -- The choice's x-axis in screen coordinates.
                        yDir = VECTOR, -- The choice's y-axis in screen coordinates.
                        pageInd = NUMBER, -- The page index this choice is on.
                        choiceInd = NUMBER, -- The index of this choice.
                        choiceRadius = NUMBER, -- The choice's radius/height.
                        bandHeight = NUMBER, -- The radial height of the name band.
                        choiceWidth = NUMBER, -- The tangential width of this choice at the outermost edge. Varies with hover progress.
                        hoverProgress = NUMBER, -- The hover progress of this choice, from 0 to 1.
                        hovered = BOOLEAN, -- Whether this choice is being hovered over or not.
                    --]==]
                    paint = function( paintArgs ) return end (optional),

                    -- This function is like paint, but inherits the choice's radial orientation.
                    -- Drawing at 0, -choiceRadius will result in drawing at the outermost edge of the choice.
                    -- Note that choices below the center have their rotation flipped for ease of readability.
                    -- paintRadialArgs is a read-only table, with the same values as paintArgs except for xDir and yDir.
                    paintRadial = function( paintRadialArgs ) return end (optional),
                },
                ...
            },
            ...
        }
    varOverrides: (optional) table
        - Allows various properties to be overridden.
        - See ModularRadialMenu.static.VARIABLE_DEFAULTS for available choices.
--]]
function MRM.New( name, displayName, pages, varOverrides )
    if type( name ) ~= "string" then error( "Expected name to be a string" ) end
    if type( displayName ) ~= "string" then error( "Expected displayName to be a string" ) end
    if type( pages ) ~= "table" then error( "Expected displayName to be a table" ) end

    if IsValid( menusByName[name] ) then
        error( "A radial menu with that name already exists" )
    end

    local menu = {}
    setmetatable( menu, MRM )
    MRM.__index = MRM

    menu.__type = "ModularRadialMenu"
    menu._name = name
    menu._displayName = displayName
    menu._pages = {}
    menu._curPageInd = 1

    applyVarOverrides( menu, varOverrides or {} )
    menu:SetPages( pages )

    menusByName[name] = menu

    return menu
end

--[[
    - Returns a blank choice for use with other page/choice functions.

    menu: (optional) ModularRadialMenu
        - If provided, will use its choice parameters as fallbacks.
        - Otherwise, will pull from ModularRadialMenu.static.VARIABLE_DEFAULTS.
    template: (optional) table
        - Behaves the same as it normally does for choice parameters, as seen in ModularRadialMenu.New().
--]]
function MRM.MakeBlankChoice( menu, template )
    if menu then return makeBlankChoice( template, menu ) end

    return makeBlankChoice(
        template,
        VARIABLE_DEFAULTS.CHOICE_GRADIENT_ENABLED,
        VARIABLE_DEFAULTS.CHOICE_BAND_ENABLED,
        VARIABLE_DEFAULTS.CHOICE_GRADIENT_COLOR_UNHOVERED,
        VARIABLE_DEFAULTS.CHOICE_BAND_COLOR_UNHOVERED,
        VARIABLE_DEFAULTS.CHOICE_NAME_COLOR_UNHOVERED
    )
end

--[[
    - Adds blank choices to a page descriptor until it has a minimum number of choices.
    - Useful for auto-filling pages with less than three choices or ensuring a page has a fixed number of choices.
    - Modifies page and returns it.
    - This should be used in conjunction with ModularRadialMenu.New() or page-editing functions. 

    page: table
        - A page descriptor, as seen in ModularRadialMenu.New().
        - Will be modified.
    targetChoiceCount: number
        - The minimum number of choices the page should have after adding blanks.
    blankChoice: (optional) table
        - The blanke choice descriptor to use.
        - If nil, will use a generic one from the class defaults.
--]]
function MRM.FillPageWithBlanks( page, targetChoiceCount, blankChoice )
    blankChoice = blankChoice or MRM.MakeBlankChoice()

    for i = #page + 1, targetChoiceCount do
        page[i] = blankChoice
    end

    return page
end

-- Identical to ModularRadialMenu.FillPageWithBlanks(), but applies to a list of page descriptors.
function MRM.FillPagesWithBlanks( pages, targetChoiceCount, blankChoice )
    blankChoice = blankChoice or MRM.MakeBlankChoice()

    for _, page in ipairs( pages ) do
        MRM.FillPageWithBlanks( page, targetChoiceCount, blankChoice )
    end

    return pages
end

--[[
    - Returns a list of pages that each have the same number of choices, using one list of choice descriptors.
    - If there aren't enough choices to complete the last page, the remainder will be filled with blank choices.

    choiceList: table
        - A list of choice descriptors, as seen in ModularRadialMenu.New().
        - Note that you can add more fields to choices that aren't listed in ModularRadialMenu.New().
            - Doing so may help when doing more complex setups with extraParams.
        - Each choice will automatically be given these additional fields:
            isTopChoice = BOOLEAN
            isBlankChoice = BOOLEAN
    choicesPerPage: number
        - The exact number of choices each page should have.
    extraParams: (optional) table
        - Additional options. All fields are optional.
        {
            blankChoice = TABLE, -- The blank choice descriptor to use, instead of the static default.
            topChoice = TABLE or function( pageInd ) return choice end, -- A choice descriptor to put at the top of every page.
            pageName = STRING or function( pageInd, page ) return name end, -- The name to use for each page.
            choiceIterator = function( pageInd, choiceInd, choice ) return end, -- Runs for every choice at the end.
        }
--]]
function MRM.MakePagesFromChoiceList( choiceList, choicesPerPage, extraParams )
    if type( choicesPerPage ) ~= "number" then error( "Expected choicesPerPage to be a number" ) end
    if math.floor( choicesPerPage ) ~= choicesPerPage then error( "Expected choicesPerPage to be an integer" ) end
    if choicesPerPage < 3 then error( "Expected choicesPerPage to be 3 or greater" ) end

    extraParams = extraParams or {}

    local allChoices = {}
    local choiceCount = 0
    local blankChoice = extraParams.blankChoice or MRM.MakeBlankChoice()
    local topChoice = extraParams.topChoice

    blankChoice.isTopChoice = false
    blankChoice.isBlankChoice = true

    -- Build the normal and top choices.
    for _, choice in ipairs( choiceList ) do
        if topChoice and choiceCount % choicesPerPage == 0 then
            local c = topChoice

            if type( topChoice ) == "function" then
                c = topChoice( choiceCount / choicesPerPage + 1 )
            end

            c.isTopChoice = true
            c.isBlankChoice = false
            table.insert( allChoices, c )
            choiceCount = choiceCount + 1
        end

        choiceCount = choiceCount + 1

        local choiceInd = choiceCount % choicesPerPage
        if choiceInd == 0 then choiceInd = choicesPerPage end

        choice.isTopChoice = false
        choice.isBlankChoice = false
        table.insert( allChoices, choice )
    end

    local pages = {}
    local curPage = {}
    local pageName = extraParams.pageName or nil
    choiceCount = 0

    -- Build the pages.
    for _, choice in ipairs( allChoices ) do
        if choiceCount == choicesPerPage then
            table.insert( pages, curPage )
            curPage = {}
            choiceCount = 0
        end

        table.insert( curPage, choice )
        choiceCount = choiceCount + 1
    end

    -- Add placeholder choices to the last page if needed.
    if choiceCount < choicesPerPage and ( #pages == 0 or choiceCount ~= 0 ) then
        for _ = choiceCount, choicesPerPage - 1 do
            table.insert( curPage, blankChoice )
        end

        choiceCount = choicesPerPage
    end

    -- Add the last page if it's not empty.
    if choiceCount ~= 0 then
        table.insert( pages, curPage )
    end

    -- Handle page names.
    for pageInd, page in ipairs( pages ) do
        if type( page ) == "function" then
            page.name = pageName( pageInd, page )
        else
            page.name = pageName
        end
    end

    -- Handle choice iterator.
    local choiceIterator = extraParams.choiceIterator

    if choiceIterator then
        for pageInd, page in ipairs( pages ) do
            for choiceInd, choice in ipairs( page ) do
                choiceIterator( pageInd, choiceInd, choice )
            end
        end
    end

    return pages
end

function MRM.GetMenuByName( name )
    return menusByName[name]
end

function MRM.GetCurMenu()
    return curMenu
end

function MRM.GetPrevMenu()
    return prevMenu
end

function MRM.GetHoveredInd()
    return hoveredInd
end

function MRM.CloseCurMenu( dontHideCursor )
    if curMenu then
        curMenu:Close( dontHideCursor )
    end
end

-- Simulates a left click on the currently hovered choice.
function MRM.ForceClickHovered()
    if not curMenu or not hoveredInd then return end

    handleChoiceClick()
end


----- INSTANCE FUNCTIONS -----

function MRM:IsValid()
    return true
end

function MRM:Destroy()
    -- Run the hook before any :OnDestroyed functions run to ensure no data is missing for the hook listeners.
    hook.Run( "ModularRadialMenu_OnDestroyed", self )
    self:OnDestroyed()

    -- This isn't quite as good as using self.class.__declaredMethods from middleclass, but I'd rather not add the dependency for a one-class addon.
    for k, v in pairs( self ) do
        if type( v ) == "function" and not UNREMOVABLE_FUNCS[k] then
            self[k] = destroyedFunc
        end
    end

    for k, v in pairs( MRM ) do
        if type( v ) == "function" and not UNREMOVABLE_FUNCS[k] then
            self[k] = destroyedFunc
        end
    end

    function self:IsValid()
        return false
    end
end

function MRM:IsOpen()
    return curMenu == self
end

function MRM:SetCurPageInd( pageInd )
    local oldPageInd = self._curPageInd
    if oldPageInd == pageInd then return end

    if pageInd < 1 or pageInd > #self._pages then
        error( "Expected pageInd to be between 1 and pageCount" )
    end

    self._curPageInd = pageInd
    resetHoverProgress( self )

    if curMenu == self then
        hoveredInd = nil
    end

    self:OnPageChanged( oldPageInd, pageInd )
end

function MRM:GetCurPageInd()
    return self._curPageInd
end

function MRM:GetCurPageChoiceCount()
    local page = self._pages[self._curPageInd]
    if not page then return end

    return #page
end

function MRM:GetPageChoiceCount( pageInd )
    local page = self._pages[pageInd]
    if not page then error( "Expected pageInd to be between 1 and pageCount" ) end

    return #page
end

function MRM:GetPageCount()
    return #self._pages
end

function MRM:GetHoveredInd()
    return curMenu == self and hoveredInd
end

--[[
    - Opens the menu (to a page), or changes the page if already open.

    pageInd: number (optional)
        - The page to open to.
        - If not set, the current page will be opened.
--]]
function MRM:Open( pageInd )
    if curMenu == self then
        if pageInd then
            self:SetCurPageInd( pageInd )
        end

        return
    end

    prevMenu = IsValid( curMenu ) and curMenu or nil
    curMenu = self
    hoveredInd = nil

    if prevMenu then
        prevMenu:OnClosed( true, true )
        hook.Run( "ModularRadialMenu_OnClosed", prevMenu, true, true )
    else
        gui.EnableScreenClicker( true )
    end

    if pageInd then
        self:SetCurPageInd( pageInd )
    else
        resetHoverProgress( self )
    end

    self:OnOpened( prevMenu, pageInd )
    hook.Run( "ModularRadialMenu_OnOpened", prevMenu, self, pageInd )
end

--[[
    - Closes the menu.

    dontHideCursor: boolean (optional)
        - If true, the cursor will not be hidden.
        - False by default.
--]]
function MRM:Close( dontHideCursor )
    if curMenu ~= self then return end

    prevMenu = self
    curMenu = nil
    hoveredInd = nil

    if not dontHideCursor then
        gui.EnableScreenClicker( false )
    end

    self:OnClosed( false, dontHideCursor )
    hook.Run( "ModularRadialMenu_OnClosed", self, false, dontHideCursor )
end

function MRM:SetHoverDuration( duration )
    if duration == nil then
        self._hoverDuration = VARIABLE_DEFAULTS.HOVER_DURATION
        return
    end

    if type( duration ) ~= "number" then error( "Expected duration to be a number or nil" ) end
    if duration >= 0 then error( "Expected duration to be greater than or equal to 0" ) end

    self._hoverDuration = duration
end

function MRM:GetHoverDuration()
    return self._hoverDuration
end

function MRM:SetNameAlign( align )
    if align == nil then
        self._nameAlign = VARIABLE_DEFAULTS.NAME_ALIGN
        return
    end

    if type( align ) ~= "number" then error( "Expected align to be a number or nil" ) end
    if align ~= TEXT_ALIGN.TOP and align ~= TEXT_ALIGN.CENTER and align ~= TEXT_ALIGN.BOTTOM then
        error( "Expected align to be one of the three vertical text alignments" )
    end

    self._nameAlign = align
end

function MRM:GetNameAlign()
    return self._nameAlign
end

function MRM:SetNameOffset( offset )
    if offset ~= nil and type( offset ) ~= "number" then error( "Expected offset to be a number or nil" ) end

    self._nameOffset = VARIABLE_DEFAULTS.NAME_OFFSET
end

function MRM:GetNameOffset()
    return self._nameOffset
end

-- Overrides the pages. See ModularRadialMenu.New() for page format.
function MRM:SetPages( pages )
    if type( pages ) ~= "table" then error( "Expected pages to be a table" ) end
    if #pages < 1 then error( "Expected pages to have at least one page" ) end

    for i, page in ipairs( pages ) do
        if type( page ) ~= "table" then error( "Expected page " .. i .. " to be a table" ) end
        if #page < 3 then error( "Expected page " .. i .. " to have at least three choices" ) end
    end

    local menuNamePrepend = self:GetName() .. "_"
    local realPages = self._pages
    local curPageInd = self:GetCurPageInd()

    for i = 1, #realPages do
        local page = realPages[i]
        local pageUID = menuNamePrepend .. i
        local pageUIDPrepend = pageUID .. "_"
        local polyStr = page.polyStr

        if polyStr then
            removePolyUser( pageUID, polyStr )
        end

        for i2 = 1, #page do
            local choice = page[i2]
            local choiceUID = pageUIDPrepend .. i2

            removeColorUser( choiceGradientColorsLookup, choiceUID, choice.gradientColorStr )
            removeColorUser( choiceBandColorsLookup, choiceUID, choice.bandColorStr )
            removeColorUser( choiceNameColorsLookup, choiceUID, choice.nameColorStr )

            page[i2] = nil
        end

        realPages[i] = nil
    end

    local choiceGradientEnabled = self:IsChoiceGradientEnabled()
    local choiceBandEnabled = self:IsChoiceBandEnabled()
    local choiceGradientColorUnhovered = self._choiceGradientColorUnhovered
    local choiceGradientColorHovered = self._choiceGradientColorHovered
    local choiceBandColorUnhovered = self._choiceBandColorUnhovered
    local choiceBandColorHovered = self._choiceBandColorHovered
    local choiceNameColorUnhovered = self._choiceNameColorUnhovered
    local choiceNameColorHovered = self._choiceNameColorHovered

    for i = 1, #pages do
        local pageUID = menuNamePrepend .. i
        local pageUIDPrepend = pageUID .. "_"
        local page = pages[i]
        local realPage = {
            name = page.name,
        }
        realPages[i] = realPage

        for i2 = 1, #page do
            realPage[i2] = {}
            editChoice( realPage, pageUIDPrepend, i2, page[i2],
                choiceGradientEnabled,
                choiceBandEnabled,
                choiceGradientColorUnhovered,
                choiceGradientColorHovered,
                choiceBandColorUnhovered,
                choiceBandColorHovered,
                choiceNameColorUnhovered,
                choiceNameColorHovered
            )
        end
    end

    if curMenu == self then
        hoveredInd = nil
    end

    self:SetCurPageInd( math.Clamp( curPageInd, 1, #realPages ) )
end

-- Inserts a new page. See ModularRadialMenu.New() for page format.
function MRM:InsertPage( pageInd, page )
    if type( pageInd ) ~= "number" then error( "Expected pageInd to be a number" ) end
    if math.floor( pageInd ) ~= pageInd then error( "Expected pageInd to be an integer" ) end
    if type( page ) ~= "table" then error( "Expected page to be a table" ) end
    if #page < 3 then error( "Expected page to have at least three choices" ) end

    local realPages = self._pages
    if pageInd < 1 or pageInd > #realPages + 1 then
        error( "Expected pageInd to be between 1 and pageCount + 1" )
    end

    for i = 1, #page do
        if type( page[i] ) ~= "table" then error( "Expected choice " .. i .. " of page to be a table" ) end
        if type( page[i].name ) ~= "string" then error( "Expected choice name to be a string" ) end
    end

    nudgePolyUsers( self, pageInd, #realPages, 1 )

    local pageUID = self:GetName() .. "_" .. pageInd
    local pageUIDPrepend = pageUID .. "_"

    local choiceGradientEnabled = self:IsChoiceGradientEnabled()
    local choiceBandEnabled = self:IsChoiceBandEnabled()
    local choiceGradientColorUnhovered = self._choiceGradientColorUnhovered
    local choiceGradientColorHovered = self._choiceGradientColorHovered
    local choiceBandColorUnhovered = self._choiceBandColorUnhovered
    local choiceBandColorHovered = self._choiceBandColorHovered
    local choiceNameColorUnhovered = self._choiceNameColorUnhovered
    local choiceNameColorHovered = self._choiceNameColorHovered

    local realPage = {
        name = page.name,
    }

    table.insert( realPages, pageInd, realPage )

    for i = 1, #page do
        realPage[i] = {}
        editChoice( realPage, pageUIDPrepend, i, page[i],
            choiceGradientEnabled,
            choiceBandEnabled,
            choiceGradientColorUnhovered,
            choiceGradientColorHovered,
            choiceBandColorUnhovered,
            choiceBandColorHovered,
            choiceNameColorUnhovered,
            choiceNameColorHovered
        )
    end

    local curPageInd = self:GetCurPageInd()

    if curPageInd >= pageInd then
        self:SetCurPageInd( curPageInd + 1 )
    end
end

-- Removes a page. There must always be at least one page, so it's best to insert before removing.
function MRM:RemovePage( pageInd )
    if type( pageInd ) ~= "number" then error( "Expected pageInd to be a number" ) end
    if math.floor( pageInd ) ~= pageInd then error( "Expected pageInd to be an integer" ) end

    local realPages = self._pages
    if #realPages == 1 then error( "Cannot remove all pages" ) end
    if pageInd < 1 or pageInd > #realPages then
        error( "Expected pageInd to be between 1 and pageCount" )
    end

    local page = realPages[pageInd]
    local pageUID = self:GetName() .. "_" .. pageInd
    local pageUIDPrepend = pageUID .. "_"
    local polyStr = page.polyStr

    if polyStr then
        removePolyUser( pageUID, page.polyStr )
    end

    for i = 1, #page do
        local choice = page[i]
        local choiceUID = pageUIDPrepend .. i

        removeColorUser( choiceGradientColorsLookup, choiceUID, choice.gradientColorStr )
        removeColorUser( choiceBandColorsLookup, choiceUID, choice.bandColorStr )
        removeColorUser( choiceNameColorsLookup, choiceUID, choice.nameColorStr )
    end

    nudgePolyUsers( self, pageInd + 1, #realPages, -1 )
    table.remove( realPages, pageInd )

    local curPageInd = self:GetCurPageInd()

    if curPageInd >= pageInd then
        if curMenu == self and curPageInd == pageInd then
            hoveredInd = nil
        end

        if curPageInd == 1 then
            self:OnPageChanged( 1, 1 )
        else
            self:SetCurPageInd( curPageInd - 1 )
        end
    end
end

-- Inserts a new choice into a new page. See ModularRadialMenu.New() for choice format.
function MRM:InsertChoice( pageInd, choiceInd, choice )
    if type( pageInd ) ~= "number" then error( "Expected pageInd to be a number" ) end
    if math.floor( pageInd ) ~= pageInd then error( "Expected pageInd to be an integer" ) end
    if type( choiceInd ) ~= "number" then error( "Expected choiceInd to be a number" ) end
    if math.floor( choiceInd ) ~= choiceInd then error( "Expected choiceInd to be an integer" ) end
    if type( choice ) ~= "table" then error( "Expected choice to be a table" ) end
    if type( choice.name ) ~= "string" then error( "Expected choice name to be a string" ) end

    local realPages = self._pages
    if pageInd < 1 or pageInd > #realPages then
        error( "Expected pageInd to be between 1 and pageCount" )
    end

    local page = realPages[pageInd]
    local choiceCount = #page
    if choiceInd < 1 or choiceInd > choiceCount + 1 then
        error( "Expected choiceInd to be between 1 and choiceCount + 1" )
    end

    local pageUID = self:GetName() .. "_" .. pageInd
    local pageUIDPrepend = pageUID .. "_"

    nudgeColorUsers( page, pageUID, choiceInd, choiceCount, 1 )
    table.insert( page, choiceInd, {} )
    editChoice( page, pageUIDPrepend, choiceInd, choice, self )

    if curMenu == self and self:GetCurPageInd() == pageInd then
        hoveredInd = nil
    end
end

-- Removes a choice from a page. There must always be at least three choices, so it's best to insert before removing.
function MRM:RemoveChoice( pageInd, choiceInd )
    if type( pageInd ) ~= "number" then error( "Expected pageInd to be a number" ) end
    if math.floor( pageInd ) ~= pageInd then error( "Expected pageInd to be an integer" ) end
    if type( choiceInd ) ~= "number" then error( "Expected choiceInd to be a number" ) end
    if math.floor( choiceInd ) ~= choiceInd then error( "Expected choiceInd to be an integer" ) end

    local realPages = self._pages
    if pageInd < 1 or pageInd > #realPages then
        error( "Expected pageInd to be between 1 and pageCount" )
    end

    local page = realPages[pageInd]
    local choiceCount = #page
    if choiceInd < 1 or choiceInd > choiceCount then
        error( "Expected choiceInd to be between 1 and choiceCount" )
    end

    local pageUID = self:GetName() .. "_" .. pageInd
    local pageUIDPrepend = pageUID .. "_"
    local choice = page[choiceInd]
    local choiceUID = pageUIDPrepend .. choiceInd

    removeColorUser( choiceGradientColorsLookup, choiceUID, choice.gradientColorStr )
    removeColorUser( choiceBandColorsLookup, choiceUID, choice.bandColorStr )
    removeColorUser( choiceNameColorsLookup, choiceUID, choice.nameColorStr )
    nudgeColorUsers( page, pageUID, choiceInd + 1, choiceCount, -1 )
    table.remove( page, choiceInd )

    if curMenu == self and self:GetCurPageInd() == pageInd then
        hoveredInd = nil
    end
end

-- Edits a choice on a page. See ModularRadialMenu.New() for choice format.
function MRM:EditChoice( pageInd, choiceInd, choice )
    if type( pageInd ) ~= "number" then error( "Expected pageInd to be a number" ) end
    if math.floor( pageInd ) ~= pageInd then error( "Expected pageInd to be an integer" ) end
    if type( choiceInd ) ~= "number" then error( "Expected choiceInd to be a number" ) end
    if math.floor( choiceInd ) ~= choiceInd then error( "Expected choiceInd to be an integer" ) end
    if type( choice ) ~= "table" then error( "Expected choice to be a table" ) end
    if type( choice.name ) ~= "string" then error( "Expected choice name to be a string" ) end

    local realPages = self._pages
    if pageInd < 1 or pageInd > #realPages then
        error( "Expected pageInd to be between 1 and pageCount" )
    end

    local page = realPages[pageInd]
    local choiceCount = #page
    if choiceInd < 1 or choiceInd > choiceCount then
        error( "Expected choiceInd to be between 1 and choiceCount" )
    end

    local pageUIDPrepend = self:GetName() .. "_" .. pageInd .. "_"

    editChoice( page, pageUIDPrepend, choiceInd, choice, self )
end

function MRM:GetName()
    return self._name
end

function MRM:GetDisplayName()
    return self._displayName
end

function MRM:IsChoiceGradientEnabled()
    return self._choiceGradientEnabled
end

function MRM:IsChoiceBandEnabled()
    return self._choiceBandEnabled
end

function MRM:GetChoiceGradientColorUnhovered()
    return cloneHSVA( self._choiceGradientColorUnhovered )
end

function MRM:GetChoiceGradientColorHovered()
    return cloneHSVA( self._choiceGradientColorHovered )
end

function MRM:GetChoiceBandColorUnhovered()
    return cloneHSVA( self._choiceBandColorUnhovered )
end

function MRM:GetChoiceBandColorHovered()
    return cloneHSVA( self._choiceBandColorHovered )
end

function MRM:GetChoiceNameColorUnhovered()
    return cloneHSVA( self._choiceNameColorUnhovered )
end

function MRM:GetChoiceNameColorHovered()
    return cloneHSVA( self._choiceNameColorHovered )
end

function MRM:GetRadius()
    return self._radius
end

-- The actual pixel value of the maximum radius.
function MRM:GetRadiusEff()
    return self._radiusHovered
end

function MRM:GetDeadzoneRadius()
    return self._deadzoneRadius
end

-- The actual pixel value of the deadzone radius.
function MRM:GetDeadzoneRadiusEff()
    return self._radiusInnerUnhovered
end

function MRM:GetHoverExpand()
    return self._hoverExpand
end

function MRM:GetHoverContract()
    return self._hoverContract
end

function MRM:GetChoiceGap()
    return self._choiceGap
end

-- Gets the current effective gradient color of a choice. Returns by reference, do not modify.
-- Provide hoverProgress to force-calculate at a fraction of your choice, independent of the choice's current state.
function MRM:GetChoiceGradientColorEff( pageInd, choiceInd, hoverProgress )
    return getColorEff( self, pageInd, choiceInd, hoverProgress, choiceGradientColorsLookup, "_gradientColorEff", "gradientColorStr" )
end

-- Gets the current effective band color of a choice. Returns by reference, do not modify.
-- Provide hoverProgress to force-calculate at a fraction of your choice, independent of the choice's current state.
function MRM:GetChoiceBandColorEff( pageInd, choiceInd, hoverProgress )
    return getColorEff( self, pageInd, choiceInd, hoverProgress, choiceBandColorsLookup, "_bandColorEff", "bandColorStr" )
end

-- Gets the current effective name color of a choice. Returns by reference, do not modify.
-- Provide hoverProgress to force-calculate at a fraction of your choice, independent of the choice's current state.
function MRM:GetChoiceNameColorEff( pageInd, choiceInd, hoverProgress )
    return getColorEff( self, pageInd, choiceInd, hoverProgress, choiceNameColorsLookup, "_nameColorEff", "nameColorStr" )
end

-- Gets the current hover progress of a choice. This is a value between 0 and 1.
function MRM:GetChoiceHoverProgress( pageInd, choiceInd )
    return self._pages[pageInd][choiceInd]._hoverProgress
end


----- OVERRIDABLE FUNCTIONS -----

--[[
    - Called when the menu is opened.
    - DO NOT call :Open() inside this function, it could cause an infinite loop.

    prevMenu: ModularRadialMenu or nil
        - The menu that was just closed to open this one.
            - If a menu is :Close()'d manually and another is :Open()'d after, this will be nil.
        - This is the same as the argument passed to :Close().
    pageInd: number or nil
        - The index of the page that was just opened to, or nil if it was not specified.
        - This is the same as the argument passed to :Open().
--]]
function MRM:OnOpened( _prevMenu, _pageInd )
end

--[[
    - Called when the menu is opened.
    - DO NOT call :Open() or :Close() inside this function, it could cause an infinite loop.

    fromOtherOpening: boolean
        - Whether the menu was closed due to another menu being opened in its place.
    dontHideCursor: boolean
        - Passed from the args of the :Close() function.
--]]
function MRM:OnClosed( _fromOtherOpening, _dontHideCursor )
end

--[[
    - Called when the page is changed.
    - DO NOT call :SetCurPageInd() inside this function, it could cause an infinite loop.

    oldPageInd: number
        - The index of the page that was just closed.
    newPageInd: number
        - The index of the page that was just opened.
--]]
function MRM:OnPageChanged( _oldPageInd, _newPageInd )
end

-- Called when the ModularRadialMenu is about to be destroyed.
function MRM:OnDestroyed()
    self:_OnDestroyed()
end

-- Provides additional info to __tostring.
function MRM:ToStringInner()
    return self._name or "UNNAMED_MRM"
end


----- META FUNCTIONS -----

function MRM:__tostring()
    local tostringInner = self:ToStringInner() or ""
    local out = self.__type or "ModularRadialMenu"

    if not self:IsValid() then
        out = out .. "(INVALID)"
    end

    if tostringInner ~= "" then
        out = out .. "[" .. tostringInner .. "]"
    end

    return string.format( "%s[%p]", out, self )
end

function MRM:__concat( other )
    return tostring( self ) .. tostring( other )
end


----- PRIVATE FUNCTIONS -----

function MRM:_OnDestroyed()
    local menuNamePrepend = self:GetName() .. "_"
    local realPages = self._pages

    for i = 1, #realPages do
        local page = realPages[i]
        local pageUID = menuNamePrepend .. i
        local pageUIDPrepend = pageUID .. "_"

        removePolyUser( pageUID, page.polyStr )

        for i2 = 1, #page do
            local choice = page[i2]
            local choiceUID = pageUIDPrepend .. i2

            removeColorUser( choiceGradientColorsLookup, choiceUID, choice.gradientColorStr )
            removeColorUser( choiceBandColorsLookup, choiceUID, choice.bandColorStr )
            removeColorUser( choiceNameColorsLookup, choiceUID, choice.nameColorStr )

            page[i2] = nil
        end

        realPages[i] = nil
    end

    if curMenu == self then
        curMenu = nil
        gui.EnableScreenClicker( false )
    end

    menusByName[self._name] = nil
end


local function nearestMultiple( x, mult )
    if mult == 0 then return x end

    local positiveMultiple = math.ceil( x / mult ) * mult
    local negativeMultiple = math.floor( x / mult ) * mult

    if math.abs( x - positiveMultiple ) < math.abs( x - negativeMultiple ) then
        return positiveMultiple
    else
        return negativeMultiple
    end
end

local function lerpFast( frac, from, to )
    if from == to then return from end
    if frac <= 0 then return from end
    if frac >= 1 then return to end

    return from + ( to - from ) * frac
end

local function hsvaToRGB( hsva )
    local rgb = HSVToColor( hsva[1], hsva[2], hsva[3] )
    rgb.a = hsva[4] or 255

    return rgb
end

local function hsvaSplitToRGB( h, s, v, a )
    local rgb = HSVToColor( h, s, v )
    rgb.a = a

    return rgb
end

local function lerpHSVAToRGB( frac, fromHSVA, toHSVA )
    return hsvaSplitToRGB(
        lerpFast( frac, fromHSVA[1], toHSVA[1] ),
        lerpFast( frac, fromHSVA[2], toHSVA[2] ),
        lerpFast( frac, fromHSVA[3], toHSVA[3] ),
        lerpFast( frac, fromHSVA[4], toHSVA[4] )
    )
end

local function makeFont( font, size, weight, antialias, outline, outlineThinness )
    local sizeShort = math.Round( size * 1080 )
    size = math.Round( size * ScrH() )

    local fontStr = "MRM_" .. font .. "_" .. sizeShort .. "_" .. tostring( antialias ) .. "_" .. tostring( outline ) .. "_" .. outlineThinness .. "_" .. weight
    local h = fontHeights[fontStr]
    if h then return fontStr, h, size end

    surface.CreateFont( fontStr, {
        font = font,
        size = size * outlineThinness,
        weight = weight,
        antialias = antialias,
        outline = outline,
    } )

    surface.SetFont( fontStr )
    local _, height = surface.GetTextSize( "ABCDEFGHIJKLMNOPQRSTUVWXYZ" )
    height = height / outlineThinness
    fontHeights[fontStr] = height

    return fontStr, height, size
end

destroyedFunc = function( self )
    error( "Invalid " .. ( self.__type or "CUSTOM_OBJECT_INSTANCE" ) )
end

cloneHSVA = function( hsva )
    return { hsva[1], hsva[2], hsva[3], hsva[4] or 255 }
end

applyVarOverrides = function( menu, overrides )
    local function get( varName )
        local val = overrides[varName]
        if val ~= nil then return val end

        return VARIABLE_DEFAULTS[varName]
    end


    local fontOutlineThinness = get( "FONT_OUTLINE_THINNESS" )
    local fontStr, fontHeight, fontSize = makeFont( get( "FONT" ), get( "FONT_SIZE" ), get( "FONT_WEIGHT" ), get( "FONT_ANTIALIAS" ), get( "FONT_OUTLINE" ), fontOutlineThinness )
    menu._fontStr = fontStr
    menu._fontSize = fontSize
    menu._fontHeight = fontHeight
    menu._fontVecScale = uniformVector( 1 / fontOutlineThinness )
    menu._bandHeight = fontHeight * 2.25

    local menuRadius = get( "RADIUS" )
    local deadzoneRadius = get( "DEADZONE_RADIUS" )
    local hoverExpand = get( "HOVER_EXPAND" )
    local hoverContract = get( "HOVER_CONTRACT" )
    local choiceGap = get( "CHOICE_GAP" )

    local radiusHovered = ScrH() * menuRadius
    local radiusUnhovered = radiusHovered * ( 1 - hoverExpand )
    local radiusInnerUnhovered = radiusHovered * deadzoneRadius
    local radiusInnerHovered = radiusInnerUnhovered + ( radiusHovered - radiusInnerUnhovered ) * hoverContract

    menu._radius = menuRadius
    menu._deadzoneRadius = deadzoneRadius
    menu._hoverExpand = hoverExpand
    menu._hoverContract = hoverContract
    menu._choiceGap = choiceGap

    menu._radiusHovered = radiusHovered
    menu._radiusUnhovered = radiusUnhovered
    menu._radiusInnerUnhovered = radiusInnerUnhovered
    menu._radiusInnerHovered = radiusInnerHovered

    menu._choiceGradientEnabled = get( "CHOICE_GRADIENT_ENABLED" )
    menu._choiceBandEnabled = get( "CHOICE_BAND_ENABLED" )
    menu._choiceGradientColorUnhovered = cloneHSVA( get( "CHOICE_GRADIENT_COLOR_UNHOVERED" ) )
    menu._choiceGradientColorHovered = cloneHSVA( get( "CHOICE_GRADIENT_COLOR_HOVERED" ) )
    menu._choiceBandColorUnhovered = cloneHSVA( get( "CHOICE_BAND_COLOR_UNHOVERED" ) )
    menu._choiceBandColorHovered = cloneHSVA( get( "CHOICE_BAND_COLOR_HOVERED" ) )
    menu._choiceNameColorUnhovered = cloneHSVA( get( "CHOICE_NAME_COLOR_UNHOVERED" ) )
    menu._choiceNameColorHovered = cloneHSVA( get( "CHOICE_NAME_COLOR_HOVERED" ) )

    menu:SetHoverDuration( overrides.HOVER_DURATION )
    menu:SetNameAlign( overrides.NAME_ALIGN )
    menu:SetNameOffset( overrides.NAME_OFFSET )
end

addPolyUser = function( uid, radiusHovered, radiusUnhovered, radiusInnerUnhovered, radiusInnerHovered, bandHeight, choiceGap, choiceCount )
    local polyStr = radiusHovered .. "_" .. radiusUnhovered .. "_" .. radiusInnerUnhovered .. "_" .. radiusInnerHovered .. "_" .. bandHeight .. "_" .. choiceGap .. "_" .. choiceCount
    local polySetsByFrame = choicePolySetsLookup[polyStr]

    if not polySetsByFrame then
        local menuCircumference = 2 * MATH_PI * radiusHovered
        local choiceArc = ( menuCircumference / choiceCount ) - radiusHovered * choiceGap
        local choiceRadHalf = choiceArc / ( radiusHovered * 2 )

        local rad90 = MATH_PI / 2
        local dirRightX = math.cos( rad90 - choiceRadHalf )
        local dirRightY = -math.sin( rad90 - choiceRadHalf )
        local dirLeftX = math.cos( rad90 + choiceRadHalf )
        local dirLeftY = -math.sin( rad90 + choiceRadHalf )
        local inscribeMult = math.cos( MATH_PI / choiceCount ) -- Accounts for name radius loss due to inscribing the circle.

        polySetsByFrame = {
            users = {},
            gradientPolys = {},
            bandPolys = {},
            nameRadii = {},
            radiusHovered = radiusHovered,
            radiusUnhovered = radiusUnhovered,
            radiusInnerUnhovered = radiusInnerUnhovered,
            radiusInnerHovered = radiusInnerHovered,
            bandHeight = bandHeight,
            choiceGap = choiceGap,
            choiceCount = choiceCount,
            dirRightX = dirRightX,
            dirRightY = dirRightY,
            dirLeftX = dirLeftX,
            dirLeftY = dirLeftY,
            inscribeMult = inscribeMult,
        }
        choicePolySetsLookup[polyStr] = polySetsByFrame
    end

    polySetsByFrame.users[uid] = true

    return polyStr
end

removePolyUser = function( uid, polyStr )
    local polySetsByFrame = choicePolySetsLookup[polyStr]
    if not polySetsByFrame then return end

    local users = polySetsByFrame.users

    users[uid] = nil

    if next( users ) ~= nil then return end

    polySetsByFrame.users = nil
    polySetsByFrame.gradientPolys = nil
    polySetsByFrame.bandPolys = nil
    polySetsByFrame.nameRadii = nil

    choicePolySetsLookup[polyStr] = nil
end

addColorUser = function( lookup, uid, color1, color2 )
    local h1 = color1[1]
    local s1 = color1[2]
    local v1 = color1[3]
    local a1 = color1[4] or 255

    local h2 = color2[1]
    local s2 = color2[2]
    local v2 = color2[3]
    local a2 = color2[4] or 255

    local colorStr = h1 .. "_" .. s1 .. "_" .. v1 .. "_" .. a1 .. "_" .. h2 .. "_" .. s2 .. "_" .. v2 .. "_" .. a2
    local colorsByFrame = lookup[colorStr]

    if not colorsByFrame then
        local same = h1 == h2 and s1 == s2 and v1 == v2 and a1 == a2
        color1 = same and hsvaToRGB( color1 ) or { h1, s1, v1, a1 }
        color2 = same and color1 or { h2, s2, v2, a2 }

        colorsByFrame = {
            users = {},
            color1 = color1,
            color2 = color2,
            same = same,
        }
        lookup[colorStr] = colorsByFrame
    end

    colorsByFrame.users[uid] = true

    return colorStr
end

removeColorUser = function( lookup, uid, colorStr )
    local colorsByFrame = lookup[colorStr]
    if not colorsByFrame then return end

    local users = colorsByFrame.users

    users[uid] = nil

    if next( users ) ~= nil then return end

    colorsByFrame.users = nil
    colorsByFrame.color1 = nil
    colorsByFrame.color2 = nil

    lookup[colorStr] = nil
end

makePolyFrame = function( polySetsByFrame, frameInd, scrH )
    local radiusHovered = polySetsByFrame.radiusHovered
    local radiusUnhovered = polySetsByFrame.radiusUnhovered
    local radiusInnerUnhovered = polySetsByFrame.radiusInnerUnhovered
    local radiusInnerHovered = polySetsByFrame.radiusInnerHovered
    local bandHeight = polySetsByFrame.bandHeight
    local dirRightX = polySetsByFrame.dirRightX
    local dirRightY = polySetsByFrame.dirRightY
    local dirLeftX = polySetsByFrame.dirLeftX
    local dirLeftY = polySetsByFrame.dirLeftY
    local inscribeMult = polySetsByFrame.inscribeMult

    local frac = frameInd / CHOICE_FRAME_COUNT
    local radiusOuter = lerpFast( frac, radiusUnhovered, radiusHovered )
    local radiusInner = lerpFast( frac, radiusInnerUnhovered, radiusInnerHovered )
    local bandInner = radiusOuter - bandHeight

    polySetsByFrame.gradientPolys[frameInd] = {
        { x = dirRightX * radiusOuter, y = dirRightY * radiusOuter, u = 1, v = 1 },
        { x = dirRightX * radiusInner, y = dirRightY * radiusInner, u = 1, v = 0.01 },
        { x = dirLeftX * radiusInner, y = dirLeftY * radiusInner, u = 0.01, v = 0.01 },
        { x = dirLeftX * radiusOuter, y = dirLeftY * radiusOuter, u = 0.01, v = 1 },
    }

    polySetsByFrame.bandPolys[frameInd] = {
        { x = dirRightX * radiusOuter, y = dirRightY * radiusOuter, u = 1, v = 1 },
        { x = dirRightX * bandInner, y = dirRightY * bandInner, u = 1, v = 0.01 },
        { x = dirLeftX * bandInner, y = dirLeftY * bandInner, u = 0.01, v = 0.01 },
        { x = dirLeftX * radiusOuter, y = dirLeftY * radiusOuter, u = 0.01, v = 1 },
    }

    -- TODO: Why is scrH * 0.002 here as a magic number?
    polySetsByFrame.nameRadii[frameInd] = inscribeMult * ( bandInner + radiusOuter ) / 2 + scrH * 0.002
end

getColorFrame = function( lookup, colorStr, frameInd )
    local colorsByFrame = lookup[colorStr]
    if colorsByFrame.same then return colorsByFrame.color1 end

    local color = colorsByFrame[frameInd]
    if color then return color end

    local frac = frameInd / CHOICE_FRAME_COUNT
    local color1 = colorsByFrame.color1
    local color2 = colorsByFrame.color2

    color = lerpHSVAToRGB( frac, color1, color2 )
    colorsByFrame[frameInd] = color

    return color
end

moveColorUser = function( lookup, colorStr, uidOld, uidNew )
    local colorsByFrame = lookup[colorStr]
    if not colorsByFrame then return end

    local users = colorsByFrame.users

    users[uidOld] = nil
    users[uidNew] = true
end

nudgePolyUsers = function( menu, indStart, indEnd, dir )
    local menuNamePrepend = menu:GetName() .. "_"
    local pages = menu._pages

    for i = indStart, indEnd do
        local page = pages[i]
        local pageUID = menuNamePrepend .. i
        local pageUIDPrepend = pageUID .. "_"
        local pageUIDNew = menuNamePrepend .. ( i + dir )
        local pageUIDNewPrepend = pageUIDNew .. "_"
        local polyStr = page.polyStr

        if polyStr then
            local polySetsByFrame = choicePolySetsLookup[polyStr]
            local users = polySetsByFrame.users

            users[pageUID] = nil
            users[pageUIDNew] = true
        end

        for i2 = 1, #page do
            local choice = page[i2]
            local choiceUID = pageUIDPrepend .. i2
            local choiceUIDNew = pageUIDNewPrepend .. i2

            moveColorUser( choiceGradientColorsLookup, choice.gradientColorStr, choiceUID, choiceUIDNew )
            moveColorUser( choiceBandColorsLookup, choice.bandColorStr, choiceUID, choiceUIDNew )
            moveColorUser( choiceNameColorsLookup, choice.nameColorStr, choiceUID, choiceUIDNew )
        end
    end
end

nudgeColorUsers = function( page, pageUID, indStart, indEnd, dir )
    local pageUIDPrepend = pageUID .. "_"
    local polyStr = page.polyStr

    if polyStr then
        removePolyUser( pageUID, polyStr )
        page.polyStr = nil -- Invalidate polyStr; build it later when drawn.
    end

    for i = indStart, indEnd do
        local choice = page[i]
        local choiceUID = pageUIDPrepend .. i
        local choiceUIDNew = pageUIDPrepend .. ( i + dir )

        moveColorUser( choiceGradientColorsLookup, choice.gradientColorStr, choiceUID, choiceUIDNew )
        moveColorUser( choiceBandColorsLookup, choice.bandColorStr, choiceUID, choiceUIDNew )
        moveColorUser( choiceNameColorsLookup, choice.nameColorStr, choiceUID, choiceUIDNew )
    end
end

-- Instead of passing all args, (choice, menu) can be passed. Using all args is ideal when iterating a whole page.
getChoiceVisuals = function(
        choice,
        gradientEnabled, bandEnabled,
        gradientColorUnhovered,
        gradientColorHovered,
        bandColorUnhovered,
        bandColorHovered,
        nameColorUnhovered,
        nameColorHovered
    )

    -- This is terrible for maintenance, but great for performance. Likewise for a lot of the backend here...
    -- Menu defaults
    if bandEnabled == nil then
        local menu = gradientEnabled

        gradientEnabled = menu:IsChoiceGradientEnabled()
        bandEnabled = menu:IsChoiceBandEnabled()
        gradientColorUnhovered = menu._choiceGradientColorUnhovered
        gradientColorHovered = menu._choiceGradientColorHovered
        bandColorUnhovered = menu._choiceBandColorUnhovered
        bandColorHovered = menu._choiceBandColorHovered
        nameColorUnhovered = menu._choiceNameColorUnhovered
        nameColorHovered = menu._choiceNameColorHovered
    end

    -- Template defaults
    local template = choice.template
    local t

    if template then
        t = template.gradientEnabled
        if t ~= nil then gradientEnabled = t end

        t = template.bandEnabled
        if t ~= nil then bandEnabled = t end

        gradientColorUnhovered = template.gradientColorUnhovered
        gradientColorHovered = template.gradientColorHovered
        bandColorUnhovered = template.bandColorUnhovered
        bandColorHovered = template.bandColorHovered
        nameColorUnhovered = template.nameColorUnhovered
        nameColorHovered = template.nameColorHovered
    end

    -- Choice overrides
    t = choice.gradientEnabled
    if t ~= nil then gradientEnabled = t end

    t = choice.bandEnabled
    if t ~= nil then bandEnabled = t end

    return
        gradientEnabled, bandEnabled,
        choice.gradientColorUnhovered or gradientColorUnhovered,
        choice.gradientColorHovered or gradientColorHovered,
        choice.bandColorUnhovered or bandColorUnhovered,
        choice.bandColorHovered or bandColorHovered,
        choice.nameColorUnhovered or nameColorUnhovered,
        choice.nameColorHovered or nameColorHovered
end

editChoice = function(
        page, pageUIDPrepend, choiceInd, choice,
        choiceGradientEnabled, choiceBandEnabled,
        choiceGradientColorUnhovered,
        choiceGradientColorHovered,
        choiceBandColorUnhovered,
        choiceBandColorHovered,
        choiceNameColorUnhovered,
        choiceNameColorHovered
    )

    local realChoice = page[choiceInd]
    local choiceUID = pageUIDPrepend .. choiceInd
    local name = choice.name

    choiceGradientEnabled, choiceBandEnabled,
        choiceGradientColorUnhovered,
        choiceGradientColorHovered,
        choiceBandColorUnhovered,
        choiceBandColorHovered,
        choiceNameColorUnhovered,
        choiceNameColorHovered =
        getChoiceVisuals( choice, choiceGradientEnabled, choiceBandEnabled,
            choiceGradientColorUnhovered,
            choiceGradientColorHovered,
            choiceBandColorUnhovered,
            choiceBandColorHovered,
            choiceNameColorUnhovered,
            choiceNameColorHovered
        )

    realChoice.name = name
    realChoice.command = choice.command
    realChoice.menu = choice.menu
    realChoice.menuPageInd = choice.menuPageInd
    realChoice.func = choice.func
    realChoice.paint = choice.paint
    realChoice.paintRadial = choice.paintRadial
    realChoice.gradientEnabled = choiceGradientEnabled
    realChoice.bandEnabled = choiceBandEnabled

    if string.find( name, "\n" ) then
        realChoice.nameLines = string.Split( name, "\n" )
    else
        realChoice.nameLines = nil
    end

    local gradientColorStrOld = realChoice.gradientColorStr
    local bandColorStrOld = realChoice.bandColorStr
    local nameColorStrOld = realChoice.nameColorStr

    gradientColorStr = addColorUser( choiceGradientColorsLookup, choiceUID, choiceGradientColorUnhovered, choiceGradientColorHovered )
    bandColorStr = addColorUser( choiceBandColorsLookup, choiceUID, choiceBandColorUnhovered, choiceBandColorHovered )
    nameColorStr = addColorUser( choiceNameColorsLookup, choiceUID, choiceNameColorUnhovered, choiceNameColorHovered )

    if gradientColorStrOld and gradientColorStrOld ~= gradientColorStr then
        removeColorUser( choiceGradientColorsLookup, choiceUID, gradientColorStrOld )
    end

    if bandColorStrOld and bandColorStrOld ~= bandColorStr then
        removeColorUser( choiceBandColorsLookup, choiceUID, bandColorStrOld )
    end

    if nameColorStrOld and nameColorStrOld ~= nameColorStr then
        removeColorUser( choiceNameColorsLookup, choiceUID, nameColorStrOld )
    end

    realChoice.gradientColorStr = gradientColorStr
    realChoice.bandColorStr = bandColorStr
    realChoice.nameColorStr = nameColorStr

    if not realChoice._hoverProgress then
        realChoice._hoverProgress = 0
    end
end

-- ge can instead be replaced with a menu instance.
makeBlankChoice = function( template, ge, be, gcu, bcu, ncu )
    local choice = {
        name = "",
        func = function() end,
        template = template,
    }

    -- Get visuals, but use the unhovered colors only so the choice doesn't get highlighted.
    local _
    ge, be, gcu, _, bcu, _, ncu, _ = getChoiceVisuals( choice, ge, be, gcu, nil, bcu, nil, ncu, nil )
    gcu = cloneHSVA( gcu )
    bcu = cloneHSVA( bcu )
    ncu = cloneHSVA( ncu )

    choice.gradientEnabled = ge
    choice.bandEnabled = be
    choice.gradientColorUnhovered = gcu
    choice.gradientColorHovered = gcu
    choice.bandColorUnhovered = bcu
    choice.bandColorHovered = bcu
    choice.nameColorUnhovered = ncu
    choice.nameColorHovered = ncu

    return choice
end

validatePolyUser = function( menu, page, pageInd )
    local radiusHovered = menu._radiusHovered
    local radiusUnhovered = menu._radiusUnhovered
    local radiusInnerUnhovered = menu._radiusInnerUnhovered
    local radiusInnerHovered = menu._radiusInnerHovered
    local bandHeight = menu._bandHeight
    local choiceGap = menu._choiceGap

    local pageUID = menu:GetName() .. "_" .. pageInd
    local polyStr = addPolyUser( pageUID, radiusHovered, radiusUnhovered, radiusInnerUnhovered, radiusInnerHovered, bandHeight, choiceGap, #page )

    page.polyStr = polyStr

    return polyStr
end

handleChoiceClick = function()
    local curPageInd = curMenu:GetCurPageInd()
    local choice = curMenu._pages[curPageInd][hoveredInd]
    local command = choice.command
    local targetMenuName = choice.menu
    local func = choice.func

    hook.Run( "ModularRadialMenu_ChoiceClicked", curMenu, curPageInd, hoveredInd )

    if command then
        LocalPlayer():ConCommand( command )
    elseif targetMenuName then
        local targetMenu = menusByName[targetMenuName]

        if targetMenu then
            local prev = curMenu
            local pageInd = choice.menuPageInd

            hook.Run( "ModularRadialMenu_OnOpenedSubmenu", prev, targetMenu, pageInd )
            targetMenu:Open( pageInd )
        else
            ErrorNoHalt( "Couldn't find a ModularRadialMenu with the name of " .. targetMenuName )
        end
    elseif func then
        func( curMenu, curMenu:GetCurPageInd(), hoveredInd )
    end
end

resetHoverProgress = function( menu )
    local page = menu._pages[menu:GetCurPageInd()]

    for i = 1, #page do
        local choice = page[i]
        choice._hoverProgress = 0
    end
end

getColorEff = function( menu, pageInd, choiceInd, hoverProgress, lookup, storedName, colorStrName )
    local choice = menu._pages[pageInd][choiceInd]

    if not hoverProgress then
        local color = choice[storedName]
        if color then return color end

        hoverProgress = choice._hoverProgress -- Choice has yet to be rendered.
    end

    local frameInd = math.floor( hoverProgress * CHOICE_FRAME_COUNT )

    return getColorFrame( lookup, choice[colorStrName], frameInd )
end


----- SETUP -----

local memVec = uniformVector( 0 ) -- Intermediate vector for calculations to create less garbage memory.
local memVecScale = uniformVector( 1 )
local memAng = Angle( 0, 0, 0 )

hook.Add( "HUDPaint", "ModularRadialMenu_DrawCurrentMenu", function()
    if not curMenu then return end

    local scrH = ScrH()
    local nameAlign = curMenu:GetNameAlign()
    local menuNameY = 0
    local menuRadius = curMenu:GetRadiusEff()

    if nameAlign == TEXT_ALIGN_TOP then
        menuNameY = -menuRadius - curMenu:GetNameOffset() * scrH
    elseif nameAlign == TEXT_ALIGN_BOTTOM then
        menuNameY = menuRadius + curMenu:GetNameOffset() * scrH
    end

    local oldClipping = DisableClipping( true )
    cam.PushModelMatrix( matrCenter, true )

    -- Draw menu name
    local m = Matrix()
    memVec[2] = menuNameY
    m:Translate( memVec )
    m:Scale( VECTOR_MENU_NAME_SCALE )

    cam.PushModelMatrix( m, true )
    draw.SimpleText( curMenu:GetDisplayName(), mainFont, 0, 0, nil, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    cam.PopModelMatrix()

    -- Draw page number and count
    m = Matrix()
    memVec[2] = menuNameY + pageNumOffsetY
    m:Translate( memVec )
    m:Scale( VECTOR_PAGE_NAME_SCALE )

    local curPageInd = curMenu:GetCurPageInd()

    cam.PushModelMatrix( m, true )
    draw.SimpleText( "Page " .. curPageInd .. " / " .. curMenu:GetPageCount(), pageFont, 0, 0, nil, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    cam.PopModelMatrix()

    local pages = curMenu._pages
    local curPage = pages[curPageInd]
    local pageName = curPage.name

    -- Draw page name
    if pageName then
        m = Matrix()
        memVec[2] = menuNameY + pageNameOffsetY
        m:Translate( memVec )
        m:Scale( VECTOR_PAGE_NAME_SCALE )

        cam.PushModelMatrix( m, true )
        draw.SimpleText( pageName, pageFont, 0, 0, nil, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
        cam.PopModelMatrix()
    end

    local polyStr = curPage.polyStr

    -- Add poly users here instead of immediately on page creation/adjustment in case multiple operations are done in one frame.
    if not polyStr then
        polyStr = validatePolyUser( curMenu, curPage, curPageInd )
    end

    local degStep = 360 / #curPage
    local hoverDuration = curMenu:GetHoverDuration()
    local hoverDT = hoverDuration <= 0 and 1 or ( FrameTime() / hoverDuration )
    local polySetsByFrame = choicePolySetsLookup[polyStr]
    local choiceGradientPolys = polySetsByFrame.gradientPolys
    local choiceBandPolys = polySetsByFrame.bandPolys
    local choiceNameRadii = polySetsByFrame.nameRadii
    local arcWidthMult = math.pi * 2 / #curPage

    local menuFont = curMenu._fontStr
    local menuFontVecScale = curMenu._fontVecScale
    local menuFontHeight = curMenu._fontSize
    local menuFontScale = menuFontVecScale[1]
    local bandHeight = curMenu._bandHeight
    local choiceGap = curMenu._choiceGap

    local matrChoice = Matrix()
    memAng[2] = degStep

    paintArgs.menu = curMenu
    paintArgs.pageInd = curPageInd
    paintArgs.bandHeight = bandHeight

    paintRadialArgs.menu = curMenu
    paintRadialArgs.pageInd = curPageInd
    paintRadialArgs.bandHeight = bandHeight

    -- Draw choices
    for i, choice in ipairs( curPage ) do
        local deg = ( i - 1 ) * degStep
        local hoverProgress = choice._hoverProgress

        if i == hoveredInd then
            hoverProgress = math.min( hoverProgress + hoverDT, 1 )
        else
            hoverProgress = math.max( hoverProgress - hoverDT, 0 )
        end

        choice._hoverProgress = hoverProgress
        local frameInd = math.Round( hoverProgress * CHOICE_FRAME_COUNT )
        local gradientPoly = choiceGradientPolys[frameInd]

        if not gradientPoly then
            makePolyFrame( polySetsByFrame, frameInd, scrH )
            gradientPoly = choiceGradientPolys[frameInd]
        end

        cam.PushModelMatrix( matrChoice, true )

        local gradientColorEff = getColorFrame( choiceGradientColorsLookup, choice.gradientColorStr, frameInd )
        choice._gradientColorEff = gradientColorEff
        surface.SetMaterial( choice.gradientEnabled and matGradient or matWhite )
        surface.SetDrawColor( gradientColorEff )
        surface.DrawPoly( gradientPoly )

        if choice.bandEnabled then
            local bandColorEff = getColorFrame( choiceBandColorsLookup, choice.bandColorStr, frameInd )
            choice._bandColorEff = bandColorEff
            surface.SetMaterial( matWhite )
            surface.SetDrawColor( bandColorEff )
            surface.DrawPoly( choiceBandPolys[frameInd] )
        end

        local nameColorEff = getColorFrame( choiceNameColorsLookup, choice.nameColorStr, frameInd )
        choice._nameColorEff = nameColorEff

        local matrText = Matrix()
        local nameRadius = choiceNameRadii[frameInd]
        memVec[2] = -nameRadius
        matrText:Translate( memVec )

        if deg > 90 and deg < 270 then
            matrText:Rotate( Angle( 0, 180, 0 ) )
        end

        matrText:Scale( menuFontVecScale )
        surface.SetFont( menuFont )

        local nameLines = choice.nameLines
        local choiceWidth = nameRadius * ( 1 - choiceGap ) * arcWidthMult
        local textWidthLimit = choiceWidth * 0.875

        if nameLines then -- Multiline name
            local textWidthMax = 0
            local lineCount = #nameLines

            for _, line in ipairs( nameLines ) do
                local textWidth = surface.GetTextSize( line ) * menuFontScale

                if textWidth > textWidthMax then
                    textWidthMax = textWidth
                end
            end

            local textHeight = menuFontHeight * lineCount
            local textHeightLimit = bandHeight
            local textMultMax = math.max( textWidthMax / textWidthLimit, textHeight / textHeightLimit )

            if textMultMax > 1 then
                local textScale = 1 / textMultMax

                memVecScale[1] = textScale
                memVecScale[2] = textScale
                matrText:Scale( memVecScale )
            end

            local y = -menuFontHeight * ( ( lineCount - 1 ) / 2 ) / menuFontScale
            local yStep = menuFontHeight / menuFontScale

            cam.PushModelMatrix( matrText, true )

            for _, line in ipairs( nameLines ) do
                draw.SimpleText( line, menuFont, 0, y, nameColorEff, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
                y = y + yStep
            end

            cam.PopModelMatrix()
        else -- One-line name
            local name = choice.name
            local textWidth = surface.GetTextSize( name ) * menuFontScale

            -- Resize text that's a bit too big to fit.
            if textWidth > textWidthLimit then
                local textScale = textWidthLimit / textWidth

                memVecScale[1] = textScale
                memVecScale[2] = textScale
                matrText:Scale( memVecScale )
            end

            cam.PushModelMatrix( matrText, true )
            draw.SimpleText( name, menuFont, 0, 0, nameColorEff, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
            cam.PopModelMatrix()
        end

        local paintRadial = choice.paintRadial

        if paintRadial then
            paintRadialArgs.choiceRadius = nameRadius + bandHeight / 2
            paintRadialArgs.hovered = i == hoveredInd
            paintRadialArgs.choiceInd = i
            paintRadialArgs.hoverProgress = hoverProgress
            paintRadialArgs.choiceWidth = choiceWidth
            paintRadial( paintRadialArgs )
        end

        cam.PopModelMatrix() -- matrChoice

        matrChoice:Rotate( memAng )

        local paint = choice.paint

        if paint then
            local rad = math.rad( deg + 90 )
            paintArgs.xDir = -math.cos( rad )
            paintArgs.yDir = -math.sin( rad )
            paintArgs.choiceRadius = nameRadius + bandHeight / 2
            paintArgs.hovered = i == hoveredInd
            paintArgs.choiceInd = i
            paintArgs.hoverProgress = hoverProgress
            paintArgs.choiceWidth = choiceWidth
            paint( paintArgs )
        end
    end

    cam.PopModelMatrix() -- matrCenter
    DisableClipping( oldClipping )
end )

hook.Add( "Think", "ModularRadialMenu_TrackMouse", function()
    if not IsValid( curMenu ) then return end

    -- If open to a menu, but the cursor isn't visible, make it visible.
    if not vgui.CursorVisible() then
        hoveredInd = nil
        gui.EnableScreenClicker( true )

        return
    end

    local x, y = input.GetCursorPos()
    x = x - ScrW() * 0.5
    y = y - ScrH() * 0.5

    local radius = math.sqrt( x * x + y * y )

    if radius <= curMenu:GetDeadzoneRadiusEff() then
        hoveredInd = false -- False for if we have had time to detect a deadzone hover, nil for we have no idea.

        return
    end

    local rad = math.asin( y / radius )
    local choiceCount = curMenu:GetCurPageChoiceCount()
    local radPerChoice = 2 * MATH_PI / choiceCount

    rad = rad + MATH_PI / 2

    if x < 0 then
        rad = 2 * MATH_PI - rad
    end

    local nearestMult = nearestMultiple( rad, radPerChoice )

    hoveredInd = 1 + math.Round( nearestMult / radPerChoice ) % choiceCount
end )

hook.Add( "PlayerButtonDown", "ModularRadialMenu_Input", function( ply, key )
    if ply ~= LocalPlayer() then return end -- Should be redundtant, but for just in case.
    if not curMenu then return end
    if not IsFirstTimePredicted() then return end

    if key == MOUSE_LEFT then
        if hoveredInd then
            handleChoiceClick()
        elseif hoveredInd == false and curMenu:GetPageCount() > 1 then
            -- Previous page
            curMenu:SetCurPageInd( ( curMenu:GetCurPageInd() - 2 ) % curMenu:GetPageCount() + 1 )
        end
    elseif key == MOUSE_RIGHT then
        if hoveredInd == false then
            if curMenu:GetPageCount() > 1 then
                -- Next page
                curMenu:SetCurPageInd( ( curMenu:GetCurPageInd() % curMenu:GetPageCount() ) + 1 )
            end
        elseif hoveredInd then
            hook.Run( "ModularRadialMenu_InputPressed", curMenu, key )
        end
    else
        hook.Run( "ModularRadialMenu_InputPressed", curMenu, key )
    end
end )


mainFont = makeFont( "Roboto Mono", MAIN_FONT_SIZE, 400, true, MAIN_FONT_OUTLINE, MAIN_FONT_OUTLINE_THINNESS )
pageFont = makeFont( "Roboto Mono", PAGE_FONT_SIZE, 400, true, MAIN_FONT_OUTLINE, MAIN_FONT_OUTLINE_THINNESS )

hook.Run( "ModularRadialMenu_LibraryLoaded" )
