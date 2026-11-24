fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Clay'
description 'Busking hat and live Top 3 tipping system for QBox'
version '1.0.0'

dependencies {
    'ox_lib',
    'ox_inventory',
    'qbx_core',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/rules.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/selfcheck.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/**/*',
}
