-- Mod Settings
name = "Artifical Wilson"
description = "Tired of playing the game? Let the game play for you....with friends!\n" ..
               "Click on the Brain to activate AI mode\n" ..
               "Right Click on the Brain to make a friend\n" ..
               "Check out Configuration Settings"
author = "KingofTown"
version = "1.06"
forumthread = "None"
icon_atlas = "modicon.xml"
icon = "modicon.tex"


priority = 15
dst_compatible = true
api_version = 10

all_clients_require_mod = true
client_only_mod = false

server_filter_tags = {"AI", "Artificial Wilson"}

configuration_options =
{
   {
        name = "MaxClones",
        label = "Max Clones Per Player",
        options = {
            {description = "0",     data = 0},
            {description = "1",     data = 1},
            {description = "2",     data = 2},
            {description = "5",     data = 5},
            {description = "10",    data = 10},
            {description = "15",    data = 15},
            {description = "20",    data = 20},
            {description = "100",   data = 100}
        },
        default = 15,
        hover = "Default is 15",
   },
   {
    name = "CloneType",
    label = "Spawned Friend Type",
    options = {
        {description = "random",    data = "random"},
        {description = "clone",     data = "clone"},
        {description = "wortox",    data = "wortox"},
    },
    default = "random",
    },
    {
        name = "CloneDeath",
        label = "Clone Death",
        options = {
            {description = "ghost",    data = "ghost"},
            {description = "remove",   data = "remove"},
        },
        default = "ghost",
    },
    {
        name = "LogLevel",
        label = "Console Log Level",
        options = {
            {description = "none", data = "none"},
            {description = "verbose", data = "AIDebugPrint"},
        },
        default = "none"
    },
    {
        name = "CheatMode",
        label = "Cheats",
        options = {
            {description = "diabled", data = "disabled"},
            {description = "enabled", data = "enabled"},
        },
        default = "none",
        hover = "There is a man behind you",
    },
    {
        name = "Revenge",
        label = "Revenge?",
        options = {
            {description = "diabled", data = "disabled"},
            {description = "enabled", data = "enabled"},
        },
        default = "disabled",
        hover = "It wasn't a fair fight",
    },
}