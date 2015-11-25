#!/usr/bin/make -f

#######################################################################
### EDIT THESE PATHS FOR YOUR OWN SETUP                             ###
#######################################################################

SOURCEMOD_DIR=/home/steam/Steam/steamapps/common/Left 4 Dead 2 Dedicated Server/left4dead2/addons/sourcemod

#######################################################################
### SHOULD NOT HAVE TO EDIT BELOW HERE                              ###
#######################################################################

SOURCE_FILES        := $(wildcard *.sp)
SMX_FILES           := $(SOURCE_FILES:.sp=.smx)
DIR                 := $(shell pwd)

all: install

install: compile

compile: $(SMX_FILES)

%.smx:
	@cp $(@:.smx=.sp) "$(SOURCEMOD_DIR)/scripting/$(@:.smx=.sp)"
	@"$(SOURCEMOD_DIR)/scripting/compile.sh" $(@:.smx=.sp)

.PHONY: all install compile
