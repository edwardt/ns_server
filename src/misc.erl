% Copyright (c) 2009, NorthScale, Inc.
% Copyright (c) 2008, Cliff Moon
% Copyright (c) 2008, Powerset, Inc
%
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions
% are met:
%
% * Redistributions of source code must retain the above copyright
% notice, this list of conditions and the following disclaimer.
% * Redistributions in binary form must reproduce the above copyright
% notice, this list of conditions and the following disclaimer in the
% documentation and/or other materials provided with the distribution.
% * Neither the name of Powerset, Inc nor the names of its
% contributors may be used to endorse or promote products derived from
% this software without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
% COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.
%
% Original Author: Cliff Moon

-module(misc).

-include("ns_common.hrl").
-include_lib("kernel/include/file.hrl").

-define(FNV_OFFSET_BASIS, 2166136261).
-define(FNV_PRIME,        16777619).

-compile(export_all).

-define(prof(Label), true).
-define(forp(Label), true).
-define(balance_prof, true).

shuffle(List) when is_list(List) ->
    [N || {_R, N} <- lists:keysort(1, [{random:uniform(), X} || X <- List])].

pmap(Fun, List, ReturnNum) ->
    ?MODULE:pmap(Fun, List, ReturnNum, infinity).

pmap(Fun, List, ReturnNum, Timeout) ->
    C = length(List),
    N = case ReturnNum > C of
            true  -> C;
            false -> ReturnNum
        end,
    SuperParent = self(),
    SuperRef = erlang:make_ref(),
    Ref = erlang:make_ref(),
    %% Spawn an intermediary to collect the results this is so that
    %% there will be no leaked messages sitting in our mailbox.
    Parent = spawn(fun () ->
                       L = gather(N, length(List), Ref, []),
                       SuperParent ! {SuperRef, pmap_sort(List, L)}
                   end),
    Pids = [spawn(fun () ->
                      Ret = (catch Fun(Elem)),
                      Parent ! {Ref, {Elem, Ret}}
                  end) || Elem <- List],
    Ret2 = receive
              {SuperRef, Ret} -> Ret
           after Timeout ->
              {error, timeout}
           end,
    % TODO: Need cleanup here?
    lists:foreach(fun(P) -> exit(P, die) end, Pids),
    Ret2.

pmap_sort(Original, Results) ->
    pmap_sort([], Original, lists:reverse(Results)).

pmap_sort(Sorted, _, []) -> lists:reverse(Sorted);
pmap_sort(Sorted, [E | Original], Results) ->
    case lists:keytake(E, 1, Results) of
        {value, {E, Val}, Rest} -> pmap_sort([Val | Sorted], Original, Rest);
        false                   -> pmap_sort(Sorted, Original, Results)
    end.

gather(_, Max, _, L) when length(L) >= Max -> L;
gather(0, _, _, L) -> L;
gather(N, Max, Ref, L) ->
    receive
        {Ref, {_Elem, {'EXIT', _}} = ElemRet} ->
            gather(N, Max, Ref, [ElemRet | L]);
        {Ref, ElemRet} ->
            gather(N - 1, Max, Ref, [ElemRet | L])
    end.

sys_info_collect_loop(FilePath) ->
    {ok, IO} = file:open(FilePath, [write]),
    sys_info(IO),
    file:close(IO),
    receive
        stop -> ok
    after 5000 -> sys_info_collect_loop(FilePath)
    end.

sys_info(IO) ->
    ok = io:format(IO, "count ~p~n", [erlang:system_info(process_count)]),
    ok = io:format(IO, "memory ~p~n", [erlang:memory()]),
    ok = file:write(IO, erlang:system_info(procs)).

rm_rf(Name) when is_list(Name) ->
  case filelib:is_dir(Name) of
    false ->
      file:delete(Name);
    true ->
      case file:list_dir(Name) of
          {ok, Filenames} ->
              lists:foreach(
                fun rm_rf/1,
                [filename:join(Name, F) || F <- Filenames]),
              file:del_dir(Name);
          {error, Reason} ->
              error_logger:info_msg("rm_rf failed because ~p~n",
                                    [Reason])
      end
  end.

