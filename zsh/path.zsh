export PATH="$PATH:/usr/local/sbin"
export PATH="$PATH:$HOME/.fzf/bin"

OS=`uname`
case OS in
  "Darwin" ) # requires gnu-sed
    # MySQL
    export PATH="$PATH:/usr/local/opt/mysql@5.6/bin"
    export PATH="$PATH:/usr/local/opt/mysql@5.7/bin"

    # PostgreSQL
    export PATH="$PATH:/Applications/Postgres.app/Contents/Versions/latest/bin"

    # Node.js
    export NVM_DIR="$HOME/.nvm"
    NODE_DEFAULT=versions/node/$(cat $NVM_DIR/alias/default)
    export PATH="$PATH:$NVM_DIR/$NODE_DEFAULT/bin" # this requires $ nvm alias default vX.Y.Z
    MANPATH="$PATH:$NVM_DIR/$NODE_DEFAULT/share/man"
    NODE_PATH=$NVM_DIR/$NODE_DEFAULT/lib/node_modules
    export NODE_PATH=${NODE_PATH:A}

    # VScode
    export PATH="$PATH:/usr/local/bin/code"

    # Python
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PATH:$PYENV_ROOT/bin"

    # Go
    export GOPATH=$HOME/go
    export PATH="$PATH:$GOPATH/bin"

    # Android
    export ANDROID_HOME=~/Library/Android/sdk
    export PATH="$PATH:$ANDROID_HOME/tools"
    export PATH="$PATH:$ANDROID_HOME/tools/bin"
    export PATH="$PATH:$ANDROID_HOME/platform-tools"
    export ANDROID_SDK=$ANDROID_HOME

    # Deno
    export PATH="$PATH:$HOME/.deno/bin"

    # Flutter
    export PATH="$PATH:$HOME/flutter/bin"
    export PATH="$PATH:$HOME/flutter/.pub-cache/bin"

    # protobuf
    export PATH="$PATH:$HOME/protoc-3.7.1-osx-x86_64/bin"

    # Swift
    export SOURCEKIT_TOOLCHAIN_PATH=/Library/Developer/Toolchains/swift-latest.xctoolchain

    # Rust
    export PATH="$PATH:~/.cargo/env"
  ;;

  "Linux" )
    export PATH="$PATH:$HOME/hub-linux-arm64-2.6.0/bin/hub"
  ;;
esac
