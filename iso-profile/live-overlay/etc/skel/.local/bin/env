#!/bin/sh
# add binaries to PATH if they aren't added yet
# affix colons on either side of $PATH to simplify matching
case ":${PATH}:" in
    *:"$HOME/.local/share/../bin":*)
        ;;
    *)
        # Prepending path in case a system-installed binary needs to be overridden
        export PATH="$HOME/.local/share/../bin:$PATH"
        ;;
esac
