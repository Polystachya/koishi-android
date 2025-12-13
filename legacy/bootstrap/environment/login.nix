{ writeScriptBin, lib }:
with builtins;
with lib;
let
in writeScriptBin "login" ''
    set -e
    
    # Set timezone if specified
    if [ -n "$KOISHI_TIMEZONE" ] && [ -e /etc/zoneinfo ]; then
        /bin/ln -sf /etc/zoneinfo/$KOISHI_TIMEZONE /etc/localtime
        echo "Timezone set to $KOISHI_TIMEZONE"
    fi
    
    # Set DNS if specified
    if [ -n "$KOISHI_DNS" ]; then
        echo "nameserver $KOISHI_DNS" > /etc/resolv.conf
        echo "DNS set to $KOISHI_DNS"
    fi
    
    # Clean environment for security
    for var in $(/bin/env | /bin/cut -d '=' -f 1); do 
        unset $var
    done
    
    # Set essential environment variables
    export PATH=/bin
    export HOME=/home
    export TZ=''${KOISHI_TIMEZONE:-UTC}
    
    # Change to home directory
    cd $HOME
    
    # Execute command with proper error handling
    if [ $# -eq 0 ]; then
        exec sh
    else
        exec sh "$@"
    fi
''