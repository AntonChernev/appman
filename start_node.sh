#!/bin/bash

cd $2
elixir --name $1@127.0.0.1 --detached -S mix run --no-compile --no-halt
