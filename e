#!/bin/bash

#Description: Fast edit of configuration files. Does not crowd aliases and is available anywhere my scripts are.
check() {
  case $1 in
    bash | b)
      file="$HOME/.bashrc"
      ;;
    vim | v)
      file="$HOME/.vimrc"
      ;;

    sxhkd)
      file="$HOME/.config/sxhkd/sxhkdrc"
      ;;

    bsp*)
      file="$HOME/.config/bspwm/bspwmrc"
      ;;
    wm)
      ## TODO: Get wm with wmctrl and open wm config based on NAME..... Not sure if needed.
      ;;
    l)
      file=lol
      ;;
  esac
  _is_file "$file" && edit "$file" || exit
}
edit(){
    exec vim "$1"
}


# -------------------------------- file check --------------------------------
_is_file(){
  if [ -f "$1" ]; then
    :
  else
    warn "file does not exist"
   exit
  fi
}


check $1


