-module(server_chat).
-export([start/1]).

%% Defines the atom to the file name and to the table name of DETS
%% The logic behind this is to have a unique name per VM
-define(DETS_TABLE, list_to_atom(atom_to_list(clients) ++ "@" ++ atom_to_list(node()))).
-define(DETS_FILE, list_to_atom("database/" ++ atom_to_list(?DETS_TABLE) ++ ".dets")).

%% Function to be called by the monitor to restart the router after it has stopped
%% It's starts by reading the clients from the DB, and it will do a ping to each one in order to remove 'offline' users
start(MonitorPid) ->
  case dets:open_file(?DETS_TABLE, [{file, ?DETS_FILE}]) of
    {ok, _} ->
      io:format("[server_chat] DETS table ~p opened successfully~n", [?DETS_TABLE]);
    {error, Reason} ->
      io:format("[server_chat] Failed to open DETS table: ~p~n", [Reason]),
      exit(Reason)
  end,
  monitor(process, MonitorPid),
  process_flag(trap_exit, true),
  io:format("[server_chat] Chat is up on pid ~p ~n", [self()]),
  ClientsMap = ping_clients(load_clients_from_db()),
  loop(ClientsMap, MonitorPid).

%% Loop server_chat function to be called recursively
%%
%% ClientsMap : Structure that maps the #{ClientPid -> Username}
%% MonitorPid : Pid of the monitor
loop(ClientsMap, MonitorPid) ->
  receive

    {From, Username, enter} ->
      case client_exists(ClientsMap, From) of
        true ->
          From ! {fail},
          loop(ClientsMap, MonitorPid);
        false ->
          link(From),
          NewMap = add_client(ClientsMap, From, Username),
          io:format("[server_chat] User ~p ~p connected~n", [From, Username]),
          From ! {ok},
          loop(NewMap, MonitorPid)
      end;

    {From, leave} ->
      case client_exists(ClientsMap, From) of
        true ->
          unlink(From),
          NewMap = remove_client(ClientsMap, From),
          io:format("[server_chat] User ~p ~p disconnected~n", [From, get_username(ClientsMap, From)]),
          From ! {ok},
          loop(NewMap, MonitorPid);
        false ->
          From ! {fail},
          loop(ClientsMap, MonitorPid)
      end;

    {From, send_message, Message} ->
      send_msg_to_all(ClientsMap, From, Message),
      loop(ClientsMap, MonitorPid);

    {list_clients} ->
      io:format("[server_chat] Clients map ~p~n", [ClientsMap]),
      loop(ClientsMap, MonitorPid);

  %% --- Monitor API ---

    {'DOWN', _Ref, process, _Pid, _Reason} ->
      demonitor(_Ref),
      io:format("[server_chat] Server monitor ~p went down. Waiting recover ...~n", [_Pid]),
      %% Waits for the ping from the server monitor
      receive
        {From, ping} ->
          From ! {self(), pong},
          monitor(process, From),
          io:format("[server_chat] Server monitor ~p is back. Continue operating ...~n", [From]),
          loop(ClientsMap, MonitorPid)
      after 5000 ->
        io:format("[server_chat] Server monitor ~p did not responded. Exiting ...~n", [_Pid])
      end;

  %% --- Link API ---

    {'EXIT', Pid, _} ->
      NewMap = remove_client(ClientsMap, Pid),
      io:format("[server_chat] User ~p ~p disconnected abruptly~n", [Pid, get_username(ClientsMap, Pid)]),
      loop(NewMap, MonitorPid)

  end.

%% Helper functions

client_exists(ClientsMap, From) ->
  maps:is_key(From, ClientsMap).

add_client(ClientsMap, From, Username) ->
  dets:insert(?DETS_TABLE, {From, Username}),
  maps:put(From, Username, ClientsMap).

remove_client(ClientsMap, From) ->
  dets:delete(?DETS_TABLE, From),
  maps:remove(From, ClientsMap).

get_username(ClientsMap, From) ->
  try
    maps:get(From, ClientsMap)
  catch
    _:_ -> not_found
  end.

load_clients_from_db() ->
  ClientList = dets:match(?DETS_TABLE, {'$1', '$2'}), %% Result is [[a,b], ...]
  TupleClientList = lists:map(fun([Key, Value]) -> {Key, Value} end, ClientList),
  io:format("[server_chat] ClientList ~p~n", [TupleClientList]),
  maps:from_list(TupleClientList).

send_msg_to_all(ClientsMap, Sender, Message) ->
  Receivers = maps:keys(ClientsMap),
  SenderUsername = get_username(ClientsMap, Sender),
  [Receiver ! {receive_message, {Sender, SenderUsername = get_username(ClientsMap, Sender)}, Message} || Receiver <- Receivers, Receiver /= Sender].

%% Iterates over the clients list and pings them to inform that chat is active again
ping_clients(ClientsMap) ->
  io:format("[server_chat] Clients to ping ~p~n", [ClientsMap]),
  maps:fold(
    fun(ClientPid, Username, Acc) ->
      io:format("[server_chat] Pinging ~p => ~p ...~n", [Username, ClientPid]),
      Result = ClientPid ! {self(), ping},
      try Result of
        _ ->
          receive
            {_, pong} ->
              io:format("[server_chat] Received pong ~p~n", [Username]),
              maps:put(ClientPid, Username, Acc)
          after 1000 ->
            io:format("[server_chat] Client ~p did not respond~n", [Username]),
            dets:delete(?DETS_TABLE, ClientPid),
            Acc
          end
      catch
        _:_ ->
          io:format("[server_chat] Failed to send ping to ~p~n", [Username]),
          dets:delete(?DETS_TABLE, ClientPid),
          Acc
      end
    end, maps:new(), ClientsMap).
