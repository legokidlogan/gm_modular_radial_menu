AddCSLuaFile()
AddCSLuaFile( "modular_radial_menu/client/modular_radial_menu.lua" )

if SERVER then
    resource.AddFile( "resource/fonts/RobotoMono.ttf" )
else
    include( "modular_radial_menu/client/modular_radial_menu.lua" )
end