space_split(Bin) ->
    byte_split(Bin, 32). % ASCII space is 32.

zero_split(Bin) ->
    byte_split(Bin, 0).

byte_split(Bin, C) ->
    byte_split(0, Bin, C).

byte_split(N, Bin, _C) when N > erlang:byte_size(Bin) -> Bin;

byte_split(N, Bin, C) ->
    case Bin of
        <<_:N/binary, C:8, _/binary>> -> split_binary(Bin, N);
        _ -> byte_split(N + 1, Bin, C)
    end.

rand_str(N) ->
  lists:map(fun(_I) ->
      random:uniform(26) + $a - 1
    end, lists:seq(1,N)).

nthreplace(N, E, List) ->
  lists:sublist(List, N-1) ++ [E] ++ lists:nthtail(N, List).

nthdelete(N, List)        -> nthdelete(N, List, []).
nthdelete(0, List, Ret)   -> lists:reverse(Ret) ++ List;
nthdelete(_, [], Ret)     -> lists:reverse(Ret);
nthdelete(1, [_E|L], Ret) -> nthdelete(0, L, Ret);
nthdelete(N, [E|L], Ret)  -> nthdelete(N-1, L, [E|Ret]).

floor(X) ->
  T = erlang:trunc(X),
  case (X - T) of
    Neg when Neg < 0 -> T - 1;
    Pos when Pos > 0 -> T;
    _ -> T
  end.

ceiling(X) ->
  T = erlang:trunc(X),
  case (X - T) of
    Neg when Neg < 0 -> T;
    Pos when Pos > 0 -> T + 1;
    _ -> T
  end.

succ([])  -> [];
succ(Str) -> succ_int(lists:reverse(Str), []).

succ_int([Char|Str], Acc) ->
  if
    Char >= $z -> succ_int(Str, [$a|Acc]);
    true -> lists:reverse(lists:reverse([Char+1|Acc]) ++ Str)
  end.

fast_acc(_, Acc, 0)   -> Acc;
fast_acc(Fun, Acc, N) -> fast_acc(Fun, Fun(Acc), N-1).

hash(Term) ->
  ?prof(hash),
  R = fnv(Term),
  ?forp(hash),
  R.

hash(Term, Seed) -> hash({Term, Seed}).

% 32 bit fnv. magic numbers ahoy
fnv(Term) when is_binary(Term) ->
  fnv_int(?FNV_OFFSET_BASIS, 0, Term);

fnv(Term) ->
  fnv_int(?FNV_OFFSET_BASIS, 0, term_to_binary(Term)).

fnv_int(Hash, ByteOffset, Bin) when erlang:byte_size(Bin) == ByteOffset ->
  Hash;

fnv_int(Hash, ByteOffset, Bin) ->
  <<_:ByteOffset/binary, Octet:8, _/binary>> = Bin,
  Xord = Hash bxor Octet,
  fnv_int((Xord * ?FNV_PRIME) rem (2 bsl 31), ByteOffset+1, Bin).

position(Predicate, List) when is_function(Predicate) ->
  position(Predicate, List, 1);

position(E, List) ->
  position(E, List, 1).

position(Predicate, [], _N) when is_function(Predicate) -> false;

position(Predicate, [E|List], N) when is_function(Predicate) ->
  case Predicate(E) of
    true -> N;
    false -> position(Predicate, List, N+1)
  end;

position(_, [], _) -> false;

position(E, [E|_List], N) -> N;

position(E, [_|List], N) -> position(E, List, N+1).

now_int()   -> time_to_epoch_int(now()).
now_float() -> time_to_epoch_float(now()).

time_to_epoch_int(Time) when is_integer(Time) or is_float(Time) ->
  Time;

time_to_epoch_int({Mega,Sec,_}) ->
  Mega * 1000000 + Sec.

time_to_epoch_ms_int({Mega,Sec,Micro}) ->
  (Mega * 1000000 + Sec) * 1000 + (Micro div 1000).

