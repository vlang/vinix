#!/bin/sh
# Run inside a Vinix image to prove the interactive login shell can load its
# bundled Oh My Zsh configuration without network access.
set -eu

export HOME=/root
export TERM=${TERM:-linux}

echo "VINIX ZSH + OH MY ZSH TEST"
test -x /bin/zsh
test -r /root/.oh-my-zsh/oh-my-zsh.sh
test -r /root/.zshrc
test -r /etc/zsh/zprofile

/bin/zsh -lic '
    [[ "$ZSH" == /root/.oh-my-zsh ]]
    [[ -r "$ZSH/oh-my-zsh.sh" ]]
    (( $+functions[omz] ))
    print -r -- "zsh=$ZSH_VERSION"
    print -r -- "oh-my-zsh=$ZSH"
'

echo "VINIX ZSH + OH MY ZSH TEST: PASS"
