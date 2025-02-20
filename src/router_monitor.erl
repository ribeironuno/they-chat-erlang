-module(router_monitor).
-export([start/2]).

%% It starts the router_monitor and must be called by the router in order to create a monitor ref to it
start(BackupMap, RouterPid) ->
  io:format("[router_monitor] Router monitor is up on pid ~p ~n", [self()]),
  monitor(process, RouterPid),
  io:format("[router_monitor] Monitoring router at ~p ~n", [RouterPid]),
  loop(BackupMap).

%% Loop router monitor function
%%
%% BackupMap : The server list backup that it will be sent to the router in case of a router failure
loop(BackupMap) ->
  receive

    {NewTopic, NewNode, add} ->
      io:format("[router_monitor] Received an update to add a server: ~p ~n", [NewTopic]),
      NewBackup = server_add(NewTopic, NewNode, BackupMap),
      loop(NewBackup);

    {TopicToRemove, remove} ->
      io:format("[router_monitor] Received an update to remove a server: ~p ~n", [TopicToRemove]),
      NewBackup = server_remove(TopicToRemove, BackupMap),
      loop(NewBackup);

    {'DOWN', Ref, process, _, _} ->
      demonitor(Ref),
      io:format("[router_monitor] Router went down~n", []),
      RouterPid = element(1, spawn_monitor(router, start_by_monitor, [BackupMap, self()])),
      register(router, RouterPid),
      loop(BackupMap)
  end.

server_add(Topic, NewNode, BackupMap) ->
  maps:put(Topic, NewNode, BackupMap).

server_remove(Topic, BackupMap) ->
  maps:remove(Topic, BackupMap).