time_to_epoch_float(Time) when is_integer(Time) or is_float(Time) ->
  Time;

time_to_epoch_float({Mega,Sec,Micro}) ->
  Mega * 1000000 + Sec + Micro / 1000000;

time_to_epoch_float(_) ->
  undefined.

byte_size(List) when is_list(List) ->
  lists:foldl(fun(El, Acc) -> Acc + ?MODULE:byte_size(El) end, 0, List);

byte_size(Term) ->
  erlang:byte_size(Term).

listify(List) when is_list(List) ->
  List;

listify(El) -> [El].

reverse_bits(V) when is_integer(V) ->
  % swap odd and even bits
  V1 = ((V bsr 1) band 16#55555555) bor
        (((V band 16#55555555) bsl 1) band 16#ffffffff),
  % swap consecutive pairs
  V2 = ((V1 bsr 2) band 16#33333333) bor
        (((V1 band 16#33333333) bsl 2) band 16#ffffffff),
  % swap nibbles ...
  V3 = ((V2 bsr 4) band 16#0F0F0F0F) bor
        (((V2 band 16#0F0F0F0F) bsl 4) band 16#ffffffff),
  % swap bytes
  V4 = ((V3 bsr 8) band 16#00FF00FF) bor
        (((V3 band 16#00FF00FF) bsl 8) band 16#ffffffff),
  % swap 2-byte long pairs
  ((V4 bsr 16) band 16#ffffffff) bor ((V4 bsl 16) band 16#ffffffff).

load_start_apps([]) -> ok;

load_start_apps([App | Apps]) ->
  case application:load(App) of
    ok -> case application:start(App) of
              ok  -> load_start_apps(Apps);
              Err -> io:format("error starting ~p: ~p~n", [App, Err]),
                     timer:sleep(10),
                     halt(1)
          end;
    Err -> io:format("error loading ~p: ~p~n", [App, Err]),
           Err,
           timer:sleep(10),
           halt(1)
  end.

running(Node, Module) ->
  Ref = erlang:monitor(process, {Module, Node}),
  R = receive
          {'DOWN', Ref, _, _, _} -> false
      after 1 ->
          true
      end,
  erlang:demonitor(Ref),
  R.

running(Pid) ->
  Ref = erlang:monitor(process, Pid),
  R = receive
          {'DOWN', Ref, _, _, _} -> false
      after 1 ->
          true
      end,
  erlang:demonitor(Ref),
  R.

running_nodes(Module) ->
  [Node || Node <- erlang:nodes([this, visible]), running(Node, Module)].

% Returns just the node name string that's before the '@' char.
% For example, returns "test" instead of "test@myhost.com".
%
node_name_short() ->
    [NodeName | _] = string:tokens(atom_to_list(node()), "@"),
    NodeName.

% Node is an atom like some_name@host.foo.bar.com

node_name_host(Node) ->
    [Name, Host | _] = string:tokens(atom_to_list(Node), "@"),
    {Name, Host}.

% Get an application environment variable, or a defualt value.
get_env_default(Var, Def) ->
    case application:get_env(Var) of
        {ok, Value} -> Value;
        undefined -> Def
    end.

make_pidfile() ->
    case application:get_env(pidfile) of
        {ok, PidFile} -> make_pidfile(PidFile);
        X -> X
    end.

make_pidfile(PidFile) ->
    Pid = os:getpid(),
    %% Pid is a string representation of the process id, so we append
    %% a newline to the end.
    ok = file:write_file(PidFile, list_to_binary(Pid ++ "\n")),
    ok.

ping_jointo() ->
    case application:get_env(jointo) of
        {ok, NodeName} -> ping_jointo(NodeName);
        X -> X
    end.

ping_jointo(NodeName) ->
    error_logger:info_msg("jointo: attempting to contact ~p~n", [NodeName]),
    case net_adm:ping(NodeName) of
        pong -> error_logger:info_msg("jointo: connected to ~p~n", [NodeName]);
        pang -> {error, io_lib:format("jointo: could not ping ~p~n", [NodeName])}
    end.

mapfilter(F, Ref, List) ->
    lists:foldr(fun (Item, Acc) ->
                    case F(Item) of
                    Ref -> Acc;
                    Value -> [Value|Acc]
                    end
                 end, [], List).

%% http://github.com/joearms/elib1/blob/master/lib/src/elib1_misc.erl#L1367

%%----------------------------------------------------------------------
%% @doc remove leading and trailing white space from a string.

-spec trim(string()) -> string().

trim(S) ->
    remove_leading_and_trailing_whitespace(S).

trim_test() ->
    "abc" = trim("    abc   ").

%%----------------------------------------------------------------------
%% @doc remove leading and trailing white space from a string.

-spec remove_leading_and_trailing_whitespace(string()) -> string().

remove_leading_and_trailing_whitespace(X) ->
    remove_leading_whitespace(remove_trailing_whitespace(X)).

remove_leading_and_trailing_whitespace_test() ->
    "abc" = remove_leading_and_trailing_whitespace("\r\t  \n \s  abc").

%%----------------------------------------------------------------------
%% @doc remove leading white space from a string.

-spec remove_leading_whitespace(string()) -> string().

remove_leading_whitespace([$\n|T]) -> remove_leading_whitespace(T);
remove_leading_whitespace([$\r|T]) -> remove_leading_whitespace(T);
remove_leading_whitespace([$\s|T]) -> remove_leading_whitespace(T);
remove_leading_whitespace([$\t|T]) -> remove_leading_whitespace(T);
remove_leading_whitespace(X) -> X.

%%----------------------------------------------------------------------
%% @doc remove trailing white space from a string.

-spec remove_trailing_whitespace(string()) -> string().

remove_trailing_whitespace(X) ->
    lists:reverse(remove_leading_whitespace(lists:reverse(X))).

%% Wait for a process.

wait_for_process(Pid, Timeout) ->
    Me = self(),
    Signal = make_ref(),
    spawn(fun() ->
                  process_flag(trap_exit, true),
                  link(Pid),
                  erlang:monitor(process, Me),
                  receive _ -> Me ! Signal end
          end),
    receive Signal -> ok
    after Timeout -> {error, timeout}
    end.

wait_for_process_test() ->
    %% Normal
    ok = wait_for_process(spawn(fun() -> ok end), 100),
    %% Timeout
    {error, timeout} = wait_for_process(spawn(fun() ->
                                                      timer:sleep(100), ok end),
                                        1),
    %% Process that exited before we went.
    Pid = spawn(fun() -> ok end),
    ok = wait_for_process(Pid, 100),
    ok = wait_for_process(Pid, 100).

spawn_link_safe(Fun) ->
    spawn_link_safe(node(), Fun).

spawn_link_safe(Node, Fun) ->
    Me = self(),
    Ref = make_ref(),
    spawn_link(
      Node,
      fun () ->
              process_flag(trap_exit, true),
              SubPid = Fun(),
              Me ! {Ref, pid, SubPid},
              receive
                  Msg -> Me ! {Ref, Msg}
              end
      end),
    receive
        {Ref, pid, SubPid} ->
            {ok, SubPid, Ref}
    end.


spawn_and_wait(Fun) ->
    spawn_and_wait(node(), Fun).

spawn_and_wait(Node, Fun) ->
    {ok, _Pid, Ref} = spawn_link_safe(Node, Fun),
    receive
        {Ref, Reason} ->
            Reason
    end.


poll_for_condition_rec(Condition, _Sleep, 0) ->
    case Condition() of
        false -> timeout;
        _ -> ok
    end;
poll_for_condition_rec(Condition, Sleep, Counter) ->
    case Condition() of
        false ->
            timer:sleep(Sleep),
            poll_for_condition_rec(Condition, Sleep, Counter-1);
        _ -> ok
    end.

poll_for_condition(Condition, Timeout, Sleep) ->
    Times = (Timeout + Sleep - 1) div Sleep,
    poll_for_condition_rec(Condition, Sleep, Times).

poll_for_condition_test() ->
    ok = poll_for_condition(fun () -> true end, 0, 10),
    timeout = poll_for_condition(fun () -> false end, 100, 10),
    Ref = make_ref(),
    self() ! {Ref, 0},
    Fun  = fun() ->
                   Counter = receive
                                 {Ref, C} -> R = C + 1,
                                             self() ! {Ref, R},
                                             R
                             after 0 ->
                                 erlang:error(should_not_happen)
                             end,
                   Counter > 5
           end,
    ok = poll_for_condition(Fun, 300, 10),
    receive
        {Ref, _} -> ok
    after 0 ->
            erlang:error(should_not_happen)
    end.


%% Remove matching messages from the inbox.
%% Returns a count of messages removed.

flush(Msg) -> flush(Msg, 0).

flush(Msg, N) ->
    receive
        Msg ->
            flush(Msg, N+1)
    after 0 ->
            N
    end.

flush_head(Head) ->
    flush_head(Head, 0).

flush_head(Head, N) ->
    receive
        Msg when element(1, Msg) == Head ->
            flush_head(Head, N+1)
    after 0 ->
            N
    end.


%% You know, like in Python
enumerate(List) ->
    enumerate(List, 1).

enumerate(List, Start) ->
    lists:zip(lists:seq(Start, length(List) + Start - 1), List).

%% Equivalent of sort|uniq -c
uniqc(List) ->
    uniqc(List, 1, []).

uniqc([], _, Acc) ->
    lists:reverse(Acc);
uniqc([H], Count, Acc) ->
    uniqc([], 0, [{H, Count}|Acc]);
uniqc([H,H|T], Count, Acc) ->
    uniqc([H|T], Count+1, Acc);
uniqc([H1,H2|T], Count, Acc) ->
    uniqc([H2|T], 1, [{H1, Count}|Acc]).

uniqc_test() ->
    [{a, 2}, {b, 5}] = uniqc([a, a, b, b, b, b, b]),
    [] = uniqc([]),
    [{c, 1}] = uniqc([c]).


keygroup(Index, List) ->
    keygroup(Index, List, []).

keygroup(_, [], Groups) ->
    lists:reverse(Groups);
keygroup(Index, [H|T], Groups) ->
    Key = element(Index, H),
    {G, Rest} = lists:splitwith(fun (Elem) -> element(Index, Elem) == Key end, T),
    keygroup(Index, Rest, [{Key, [H|G]}|Groups]).

keygroup_test() ->
    [{a, [{a, 1}, {a, 2}]},
     {b, [{b, 2}, {b, 3}]}] = keygroup(1, [{a, 1}, {a, 2}, {b, 2}, {b, 3}]),
    [] = keygroup(1, []).

keymin(I, [H|T]) ->
    keymin(I, T, H).

keymin(_, [], M) ->
    M;
keymin(I, [H|T], M) ->
    case element(I, H) < element(I, M) of
        true ->
            keymin(I, T, H);
        false ->
            keymin(I, T, M)
    end.

keymin_test() ->
    {c, 3} = keymin(2, [{a, 5}, {c, 3}, {d, 10}]).

keymax(I, [H|T]) ->
    keymax(I, T, H).

keymax(_, [], M) ->
    M;
keymax(I, [H|T], M) ->
    case element(I, H) > element(I, M) of
        true ->
            keymax(I, T, H);
        false ->
            keymax(I, T, M)
    end.

keymax_test() ->
    {20, g} = keymax(1, [{5, d}, {19, n}, {20, g}, {15, z}]).

%% Turn [[1, 2, 3], [4, 5, 6], [7, 8, 9]] info
%% [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
rotate(List) ->
    rotate(List, [], [], []).

rotate([], [], [], Acc) ->
    lists:reverse(Acc);
rotate([], Heads, Tails, Acc) ->
    rotate(lists:reverse(Tails), [], [], [lists:reverse(Heads)|Acc]);
rotate([[H|T]|Rest], Heads, Tails, Acc) ->
    rotate(Rest, [H|Heads], [T|Tails], Acc);
rotate(_, [], [], Acc) ->
    lists:reverse(Acc).

rotate_test() ->
    [[1, 4, 7], [2, 5, 8], [3, 6, 9]] =
        rotate([[1, 2, 3], [4, 5, 6], [7, 8, 9]]),
    [] = rotate([]).


pairs(L) ->
    pairs(L, []).

pairs([H1,H2|T], P) ->
    pairs([H2|T], [{H1, H2}|P]);
pairs(_, P) ->
    lists:reverse(P).

pairs_test() ->
    [{1,2}, {2,3}, {3,4}] = pairs([1,2,3,4]),
    [] = pairs([]),
    [{1,2}, {2,3}] = pairs([1,2,3]),
    [] = pairs([1]),
    [{1,2}] = pairs([1,2]).



rewrite_value(Old, New, Old) ->
    New;
rewrite_value(Old, New, L) when is_list(L) ->
    lists:map(fun (V) -> rewrite_value(Old, New, V) end, L);
rewrite_value(Old, New, T) when is_tuple(T) ->
    list_to_tuple(rewrite_value(Old, New, tuple_to_list(T)));
rewrite_value(_Old, _New, X) -> X.

rewrite_value_test() ->
    x = rewrite_value(a, b, x),
    b = rewrite_value(a, b, a),
    b = rewrite_value(a, b, b),

    [x, y, z] = rewrite_value(a, b, [x, y, z]),

    [x, b, c, b] = rewrite_value(a, b, [x, a, c, a]),

    {x, y} = rewrite_value(a, b, {x, y}),
    {x, b} = rewrite_value(a, b, {x, a}),

    X = rewrite_value(a, b,
                      [ {"a string", 1, x},
                        {"b string", 4, a, {blah, a, b}}]),
    X = [{"a string", 1, x},
         {"b string", 4, b, {blah, b, b}}].


ukeymergewith(Fun, N, L1, L2) ->
    ukeymergewith(Fun, N, L1, L2, []).

ukeymergewith(_, _, [], [], Out) ->
    lists:reverse(Out);
ukeymergewith(_, _, L1, [], Out) ->
    lists:reverse(Out, L1);
ukeymergewith(_, _, [], L2, Out) ->
    lists:reverse(Out, L2);
ukeymergewith(Fun, N, L1 = [T1|R1], L2 = [T2|R2], Out) ->
    K1 = element(N, T1),
    K2 = element(N, T2),
    case K1 of
        K2 ->
            ukeymergewith(Fun, N, R1, R2, [Fun(T1, T2) | Out]);
        K when K < K2 ->
            ukeymergewith(Fun, N, R1, L2, [T1|Out]);
        _ ->
            ukeymergewith(Fun, N, L1, R2, [T2|Out])
    end.

ukeymergewith_test() ->
    Fun = fun ({K, A}, {_, B}) ->
                  {K, A + B}
          end,
    [{a, 3}] = ukeymergewith(Fun, 1, [{a, 1}], [{a, 2}]),
    [{a, 3}, {b, 1}] = ukeymergewith(Fun, 1, [{a, 1}], [{a, 2}, {b, 1}]),
    [{a, 1}, {b, 3}] = ukeymergewith(Fun, 1, [{b, 1}], [{a, 1}, {b, 2}]).


start_singleton(Module, Name, Args, Opts) ->
    case Module:start_link({global, Name}, Name, Args, Opts) of
        {error, {already_started, Pid}} ->
            ?log_info("start_singleton(~p, ~p, ~p, ~p):"
                      " monitoring ~p from ~p",
                      [Module, Name, Args, Opts, Pid, node()]),
            {ok, spawn_link(fun () ->
                                    misc:wait_for_process(Pid, infinity),
                                    ?log_info("~p saw ~p exit (was pid ~p).",
                                              [self(), Name, Pid])
                            end)};
        {ok, Pid} = X ->
            ?log_info("start_singleton(~p, ~p, ~p, ~p):"
                      " started as ~p on ~p~n",
                      [Module, Name, Args, Opts, Pid, node()]),
            X;
        X -> X
    end.


%% Verify that a given global name belongs to the local pid, exiting
%% if it doesn't.
-spec verify_name(atom()) ->
                         ok | no_return().
verify_name(Name) ->
    case global:whereis_name(Name) of
        Pid when Pid == self() ->
            ok;
        Pid ->
            ?log_error("~p is registered to ~p. Killing ~p.",
                       [Name, Pid, self()]),
            exit(kill)
    end.


key_update_rec(Key, List, Fun, Acc) ->
    case List of
        [{Key, OldValue} | Rest] ->
            %% once we found our key, compute new value and don't recurse anymore
            %% just append rest of list to reversed accumulator
            lists:reverse([{Key, Fun(OldValue)} | Acc],
                          Rest);
        [] ->
            %% if we reach here, then we didn't found our tuple
            false;
        [X | XX] ->
            %% anything that's not our pair is just kept intact
            key_update_rec(Key, XX, Fun, [X | Acc])
    end.

%% replace value of given Key with result of applying Fun on it in
%% given proplist. Preserves order of keys. Assumes Key occurs only
%% once.
key_update(Key, PList, Fun) ->
    key_update_rec(Key, PList, Fun, []).

%% replace values from OldPList with values from NewPList
update_proplist(OldPList, NewPList) ->
    NewPList ++
        lists:filter(fun ({K, _}) ->
                             case lists:keyfind(K, 1, NewPList) of
                                 false -> true;
                                 _ -> false
                             end
                     end, OldPList).

update_proplist_test() ->
    [{a, 1}, {b, 2}, {c,3}] =:= update_proplist([{a,2}, {c,3}],
                                                [{a,1}, {b,2}]).

%% get proplist value or fail
expect_prop_value(K, List) ->
    Ref = make_ref(),
    try
        case proplists:get_value(K, List, Ref) of
            RV when RV =/= Ref -> RV
        end
    catch
        error:X -> erlang:error(X, [K, List])
    end.

%% true iff given path is absolute
is_absolute_path(Path) ->
    Normalized = filename:join([Path]),
    filename:absname(Normalized) =:= Normalized.

%% Retry a function that returns either N times
retry(F) -> retry(F, 3).
retry(F, N) -> retry(F, N, initial_error).

%% Implementation below.
%% These wouldn't be exported if it werent for export_all
retry(_F, 0, Error) -> exit(Error);
retry(F, N, _Error) ->
    case catch(F()) of
        {'EXIT',X} -> retry(F, N - 1, X);
        Success -> Success
    end.

retry_test() ->
    %% Positive cases.
    ok = retry(fun () -> ok end),
    {ok, 1827841} = retry(fun() -> {ok, 1827841} end),

    %% Error cases.
    case (catch retry(fun () -> exit(foo) end)) of
        {'EXIT', foo} ->
            ok
    end,

    %% Verify a retry with a function that will succeed the second
    %% time.
    self() ! {testval, a},
    self() ! {testval, b},
    self() ! {testval, c},
    self() ! {testval, d},
    b = retry(fun () -> b = receive {testval, X} -> X end end).


%% @doc Truncate a timestamp to the nearest multiple of N seconds.
trunc_ts(TS, N) ->
    TS - (TS rem (N*1000)).

%% alternative of file:read_file/1 that reads file until EOF is
%% reached instead of relying on file length. See
%% http://groups.google.com/group/erlang-programming/browse_thread/thread/fd1ec67ff690d8eb
%% for more information. This piece of code was borrowed from above mentioned URL.
raw_read_file(Path) ->
    case file:open(Path, [read, binary]) of
        {ok, File} -> raw_read_loop(File, []);
        Crap -> Crap
    end.
raw_read_loop(File, Acc) ->
    case file:read(File, 10) of
        {ok, Bytes} ->
            raw_read_loop(File, [Acc | Bytes]);
        eof ->
            file:close(File),
            {ok, iolist_to_binary(Acc)};
        {error, Reason} ->
            file:close(File),
            erlang:error(Reason)
    end.

multicall_result_to_plist_rec([], _ResL, _BadNodes, Acc) ->
    Acc;
multicall_result_to_plist_rec([N | Nodes], ResL, BadNodes, Acc) ->
    case lists:member(N, BadNodes) of
        true -> multicall_result_to_plist_rec(Nodes, ResL, BadNodes, Acc);
        _ ->
            NewAcc = [{N, hd(ResL)} | Acc],
            multicall_result_to_plist_rec(Nodes, tl(ResL), BadNodes, NewAcc)
    end.

multicall_result_to_plist(Nodes, {ResL, BadNodes}) ->
    multicall_result_to_plist_rec(Nodes, ResL, BadNodes, []).

realpath(Path, BaseDir) ->
    case erlang:system_info(system_architecture) of
        "win32" ->
            filename:absname(Path, BaseDir);
        _ -> case realpath_full(Path, BaseDir, 32) of
                 {ok, X, _} -> {ok, X};
                 X -> X
             end
    end.

realpath_full(Path, BaseDir, SymlinksLimit) ->
    NormalizedPath = filename:join([Path]),
    Tokens = string:tokens(NormalizedPath, "/"),
    case Path of
        [$/ | _] ->
            realpath_rec_check("/", Tokens, SymlinksLimit);
        _ ->
            realpath_rec_info(#file_info{type = other}, BaseDir, Tokens, SymlinksLimit)
    end.

realpath_rec_check(Current, Tokens, SymlinksLimit) ->
    case file:read_link_info(Current) of
        {ok, Info} ->
            realpath_rec_info(Info, Current, Tokens, SymlinksLimit);
        Crap -> {error, read_file_info, Current, Crap}
    end.

realpath_rec_info(Info, Current, Tokens, SymlinksLimit) when Info#file_info.type =:= symlink ->
    case file:read_link(Current) of
        {error, _} = Crap -> {error, read_link, Current, Crap};
        {ok, LinkDestination} ->
            case SymlinksLimit of
                0 -> {error, symlinks_limit_reached};
                _ ->
                    case realpath_full(LinkDestination, filename:dirname(Current), SymlinksLimit-1) of
                        {ok, Expanded, NewSymlinksLimit} ->
                            realpath_rec_check(Expanded, Tokens, NewSymlinksLimit);
                        Error -> Error
                    end
            end
    end;
realpath_rec_info(_, Current, [], SymlinksLimit) ->
    {ok, Current, SymlinksLimit};
realpath_rec_info(Info, Current, ["." | Tokens], SymlinksLimit) ->
    realpath_rec_info(Info, Current, Tokens, SymlinksLimit);
realpath_rec_info(_Info, Current, [".." | Tokens], SymlinksLimit) ->
    realpath_rec_check(filename:dirname(Current), Tokens, SymlinksLimit);
realpath_rec_info(_Info, Current, [FirstToken | Tokens], SymlinksLimit) ->
    NewCurrent = filename:absname(FirstToken, Current),
    realpath_rec_check(NewCurrent, Tokens, SymlinksLimit).

zipwith4(_Combine, [], [], [], []) -> [];
zipwith4(Combine, List1, List2, List3, List4) ->
    [Combine(hd(List1), hd(List2), hd(List3), hd(List4))
     | zipwith4(Combine, tl(List1), tl(List2), tl(List3), tl(List4))].

zipwith4_test() ->
    F = fun (A1, A2, A3, A4) -> {A1, A2, A3, A4} end,

    Actual1 = zipwith4(F, [1, 1, 1], [2,2,2], [3,3,3], [4,4,4]),
    Actual1 = lists:duplicate(3, {1,2,3,4}),

    case (catch {ok, zipwith4(F, [1,1,1], [2,2,2], [3,3,3], [4,4,4,4])}) of
        {ok, _} ->
            exit(bad_error_handling);
        _ -> ok
    end.
