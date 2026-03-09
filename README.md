# Modular Radial Menu
A heavily customizable, highly performant radial menu class. \
Each menu can have multiple pages, cycled through with left/right click while hovering over the center.


## Basic Usage / Examples
The minimum three things any radial menu setup needs are `ModularRadialMenu.New()`, `:Open()`, and `:Close()`. \
The first of these creates the menu and defines the appearance and functionality of its pages and choices. \
The other two should be called as required by your script, such as opening when holding a specific key and closing when the player lets go of it. \
Various other static and instance functions can be used to edit the menu or auto-generate pages in specific ways. \
See [modular_radial_menu.lua](/lua/modular_radial_menu/client/modular_radial_menu.lua) for more info.


### Example 1
```lua
if IsValid( TEST_MENU ) then TEST_MENU:Destroy() end -- Auto-destroy old menu for testing around in luapad

TEST_MENU = ModularRadialMenu.New( "test", "Test Menu", {
    [1] = {
        name = "Foo",
        [1] = {
            name = "say foo",
            command = "say foo",
        },
        [2] = {
            name = "PAGE 2",
            menu = "test",
            menuPageInd = 2,
        },
        [3] = {
            name = "print",
            func = function( menu, pageInd, choiceInd )
                LocalPlayer():ChatPrint( menu .. " " .. pageInd .. " " .. choiceInd )
            end,
        },
        [4] = {
            name = "CLOSE",
            func = function( menu, pageInd, choiceInd )
                menu:Close()
            end,
        },
        [5] = ModularRadialMenu.MakeBlankChoice(),
    },
    [2] = {
        name = "Bar",
        [1] = {
            name = "say bar",
            command = "say bar",
        },
        [2] = {
            name = "PAGE 1",
            menu = "test",
            menuPageInd = 1,
        },
        [3] = {
            name = "print",
            func = function( menu, pageInd, choiceInd )
                LocalPlayer():ChatPrint( menu .. " " .. pageInd .. " " .. choiceInd )
            end,
        },
        [4] = {
            name = "CLOSE",
            func = function( menu, pageInd, choiceInd )
                menu:Close()
            end,
        },
    },
} )

TEST_MENU:Open() -- Open it only once. If it closes, it won't open again unless some other script calls TEST_MENU:Open()
```
The above code results in a simple menu with the following two pages:
![Example 1](https://i.imgur.com/mDLyXg9.png "Example 1")


### Example 2
```lua
if IsValid( TEST_MENU ) then TEST_MENU:Destroy() end -- Auto-destroy old menu for testing around in luapad

local numChoices = 20
local choicesPerPage = 12

local choices = {}

for i = 1, numChoices do
    local hue = 360 * ( i - 1 ) / numChoices

    choices[i] = {
        name = "choice " .. i,
        func = function() end,
        gradientColorUnhovered = { hue, 0.08, 0.19, 255 },
        gradientColorHovered = { hue, 1, 1, 255 },
        bandColorUnhovered = { hue, 0.08, 0.19, 255 },
        bandColorHovered = { hue, 1, 1, 255 },
        nameColorUnhovered = { 0, 0, 1, 255 },
        nameColorHovered = { 0, 0, 1, 255 },
    }
end

local pages = ModularRadialMenu.MakePagesFromChoiceList( choices, choicesPerPage )
TEST_MENU = ModularRadialMenu.New( "test", "Test Menu", pages )

TEST_MENU:Open() -- Open it only once. If it closes, it won't open again unless some other script calls TEST_MENU:Open()
```
The above code results in the following menu:
![Example 2.1](https://i.imgur.com/W8NfbDo.gif "Example 2.1")

If you then replace the `local pages = ...` line with this snippet...
```lua
local pages = ModularRadialMenu.MakePagesFromChoiceList( choices, choicesPerPage, {
    topChoice = {
        name = "CLOSE",
        func = function( menu ) menu:Close() end,
    },
} )
```
...A close button will be added to each page:
![Example 2.2](https://i.imgur.com/FGLBUr6.gif "Example 2.2")


## Hooks
- ModularRadialMenu_LibraryLoaded()
    - Called whenever this library is (re)loaded.
    - Reloads should only happen if the library is being edited and dev-tested.
    - Reloads will cause all former ModularRadialMenus to be destroyed, and they cannot be re-made until after this is called.
    - During reloads, all ModularRadialMenu instances will have `self.classIsReloading = true`.
- ModularRadialMenu_OnClosed( menu, fromOtherOpening, dontHideCursor )
    - Called when a menu is closed.
    - `menu`: (ModularRadialMenu)
        - The ModularRadialMenu that was closed.
    - `fromOtherOpening`: (boolean)
        - Whether the menu was closed because another menu was opened.
    - `dontHideCursor`: (boolean)
        - True if the menu was told to not hide the cursor.
- ModularRadialMenu_OnOpened( prevMenu, curMenu, pageInd )
    - Called when a menu is opened.
    - `prevMenu`: (ModularRadialMenu or nil)
        - The menu that was closed in order to open the new one.
        - nil if no menu was open when the new one was opened.
    - `curMenu`: (ModularRadialMenu)
        - The menu that was opened.
    - `pageInd`: (number or nil)
        - The page number the menu was opened to, if specified.
        - If nil, check the menu's current page.
- ModularRadialMenu_OnDestroyed( menu )
    - Called when a menu is about to be destroyed, before `:OnDestroyed()` runs.
    - `menu`: (ModularRadialMenu)
        - The menu that is being destroyed.
- ModularRadialMenu_ChoiceClicked( menu, pageInd, choiceInd )
    - Called when a menu's choice is left-clicked.
    - Called immediately before processing the choice's action.
    - Useful for adding universal behaviour like clicking sounds.
    - `menu`: (ModularRadialMenu)
        - The menu that was clicked.
    - `pageInd`: (number)
        - The page number of the choice that was clicked.
    - `choiceInd`: (number)
        - The index of the choice that was clicked.
- ModularRadialMenu_OnOpenedSubmenu( prevMenu, curMenu, pageInd )
    - Called when a menu is opened directly from the 'menu' parameter of a choice.
    - Called immediately before the menu is opened.
    - `prevMenu`: (ModularRadialMenu)
        - The menu whose choice was clicked to open the new one.
    - `curMenu`: (ModularRadialMenu)
        - The menu that was opened.
    - `pageInd`: (number or nil)
        - The page number the menu was opened to, if specified.
        - If nil, check the menu's current page.
- ModularRadialMenu_InputPressed( menu, key )
    - Called when a key is pressed with a menu open.
    - Never called for the left mouse button.
    - Never called for the right mouse button when not hovering a choice.
    - `menu`: (ModularRadialMenu)
        - The menu that is open.
    - `key`: (number)
        - The key that was pressed.
        - A member of the KEY or MOUSE enums.
