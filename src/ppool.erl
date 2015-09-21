%%%-------------------------------------------------------------------
%%% @author skell
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Sep 2015 4:00 PM
%%%-------------------------------------------------------------------
-module(ppool).
-author("skell").

%% API
-behaviour(application).
-export([start/2, stop/1, start_pool/3, run/2, sync_queue/2, async_queue/2, stop_pool/1]).

start(normal, _Args) ->
  ppool_supersup:start_link().

stop(_State) ->
  ok.

start_pool(Name, Limit, {M,F,A}) ->
  ppool_supersup:start_pool(Name, Limit, {M,F,A}).

stop_pool(Name) ->
  ppool_supersup:stop_pool(Name).

run(Name, Args) ->
  ppool_serv:run(Name, Args).

async_queue(Name, Args) ->
  ppool_serv:async_queue(Name, Args).

sync_queue(Name, Args) ->
  ppool_serv:sync_queue(Name, Args).

