#!/bin/bash
# Developed by Qwertimer
# Program in development. This program will look in the current
# directory and pipe the results to fzf when you select the item if it
# is an item it should change to that directory otherwise it will open
# the program.program

f() {

  ITEM=$(ls | fzf) 

  [[ -f $ITEM ]] && exec xdg-open $ITEM
  [[ -d $ITEM ]] && cd $ITEM
}


f 
